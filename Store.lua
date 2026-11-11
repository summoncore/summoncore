-- Store: the only module that touches SummonTrackerDB. The event log is the source of truth;
-- tallies are always derived from it.
local ADDON, ST = ...
local Store = {}
ST.Store = Store

function Store.me()
    return UnitName("player")
end

local function newID(caster, t)
    local id = caster .. "-" .. t
    local n = 1
    while ST.db.events[id] do
        n = n + 1
        id = caster .. "-" .. t .. "-" .. n
    end
    return id
end

-- ev: caster, target, assistants (list), mapID, subzone, time, confirmed.
-- Returns the id, the event, and a list of the achievements earned by this save (their names).
-- localOnly keeps the event off the network (used for test events).
function Store.Add(ev, localOnly)
    -- at most two assistants, each named once, and neither the caster nor the target: the same rule Sync.Decode holds every
    -- record to, so nothing saved here can be a record that every friend refuses
    local assistants, seen = {}, {}
    for _, a in ipairs(ev.assistants or {}) do
        if a ~= ev.caster and a ~= ev.target and not seen[a] and #assistants < 2 then
            seen[a] = true
            assistants[#assistants + 1] = a
        end
    end
    ev.assistants = assistants
    ev.time = ev.time or time()
    ev.wrote = ev.wrote or time()
    -- Never file a summons at or before the last reset: every peer holding the same mark refuses it (Sync.Merge), so a clock
    -- behind the admin's would keep it on this client alone. It is filed just after the mark instead.
    local cut = ST.db.resetAt
    if cut and ev.time <= cut then ev.time, ev.wrote = cut + 1, math.max(ev.wrote, cut + 1) end
    if ev.subzone then ev.subzone = ST.Sync.Clip(ev.subzone, ST.Sync.MAX_SUBZONE) end -- keep what friends will receive
    ev.points, ev.kind = ST.Scoring.Score(ev.mapID, ev.subzone)
    local id = newID(ev.by or ev.caster, ev.time) -- a record Zennit's client filed for someone else starts with his name
    ST.db.events[id] = ev
    if Store.onAdd and not localOnly then Store.onAdd(id, ev) end
    if ST.Week and not localOnly then ST.Week.Warn(ev) end
    return id, ev, ST.Achieve.Evaluate()
end


-- Zennit's answer to a summon of him (set by his client, carried by sync): { result, zroll, sroll, time }.
-- A summon still counts unless it was refused or he won the dice. A demand for silver does NOT stop it counting: the silver goes
-- on the caster's tab (design/lenses.md, Meaningful Choices), so it cannot be used to reject a summons.
-- "excused" is a refusal of a destination on his secret list: no points for the summoner and no penalty for him.
-- "declined" is what the game itself saw: he declined the summons in the game's own prompt. The summons did not happen, so no
-- points for the summoner and none for him, unless the group played a writ on it (Week.Writ), which makes it a "refused".
-- "away" is filed by his own client when he was already away from his keyboard as the summons came (design/lenses.md, Freedom):
-- it did not happen, it is free, and it does not use his free decline.
Store.RESULTS = { accepted = true, refused = true, excused = true, declined = true, owed = true, paid = true, won = true, lost = true,
    away = true }
local NO_POINTS = { refused = true, excused = true, declined = true, won = true, away = true }

function Store.Lands(ev)
    return not (ev.response and NO_POINTS[ev.response.result])
end

-- Points toward Zennit's goal (a week off from being summoned), from the summon's worth P (draft rules):
--   he wins the dice: +P        a plain refusal: -P
--   a summon that lands at a place on his list: +P bonus (response.listed, set by his client)
function Store.Goal(ev)
    local r, p = ev.response, ev.points or 0
    if not r then return 0 end
    if r.result == "won" then return p end
    if r.result == "refused" then return -p end
    if r.listed and Store.Lands(ev) then return p end
    return 0
end

function Store.SetResponse(id, resp)
    local ev = ST.db.events[id]
    if not ev then return false end
    ev.response = resp
    return true
end

function Store.Has(id) return ST.db.events[id] ~= nil end
function Store.Get(id) return ST.db.events[id] end

-- Writes an event received from sync, replacing any copy with the same id.
function Store.Put(id, ev)
    ST.db.events[id] = ev
end

function Store.Count()
    local n = 0
    for _, ev in pairs(ST.db.events) do
        if not ev.fake then n = n + 1 end
    end
    return n
end

function Store.Latest()
    local latest = 0
    for _, ev in pairs(ST.db.events) do
        if not ev.fake and ev.time > latest then latest = ev.time end
    end
    return latest
end

-- Time of the newest answer from Zennit on any summon (0 if none); HELLO carries it so a changed answer resyncs.
function Store.LatestResponse()
    local latest = 0
    for _, ev in pairs(ST.db.events) do
        local r = ev.response
        if not ev.fake and r and r.time > latest then latest = r.time end
    end
    return latest
end

-- Events with time > t, oldest first.
function Store.Since(t)
    local list = {}
    for id, ev in pairs(ST.db.events) do
        if ev.time > t and not ev.fake then list[#list + 1] = { id = id, ev = ev } end
    end
    table.sort(list, function(a, b)
        if a.ev.time ~= b.ev.time then return a.ev.time < b.ev.time end
        return a.id < b.id
    end)
    return list
end

-- Events sorted newest first.
function Store.Recent(limit)
    local list = {}
    for id, ev in pairs(ST.db.events) do list[#list + 1] = { id = id, ev = ev } end
    table.sort(list, function(a, b) return a.ev.time > b.ev.time end)
    if limit and #list > limit then
        for i = #list, limit + 1, -1 do list[i] = nil end
    end
    return list
end

-- Who wrote a summons: the name its id starts with ("<author>-<time>[-n]"; a name never holds a '-').
function Store.Author(id)
    return type(id) == "string" and id:match("^([^%-]+)%-") or nil
end

-- Whether this client may delete the summons `id`: one its own character wrote, or, on Zennit's account, one any of his
-- characters wrote (his client files summons of him on whichever character he is playing, and must be able to take them
-- back, and to say so again, from another).
function Store.Mine(id)
    local author, me = Store.Author(id), ST.Sync.myName()
    if not author or not me then return false end
    if author == me then return true end
    return ST.Week ~= nil and ST.Week.IsZennit(me) and ST.Week.IsZennit(author) and ST.IsZennitAccount()
end

-- Removes a summons this client wrote (Store.Mine), leaving a tombstone so sync cannot bring it back.
function Store.Remove(id)
    local ev = ST.db.events[id]
    if not ev or not Store.Mine(id) then return false end
    ST.db.events[id] = nil
    ST.db.deleted = ST.db.deleted or {}
    ST.db.deleted[id] = time()
    if Store.onRemove then Store.onRemove(id) end
    return true
end

-- Removes the newest summons this client wrote (its id starts with our name: nobody can delete someone else's, Sync's T),
-- through Store.Remove, so it leaves the same tombstone; test summons are simply dropped. That is usually the newest summons
-- this character cast, and on Zennit's client it can also be one his client filed for a caster without the addon.
function Store.RemoveLast()
    for _, r in ipairs(Store.Recent()) do
        if Store.Mine(r.id) then
            if r.ev.fake then
                ST.db.events[r.id] = nil
            elseif not Store.Remove(r.id) then
                return nil
            end
            return r
        end
    end
end

function Store.IsDeleted(id)
    return ST.db.deleted ~= nil and ST.db.deleted[id] ~= nil
end

-- Our own tombstones (Store.Mine: on Zennit's account, those of any of his characters), newest first, at most `limit`.
function Store.OwnTombstones(limit)
    local list = {}
    for id, t in pairs(ST.db.deleted or {}) do
        if Store.Mine(id) then list[#list + 1] = { id = id, t = t } end
    end
    table.sort(list, function(a, b) return a.t > b.t end)
    for i = #list, (limit or #list) + 1, -1 do list[i] = nil end
    return list
end

-- Per-name tallies derived from the log. points count for the caster only.
function Store.Tallies()
    local t = {}
    local function row(name)
        t[name] = t[name] or { cast = 0, received = 0, assisted = 0, points = 0 }
        return t[name]
    end
    for _, ev in pairs(ST.db.events) do
        if not ev.fake then -- test summons are not counted
            -- only a summons that lands is counted (README: points, tallies and badges only count summons that land); his
            -- points still count the dice he won and the refusals that cost him, as Store.Goal says
            local c, tr = row(ev.caster), row(ev.target)
            tr.points = tr.points + Store.Goal(ev)
            if Store.Lands(ev) then
                c.cast = c.cast + 1
                c.points = c.points + (ev.points or 0)
                tr.received = tr.received + 1
                for _, a in ipairs(ev.assistants or {}) do row(a).assisted = row(a).assisted + 1 end
            end
        end
    end
    return t
end

-- The Party tab's rows: every name in the tallies, ranked by summons of Zennit this season (from `casters`, keyed by plain
-- name, which counts every one of them, as the titles do), then by points, then by name. Each row is { name, tally, ofZennit }.
function Store.Ranked(tallies, casters)
    local rows = {}
    for name, t in pairs(tallies) do
        rows[#rows + 1] = { name, t, casters[ST.baseName(name) or name] or 0 }
    end
    table.sort(rows, function(a, b)
        if a[3] ~= b[3] then return a[3] > b[3] end
        if a[2].points ~= b[2].points then return a[2].points > b[2].points end
        return a[1] < b[1]
    end)
    return rows
end

-- Stats about the summons a given caster has cast, used by the achievements (Achieve.lua).
function Store.Stats(caster)
    local s = { cast = 0, kinds = {}, distinctMaps = 0, points = 0 }
    local maps = {}
    for _, ev in pairs(ST.db.events) do
        if ev.caster == caster and not ev.fake and Store.Lands(ev) then
            s.cast = s.cast + 1
            s.points = s.points + (ev.points or 0)
            if ev.kind then s.kinds[ev.kind] = (s.kinds[ev.kind] or 0) + 1 end
            if ev.mapID and not maps[ev.mapID] then
                maps[ev.mapID] = true
                s.distinctMaps = s.distinctMaps + 1
            end
        end
    end
    return s
end
