-- Scoring: zone value table and points. Placeholder values to argue about. (The achievements are in Achieve.lua.)
local ADDON, ST = ...
setfenv(1, ST.env) -- the addon's own globals (Core.lua)
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
