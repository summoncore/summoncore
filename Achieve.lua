-- Achieve: the achievements. One for every thing the Index keeps count of: summons cast, received and helped with, points, the
-- places, the race for Zennit (his summons, the weeks, the dice his helpers tipped, the writs, his week off, the postcards),
-- the silver and the cards, the fish given to him, the snowballs thrown at him, and the story. Each is a count and a goal, so
-- the ones not earned yet show how far along they are. They began as the ten badges (the ids of those are unchanged, and what
-- a character had earned is kept); they are earned per character and kept in db.badgesBy. /sc achievements, and the Party
-- tab's Achievements section. Hidden on Zennit's client, as his tally is.
local ADDON, ST = ...
local Achieve = {}
ST.Achieve = Achieve

-- Raised whenever the list below gains an entry: a character whose saved achievements were worked out under an older list
-- takes the new ones it already qualifies for quietly, the first time this version looks (Achieve.Badges).
Achieve.RULES = 2

Achieve.groups = {
    { "cast", "Casting" }, { "party", "Summoned and helping" }, { "places", "Places" }, { "race", "The race for Zennit" },
    { "silver", "Silver and cards" }, { "gifts", "Fish and snowballs" }, { "story", "The story" },
}

----------------------------------------------------------------------
-- The figures: everything the addon tracks about one character, worked out a part at a time and only when a rule asks
----------------------------------------------------------------------
local parts = {}

-- the summons this character cast, received and helped with (only those that landed; test summons never)
function parts.log(s, name)
    local st = ST.Store.Stats(name)
    local t = ST.Store.Tallies()[name]
    s.cast, s.points, s.kinds, s.distinctMaps = st.cast, st.points, st.kinds, st.distinctMaps
    s.received, s.assisted = t and t.received or 0, t and t.assisted or 0
end

-- what the log says of this character in the race: every summons of Zennit, of every season
function parts.ledger(s, name)
    local base = ST.baseName(name) or name
    local d = ST.Ledger.Collect(ST.db.events, 0, math.huge, ST.Ledger.Context())
    local by = d.by[base] or {}
    s.ofZennit, s.weekCount, s.tipped = by.summons or 0, by.weekCount or 0, by.tipped or 0
    s.paid, s.owed, s.weeks = by.paid or 0, by.owed or 0, by.weeks or {}
    s.helperTips, s.writPoints, s.onLeave = d.helperTips[base] or 0, d.writs[base] or 0, d.leave.by[base] or 0
    s.postcards = 0
    for _, card in ipairs(d.postcards) do
        if card.caster == base then s.postcards = s.postcards + 1 end
    end
end

-- the weeks and the seasons the group won that this character summoned him in
function parts.season(s)
    local season, weeks = ST.Week.Season(), s.weeks
    s.weeksWon, s.seasonsWon = 0, 0
    for _, ch in ipairs(season.chapters) do
        if ch.side == "group" and weeks[ch.start] then s.weeksWon = s.weeksWon + 1 end
    end
    for _, f in ipairs(season.finales) do
        local there = false
        for week in pairs(weeks) do
            if week >= f.from and week <= f.start then there = true end
        end
        if f.side == "group" and there then s.seasonsWon = s.seasonsWon + 1 end
    end
end

