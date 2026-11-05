-- Scoring: zone value table, points and badge rules. Placeholder values to argue about.
local ADDON, ST = ...
local Scoring = {}
ST.Scoring = Scoring

Scoring.kindPoints = { city = 1, zone = 3, dungeon = 5, remote = 10 }
Scoring.defaultKind = "zone"

-- Keyed by uiMapID. Unlisted maps score as the default kind.
-- Capital cities (classic uiMapIDs; confirm in game with /sc where).
Scoring.mapKinds = {}
-- The names are what the Index expects each map to be called, so /sc places can ask the game and catch a wrong ID.
local cities = {
    [1453] = "Stormwind City", [1455] = "Ironforge", [1457] = "Darnassus",
    [1454] = "Orgrimmar", [1456] = "Thunder Bluff", [1458] = "Undercity",
}
for id in pairs(cities) do Scoring.mapKinds[id] = "city" end
Scoring.cityNames = cities

-- Far-flung places: a long way from anywhere a friend would be, so a summon there is worth the most.
-- Classic uiMapIDs written from memory: confirm each with /sc where before trusting it.
local remote = {
    [1451] = "Silithus", [1452] = "Winterspring", [1447] = "Azshara", [1448] = "Felwood",
    [1449] = "Un'Goro Crater", [1423] = "Eastern Plaguelands", [1428] = "Burning Steppes",
    [1419] = "Blasted Lands", [1430] = "Deadwind Pass", [1450] = "Moonglade",
}
for id in pairs(remote) do Scoring.mapKinds[id] = "remote" end
Scoring.remoteNames = remote -- for reference and the self-test

-- A dungeon entrance sits in an ordinary outdoor map, so it is matched by subzone text
-- (lowercase). Stand at the spot and run /sc where to learn the exact string, then add it.
Scoring.subzoneKinds = {
    ["the deadmines"] = "dungeon",
    -- Outdoor dungeon entrances, from memory (unverified): confirm each with /sc where and fix the text here.
    ["wailing caverns"] = "dungeon",
    ["shadowfang keep"] = "dungeon",
    ["blackfathom deeps"] = "dungeon",
    ["gnomeregan"] = "dungeon",
    ["razorfen kraul"] = "dungeon",
    ["razorfen downs"] = "dungeon",
    ["scarlet monastery"] = "dungeon",
    ["uldaman"] = "dungeon",
    ["zul'farrak"] = "dungeon",
    ["maraudon"] = "dungeon",
    ["the temple of atal'hakkar"] = "dungeon",
    ["blackrock mountain"] = "dungeon",
}

function Scoring.Kind(mapID, subzone)
    local sz = type(subzone) == "string" and subzone:lower() or nil
    return (sz and Scoring.subzoneKinds[sz]) or Scoring.mapKinds[mapID] or Scoring.defaultKind
end

function Scoring.Score(mapID, subzone)
    local kind = Scoring.Kind(mapID, subzone)
    return Scoring.kindPoints[kind] or Scoring.kindPoints[Scoring.defaultKind], kind
end

-- How a place reads in a sentence ("a city", "a zone"...), for the lines that say what a summons is worth.
Scoring.kindText = { city = "a city", zone = "a zone", dungeon = "a dungeon entrance", remote = "a far-flung place" }

