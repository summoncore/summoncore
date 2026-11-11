-- Detector: watches the player's Ritual of Summoning casts and snapshots roster and channel state.
-- Only the caster's client sees the cast; everyone else is credited from the snapshot. Every other client in the group watches
-- too (the witness, below), so Zennit's client can file a summons whose caster has no addon.
local ADDON, ST = ...
local Detector = {}
ST.Detector = Detector

local PENDING_TTL = 30
local TICK = 0.5
local MAX_CANDIDATES = 12 -- longest list the assistants prompt offers
local OWN_GRACE = 5 -- seconds after our own ritual begins or is committed in which the witness stays quiet, whatever the channel shows
local pending
local own -- GetTime() when this client's player last began or committed a ritual of their own; nil once their channel stops
Detector.writ = false -- a writ armed for the next ritual on Zennit (/sc writ; Week.RULES.writs a week)

local function dbg(msg)
    if ST.db and ST.db.settings.debug then ST.print("|cff888888[detect]|r " .. msg) end
end

local function isRitualID(spellID)
    return spellID ~= nil and not ST.isSecret(spellID) and spellID == ST.RITUAL_ID
end

-- Plain string name, or nil if the value is missing or secret.
local function cleanName(v)
    return ST.baseName(v)
end

-- Unit tokens for everyone else in the group: party1-4, or the whole raid (helpers may be in any subgroup).
local function groupUnits()
    local out = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then out[#out + 1] = unit end
        end
    else
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then out[#out + 1] = unit end
        end
    end
    return out
end

local function partyMembers()
    local out = {}
    for _, unit in ipairs(groupUnits()) do
        local n = cleanName(UnitName(unit))
        if n then out[#out + 1] = n end
    end
    return out
end
Detector.PartyMembers = partyMembers

-- Whether this unit is channeling the ritual (the caster, or a helper clicking the portal).
local function channelingRitual(unit)
    local ok, cname, _, _, _, _, _, _, spellID = pcall(UnitChannelInfo, unit)
    if not ok then return false end
    if isRitualID(spellID) then return true end
    local rname = ST.SpellName(ST.RITUAL_ID)
    return rname ~= nil and type(cname) == "string" and not ST.isSecret(cname) and cname == rname
end

-- Names of group members currently channeling the ritual.
local function channelers()
    local out = {}
    for _, unit in ipairs(groupUnits()) do
        if channelingRitual(unit) then
            local n = cleanName(UnitName(unit))
            if n then out[#out + 1] = n end
        end
    end
    return out
end

-- The names offered in the assistants prompt: not the target or the caster, detected helpers first, at most `max`
-- (a raid can be 40 people, far too many to tick through).
function Detector.PickCandidates(members, helpers, target, me, max)
    local out, seen = {}, {}
    local function add(n)
        if n ~= target and n ~= me and not seen[n] and #out < max then
            seen[n] = true
            out[#out + 1] = n
        end
    end
    local present = {}
    for _, n in ipairs(members) do present[n] = true end
    for _, n in ipairs(helpers) do if present[n] then add(n) end end
    for _, n in ipairs(members) do add(n) end
    return out
end

local function snapshotHelpers()
    if not pending then return end
    for _, n in ipairs(channelers()) do
        if not pending.helpers[n] then
            pending.helpers[n] = true
            dbg("helper seen channeling: " .. n)
        end
    end
end

-- Whether the group member called `name` shows as away from the keyboard (design/lenses.md, Freedom).
function Detector.IsAway(name)
    for _, unit in ipairs(groupUnits()) do
        if cleanName(UnitName(unit)) == name then
            local ok, afk = pcall(UnitIsAFK, unit)
            return ok and afk and not ST.isSecret(afk) and true or false
        end
    end
    return false
end

local function clearPending()
    if pending and pending.ticker then pending.ticker:Cancel() end
    pending = nil
end

local function startPending(target)
    clearPending()
    own = GetTime()
    local mapID = C_Map.GetBestMapForUnit("player")
    pending = {
        target = cleanName(target) or cleanName(UnitName("target")),
        mapID = mapID, subzone = GetSubZoneText(), started = time(), helpers = {},
    }
    local ticks = 0
    pending.ticker = C_Timer.NewTicker(TICK, function()
        ticks = ticks + 1
        snapshotHelpers()
        -- a ritual still channelling is still waiting for its clickers: its target and the helpers seen so far are kept
        if ticks * TICK > PENDING_TTL and not channelingRitual("player") then clearPending() end
    end)
    ST.Trace(string.format("ritual sent on %s%s", tostring(pending.target), Detector.writ and " (a writ is armed)" or ""))
    ST.Clips.Play("ritual") -- a recorded line as the ritual begins
    -- a ritual on Zennit: tell the caster whether it will count, where the week stands, and what helpers add
    local brief = pending.target and ST.Week.Briefing(pending.target, mapID, pending.subzone, Detector.writ, Detector.IsAway(pending.target))
    if brief then ST.print(brief) end
    dbg(string.format("pending: target=%s map=%s subzone=%s", tostring(pending.target),
        tostring(mapID), tostring(pending.subzone)))
end

local function report(ev, badges)
    ST.Trace(string.format("summons logged: %s in %s%s", tostring(ev.target), ev.subzone ~= "" and ev.subzone or "?", ev.writ and ", with a writ" or ""))
    if ST.Hub then ST.Hub.Refresh() end
    local zenit = ST.Gag.IsZennit()
    ST.print(ST.Voice.Say("logged", { "Summon logged: %s in %s%s%s", "The Index has noted a summons of %s to %s%s%s.",
        "Filed: %s, in %s%s%s." }, ev.target, ev.subzone ~= "" and ev.subzone or "?",
        zenit and "" or string.format(" (+%d, %s)", ev.points, ev.kind), ev.confirmed and "" or " [unconfirmed]"))
    -- a summon of Zennit moves the week: say where it stands now
    local week = not ev.fake and ST.Week.IsZennit(ev.target) and ST.Week.StatusLine(ST.Week.Start(ev.time))
    if week then ST.print(week) end
    if ev.writ then
        ST.print(string.format("The Index files the writ on this summons: %d left this week. If he declines it in the game, it costs him %d point%s.",
            ST.Week.WritsLeft(ST.Week.Start(ev.time)), ev.points, ev.points == 1 and "" or "s"))
    end
    if zenit then return end -- points and badges are hidden on Zennit's client
    ST.Achieve.Say(badges)
end

-- Saves an event, asking the caster about assistants when the roster is unclear.
-- info: target, mapID, subzone, helpers (list of detected helper names)
function Detector.Finish(info)
    local me = ST.Store.me()
    local target = info.target or "Unknown"
    local candidates = Detector.PickCandidates(partyMembers(), info.helpers, target, me, MAX_CANDIDATES)
    -- the record keeps the time of the ritual, not of the prompt's answer, so it lands in the week it was cast in
    local at = info.time or time()
    local function save(assistants, confirmed)
        local _, ev, badges = ST.Store.Add({
            caster = me, target = target, assistants = assistants, time = at,
            mapID = info.mapID, subzone = info.subzone or "", confirmed = confirmed, writ = info.writ or nil,
        })
        report(ev, badges)
    end
    -- neither the one summoned nor the caster can be their own assistant, however they showed up in the snapshot
    local helpers = {}
    for _, n in ipairs(info.helpers) do
        if n ~= target and n ~= me then helpers[#helpers + 1] = n end
    end
    if #candidates == 0 then
        save({}, true) -- nobody could have helped
    elseif #helpers == 2 and info.target then
        save(helpers, true)
    else
        dbg(string.format("%d helpers detected, asking caster", #helpers))
        ST.Prompt.Ask(target, candidates, helpers, save)
    end
end

local function commit()
    if not pending then startPending() end
    snapshotHelpers()
    local info = {
        target = pending.target, mapID = pending.mapID, subzone = pending.subzone,
        helpers = {}, time = time(),
    }
    for n in pairs(pending.helpers) do info.helpers[#info.helpers + 1] = n end
    table.sort(info.helpers)
    clearPending()
    own = GetTime()
    -- a writ armed with /sc writ goes on a summons of Zennit, if one is still to be had; a ritual on anyone else leaves it armed
    if Detector.writ and info.target and ST.Week.IsZennit(info.target) then
        info.writ = ST.Week.WritsLeft(ST.Week.Start()) > 0 or nil
        Detector.writ = false
    end
    Detector.Finish(info)
end

Detector.lastCommit = 0 -- GetTime() of the last commit (on Detector so the self-test can put it back)
local frame = CreateFrame("Frame")
for _, ev in ipairs({
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED",
}) do
    pcall(frame.RegisterUnitEvent, frame, ev, "player")
end

-- The handler is kept on Detector too, so the self-test can play a ritual's events through it.
Detector.OnCast = ST.Safe("the ritual detector", function(_, event, _, a2, a3, a4)
    -- SENT args: unit, target, castGUID, spellID. Others: unit, castGUID, spellID.
    local spellID = (event == "UNIT_SPELLCAST_SENT") and a4 or a3
    if not isRitualID(spellID) then return end
    dbg(event)
    if event == "UNIT_SPELLCAST_SENT" then
        startPending(a2)
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        if not pending then startPending() end
        snapshotHelpers()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Guard against a second SUCCEEDED for the same cast.
        if GetTime() - Detector.lastCommit < 5 then return end
        Detector.lastCommit = GetTime()
        commit()
    else
        clearPending() -- interrupted or failed
        own = nil
    end
end)
frame:SetScript("OnEvent", Detector.OnCast)

-- Whether this client's player is casting a ritual of their own (or has just committed one): while they are, every channel the
-- group shows is their ritual's, and the witness below keeps out of it.
function Detector.OwnRitual()
    if pending then return true end
    if not own then return false end
    return GetTime() - own < OWN_GRACE or channelingRitual("player")
end

----------------------------------------------------------------------
-- The witness (design/lenses.md, Accessibility, G)
----------------------------------------------------------------------
-- A client in the group that is not casting watches who channels a ritual: the first to start is the caster (the warlock starts it,
-- the helpers join by clicking the portal), their target is the one being summoned, and anyone who starts after is a helper. When
-- the caster stops, a note goes to the group, where only Zennit's client keeps it: if no record comes from the caster (no addon),
-- his client files the summons with what the notes say. When the caster has the addon the note is simply not needed.
local WATCH_TTL = 40
local watch

local function sendWatch()
    local w = watch
    watch = nil
    if not w then return end
    if w.ticker then w.ticker:Cancel() end
    if pending or not w.caster then return end -- we cast it ourselves: our own record says it all
    if w.target and not ST.Week.IsZennit(w.target) then return end
    local helpers = {}
    for n in pairs(w.helpers) do if n ~= w.caster then helpers[#helpers + 1] = n end end
    table.sort(helpers)
    ST.Sync.SendWitness({ caster = w.caster, target = w.target, helpers = helpers, mapID = w.mapID, subzone = w.subzone,
        time = w.time, helping = w.helping })
    ST.Trace(string.format("witnessed a ritual: %s on %s, helpers %s%s", w.caster, tostring(w.target), table.concat(helpers, ","),
        w.helping and " (this client helped)" or ""))
end

-- Starts watching when `unit` begins to channel. Anyone already channeling started first, so that is the caster; else `unit` is.
local function startWatch(unit)
    local w = { helpers = {}, time = time(), mapID = C_Map.GetBestMapForUnit("player"), subzone = GetSubZoneText() }
    local casterUnit = unit ~= "player" and unit or nil
    for _, u in ipairs(groupUnits()) do
        if u ~= unit and channelingRitual(u) then casterUnit = u break end
    end
    if casterUnit then
        w.caster = cleanName(UnitName(casterUnit))
        local ok, t = pcall(UnitName, casterUnit .. "target")
        w.target = ok and cleanName(t) or nil
        if unit ~= "player" and unit ~= casterUnit then
            local n = cleanName(UnitName(unit))
            if n then w.helpers[n] = true end
        end
    end
    w.ticker = C_Timer.NewTimer(WATCH_TTL, sendWatch)
    watch = w
end

local watcher = CreateFrame("Frame")
pcall(watcher.RegisterEvent, watcher, "UNIT_SPELLCAST_CHANNEL_START")
pcall(watcher.RegisterEvent, watcher, "UNIT_SPELLCAST_CHANNEL_STOP")
Detector.OnWitness = ST.Safe("the ritual witness", function(_, event, unit)
    if type(unit) ~= "string" then return end
    local isPlayer = unit == "player"
    -- our own ritual's channel has ended; or we began to channel a while after our own ritual with none pending, which can only
    -- be a click on someone else's portal: either way the witness may watch again
    if isPlayer and own and not pending and (event == "UNIT_SPELLCAST_CHANNEL_STOP" or GetTime() - own >= OWN_GRACE) then
        own = nil
    end
    -- our own ritual is the detector's above: the caster's client must never name one of its helpers as the caster
    if Detector.OwnRitual() then return end
    if not (isPlayer or unit:match("^party%d$") or unit:match("^raid%d+$")) then return end
    local name = cleanName(UnitName(unit))
    if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if watch and name and name == watch.caster then sendWatch() end
        return
    end
    if not channelingRitual(unit) then return end
    if not watch then
        -- we were channelling the ritual before anyone we watched: it is our own (say, after a /reload mid-ritual), not theirs
        if not isPlayer and channelingRitual("player") then return end
        startWatch(unit)
        if not isPlayer then return end
    end
    if isPlayer then
        watch.helping = true
        local me = cleanName(UnitName("player"))
        if me then watch.helpers[me] = true end
    elseif name and name ~= watch.caster then
        if not watch.caster then watch.caster = name else watch.helpers[name] = true end
    end
end)
watcher:SetScript("OnEvent", Detector.OnWitness)