-- what is counted outside the log: the cards, the fish book (his client shares each giver's total), this client's snowballs
function parts.gifts(s, name)
    local base = ST.baseName(name) or name
    s.cardsUsedUp = ST.Cards and ST.Cards.Exhausted(name) or 0
    s.fish, s.snowballs = 0, 0
    for _, row in ipairs(ST.Fish and ST.Fish.Board() or {}) do
        if row.name == base then s.fish = row.count end
    end
    -- the snowballs are this client's own count, so they are the character being played's
    if ST.Snowball and base == (ST.baseName(ST.Sync.myName()) or ST.Sync.myName()) then s.snowballs = (ST.Snowball.Mine()) end
end

-- what this player has seen and said (kept with the settings)
function parts.story(s)
    local set = ST.db.settings or {}
    s.introWatched = set.introWatched and 1 or 0
    s.tourSeen = set.tourSeen and 1 or 0
    s.opinions = (set.feelMine and next(set.feelMine)) and 1 or 0 -- old answers are pruned; one earned is kept
end

local PART_OF = {
    cast = "log", points = "log", kinds = "log", distinctMaps = "log", received = "log", assisted = "log",
    ofZennit = "ledger", weekCount = "ledger", tipped = "ledger", paid = "ledger", owed = "ledger", weeks = "ledger",
    helperTips = "ledger", writPoints = "ledger", onLeave = "ledger", postcards = "ledger",
    weeksWon = "season", seasonsWon = "season",
    cardsUsedUp = "gifts", fish = "gifts", snowballs = "gifts",
    introWatched = "story", tourSeen = "story", opinions = "story",
}

-- Every figure for `name` (as the log writes it). A field is worked out, with the rest of its part, the first time it is read.
function Achieve.Stats(name)
    return setmetatable({}, { __index = function(s, key)
        local part = PART_OF[key]
        if not part then return nil end
        parts[part](s, name)
        return rawget(s, key)
    end })
end

----------------------------------------------------------------------
-- The list. id: what is saved (never change one). name: how the Index would put it (design/voice.md). how: what it takes,
-- said plainly. value(stats) against goal is the progress; it is earned when value reaches goal.
----------------------------------------------------------------------
local function kind(k) return function(s) return s.kinds[k] or 0 end end
local function field(k) return function(s) return s[k] end end

Achieve.list = {
    -- casting
    { id = "first-summon", group = "cast", name = "Entered in the Index", how = "cast a summons", value = field("cast"), goal = 1 },
    { id = "summons-10", group = "cast", name = "Filed in Triplicate", how = "cast ten summons that land", value = field("cast"), goal = 10 },
    { id = "summons-50", group = "cast", name = "A Volume of Their Own", how = "cast fifty summons that land", value = field("cast"), goal = 50 },
    { id = "summons-100", group = "cast", name = "A Shelf of Their Own", how = "cast a hundred summons that land", value = field("cast"), goal = 100 },
    { id = "points-50", group = "cast", name = "Fifty Points, Itemised", how = "earn fifty points", value = field("points"), goal = 50 },
    { id = "points-250", group = "cast", name = "The Index Ran Out of Columns", how = "earn two hundred and fifty points", value = field("points"), goal = 250 },
    -- summoned, and helping
    { id = "received-1", group = "party", name = "Delivered, Signed For", how = "be summoned", value = field("received"), goal = 1 },
    { id = "received-10", group = "party", name = "Frequently Forwarded", how = "be summoned ten times", value = field("received"), goal = 10 },
    { id = "received-25", group = "party", name = "No Fixed Address", how = "be summoned twenty-five times", value = field("received"), goal = 25 },
    { id = "assist-1", group = "party", name = "A Hand on the Portal", how = "help with a summons", value = field("assisted"), goal = 1 },
    { id = "assist-10", group = "party", name = "A Reliable Witness", how = "help with ten summons", value = field("assisted"), goal = 10 },
    { id = "assist-50", group = "party", name = "Notary to the Ritual", how = "help with fifty summons", value = field("assisted"), goal = 50 },
    -- places
    { id = "dungeon-1", group = "places", name = "Admitted Below Stairs", how = "summon someone to a dungeon entrance", value = kind("dungeon"), goal = 1 },
    { id = "dungeon-10", group = "places", name = "A Regular Below Stairs", how = "summon to a dungeon entrance ten times", value = kind("dungeon"), goal = 10 },
    { id = "far-flung-1", group = "places", name = "Beyond the Index's Jurisdiction", how = "summon someone to a far-flung place", value = kind("remote"), goal = 1 },
    { id = "far-flung-5", group = "places", name = "Long-Distance Carrier", how = "summon to a far-flung place five times", value = kind("remote"), goal = 5 },
    { id = "city-10", group = "places", name = "The Commuter's Stamp", how = "summon to a city ten times", value = kind("city"), goal = 10 },
    { id = "variety-5", group = "places", name = "Stamped in Five Places", how = "summon to five different places", value = field("distinctMaps"), goal = 5 },
    { id = "variety-15", group = "places", name = "The Atlas, Annotated", how = "summon to fifteen different places", value = field("distinctMaps"), goal = 15 },
    { id = "postcard-1", group = "places", name = "Wish You Were Here", how = "be the first to get Zennit to a far-flung place (his postcard is yours)", value = field("postcards"), goal = 1 },
    { id = "postcard-3", group = "places", name = "A Rack of Postcards", how = "be the first to get Zennit to three far-flung places", value = field("postcards"), goal = 3 },
    -- the race for Zennit
    { id = "zennit-1", group = "race", name = "Served the Summons", how = "summon Zennit", value = field("ofZennit"), goal = 1 },
    { id = "zennit-10", group = "race", name = "A Repeat Offender", how = "summon Zennit ten times", value = field("ofZennit"), goal = 10 },
    { id = "zennit-50", group = "race", name = "His Standing Appointment", how = "summon Zennit fifty times", value = field("ofZennit"), goal = 50 },
    { id = "regular", group = "race", name = "Known to the Clerk", how = "summon Zennit in four different weeks", value = field("weekCount"), goal = 4 },
    { id = "regular-10", group = "race", name = "On First-Name Terms with the Clerk", how = "summon Zennit in ten different weeks", value = field("weekCount"), goal = 10 },
    { id = "week-won", group = "race", name = "On the Winning Side", how = "summon Zennit in a week the group wins", value = field("weeksWon"), goal = 1 },
    { id = "weeks-won-5", group = "race", name = "Five Weeks to the Good", how = "summon Zennit in five weeks the group wins", value = field("weeksWon"), goal = 5 },
    { id = "season-won", group = "race", name = "Present at the Finale", how = "summon Zennit in a season the group wins", value = field("seasonsWon"), goal = 1 },
    { id = "well-supported", group = "race", name = "Countersigned by Witnesses", how = "have your helpers tip a roll of yours", value = field("tipped"), goal = 1 },
    { id = "tipper-1", group = "race", name = "The Deciding Vote", how = "be a helper whose bonus tips a roll", value = field("helperTips"), goal = 1 },
    { id = "tipper-5", group = "race", name = "A Thumb on the Scale", how = "be a helper whose bonus tips five rolls", value = field("helperTips"), goal = 5 },
    { id = "writ-1", group = "race", name = "Duly Served", how = "play a writ that costs Zennit its points", value = function(s) return s.writPoints > 0 and 1 or 0 end, goal = 1 },
    { id = "leave-1", group = "race", name = "Out of Office, Disregarded", how = "summon Zennit on his week off", value = field("onLeave"), goal = 1 },
    -- silver and cards
    { id = "clean-slate", group = "silver", name = "Paid in Full, No Receipt", how = "pay what you owe Zennit",
        value = function(s) return (s.paid > 0 and s.owed == 0) and 1 or 0 end, goal = 1 },
    { id = "patron", group = "silver", name = "A Friend of the Treasury", how = "pay Zennit two hundred silver in all", value = field("paid"), goal = 200 },
    { id = "card-sharp", group = "silver", name = "Stamped to the Last Punch", how = "use up a summon card", value = field("cardsUsedUp"), goal = 1 },
    -- fish and snowballs
    { id = "fish-1", group = "gifts", name = "Something Fishy on File", how = "give Zennit a fish", value = field("fish"), goal = 1 },
    { id = "fish-20", group = "gifts", name = "Fishmonger to the Index", how = "give Zennit twenty fish", value = field("fish"), goal = 20 },
    { id = "fish-100", group = "gifts", name = "The Whole Catch", how = "give Zennit a hundred fish", value = field("fish"), goal = 100 },
    { id = "snow-1", group = "gifts", name = "A Cold Case", how = "hit Zennit with a snowball", value = field("snowballs"), goal = 1 },
    { id = "snow-25", group = "gifts", name = "A Flurry of Filings", how = "hit Zennit with twenty-five snowballs", value = field("snowballs"), goal = 25 },
    { id = "snow-100", group = "gifts", name = "Avalanche, Unsigned", how = "hit Zennit with a hundred snowballs", value = field("snowballs"), goal = 100 },
    -- the story
    { id = "intro", group = "story", name = "Read the Preamble", how = "watch the story from its first scene to its last (/sc intro)", value = field("introWatched"), goal = 1 },
    { id = "tour", group = "story", name = "Shown Round the Stacks", how = "take the tour to its end (/sc tour)", value = field("tourSeen"), goal = 1 },
    { id = "opinion", group = "story", name = "Feedback, Duly Filed", how = "answer the Index's weekly question", value = field("opinions"), goal = 1 },
}

----------------------------------------------------------------------
-- Earning them
----------------------------------------------------------------------
-- Adds to `got` every achievement `name` now meets and does not hold yet. Returns their names.
local function award(name, got)
    local stats, earned = Achieve.Stats(name), {}
    for _, a in ipairs(Achieve.list) do
        if not got[a.id] and (a.value(stats) or 0) >= a.goal then
            got[a.id] = { earned = time() }
            earned[#earned + 1] = a.name
        end
    end
    return earned
end

-- The achievements a character holds (default: the one being played), as { id = { earned } }. They are earned per character,
-- but the saved variables are the account's, so they are kept per character in db.badgesBy. A character with no entry yet, or
-- one whose entry was worked out under an older list (db.badgesRules), takes what it already qualifies for, quietly: nothing
-- is announced late, and nobody loses one they earned. The old account-wide db.badges is left where it is, unused.
function Achieve.Badges(name)
    name = name or ST.Sync.myName()
    ST.db.badgesBy = ST.db.badgesBy or {}
    ST.db.badgesRules = ST.db.badgesRules or {}
    local got = ST.db.badgesBy[name]
    if not got then
        got = {}
        ST.db.badgesBy[name] = got
    end
    if ST.db.badgesRules[name] ~= Achieve.RULES then
        ST.db.badgesRules[name] = Achieve.RULES
        award(name, got)
    end
    return got
end

-- Awards any newly met achievements to the character being played. Returns a list of the names earned just now.
function Achieve.Evaluate()
    local me = ST.Sync.myName()
    return award(me, Achieve.Badges(me))
end

-- Says the achievements just earned (a list of names, as Achieve.Evaluate and Store.Add return them).
function Achieve.Say(names)
    for _, name in ipairs(names or {}) do ST.print("|cffffd100Achievement earned:|r " .. name) end
end

-- After something changes what is counted for me (an answer, a payment, a fish, a snowball): award and say what has just been
-- earned. Nothing on Zennit's client: his tally and achievements are hidden.
function Achieve.Announce()
    if not ST.db or (ST.Gag and ST.Gag.IsZennit()) then return end
    Achieve.Say(Achieve.Evaluate())
end

-- The same, a moment from now and once however many times it is asked for: for what arrives in a burst (a sync batch).
local waiting = false
function Achieve.Soon()
    if waiting or not (C_Timer and C_Timer.After) then return end
    waiting = true
    C_Timer.After(2, ST.Safe("the achievements", function()
        waiting = false
        Achieve.Announce()
        if ST.Hub then ST.Hub.Refresh() end
    end))
end

----------------------------------------------------------------------
-- Showing them
----------------------------------------------------------------------
-- Every achievement for the character being played, in the list's order: { def, got (or nil), value, goal }, with how many
-- are earned. Read-only: nothing is awarded here.
function Achieve.Rows()
    local me = ST.Sync.myName()
    local got, stats = Achieve.Badges(me), Achieve.Stats(me)
    local rows, earned = {}, 0
    for _, a in ipairs(Achieve.list) do
        local value = math.max(0, math.min(a.value(stats) or 0, a.goal))
        if got[a.id] then earned = earned + 1 end
        rows[#rows + 1] = { def = a, got = got[a.id], value = got[a.id] and a.goal or value, goal = a.goal }
    end
    return rows, earned
end

-- For the chat window. Short: how many are earned, the newest few, and the ones closest to being earned. all = true: every
-- one, by group, with its progress.
function Achieve.Lines(all)
    local rows, earned = Achieve.Rows()
    local lines = { string.format("|cffffd100Achievements|r: %d of %d earned.", earned, #rows) }
    if all then
        for _, g in ipairs(Achieve.groups) do
            lines[#lines + 1] = g[2] .. ":"
            for _, r in ipairs(rows) do
                if r.def.group == g[1] then
                    lines[#lines + 1] = r.got and string.format("   |cff33ff66[x]|r %s (%s)", r.def.name, date("%Y-%m-%d", r.got.earned))
                        or string.format("   [ ] %s: %s (%d/%d)", r.def.name, r.def.how, r.value, r.goal)
                end
            end
        end
        return lines
    end
    local have, near = {}, {}
    for i, r in ipairs(rows) do
        r.order = i
        if r.got then have[#have + 1] = r else near[#near + 1] = r end
    end
    table.sort(have, function(a, b)
        if a.got.earned ~= b.got.earned then return a.got.earned > b.got.earned end
        return a.order > b.order
    end)
    table.sort(near, function(a, b)
        local fa, fb = a.value / a.goal, b.value / b.goal
        if fa ~= fb then return fa > fb end
        return a.order < b.order
    end)
    for i = 1, math.min(5, #have) do
        lines[#lines + 1] = string.format("   |cff33ff66[x]|r %s", have[i].def.name)
    end
    if #have > 5 then lines[#lines + 1] = string.format("   and %d more.", #have - 5) end
    if #near > 0 then lines[#lines + 1] = "Next:" end
    for i = 1, math.min(5, #near) do
        local r = near[i]
        lines[#lines + 1] = string.format("   [ ] %s: %s (%d/%d)", r.def.name, r.def.how, r.value, r.goal)
    end
    lines[#lines + 1] = "/sc achievements all lists every one; so does the Party tab's Achievements."
    return lines
end
