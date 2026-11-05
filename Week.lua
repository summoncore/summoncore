-- Week: the weekly contest. Each Monday (UTC) to the next, the group's landed summon points are set against
-- Zennit's points toward a week off (see Store.Goal). He starts every week with a head start, and a tie goes to
-- him. When he wins, the seven days that follow are his: no summons. From October 2026 the race follows
-- Week.RULES: the group has to beat Zennit at his own answers, and he no longer wins most weeks by default.
-- Everything is derived from the event log, so every client reaches the same result.
-- A week closes two days after it ends: Zennit can no longer answer into it (Week.LateAnswer), so its result then only
-- changes if a summons made in it reaches a client late, and then the same way on every client.
local ADDON, ST = ...
local Week = {}
ST.Week = Week

local DAY = 86400
local LENGTH = 7 * DAY
local MONDAY = 4 * DAY       -- 1970-01-05 00:00 UTC was a Monday
Week.HEADSTART = 10          -- points Zennit starts each week with

-- Start of the week containing t (default: now), a Unix time.
function Week.Start(t)
    t = t or time()
    return t - ((t - MONDAY) % LENGTH)
end

-- Zennit's characters: the listed names, plus the alts his own client has announced over sync (settings.zenitAlts).
local function isZennit(name)
    local base = ST.baseName(name)
    if not base then return false end
    local s = ST.db.settings
    for _, list in ipairs({ s and s.zenitNames or { "Zennit" }, s and s.zenitAlts or {} }) do
        for _, n in ipairs(list) do
            if ST.baseName(n) and ST.baseName(n):lower() == base:lower() then return true end
        end
    end
    return false
end
Week.IsZennit = isZennit

-- A week closes GRACE after it ends, leaving time for late answers and late syncs. Once closed, no answer made later counts
-- toward it. Its result is not frozen on each client (a client that synced late would keep a different one for good): it is
-- worked out from the log, which every client ends up holding the same.
Week.GRACE = 2 * DAY

function Week.Closed(start, now)
    return (now or time()) >= start + LENGTH + Week.GRACE
end

function Week.EventClosed(ev)
    return Week.Closed(Week.Start(ev.time))
end

-- Is this answer to the summons `ev` too late to count? One made after the summons' week closed is, unless it pays silver
-- already owed (that moves no points). It goes by the answer's own time, not when it arrived, so every client agrees: Sync
-- refuses such an answer, and Respond.Decide never makes one.
function Week.LateAnswer(ev, resp)
    return resp ~= nil and resp.result ~= "paid" and resp.time >= Week.Start(ev.time) + LENGTH + Week.GRACE
end

-- The race from the week of Monday 5 October 2026 (UTC) on: beating Zennit means beating his answers (see
-- design/lenses.md). Only summons OF Zennit count, up to `cap` of them each week; once `minimum` have been filed and
-- the latest answered, he may close the Index for the rest of the week (an answer with `closes` set). He has `dice`
-- rolls a week; each helper (up to `helpersMax`) adds `helperBonus` to the summoner's roll. Weeks before `from` keep the
-- rules they were played under, so the season and the chapters already reached do not change.
Week.RULES = { from = 1791158400, headstart = 2, minimum = 5, cap = 10, dice = 3, helperBonus = 5, helpersMax = 2,
    -- Catch-up (design/lenses.md, the Interest Curve): when one side is this many wins ahead in the season, the Index
    -- moves Zennit's edge on the dice by this much for the side that is behind, and the other way for the side ahead.
    -- A lead of 1 changes nothing; a lead past the last step uses the last step.
    catchup = { [2] = 5, [3] = 10 },
    -- The whim of the week (design/lenses.md, Surprise): about half the weeks, the Index draws one small twist.
    whims = true,
    -- A summons of Zennit unanswered for this many seconds is "waiting for his answer": the group is told, so it can chase him
    -- (design/lenses.md, Community).
    overdue = 3600,
    -- In the last stretch of a week (this many seconds) the Index says it is about to close (design/lenses.md, Time).
    lastCall = 24 * 3600,
    -- Writs (design/lenses.md, Resonance): the group may play this many a week on a summons of him. If he then declines that
    -- summons in the game's own prompt, it costs him its points; with no writ a decline costs nothing and the summons does not count.
    writs = 2,
    -- Free declines (design/lenses.md, Balance): the first decline he really makes in a week costs nothing and the summons does not
    -- happen. Every later one costs him its points: a free decline with no limit would let him decide every week (Balance).
    declines = 1,
    -- From the week of Monday 9 November 2026 (UTC), a week has a winner only if at least one summons of Zennit was filed in it.
    -- Only summons of him count, so summons of each other do not start the race: a week nobody summoned him has no winner, as a
    -- week with no summons at all has none. Earlier weeks keep the results they were played under (Week.RaceNeedsHim).
    needsHim = 1794182400 }

-- Each whim moves one rule for one week, by a few points of the group's chance (about +6 or -5 in a normal week), so no
-- week is much easier or harder than another. `show` is the rule whose number the text names, when it does.
Week.WHIMS = {
    distracted = { name = "The Index is distracted", rules = { edge = -5 }, text = "Zennit's edge on the dice is 5 lower this week." },
    attentive = { name = "The Index is attentive", rules = { edge = 5 }, text = "Zennit's edge on the dice is 5 higher this week." },
    feast = { name = "A helpers' feast", rules = { helperBonus = 3 }, show = "helperBonus",
        text = "Each helper adds +%d to the summoner's roll this week." },
    tired = { name = "The helpers are tired", rules = { helperBonus = -3 }, show = "helperBonus",
        text = "Each helper adds only +%d to the summoner's roll this week." },
}
-- Half the weeks have none. The week number picks one, the same on every client, so nothing is synced or kept.
local DECK = { false, "distracted", false, "feast", false, "attentive", false, "tired" }

