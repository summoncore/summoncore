-- Respond: how Zennit deals with a summon of him, and the dice.
--
-- When a live summon of Zennit reaches his client, a dialog gives him four choices (the same choices are in the
-- hub window's Zennit tab):
--   Accept          the summon counts.
--   Decline         the summon does not count; free or not by one rule (Respond.NoResult), the same as the game's own Decline.
--   50 silver       the summon counts once he says the silver was paid ("owes" until then).
--   Dice            he rolls 1-100 (a real /roll, so the party sees it); the summoner is asked to roll back;
--                   Zennit adds 10 to his roll (a little less or more as the season's catch-up moves it), higher wins and a tie goes to him. If he wins, the summon does not count.
-- His answer is stored on the event and sent to everyone (message Z); only his own client can answer for him.
-- The dice use messages D (his roll, to the summoner) and S (the summoner's roll, back to him).
local ADDON, ST = ...
local Respond = {}
ST.Respond = Respond
local T = ST.Theme

local SILVER = 50
Respond.SILVER = SILVER   -- the usual price: what a demand asks when he does not name another
Respond.MAX_SILVER = 100000

-- The silver an answer asked for (or was paid): what he named, else the usual price.
function Respond.AmountOf(resp)
    return resp and resp.amount or SILVER
end

-- "50", "2g", "1g 20s" or "20s" as a whole number of silver (100 silver to the gold), or nil.
function Respond.ParseSilver(text)
    text = (tostring(text or "")):lower():gsub("%s+", "")
    local gold, silver = text:match("^(%d+)g(%d*)s?$")
    local n
    if gold then
        n = tonumber(gold) * 100 + (tonumber(silver) or 0)
    else
        local only = text:match("^(%d+)s?$")
        n = only and tonumber(only)
    end
    if not n or n < 1 or n > Respond.MAX_SILVER then return nil end
    return n
end
local WAIT = 90         -- seconds to wait for the summoner to roll back
local ROLL_WINDOW = 15  -- seconds after pressing Roll in which a /roll result is accepted

local state = {}        -- Zennit's side: id -> { zroll } while waiting for the summoner's roll
local pendingRoll       -- { kind = "zennit" | "summoner", id, expires }
local diceCurrent       -- the dice prompt on the summoner's side: { id, ev, zroll }
local diceDlg           -- that prompt's window (built when first needed)
local surfaces = {}     -- every place the four choices are drawn (the popup and the hub's Zennit tab)
local dlg, dlgSurface   -- the popup

----------------------------------------------------------------------
-- Rules
----------------------------------------------------------------------
-- The dice are loaded his way: Zennit adds EDGE to his roll, and a tie goes to him. Under the new race rules the
-- summoner adds `bonus` (Week.HelperBonus: so much per helper), so a well-organised summon can beat his edge.
-- "won" means Zennit won, so the summon does not count.
Respond.EDGE = 10
function Respond.Resolve(zroll, sroll, bonus, edge)
    return zroll + (edge or Respond.EDGE) >= sroll + (bonus or 0) and "won" or "lost"
end

-- His edge on the dice for the week of this summon: EDGE, moved by the season's catch-up (Week.Edge).
local function edgeFor(ev)
    return (ST.Week.Edge(ST.Week.Start(ev.time)))
end

-- The summoner's roll as shown: "58", or "58+10" with the helpers' bonus.
local function summonerRoll(ev, sroll)
    local bonus = ST.Week.HelperBonus(ev)
    return bonus > 0 and (sroll .. "+" .. bonus) or tostring(sroll)
end

-- A short outcome for the log, or nil if Zennit has not answered.
function Respond.Describe(ev)
    local r = ev.response
    if not r then return nil end
    if r.result == "accepted" then return "accepted" end
    if r.result == "refused" then return "declined (cost him " .. (ev.points or 0) .. ")" end
    if r.result == "excused" then return "declined (free: his list)" end
    if r.result == "declined" then return "declined (free)" end
    if r.result == "away" then return "away from his keyboard (free)" end
    if r.result == "owed" then return "owes " .. Respond.AmountOf(r) .. " silver" end
    if r.result == "paid" then return (r.card and "paid by a punch: " or "paid ") .. Respond.AmountOf(r) .. " silver" end
    if r.result == "won" then return string.format("won the dice %d-%s", r.zroll, summonerRoll(ev, r.sroll)) end
    if r.result == "lost" then return string.format("lost the dice %d-%s", r.zroll, summonerRoll(ev, r.sroll)) end
end

local function plural(n) return n == 1 and "" or "s" end

-- When the helpers' bonus is what beat him (he would have won the roll without it), the line that names them:
-- " Al and Cy's +10 tipped it." Otherwise "".
local function tippedBy(ev, resp)
    local bonus = ST.Week.HelperBonus(ev)
    if bonus == 0 or resp.result ~= "lost" or Respond.Resolve(resp.zroll, resp.sroll, 0, edgeFor(ev)) ~= "won" then return "" end
    local names = {}
    for i = 1, math.min(#ev.assistants, ST.Week.RULES.helpersMax) do names[i] = ev.assistants[i] end
    return string.format(" %s's +%d tipped it.", table.concat(names, " and "), bonus)
end

-- Where a summon landed, as a key to tell places apart: the subzone text, else the map.
local function placeKey(ev)
    local zone = (ev.subzone or ""):lower()
    if zone ~= "" then return zone end
    return ev.mapID and ("map " .. ev.mapID) or nil
end

local ORDINAL = { [3] = "third", [4] = "fourth", [5] = "fifth", [6] = "sixth" }

-- How many summons of Zennit to this place, this one included, have landed on his list (his answers say so: `listed`).
function Respond.ListHits(ev, resp)
    local key = placeKey(ev)
    if not key or not (resp and resp.listed) then return 0 end
    local n = 1
    for _, other in pairs(ST.db.events) do
        if other ~= ev and not other.fake and other.time < ev.time and other.response and other.response.listed
            and ST.Week.IsZennit(other.target) and placeKey(other) == key then
            n = n + 1
        end
    end
    return n
end

-- When a place on his list comes up again, the Index notices: "Darnassus again." Never for the first time, so the list
-- keeps its secret until it hits. Empty when there is nothing to add.
local function listNote(ev, resp)
    local n = Respond.ListHits(ev, resp)
    if n < 2 then return "" end
    local place = (ev.subzone or "") ~= "" and ev.subzone or "That place"
    if n == 2 then return string.format(" %s again. The Index is beginning to see a pattern.", place) end
    return string.format(" %s for the %s time. The Index has stopped pretending it is a coincidence.", place,
        ORDINAL[n] or (n .. "th"))
end

-- What Zennit did, for a summon past the week's limit (Announce has no points to report for those).
local DID = { accepted = "accepted", refused = "declined", excused = "declined", declined = "declined", away = "missed", owed = "put the silver for",
    paid = "was paid for", won = "won the dice on", lost = "lost the dice on" }

-- One line for the chat window when Zennit has answered.
function Respond.Announce(ev, resp)
    local who, pts = ev.target, ev.points or 0
    local r = resp.result
    if not ST.Week.Counts(ev) then
        local why, filing = ST.Week.Why(ST.Week.Start(ev.time))
        return string.format("%s %s the summon from %s. %s, so the race ignores it: the Index files it under '%s'.",
            who, DID[r] or "answered", ev.caster, why, filing)
    end
    local sroll = summonerRoll(ev, resp.sroll or 0)
    local bonus = ""
    if resp.listed and ST.Store.Lands({ response = resp }) then
        bonus = string.format(" It is on his list: +%d point%s toward his week off.", pts, plural(pts)) .. listNote(ev, resp)
    end
    local say = ST.Voice.Say
    if r == "accepted" then
        return say("answer.accepted", {
            "%s accepted the summon from %s. +%d point%s.%s",
            "%s accepted the summon from %s, without comment. +%d point%s.%s",
            "The Index records that %s accepted the summon from %s. +%d point%s.%s" }, who, ev.caster, pts, plural(pts), bonus)
    end
    -- every no reads as a decline; what differs is whether it cost him (design/lenses.md, Simplicity/Complexity)
    if r == "declined" then
        return say("answer.declined", {
            "%s declined the summon from %s, free: his one free decline this week. It did not happen, so no points for them and none for him.",
            "%s declined the summon from %s and spent his free decline. It did not happen: no points either way, and the Index has no comment.",
            "%s declined the summon from %s. It was his free decline, so it is worth nothing to either side." }, who, ev.caster)
    end
    if r == "away" then
        return string.format("%s was away from his keyboard when the summons from %s came. The Index files it as away: it did not happen, and it costs nobody anything.",
            who, ev.caster)
    end
    if r == "refused" and ev.writ and ST.Week.WritCounts(ev) then
        return string.format("%s declined the summon from %s, and the group had played a writ on it: it cost him. No points for them, and %s loses %d point%s toward his goal.",
            who, ev.caster, who, pts, plural(pts))
    end
    if r == "refused" then
        return say("answer.refused", {
            "%s declined the summon from %s, and it cost him: no points for them, and %s loses %d point%s toward his goal.",
            "%s declined the summon from %s, with some dignity, and it cost him: no points for them, and %s loses %d point%s toward his goal.",
            "The Index records that %s declined the summon from %s, at a cost: no points, and %s loses %d point%s toward his goal." },
            who, ev.caster, who, pts, plural(pts))
    end
    if r == "excused" then
        return say("answer.excused", {
            "%s declined the summon from %s, free: the place is on his list. No points.%s",
            "%s declined the summon from %s. No points, but the place is on his list, so it costs him nothing.%s",
            "%s declined the summon from %s at no cost to himself: the destination is on his list. No points.%s" },
            who, ev.caster, listNote(ev, resp))
    end
    local silver = Respond.AmountOf(resp)
    if r == "owed" then
        -- the summons counts at once; the silver goes on the caster's tab, so asking for it can never be a way to refuse
        return say("answer.owed", {
            "%s asks %d silver of %s, in cash, with no receipt. The summons counts: +%d point%s.%s The silver goes on the tab.",
            "%s would like %d silver from %s, in cash, and would prefer no receipt. The summons counts: +%d point%s.%s It goes on the tab.",
            "%s has named his price: %d silver from %s, in cash, no receipt. The summons counts: +%d point%s.%s It goes on the tab." },
            who, silver, ev.caster, pts, plural(pts), bonus)
    end
    if r == "paid" and resp.card then
        return string.format("%s's card pays the %d silver: the Index stamps it, %d punches left. +%d point%s.%s", ev.caster, silver,
            ST.Cards.Left(ev.caster), pts, plural(pts), bonus)
    end
    if r == "paid" then
        return say("answer.paid", {
            "%s says the %d silver was paid. +%d point%s.%s",
            "%s confirms the %d silver arrived. +%d point%s.%s",
            "%s has been paid the %d silver, and says so. +%d point%s.%s" }, who, silver, pts, plural(pts), bonus)
    end
    if r == "won" then
        return say("answer.won", {
            "%s won the dice (%d to %s): the summon does not count, and he gains %d point%s toward his week off.",
            "%s won the dice (%d to %s). The summon does not count, and he gains %d point%s toward his week off.",
            "The dice favoured %s (%d to %s): the summon does not count, and he gains %d point%s toward his week off. The Index checked the dice." },
            who, resp.zroll, sroll, pts, plural(pts))
    end
    if r == "lost" then
        return say("answer.lost", {
            "%s lost the dice (%d to %s): the summon counts. +%d point%s.%s%s",
            "%s lost the dice (%d to %s), and the summon counts. +%d point%s.%s%s",
            "The dice went against %s (%d to %s): the summon counts. +%d point%s.%s%s" },
            who, resp.zroll, sroll, pts, plural(pts), bonus, tippedBy(ev, resp))
    end
end

-- Zennit's secret list for the week: destination words kept on his client only (never synced or exported).
function Respond.List()
    ST.db.settings.zennitList = ST.db.settings.zennitList or {}
    return ST.db.settings.zennitList
end

-- The list is bounded (design/lenses.md, Elegance): an entry matches any part of a place's name, so a single letter would
-- match most places and decide every week. Only the first LIST_MAX entries count, and only those of LIST_MIN letters or more.
Respond.LIST_MAX, Respond.LIST_MIN = 5, 4

-- When each place was added (lowercase text -> time). A place counts from the Monday after it was added, so the list is set for the
-- week and cannot be changed with a summons on screen (design/lenses.md, Secrets). Older entries have no time and count at once.
local function addedAt()
    ST.db.settings.zennitListAdded = ST.db.settings.zennitListAdded or {}
    return ST.db.settings.zennitListAdded
end

-- Whether an entry is still waiting for its first Monday at time `at` (default: now).
function Respond.ListPending(word, at)
    local t = addedAt()[word:lower()]
    return t ~= nil and t >= ST.Week.Start(at or time())
end

-- The entries that count, in order: the first five long enough, and (with `at`) only those that had a Monday before `at`.
function Respond.ListActive(at)
    local out, n = {}, 0
    for _, word in ipairs(Respond.List()) do
        if n < Respond.LIST_MAX and #word >= Respond.LIST_MIN then
            n = n + 1
            if not at or not Respond.ListPending(word, at) then out[#out + 1] = word end
        end
    end
    return out
end

-- Adds a place. Returns true, or false and why it was refused.
function Respond.ListAdd(text)
    text = (text or ""):match("^%s*(.-)%s*$")
    if text == "" then return false, "add what?" end
    if #text < Respond.LIST_MIN then
        return false, string.format("'%s' is too short: a place needs at least %d letters", text, Respond.LIST_MIN)
    end
    local list = Respond.List()
    for _, word in ipairs(list) do
        if word:lower() == text:lower() then return false, string.format("'%s' is already on the list", word) end
    end
    if #Respond.ListActive() >= Respond.LIST_MAX then
        return false, string.format("the list holds %d places: remove one first", Respond.LIST_MAX)
    end
    list[#list + 1] = text
    addedAt()[text:lower()] = time()
    return true
end

-- Every zone the client knows, by its own names. No map IDs are written down here: start from where the player stands (or the
-- client's default world map), climb to the top of the map tree, and ask for every zone below it.
function Respond.WorldZoneNames()
    local names = {}
    if not (C_Map and C_Map.GetMapInfo and C_Map.GetMapChildrenInfo and Enum and Enum.UIMapType) then return names end
    local id = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not id and C_Map.GetFallbackWorldMapID then id = C_Map.GetFallbackWorldMapID() end
    local ok, info = pcall(C_Map.GetMapInfo, id)
    if not (ok and info) then return names end
    for _ = 1, 10 do -- a short tree; the bound only guards against a loop
        if not info.parentMapID or info.parentMapID == 0 then break end
        local okUp, up = pcall(C_Map.GetMapInfo, info.parentMapID)
        if not (okUp and up) then break end
        id, info = info.parentMapID, up
    end
    local okKids, maps = pcall(C_Map.GetMapChildrenInfo, id, Enum.UIMapType.Zone, true)
    if okKids and type(maps) == "table" then
        for _, m in ipairs(maps) do names[#names + 1] = m.name end
    end
    return names
end

-- Place names to suggest while he types an entry, sorted: the places the Index scores, the world's zones as the client names
-- them, and every place a summons has landed. Names already on his list are left out.
function Respond.ListSuggestions()
    local seen, out = {}, {}
    for _, word in ipairs(Respond.List()) do seen[word:lower()] = true end
    local function add(name)
        if type(name) ~= "string" or #name < Respond.LIST_MIN then return end
        local key = name:lower()
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = name
    end
    for _, n in pairs(ST.Scoring.cityNames) do add(n) end
    for _, n in pairs(ST.Scoring.remoteNames) do add(n) end
    for sz in pairs(ST.Scoring.subzoneKinds) do -- kept lowercase for matching: capitalise each word to show
        add((sz:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end):gsub(" Of ", " of ")))
    end
    for _, name in ipairs(Respond.WorldZoneNames()) do add(name) end
    for _, ev in pairs(ST.db.events or {}) do add(ev.subzone) end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

function Respond.ListRemove(n)
    return table.remove(Respond.List(), tonumber(n) or 0) ~= nil
end

function Respond.ListClear()
    local list = Respond.List()
    for i = #list, 1, -1 do list[i] = nil end
end

-- One rule for no, wherever he says it: the game's Decline or the form's (design/lenses.md, Simplicity/Complexity). A writ always
-- costs him the summons' points; a place on his list is free; otherwise his first decline of the week is free and every later one
-- costs. Returns the result to record: "refused" (it cost him), "excused" (free, his list) or "declined" (free, his free decline).
function Respond.NoResult(ev)
    if ST.Week.WritCounts(ev) then return "refused" end
    if Respond.OnList(ev) then return "excused" end
    if ST.Week.DeclinesLeft(ST.Week.Start(ev.time)) > 0 then return "declined" end
    return "refused"
end

-- What a decline of this summons would do, in words, for his form.
function Respond.NoText(ev)
    local r, pts = Respond.NoResult(ev), ev.points or 0
    if r == "excused" then return "On your list: accepting earns you the points again for your week off; declining costs nothing." end
    if r == "declined" then return "Declining is free: it uses your one free decline this week." end
    if ST.Week.WritCounts(ev) then
        return string.format("The group played a writ on this one: declining costs you %d point%s.", pts, plural(pts))
    end
    return string.format("Your free decline this week is used: declining costs you %d point%s.", pts, plural(pts))
end

-- Is the summon's destination (zone or subzone name) on the list? A word on the list matches any part of the name.
function Respond.OnList(ev)
    local zone = ev.mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(ev.mapID)
    local where = ((ev.subzone or "") .. " " .. ((zone and zone.name) or "")):lower()
    for _, word in ipairs(Respond.ListActive(ev.time)) do -- the list as it stood when the summons' week began
        if where:find(word:lower(), 1, true) then return true end
    end
    return false
end

-- Silver still owed, in every week (it is paid in person, so a summons stays owing until Zennit says it was paid).
-- Returns the number of summons and the silver, for the summons OF this character (`role` "target": what he is owed) or
-- cast BY this character ("caster": what they owe).
function Respond.Owed(role)
    local me, n, silver = ST.Store.me(), 0, 0
    for _, ev in pairs(ST.db.events) do
        local who = role == "caster" and ev.caster or ev.target
        if not ev.fake and who == me and ev.response and ev.response.result == "owed" then
            n, silver = n + 1, silver + Respond.AmountOf(ev.response)
        end
    end
    return n, silver
end

-- How many summons of this character have no answer at all (not counting those that only owe the silver).
function Respond.Waiting()
    local n = 0
    for _, r in ipairs(Respond.Pending()) do
        if not r.ev.response then n = n + 1 end
    end
    return n
end

-- Summons of this character that still need an answer (none yet, or owing the silver), newest first.
function Respond.Pending()
    local me, out = ST.Store.me(), {}
    for _, r in ipairs(ST.Store.Recent(200)) do
        local res = r.ev.response and r.ev.response.result
        -- silver stays owed however old the summons is: it is paid in person, often after the week has closed
        if r.ev.target == me and ((not res and not ST.Week.EventClosed(r.ev)) or res == "owed") then out[#out + 1] = r end
    end
    return out
end

----------------------------------------------------------------------
-- Zennit's decisions
----------------------------------------------------------------------
local refreshSurfaces

-- A recorded line for how Zennit answered (a refusal, or winning the dice); silent when no clip is recorded.
local function playAnswerClip(resp)
    if not resp then return end
    if resp.result == "refused" or resp.result == "excused" then
        ST.Clips.Play("zenit_refuse")
    elseif resp.result == "won" then
        ST.Clips.Play("zenit_win")
    end
end

-- Where the week stands after an answer to this summon, in chat (test summons don't move it).
local function printWeek(ev, you)
    local line = not ev.fake and ST.Week.StatusLine(ST.Week.Start(ev.time), you)
    if line then ST.print(line) end
    local last = ST.Week.LastDie(ev, you)
    if last then ST.print(last) end
end

-- He names the price: a small box asks how much silver, and his last answer is the default. A holder of a card pays with a
-- punch instead, with no question asked.
StaticPopupDialogs["SUMMONCORE_ASK_SILVER"] = {
    text = "%s",
    button1 = "Ask",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 12,
    OnShow = function(self, data)
        local box = self.editBox or self.EditBox
        if box then
            box:SetText(tostring(data and data.default or SILVER))
            box:HighlightText()
        end
    end,
    OnAccept = function(self, data)
        local box = self.editBox or self.EditBox
        local n = Respond.ParseSilver(box and box:GetText())
        if n and data then data.go(n) else ST.print("That is not an amount of silver (try 50, 2g or 1g 20s).") end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local n = Respond.ParseSilver(self:GetText())
        local data = parent.data
        parent:Hide()
        if n and data then data.go(n) else ST.print("That is not an amount of silver (try 50, 2g or 1g 20s).") end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function Respond.AskSilver(id, ev)
    if ST.Cards.Left(ev.caster) > 0 then return Respond.Decide(id, "owed") end -- a card pays: a punch, no question
    local s = ST.db.settings
    StaticPopup_Show("SUMMONCORE_ASK_SILVER", string.format("The Index asks how much silver you ask of %s, in cash, with no receipt. (50, 2g, 1g 20s.) " ..
        "The summons counts either way; the silver goes on the tab.", ev.caster), nil, {
        default = s and s.silverAsk or SILVER,
        go = function(n)
            if s then s.silverAsk = n end
            Respond.Decide(id, "owed", nil, nil, n)
        end })
end

-- Records Zennit's decision on this client and tells everyone (test summons stay local).
function Respond.Decide(id, result, zroll, sroll, amount)
    local ev = ST.Store.Get(id)
    if not ev or not ST.Store.RESULTS[result] then return nil end
    -- that week is over; answers no longer change it, except the silver being paid, which does not move a decided week
    if ST.Week.EventClosed(ev) and not (result == "paid" and ev.response and ev.response.result == "owed") then return nil end
    -- the holder of a card pays the silver with a punch, there and then
    local card
    if result == "owed" and not ev.fake and ST.Cards.Left(ev.caster) > 0 then
        result, card, amount = "paid", true, ST.Cards.UnitPrice(ev.caster)
    end
    -- the silver: what he named (or the usual price) for a demand; kept when he later marks it paid
    if result == "owed" then amount = math.max(1, math.min(Respond.MAX_SILVER, math.floor(amount or SILVER)))
    elseif result == "paid" then amount = amount or (ev.response and ev.response.amount) or nil
    else amount = nil end
    -- paying the silver he asked for settles that same answer: the list bonus stays as it was then, even if he has changed his
    -- list since (a payment after the week closed must not move its points: Week.LateAnswer lets it through)
    local listed
    if result == "paid" and ev.response and ev.response.result == "owed" then listed = ev.response.listed
    else listed = Respond.OnList(ev) or nil end
    -- a new answer is always later than the one it replaces, or other clients keep the old one (sync takes the later)
    local resp = { result = result, zroll = zroll or 0, sroll = sroll or 0,
        time = math.max(time(), ev.response and ev.response.time + 1 or 0),
        listed = listed, closes = ev.response and ev.response.closes or nil,
        card = card or (ev.response and ev.response.card) or nil, amount = amount }
    local before = ev.response
    ST.Store.SetResponse(id, resp)
    if not ev.fake then ST.Sync.SendResponse(id, resp) end
    ST.print(Respond.Announce(ev, resp))
    local postcard = ST.Ledger.PostcardFor(ev, before)
    if postcard then
        ST.print(postcard)
        if ST.Check then ST.Check.Seen("d-postcard", "a postcard was filed") end
    end
    printWeek(ev, true)
    playAnswerClip(resp)
    refreshSurfaces(id, "done")
    if ST.Hub then ST.Hub.Refresh() end
    return resp
end

-- The chat line for Zennit closing the Index on the week of this summon.
local function closedLine(ev)
    local r = ST.Week.Score(ST.Week.Start(ev.time))
    return string.format("%s has closed the Index for the week after %d summons of him. Any more are filed under " ..
        "'enthusiasm' until Monday.", ev.target, r.counted)
end

-- Zennit closes the Index for the week of `start` (default: this week): no more summons of him count until Monday.
-- Allowed once the week's minimum has been filed and the latest of them answered. Returns true if it closed.
function Respond.CloseIndex(start)
    local id, ev = ST.Week.CloseTarget(start or ST.Week.Start())
    if not id or ST.Week.EventClosed(ev) then return false end
    -- the same answer (a card's punch and a named price included), now closing the Index
    local resp = {}
    for k, v in pairs(ev.response) do resp[k] = v end
    resp.time, resp.closes = math.max(time(), ev.response.time + 1), true
    ST.Store.SetResponse(id, resp)
    ST.Sync.SendResponse(id, resp)
    ST.print(closedLine(ev))
    printWeek(ev, true)
    if ST.Hub then ST.Hub.Refresh() end
    return true
end

-- Zennit has rolled: ask the summoner to roll back.
function Respond.StartDice(id, zroll)
    local ev = ST.Store.Get(id)
    if not ev then return end
    state[id] = { zroll = zroll }
    if ev.fake then
        -- a test summon: a pretend summoner rolls back after a moment
        C_Timer.After(1.5, function() Respond.OnDiceReply(id, ev, math.random(100)) end)
    else
        ST.Sync.SendDice(id, zroll, ev.caster)
    end
    refreshSurfaces(id, "waiting", zroll)
    C_Timer.After(WAIT, function()
        if state[id] and state[id].zroll == zroll then
            state[id] = nil
            refreshSurfaces(id, "noanswer")
        end
    end)
end

-- The summoner's roll has come back (Sync calls this): decide the dice.
function Respond.OnDiceReply(id, ev, sroll)
    local st = state[id]
    if not st then return end
    state[id] = nil
    local target = ST.Store.Get(id) or ev
    Respond.Decide(id, Respond.Resolve(st.zroll, sroll, ST.Week.HelperBonus(target), edgeFor(target)), st.zroll, sroll)
end

----------------------------------------------------------------------
-- Rolls: a real /roll 1-100, picked up from the system message
----------------------------------------------------------------------
local function rollPattern()
    local fmt = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
    local p = (fmt:gsub("[%(%)%.%-%+%?%*%[%]%^%$]", "%%%0"))
    p = p:gsub("%%s", "(.+)")
    p = p:gsub("%%d", "(%%d+)")
    return "^" .. p .. "$"
end

-- A roll for `kind` ("zennit" or "summoner") has come in with this value.
function Respond.GotRoll(kind, id, value)
    local ev = ST.Store.Get(id)
    if not ev then return end
    if kind == "zennit" then
        if ev.response then return end -- answered in the game while the roll was on its way: no dice
        Respond.StartDice(id, value)
    elseif kind == "summoner" then
        ST.Sync.SendDiceReply(id, value, ev.target)
        if diceDlg and diceCurrent and diceCurrent.id == id then
            diceDlg.text:SetText(string.format("You rolled %d. Waiting for %s's decision...", value, ev.target))
            diceDlg.rollBtn:Hide()
        end
    end
end

function Respond.RequestRoll(kind, id)
    pendingRoll = { kind = kind, id = id, expires = GetTime() + ROLL_WINDOW }
    if RandomRoll then RandomRoll(1, 100) else Respond.GotRoll(kind, id, math.random(100)) end
end

local rollFrame = CreateFrame("Frame")
rollFrame:RegisterEvent("CHAT_MSG_SYSTEM")
rollFrame:SetScript("OnEvent", function(_, _, message)
    if not pendingRoll or type(message) ~= "string" or ST.isSecret(message) then return end
    if GetTime() > pendingRoll.expires then pendingRoll = nil return end
    local name, value, lo, hi = message:match(rollPattern())
    if not name or tonumber(lo) ~= 1 or tonumber(hi) ~= 100 then return end
    if ST.baseName(name) ~= ST.Store.me() then return end
    local p = pendingRoll
    pendingRoll = nil
    Respond.GotRoll(p.kind, p.id, tonumber(value))
end)

----------------------------------------------------------------------
-- The summoner's side: Zennit suggested dice
----------------------------------------------------------------------
local function buildDiceDialog()
    diceDlg = T.Window("SummonCoreDice", 400, 200, { strata = "DIALOG", escape = false })
    diceDlg:ClearAllPoints()
    diceDlg:SetPoint("TOP", 0, -180)
    diceDlg.TitleText:SetText("DICE!")
    diceDlg.text = T.Text(diceDlg, 18, "green")
    diceDlg.text:SetPoint("TOPLEFT", 18, -40)
    diceDlg.text:SetSize(364, 90)
    diceDlg.text:SetJustifyV("TOP")
    diceDlg.rollBtn = T.Button(diceDlg, "ROLL 1-100", 170, 28, function()
        if diceCurrent then
            Respond.RequestRoll("summoner", diceCurrent.id)
            diceDlg.text:SetText("Rolling...")
        end
    end, "primary")
    diceDlg.rollBtn:SetPoint("BOTTOMLEFT", 18, 16)
    local close = T.Button(diceDlg, "CLOSE", 170, 28, function() diceDlg:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -18, 16)
end

-- Sync calls this when Zennit has rolled and suggests dice for our summon of him.
function Respond.OnDiceChallenge(id, ev, zroll)
    if not diceDlg then buildDiceDialog() end
    diceCurrent = { id = id, ev = ev, zroll = zroll }
    local bonus = ST.Week.HelperBonus(ev)
    diceDlg.text:SetText(string.format("%s suggests dice for your summon of him, and has rolled %d.\n\nRoll 1-100: beat his roll plus %d and the summon counts. A tie goes to him.%s",
        ev.target, zroll, edgeFor(ev), bonus > 0 and string.format(" Your helpers add +%d to your roll.", bonus) or ""))
    diceDlg.rollBtn:Show()
    diceDlg:Show()
end

-- Sync calls this when Zennit's answer arrives. Tell the chat, and finish the dice prompt if we have one.
function Respond.OnResponse(id, ev, resp, before)
    local line = Respond.Announce(ev, resp)
    if resp.closes and before and not before.closes and before.result == resp.result then
        line = closedLine(ev) -- the same answer again, now closing the Index: only that is news
    end
    playAnswerClip(resp)
    if line then ST.print(line) end
    local postcard = ST.Ledger.PostcardFor(ev, before)
    if postcard then
        ST.print(postcard)
        if ST.Check then ST.Check.Seen("d-postcard", "a postcard was filed") end
    end
    printWeek(ev, false)
    ST.Achieve.Announce() -- his answer may have earned me an achievement (a tipped roll, a clean tab, a card used up)
    if ST.Hub then ST.Hub.Refresh() end
    if diceDlg and diceCurrent and diceCurrent.id == id then
        diceDlg.text:SetText(line or "")
        diceDlg.rollBtn:Hide()
    end
end

ST.Sync.onResponse = Respond.OnResponse
ST.Sync.onDice = Respond.OnDiceChallenge
ST.Sync.onDiceReply = Respond.OnDiceReply

----------------------------------------------------------------------
-- The four choices, drawn wherever they are wanted
----------------------------------------------------------------------
local function summonText(ev)
    local where = (ev.subzone and ev.subzone ~= "") and ev.subzone or "somewhere"
    local helpers = #ev.assistants > 0 and table.concat(ev.assistants, ", ") or "nobody"
    local text = string.format("%s has summoned you to %s.\n(%s, %s. Helped by %s.)", T.Paint("cyan", ev.caster), where,
        ev.kind or "?", T.Paint("amber", (ev.points or 0) .. " point" .. plural(ev.points or 0)), helpers)
    if not ev.response and not ev.fake and ST.Week.NewRules(ST.Week.Start(ev.time)) then -- he must know before he decides, in the game or here
        local pts = string.format("%d point%s", ev.points or 0, plural(ev.points or 0))
        if ev.writ and ST.Week.WritCounts(ev) then
            text = text .. string.format("\n%s If you decline it in the game, it costs you %s.", T.Paint("amber", "The group has played a writ on this summons."), pts)
        elseif ST.Week.DeclinesLeft(ST.Week.Start(ev.time)) > 0 then
            text = text .. string.format("\nIf you decline it in the game it is free: you have %s this week.", ST.Week.DeclinesText(ST.Week.DeclinesLeft(ST.Week.Start(ev.time))))
        else
            text = text .. string.format("\nIf you decline it in the game it costs you %s: your free decline this week is used.", pts)
        end
    end
    return text
end

local function setButtons(s, list)
    for i, b in ipairs(s.buttons) do
        local item = list[i]
        if item then
            b:SetText(item[1]:upper())
            b:SetScript("OnClick", item[2])
            b:SetEnabled(not item[3])
            b:Show()
        else
            b:Hide()
        end
    end
end

-- Dice Zennit has left for the week of this summon (nil: no limit), not counting rolls still being decided.
local function diceLeft(id, ev)
    local start = ST.Week.Start(ev.time)
    local left = ST.Week.DiceLeft(start)
    if not left then return nil end
    for other in pairs(state) do
        local o = ST.Store.Get(other)
        if other ~= id and o and not o.fake and ST.Week.Start(o.time) == start then left = left - 1 end
    end
    return math.max(0, left)
end

-- Draws one stage on a surface: "choose", "waiting" (extra = Zennit's roll), "noanswer" or "done".
local function render(s, stage, extra)
    if not s.current then return end
    local id, ev = s.current.id, s.current.ev
    s.stage = stage
    if stage == "choose" then
        local cost
        if not ST.Week.Counts(ev) then
            local why, filing = ST.Week.Why(ST.Week.Start(ev.time), true)
            cost = string.format("%s, so the race ignores it: the Index files it under '%s'. Answer however you like.", why, filing)
        else
            cost = Respond.NoText(ev)
        end
        local dice = diceLeft(id, ev) -- the week line below says how many are left
        local week = ST.Week.StatusLine(ST.Week.Start(ev.time), ST.Gag.IsZennit())
        s.text:SetText(summonText(ev) .. "\n" .. cost .. "\n" .. (week and (week .. " ") or "") .. "How will you deal with it? (Ignore it and it counts as accepted.)")
        setButtons(s, {
            { "Accept it", function() Respond.Decide(id, "accepted") end },
            { Respond.NoResult(ev) == "refused" and "Decline" or "Decline (free)", function() Respond.Decide(id, Respond.NoResult(ev)) end },
            { ST.Cards.Left(ev.caster) > 0 and string.format("Stamp the card (%d left)", ST.Cards.Left(ev.caster))
                or "Name a price, in silver (no receipt)", function() Respond.AskSilver(id, ev) end },
            dice == 0 and { "No dice left this week", function() end, true }
                or { "Roll the dice (1-100)", function()
                    if diceLeft(id, ev) == 0 then return render(s, "choose") end -- the last die went on another summon
                    Respond.RequestRoll("zennit", id)
                    render(s, "waiting")
                end },
        })
    elseif stage == "waiting" then
        -- the rules are said here, once the die is cast, so that rolling is one click (design/lenses.md, Flow)
        local bonus = ST.Week.HelperBonus(ev)
        local rules = string.format("\n\nYou add %d to your roll%s; higher wins and a tie goes to you. If you win, the summon does not count.",
            edgeFor(ev), bonus > 0 and string.format(", and %s's helpers add %d to theirs", ev.caster, bonus) or "")
        s.text:SetText((extra and string.format("You rolled %d. Waiting for %s to roll back...", extra, ev.caster) or "Rolling...") .. rules)
        setButtons(s, { { "Choose something else", function() state[id] = nil render(s, "choose") end } })
    elseif stage == "noanswer" then
        s.text:SetText(string.format("%s did not roll back.\n\nChoose again.", ev.caster))
        setButtons(s, { { "Back", function() render(s, "choose") end } })
    else -- done
        local resp = ev.response or { result = "accepted", zroll = 0, sroll = 0 }
        local text = Respond.Announce(ev, resp) or ""
        local buttons = {}
        if resp.result == "owed" then buttons[#buttons + 1] = { "They paid", function() Respond.Decide(id, "paid") end } end
        buttons[#buttons + 1] = { "Done", s.close }
        if not ev.fake and ST.Week.CloseTarget(ST.Week.Start(ev.time)) then
            text = text .. "\n\nThat makes enough summons for the Index to accept a closure. You may close it for the week."
            buttons[#buttons + 1] = { "Close the Index", function()
                Respond.CloseIndex(ST.Week.Start(ev.time))
                render(s, "done")
            end }
        end
        s.text:SetText(text)
        setButtons(s, buttons)
    end
end

function refreshSurfaces(id, stage, extra)
    for _, s in ipairs(surfaces) do
        if s.current and s.current.id == id and s.text:IsVisible() then render(s, stage, extra) end
    end
end

-- A place to draw the choices: some text and four buttons inside `parent`, in `columns` columns (default 1).
-- closeFn runs for the Close button.
function Respond.NewSurface(parent, x, y, width, closeFn, columns, textHeight)
    columns, textHeight = columns or 1, textHeight or 110
    local s = { buttons = {}, close = closeFn or function() end }
    s.text = T.Text(parent, 18, "green")
    s.text:SetPoint("TOPLEFT", x, y)
    s.text:SetSize(width, textHeight)
    s.text:SetJustifyV("TOP")
    s.text:SetSpacing(2)
    local bw = (width - (columns - 1) * 8) / columns
    for i = 1, 4 do
        local col, row = (i - 1) % columns, math.floor((i - 1) / columns)
        local b = T.Button(parent, "", bw, 28, nil, i == 1 and "primary" or nil)
        b:SetPoint("TOPLEFT", x + col * (bw + 8), y - textHeight - 6 - row * 34)
        s.buttons[i] = b
    end
    surfaces[#surfaces + 1] = s
    return s
end

-- Show a summon on a surface: its choices if it is waiting, or its outcome if it has been answered.
function Respond.Select(s, id, ev)
    s.current = { id = id, ev = ev }
    render(s, ev.response and "done" or "choose")
end

-- Empty a surface.
function Respond.Clear(s)
    s.current, s.stage = nil, nil
    s.text:SetText("")
    setButtons(s, {})
end

function Respond.Stage(s) return s.stage end

----------------------------------------------------------------------
-- The popup, and opening it
----------------------------------------------------------------------
local function buildDialog()
    dlg = T.Window("SummonCoreRespond", 440, 380, { strata = "DIALOG", escape = false })
    dlg:ClearAllPoints()
    dlg:SetPoint("TOP", 0, -140)
    dlg.TitleText:SetText("A SUMMONING!")
    dlgSurface = Respond.NewSurface(dlg, 18, -40, 404, function() dlg:Hide() end, 1, 190)
end

-- A live summon of Zennit has arrived on his client (Sync calls this).
function Respond.Incoming(id, ev)
    ST.Trace(string.format("the Index's form opened for %s (from %s)", id, tostring(ev.caster)))
    if not dlg then buildDialog() end
    Respond.Select(dlgSurface, id, ev)
    dlg:Show()
    if ST.Hub then ST.Hub.Refresh() end
end

-- Re-open the popup for the latest summon of me that is still waiting (or owes silver).
function Respond.Open()
    local first = Respond.Pending()[1]
    if first then
        Respond.Incoming(first.id, first.ev)
        return true
    end
    ST.print("No summon of you is waiting for an answer.")
    return false
end

-- A pretend summon of me, to try the choices without a second player. Nothing leaves this client.
function Respond.Test()
    local id, ev = ST.Store.Add({
        caster = "Tester", target = ST.Store.me(), assistants = { "Helper" },
        mapID = C_Map.GetBestMapForUnit("player"), subzone = GetSubZoneText(), confirmed = true, fake = true,
    }, true)
    Respond.Incoming(id, ev)
end

----------------------------------------------------------------------
-- The game's own summon prompt (design/lenses.md, Resonance)
----------------------------------------------------------------------
-- When the ritual completes the game puts its own Accept / Decline prompt in front of Zennit, and has since long before this addon. What
-- he really does with it is the answer: accepting records "accepted" and closes the Index's form; declining records "declined" (the
-- summons did not happen: no points either way), or "refused" if the group played a writ on it. If nothing is seen, the form works
-- as it always did, and an unanswered summons still counts as accepted.
local SUMMON_WINDOW = 150   -- the game's prompt lasts about two minutes; a later answer is not about this summons
local FILE_WAIT = 5         -- seconds to wait for the caster's own record before his client files the summons itself
local lastSummoner          -- who the game's prompt named, when the client says (a plain first name, or nil)
local promptAt, promptArea  -- when the game's prompt last came up, and the place it named
local promptOf = {}         -- id -> the promptAt of the game's prompt that answered (or claimed) that summons
Respond.later = function(fn) C_Timer.After(FILE_WAIT, fn) end -- a seam: the self-test runs it at once

-- What he pressed, recorded on the summons `pick` ({ id, ev }).
local function answer(pick, kind)
    if promptAt then promptOf[pick.id] = promptAt end -- this summons was the one that prompt was about
    local rolling = state[pick.id] ~= nil
    state[pick.id] = nil -- a roll in flight is over: the game's prompt is his answer, and no die is spent
    if pendingRoll and pendingRoll.id == pick.id then pendingRoll = nil end
    local resp, why
    if kind == "accept" then
        resp, why = Respond.Decide(pick.id, "accepted"), "d-accept"
    elseif kind == "away" then
        resp, why = Respond.Decide(pick.id, "away"), "d-away"
    else
        local result = Respond.NoResult(pick.ev) -- the same rule as the form's Decline
        if result == "refused" and ST.Week.WritCounts(pick.ev) then
            why = "d-writ"
        elseif result == "refused" then
            ST.print(string.format("The Index notes that your free decline this week is used, so this one costs you %d point%s.",
                pick.ev.points or 0, plural(pick.ev.points or 0)))
            why = "d-cost"
        elseif result == "declined" then
            why = "d-decline"
        end
        resp = Respond.Decide(pick.id, result)
    end
    ST.Trace(string.format("%s -> %s (%s%s)", kind, resp and resp.result or "nothing recorded", pick.id, rolling and ", ended a roll in flight" or ""))
    if resp and ST.Check then
        ST.Check.Seen(why, string.format("%s recorded %s", kind, resp.result))
        if rolling then ST.Check.Seen("d-dice-ends", string.format("%s ended a roll; %s", kind, resp.result)) end
    end
    return resp
end

-- kind: "accept" or "decline". summoner: the plain name the prompt named, if known. Returns the answer recorded, or nil when this
-- was not about a summons we are waiting on. A dice roll in flight is ended by it: one answer per summons. When no record of the
-- summons has arrived (a caster without the addon), his client looks again in a few seconds and then files it itself (`final`).
function Respond.Real(kind, summoner, final)
    if not ST.Gag.IsZennit() then return nil end
    local now, pick = time(), nil
    for _, r in ipairs(Respond.Pending()) do -- newest first
        local ev = r.ev
        if not ev.response and not ev.fake and now - ev.time <= SUMMON_WINDOW
            and (not summoner or ST.baseName(ev.caster) == summoner) then
            pick = r
            break
        end
    end
    if pick then return answer(pick, kind) end
    if final then return Respond.FileWitnessed(kind, summoner) end
    if promptAt and now - promptAt <= SUMMON_WINDOW then
        ST.Trace(kind .. ": no record of this summons yet; the Index looks again in a few seconds")
        Respond.later(function() ST.Guard("the summon prompt", Respond.Real, kind, summoner, true) end)
    else
        ST.Trace(kind .. ": no summons of him is waiting, so nothing is recorded")
    end
    return nil
end

----------------------------------------------------------------------
-- A summons whose caster has no addon (design/lenses.md, Accessibility, G)
----------------------------------------------------------------------
-- The game puts its prompt in front of him whoever cast the ritual, so his client can file the summons itself. Who cast it comes
-- from the prompt, or from what a group member's client saw (Detector's witness), or is the only warlock in his group; the helpers
-- only from a witness; the place from where he arrives when he accepts, else from a helper's note or the prompt's area name.

----------------------------------------------------------------------
-- Away from the keyboard (design/lenses.md, Freedom)
----------------------------------------------------------------------
-- If he was already AFK when a summons came, and had been for AWAY_MARGIN or more, his client files it as "away" a few seconds
-- later (unless he answers first): it did not happen and costs nothing. Only an AFK that began well before the summons counts, so
-- typing /afk as a ritual starts is not a dodge. The game's own idle AFK starts after five minutes, hence the margin.
Respond.AWAY_MARGIN = 300
local afkSince -- when his AFK flag was set, or nil
Respond.isAFK = function() local ok, afk = pcall(UnitIsAFK, "player") return ok and afk and not ST.isSecret(afk) and true or false end

-- Sets when he went AFK (his flag watcher does this; the self-test calls it).
function Respond.SetAFK(since) afkSince = since end

-- Was he away, long enough, at time `at`?
function Respond.AwayAt(at)
    return afkSince ~= nil and at - afkSince >= Respond.AWAY_MARGIN and Respond.isAFK()
end

-- A few seconds after the prompt: still away and nothing pressed, so the Index files the summons as away.
function Respond.FileAway(summoner)
    if not ST.Gag.IsZennit() or not promptAt or not Respond.AwayAt(promptAt) then return nil end
    local now = time()
    for _, r in ipairs(Respond.Pending()) do
        local ev = r.ev
        if not ev.response and not ev.fake and now - ev.time <= SUMMON_WINDOW and (not summoner or ST.baseName(ev.caster) == summoner) then
            return answer(r, "away")
        end
    end
    return Respond.FileWitnessed("away", summoner) -- a caster without the addon: filed from his side, as away
end

local afkFrame = CreateFrame("Frame")
afkFrame:RegisterEvent("PLAYER_LOGIN")
pcall(afkFrame.RegisterEvent, afkFrame, "PLAYER_FLAGS_CHANGED")
afkFrame:SetScript("OnEvent", ST.Safe("the AFK watch", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(Respond.ADOPT_AFTER, function() ST.Guard("the Index's sweep", Respond.AdoptAll) end)
    end
    if event == "PLAYER_FLAGS_CHANGED" and unit ~= "player" then return end
    if Respond.isAFK() then afkSince = afkSince or time() else afkSince = nil end
end))

-- Sets what the game's prompt said (the prompt's own handler does this; the self-test calls it).
function Respond.SetPrompt(at, area) promptAt, promptArea = at, area end

-- The only warlock in his group, or nil.
local function loneWarlock()
    local found
    local units = {}
    if IsInRaid() then for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else for i = 1, 4 do units[#units + 1] = "party" .. i end end
    for _, unit in ipairs(units) do
        local ok, _, class = pcall(UnitClass, unit)
        if ok and class == "WARLOCK" and not UnitIsUnit(unit, "player") then
            if found then return nil end
            found = ST.baseName(UnitName(unit))
        end
    end
    return found
end

-- The record to file, from what is known (pure, for the self-test). k: me, kind, summoner, notes (newest first), warlock,
-- here = { mapID, subzone } (where he is now), area (the prompt's place name), at (when the prompt came up).
function Respond.Witnessed(k)
    local caster = k.summoner
    local notes = {}
    for _, n in ipairs(k.notes or {}) do
        if (not n.target or n.target == k.me) and n.caster and (not caster or n.caster == caster) then notes[#notes + 1] = n end
    end
    caster = caster or (notes[1] and notes[1].caster) or k.warlock or "Unknown"
    local helpers, seen = {}, {}
    for _, n in ipairs(notes) do
        if n.caster == caster then
            for _, h in ipairs(n.helpers) do
                if h ~= caster and h ~= k.me and not seen[h] then seen[h] = true helpers[#helpers + 1] = h end
            end
        end
    end
    table.sort(helpers)
    while #helpers > 2 do table.remove(helpers) end
    local mapID, subzone
    if k.kind == "accept" and k.here then
        mapID, subzone = k.here.mapID, k.here.subzone
    else
        for _, n in ipairs(notes) do
            if n.helping and n.caster == caster then mapID, subzone = n.mapID, n.subzone break end
        end
        if not (mapID or subzone) then subzone = k.area end
    end
    return { caster = caster, target = k.me, assistants = helpers, mapID = mapID, subzone = subzone or "",
        confirmed = #helpers == 2, by = k.me, time = k.at }
end

-- Files the summons he just answered, when no record of it came (`final` above), and records the answer on it.
function Respond.FileWitnessed(kind, summoner)
    local me, now = ST.Store.me(), time()
    if not promptAt or now - promptAt > SUMMON_WINDOW then return nil end
    -- a record of it may be here after all: nothing to file. Only one still unanswered, or one that belongs to this prompt (answered
    -- under it, or answered on the Index's form and claimed by no earlier prompt). One answered under an earlier prompt is an
    -- earlier summons, so a warlock casting again after he declined is filed, not lost.
    for _, r in ipairs(ST.Store.Recent(30)) do
        if r.ev.target == me and not r.ev.fake and math.abs(r.ev.time - promptAt) <= SUMMON_WINDOW
            and (not summoner or ST.baseName(r.ev.caster) == summoner)
            and (not r.ev.response or (promptOf[r.id] or promptAt) == promptAt) then
            promptOf[r.id] = promptAt
            ST.Trace(kind .. ": a record of this summons is here already; nothing to file")
            return nil
        end
    end
    local mapID = C_Map.GetBestMapForUnit("player")
    local rec = Respond.Witnessed({ me = me, kind = kind, summoner = summoner, notes = ST.Sync.Witnessed(promptAt - 90),
        warlock = loneWarlock(), here = { mapID = mapID, subzone = GetSubZoneText() }, area = promptArea, at = promptAt })
    local id, ev = ST.Store.Add(rec)
    ST.print(string.format("The Index filed this summons itself: %s cast it without Summon Core%s.", ev.caster,
        #ev.assistants > 0 and (", helped by " .. table.concat(ev.assistants, " and ")) or ""))
    ST.Trace(string.format("filed %s for %s (helpers %s, %s)", id, ev.caster, table.concat(ev.assistants, ","), ev.subzone ~= "" and ev.subzone or "?"))
    if ST.Check then ST.Check.Seen("d-witness", string.format("filed for %s, %d helpers", ev.caster, #ev.assistants)) end
    return answer({ id = id, ev = ev }, kind)
end

-- From the week of Monday 9 November 2026 (UTC), a caster's record that arrives by a batch, or is already held, takes over the
-- summons his client filed (and the sweep after login does the same), and a no moved over is decided again. Weeks before keep the
-- results they were played with, as Week.RULES.from keeps the old race rules.
Respond.FILING_FROM = 1794182400
function Respond.NewFiling(ev)
    return ST.Week.Start(ev.time) >= Respond.FILING_FROM
end

local NO = { declined = true, excused = true, refused = true }

-- The caster's own record arrived after his client filed the same summons: the answer moves to it, and the filed one goes.
-- Returns true when it did, so the Index's form does not open for a summons already answered. Only a caster's own record that
-- is still unanswered takes over: one with an answer has already been matched (or answered on its own), and the filed record
-- nearest in time is the one it replaces, so two summons by one warlock close together each keep their own answer.
function Respond.Adopt(id, ev)
    if ev.by or ev.fake or ev.response then return false end
    local me = ST.Store.me()
    local fid, f
    for oid, o in pairs(ST.db.events) do
        if oid ~= id and o.by == me and o.target == ev.target and math.abs(o.time - ev.time) <= SUMMON_WINDOW
            and (o.caster == ev.caster or o.caster == "Unknown") then
            local d, best = math.abs(o.time - ev.time), f and math.abs(f.time - ev.time)
            if not f or d < best or (d == best and oid < fid) then fid, f = oid, o end
        end
    end
    if not f then return false end
    -- the filed record goes first, so a decline moved over below is decided without counting it
    ST.Store.Remove(fid)
    if f.response then
        local resp = {}
        for key, v in pairs(f.response) do resp[key] = v end
        resp.time = math.max(time(), f.response.time + 1)
        -- moved after the summons' week closed: an answer he made in time stays in time, or every client would refuse it
        if ST.Week.LateAnswer(ev, resp) then resp.time = f.response.time + 1 end
        -- his client did not know of the caster's writ when it filed: a no is decided again on the caster's record, by the one rule
        -- (Respond.NoResult), so a decline of a writ'd summons costs him as the README says, as it would have in the game's prompt
        local redo = NO[resp.result] and not ST.Week.EventClosed(ev) and Respond.NewFiling(ev)
            and Respond.NoResult(ev)
        local changed = redo and redo ~= resp.result
        if changed then resp.result = redo end
        ST.Store.SetResponse(id, resp)
        ST.Sync.SendResponse(id, resp)
        if changed then
            ST.print(Respond.Announce(ev, resp))
            printWeek(ev, true)
        end
    end
    ST.Trace(string.format("%s's own record replaced the one the Index filed (%s)", ev.caster, fid))
    if ST.Hub then ST.Hub.Refresh() end
    return true
end

-- After login his client looks over the weeks still open for summons of him it filed itself while the caster's own record was
-- on its way, and hands each answer over (Adopt): a record that came by a batch, or before an update, is matched here. A
-- closed week is never touched, so a result already decided does not change. Returns how many were adopted.
function Respond.AdoptAll()
    if not ST.Gag.IsZennit() then return 0 end
    local me, list = ST.Store.me(), {}
    for id, ev in pairs(ST.db.events) do
        if ev.target == me and not ev.by and not ev.fake and not ev.response and ev.caster ~= me and not ST.Week.EventClosed(ev)
            and Respond.NewFiling(ev) then
            list[#list + 1] = { id = id, ev = ev }
        end
    end
    table.sort(list, function(a, b)
        if a.ev.time ~= b.ev.time then return a.ev.time < b.ev.time end
        return a.id < b.id
    end)
    local n = 0
    for _, r in ipairs(list) do
        if Respond.Adopt(r.id, r.ev) then n = n + 1 end
    end
    return n
end
Respond.ADOPT_AFTER = 30 -- seconds after login: time for the first hello's batches to arrive

local promptFrame = CreateFrame("Frame")
Respond.hooks = {} -- what was installed, for /sc check
Respond.hooks.event = pcall(promptFrame.RegisterEvent, promptFrame, "CONFIRM_SUMMON") and true or false
pcall(promptFrame.RegisterEvent, promptFrame, "CANCEL_SUMMON") -- only traced: it tells us whether an expiry closes the prompt
promptFrame:SetScript("OnEvent", ST.Safe("the summon prompt", function(_, event)
    if event == "CANCEL_SUMMON" then return ST.Trace("CANCEL_SUMMON: the game closed the prompt") end
    lastSummoner = nil
    promptAt, promptArea = time(), nil
    local area = C_SummonInfo and C_SummonInfo.GetSummonConfirmAreaName
    if area then
        local ok, name = pcall(area)
        promptArea = ok and type(name) == "string" and not ST.isSecret(name) and name:sub(1, 40) or nil
    end
    local get = C_SummonInfo and C_SummonInfo.GetSummonConfirmSummoner
    if get then
        local ok, name = pcall(get)
        lastSummoner = ok and ST.baseName(name) or nil
    end
    ST.Trace("CONFIRM_SUMMON: summoner=" .. (lastSummoner or "hidden"))
    if Respond.AwayAt(promptAt) then -- he was already away: unless he answers in the next few seconds, the Index files it as away
        local summoner = lastSummoner
        Respond.later(function() ST.Guard("the summon prompt", Respond.FileAway, summoner) end)
    end
    if ST.Check then ST.Check.Seen("d-name", lastSummoner and ("the game named " .. lastSummoner) or "the game hid the name") end
end))

-- What he presses is what he did: the prompt's buttons call these, and a hook sees the call without changing it. Where this client
-- has no such functions the hooks are skipped and nothing here runs.
local function hook(name, kind, flag)
    if not (C_SummonInfo and hooksecurefunc and C_SummonInfo[name]) then Respond.hooks[flag] = false return end
    Respond.hooks[flag] = pcall(hooksecurefunc, C_SummonInfo, name, ST.Safe("the summon prompt", function()
        ST.Trace("hook " .. name .. " called")
        Respond.Real(kind, lastSummoner)
    end)) and true or false
end
hook("ConfirmSummon", "accept", "confirm")
hook("CancelSummon", "decline", "cancel")
