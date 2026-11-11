-- Fish: the other thing friends hand Zennit. Fish come to him the way silver does, by trade or by mail (loose, or wrapped in a
-- present, counted when he opens it), and on his client only this module counts them: each fish taken from a mail or received in a
-- completed trade goes into the fish book (ST.db.fish) with who
-- gave it, what it was and how many. Nothing is asked and nothing in the race changes; it is a tally he can read with /sc fish
-- (also the Tools tab's Fish). The book itself stays on his client; each giver's totals are shared with everyone (message P), so the
-- leaderboard (Leaders.lua) can rank the givers on every client.
local ADDON, ST = ...
setfenv(1, ST.env) -- the addon's own globals (Core.lua)
local Fish = {}
ST.Fish = Fish

-- The fish of the old world, raw and cooked, by item ID. A name the list does not know is still a fish if one of its words is a
-- fish word (Fish.IsFish), so a fish missing here is caught all the same.
Fish.IDS = {
    [6291] = true, [6303] = true, [6289] = true, [6317] = true, [6361] = true, [6308] = true, [6362] = true, [21071] = true,
    [4603] = true, [8365] = true, [6358] = true, [6359] = true, [13754] = true, [13756] = true, [13758] = true, [13759] = true,
    [13760] = true, [13889] = true, [13888] = true, [21153] = true, [12238] = true, [13422] = true,
    [787] = true, [4592] = true, [4593] = true, [4594] = true, [5095] = true, [6290] = true, [6887] = true, [8364] = true,
    [13927] = true, [13929] = true, [13930] = true, [13932] = true, [13933] = true, [13934] = true, [13935] = true,
}

-- Words that make a name a fish. Any word ending in "fish" counts too (catfish, sagefish, smallfish, mightfish).
local WORDS = {}
for _, w in ipairs({ "snapper", "mackerel", "cod", "albacore", "yellowtail", "trout", "salmon", "bass", "redgill", "eel",
    "grouper", "lobster", "frenzy", "blackmouth", "perch", "carp", "pike", "tuna", "herring", "minnow", "sardine", "halibut",
    "mullet", "flounder", "squid" }) do
    WORDS[w] = true
end
-- Words that make a name NOT a fish however fishy the rest: tools, bait and the like.
local NOT = { pole = true, rod = true, lure = true, bait = true, hat = true, recipe = true, net = true, line = true }

-- Is this item a fish? By its ID if the list knows it, else by the words of its name.
function Fish.IsFish(name, itemID)
    if itemID and Fish.IDS[itemID] then return true end
    if type(name) ~= "string" then return false end
    local fishy = false
    for word in name:lower():gmatch("%a+") do
        if NOT[word] then return false end
        if WORDS[word] or word:find("fish$") then fishy = true end
    end
    return fishy
end

local function secret(v)
    return ST.isSecret and ST.isSecret(v)
end

local function base(name)
    return ST.baseName(name) or name or ""
end

local function book()
    ST.db.fish = ST.db.fish or {}
    return ST.db.fish
end

-- `count` of the fish `item` (a name; itemID optional) has arrived from `from` by `via` ("trade", "mail" or "hand", written in by
-- Zennit). Returns the entry, or nil and why.
function Fish.Add(from, item, count, via, itemID)
    from = base(from)
    count = tonumber(count)
    if from == "" then return nil, "from whom?" end
    if not count or count < 1 or count > 100000 then return nil, "a count of 1 to 100000 fish" end
    local entry = { from = from, item = item or "fish", itemID = itemID, count = math.floor(count), via = via or "hand", time = time() }
    local list = book()
    list[#list + 1] = entry
    Fish.Share(entry.from)
    if ST.Hub then ST.Hub.Refresh() end
    return entry
end

-- Takes the newest entry out of the book; returns it, or nil when the book is empty.
function Fish.Undo()
    local entry = table.remove(book())
    if entry then
        Fish.Share(entry.from)
        if ST.Hub then ST.Hub.Refresh() end
    end
    return entry
end

-- Tells everyone one giver's totals now (0 takes them off the board).
function Fish.Share(giver)
    if not (ST.Sync and ST.Sync.SendFish) then return end
    local weekStart = ST.Week.Start()
    local total, week = 0, 0
    for _, e in ipairs(book()) do
        if e.from == giver then
            total = total + e.count
            if e.time >= weekStart then week = week + e.count end
        end
    end
    ST.Sync.SendFish(giver, total, week, weekStart)
end

-- The givers, most fish first: { { name, count, week } }. Zennit's client reads its own book; everyone else the totals his client
-- has shared (a week count from an earlier week is 0 now).
function Fish.Board()
    local rows = {}
    local weekStart = ST.Week.Start()
    if ST.Gag.IsZennit() then
        local all = Fish.Totals(book())
        local week = {}
        for _, g in ipairs((Fish.Totals(book(), weekStart))) do week[g.name] = g.count end
        for _, g in ipairs(all) do rows[#rows + 1] = { name = g.name, count = g.count, week = week[g.name] or 0 } end
    else
        for _, line in pairs(ST.db.fishBoard or {}) do
            if line.count > 0 then
                rows[#rows + 1] = { name = line.name, count = line.count, week = line.weekStart == weekStart and line.week or 0 }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    return rows
end

-- Fish from each giver, most first: { { name, count, items = { [item] = count }, last } }, and the total.
function Fish.Totals(list, since)
    local who, order, total = {}, {}, 0
    for _, e in ipairs(list or {}) do
        if not since or e.time >= since then
            local g = who[e.from]
            if not g then
                g = { name = e.from, count = 0, items = {}, last = 0 }
                who[e.from] = g
                order[#order + 1] = g
            end
            g.count = g.count + e.count
            g.items[e.item] = (g.items[e.item] or 0) + e.count
            g.last = math.max(g.last, e.time)
            total = total + e.count
        end
    end
    table.sort(order, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    return order, total
end

-- "10 Raw Rockscale Cod, 2 Raw Sagefish": the most first.
local function itemsLine(items)
    local names = {}
    for item in pairs(items) do names[#names + 1] = item end
    table.sort(names, function(a, b)
        if items[a] ~= items[b] then return items[a] > items[b] end
        return a < b
    end)
    local parts = {}
    for _, item in ipairs(names) do parts[#parts + 1] = items[item] .. " " .. item end
    return table.concat(parts, ", ")
end

-- The fish book as lines: on Zennit's client, who has given him what, this week and in all; anyone else gets the givers' totals
-- his client has shared.
function Fish.Lines()
    if not ST.Gag.IsZennit() then
        local rows = Fish.Board()
        if #rows == 0 then
            return { "Nobody has given Zennit a fish yet, as far as his client has told this one. Trade or mail him one: it is counted there." }
        end
        local lines, total = {}, 0
        for _, r in ipairs(rows) do
            total = total + r.count
            lines[#lines + 1] = string.format("%s: %d fish, %d of them this week.", r.name, r.count, r.week)
        end
        table.insert(lines, 1, string.format("The fish book, as Zennit's client shares it: %d fish given to him.", total))
        return lines
    end
    local list = book()
    local all, total = Fish.Totals(list)
    if total == 0 then
        return { "The fish book is empty. Fish traded or mailed to you are counted here (/sc fish add <name> <count> writes one in by hand)." }
    end
    local _, week = Fish.Totals(list, ST.Week and ST.Week.Start and ST.Week.Start() or nil)
    local lines = { string.format("The fish book: %d fish given to Zennit, %d of them this week.", total, week) }
    for _, g in ipairs(all) do
        lines[#lines + 1] = string.format("%s: %d (%s), the last on %s.", g.name, g.count, itemsLine(g.items), date("%d %b", g.last))
    end
    return lines
end

-- Fish have arrived on Zennit's client: into the book, and one line in chat.
-- `text`: what to say in place of "Bo sent you 3 Raw Sagefish by trade." (a present says it was opened).
local function received(from, item, count, via, itemID, text)
    local entry = Fish.Add(from, item, count, via, itemID)
    if not entry then return end
    local mine = 0
    for _, e in ipairs(book()) do
        if e.from == entry.from then mine = mine + e.count end
    end
    ST.print(string.format("%s Into the fish book: %d fish from %s so far.", text or string.format("%s sent you %d %s by %s.",
        entry.from, entry.count, entry.item, via), mine, entry.from))
end

----------------------------------------------------------------------
-- Watching the client (Zennit's only)
----------------------------------------------------------------------
local function call(name, ...)
    local fn = ST.env[name]
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2)
end

-- One call of a function value (C_Container's), or nil if it fails.
local function call2(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2)
end

local function plain(v, kind)
    if v == nil or secret(v) or type(v) ~= kind then return nil end
    return v
end

local function idOf(link)
    link = plain(link, "string")
    return link and tonumber(link:match("item:(%d+)")) or nil
end

-- A fish the client shows in a trade slot or a mail attachment, or nil.
local function fishOf(name, count, itemID)
    name, count, itemID = plain(name, "string"), plain(count, "number"), plain(itemID, "number")
    if not name or not Fish.IsFish(name, itemID) then return nil end
    return { item = name, count = (count and count > 0) and count or 1, itemID = itemID }
end

----------------------------------------------------------------------
-- Wrapped presents: what is inside cannot be seen until he opens one, so a present that arrives from a player (by trade or mail,
-- the same rules as a fish) is noted with who sent it (ST.db.presents). When he opens a present in his bags, the fish in his bags
-- are counted just before; the fish that turn up in the next minute came out of it, and go into the book as the sender's.
----------------------------------------------------------------------
local PRESENT_WORDS = { wrapped = true, present = true, gift = true }
local NOT_PRESENT = { paper = true, wrap = true, wrapping = true, ribbon = true, recipe = true }

-- Is this item a wrapped present? By the words of its name ("Wrapped Gift", "Gaily Wrapped Present"), never the paper.
function Fish.IsPresent(name)
    if type(name) ~= "string" then return false end
    local yes = false
    for word in name:lower():gmatch("%a+") do
        if NOT_PRESENT[word] then return false end
        if PRESENT_WORDS[word] then yes = true end
    end
    return yes
end

local function presentOf(name, count)
    name, count = plain(name, "string"), plain(count, "number")
    if not name or not Fish.IsPresent(name) then return nil end
    return { present = true, item = name, count = (count and count > 0) and count or 1 }
end

local PRESENT_DAYS = 60

local function presents()
    ST.db.presents = ST.db.presents or {}
    local list, cutoff = ST.db.presents, time() - PRESENT_DAYS * 86400
    for i = #list, 1, -1 do
        if list[i].time < cutoff then table.remove(list, i) end
    end
    return list
end

-- A present has arrived from `from` by `via` ("trade" or "mail"): noted, oldest first, one line per present in the stack.
function Fish.PresentArrived(from, item, count, via)
    from = base(from)
    if from == "" then return end
    local list = presents()
    for _ = 1, math.min(count or 1, 20) do
        if #list >= 100 then table.remove(list, 1) end
        list[#list + 1] = { from = from, item = item, via = via, time = time() }
    end
    ST.print(string.format("%s sent you %s by %s. The Index will count any fish in it when you open it.", from, item, via))
end

-- The fish in his bags now: { [name] = { count, itemID } }. Replaced in the self-test.
function Fish.BagFish()
    local out = {}
    local C = C_Container
    for bag = 0, 4 do
        local slots = (C and C.GetContainerNumSlots and call2(C.GetContainerNumSlots, bag)) or call("GetContainerNumSlots", bag)
        slots = plain(slots, "number") or 0
        for slot = 1, slots do
            local link, count, itemID
            if C and C.GetContainerItemInfo then
                local info = call2(C.GetContainerItemInfo, bag, slot)
                if type(info) == "table" then link, count, itemID = info.hyperlink, info.stackCount, info.itemID end
            else
                local _, n, _, _, _, _, l, _, _, id = call("GetContainerItemInfo", bag, slot)
                link, count, itemID = l, n, id
            end
            link = plain(link, "string")
            local name = link and link:match("%[(.-)%]")
            local fish = fishOf(name, count, plain(itemID, "number") or idOf(link))
            if fish then
                local e = out[fish.item] or { count = 0, itemID = fish.itemID }
                e.count = e.count + fish.count
                out[fish.item] = e
            end
        end
    end
    return out
end

local OPEN_WINDOW = 60
local opening -- { present, before, at } while a present he opened has not yet given up its fish

-- He has opened the present `item` in his bags: which of the noted presents it is (the oldest of that name, else the oldest), and
-- the fish in his bags just before.
function Fish.Opening(item, before)
    local list = presents()
    local pick
    for i, p in ipairs(list) do
        if p.item == item then pick = i break end
    end
    pick = pick or (#list > 0 and 1 or nil)
    local present = pick and table.remove(list, pick) or nil
    opening = { present = present, item = item, before = before or Fish.BagFish(), at = time() }
end

-- His bags have changed: if a present is being opened, the fish that are new since are what was in it. Returns the fish counted.
function Fish.Opened(after)
    local o = opening
    if not o then return 0 end
    if time() - o.at > OPEN_WINDOW then
        opening = nil
        return 0
    end
    after = after or Fish.BagFish()
    local gained = 0
    for name, e in pairs(after) do
        local more = e.count - ((o.before[name] and o.before[name].count) or 0)
        if more > 0 then
            gained = gained + more
            if o.present then
                received(o.present.from, name, more, "present", e.itemID,
                    string.format("You opened %s's present (%s): %d %s.", o.present.from, o.present.via, more, name))
            else
                ST.print(string.format("The present held %d %s, but the Index did not see who sent it (it came before the addon was watching). /sc fish add <name> %d %s puts it in the book.",
                    more, name, more, name))
            end
        end
    end
    if gained > 0 then opening = nil end
    return gained
end

-- A bag slot he has just used: if it holds a present, it is being opened.
local function usedItem(bag, slot)
    if not (ST.db and ST.Gag.IsZennit()) then return end
    local link
    if C_Container and C_Container.GetContainerItemInfo then
        local info = call2(C_Container.GetContainerItemInfo, bag, slot)
        link = type(info) == "table" and info.hyperlink or nil
    else
        link = select(7, call("GetContainerItemInfo", bag, slot))
    end
    link = plain(link, "string")
    local name = link and link:match("%[(.-)%]")
    if name and Fish.IsPresent(name) then Fish.Opening(name) end
end

-- Trades: what the other side has put up (slots 1 to 6; the seventh is "will not be traded"), counted once the trade completes.
local trade = { accepted = false, items = {} }

local function snapshotTrade()
    local items = {}
    for slot = 1, 6 do
        local name, _, quantity = call("GetTradeTargetItemInfo", slot)
        local item = fishOf(name, quantity, idOf(call("GetTradeTargetItemLink", slot))) or presentOf(name, quantity)
        if item then items[#items + 1] = item end
    end
    trade.items = items
end

-- Fish.Trade(event, ...) follows one trade event; exposed for the self-test.
function Fish.Trade(event, a, b)
    if event == "TRADE_SHOW" then
        local partner = plain(call("UnitName", "NPC"), "string")
        trade = { partner = partner, accepted = false, items = {} }
    elseif event == "TRADE_TARGET_ITEM_CHANGED" then
        snapshotTrade()
    elseif event == "TRADE_ACCEPT_UPDATE" then
        snapshotTrade()
        trade.accepted = (a == 1 or a == true) and (b == 1 or b == true)
    elseif event == "TRADE_REQUEST_CANCEL" then
        trade.accepted = false
    elseif event == "TRADE_CLOSED" then
        local t = trade
        trade = { accepted = false, items = {} }
        if not (t.accepted and t.partner) then return end
        for _, item in ipairs(t.items) do
            if item.present then
                Fish.PresentArrived(t.partner, item.item, item.count, "trade")
            else
                received(t.partner, item.item, item.count, "trade", item.itemID)
            end
        end
    end
end

-- Mail: each mail's fish and presents, read when the inbox updates, so that when one is taken (TakeInboxItem for one attachment,
-- AutoLootMailItem for the lot) the book knows what it was and who sent it. A mail no player sent (the Auction House, Greatfather
-- Winter) is skipped, and so is one from a stranger when the client does not say, as for silver (Silver.Known).
local inbox = {}
local MAX_ATTACHMENTS = 16

local function snapshotInbox()
    inbox = {}
    local count = plain(call("GetInboxNumItems"), "number")
    if not count then return end
    for i = 1, math.min(count, 50) do
        local _, _, sender, _, _, _, _, hasItem, _, _, _, canReply = call("GetInboxHeaderInfo", i)
        sender = plain(sender, "string")
        if sender and hasItem and not secret(hasItem) then
            local mail = { sender = sender, canReply = plain(canReply, "boolean"), items = {} }
            for slot = 1, MAX_ATTACHMENTS do
                local name, itemID, _, quantity = call("GetInboxItem", i, slot)
                mail.items[slot] = fishOf(name, quantity, plain(itemID, "number") or idOf(call("GetInboxItemLink", i, slot)))
                    or presentOf(name, quantity)
            end
            inbox[i] = mail
        end
    end
end

-- Fish.Mail(sender, item, canReply): one fish (or present) taken from a mail; exposed for the self-test.
function Fish.Mail(sender, item, canReply)
    if canReply == false then return end
    if canReply ~= true and not (ST.Silver and ST.Silver.Known(sender)) then return end
    if item.present then return Fish.PresentArrived(sender, item.item, item.count, "mail") end
    received(sender, item.item, item.count, "mail", item.itemID)
end

local function tookItem(index, slot)
    if not (ST.db and ST.Gag.IsZennit()) then return end
    local mail = inbox[index]
    if not mail then return end
    local from, to = slot or 1, slot or MAX_ATTACHMENTS
    for s = from, to do
        local item = mail.items[s]
        if item then
            mail.items[s] = nil -- once: the inbox is read again when it updates
            Fish.Mail(mail.sender, item, mail.canReply)
        end
    end
end

local watcher = CreateFrame("Frame")
for _, event in ipairs({ "TRADE_SHOW", "TRADE_TARGET_ITEM_CHANGED", "TRADE_ACCEPT_UPDATE", "TRADE_CLOSED",
    "TRADE_REQUEST_CANCEL", "MAIL_INBOX_UPDATE", "BAG_UPDATE_DELAYED" }) do
    pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", ST.Safe("the fish watcher", function(_, event, ...)
    if not (ST.db and ST.Gag and ST.Gag.IsZennit()) then return end -- only his client keeps the fish book
    if event == "MAIL_INBOX_UPDATE" then snapshotInbox()
    elseif event == "BAG_UPDATE_DELAYED" then Fish.Opened()
    else Fish.Trade(event, ...) end
end))
if hooksecurefunc then
    pcall(hooksecurefunc, "TakeInboxItem", function(index, slot) tookItem(index, slot) end)
    pcall(hooksecurefunc, "AutoLootMailItem", function(index) tookItem(index, nil) end)
    -- opening a present: a bag item used (right-click), by whichever name this client gives the call
    if C_Container and C_Container.UseContainerItem then
        pcall(hooksecurefunc, C_Container, "UseContainerItem", function(bag, slot) usedItem(bag, slot) end)
    end
    pcall(hooksecurefunc, "UseContainerItem", function(bag, slot) usedItem(bag, slot) end)
end
