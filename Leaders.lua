-- Leaders: the leaderboard. Two boards, on every client (Zennit's too: it gives no gag away): who has summoned Zennit most (this
-- week, this season, and in all; the season is what the race counts) and who has given him the most fish (Fish.Board, shared by
-- his client). /sc leaders, the Party tab's Leaders section, and the Tools tab's Leaderboard.
local ADDON, ST = ...
local Leaders = {}
ST.Leaders = Leaders

-- Summons of Zennit by caster: { { name, week, season, all } }, ranked by the season, then in all, then this week, then name.
-- `events` and the window starts are arguments so the self-test can feed its own.
function Leaders.Summons(events, weekStart, seasonStart, ctx)
    local function count(from) return ST.Ledger.Collect(events, from or 0, math.huge, ctx).casters end
    local week, season, all = count(weekStart), count(seasonStart), count(0)
    local rows = {}
    for name, n in pairs(all) do
        rows[#rows + 1] = { name = name, week = week[name] or 0, season = season[name] or 0, all = n }
    end
    table.sort(rows, function(a, b)
        if a.season ~= b.season then return a.season > b.season end
        if a.all ~= b.all then return a.all > b.all end
        if a.week ~= b.week then return a.week > b.week end
        return a.name < b.name
    end)
    return rows
end

-- The summons board for this client's log.
function Leaders.SummonRows()
    return Leaders.Summons(ST.db.events, ST.Week.Start(), ST.Week.Season().since or 0, ST.Ledger.Context())
end

-- Both boards as lines for the chat window: the top `n` of each (default 5).
function Leaders.Lines(n)
    n = n or 5
    local lines = { "|cffffd100The leaderboard|r" }
    local summons = Leaders.SummonRows()
    lines[#lines + 1] = "Summons of Zennit (this season, what the race counts):"
    if #summons == 0 then lines[#lines + 1] = "   nobody has summoned him yet." end
    for i = 1, math.min(n, #summons) do
        local r = summons[i]
        lines[#lines + 1] = string.format("   %d. %s: %d this season, %d this week, %d in all", i, r.name, r.season, r.week, r.all)
    end
    local fish = ST.Fish.Board()
    lines[#lines + 1] = "Fish given to Zennit:"
    if #fish == 0 then lines[#lines + 1] = "   nobody has given him a fish yet." end
    for i = 1, math.min(n, #fish) do
        local r = fish[i]
        lines[#lines + 1] = string.format("   %d. %s: %d fish, %d this week", i, r.name, r.count, r.week)
    end
    return lines
end