-- What /sc places prints, as a list of lines. nameOf(mapID) is the client's name for a map, or nil when it has none
-- (injected so the self-test can run without the game). A map the client does not know, or names differently, is flagged:
-- that entry is a guess to fix. Dungeon entrances are matched by subzone text, which the game cannot look up.
function Scoring.Places(nameOf)
    local kp = Scoring.kindPoints
    local out = {
        string.format("The Index values a place so: a city %d, a dungeon entrance %d, a far-flung place %d, anywhere else %d.",
            kp.city, kp.dungeon, kp.remote, kp.zone),
    }
    local function group(label, names)
        local ids = {}
        for id in pairs(names) do ids[#ids + 1] = id end
        table.sort(ids)
        local parts, wrong = {}, 0
        for _, id in ipairs(ids) do
            local got = nameOf(id)
            if got == nil then
                parts[#parts + 1] = string.format("%s (%d: the client has no such map)", names[id], id)
                wrong = wrong + 1
            elseif got:lower() ~= names[id]:lower() then
                parts[#parts + 1] = string.format("%s (%d: the client calls it '%s')", names[id], id, got)
                wrong = wrong + 1
            else
                parts[#parts + 1] = names[id]
            end
        end
        out[#out + 1] = string.format("%s: %s.", label, table.concat(parts, ", "))
        return wrong
    end
    local wrong = group("Cities", Scoring.cityNames) + group("Far-flung", Scoring.remoteNames)
    local subs = {}
    for sz in pairs(Scoring.subzoneKinds) do subs[#subs + 1] = sz end
    table.sort(subs)
    out[#out + 1] = "Dungeon entrances, matched by subzone text: " .. table.concat(subs, ", ") .. "."
    out[#out + 1] = wrong == 0 and "The client knows every map above by the name the Index expects."
        or string.format("%d map%s above did not match the client: fix the ID in Scoring.lua. ", wrong, wrong == 1 and "" or "s") ..
            "Dungeon entrances cannot be looked up: stand at one and run /sc where."
    return out
end

-- Badges: threshold rules over the summons the player cast. stats comes from Store.Stats.
Scoring.badges = {
    -- name: how the Index would put it (design/voice.md); how: what it takes, said plainly. The ids are what is saved.
    { id = "first-summon", name = "Entered in the Index", how = "cast a summons",
        test = function(s) return s.cast >= 1 end },
    { id = "summons-10", name = "Filed in Triplicate", how = "cast ten summons that land",
        test = function(s) return s.cast >= 10 end },
    { id = "summons-50", name = "A Volume of Their Own", how = "cast fifty summons that land",
        test = function(s) return s.cast >= 50 end },
    { id = "dungeon-1", name = "Admitted Below Stairs", how = "summon someone to a dungeon entrance",
        test = function(s) return (s.kinds.dungeon or 0) >= 1 end },
    { id = "far-flung-1", name = "Beyond the Index's Jurisdiction", how = "summon someone to a far-flung place",
        test = function(s) return (s.kinds.remote or 0) >= 1 end },
    { id = "variety-5", name = "Stamped in Five Places", how = "summon to five different places",
        test = function(s) return s.distinctMaps >= 5 end },
    -- spread across the season rather than front-loaded (design/lenses.md, Reward); for the people who cast
    { id = "regular", name = "Known to the Clerk", how = "summon Zennit in four different weeks",
        test = function(s) return (s.extra.weekCount or 0) >= 4 end },
    { id = "well-supported", name = "Countersigned by Witnesses", how = "have your helpers tip a roll of yours",
        test = function(s) return (s.extra.tipped or 0) >= 1 end },
    { id = "clean-slate", name = "Paid in Full, No Receipt", how = "pay what you owe Zennit",
        test = function(s) return (s.extra.paid or 0) > 0 and (s.extra.owed or 0) == 0 end },
    { id = "card-sharp", name = "Stamped to the Last Punch", how = "use up a summon card",
        test = function(s) return (s.cardsUsedUp or 0) >= 1 end },
}

-- After an answer or a payment changes what the log says about me: award and say any badge that has just been earned.
function Scoring.Announce()
    if ST.Gag and ST.Gag.IsZennit() then return end -- his tally and badges are hidden
    for _, name in ipairs(Scoring.EvaluateBadges()) do ST.print("|cffffd100Badge earned:|r " .. name) end
end

-- What a character qualifies for (stats as Store.Stats gives them, plus the ledger's figures and the cards it used up).
local function statsOf(name)
    local stats = ST.Store.Stats(name)
    stats.extra = ST.Ledger and ST.Ledger.CasterStats(name) or {}
    stats.cardsUsedUp = ST.Cards and ST.Cards.Exhausted(name) or 0
    return stats
end

-- Adds to `got` every badge `name` now meets and does not hold yet. Returns their names.
local function award(name, got)
    local stats, earned = statsOf(name), {}
    for _, b in ipairs(Scoring.badges) do
        if not got[b.id] and b.test(stats) then
            got[b.id] = { earned = time() }
            earned[#earned + 1] = b.name
        end
    end
    return earned
end

-- The badges a character holds (default: the one being played), as { id = { earned } }. Badges are earned per character
-- (Store.Stats counts what that character cast), but the saved variables are the account's, so they are kept per character
-- in db.badgesBy. A character with no entry yet (each one, the first time this version runs) takes the badges it already
-- qualifies for, quietly: nothing is announced twice, and nobody loses a badge they earned. The old account-wide db.badges is
-- left where it is, unused.
function Scoring.Badges(name)
    name = name or ST.Sync.myName()
    ST.db.badgesBy = ST.db.badgesBy or {}
    local got = ST.db.badgesBy[name]
    if not got then
        got = {}
        ST.db.badgesBy[name] = got
        award(name, got)
    end
    return got
end

-- Awards any newly met badges to the character being played. Returns a list of the badge names earned just now.
function Scoring.EvaluateBadges()
    local me = ST.Sync.myName()
    return award(me, Scoring.Badges(me))
end
