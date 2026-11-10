-- Snowball: who has thrown a snowball at Zennit. Only the thrower's client sees its own cast for certain (as with a ritual), so the
-- thrower's client counts its own throws at him and tells everyone its totals (message N): each client keeps the newest line per
-- thrower, and the leaderboard (Leaders.lua) ranks them. Zennit's client also says who hit him. A throw from someone without the
-- addon is not seen. /sc snowballs, and the leaderboard's third board.
local ADDON, ST = ...
local Snowball = {}
ST.Snowball = Snowball

Snowball.SPELL_ID = 21343 -- Snowball (the item's spell); a spell of that name counts too, in case the client numbers it differently
Snowball.SPELL_NAME = "Snowball"

local function secret(v)
    return ST.isSecret and ST.isSecret(v)
end

local function base(name)
    return ST.baseName(name) or name or ""
end

local function plain(v)
    if v == nil or secret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end

function Snowball.IsSnowball(spellID)
    if spellID == nil or secret(spellID) then return false end
    if spellID == Snowball.SPELL_ID then return true end
    return ST.SpellName and ST.SpellName(spellID) == Snowball.SPELL_NAME or false
end

local function store()
    ST.db.snowballs = ST.db.snowballs or { thrown = {}, board = {} }
    local s = ST.db.snowballs
    s.thrown, s.board = s.thrown or {}, s.board or {}
    return s
end

-- This client's own throws at Zennit: total, and this week.
function Snowball.Mine()
    local weekStart, week = ST.Week.Start(), 0
    local thrown = store().thrown
    for _, t in ipairs(thrown) do
        if t >= weekStart then week = week + 1 end
    end
    return #thrown, week, weekStart
end

-- This client threw a snowball at `target`: if it is Zennit, count it, tell everyone, and say so. Returns true if it counted.
function Snowball.Thrown(target, at)
    target = plain(target)
    if not target or not ST.Week.IsZennit(target) then return false end
    if ST.Week.IsZennit(ST.Sync.myName()) then return false end -- one of his characters at another: no
    local thrown = store().thrown
    thrown[#thrown + 1] = at or time()
    while #thrown > 5000 do table.remove(thrown, 1) end
    local total, week, weekStart = Snowball.Mine()
    ST.Sync.SendSnowballs(total, week, weekStart, true)
    ST.print(string.format("Snowball! The Index has you down for %d at Zennit this week, %d in all.", week, total))
    if ST.Hub then ST.Hub.Refresh() end
    return true
end

-- A line from another client: `who` has thrown `total` at Zennit, `week` of them in the week starting `weekStart`. `live` when
-- it is a throw just made, which Zennit's client says. Returns what Sync reports.
function Snowball.Heard(who, total, week, weekStart, stamp, live)
    local key = base(who)
    local board = store().board
    local old = board[key]
    if old and old.stamp > stamp then return "kept" end
    if not old then
        local n = 0
        for _ in pairs(board) do n = n + 1 end
        if n >= 200 then return "rejected:full" end
    end
    board[key] = { name = key, count = total, week = week, weekStart = weekStart, stamp = stamp }
    if live and (not old or total > old.count) and ST.Gag.IsZennit() then
        ST.print(string.format("%s threw a snowball at you! That is %d this week, %d in all.", key, week, total))
    end
    if ST.Hub then ST.Hub.Refresh() end
    return "snowball"
end

-- The throwers, most first: { { name, count, week } }, this client's own count from its own record.
function Snowball.Board()
    local weekStart, rows = ST.Week.Start(), {}
    local me = base(ST.Sync.myName())
    for key, line in pairs(store().board) do
        if key ~= me and line.count > 0 then
            rows[#rows + 1] = { name = line.name, count = line.count, week = line.weekStart == weekStart and line.week or 0 }
        end
    end
    local total, week = Snowball.Mine()
    if total > 0 then rows[#rows + 1] = { name = me, count = total, week = week } end
    table.sort(rows, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    return rows
end

function Snowball.Lines()
    local rows = Snowball.Board()
    if #rows == 0 then return { "Nobody has thrown a snowball at Zennit yet (that the Index has seen: the thrower needs the addon)." } end
    local lines, total = {}, 0
    for _, r in ipairs(rows) do
        total = total + r.count
        lines[#lines + 1] = string.format("%s: %d, %d of them this week.", r.name, r.count, r.week)
    end
    table.insert(lines, 1, string.format("Snowballs thrown at Zennit: %d.", total))
    return lines
end

----------------------------------------------------------------------
-- Watching this client's own casts
----------------------------------------------------------------------
local cast -- { guid, target } from UNIT_SPELLCAST_SENT, until it succeeds or fails

-- One cast event of the player's (exposed for the self-test). SENT args: unit, target, castGUID, spellID; the rest: unit,
-- castGUID, spellID.
function Snowball.OnCast(event, _, a2, a3, a4)
    local spellID = (event == "UNIT_SPELLCAST_SENT") and a4 or a3
    if not Snowball.IsSnowball(spellID) then return end
    if event == "UNIT_SPELLCAST_SENT" then
        local target = plain(a2)
        if not target and UnitSpellTargetName then
            local ok, v = pcall(UnitSpellTargetName, "player")
            target = ok and plain(v) or nil
        end
        if not target and UnitName then
            local ok, v = pcall(UnitName, "target")
            target = ok and plain(v) or nil
        end
        cast = { guid = a3, target = target }
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local c = cast
        cast = nil
        if c and (c.guid == nil or a2 == nil or c.guid == a2) then Snowball.Thrown(c.target) end
    else
        cast = nil -- failed or interrupted
    end
end

local frame = CreateFrame("Frame")
for _, ev in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
    pcall(frame.RegisterUnitEvent, frame, ev, "player")
end
frame:SetScript("OnEvent", ST.Safe("the snowball watcher", function(_, event, ...)
    if not ST.db then return end
    Snowball.OnCast(event, ...)
end))
