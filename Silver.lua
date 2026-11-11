-- Silver: the money side of the game. Zennit's "50 silver, in cash, no receipt" is paid in person, by trade or by mail. On his
-- client only, this module watches both: when money arrives from someone, it works out what it pays (their owed summons, a card
-- he sells) and ASKS him before it touches anything. /sc probe listens to the same events and prints what the client lets an
-- addon see (who, how much, or a secret value), to learn what is real if detection does not fire.
local ADDON, ST = ...
setfenv(1, ST.env) -- the addon's own globals (Core.lua)
local Silver = {}
ST.Silver = Silver

local EVENTS = { "TRADE_SHOW", "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE", "TRADE_CLOSED", "TRADE_REQUEST_CANCEL",
    "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_CLOSED", "MAIL_SUCCESS", "MAIL_FAILED", "MAIL_SEND_SUCCESS" }

local function secret(v)
    return ST.isSecret and ST.isSecret(v)
end

local function shown(v)
    if secret(v) then return "<secret value>" end
    return tostring(v)
end

-- Copper as "1g 20s 5c".
local function coin(copper)
    if type(copper) ~= "number" or secret(copper) then return shown(copper) end
    return string.format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

local function say(text)
    ST.print("|cff888888[probe]|r " .. text)
end

-- One call of a client function, as "name = value" or why it failed.
local function try(name, ...)
    local fn = ST.env[name]
    if type(fn) ~= "function" then return name .. ": not there" end
    local results = { pcall(fn, ...) }
    if not results[1] then return name .. ": error " .. tostring(results[2]) end
    local parts = {}
    for i = 2, #results do parts[#parts + 1] = shown(results[i]) end
    return name .. " = " .. (#parts > 0 and table.concat(parts, ", ") or "(nothing)")
end

local function onEvent(_, event, ...)
    if event:find("^TRADE") then
        local who = UnitName and UnitName("NPC")
        say(string.format("%s%s (args: %s)", event, who and (" with " .. shown(who)) or "", shown((...))))
        local function money(name)
            local fn = ST.env[name]
            return type(fn) == "function" and select(2, pcall(fn)) or nil
        end
        local target, player = money("GetTargetTradeMoney"), money("GetPlayerTradeMoney")
        say("   they offer " .. coin(target) .. ", you offer " .. coin(player))
    elseif event == "MAIL_INBOX_UPDATE" then
        local ok, count = pcall(function() return ST.env["GetInboxNumItems"]() end)
        say("MAIL_INBOX_UPDATE: " .. (ok and (shown(count) .. " in the inbox") or ("GetInboxNumItems failed: " .. tostring(count))))
        if ok and type(count) == "number" and not secret(count) then
            for i = 1, math.min(count, 10) do
                local info = { pcall(ST.env["GetInboxHeaderInfo"], i) }
                if info[1] then
                    -- classic order: packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft, hasItem, ...
                    say(string.format("   #%d from %s, %s, money %s", i, shown(info[4]), shown(info[5]), coin(info[6])))
                else
                    say("   #" .. i .. ": GetInboxHeaderInfo failed: " .. tostring(info[2]))
                end
            end
        end
    else
        say(event .. " (args: " .. shown((...)) .. ")")
    end
end

local frame

-- /sc probe: starts or stops the listener, and says what the client offers right now.
function Silver.Probe()
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", onEvent)
    end
    if frame.on then
        frame:UnregisterAllEvents()
        frame.on = false
        return say("stopped")
    end
    local missing = {}
    for _, event in ipairs(EVENTS) do
        if not pcall(frame.RegisterEvent, frame, event) then missing[#missing + 1] = event end
    end
    frame.on = true
    say("listening to trade and mail. Open a trade or the mailbox and move some money; run /sc probe again to stop.")
    if #missing > 0 then say("this client has no such event: " .. table.concat(missing, ", ")) end
    say(try("GetPlayerTradeMoney"))
    say(try("GetTargetTradeMoney"))
    say(try("GetInboxNumItems"))
    say(try("GetMoney"))
end

----------------------------------------------------------------------
-- What a payment pays
----------------------------------------------------------------------
local function base(name)
    return ST.baseName(name) or name or ""
end

-- Zennit's summons that this person owes the silver for, oldest first: { { id, ev, amount } }.
function Silver.OwedBy(payer)
    local list = {}
    for id, ev in pairs(ST.db.events) do
        if not ev.fake and ev.response and ev.response.result == "owed" and ST.Week.IsZennit(ev.target)
            and base(ev.caster) == base(payer) then
            list[#list + 1] = { id = id, ev = ev, amount = ST.Respond.AmountOf(ev.response) }
        end
    end
    table.sort(list, function(a, b)
        if a.ev.time ~= b.ev.time then return a.ev.time < b.ev.time end
        return tostring(a.id) < tostring(b.id)
    end)
    return list
end

-- What `copper` paid by `payer` would settle: { silver, owed = { ids of the oldest summons it covers }, owedSilver, card = an
-- offer or nil, left = the silver nothing claims }. Each owed summons is settled in full or not at all, oldest first.
-- `owed` is Silver.OwedBy(payer), `offers` is Cards.Offers().
function Silver.Match(copper, owed, offers)
    local silver = math.floor(copper / 100)
    local out = { silver = silver, owed = {}, owedSilver = 0, left = silver }
    for _, item in ipairs(owed) do
        if out.left < item.amount then break end
        out.owed[#out.owed + 1] = item.id
        out.owedSilver = out.owedSilver + item.amount
        out.left = out.left - item.amount
    end
    local best
    for _, offer in ipairs(offers) do
        if offer.silver <= out.left and (not best or offer.silver > best.silver) then best = offer end
    end
    if best then
        out.card = best
        out.left = out.left - best.silver
    end
    return out
end

-- The tab as a statement: who owes Zennit what, and what has been paid, across every week (design/lenses.md, Economy).
-- ctx: { isZennit(name), name(name), amount(resp) }. `viewer` limits it to one caster (nil: everyone, for Zennit).
-- Returns { lines, owed (silver) }.
function Silver.Statement(events, ctx, viewer)
    local who, order = {}, {}
    for _, ev in pairs(events) do
        local r = ev.response
        if not ev.fake and r and ctx.isZennit(ev.target) and (r.result == "owed" or r.result == "paid") then
            local name = ctx.name(ev.caster)
            if not viewer or ctx.name(viewer) == name then
                local entry = who[name]
                if not entry then
                    entry = { name = name, owed = 0, n = 0, paid = 0, oldest = nil }
                    who[name] = entry
                    order[#order + 1] = entry
                end
                if r.result == "owed" then
                    entry.owed, entry.n = entry.owed + ctx.amount(r), entry.n + 1
                    entry.oldest = (not entry.oldest or ev.time < entry.oldest) and ev.time or entry.oldest
                else
                    entry.paid = entry.paid + ctx.amount(r)
                end
            end
        end
    end
    table.sort(order, function(a, b)
        if a.owed ~= b.owed then return a.owed > b.owed end
        return a.name < b.name
    end)
    local lines, owed, paid = {}, 0, 0
    for _, e in ipairs(order) do
        owed, paid = owed + e.owed, paid + e.paid
        local subject = viewer and "The Index has you down for" or ("The Index has " .. e.name .. " down for")
        if e.owed > 0 then
            lines[#lines + 1] = string.format("%s %d silver on %d summons (the oldest from %s); %d paid so far.", subject, e.owed, e.n,
                date("%d %b", e.oldest), e.paid)
        elseif e.paid > 0 then
            lines[#lines + 1] = string.format("The Index has %s down for nothing now, with %d silver paid so far.", viewer and "you" or e.name, e.paid)
        end
    end
    if #lines == 0 then
        lines[1] = viewer and "The Index has you down for nothing." or "The Index has nobody down for anything."
    elseif not viewer then
        table.insert(lines, 1, string.format("The tab: %d silver owed to Zennit, %d paid so far.", owed, paid))
    end
    return { lines = lines, owed = owed }
end

-- The statement for this client: everyone's tab on Zennit's, your own on anyone else's (and your card, if you hold one).
function Silver.Lines()
    local ctx = { isZennit = ST.Week.IsZennit, name = base, amount = ST.Respond.AmountOf }
    local me = ST.Store.me()
    if ST.Gag.IsZennit() then return Silver.Statement(ST.db.events, ctx).lines end
    local lines = Silver.Statement(ST.db.events, ctx, me).lines
    for _, line in ipairs(ST.Cards.Lines(me)) do lines[#lines + 1] = line end
    return lines
end

StaticPopupDialogs["SUMMONCORE_SILVER"] = {
    text = "%s",
    button1 = "Yes",
    button2 = "Not now",
    OnAccept = function(_, data) if data then data() end end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Is `payer` someone the Index deals with: named in the log (a caster, a helper or the one summoned), holding a card, or a
-- client sync has heard from? Used for a mail when the client does not say whether a player sent it.
function Silver.Known(payer)
    local who = base(payer)
    if who == "" then return false end
    for _, ev in pairs(ST.db.events) do
        if base(ev.caster) == who or base(ev.target) == who then return true end
        for _, a in ipairs(ev.assistants or {}) do
            if base(a) == who then return true end
        end
    end
    for _, card in pairs(ST.db.cards or {}) do
        if base(card.holder):lower() == who:lower() then return true end -- a card sold before 0.29 may be in lower case
    end
    local address = ST.Sync.state and ST.Sync.state.address
    return address ~= nil and address[who] ~= nil
end

-- Money has arrived from `payer` (by "trade" or "mail"): say what it would settle and ask Zennit.
local seen = {}
function Silver.Paid(payer, copper, via)
    if not payer or payer == "" or type(copper) ~= "number" or copper <= 0 then return end
    local key = base(payer) .. ":" .. copper .. ":" .. math.floor(time() / 60)
    if seen[key] then return end -- one payment, however many events it raised
    seen[key] = true
    local m = Silver.Match(copper, Silver.OwedBy(payer), ST.Cards.Offers())
    local who = base(payer)
    if #m.owed == 0 and not m.card then
        return ST.print(string.format("%s sent you %s by %s. It does not settle anything owed, and no card costs that much, so the Index has not touched the books.",
            who, coin(copper), via))
    end
    local parts = {}
    if #m.owed > 0 then
        parts[#parts + 1] = string.format("mark %d of %s's summons paid (%d silver)", #m.owed, who, m.owedSilver)
    end
    if m.card then
        parts[#parts + 1] = string.format("sell %s a card of %d punches (%d silver)", who, m.card.punches, m.card.silver)
    end
    local text = string.format("%s has paid you %s by %s. The Index would like to %s.%s", who, coin(copper), via,
        parts[1] .. (parts[2] and (" and " .. parts[2]) or ""),
        m.left > 0 and string.format(" (%d silver is left over, and the Index has not asked what for.)", m.left) or "")
    StaticPopup_Show("SUMMONCORE_SILVER", text, nil, function()
        for _, id in ipairs(m.owed) do ST.Respond.Decide(id, "paid") end
        if m.card then ST.Cards.Issue(who, m.card.punches, m.card.silver) end
        if ST.Hub then ST.Hub.Refresh() end
    end)
end

----------------------------------------------------------------------
-- Watching the client (Zennit's only)
----------------------------------------------------------------------
local function known(v)
    return type(v) == "number" and not secret(v)
end

local function call(name, ...)
    local fn = ST.env[name]
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2)
end

local trade = { accepted = false, offer = 0 }
local inbox = {}
local warned

local function hidden(what)
    if warned then return end
    warned = true
    ST.print("The client hides " .. what .. " from addons, so the silver cannot be seen automatically. /sc probe shows what it lets through.")
end

-- Money taken from a mail. A mail the game says cannot be answered is not from a player (an auction sale, the Postmaster): none
-- of the Index's business. When the client does not say, only someone the Index knows (Silver.Known) counts.
function Silver.Mail(sender, copper, canReply)
    if canReply == false then return end
    if canReply ~= true and not Silver.Known(sender) then return end
    Silver.Paid(sender, copper, "mail")
end

local function snapshotInbox()
    inbox = {}
    local count = call("GetInboxNumItems")
    if not known(count) then return hidden("the mailbox") end
    for i = 1, math.min(count, 50) do
        local _, _, sender, _, money, _, _, _, _, _, _, canReply = call("GetInboxHeaderInfo", i)
        if type(sender) == "string" and not secret(sender) then
            local reply
            if type(canReply) == "boolean" and not secret(canReply) then reply = canReply end
            inbox[i] = { sender = sender, money = known(money) and money or 0, canReply = reply }
        end
    end
end

local function tookMail(index)
    if not ST.Gag.IsZennit() then return end
    local entry = inbox[index]
    if entry and entry.money > 0 then
        local copper = entry.money
        entry.money = 0
        Silver.Mail(entry.sender, copper, entry.canReply)
    end
end

local function onTrade(event, a, b)
    if event == "TRADE_SHOW" then
        local partner = call("UnitName", "NPC")
        trade = { partner = type(partner) == "string" and not secret(partner) and partner or nil,
            before = call("GetMoney"), offer = 0, accepted = false }
    elseif event == "TRADE_MONEY_CHANGED" or event == "TRADE_ACCEPT_UPDATE" then
        local offer = call("GetTargetTradeMoney")
        if known(offer) then trade.offer = offer elseif offer ~= nil then hidden("trade money") end
        if event == "TRADE_ACCEPT_UPDATE" then trade.accepted = (a == 1 or a == true) and (b == 1 or b == true) end
    elseif event == "TRADE_REQUEST_CANCEL" then
        trade.accepted = false
    elseif event == "TRADE_CLOSED" then
        local t = trade
        trade = { accepted = false, offer = 0 }
        if not (t.accepted and t.partner) then return end
        C_Timer.After(0.5, function()
            local after = call("GetMoney")
            local copper = (known(after) and known(t.before) and after - t.before > 0) and (after - t.before) or t.offer
            if copper and copper > 0 then Silver.Paid(t.partner, copper, "trade") end
        end)
    end
end

local watcher = CreateFrame("Frame")
for _, event in ipairs({ "TRADE_SHOW", "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE", "TRADE_CLOSED", "TRADE_REQUEST_CANCEL",
    "MAIL_INBOX_UPDATE" }) do
    pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", ST.Safe("the silver watcher", function(_, event, ...)
    if not (ST.db and ST.Gag and ST.Gag.IsZennit()) then return end -- only his client watches the money
    if event == "MAIL_INBOX_UPDATE" then snapshotInbox() else onTrade(event, ...) end
end))
if hooksecurefunc then
    pcall(hooksecurefunc, "TakeInboxMoney", tookMail)
    pcall(hooksecurefunc, "AutoLootMailItem", tookMail)
end
