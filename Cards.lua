-- Cards: Zennit sells summon cards, like a coffee card. A card is prepaid silver: N punches, bought once at a price he sets
-- (for example 5 punches for 200 silver, against 250 at the counter). Each time he demands the fifty silver from the holder,
-- a punch pays it and the Index says so. A card is a record Zennit's client issues and everyone keeps (message K); the
-- punches used are not stored anywhere: they are counted from the summons he settled with a punch (answers carrying the card
-- flag), oldest card first, so every client agrees and nothing can drift.
local ADDON, ST = ...
setfenv(1, ST.env) -- the addon's own globals (Core.lua)
local Cards = {}
ST.Cards = Cards

Cards.DEFAULT_OFFER = { punches = 5, silver = 200 }

local function base(name)
    return ST.baseName(name) or name or ""
end

-- A holder as the game writes a name: "bravo" typed in /sc card sell is Bravo. Cards are stored and sent this way.
function Cards.Holder(name)
    local b = base(name)
    return b:sub(1, 1):upper() .. b:sub(2):lower()
end

-- Who a card belongs to, for matching: the plain name in lower case, so a card sold to "bravo" (or saved that way by an
-- earlier version) is Bravo's.
local function key(name)
    return base(name):lower()
end

function Cards.All()
    ST.db.cards = ST.db.cards or {}
    return ST.db.cards
end

-- All cards, oldest first.
function Cards.Sorted()
    local list = {}
    for _, card in pairs(Cards.All()) do list[#list + 1] = card end
    table.sort(list, function(a, b)
        if a.time ~= b.time then return a.time < b.time end
        return a.id < b.id
    end)
    return list
end

-- Punches used so far by each holder: the summons of Zennit they cast that he settled with a punch.
local function usedBy()
    local used = {}
    for _, ev in pairs(ST.db.events) do
        if not ev.fake and ev.response and ev.response.card and ST.Week.IsZennit(ev.target) then
            local who = key(ev.caster)
            used[who] = (used[who] or 0) + 1
        end
    end
    return used
end

-- Every holder's cards with the punches left on each, spending the oldest card first.
-- Returns { holderKey = { cards = { { card, left } }, left = total, bought = total, used = n } }.
function Cards.Balances()
    local used, out = usedBy(), {}
    for _, card in ipairs(Cards.Sorted()) do
        local who = key(card.holder)
        local b = out[who]
        if not b then
            b = { cards = {}, left = 0, bought = 0, used = used[who] or 0, name = Cards.Holder(card.holder) }
            out[who] = b
        end
        b.bought = b.bought + card.punches
        b.cards[#b.cards + 1] = { card = card, left = 0 }
    end
    for _, b in pairs(out) do
        local spend = b.used
        for _, entry in ipairs(b.cards) do
            local take = math.min(spend, entry.card.punches)
            entry.left = entry.card.punches - take
            spend = spend - take
            b.left = b.left + entry.left
        end
    end
    return out
end

-- Punches left for a holder (a character name).
function Cards.Left(holder)
    local b = Cards.Balances()[key(holder)]
    return b and b.left or 0
end

-- Punches left on one card.
function Cards.PunchesLeft(card)
    local b = Cards.Balances()[key(card.holder)]
    if not b then return 0 end
    for _, entry in ipairs(b.cards) do
        if entry.card.id == card.id then return entry.left end
    end
    return 0
end

-- How many of this holder's cards have been used up.
function Cards.Exhausted(holder)
    local b = Cards.Balances()[key(holder)]
    local n = 0
    for _, entry in ipairs(b and b.cards or {}) do
        if entry.left == 0 then n = n + 1 end
    end
    return n
end

-- What one punch is worth for this holder, in silver: the price of their oldest card with a punch left, per punch.
function Cards.UnitPrice(holder)
    local b = Cards.Balances()[key(holder)]
    if b then
        for _, entry in ipairs(b.cards) do
            if entry.left > 0 then return math.max(1, math.floor(entry.card.silver / entry.card.punches + 0.5)) end
        end
    end
    return ST.Respond.SILVER
end

-- What Zennit sells: a list of { punches, silver }; his own, or one default offer.
function Cards.Offers()
    local s = ST.db.settings
    if s and s.cardOffers and #s.cardOffers > 0 then return s.cardOffers end
    return { Cards.DEFAULT_OFFER }
end

-- Sets his offer (one at a time: `/sc card offer 5 200`).
function Cards.SetOffer(punches, silver)
    punches, silver = tonumber(punches), tonumber(silver)
    if not punches or not silver or punches < 1 or punches > 50 or silver < 1 or silver > 100000 then return false end
    ST.db.settings.cardOffers = { { punches = math.floor(punches), silver = math.floor(silver) } }
    return true
end

-- The offer a payment of `silver` buys: the biggest one it covers, or nil.
function Cards.OfferFor(silver)
    local best
    for _, offer in ipairs(Cards.Offers()) do
        if offer.silver <= silver and (not best or offer.silver > best.silver) then best = offer end
    end
    return best
end

-- Sells a card (on Zennit's client only): records it, tells everyone, and says so. Returns the card, or nil and why.
function Cards.Issue(holder, punches, silver)
    if not ST.Week.IsZennit(ST.Sync.myName()) then return nil, "only Zennit can sell cards" end
    holder = Cards.Holder(holder)
    punches, silver = tonumber(punches), tonumber(silver)
    if holder == "" then return nil, "sell it to whom?" end
    if not punches or punches < 1 or punches > 50 then return nil, "a card has 1 to 50 punches" end
    if not silver or silver < 0 or silver > 100000 then return nil, "the price is 0 to 100000 silver" end
    local t = time()
    local id = "card-" .. t
    local n = 1
    while Cards.All()[id] do
        n = n + 1
        id = "card-" .. t .. "-" .. n
    end
    local card = { id = id, holder = holder, punches = math.floor(punches), silver = math.floor(silver), time = t }
    Cards.All()[id] = card
    ST.Sync.SendCard(card)
    ST.print(string.format("The Index has stamped a card for %s: %d punches, paid %d silver.", holder, card.punches, card.silver))
    if ST.Hub then ST.Hub.Refresh() end
    return card
end

-- Lines for chat: every holder's balance (`holder` limits it to one character, for a holder looking at their own).
function Cards.Lines(holder)
    local lines = {}
    local names = {}
    for who in pairs(Cards.Balances()) do names[#names + 1] = who end
    table.sort(names)
    local balances = Cards.Balances()
    for _, who in ipairs(names) do
        if not holder or key(holder) == who then
            local b = balances[who]
            lines[#lines + 1] = string.format("%s: %d of %d punches left, %d already stamped.", b.name, b.left, b.bought, b.used)
        end
    end
    if #lines == 0 then
        lines[1] = holder and "You hold no card. Zennit sells them." or "No card has been sold."
    end
    return lines
end

-- A card has arrived from Zennit (Sync): say who now holds one.
ST.Sync.onCard = function(card)
    if ST.Sync.quiet then return end
    ST.print(string.format("The Index records that Zennit has sold %s a card: %d punches, paid %d silver.", card.holder, card.punches, card.silver))
    if ST.Hub then ST.Hub.Refresh() end
end
