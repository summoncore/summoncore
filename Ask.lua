-- Ask: the state of Zennit, read by his own client. Nothing is put to him and he presses nothing: his client looks and answers.
-- Questions only Zennit's client can answer (design/lenses.md, Parked ideas: the stranded summons). Is his hearthstone ready?
-- How long has he been logged in? Anyone asks; the question goes to the group and the guild, and only his
-- client answers, whispering back to whoever asked. No rule uses an answer yet: this is the mechanism a challenge or a card
-- could play later (Ask.Ask takes a callback for that). He is told each time he is asked, and /sc zennit ask off stops answers.
--
-- A question: key = { label, arg (what the argument is, if it takes one), about(arg) -> what was asked, for his notice,
-- answer(arg) -> status, value (his client), say(value, arg) -> the fact as a sentence (the asker's client) }. A status is "ok", "unknown" (the game would not say), "off"
-- (he has switched them off) or "unasked" (his client does not know the key). Values are short strings, never trusted for more
-- than what they say.
local ADDON, ST = ...
setfenv(1, ST.env) -- the addon's own globals (Core.lua)
local Ask = {}
ST.Ask = Ask

Ask.TIMEOUT = 8          -- seconds to wait for his client before saying there was no answer
Ask.COOLDOWN = 5         -- his client answers each asker at most once in this many seconds
Ask.MAX_PENDING = 3      -- questions one client may have waiting at once
Ask.HEARTHSTONE = 6948   -- the item ID of a Hearthstone
local GCD = 1.5          -- a cooldown this short is the global cooldown, not the item's own

-- what this client is waiting for (pending), and on his client what it has answered; the self-test gives each client its own
function Ask.newState() return { pending = {}, seq = 0, answered = {}, lastFrom = {} } end
Ask.state = Ask.newState()

----------------------------------------------------------------------
-- Seams (the self-test swaps these)
----------------------------------------------------------------------
function Ask.later(secs, fn) C_Timer.After(secs, fn) end
function Ask.now() return time() end
function Ask.clock() return GetTime() end

local function plain(v)
    if v == nil or ST.isSecret(v) then return nil end
    return v
end

-- How many of an item are in his bags, or nil when the game will not say. Only the hearthstone is asked about: what else he
-- carries is his business, so no question looks in his bags for anything else.
function Ask.itemCount(item)
    local get = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not get then return nil end
    local ok, n = pcall(get, item)
    n = ok and plain(n) or nil
    return type(n) == "number" and n or nil
end

-- Seconds left on an item's cooldown (0 when ready), or nil when the game will not say.
function Ask.cooldownLeft(itemID)
    local get = (C_Container and C_Container.GetItemCooldown) or (C_Item and C_Item.GetItemCooldown) or GetItemCooldown
    if not get then return nil end
    local ok, start, duration = pcall(get, itemID)
    start, duration = ok and plain(start) or nil, ok and plain(duration) or nil
    if type(start) ~= "number" or type(duration) ~= "number" then return nil end
    if start <= 0 or duration <= GCD then return 0 end
    return math.max(0, math.ceil(start + duration - Ask.clock()))
end

-- When this character logged in (kept across a /reload), or nil if the addon has not seen it.
function Ask.loginAt()
    return ST.db and ST.db.settings and ST.db.settings.loginAt
end

----------------------------------------------------------------------
-- The questions
----------------------------------------------------------------------
local function minutes(secs)
    local m = math.max(1, math.ceil(secs / 60))
    if m < 60 then return string.format("%d minute%s", m, m == 1 and "" or "s") end
    local h = math.floor(m / 60)
    m = m % 60
    return string.format("%d hour%s%s", h, h == 1 and "" or "s", m > 0 and string.format(" %d minute%s", m, m == 1 and "" or "s") or "")
end

Ask.QUESTIONS = {
    hearth = {
        label = "Is his hearthstone in his bags, and ready?",
        about = function() return "whether your hearthstone is ready" end,
        answer = function()
            local n = Ask.itemCount(Ask.HEARTHSTONE)
            if n == nil then return "unknown" end
            if n == 0 then return "ok", "none" end
            local left = Ask.cooldownLeft(Ask.HEARTHSTONE)
            if left == nil then return "unknown" end
            return "ok", left == 0 and "ready" or ("cd:" .. left)
        end,
        say = function(v)
            if v == "none" then return "Zennit is not carrying a hearthstone." end
            if v == "ready" then return "Zennit's hearthstone is in his bags and ready." end
            local left = tonumber((v or ""):match("^cd:(%d+)$"))
            if left then return "Zennit's hearthstone is in his bags, on cooldown for " .. minutes(left) .. " more." end
        end,
    },
    playing = {
        label = "How long has he been logged in?",
        about = function() return "how long you have been logged in" end,
        answer = function()
            local at = Ask.loginAt()
            if not at then return "unknown" end
            return "ok", tostring(math.max(0, Ask.now() - at))
        end,
        say = function(v)
            local secs = tonumber(v)
            if secs then return "Zennit has been logged in for " .. minutes(secs) .. "." end
        end,
    },
}

-- The keys in a fixed order, for the list.
function Ask.Keys()
    local keys = {}
    for k in pairs(Ask.QUESTIONS) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

----------------------------------------------------------------------
-- His client: answering
----------------------------------------------------------------------
function Ask.IsOff()
    return ST.db and ST.db.settings and ST.db.settings.askOff == true
end

-- Works out the answer to one question here. Returns status, value.
function Ask.AnswerHere(key, arg)
    local q = Ask.QUESTIONS[key]
    if not q then return "unasked", "" end
    if Ask.IsOff() then return "off", "" end
    local ok, status, value = pcall(q.answer, arg or "")
    if not ok then return "unknown", "" end
    if not ST.Sync.ASK_STATUS[status or ""] then return "unknown", "" end
    return status, tostring(value or "")
end

-- The answer as the asker reads it.
function Ask.Text(key, status, value, arg)
    if status == "off" then return "Zennit has switched questions off. His client keeps its answers to itself." end
    if status == "unasked" then return "Zennit's client does not know that question (it may be on an older version)." end
    if status == "timeout" then
        return "No answer from Zennit's client: he is offline, in neither your group nor your guild, or not running Summon Core "
            .. ST.version .. " or later."
    end
    local q = Ask.QUESTIONS[key]
    local text = status == "ok" and q and q.say(value, arg or "")
    return text or "Zennit's client could not tell: the game would not say."
end

-- A question arrived from `sender` (Sync, on his client only). Returns what happened, for the self-test.
function Ask.Answer(sender, qid, key, arg)
    if Ask.state.answered[qid] then return "ignored:repeat" end -- the same question by party and by guild
    local now = Ask.clock()
    if Ask.state.lastFrom[sender] and now - Ask.state.lastFrom[sender] < Ask.COOLDOWN then return "ignored:ratelimit" end
    Ask.state.lastFrom[sender] = now
    Ask.state.answered[qid] = now
    for id, t in pairs(Ask.state.answered) do if now - t > 60 then Ask.state.answered[id] = nil end end
    local status, value = Ask.AnswerHere(key, arg)
    ST.Sync.SendReply(sender, qid, key, status, value)
    if not ST.Sync.quiet then
        local q = Ask.QUESTIONS[key]
        local what = q and q.about(arg or "") or ("'" .. key .. "'")
        ST.print(string.format("%s asked the Index %s. %s%s", sender, what,
            status == "off" and "Nothing was said: questions are off." or ("The Index told them: " .. Ask.Text(key, status, value, arg)),
            Ask.state.toldOff and "" or " (/sc zennit ask off stops answers)"))
        Ask.state.toldOff = true
    end
    return "answered:" .. status
end

----------------------------------------------------------------------
-- Anyone's client: asking
----------------------------------------------------------------------
local function finish(qid, result)
    local p = Ask.state.pending[qid]
    if not p then return false end
    Ask.state.pending[qid] = nil
    result.key, result.arg = p.key, p.arg
    result.text = Ask.Text(p.key, result.status, result.value, p.arg)
    if p.callback then p.callback(result) end
    return true
end

-- Asks Zennit's client question `key` (with `arg`, if it takes one). callback(result) runs once, with result.status ("ok",
-- "unknown", "off", "unasked" or "timeout"), result.value, result.text (the sentence to show) and result.from (who answered).
-- Returns the question's id, or nil and why it was not asked.
function Ask.Ask(key, arg, callback)
    local q = Ask.QUESTIONS[key]
    if not q then return nil, "no such question" end
    arg = q.arg and (arg or ""):match("^%s*(.-)%s*$") or ""
    if q.arg and arg == "" then return nil, "that question needs " .. q.arg end
    local count = 0
    for _ in pairs(Ask.state.pending) do count = count + 1 end
    if count >= Ask.MAX_PENDING then return nil, "three questions are already waiting for an answer" end
    Ask.state.seq = Ask.state.seq + 1
    local me = ST.Sync.myName()
    local qid = string.format("%s-%d-%d", me, Ask.now() % 100000, Ask.state.seq)
    Ask.state.pending[qid] = { key = key, arg = arg, callback = callback }
    if ST.Gag.IsZennit() then
        -- his own client knows: no need to ask anyone (and this is how he, or the admin in Zennit test mode, tries it alone)
        local status, value = Ask.AnswerHere(key, arg)
        finish(qid, { status = status, value = value, from = me })
        return qid
    end
    if #ST.Sync.channels() == 0 then
        Ask.state.pending[qid] = nil
        return nil, "you are in no group or guild, so Zennit's client cannot hear the question"
    end
    -- his client answers each person once in COOLDOWN seconds: a quicker second question would only time out
    local now = Ask.clock()
    if Ask.state.lastAsked and now - Ask.state.lastAsked < Ask.COOLDOWN then
        Ask.state.pending[qid] = nil
        return nil, string.format("one question every %d seconds: ask again in a moment", Ask.COOLDOWN)
    end
    Ask.state.lastAsked = now
    ST.Sync.SendQuestion(qid, key, arg)
    Ask.later(Ask.TIMEOUT, function() finish(qid, { status = "timeout", value = "" }) end)
    return qid
end

-- His client's answer arrived (Sync checks it came from one of his characters by whisper). Returns what happened.
function Ask.OnReply(sender, qid, key, status, value)
    local p = Ask.state.pending[qid]
    if not p then return "rejected:unasked" end
    if p.key ~= key then return "rejected:key" end
    finish(qid, { status = status, value = value, from = sender })
    return "answer:" .. status
end

-- /sc ask [<question> [<arg>]]: lists the questions, or asks one and prints the answer.
function Ask.Command(rest)
    local key, arg = (rest or ""):match("^(%S*)%s*(.-)$")
    key = key:lower()
    if key == "" then
        ST.print("What Zennit's client can tell about him, read by the addon itself (he presses nothing; he is told afterwards who asked):")
        for _, k in ipairs(Ask.Keys()) do
            local q = Ask.QUESTIONS[k]
            ST.print(string.format("  /sc ask %s%s - %s", k, q.arg and (" " .. q.arg) or "", q.label))
        end
        return
    end
    local q = Ask.QUESTIONS[key]
    if not q then return ST.print("no question '" .. key .. "': /sc ask lists them") end
    local qid, why = Ask.Ask(key, arg, function(result)
        ST.print("|cffffd100Asked:|r " .. result.text)
    end)
    if not qid then return ST.print(why) end
    if Ask.state.pending[qid] then ST.print("The Index has put the question to Zennit's client. " .. q.label) end
end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
ST.Sync.onQuestion = function(...) return Ask.Answer(...) end
ST.Sync.onReply = function(...) return Ask.OnReply(...) end

-- When this character logged in: a fresh login sets it, a /reload keeps it.
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", ST.Safe("ask", function(_, _, isLogin)
    local s = ST.db and ST.db.settings
    if s and (isLogin or not s.loginAt) then s.loginAt = Ask.now() end
end))
