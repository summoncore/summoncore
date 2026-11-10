-- Reset: wipes the summons, the badges and, with them, the story (the season is worked out from the log).
-- It asks first. The admin can also ask everyone else to reset (/sc reset all): each user is shown a prompt and
-- nothing is changed on their client until they agree. A reset leaves a mark (db.resetAt); anything older than it
-- is refused by sync, so another client still holding the old log cannot put it back. A reset everyone was asked to make
-- is also kept as db.resetAll, which every hello passes on (Sync), so a client that missed the request is asked later;
-- a friend's own reset stays on their client.
local ADDON, ST = ...
local Reset = {}
ST.Reset = Reset

StaticPopupDialogs["SUMMONCORE_RESET"] = {
    text = "%s",
    button1 = "Reset",
    button2 = "Cancel",
    OnAccept = function(_, data) if data then data() end end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Wipes this client now. `stamp` is the moment of the reset (default: now); returns how many summons went.
function Reset.Apply(stamp)
    stamp = stamp or time()
    local removed = 0
    for id, ev in pairs(ST.db.events) do
        if ev.time <= stamp then
            ST.db.events[id] = nil
            removed = removed + 1
        end
    end
    ST.db.resetAt = stamp
    ST.db.badges = {}
    -- badges go too (Scoring.Badges): this character starts again with none, and any other is worked out afresh at its login
    ST.db.badgesBy = { [ST.Sync.myName()] = {} }
    -- A tombstone of a summons the reset removes is redundant (the mark refuses it), but one of a summons made after the mark is
    -- not: this reset may be accepted long after its stamp, and a peer may still hold that summons. The id carries the summons'
    -- time ("<author>-<time>[-n]").
    for id in pairs(ST.db.deleted or {}) do
        local t = tonumber(id:match("^[^%-]+%-(%d+)"))
        if not t or t <= stamp then ST.db.deleted[id] = nil end
    end
    ST.db.cards = nil   -- a card's punches are counted from the summons, so with them gone every card would be full again
    if ST.db.settings then ST.db.settings.weekSeen, ST.db.settings.weekAnnounced = nil, nil end
    if ST.Hub then ST.Hub.Refresh() end
    return removed
end

-- Asks this user, then resets; with everyone = true (admin only) also asks everyone else to do the same.
function Reset.Ask(everyone)
    if everyone and not ST.IsAdmin() then return ST.print("that is an admin tool") end
    local text = everyone and
        "Reset all summons, badges and the story on THIS client, and ask everyone else running Summon Core to do the same?" or
        "Reset all summons, badges and the story on this client? This cannot be undone."
    StaticPopup_Show("SUMMONCORE_RESET", text, nil, function()
        local stamp = time()
        local removed = Reset.Apply(stamp)
        ST.print(string.format("reset: %d summon%s removed, badges and story cleared.", removed, removed == 1 and "" or "s"))
        if everyone then
            ST.db.resetAll = stamp
            ST.Sync.SendReset(stamp)
            ST.print("asked everyone else to reset too.")
        end
    end)
end

-- Does this client hold anything a reset as of `stamp` would remove?
function Reset.Holds(stamp)
    for _, ev in pairs(ST.db.events) do
        if ev.time <= stamp then return true end
    end
    return false
end

-- Makes the reset `sender` asked for. Its mark is kept as one everyone was asked to make, so this client passes it on.
function Reset.Accept(sender, stamp)
    local removed = Reset.Apply(stamp)
    ST.db.resetAll = math.max(ST.db.resetAll or 0, stamp)
    ST.print(string.format("reset by request of %s: %d summon%s removed.", sender, removed, removed == 1 and "" or "s"))
end

-- Another user (the admin) asks us to reset; they were not verified, so we ask before doing anything. A client holding
-- nothing from before the reset (a newcomer, say) has nothing to lose: it takes the mark without asking.
local asked = {}
ST.Sync.onReset = function(sender, stamp)
    if not Reset.Holds(stamp) then
        ST.db.resetAt = math.max(ST.db.resetAt or 0, stamp)
        ST.db.resetAll = math.max(ST.db.resetAll or 0, stamp)
        return
    end
    if asked[stamp] then return end
    asked[stamp] = true
    StaticPopup_Show("SUMMONCORE_RESET",
        sender .. " asks everyone to reset all summons, badges and the story. Do it on this client?", nil, function()
            Reset.Accept(sender, stamp)
        end)
end

----------------------------------------------------------------------
-- Seasons: the admin starts and stops them (Week.Marks); unlike a reset, nobody else is asked, and no summons are removed
----------------------------------------------------------------------
StaticPopupDialogs["SUMMONCORE_SEASON"] = {
    text = "%s",
    button1 = "Yes",
    button2 = "Cancel",
    OnAccept = function(_, data) if data then data() end end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- What the Index says when a season starts or stops (here, or on the admin's word from another client).
function Reset.SeasonNews(kind, sender)
    local by = sender and (" (Heard from " .. sender .. ".)") or ""
    if kind == "start" then
        ST.print("|cffffd100A new season has begun.|r The race starts again from this week, 0 to 0. First to " ..
            ST.Week.WINS .. " weekly wins takes the finale." .. by)
    else
        ST.print("|cffffd100The season has been stopped.|r The race counts nothing until the admin starts a new one. " ..
            "Summons are still filed, under 'between seasons'." .. by)
    end
    if ST.Hub then ST.Hub.Refresh() end
end

-- The admin's client: asks, then starts ("start") or stops ("stop") the season and tells everyone.
function Reset.Season(kind)
    if not ST.IsAdmin() then return ST.print("that is an admin tool") end
    local running = ST.Week.Running(ST.Week.Start())
    if kind == "stop" and not running then return ST.print("no season is running, so there is nothing to stop.") end
    local s = ST.Week.Season()
    local text = kind == "stop" and string.format("Stop the season now? It ends at Zennit %d, the group %d, with no finale, " ..
            "and this week will not count. Everyone's Summon Core hears of it.", s.zennit, s.group)
        or (running and string.format("Start a new season? The one in progress ends at Zennit %d, the group %d, with no " ..
            "finale, and the new one starts 0 to 0 with this week. Everyone's Summon Core hears of it.", s.zennit, s.group)
        or "Start a new season? It starts 0 to 0 with this week. Everyone's Summon Core hears of it.")
    StaticPopup_Show("SUMMONCORE_SEASON", text, nil, function()
        local m, why = ST.Sync.MarkSeason(kind)
        if not m then return ST.print(why) end
        Reset.SeasonNews(kind)
    end)
end

ST.Sync.onSeason = function(kind, t, sender)
    -- only news when it is the newest word: an old mark caught up on later changes the past quietly
    local last = ST.Week.LastMark()
    if last and last.time == t and last.kind == kind then
        if ST.Week.Start(t) == ST.Week.Start() then Reset.SeasonNews(kind, sender) else ST.print(kind == "start" and
            "While you were away, the admin started a new season." or "While you were away, the admin stopped the season.") end
    end
    if ST.Hub then ST.Hub.Refresh() end
end
