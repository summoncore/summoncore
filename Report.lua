-- Report: what the log already says about how the race is being played, so a playtest does not rely on memory or ask the
-- group to keep notes (they dislike bookkeeping). `/sc report` prints it; paste it into the group chat or the design
-- journal. It answers the questions in design/playtest.md that numbers can answer: how many summons a week, how he spends
-- his dice, how often the list hits, whether he closes, who wins the weeks. Nothing is stored and nothing is synced.
local ADDON, ST = ...
setfenv(1, ST.env) -- the addon's own globals (Core.lua)
local Report = {}
ST.Report = Report

local DAY = 86400
local WEEK = 7 * DAY

local function pct(a, b)
    if b == 0 then return "n/a" end
    return string.format("%d%%", math.floor(100 * a / b + 0.5))
end

local function mean(sum, n)
    if n == 0 then return "n/a" end
    return string.format("%.1f", sum / n)
end

local function median(list)
    if #list == 0 then return nil end
    table.sort(list)
    return list[math.ceil(#list / 2)]
end

local function plural(n, word)
    return string.format("%d %s%s", n, word, n == 1 and "" or "s")
end

-- ctx: { events, isZennit(name), weekStart(time), nowStart, score(start) -> { winner, off, closed, counted, summons },
--        whim(start) -> a whim or nil, dice (a week's dice), tipped (rolls the helpers tipped, counted by the caller) }
-- Returns a list of lines.
function Report.Build(ctx)
    local weeks, first, total = {}, nil, 0
    local answers, unanswered, answerDelays = {}, 0, {}
    local helpers = { [0] = 0, 0, 0 }
    local listed, answered = 0, 0
    for _, ev in pairs(ctx.events) do
        if not ev.fake and ctx.isZennit(ev.target) then
            local start = ctx.weekStart(ev.time)
            weeks[start] = weeks[start] or {}
            table.insert(weeks[start], ev)
            first = (not first or start < first) and start or first
            total = total + 1
            local n = math.min(#(ev.assistants or {}), 2)
            helpers[n] = helpers[n] + 1
            local r = ev.response
            if r then
                answers[r.result] = (answers[r.result] or 0) + 1
                answered = answered + 1
                if r.listed then listed = listed + 1 end
                if r.time and r.time >= ev.time then answerDelays[#answerDelays + 1] = r.time - ev.time end
            else
                unanswered = unanswered + 1
            end
        end
    end
    if total == 0 then return { "No summon of Zennit is in the log yet, so there is nothing to report." } end

    -- weeks, one at a time, up to and including the current one
    local active, quiet, played = 0, 0, {}
    local buckets = { { "1 or 2 summons", 1, 2 }, { "3 or 4", 3, 4 }, { "5 or more", 5, math.huge } }
    local won = {}
    local dist = { ["1-2"] = 0, ["3-4"] = 0, ["5-6"] = 0, ["7+"] = 0 }
    local diceUsed, weeksWithDice, diceOnFirstThree, diceTotal = {}, 0, 0, 0
    local rolledSum, rolledN, plainSum, plainN, afterSum, afterN, beforeSum, beforeN = 0, 0, 0, 0, 0, 0, 0, 0
    local closedWeeks, closedAt = 0, 0
    local offWeeks, groupWins, zennitWins, noWinner = 0, 0, 0, 0
    local whimWeeks, whimGroup, whimDone = 0, 0, 0
    for start = first, ctx.nowStart, WEEK do
        local list = weeks[start]
        local current = start == ctx.nowStart
        local sc = ctx.score(start)
        if list then
            active = active + 1
            table.sort(list, function(a, b) return a.time < b.time end)
            local n = #list
            if n <= 2 then dist["1-2"] = dist["1-2"] + 1 elseif n <= 4 then dist["3-4"] = dist["3-4"] + 1
            elseif n <= 6 then dist["5-6"] = dist["5-6"] + 1 else dist["7+"] = dist["7+"] + 1 end
            -- the dice: which summons he rolled on, and what they were worth
            local rolled, lastRolled = 0, nil
            for i, ev in ipairs(list) do
                local res = ev.response and ev.response.result
                if res == "won" or res == "lost" then
                    rolled = rolled + 1
                    lastRolled = i
                    rolledSum, rolledN = rolledSum + (ev.points or 0), rolledN + 1
                    if i <= 3 then diceOnFirstThree = diceOnFirstThree + 1 end
                else
                    plainSum, plainN = plainSum + (ev.points or 0), plainN + 1
                end
            end
            diceTotal = diceTotal + rolled
            diceUsed[rolled] = (diceUsed[rolled] or 0) + 1
            if rolled >= ctx.dice then
                weeksWithDice = weeksWithDice + 1
                for i, ev in ipairs(list) do -- what came before his last die, and what came after it
                    if i <= lastRolled then beforeSum, beforeN = beforeSum + (ev.points or 0), beforeN + 1
                    else afterSum, afterN = afterSum + (ev.points or 0), afterN + 1 end
                end
            end
        elseif not current then
            quiet = quiet + 1
        end
        if not current then
            if sc.off then offWeeks = offWeeks + 1 end
            if sc.winner == "group" then groupWins = groupWins + 1
            elseif sc.winner == "zennit" then zennitWins = zennitWins + 1
            else noWinner = noWinner + 1 end
            if list and not sc.off then
                local n = sc.counted or #list
                for _, b in ipairs(buckets) do
                    if n >= b[2] and n <= b[3] then
                        won[b[1]] = won[b[1]] or { 0, 0 }
                        won[b[1]][2] = won[b[1]][2] + 1
                        if sc.winner == "group" then won[b[1]][1] = won[b[1]][1] + 1 end
                    end
                end
            end
            if sc.closed then closedWeeks, closedAt = closedWeeks + 1, closedAt + (sc.counted or 0) end
            if ctx.whim(start) and not sc.off then
                whimWeeks = whimWeeks + 1
                if sc.winner then
                    whimDone = whimDone + 1
                    if sc.winner == "group" then whimGroup = whimGroup + 1 end
                end
            end
        end
    end

    local out = {}
    local function add(text) out[#out + 1] = text end
    local weeksSpan = math.floor((ctx.nowStart - first) / WEEK) + 1
    add(string.format("PLAYTEST REPORT: %s of the log (the current one included), %d summons of Zennit.",
        plural(weeksSpan, "week"), total))
    add(string.format("Weeks: %d with a summons of him, %d without; he was on leave for %d. Summons a week when played: %s (1-2: %d, 3-4: %d, 5-6: %d, 7+: %d).",
        active, quiet, offWeeks, mean(total, active), dist["1-2"], dist["3-4"], dist["5-6"], dist["7+"]))
    add(string.format("Finished weeks: the group won %d, Zennit %d, nobody %d.", groupWins, zennitWins, noWinner))
    local tries = {}
    for _, b in ipairs(buckets) do
        local w = won[b[1]]
        if w then tries[#tries + 1] = string.format("%s: %d of %d", b[1], w[1], w[2]) end
    end
    if #tries > 0 then add("The group's wins by how many summons counted: " .. table.concat(tries, "; ") .. ".") end
    if whimWeeks > 0 then
        add(string.format("Whim weeks: %d, the group won %d of the %d decided.", whimWeeks, whimGroup, whimDone))
    end
    local order = { "accepted", "refused", "excused", "declined", "away", "owed", "paid", "won", "lost" }
    local mix = {}
    for _, k in ipairs(order) do
        if answers[k] then mix[#mix + 1] = string.format("%s %d", k == "won" and "dice won" or k == "lost" and "dice lost" or k, answers[k]) end
    end
    local delay = median(answerDelays)
    add(string.format("His answers: %s; unanswered %d%s.", #mix > 0 and table.concat(mix, ", ") or "none yet", unanswered,
        delay and string.format("; median time to answer %s", delay < 120 and (delay .. " s") or string.format("%d min", math.floor(delay / 60))) or ""))
    add(string.format("Dice: %d rolled in %d weeks (%s of rolls on the first three summons of a week). A rolled summons was worth %s on average, an unrolled one %s.",
        diceTotal, active, pct(diceOnFirstThree, diceTotal), mean(rolledSum, rolledN), mean(plainSum, plainN)))
    if weeksWithDice > 0 then
        add(string.format("In the %s he spent every die, the summons up to the last die were worth %s, and those after it %s (%d of them).",
            plural(weeksWithDice, "week"), mean(beforeSum, beforeN), mean(afterSum, afterN), afterN))
    end
    add(string.format("The list: %s of his answers were on it. Helpers on a summons: none %s, one %s, two %s. Rolls the helpers tipped: %d.",
        pct(listed, answered), pct(helpers[0], total), pct(helpers[1], total), pct(helpers[2], total), ctx.tipped or 0))
    add(string.format("He closed the Index in %d of the finished weeks%s.", closedWeeks,
        closedWeeks > 0 and string.format(" (after %s filed, on average)", mean(closedAt, closedWeeks)) or ""))
    return out
end

-- The live report from this client's log.
function Report.Lines()
    local W = ST.Week
    local now = time()
    local facts = ST.Ledger.Collect(ST.db.events, 0, math.huge, ST.Ledger.Context())
    return Report.Build({
        events = ST.db.events, isZennit = W.IsZennit, weekStart = W.Start, nowStart = W.Start(now), score = W.Score,
        whim = function(start) return (W.Whim(start)) end, dice = W.RULES.dice, tipped = facts.tippedCount })
end