function Week.Whim(start)
    if not Week.RULES.whims or not Week.NewRules(start) then return nil end
    local n = math.floor((start - MONDAY) / LENGTH)
    local x = (n * 1103515245 + 12345) % 2147483648
    local id = DECK[math.floor(x / 65536) % #DECK + 1]
    return id and Week.WHIMS[id] or nil, id
end

-- A rule's value for the week starting at `start`: its base value, moved by the week's whim (never below 0).
function Week.Rule(name, start)
    local base = name == "edge" and ST.Respond.EDGE or Week.RULES[name]
    local whim = Week.Whim(start)
    return math.max(0, base + (whim and whim.rules[name] or 0))
end

-- A whim in one sentence ("The Index is distracted. Zennit's edge on the dice is 5 lower this week."), the number being the
-- rule's value in a week that has that whim. Needs no week, so the Ledger can compare it with its recorded lines.
function Week.WhimSentence(id)
    local whim = Week.WHIMS[id]
    if not whim then return nil end
    local text = whim.text
    if whim.show then
        local base = whim.show == "edge" and ST.Respond.EDGE or Week.RULES[whim.show]
        text = string.format(text, math.max(0, base + (whim.rules[whim.show] or 0)))
    end
    return whim.name .. ". " .. text
end

-- The week's whim in one sentence, or nil.
function Week.WhimLine(start)
    local _, id = Week.Whim(start)
    return id and Week.WhimSentence(id) or nil
end

function Week.NewRules(start)
    return start >= Week.RULES.from
end

-- Does the week starting at `start` need a summons of Zennit to have a winner? (Week.RULES.needsHim)
function Week.RaceNeedsHim(start)
    return Week.NewRules(start) and start >= Week.RULES.needsHim
end

-- Seasons started and stopped by the admin (/sc season start|stop). A stop ends the season in progress at once, with no
-- finale, and the race counts no week until a start; a start begins a new season, 0 to 0, from the week it is made in.
-- Kept in ST.db.seasonMarks as { [kind:time] = { kind, time } } and synced (Sync, "C"), so every client works out the same
-- seasons whenever it hears of them. With no marks at all the season runs from the first summon, as it always has.
local function marks()
    ST.db.seasonMarks = ST.db.seasonMarks or {}
    return ST.db.seasonMarks
end

-- Keeps a mark if it is new. Returns true when it was.
function Week.PutMark(kind, t)
    if (kind ~= "start" and kind ~= "stop") or type(t) ~= "number" then return false end
    local key = kind .. ":" .. t
    if marks()[key] then return false end
    marks()[key] = { kind = kind, time = t }
    return true
end

-- Every mark, oldest first.
function Week.Marks()
    local list = {}
    for _, m in pairs(marks()) do list[#list + 1] = m end
    table.sort(list, function(a, b)
        if a.time ~= b.time then return a.time < b.time end
        return a.kind > b.kind -- a stop and a start made in the same second: the start is the later word
    end)
    return list
end

-- The newest mark, or nil.
function Week.LastMark()
    local list = Week.Marks()
    return list[#list]
end

-- Is a season running in the week starting at `start`? The last mark made before the week ended decides; no mark, it is.
function Week.Running(start)
    local last
    for _, m in ipairs(Week.Marks()) do
        if m.time < start + LENGTH then last = m else break end
    end
    return not last or last.kind == "start"
end

-- Was a mark made in the week starting at `start`? (A season started that week owes nothing to the week before.)
function Week.MarkIn(start)
    for _, m in ipairs(Week.Marks()) do
        if m.time >= start and m.time < start + LENGTH then return true end
    end
    return false
end

-- Whether a week was his week off depends on the week before, and that one on the week before it, back to the first summons.
-- So the answers are kept until anything the race reads changes: the summons and their answers, Zennit's names, the season
-- marks or the rules. The stamp sums those (exactly: well inside a double's 53 bits for any log this addon will see).
local ANSWER_CODE = { accepted = 1, refused = 2, excused = 3, declined = 4, owed = 5, paid = 6, won = 7, lost = 8, away = 9 }
local zennitKnown, zennitNames = {}, nil -- isZennit by target, while his names stay the same
local function raceStamp()
    local s = ST.db.settings
    local names = table.concat(s and s.zenitNames or { "Zennit" }, ",") .. ";" .. table.concat(s and s.zenitAlts or {}, ",")
    if names ~= zennitNames then zennitKnown, zennitNames = {}, names end
    local n, times, answers, marked = 0, 0, 0, 0
    for _, ev in pairs(ST.db.events) do
        if not ev.fake then
            n = n + 1
            local target = ev.target or ""
            local z = zennitKnown[target]
            if z == nil then
                z = isZennit(target)
                zennitKnown[target] = z
            end
            times = times + ev.time + (z and ev.time or 0) + (ev.points or 0) * 7
            local r = ev.response
            if r then
                answers = answers + (r.time or 0) * 64 + (ANSWER_CODE[r.result] or 15) * 4 + (r.closes and 2 or 0) + (r.listed and 1 or 0)
            end
        end
    end
    for _, m in pairs(ST.db.seasonMarks or {}) do marked = marked + m.time * 2 + (m.kind == "start" and 1 or 0) end
    local R = Week.RULES
    return string.format("%d:%.0f:%.0f:%.0f:%s:%s:%s:%s:%s:%s", n, times, answers, marked, tostring(R.from), tostring(R.headstart),
        tostring(R.minimum), tostring(R.cap), tostring(R.needsHim), names)
end
local offKnown, offStamp = {}, nil

-- Is the week starting at `start` Zennit's week off? From the new rules on, a week off is real: he won the week before,
-- so summons of him are filler (logged, answered and gagged as usual, but the race ignores them) and nobody wins the
-- week: a win for Zennit is a pause, not a head start. The search back through the weeks ends at the first real summon.
function Week.IsOff(start)
    if not Week.NewRules(start) then return false end
    if not Week.Running(start) or Week.MarkIn(start) then return false end -- no race, or a season started this week
    local stamp = raceStamp()
    if stamp ~= offStamp then offKnown, offStamp = {}, stamp end
    if offKnown[start] ~= nil then return offKnown[start] end
    local prev, first = start - LENGTH, nil
    for _, ev in pairs(ST.db.events) do
        if not ev.fake and (not first or ev.time < first) then first = ev.time end
    end
    local off = false
    if first and prev >= Week.Start(first) then off = Week.Score(prev).winner == "zennit" end
    offKnown[start] = off
    return off
end

-- Why a summon of Zennit in the week starting at `start` does not count, and what the Index files it under. `you` words
-- it for Zennit's own client.
function Week.Why(start, you)
    if not Week.Running(start) then return "No season is running", "between seasons" end
    if Week.IsOff(start) then return you and "It is your week off" or "It is his week off", "disturbing his leave" end
    if Week.IsClosed(start) then
        return you and "You have closed the Index for the week" or "He has closed the Index for the week", "enthusiasm"
    end
    return string.format(you and "It is past the %d summons of you that count this week" or
        "It is past the %d summons of him that count this week", Week.RULES.cap), "enthusiasm"
end

-- The real summons of Zennit in the week starting at `start`, oldest first: { { id, ev }, ... }.
local function summonsOfZennit(start)
    local list = {}
    for id, ev in pairs(ST.db.events) do
        if not ev.fake and ev.time >= start and ev.time < start + LENGTH and isZennit(ev.target) then
            list[#list + 1] = { id = id, ev = ev }
        end
    end
    table.sort(list, function(a, b)
        if a.ev.time ~= b.ev.time then return a.ev.time < b.ev.time end
        return tostring(a.id) < tostring(b.id)
    end)
    return list
end

-- The writs played on summons of Zennit in the week starting at `start`, oldest first. Only the first RULES.writs count: the rest
-- are worked out the same way on every client, so two friends who arm one at once cannot get a third.
function Week.Writs(start)
    local out = {}
    for _, s in ipairs(summonsOfZennit(start)) do
        if s.ev.writ then out[#out + 1] = s.ev end
    end
    return out
end

-- Writs the group can still play in the week starting at `start` (none outside the new rules, or in his week off).
function Week.WritsLeft(start)
    if not Week.NewRules(start) or Week.IsOff(start) or not Week.Running(start) then return 0 end
    return math.max(0, Week.RULES.writs - #Week.Writs(start))
end

-- Free declines he still has in the week starting at `start`: the first decline of a week is free, counted from the log.
function Week.DeclinesLeft(start)
    if not Week.NewRules(start) or Week.IsOff(start) then return 0 end
    local used = 0
    for _, s in ipairs(summonsOfZennit(start)) do
        if s.ev.response and s.ev.response.result == "declined" then used = used + 1 end
    end
    return math.max(0, Week.RULES.declines - used)
end

local function declinesText(n)
    return string.format("%d free decline%s left", n, n == 1 and "" or "s")
end
Week.DeclinesText = declinesText

-- Does this summons carry a writ that counts?
function Week.WritCounts(ev)
    if not ev.writ then return false end
    for i, w in ipairs(Week.Writs(Week.Start(ev.time))) do
        if w == ev then return i <= Week.RULES.writs end
    end
    return false
end

-- The summons of Zennit filed toward the week starting at `start`: the list (oldest first), how many of them count
-- (up to `cap`, or up to the one whose answer closed the Index), and whether he closed it.
local function filed(start, off)
    local list = summonsOfZennit(start)
    if off == nil then off = Week.IsOff(start) end
    if off then return list, 0, false end
    local limit, closed = Week.RULES.cap, false
    for i, s in ipairs(list) do
        if i > limit then break end
        if i >= Week.RULES.minimum and s.ev.response and s.ev.response.closes then
            limit, closed = i, true
            break
        end
    end
    return list, math.min(limit, #list), closed
end

-- Has Zennit closed the Index for the week starting at `start`?
function Week.IsClosed(start)
    if not Week.NewRules(start) then return false end
    return (select(3, filed(start)))
end

-- Summons of Zennit in the week starting at `start` that he has not answered. With `minAge`, only those at least that old.
function Week.Unanswered(start, minAge)
    local n, now = 0, time()
    for _, s in ipairs(summonsOfZennit(start)) do
        if not s.ev.response and (not minAge or now - s.ev.time >= minAge) then n = n + 1 end
    end
    return n
end

-- Summons of Zennit in the week starting at `start` whose silver he has asked for and not yet had. Returns how many, and the silver.
function Week.Owed(start)
    local n, silver = 0, 0
    for _, s in ipairs(summonsOfZennit(start)) do
        if s.ev.response and s.ev.response.result == "owed" then
            n, silver = n + 1, silver + ST.Respond.AmountOf(s.ev.response)
        end
    end
    return n, silver
end

-- When the week starting at `start` closes to the race, in the player's own time ("Monday 11:00"), and when he can last answer
-- into it (two days later). The clock is UTC, so this is the week's real turnover where the player is.
function Week.ClosesText(start)
    return date("%A %H:%M", start + LENGTH), date("%A %H:%M", start + LENGTH + Week.GRACE)
end

-- "9 hours", "40 minutes" or "1 hour": how long is left.
local function leftText(secs)
    if secs >= 3600 then
        local h = math.ceil(secs / 3600)
        return h == 1 and "1 hour" or (h .. " hours")
    end
    local m = math.max(1, math.ceil(secs / 60))
    return m == 1 and "1 minute" or (m .. " minutes")
end

-- Seconds left in the current week if it is in its last stretch (RULES.lastCall), else nil.
function Week.LastCall(now)
    now = now or time()
    local start = Week.Start(now)
    local left = start + LENGTH - now
    if Week.RULES.lastCall and left > 0 and left <= Week.RULES.lastCall and Week.NewRules(start) and not Week.IsOff(start)
        and Week.Running(start) then
        return left
    end
end

-- Waiting for his answer for longer than RULES.overdue.
function Week.Overdue(start)
    return Week.Unanswered(start, Week.RULES.overdue)
end

-- The summon Zennit can close the Index on, in the week starting at `start` (nil if he can't yet): the latest summon that
-- counts, once at least `minimum` have been filed and the latest of them answered (README). A close cuts the count at the
-- summons it is made on, so closing on an earlier one while a later one waits for his answer would take away summons made
-- before the close, which count as accepted.
function Week.CloseTarget(start)
    if not Week.NewRules(start) then return nil end
    local list, counted, closed = filed(start)
    if closed or counted < Week.RULES.minimum then return nil end
    if not (list[counted].ev.response and list[#list].ev.response) then return nil end
    return list[counted].id, list[counted].ev
end

-- Does this summon count toward its week? Under the new rules: a summon of Zennit among those filed (a test summon is
-- placed among the real ones by its time). Under the old rules every summon counts.
function Week.Counts(ev)
    local start = Week.Start(ev.time)
    if not Week.NewRules(start) then return true end
    if not isZennit(ev.target) or Week.IsOff(start) or not Week.Running(start) then return false end
    local list, counted, closed = filed(start)
    local before = 0
    for i, s in ipairs(list) do
        if s.ev == ev then return i <= counted end
        if s.ev.time <= ev.time then before = before + 1 end
    end
    return before < (closed and counted or Week.RULES.cap)
end

-- Dice Zennit has left in the week starting at `start`, or nil when there is no limit (the old rules).
function Week.DiceLeft(start)
    if not Week.NewRules(start) then return nil end
    local used = 0
    for _, s in ipairs(summonsOfZennit(start)) do
        local res = s.ev.response and s.ev.response.result
        if res == "won" or res == "lost" then used = used + 1 end
    end
    return math.max(0, Week.RULES.dice - used)
end

-- Zennit's edge on the dice for the week starting at `start`: Respond.EDGE, moved by the season's lead (RULES.catchup).
-- Zennit ahead by wins: the edge shrinks, so the group has a way back; the group ahead: it grows. It is worked out from
-- the weeks before `start`, so it does not change during the week. Second value: how far it moved (negative: in the
-- group's favour).
function Week.Edge(start)
    local base = Week.Rule("edge", start)
    if not Week.NewRules(start) then return base, 0 end
    local season = Week.Season(start)
    local lead = season.zennit - season.group -- Zennit's lead in weekly wins
    local steps, top = Week.RULES.catchup, 0
    for lead_ in pairs(steps) do top = math.max(top, lead_) end
    local by = steps[math.min(math.abs(lead), top)] or 0
    if lead == 0 or by == 0 then return base, 0 end
    local moved = lead > 0 and -by or by
    if base + moved < 0 then moved = -base end -- never a handicap for Zennit
    return base + moved, moved
end

-- What the summoner adds to their dice roll for this summon: a bonus per helper (0 under the old rules).
function Week.HelperBonus(ev)
    if not Week.NewRules(Week.Start(ev.time)) then return 0 end
    return math.min(#(ev.assistants or {}), Week.RULES.helpersMax) * Week.Rule("helperBonus", Week.Start(ev.time))
end

-- The score for the week starting at `start`: { start, group, zennit, summons, winner, over, new, counted, extra,
-- closed }. winner is "zennit", "group", or nil when there were no summons that week. Under the new rules, counted is
-- how many summons of Zennit count toward the week, extra how many came after those, and closed whether he closed
-- the Index. paused: no season was running that week (Week.Running), so nothing counts and nobody wins it.
function Week.Score(start)
    local new = Week.NewRules(start)
    local r = { start = start, group = 0, zennit = new and Week.RULES.headstart or Week.HEADSTART, summons = 0,
        over = time() >= start + LENGTH, new = new, counted = 0, extra = 0, off = new and Week.IsOff(start),
        paused = not Week.Running(start) }
    for _, ev in pairs(ST.db.events) do
        if not ev.fake and ev.time >= start and ev.time < start + LENGTH then
            r.summons = r.summons + 1
            if not new then
                if ST.Store.Lands(ev) then r.group = r.group + (ev.points or 0) end
                if isZennit(ev.target) then r.zennit = r.zennit + ST.Store.Goal(ev) end
            end
        end
    end
    if new then
        local list, counted, closed = filed(start, r.off or r.paused)
        r.closed = closed
        for i, s in ipairs(list) do
            if i <= counted then
                r.counted = r.counted + 1
                if ST.Store.Lands(s.ev) then r.group = r.group + (s.ev.points or 0) end
                r.zennit = r.zennit + ST.Store.Goal(s.ev)
            else
                r.extra = r.extra + 1
            end
        end
    end
    -- from RULES.needsHim, summons of each other do not start the race: no summons of him filed, no winner
    local raced = r.summons > 0 and not (Week.RaceNeedsHim(start) and r.counted + r.extra == 0)
    if raced and not r.off and not r.paused then r.winner = r.zennit >= r.group and "zennit" or "group" end
    return r
end

-- Is Zennit on his week off right now? True when he won last week. Returns the end time as the second value. Under the
-- new rules it is Week.IsOff, so a season started or stopped this week (no week off carried over) is not called his leave.
function Week.Immune(now)
    local current = Week.Start(now)
    if Week.NewRules(current) then return Week.IsOff(current), current + LENGTH end
    local last = Week.Score(current - LENGTH)
    return last.winner == "zennit", current + LENGTH
end

local function lines(r)
    local text = string.format("group %d, Zennit %d (including a %d point head start)", r.group, r.zennit,
        r.new and Week.RULES.headstart or Week.HEADSTART)
    if r.new then
        text = text .. string.format("; %d of up to %d summons of Zennit filed", r.counted, Week.RULES.cap)
        if r.closed then text = text .. ", and he closed the Index" end
        if r.extra > 0 then text = text .. string.format(", %d more filed under 'enthusiasm'", r.extra) end
    end
    return text
end

-- One line saying how the week is going, or how it ended.
function Week.Describe(r)
    if r.paused then
        return r.summons == 0 and "no season running, and no summons" or
            string.format("no season running, so the race skipped the week (%d summons filed under 'between seasons')", r.summons)
    end
    if r.off then
        return (r.over and "Zennit's week off: " or "Zennit's week off, ") .. (r.extra == 0 and "nobody summoned him" or
            string.format("his leave disturbed %d time%s", r.extra, r.extra == 1 and "" or "s")) ..
            ", and the race skipped the week"
    end
    if r.summons == 0 then return "no summons that week" end
    if Week.RaceNeedsHim(r.start) and r.counted + r.extra == 0 then
        return r.over and "nobody summoned Zennit that week, so the race had no winner" or
            "this week so far: nobody has summoned Zennit, and the race starts with the first summons of him"
    end
    if not r.over then
        return "this week so far: " .. lines(r) .. (r.zennit >= r.group and ", Zennit is ahead" or ", the group is ahead")
    end
    return (r.winner == "zennit" and "Zennit won the week: " or "the group won the week: ") .. lines(r)
end

-- The season is a race: the first side to WINS weekly wins takes the finale, then the count starts again.
-- Worked out from the log, one completed week at a time, so every client reaches the same story.
-- Returns { zennit, group (wins so far this season), since (the season's first week), running (false once the admin has
-- stopped it), number (the season's number in the story), finales = { { start, side, from, season } }, ended = { { from,
-- to, zennit, group } } (seasons the admin stopped before a finale), chapters = { { start, side, n, key, season } },
-- openings = { { start, season, key } } } where key is the story chapter that win plays (Week.ChapterKey; n = 5 is the
-- finale), and each season after the first opens with a chapter of its own, chosen by how the season before it ended.
-- Only a finale moves the story on to its next season: a season the admin stops and starts again is the same season,
-- told again from its start, so a restart (a test season before the beta, say) never skips a season of the story.
Week.WINS = 5

-- The story chapter of a side's nth win in a season: z3 and g3 in season one, 2z3 and 2g3 in season two.
function Week.ChapterKey(number, side, n)
    return (number > 1 and number or "") .. (side == "zennit" and "z" or "g") .. n
end

-- The opening chapter of a season after the first: 2a after Zennit took the season before's finale, 2b after the group did.
function Week.OpeningKey(number, side)
    return number .. (side == "zennit" and "a" or "b")
end

function Week.Season(now)
    now = now or time()
    local s = { zennit = 0, group = 0, finales = {}, chapters = {}, ended = {}, openings = {}, running = true, number = 1 }
    local first
    for _, ev in pairs(ST.db.events) do
        if not ev.fake and (not first or ev.time < first) then first = ev.time end
    end
    local list = Week.Marks()
    if list[1] and list[1].time <= now and (not first or list[1].time < first) then first = list[1].time end
    if not first then return s end
    local start, current = Week.Start(first), Week.Start(now)
    s.since = start -- the first week of the season in progress (each finale lists its own as `from`)
    local m = 1
    while start <= current do
        -- the admin's marks in this week (only those already made, when `now` is in it): the last one decides
        local last
        while list[m] and list[m].time < start + LENGTH and list[m].time <= now do
            last = list[m]
            m = m + 1
        end
        if last then
            if s.running and (s.zennit > 0 or s.group > 0) then
                s.ended[#s.ended + 1] = { from = s.since, to = start, zennit = s.zennit, group = s.group }
            end
            s.zennit, s.group, s.since, s.running = 0, 0, start, last.kind == "start"
        end
        local r = start < current and s.running and Week.Score(start)
        local side = r and r.winner
        if side then
            s[side] = s[side] + 1
            s.chapters[#s.chapters + 1] = { start = start, side = side, n = s[side], season = s.number,
                key = Week.ChapterKey(s.number, side, s[side]) }
            if s[side] >= Week.WINS then
                s.finales[#s.finales + 1] = { start = start, side = side, from = s.since, season = s.number }
                s.zennit, s.group = 0, 0
                s.since = start + LENGTH
                s.number = s.number + 1
                s.openings[#s.openings + 1] = { start = s.since, season = s.number, key = Week.OpeningKey(s.number, side) }
            end
        end
        start = start + LENGTH
    end
    return s
end

-- Says once a week what the whim of this week is (nothing in a week off, or when there is none).
function Week.AnnounceWhim()
    local settings = ST.db and ST.db.settings
    local start = Week.Start()
    if not settings or settings.whimSeen == start then return end
    local line = Week.WhimLine(start)
    if not line or Week.IsOff(start) then return end
    settings.whimSeen = start
    ST.print("|cffffd100This week's whim:|r " .. line)
end

-- Says once when a finished week has been won, and points to that win's chapter of the story.
-- The keepsake of the season that has just ended, in chat.
local function printKeepsake()
    local seasons = ST.Ledger.Seasons()
    if seasons[1] then
        for _, line in ipairs(seasons[1].lines) do ST.print(line) end
    end
end

-- A result announced as provisional is settled once its week has closed: said again as final, or as changed.
local function settleLastWeek()
    local settings = ST.db.settings
    local a = settings.weekAnnounced
    if not (a and a.provisional and Week.Closed(a.start)) then return end
    a.provisional = nil
    local now = Week.Score(a.start).winner
    local who = { zennit = "Zennit", group = "the group" }
    if now == a.winner then
        ST.print(string.format("The week of %s is now final: it stays with %s.", date("%d %b", a.start), who[now] or "nobody"))
    else
        ST.print(string.format("|cffffd100The week of %s changed|r after answers or summons that came in late: it went to %s, not %s.",
            date("%d %b", a.start), who[now] or "nobody", who[a.winner] or "nobody"))
    end
    local season = Week.Season()
    local f = season.finales[#season.finales]
    if now == a.winner and f and f.start == a.start then printKeepsake() end
end

-- A week already announced as final can still change when summons made in it reach this client late (a friend who was away
-- syncs at last): the result follows the log on every client, so say so, once. Sync calls this after summons arrive.
function Week.Recheck()
    local a = ST.db and ST.db.settings and ST.db.settings.weekAnnounced
    if not a or a.provisional then return end -- a provisional result is settled at the next login (settleLastWeek)
    local now = Week.Score(a.start).winner
    if now == a.winner then return end
    local who = { zennit = "Zennit", group = "the group" }
    ST.print(string.format("|cffffd100The week of %s changed|r: summons made in it reached the Index late, and it went to %s, not %s.",
        date("%d %b", a.start), who[now] or "nobody", who[a.winner] or "nobody"))
    a.winner = now
end

local function checkLastWeek()
    if not ST.db or not ST.db.settings then return end
    ST.db.settings.weekFrozen = nil -- winners each client froze for itself, before 0.28.1: results come from the log alone now
    settleLastWeek() -- an earlier provisional result, now that its week has closed
    local last = Week.Score(Week.Start() - LENGTH)
    if last.off and ST.db.settings.weekSeen ~= last.start then
        ST.db.settings.weekSeen = last.start
        ST.print("Zennit's week off is over. He is back on the list, and the Index has filed the week's summons as disturbing his leave.")
        return
    end
    if not last.winner or ST.db.settings.weekSeen == last.start then return end
    ST.db.settings.weekSeen = last.start
    ST.Clips.Play("narrator_weekopen")
    local season = Week.Season()
    local chapter = season.chapters[#season.chapters]
    local key = chapter and chapter.start == last.start and chapter.key
    -- while he can still answer into the week (two days after it ends), the result is provisional
    local waiting = Week.Unanswered(last.start)
    local provisional = waiting > 0 and not Week.Closed(last.start)
    ST.db.settings.weekAnnounced = { start = last.start, winner = last.winner, provisional = provisional or nil }
    local story = ""
    if key then
        story = ST.Intro.HasChapter(key) and (" The story: |cffffd100/sc intro " .. key .. " group|r shows it to the group, at the raid perhaps.")
            or " (That chapter of the story is not written yet.)"
        if chapter.n >= Week.WINS then
            -- the next season has begun with this week: its opening plays now, if this version of the addon has it
            local open = season.openings[#season.openings]
            if open and ST.Intro.HasChapter(open.key) then
                story = story .. string.format(" That was the finale, and season %d has begun: |cffffd100/sc intro %s|r is how it " ..
                    "opens. |cffffd100/sc seasons|r keeps the Index's record of the last one.", season.number, open.key)
            else
                story = story .. string.format(" That was the finale, and season %d has begun. Its story is not in this version of " ..
                    "Summon Core: an update will have it. |cffffd100/sc seasons|r keeps the Index's record of the last one.", season.number)
            end
        end
    end
    if last.winner == "zennit" then
        ST.print(ST.Voice.Say("week.zennit", {
            "|cffffd100Zennit won the week|r (%s). He is on leave until next Monday.%s",
            "|cffffd100Zennit has won the week|r (%s). He is on leave until Monday, and the Index has been told not to look for him.%s",
            "|cffffd100The week was Zennit's|r (%s). He is on leave until next Monday.%s" }, lines(last), story))
    else
        ST.print(ST.Voice.Say("week.group", {
            "The group won the week (%s). Zennit is back on the list.%s",
            "The group took the week (%s). Zennit is back on the list, and has been told.%s",
            "The week went to the group (%s). Zennit is back on the list.%s" }, lines(last), story))
    end
    ST.print(string.format("Season %d: Zennit %d of %d, the group %d of %d.", season.number, season.zennit, Week.WINS, season.group,
        Week.WINS))
    if provisional then
        ST.print(string.format("|cffffd100Provisional:|r %d summons of him %s still waiting for his answer, and the week closes on %s. " ..
            "The Index will say again if it changes.", waiting, waiting == 1 and "is" or "are",
            date("%A", last.start + LENGTH + Week.GRACE)))
    elseif chapter and chapter.start == last.start and chapter.n >= Week.WINS then
        printKeepsake() -- a finale just landed: the Index's keepsake of the season, with who was there
    end
end

-- The rules of the race on one card, with this week's live numbers (the base rules, the whim and the catch-up already
-- applied), so there is one place that says them all and it cannot go stale. A list of lines.
function Week.RulesCard(start)
    start = start or Week.Start()
    local R, kinds = Week.RULES, ST.Scoring.kindPoints
    if not Week.NewRules(start) then
        return { "The race runs on the old rules this week: every landed summon counts for the group, and Zennit starts with " ..
            Week.HEADSTART .. " points." }
    end
    local edge, moved = Week.Edge(start)
    local bonus = Week.Rule("helperBonus", start)
    local card = {
        "THE RACE, this week",
        string.format("Counts: only summons of Zennit, up to %d a week. Any more are filed under 'enthusiasm'. Once %d are filed and " ..
            "the latest is answered, he may close the Index for the week.", R.cap, R.minimum),
        string.format("Points: a city %d, a zone %d, a dungeon %d, a far-flung place %d. The group scores the summons that land; " ..
            "Zennit scores the dice he wins and the places on his list that land. Zennit starts the week with %d, and a tie is his.",
            kinds.city, kinds.zone, kinds.dungeon, kinds.remote, R.headstart),
        string.format("Dice: he has %d a week and adds +%d to his roll; each helper (two at most) adds +%d to the summoner's. " ..
            "When they are gone he can only accept, decline or ask for the silver.", Week.Rule("dice", start), edge, bonus),
        string.format("Writs: the group has %d a week. Played with /sc writ before a ritual on him, a writ makes his decline of that summons " ..
            "cost him its points. Once his free decline is used, a writ only bites at a place on his list.", R.writs),
        string.format("Declines: in the game's prompt or on the Index's form, a declined summons does not happen. It is free at a place on " ..
            "his list, and his first decline of a week is free (%d); every other one costs him its points, and one with a writ always does.", R.declines),
        string.format("His list: up to %d places of %d letters or more, set for the week (a place he adds counts from the next Monday). " ..
            "Accepting a summon there earns him the points; declining it is free (unless the group played a writ).",
            ST.Respond.LIST_MAX, ST.Respond.LIST_MIN),
        string.format("Postcards: the first summons of him to each far-flung place (%d points) in a season that lands earns the Index a " ..
            "postcard from him. This season: %d of %d.", kinds.remote, #ST.Ledger.Postcards(), ST.Ledger.PostcardPlaces()),
        string.format("Catch-up: when a side leads the season by two wins, his edge moves %d toward the side that is behind; by three, %d.%s",
            R.catchup[2] or 0, R.catchup[3] or 0, moved ~= 0 and string.format(" This week it has moved %+d.", moved) or ""),
        string.format("The clock: this week closes %s, your time (answers stop %s). A week is Monday to Monday, UTC.",
            Week.ClosesText(start)),
        string.format("The season: win %d weeks to take its finale. A week he wins is followed by his week off: summons of him disturb his leave, which the race ignores but the postcards and the titles do not.",
            Week.WINS),
        "Who needs Summon Core: the caster or Zennit, for a summons of him to be filed, and Zennit, for his answers to be his. Helpers are credited if the caster has it, or anyone at the portal does.",
    }
    local whim = Week.WhimLine(start)
    card[#card + 1] = whim and ("This week's whim: " .. whim) or "No whim this week."
    if Week.IsOff(start) then card[#card + 1] = "This is his week off: nobody wins the week, but summons of him still earn postcards and count for the titles, and the Index counts who disturbs his leave." end
    return card
end

-- At login: the week's clock in the player's time, once a week; and, in its last stretch, a last call with the standing.
function Week.AnnounceClock()
    local s = ST.db and ST.db.settings
    local start = Week.Start()
    if not s or not Week.NewRules(start) or Week.IsOff(start) then return end
    if s.clockSeen ~= start then
        s.clockSeen = start
        local closes, answers = Week.ClosesText(start)
        ST.print(string.format("The Index closes this week on %s, your time, and takes late answers until %s.", closes, answers))
        -- where to go this week, said before anyone travels (design/lenses.md, Indirect Control)
        local missing = ST.Ledger.MissingLine(ST.Ledger.Facts(), true)
        if missing then ST.print(missing) end
    end
    local left = Week.LastCall()
    if left and s.lastCallSeen ~= start then
        s.lastCallSeen = start
        local r = Week.Score(start)
        local side, by = Week.Lead(r)
        ST.print(string.format("|cffffd100Last call:|r the Index closes the week in %s. %s, %d of %d summons filed.", leftText(left),
            side == "group" and string.format("The group leads by %d", by) or
                (by == 0 and "It is level, and a tie goes to Zennit" or string.format("Zennit leads by %d", by)),
            r.counted, Week.RULES.cap))
        if ST.Check then ST.Check.Seen("s-lastcall", "said at login with " .. leftText(left) .. " left") end
    end
end

-- One line about a command players may not know, once a Monday at login (design/lenses.md, Interface). They go round in order,
-- so none comes twice running; `for` limits a tip to Zennit's client or everyone else's.
Week.TIPS = {
    { text = "/sc rules prints the race with this week's live numbers: the cap, his dice and edge, what a helper adds, the whim." },
    { text = "/sc tab shows what is owed in silver, and /sc cards who holds a summon card and how many punches are left." },
    { text = "/sc titles shows who leads the season's titles so far. The Index names them for good in the finale's keepsake." },
    { text = "/sc report prints how the race is going. Paste it into the group chat on a Monday." },
    { text = "/sc seasons keeps the Index's record of every finished season: who was in the room, the silver, the moments." },
    { text = "The Story tab in /sc shows every chapter the season has reached. Click a lit one to play it again." },
    { text = "/sc respond opens the summons waiting for your answer, and /sc card sell <name> sells someone a card.", only = "zennit" },
    { text = "/sc zennit list add <place> adds to your secret list (five places of four letters or more).", only = "zennit" },
}

-- The next tip for this client, advancing the round; nil when there are none for it.
function Week.NextTip()
    local s = ST.db and ST.db.settings
    if not s then return nil end
    local zennit = ST.Gag and ST.Gag.IsZennit()
    local list = {}
    for _, tip in ipairs(Week.TIPS) do
        if not tip.only or (tip.only == "zennit") == (zennit and true or false) then list[#list + 1] = tip end
    end
    if #list == 0 then return nil end
    s.tipIndex = ((s.tipIndex or 0) % #list) + 1
    return list[s.tipIndex].text
end

-- Says one tip once a week, unless they are switched off (/sc tips off).
function Week.AnnounceTip()
    local s = ST.db and ST.db.settings
    local start = Week.Start()
    if not s or s.tipsOff or s.tipSeen == start then return end
    local tip = Week.NextTip()
    if not tip then return end
    s.tipSeen = start
    ST.print("|cffffd100Tip:|r " .. tip)
end

-- At login: how the last week ended, then this week's whim, and (on Zennit's client) what is waiting for his answer.
function Week.Check()
    -- each step on its own, so one that fails does not stop the others
    ST.Guard("the week's result", checkLastWeek)
    ST.Guard("the week's whim", Week.AnnounceWhim)
    ST.Guard("the week's clock", Week.AnnounceClock)
    ST.Guard("the Monday tip", Week.AnnounceTip)
    ST.Guard("the waiting summons", Week.AnnounceWaiting)
end

-- Says this week's login lines again (/sc week login): the whim, the clock, a last call, a tip, and what is waiting or owed.
-- Last week's result is left alone, since announcing it also plays the week's opening and records the result.
function Week.Replay()
    local s = ST.db and ST.db.settings
    if not s then return end
    s.whimSeen, s.clockSeen, s.lastCallSeen, s.tipSeen = nil, nil, nil, nil
    Week.Check()
end

-- Zennit's client says what is waiting for him; everyone else's says what they owe.
function Week.AnnounceWaiting()
    if ST.Gag.IsZennit() then
        local waiting = ST.Respond.Waiting()
        if waiting > 0 then
            ST.print(string.format("The Index is holding %d summons for your answer. |cffffd100/sc respond|r opens the latest.", waiting))
        end
        local n, silver = ST.Respond.Owed("target")
        if n > 0 then
            ST.print(string.format("The Index shows %d silver owed to you on %d summons, in cash, with no receipt. Mark each paid in the Answer tab.", silver, n))
        end
    else
        local n, silver = ST.Respond.Owed("caster")
        if n > 0 then
            ST.print(string.format("You owe Zennit %d silver for %d summons, in cash, no receipt. The Ritual is keeping count: /sc tab lists it.",
                silver, n))
        end
    end
end

-- Who is ahead in a week's score, and by how much: "group" or "zennit" (a tie is his, so "zennit" with 0).
function Week.Lead(r)
    if r.group > r.zennit then return "group", r.group - r.zennit end
    return "zennit", r.zennit - r.group
end

-- The lead in words; `you` words it for Zennit's own client.
local function leadText(r, you)
    local side, by = Week.Lead(r)
    if side == "group" then return string.format("the group leads by %d", by) end
    if by == 0 then return you and "it is level, and a tie is yours" or "it is level, and a tie goes to Zennit" end
    return string.format(you and "you lead by %d" or "Zennit leads by %d", by)
end

local function diceText(n)
    return string.format("%d %s left", n, n == 1 and "die" or "dice")
end

-- The line for the moment Zennit's last die of the week is spent, or nil: from then on every summon is certain, which is
-- when the group's ordering of its summons pays off (design/lenses.md, Skill and Chance). `you` words it for Zennit.
function Week.LastDie(ev, you)
    local res = ev.response and ev.response.result
    local start = Week.Start(ev.time)
    if ev.fake or (res ~= "won" and res ~= "lost") or Week.DiceLeft(start) ~= 0 then return nil end
    if Week.IsOff(start) or Week.IsClosed(start) then return nil end
    if you then
        return ST.Voice.Say("lastdie.you", {
            "That was your last die this week. From here you can only accept, decline or ask for the silver.",
            "That was your last die of the week. From here it is accept, decline or the silver.",
            "Your dice are spent for the week. From here you can only accept, decline or ask for the silver." })
    end
    return ST.Voice.Say("lastdie.them", {
        "That was Zennit's last die this week. Every summon from here is certain: he can only accept, decline or ask for the silver.",
        "That was Zennit's last die of the week. Every summon from here is certain: he can only accept, decline or ask for the silver.",
        "Zennit's dice are spent for the week. Every summon from here is certain: he can only accept, decline or ask for the silver." })
end

-- One line on where the week starting at `start` stands (default: this week), for the chat after a summon of Zennit
-- or an answer: "Week: the group leads by 1, 4 of 10 filed, 1 die left." nil under the old rules.
function Week.StatusLine(start, you)
    start = start or Week.Start()
    if not Week.NewRules(start) then return nil end
    local r = Week.Score(start)
    if r.paused then return "Week: no season is running, so the race is off until the admin starts one." end
    if r.off then return "Week: Zennit's week off, so the race is off; summons of him disturb his leave, and still earn postcards and titles." end
    local parts = { leadText(r, you), string.format("%d of %d filed", r.counted, Week.RULES.cap),
        r.closed and "the Index is closed" or diceText(Week.DiceLeft(start)) }
    if you and not r.closed and Week.NewRules(start) and not r.off then parts[#parts + 1] = declinesText(Week.DeclinesLeft(start)) end
    local edge, moved = Week.Edge(start)
    if moved ~= 0 and not r.closed then parts[#parts + 1] = string.format("his dice edge is +%d", edge) end
    local waiting = Week.Overdue(start)
    if waiting > 0 then
        parts[#parts + 1] = string.format(you and "%d waiting for your answer" or "%d waiting for his answer", waiting)
    end
    local _, silver = Week.Owed(start)
    if silver > 0 then
        parts[#parts + 1] = string.format(you and "%d silver owed to you" or "%d silver owed to him", silver)
    end
    local left = start == Week.Start() and Week.LastCall()
    if left then parts[#parts + 1] = "the week closes in " .. leftText(left) end
    return ST.Voice.Say("week.status", { "Week: %s.", "The Index's tally for the week: %s.", "Standing: %s." },
        table.concat(parts, ", "))
end

-- The line `/sc week say` sends, and the one `/sc week copy` puts in the copy window. Or nil and why not.
function Week.SayText(start)
    start = start or Week.Start()
    if not Week.NewRules(start) then return nil, "The race runs on the old rules this week, so there is no standing to say." end
    return "Summon Core: " .. Week.StatusLine(start)
end

-- The week's standing, said to the group: `chat.channel()` is "PARTY", "RAID" or nil (not in a group) and `chat.send(text,
-- channel)` sends it. Returns true and the text sent, or false and why not. Anyone can say it; it is one line, not a report.
function Week.SayWeek(chat, start)
    local text, why = Week.SayText(start)
    if not text then return false, why end
    local channel = chat.channel()
    if not channel then return false, "You are not in a group, so there is nobody to tell." end
    local ok, err = pcall(chat.send, text, channel)
    if not ok then return false, "The game would not send that to the group (" .. tostring(err) .. ")." end
    return true, text
end

-- What the place the caster stands in is worth, and what is at stake in it: a summons is worth P to the group if he
-- accepts, to him if he wins the roll, and P comes off him if a decline costs him. A city is worth less than his head start.
function Week.PlaceLine(mapID, subzone, start)
    local pts, kind = ST.Scoring.Score(mapID, subzone)
    local place = ST.Scoring.kindText[kind] or kind
    local head = Week.Rule("headstart", start)
    if pts < head then
        return string.format("From here (%s) the summons is worth %d, which is less than his head start of %d. " ..
            "The Index would not call that a plan.", place, pts, head)
    end
    return ST.Voice.Say("briefing.place", {
        "From here (%s) the summons is worth %d: his roll could take %d, and so could yours.",
        "The Index values this place (%s) at %d: that is %d on his roll, or %d on yours.",
    }, place, pts, pts, pts)
end

-- What the caster should know as a ritual on `target` begins, or nil when it is not Zennit or the old rules apply:
-- whether it will count, where the week stands, his dice, and what helpers add.
-- True when this player has never cast a summons of Zennit (in the log as synced): their first one gets the full briefing,
-- whatever day of the week it is (design/lenses.md, Accessibility).
function Week.FirstCast()
    local me = ST.baseName(ST.Sync.myName())
    if not me then return false end
    for _, ev in pairs(ST.db.events) do
        if not ev.fake and isZennit(ev.target) and ST.baseName(ev.caster) == me then return false end
    end
    return true
end

-- away: the caster's client sees him flagged AFK (design/lenses.md, Freedom).
function Week.Briefing(target, mapID, subzone, writ, away)
    if not isZennit(target) then return nil end
    local now = time()
    local start = Week.Start(now)
    if not Week.NewRules(start) then return nil end
    -- his out-of-office, when he has written one (design/lenses.md, Character), in place of the Index's hopes
    local outOfOffice = ST.Sync.ZennitLine("away")
    if Week.IsOff(start) then
        -- what still counts on his leave (design/lenses.md, Inner Contradiction): the race is off, the rest is not
        return target .. " is on his week off. The Index will file this summons as disturbing his leave: it will not count for the race, " ..
            "but a far-flung place still earns a postcard, and the titles still see it." ..
            (outOfOffice and string.format(" His out-of-office says: '%s'", outOfOffice) or "")
    end
    if Week.Immune(now) then
        return target .. " is on his week off. The Index will note the summons" ..
            (outOfOffice and string.format(". His out-of-office says: '%s'", outOfOffice) or ", and is not hopeful.")
    end
    if away then
        return target .. " is away from his keyboard. If he has been away a while, the Index will file this summons as away: it will " ..
            "not count, and it costs nobody anything. It may be worth waiting."
    end
    local r = Week.Score(start)
    if r.closed then return target .. " has closed the Index for the week: this summon will not count." end
    if r.counted >= Week.RULES.cap then
        return target .. " has had all the summons that count this week: this one will not count."
    end
    local dice = Week.DiceLeft(start)
    local edge, moved = Week.Edge(start)
    -- The first summons of the week says everything (the helper rule, the catch-up, the whim), and so does a player's first ever.
    -- Later ones say only what changes from one cast to the next, since the rest is on /sc rules and was said a few summons ago.
    local first = r.counted == 0 or Week.FirstCast()
    local text
    if first then
        text = string.format("Summoning %s: summon %d of %d this week, and %s. He has %s%s", target, r.counted + 1,
            Week.RULES.cap, leadText(r), diceText(dice), dice == 0 and ": he must accept, decline or ask for the silver." or
            string.format("; each helper adds +%d to your roll if he suggests dice (two helpers at most).", Week.Rule("helperBonus", start)))
    else
        text = string.format("Summoning %s: summon %d of %d, %s, %s.%s", target, r.counted + 1, Week.RULES.cap, leadText(r),
            diceText(dice), dice == 0 and " He must accept, decline or ask for the silver." or "")
    end
    if mapID ~= nil or subzone ~= nil then text = text .. " " .. Week.PlaceLine(mapID, subzone, start) end
    if first and moved ~= 0 and dice > 0 then
        text = text .. string.format(" The Index, which takes no sides, has %s his edge on the dice to +%d this week.",
            moved < 0 and "cut" or "raised", edge)
    end
    local whim = first and Week.WhimLine(start)
    if whim then text = text .. " This week's whim: " .. whim end
    -- a writ only changes a decline that would have been free: his free decline, or a place on his list. Once his free decline is
    -- spent, only the list is left, and that is his secret, so the briefing says so (design/lenses.md, Secrets)
    local spent = Week.DeclinesLeft(start) == 0
    if writ then
        local pts = (mapID ~= nil or subzone ~= nil) and (ST.Scoring.Score(mapID, subzone))
        local cost = pts and string.format("%d point%s", pts, pts == 1 and "" or "s") or "its points"
        text = text .. (spent and string.format(" A writ is played. His free decline is used, so it only bites if this place is on his list: then a decline costs him %s.", cost)
            or string.format(" A writ is played: if he declines this summons in the game, it costs him %s.", cost))
    elseif first and Week.WritsLeft(start) > 0 then
        text = text .. (spent and string.format(" His free decline is used: a writ (/sc writ, %d left) only bites if this place is on his list.", Week.WritsLeft(start))
            or string.format(" /sc writ (%d left) makes a decline of this one cost him.", Week.WritsLeft(start)))
    end
    local left = Week.LastCall(now)
    if left then text = text .. string.format(" Last call: the Index closes the week in %s (%s).", leftText(left), (Week.ClosesText(start))) end
    local waiting = Week.Overdue(start)
    if waiting > 0 then
        text = text .. string.format(" %d earlier summons of him %s still waiting for his answer: a word to him might help.", waiting,
            waiting == 1 and "is" or "are")
    end
    return text
end

-- The caster is told when they summon Zennit during his week off, or after he has closed the Index for the week.
function Week.Warn(ev)
    if ev.fake or not isZennit(ev.target) then return end
    if Week.IsOff(Week.Start(ev.time)) then
        ST.print(string.format("%s is on his week off. The Index has filed the summons as disturbing his leave (%d this week): not for the race, but the titles saw it.",
            ev.target, #summonsOfZennit(Week.Start(ev.time))))
        if ST.Check then ST.Check.Seen("d-leave", "a summons of him on his week off was filed as disturbing his leave") end
    elseif Week.Immune(ev.time) then
        ST.print(ev.target .. " is on his week off. The Index has noted the summons, and is not hopeful.")
    elseif not Week.Counts(ev) then
        ST.print(ev.target .. (Week.IsClosed(Week.Start(ev.time)) and " has closed the Index for the week" or
            " has had all the summons that count this week") .. ". The Index has filed yours under 'enthusiasm'.")
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function() C_Timer.After(60, Week.Check) end) -- 60s: let the login sync bring in late summons first
