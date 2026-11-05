-- Sync: shares events (not totals) between addon users, so merging is a set union and
-- double-counting is impossible. Only this module touches the network.
--
-- Wire format: "<proto>~<type>~<body>"
--   H  HELLO    body: count|latest|addonVersion
--   E  EVENT    body: record               (live broadcast of a new summon; sender must be the caster)
--   R  REQUEST  body: since                (asks the whisper target for events with time > since)
--   B  BATCH    body: record               (one record per message, whispered in reply to R)
--   L  LINE     body: key|time|text        (a line Zennit wrote for himself: a postcard "pc:<mapID>" or his out-of-office "away")
--   F  FEELING  body: week|role|n           (how a player felt about a week: role p (the group) or z (Zennit), n 1 good to 3 bad;
--                                           kept only by Zennit's and the admin's clients, shown as counts)
--   V  WATCH    body: key                   (someone is showing the group a chapter of the story: z1..z5, g1..g5)
--   W  WITNESS  body: caster|target|helpers|mapID|subzone|time|helping   (what a group member saw of a ritual, for Zennit's client)
--   C  SEASON   body: kind|time|stamp       (the admin started or stopped a season; stamp: ST.TagHash of the sender's BattleTag,
--                                           kept only when it is the admin's. Anyone may pass a mark on: the stamp travels with it)
--   Q  QUESTION body: qid|key|arg           (a question only Zennit's client can answer, Ask.lua; qid starts with the asker's name)
--   Y  REPLY    body: qid|key|status|value  (his client's answer, whispered back to whoever asked; only from his characters)
-- record = id|caster|target|assist1,assist2|mapID|subzone|time|confirmed|wrote[|answer[|w[|by]]]
-- A record filed by Zennit's client for a caster without the addon carries "by" (his name): its id starts with it, and only he
-- can send or delete it (design/lenses.md, Accessibility, G).
-- Fields are percent-escaped. Points and kind are never trusted from the wire: they are recomputed.
local ADDON, ST = ...
local Sync = {}
ST.Sync = Sync

local PREFIX = "SUMMONSYNC"
local PROTO = 1            -- major protocol version; messages from a higher one are ignored
local MAX_MSG = 250        -- addon message limit is 255 bytes
local MAX_NAME = 24
local MAX_SUBZONE = 40
local MAX_ASSISTANTS = 2
local MAX_ALTS = 10        -- most alts of Zennit that we will learn
local MAX_BATCH = 500      -- most events sent in reply to one REQUEST
local SEND_INTERVAL = 0.34 -- about 3 messages per second
local REQUEST_COOLDOWN = 10
local HELLO_BACK_COOLDOWN = 30
local REQUEST_WINDOW = 120 -- how long after our REQUEST (or the last BATCH message) we accept more from that sender

local function newState()
    return { queue = {}, requested = {}, lastReq = {}, lastHelloBack = {}, added = 0, witness = {} }
end
Sync.newState = newState
Sync.state = newState()
Sync.quiet = false

----------------------------------------------------------------------
-- Overridable seams (the self-test swaps these)
----------------------------------------------------------------------
function Sync.myName()
    return Sync.nameOverride or ST.Store.me()
end

function Sync.now()
    return GetTime()
end

function Sync.channels()
    local out = {}
    if IsInRaid() then out[#out + 1] = "RAID" elseif IsInGroup() then out[#out + 1] = "PARTY" end
    if IsInGuild() then out[#out + 1] = "GUILD" end
    return out
end

function Sync.transport(channel, target, payload)
    return pcall(C_ChatInfo.SendAddonMessage, PREFIX, payload, channel, target)
end

----------------------------------------------------------------------
-- Encoding
----------------------------------------------------------------------
local function esc(s)
    return (tostring(s):gsub("[%%|,~%c]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function unesc(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function split(s, sep)
    local out, pos = {}, 1
    while true do
        local i = s:find(sep, pos, true)
        if not i then out[#out + 1] = s:sub(pos) break end
        out[#out + 1] = s:sub(pos, i - 1)
        pos = i + 1
    end
    return out
end

-- An answer's flags as one digit: 1 = the place is on his list, 2 = he closed the Index with it, 4 = the silver was paid by a
-- punch of a card (Cards.lua). "" for none.
local function respFlags(r)
    local n = (r.listed and 1 or 0) + (r.closes and 2 or 0) + (r.card and 4 or 0)
    return n > 0 and tostring(n) or ""
end

-- The flags digit back into an answer's fields.
local function applyFlags(resp, digit)
    local n = tonumber(digit) or 0
    resp.listed = n % 2 == 1 or nil
    resp.closes = math.floor(n / 2) % 2 == 1 or nil
    resp.card = math.floor(n / 4) % 2 == 1 or nil
    return resp
end

-- The silver a demand asks for is a whole number of silver, 1 to MAX_SILVER.
local MAX_SILVER = 100000

-- Flags and the silver asked for, as the optional tail of an answer: ":flags[:silver]" ("" for neither). The flags digit is
-- always written when there is a silver amount.
local function respTail(r)
    local flags = respFlags(r)
    if r.amount then return ":" .. (flags ~= "" and flags or "0") .. ":" .. r.amount end
    return flags ~= "" and (":" .. flags) or ""
end

-- The tail back into flags and an amount. Returns false if it is malformed.
local function parseTail(tail)
    if tail == "" then return "", nil end
    local flags, amount = tail:match("^:(%d)$"), nil
    if not flags then
        flags, amount = tail:match("^:(%d):(%d+)$")
        if not flags then return false end
        amount = tonumber(amount)
        if amount < 1 or amount > MAX_SILVER then return false end
    end
    return flags, amount
end

-- Zennit's answer to a summon of him travels with the record as "result:zroll:sroll:time[:flags[:silver]]" (empty if none).
local function respString(r)
    if not r then return "" end
    return string.format("%s:%d:%d:%d%s", r.result, r.zroll or 0, r.sroll or 0, r.time, respTail(r))
end

-- nil for none, false for a malformed answer, otherwise the answer.
local function parseResp(str)
    if str == "" then return nil end
    local result, z, r, t, tail = str:match("^(%a+):(%d+):(%d+):(%d+)(.*)$")
    if not result or not ST.Store.RESULTS[result] then return false end
    z, r, t = tonumber(z), tonumber(r), tonumber(t)
    if z > 100 or r > 100 or t <= 0 or t > time() + 86400 then return false end
    local flags, amount = parseTail(tail)
    if flags == false then return false end
    if amount and result ~= "owed" and result ~= "paid" then return false end
    local resp = applyFlags({ result = result, zroll = z, sroll = r, time = t }, flags)
    resp.amount = amount
    return resp
end

-- The later of two answers to the summons `ev` (an answer can change: owes 50 silver, then paid). An answer made after its week
-- closed (Week.LateAnswer) does not count at all, so every client keeps the same answer for a closed week.
local function laterResponse(ev, a, b)
    if a and ST.Week.LateAnswer(ev, a) then a = nil end
    if b and ST.Week.LateAnswer(ev, b) then b = nil end
    if not a then return b end
    if not b then return a end
    return b.time > a.time and b or a
end

function Sync.Encode(id, ev)
    local assist = {}
    for _, a in ipairs(ev.assistants or {}) do assist[#assist + 1] = esc(a) end
    -- an 11th field "w" marks a summons the group played a writ on, and a 12th names who filed it when the caster did not (Zennit's
    -- client); most records stay 10 fields, as before
    return table.concat({
        esc(id), esc(ev.caster), esc(ev.target), table.concat(assist, ","),
        ev.mapID and tostring(ev.mapID) or "", esc((ev.subzone or ""):sub(1, MAX_SUBZONE)),
        tostring(ev.time), ev.confirmed and "1" or "0", tostring(ev.wrote or ev.time),
        respString(ev.response), (ev.writ and "w") or (ev.by and "") or nil, ev.by and esc(ev.by) or nil,
    }, "|")
end

local function validName(s)
    return type(s) == "string" and #s > 0 and #s <= MAX_NAME
end

-- Returns id, ev on success, or nil, reason. Never trusts the sender's field values.
function Sync.Decode(record)
    local f = split(record, "|")
    if #f < 9 or #f > 12 then return nil, "fields" end
    if f[11] ~= nil and f[11] ~= "w" and not (f[11] == "" and f[12]) then return nil, "writ" end
    local id, caster, target = unesc(f[1]), unesc(f[2]), unesc(f[3])
    if not validName(caster) or not validName(target) then return nil, "name" end
    -- only Zennit files a summons for someone else, and only a summons of himself
    local by = f[12] and unesc(f[12]) or nil
    if by and (not validName(by) or by ~= target) then return nil, "by" end
    local author = by or caster
    if #id > 48 or id:sub(1, #author + 1) ~= author .. "-" then return nil, "id" end
    local assistants = {}
    if f[4] ~= "" then
        for _, a in ipairs(split(f[4], ",")) do
            a = unesc(a)
            if not validName(a) then return nil, "assistant" end
            assistants[#assistants + 1] = a
        end
    end
    if #assistants > MAX_ASSISTANTS then return nil, "assistants" end
    local mapID
    if f[5] ~= "" then
        mapID = tonumber(f[5])
        if not mapID or mapID < 0 or mapID ~= math.floor(mapID) then return nil, "map" end
    end
    local subzone = unesc(f[6])
    if #subzone > MAX_SUBZONE then return nil, "subzone" end
    local t, wrote = tonumber(f[7]), tonumber(f[9])
    if not t or not wrote or t <= 0 or wrote <= 0 then return nil, "time" end
    if t > time() + 86400 or wrote > time() + 86400 then return nil, "future" end
    if f[8] ~= "0" and f[8] ~= "1" then return nil, "confirmed" end
    local resp = parseResp(f[10] or "")
    if resp == false then return nil, "response" end
    return id, {
        caster = caster, target = target, assistants = assistants, mapID = mapID,
        subzone = subzone, time = t, wrote = wrote, confirmed = f[8] == "1",
        response = resp, writ = f[11] == "w" or nil, by = by,
    }
end

----------------------------------------------------------------------
-- Merge (pure rules; the only DB access is through Store)
----------------------------------------------------------------------
-- live: the record arrived as an EVENT broadcast, so the sender must be the caster (or, for a record Zennit filed, Zennit).
-- opts.dryRun: report what would happen without writing.
-- opts.allowSelf: accept your own events that you do not have (a user-initiated import restoring a
--   lost log); an existing copy of your own event is still never overwritten.
-- Returns "added", "replaced", "kept" or "rejected:<why>".
function Sync.Merge(id, ev, sender, live, opts)
    opts = opts or {}
    local store = ST.Store
    local author = ev.by or ev.caster
    if live and author ~= sender then return "rejected:sender" end
    -- anything from before the last reset stays gone, even if another client still holds it
    if ST.db.resetAt and ev.time <= ST.db.resetAt then return "rejected:reset" end
    if store.IsDeleted(id) then return "rejected:deleted" end
    local cur = store.Get(id)
    if author == Sync.myName() then
        -- Nobody can write entries against the receiver. Our own copy is authoritative.
        if cur then
            if not opts.dryRun then cur.response = laterResponse(ev, cur.response, ev.response) end
            return "kept"
        end
        if not opts.allowSelf then return "rejected:self" end
    end
    ev.points, ev.kind = ST.Scoring.Score(ev.mapID, ev.subzone)
    if not cur then
        if not opts.dryRun then
            ev.response = laterResponse(ev, ev.response, nil)
            store.Put(id, ev)
        end
        return "added"
    end
    local replace
    if ev.confirmed ~= cur.confirmed then
        replace = ev.confirmed -- keep the confirmed copy
    else
        replace = (ev.wrote or ev.time) < (cur.wrote or cur.time) -- both confirmed or both not: earlier write
    end
    if not opts.dryRun then
        if replace then
            ev.response = laterResponse(ev, ev.response, cur.response)
            store.Put(id, ev)
        else
            cur.response = laterResponse(ev, cur.response, ev.response)
        end
    end
    return replace and "replaced" or "kept"
end

----------------------------------------------------------------------
-- Sending
----------------------------------------------------------------------
-- Where a whisper to `name` must go: the full name the game gave when we last heard from them ("Father-Realm"), which is
-- what it needs to deliver one; the addon itself only keeps the first word of a name (ST.baseName), which the game may not
-- find ("No player named 'Father' is currently playing"). A name we have not heard from is used as it is.
function Sync.Address(name)
    local book = Sync.state.address
    return book and book[ST.baseName(name) or ""] or name
end

local function enqueue(channel, target, typ, body)
    local payload = PROTO .. "~" .. typ .. "~" .. body
    if #payload > MAX_MSG then return false end
    if channel == "WHISPER" then target = Sync.Address(target) end
    local q = Sync.state.queue
    q[#q + 1] = { channel = channel, target = target, payload = payload }
    return true
end

-- Sends up to max queued messages. The ticker calls this with 1 about three times a second.
function Sync.Pump(max)
    local n = 0
    local q = Sync.state.queue
    while n < max and #q > 0 do
        local m = table.remove(q, 1)
        Sync.transport(m.channel, m.target, m.payload)
        n = n + 1
    end
    return n
end

-- "0.19.1" -> 0, 19 (major and minor; nil for anything that is not a version).
local function parseVersion(v)
    local major, minor = tostring(v or ""):match("^(%d+)%.(%d+)")
    if not major then return nil end
    return tonumber(major), tonumber(minor)
end

-- What to say when a friend's addon is not the same version as ours (major.minor; a patch does not matter), or nil. The answer
-- format changed in 0.19, so mixed versions read some answers wrongly (design/lenses.md, Risk Mitigation).
function Sync.VersionNote(sender, theirs, mine)
    local tm, tn = parseVersion(theirs)
    local mm, mn = parseVersion(mine)
    if not (tm and mm) or (tm == mm and tn == mn) then return nil end
    local older = tm < mm or (tm == mm and tn < mn)
    return string.format(older and "%s is on %s and you are on %s: ask them to update (answers and cards are read wrongly across versions)."
        or "%s is on %s, newer than your %s: update the addon (answers and cards are read wrongly across versions).",
        sender, theirs, mine)
end

-- When the newest season mark we hold was made (0 for none): a hello carries it, so a client that missed one asks for it.
local function lastMarkTime()
    local m = ST.Week.LastMark()
    return m and m.time or 0
end

-- The fifth field is the newest reset everyone was asked to make (db.resetAll, from the admin's /sc reset all), never a friend's
-- own reset, and a seventh carries the admin's stamp with it, as season marks do. Clients before 0.28.1 read only the first six.
local function helloBody()
    local resetAll = ST.db.resetAll or 0
    return string.format("%d|%d|%s|%d|%d|%d%s", ST.Store.Count(), ST.Store.Latest(), ST.version, ST.Store.LatestResponse(),
        resetAll, lastMarkTime(), resetAll > 0 and ("|" .. ST.ADMIN_HASH) or "")
end

function Sync.Hello(channel, target)
    if channel then
        enqueue(channel, target, "H", helloBody())
    else
        for _, ch in ipairs(Sync.channels()) do enqueue(ch, nil, "H", helloBody()) end
        Sync.SendFeelings() -- our own answers again, so Zennit's and the admin's clients catch up
        if ST.IsZennitAccount() then
            Sync.SendAlt()
            Sync.SendCards()
            Sync.SendLines()
        end
    end
end

function Sync.BroadcastEvent(id, ev)
    local rec = Sync.Encode(id, ev)
    for _, ch in ipairs(Sync.channels()) do enqueue(ch, nil, "E", rec) end
end

-- What a group member saw of a ritual (Detector): sent to the group, where only Zennit's client keeps it.
-- note: caster, target (or nil), helpers (list), mapID, subzone, time, helping (the witness clicked the portal itself)
function Sync.EncodeWitness(n)
    local helpers = {}
    for i, h in ipairs(n.helpers or {}) do if i <= 4 then helpers[#helpers + 1] = esc(h) end end
    return table.concat({ esc(n.caster or ""), esc(n.target or ""), table.concat(helpers, ","), n.mapID and tostring(n.mapID) or "",
        esc((n.subzone or ""):sub(1, MAX_SUBZONE)), tostring(n.time), n.helping and "1" or "0" }, "|")
end

function Sync.DecodeWitness(body, sender)
    local f = split(body, "|")
    if #f ~= 7 then return nil end
    local caster, target = unesc(f[1]), unesc(f[2])
    if caster ~= "" and not validName(caster) then return nil end
    if target ~= "" and not validName(target) then return nil end
    local helpers = {}
    if f[3] ~= "" then
        for _, h in ipairs(split(f[3], ",")) do
            h = unesc(h)
            if not validName(h) or #helpers >= 4 then return nil end
            helpers[#helpers + 1] = h
        end
    end
    local mapID = f[4] ~= "" and tonumber(f[4]) or nil
    if f[4] ~= "" and (not mapID or mapID < 0 or mapID ~= math.floor(mapID)) then return nil end
    local subzone, t = unesc(f[5]), tonumber(f[6])
    if #subzone > MAX_SUBZONE or not t or t <= 0 or t > time() + 86400 then return nil end
    if f[7] ~= "0" and f[7] ~= "1" then return nil end
    return { caster = caster ~= "" and caster or nil, target = target ~= "" and target or nil, helpers = helpers, mapID = mapID,
        subzone = subzone, time = t, helping = f[7] == "1", from = sender }
end

local WITNESS_KEEP = 300 -- seconds a note is kept
function Sync.AddWitness(note)
    local list = Sync.state.witness
    list[#list + 1] = note
    local cutoff = time() - WITNESS_KEEP
    for i = #list, 1, -1 do
        if list[i].time < cutoff or #list > 20 then table.remove(list, i) end
    end
end

-- Notes about rituals from `since` on, newest first.
function Sync.Witnessed(since)
    local out = {}
    for i = #Sync.state.witness, 1, -1 do
        local n = Sync.state.witness[i]
        if n.time >= since then out[#out + 1] = n end
    end
    return out
end

-- Sends a note to the group (party or raid only: the guild was not there). Zennit's own client keeps its note as well.
function Sync.SendWitness(note)
    if ST.Gag.IsZennit() then Sync.AddWitness(note) end
    local body = Sync.EncodeWitness(note)
    for _, ch in ipairs(Sync.channels()) do
        if ch ~= "GUILD" then enqueue(ch, nil, "W", body) end
    end
end

----------------------------------------------------------------------
-- Feelings (design/lenses.md, Playtesting revisited): one click a week on how the week felt. Each client keeps its own answers and
-- sends them with its hello; only Zennit's and the admin's clients keep everyone's, and they show counts, never names.
----------------------------------------------------------------------
Sync.FEEL_KEEP = 8 * 7 * 86400 -- answers older than eight weeks are neither sent nor kept

local function feelBody(week, a) return string.format("%d|%s|%d", week, a.role, a.n) end

function Sync.SendFeeling(week, a)
    for _, ch in ipairs(Sync.channels()) do enqueue(ch, nil, "F", feelBody(week, a)) end
end

function Sync.SendFeelings()
    local mine = ST.db.settings.feelMine or {}
    for week, a in pairs(mine) do
        if week >= time() - Sync.FEEL_KEEP then Sync.SendFeeling(week, a) end
    end
end

-- Keeps an answer from `sender`, if this client is one that keeps them. One answer per person per week: a later one replaces it.
function Sync.PutFeeling(sender, week, role, n)
    if not (ST.Gag.IsZennit() or ST.IsAdminAccount()) then return "ignored" end -- kept while viewing as a player too
    ST.db.settings.feelings = ST.db.settings.feelings or {}
    local all = ST.db.settings.feelings
    all[week] = all[week] or {}
    all[week][sender] = { role = role, n = n }
    for w in pairs(all) do if w < time() - Sync.FEEL_KEEP then all[w] = nil end end
    return "kept"
end

-- Shows a chapter of the story to the group (Intro.PlayForGroup): party or raid only.
function Sync.SendWatch(key)
    for _, ch in ipairs(Sync.channels()) do
        if ch ~= "GUILD" then enqueue(ch, nil, "V", key) end
    end
end

-- Zennit tells everyone how he dealt with a summon of him.
function Sync.SendResponse(id, resp)
    -- the same optional tail as the record's answer, with "|" for ":"
    local body = string.format("%s|%s|%d|%d|%d%s", esc(id), resp.result, resp.zroll or 0, resp.sroll or 0, resp.time,
        (respTail(resp):gsub(":", "|")))
    for _, ch in ipairs(Sync.channels()) do enqueue(ch, nil, "Z", body) end
end

-- A card Zennit has sold (Cards.lua): "id|holder|punches|silver|time". Only his own client sends them, and everyone keeps
-- them, so a holder can see their punches. They are sent when a card is sold, with his hello, and to anyone who asks for events.
local MAX_CARDS = 200
function Sync.SendCard(card, target)
    local body = string.format("%s|%s|%d|%d|%d", esc(card.id), esc(card.holder), card.punches, card.silver, card.time)
    if target then
        enqueue("WHISPER", target, "K", body)
    else
        for _, ch in ipairs(Sync.channels()) do enqueue(ch, nil, "K", body) end
    end
end

-- Resends cards, if this client is Zennit's. Punches are spent oldest card first (Cards.lua), so a client that missed a card
-- that is now used up would charge its punches to the holder's newer card: every card of a holder who still has a punch goes
-- with his hello (newest first, up to 40), and every card (up to MAX_CARDS) is whispered to a client that asked for events.
local CARDS_PER_HELLO = 40
function Sync.SendCards(target)
    if not (ST.Cards and ST.Week.IsZennit(Sync.myName())) then return end
    local list, sent, left = ST.Cards.Sorted(), 0, {}
    for i = #list, 1, -1 do
        local card = list[i]
        if sent >= (target and MAX_CARDS or CARDS_PER_HELLO) then break end
        local holder = card.holder:lower()
        if left[holder] == nil then left[holder] = ST.Cards.Left(card.holder) > 0 end
        if target or left[holder] then
            Sync.SendCard(card, target)
            sent = sent + 1
        end
    end
end

-- Zennit's own client says "the character I am playing is his": everyone else cannot see his Battle.net account,
-- so this is how they learn his alts. The sender is the character; nothing else is claimed.
function Sync.SendAlt()
    for _, ch in ipairs(Sync.channels()) do enqueue(ch, nil, "A", "1") end
end

----------------------------------------------------------------------
-- His own lines (design/lenses.md, Character): short texts Zennit writes for himself, a postcard per far-flung place and an
-- out-of-office for his week off. Kept on every client (settings.zennitLines), sent from his client only, the newest wins.
----------------------------------------------------------------------
Sync.LINE_MAX = 80

-- Whether `key` names a line he may write: "away", or "pc:<mapID>" for a far-flung place.
function Sync.LineKey(key)
    if key == "away" then return true end
    local id = tonumber((key or ""):match("^pc:(%d+)$"))
    return id ~= nil and ST.Scoring.remoteNames[id] ~= nil
end

-- A line as he would type it, made safe to show: no escape codes, one line, at most LINE_MAX letters.
function Sync.CleanLine(text)
    text = tostring(text or ""):gsub("|", ""):gsub("%c", " "):match("^%s*(.-)%s*$")
    return text:sub(1, Sync.LINE_MAX)
end

local function lines()
    ST.db.settings.zennitLines = ST.db.settings.zennitLines or {}
    return ST.db.settings.zennitLines
end

-- His line for `key`, or nil (none written, or cleared).
function Sync.ZennitLine(key)
    local l = lines()[key]
    return l and l.text ~= "" and l.text or nil
end

-- Keeps a line if it is newer than the one held. Returns true when it changed.
function Sync.PutLine(key, text, t)
    if not Sync.LineKey(key) then return false end
    local cur = lines()[key]
    if cur and cur.t >= t then return false end
    lines()[key] = { text = Sync.CleanLine(text), t = t }
    return true
end

local function sendLine(key, l, channel, target)
    enqueue(channel, target, "L", string.format("%s|%d|%s", key, l.t, esc(l.text)))
end

-- His client: writes a line (empty text clears it back to the default) and tells everyone.
function Sync.SetLine(key, text)
    local t = math.max(time(), (lines()[key] and lines()[key].t or 0) + 1)
    if not Sync.PutLine(key, text, t) then return false end
    for _, ch in ipairs(Sync.channels()) do sendLine(key, lines()[key], ch) end
    return true
end

-- His client sends every line he has written (with his hello).
function Sync.SendLines()
    for key, l in pairs(lines()) do
        for _, ch in ipairs(Sync.channels()) do sendLine(key, l, ch) end
    end
end

----------------------------------------------------------------------
-- Seasons (Week.Marks): the admin starts and stops them; every client keeps the marks and passes them on
----------------------------------------------------------------------
local function sendMark(m, channel, target)
    enqueue(channel, target, "C", string.format("%s|%d|%s", m.kind, m.time, ST.ADMIN_HASH))
end

-- The admin's client: makes a mark ("start" or "stop") now and tells everyone. Returns the mark, or nil and why not.
function Sync.MarkSeason(kind)
    if not ST.IsAdminAccount() then return nil, "only the admin can start or stop a season" end
    local last = ST.Week.LastMark()
    local t = math.max(time(), last and last.time + 1 or 0) -- never two marks in one second, so the order is plain
    if not ST.Week.PutMark(kind, t) then return nil, "that mark is already made" end
    local m = { kind = kind, time = t }
    for _, ch in ipairs(Sync.channels()) do sendMark(m, ch) end
    return m
end

-- Whispers every mark we hold to someone who has fewer (in reply to their request).
function Sync.SendMarks(target)
    for _, m in ipairs(ST.Week.Marks()) do sendMark(m, "WHISPER", target) end
end

-- A deleted summon: only its caster can say so. `T` carries the id.
function Sync.SendTombstone(id)
    for _, ch in ipairs(Sync.channels()) do enqueue(ch, nil, "T", esc(id)) end
end

-- Whispers our own tombstones to someone who may still hold what we deleted. Returns whether any were sent.
local MAX_TOMBSTONES = 50
local TOMBSTONE_COOLDOWN = 60
function Sync.SendTombstones(target)
    local st = Sync.state
    local now = Sync.now()
    st.lastTomb = st.lastTomb or {}
    if st.lastTomb[target] and now - st.lastTomb[target] < TOMBSTONE_COOLDOWN then return false end
    local sent = false
    for _, t in ipairs(ST.Store.OwnTombstones(MAX_TOMBSTONES)) do
        if enqueue("WHISPER", target, "T", esc(t.id)) then sent = true end
    end
    if sent then st.lastTomb[target] = now end
    return sent
end

-- Asks everyone to wipe their summons and the story as of `stamp` (each user is asked before it happens).
function Sync.SendReset(stamp)
    for _, ch in ipairs(Sync.channels()) do enqueue(ch, nil, "X", tostring(stamp)) end
end

-- Dice: Zennit's roll goes to the summoner, who rolls back; both by whisper.
function Sync.SendDice(id, zroll, toName)
    enqueue("WHISPER", toName, "D", esc(id) .. "|" .. zroll)
end

function Sync.SendDiceReply(id, sroll, toName)
    enqueue("WHISPER", toName, "S", esc(id) .. "|" .. sroll)
end

----------------------------------------------------------------------
-- Questions for Zennit's client (Ask.lua): something only his client can tell, such as whether his hearthstone is ready. The
-- question goes to the group and the guild, since he may be in either; his client whispers the answer back to whoever asked.
----------------------------------------------------------------------
Sync.ASK_KEY = "^%l+$"   -- a question's key: lowercase letters
local MAX_ASK_ARG = 40     -- an argument (an item's name) and an answer's value are short
local ASK_STATUS = { ok = true, off = true, unknown = true, unasked = true }
Sync.ASK_STATUS = ASK_STATUS

function Sync.SendQuestion(qid, key, arg)
    local body = string.format("%s|%s|%s", esc(qid), key, esc((arg or ""):sub(1, MAX_ASK_ARG)))
    for _, ch in ipairs(Sync.channels()) do enqueue(ch, nil, "Q", body) end
end

function Sync.SendReply(target, qid, key, status, value)
    enqueue("WHISPER", target, "Y", string.format("%s|%s|%s|%s", esc(qid), key, status, esc(tostring(value or ""):sub(1, MAX_ASK_ARG))))
end

----------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------
local function short(name)
    return ST.baseName(name) or ""
end

-- Says how many summons arrived once they stop arriving. A newcomer's history comes in at about three a second (Pump), so a line
-- every couple of seconds would fill their chat; a long stream still says how it is going once a minute.
local ANNOUNCE_QUIET = 3
local ANNOUNCE_EVERY = 60
local function announceSoon()
    local st = Sync.state
    if Sync.quiet then return end
    local now = Sync.now()
    st.lastAdded = now
    st.firstAdded = st.firstAdded or now
    if st.announcing then return end
    st.announcing = true
    local function check()
        local t = Sync.now()
        if t - st.lastAdded < ANNOUNCE_QUIET and t - st.firstAdded < ANNOUNCE_EVERY then return C_Timer.After(1, check) end
        st.announcing, st.firstAdded = false, nil
        if st.added > 0 then
            ST.print(string.format("Sync: received %d new summon%s.", st.added, st.added == 1 and "" or "s"))
            ST.Guard("the week check after sync", ST.Week.Recheck) -- a late summons can change a week already announced
            if ST.Hub then ST.Hub.Refresh() end
            st.added = 0
        end
    end
    C_Timer.After(ANNOUNCE_QUIET, check)
end

-- Returns a short result string describing what happened (used by the self-test).
function Sync.OnMessage(text, channel, sender)
    local full = sender
    sender = short(sender)
    if sender == Sync.myName() or sender == "" then return "ignored:self" end
    -- remember where to whisper them back: the name exactly as the game gave it
    if type(full) == "string" and not ST.isSecret(full) and full ~= sender and #full <= 64 then
        Sync.state.address = Sync.state.address or {}
        Sync.state.address[sender] = full
    end
    local proto, typ, body = tostring(text):match("^(%d+)~(%a)~(.*)$")
    if not proto then return "bad" end
    if tonumber(proto) > PROTO then return "ignored:version" end
    local st = Sync.state
    local now = Sync.now()

    if typ == "H" then
        local count, latest, respT, theirReset, theirMark, resetStamp = body:match("^(%d+)|(%d+)|[^|]*|?(%d*)|?(%d*)|?(%d*)|?(%x*)")
        count, latest, respT, theirReset = tonumber(count), tonumber(latest), tonumber(respT) or 0, tonumber(theirReset) or 0
        theirMark = tonumber(theirMark) or 0
        if not count then return "bad" end
        local myCount, myLatest, myResp = ST.Store.Count(), ST.Store.Latest(), ST.Store.LatestResponse()
        local myMark = lastMarkTime()
        local actions = {}
        -- a friend on another version: say so once
        st.versionNoted = st.versionNoted or {}
        if not st.versionNoted[sender] then
            local note = Sync.VersionNote(sender, body:match("^%d+|%d+|([^|]*)"), ST.version)
            if note then
                st.versionNoted[sender] = true
                if not Sync.quiet then ST.print("|cffffd100Version:|r " .. note) end
                actions[#actions + 1] = "version"
            end
        end
        -- They may hold something we lack: ask for everything (set union makes repeats harmless).
        if count > myCount or latest > myLatest or (count == myCount and latest ~= myLatest) or respT > myResp
            or theirMark > myMark then
            st.requested[sender] = now
            enqueue("WHISPER", sender, "R", tostring(ST.db.resetAt or 0)) -- never ask for what a reset removed
            actions[#actions + 1] = "request"
        end
        -- We hold more than they do: tell them so they can ask us.
        if count < myCount or latest < myLatest or respT < myResp or theirMark < myMark then
            if not st.lastHelloBack[sender] or now - st.lastHelloBack[sender] >= HELLO_BACK_COOLDOWN then
                st.lastHelloBack[sender] = now
                enqueue("WHISPER", sender, "H", helloBody())
                actions[#actions + 1] = "hello-back"
            end
        end
        -- They took part in a reset everyone was asked to make, after our last one (we were offline, or said no): ask our user
        -- again. Only one with the admin's stamp: clients before 0.28.1 sent a friend's own reset here, unstamped.
        if theirReset > (ST.db.resetAt or 0) and resetStamp == ST.ADMIN_HASH and theirReset <= time() + 86400 and Sync.onReset then
            Sync.onReset(sender, theirReset)
            actions[#actions + 1] = "reset-asked"
        end
        -- They hold more than we do: some of it may be summons we deleted, so tell them (rate limited).
        if count > myCount or latest > myLatest then
            if Sync.SendTombstones(sender) then actions[#actions + 1] = "tombstones" end
        end
        return #actions > 0 and table.concat(actions, "+") or "in-sync"

    elseif typ == "R" then
        local since = tonumber(body)
        if not since then return "bad" end
        if st.lastReq[sender] and now - st.lastReq[sender] < REQUEST_COOLDOWN then return "ignored:ratelimit" end
        st.lastReq[sender] = now
        local sent = 0
        for _, r in ipairs(ST.Store.Since(since)) do
            if sent >= MAX_BATCH then break end
            if enqueue("WHISPER", sender, "B", Sync.Encode(r.id, r.ev)) then sent = sent + 1 end
        end
        Sync.SendTombstones(sender)
        Sync.SendCards(sender)
        Sync.SendMarks(sender)
        return "batch:" .. sent

    elseif typ == "E" or typ == "B" then
        if typ == "B" then
            if channel ~= "WHISPER" then return "rejected:channel" end
            if not st.requested[sender] or now - st.requested[sender] > REQUEST_WINDOW then
                return "rejected:unrequested"
            end
            st.requested[sender] = now -- sliding window: a long batch keeps itself open
        end
        local id, ev = Sync.Decode(body)
        if not id then return "rejected:" .. tostring(ev) end
        local result = Sync.Merge(id, ev, sender, typ == "E")
        if result == "added" then
            st.added = st.added + 1
            announceSoon()
            -- Zennit hears a recorded complaint when a friend summons him (live events only, not history).
            if typ == "E" and ev.target == Sync.myName() and ST.Gag.IsZennit() then
                ST.Clips.Play("zenit_land")
                -- a summons he has already answered, filed by his own client while this record was on its way: the answer moves over
                if ST.Respond and not ST.Respond.Adopt(id, ev) then ST.Respond.Incoming(id, ev) end
            end
        end
        return result
    elseif typ == "Z" then
        -- Zennit's answer: only he can answer for himself
        local rid, result, z, r, rt, tail = body:match("^([^|]+)|(%a+)|(%d+)|(%d+)|(%d+)(.*)$")
        if not rid then return "bad" end
        local flags, amount = parseTail((tail:gsub("|", ":")))
        if flags == false or (amount and result ~= "owed" and result ~= "paid") then return "bad" end
        rid = unesc(rid)
        local ev = ST.Store.Get(rid)
        if not ev then return "rejected:unknown" end
        if sender ~= ev.target then return "rejected:sender" end
        if not ST.Store.RESULTS[result] then return "rejected:result" end
        local resp = applyFlags({ result = result, zroll = tonumber(z), sroll = tonumber(r), time = tonumber(rt) }, flags)
        resp.amount = amount
        if resp.zroll > 100 or resp.sroll > 100 or resp.time > time() + 86400 then return "rejected:values" end
        if ST.Week.LateAnswer(ev, resp) then return "rejected:late" end -- made after the week closed
        if laterResponse(ev, ev.response, resp) ~= resp then return "kept" end
        local before = ev.response
        ST.Store.SetResponse(rid, resp)
        if Sync.onResponse then Sync.onResponse(rid, ev, resp, before) end
        return "applied"

    elseif typ == "K" then
        -- a card Zennit sold: only his characters can issue one
        if not ST.Week.IsZennit(sender) then return "rejected:sender" end
        local cid, holder, punches, silver, ct = body:match("^([^|]+)|([^|]+)|(%d+)|(%d+)|(%d+)$")
        if not cid then return "bad" end
        cid, holder, punches, silver, ct = unesc(cid), unesc(holder), tonumber(punches), tonumber(silver), tonumber(ct)
        if #cid > 48 or not validName(holder) or punches < 1 or punches > 50 or silver > 100000 or ct <= 0 or ct > time() + 86400 then
            return "rejected:values"
        end
        ST.db.cards = ST.db.cards or {}
        if ST.db.cards[cid] then return "kept" end
        local count = 0
        for _ in pairs(ST.db.cards) do count = count + 1 end
        if count >= MAX_CARDS then return "rejected:full" end
        -- the holder as the game writes the name, whatever was typed when it was sold (Cards.Holder)
        ST.db.cards[cid] = { id = cid, holder = ST.Cards and ST.Cards.Holder(holder) or holder, punches = punches, silver = silver,
            time = ct }
        if Sync.onCard then Sync.onCard(ST.db.cards[cid]) end
        return "card"

    elseif typ == "A" then
        if not validName(sender) then return "bad" end
        local s = ST.db.settings
        if not s then return "bad" end
        s.zenitAlts = s.zenitAlts or {}
        if ST.Week.IsZennit(sender) then return "kept" end
        if #s.zenitAlts >= MAX_ALTS then return "rejected:full" end
        s.zenitAlts[#s.zenitAlts + 1] = sender
        return "learned"

    elseif typ == "F" then
        local week, role, n = body:match("^(%d+)|([pz])|([123])$")
        week, n = tonumber(week), tonumber(n)
        if not week or week > time() or week < time() - Sync.FEEL_KEEP or not validName(sender) then return "bad" end
        if (role == "z") ~= (ST.Week.IsZennit(sender) and true or false) then return "rejected:role" end
        return Sync.PutFeeling(sender, week, role, n)

    elseif typ == "V" then
        -- a chapter shown to the group: only from the party or raid, and never our own echo
        if channel ~= "PARTY" and channel ~= "RAID" then return "rejected:channel" end
        if not (body:match("^%d*[zg]%d$") or body:match("^%d+[ab]$")) then return "bad" end -- z1, or 2z1 and 2a in a later season
        if sender == Sync.myName() then return "self" end
        if Sync.onWatch then Sync.onWatch(sender, body) end
        return "asked"

    elseif typ == "L" then
        -- a line Zennit wrote for himself: only his characters may send one
        if not ST.Week.IsZennit(sender) then return "rejected:sender" end
        local key, t, text = body:match("^([%w:]+)|(%d+)|(.*)$")
        t = tonumber(t)
        if not key or not Sync.LineKey(key) or not t or t > time() + 86400 or #unesc(text) > Sync.LINE_MAX * 2 then return "bad" end
        return Sync.PutLine(key, unesc(text), t) and "stored" or "kept"

    elseif typ == "C" then
        -- the admin started or stopped a season: kept when the stamp is the admin's (not proof, see ST.TagHash)
        local kind, t, stamp = body:match("^(%a+)|(%d+)|(%x+)$")
        t = tonumber(t)
        if not kind or (kind ~= "start" and kind ~= "stop") or not t or t > time() + 86400 then return "bad" end
        if stamp ~= ST.ADMIN_HASH then return "rejected:stamp" end
        if not ST.Week.PutMark(kind, t) then return "kept" end
        if Sync.onSeason and not Sync.quiet then Sync.onSeason(kind, t, sender) end
        return "stored"

    elseif typ == "W" then
        -- what a group member saw of a ritual: kept a few minutes on Zennit's client, for a summons whose caster has no addon
        if not ST.Gag.IsZennit() then return "ignored" end
        local note = Sync.DecodeWitness(body, sender)
        if not note then return "bad" end
        Sync.AddWitness(note)
        return "noted"

    elseif typ == "Q" then
        -- a question for Zennit's client: the asker names itself in the id, and only his client answers (Ask.Answer)
        local qid, key, arg = body:match("^([^|]+)|([^|]+)|([^|]*)$")
        if not qid or not key:match(Sync.ASK_KEY) or #key > 16 then return "bad" end
        qid, arg = unesc(qid), unesc(arg)
        if #qid > 48 or qid:sub(1, #sender + 1) ~= sender .. "-" or #arg > MAX_ASK_ARG then return "rejected:values" end
        if not ST.Gag.IsZennit() then return "ignored" end
        if not Sync.onQuestion then return "ignored" end
        return Sync.onQuestion(sender, qid, key, arg)

    elseif typ == "Y" then
        -- his client's answer: only his characters may give one, and only to a question we asked (Ask.OnReply checks that)
        if channel ~= "WHISPER" then return "rejected:channel" end
        if not ST.Week.IsZennit(sender) then return "rejected:sender" end
        local qid, key, status, value = body:match("^([^|]+)|([^|]+)|(%a+)|([^|]*)$")
        if not qid or not ASK_STATUS[status] then return "bad" end
        value = unesc(value)
        if #value > MAX_ASK_ARG then return "rejected:values" end
        if not Sync.onReply then return "ignored" end
        return Sync.onReply(sender, unesc(qid), key, status, value)

    elseif typ == "T" then
        -- the caster deleted this summon: nobody else can, so the sender must be the one named in the id
        local id = unesc(body)
        if #id > 48 or id:sub(1, #sender + 1) ~= sender .. "-" then return "rejected:sender" end
        ST.db.deleted = ST.db.deleted or {}
        if ST.db.deleted[id] then return "kept" end
        ST.db.deleted[id] = time() -- a wall-clock time, like the caster's own tombstone (Store.Remove), not this session's GetTime
        ST.db.events[id] = nil
        return "deleted"

    elseif typ == "X" then
        -- a request to reset: nothing happens until this user agrees
        local stamp = tonumber(body:match("^(%d+)$"))
        if not stamp or stamp > time() + 86400 then return "bad" end
        if stamp <= (ST.db.resetAt or 0) then return "kept" end
        if Sync.onReset then Sync.onReset(sender, stamp) end
        return "asked"

    elseif typ == "D" then
        -- Zennit suggests dice for a summon of him, and has rolled; we are the summoner
        local rid, z = body:match("^([^|]+)|(%d+)$")
        if not rid then return "bad" end
        rid, z = unesc(rid), tonumber(z)
        local ev = ST.Store.Get(rid)
        if not ev then return "rejected:unknown" end
        if sender ~= ev.target or ev.caster ~= Sync.myName() then return "rejected:sender" end
        if z < 1 or z > 100 then return "rejected:values" end
        if Sync.onDice then Sync.onDice(rid, ev, z) end
        return "dice"

    elseif typ == "S" then
        -- the summoner's roll, back to Zennit
        local rid, sroll = body:match("^([^|]+)|(%d+)$")
        if not rid then return "bad" end
        rid, sroll = unesc(rid), tonumber(sroll)
        local ev = ST.Store.Get(rid)
        if not ev then return "rejected:unknown" end
        if sender ~= ev.caster or ev.target ~= Sync.myName() then return "rejected:sender" end
        if sroll < 1 or sroll > 100 then return "rejected:values" end
        if Sync.onDiceReply then Sync.onDiceReply(rid, ev, sroll) end
        return "dice-reply"
    end
    return "bad"
end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
function Sync.Status()
    local st = Sync.state
    ST.print(string.format("Sync: %d summons, latest %s, %d queued, channels: %s", ST.Store.Count(),
        ST.Store.Latest() > 0 and date("%Y-%m-%d %H:%M", ST.Store.Latest()) or "never", #st.queue,
        #Sync.channels() > 0 and table.concat(Sync.channels(), ",") or "none"))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")
local grouped = false
frame:SetScript("OnEvent", ST.Safe("sync", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
        ST.Store.onAdd = function(id, ev) Sync.BroadcastEvent(id, ev) end
        ST.Store.onRemove = function(id) Sync.SendTombstone(id) end
        C_Timer.NewTicker(SEND_INTERVAL, function() Sync.Pump(1) end)
        C_Timer.After(5, function() Sync.Hello() end)
        grouped = IsInGroup()
    elseif event == "GROUP_ROSTER_UPDATE" then
        local now = IsInGroup()
        if now and not grouped then C_Timer.After(2, function() Sync.Hello() end) end
        grouped = now
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, text, channel, sender = ...
        if prefix == PREFIX then Sync.OnMessage(text, channel, sender) end
    end
end))
