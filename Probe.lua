-- Probe: what the client lets an addon see, for ideas that depend on it. (The silver one is Silver.Probe: /sc probe.)
-- /sc probe chat is for the idea of logging what Zennit says after he arrives. It listens to say, yell, party and raid chat,
-- and to the events around a summons arriving, and prints what an addon can read of each: whether the text and the sender are
-- readable or secret values, how long the text is, and how long after the summons prompt each event came. It stores and
-- sends nothing. Another player's words are never printed (only whether they could be read, and how long they were); your
-- own are, so run it on Zennit's client and say a line after you arrive.
local ADDON, ST = ...
setfenv(1, ST.env) -- the addon's own globals (Core.lua)
local Probe = {}
ST.Probe = Probe

local CHAT = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" }
local ARRIVAL = { "CONFIRM_SUMMON", "CANCEL_SUMMON", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "LOADING_SCREEN_DISABLED" }
local MAX_PRINTED, MAX_KEPT = 80, 300 -- lines shown in a run (the rest are only counted), and lines kept for /sc probe chat copy

local frame
local run  -- the run in progress: { lines, printed, muted, seen, readable, mine, mineReadable, promptAt }; nil when stopped
local last -- the lines of the last run that finished, for /sc probe chat copy

local function secret(v)
    return ST.isSecret(v)
end

-- Prints a line (up to MAX_PRINTED a run) and keeps it, without colour codes, for the copy window.
local function say(text)
    if run then
        run.lines[#run.lines + 1] = (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
        if #run.lines > MAX_KEPT then table.remove(run.lines, 1) end
        if run.printed >= MAX_PRINTED then
            run.muted = run.muted + 1
            return
        end
        run.printed = run.printed + 1
    end
    ST.print("|cff888888[probe]|r " .. text)
end

-- What may limit an addon right now: combat and instances are where the client hides the most.
local function where()
    local lockdown = _G["InCombatLockdown"]
    local combat = lockdown and lockdown() and "in combat" or "out of combat"
    local ok, inside, kind = pcall(IsInInstance)
    local place = ok and (inside and ("instance: " .. tostring(kind)) or "open world") or "instance: unknown"
    return combat .. ", " .. place
end

-- Is this line yours? true or false, or nil when the client will not say.
local function isMine(sender, guid)
    local me = UnitGUID and UnitGUID("player")
    if guid ~= nil and me ~= nil and not secret(guid) and not secret(me) then return guid == me end
    if sender ~= nil and not secret(sender) then return ST.baseName(sender) == ST.baseName(UnitName("player")) end
    return nil
end

local function onChat(event, ...)
    local args = { ... }
    local text, sender, guid = args[1], args[2], args[12]
    local mine = isMine(sender, guid)
    local readable = type(text) == "string" and not secret(text)
    run.seen = run.seen + 1
    if readable then run.readable = run.readable + 1 end
    if mine == true then
        run.mine = run.mine + 1
        if readable then run.mineReadable = run.mineReadable + 1 end
    end
    local who = mine == true and "you" or mine == false and "someone else" or "someone (the client will not say who)"
    local info
    if secret(text) then
        info = "the text is a secret value"
    elseif type(text) ~= "string" then
        info = "the text is a " .. type(text)
    else
        info = string.format("the text is readable (%d letters)", #text)
        if mine == true then info = info .. ': "' .. text:gsub("|", "/") .. '"' end
    end
    local channel = event:gsub("^CHAT_MSG_", "")
    say(string.format("%s from %s: %s; the sender is %s; %s", channel, who, info, secret(sender) and "hidden" or "readable", where()))
end

local function onArrival(event)
    local now = GetTime()
    if event == "CONFIRM_SUMMON" then run.promptAt = now end
    local since = run.promptAt and string.format("%.1f s after the prompt", now - run.promptAt) or "no prompt seen yet"
    local mapOk, map = pcall(function() return C_Map.GetBestMapForUnit("player") end)
    local line = string.format("%s: %s; map %s; %s", event, since, mapOk and ST.safe(map) or "unknown", where())
    if event == "CONFIRM_SUMMON" and C_SummonInfo then
        local okWho, summoner = pcall(C_SummonInfo.GetSummonConfirmSummoner)
        local okArea, area = pcall(C_SummonInfo.GetSummonConfirmAreaName)
        line = line .. string.format("; summoner %s, to %s", okWho and ST.safe(summoner) or "?", okArea and ST.safe(area) or "?")
    end
    say(line)
end

local function onEvent(_, event, ...)
    if not run then return end
    if event:find("^CHAT_MSG_") then onChat(event, ...) else onArrival(event) end
end

-- /sc probe chat: starts or stops the listener. /sc probe chat copy opens what it printed in a window to copy from.
function Probe.Chat(rest)
    if rest == "copy" then
        local lines = run and run.lines or last
        if not lines or #lines == 0 then return ST.print("nothing to copy yet: run /sc probe chat first.") end
        return ST.Check.CopyLines(lines)
    end
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", ST.Safe("chat probe", onEvent))
    end
    if run then
        frame:UnregisterAllEvents()
        local summary = string.format("stopped. %d chat lines seen: %d with readable text (yours: %d of %d)%s.", run.seen, run.readable,
            run.mineReadable, run.mine, run.muted > 0 and (", " .. run.muted .. " more not printed") or "")
        run.lines[#run.lines + 1] = summary
        ST.print("|cff888888[probe]|r " .. summary)
        last, run = run.lines, nil
        return
    end
    run = { lines = {}, printed = 0, muted = 0, seen = 0, readable = 0, mine = 0, mineReadable = 0 }
    local missing = {}
    for _, list in ipairs({ CHAT, ARRIVAL }) do
        for _, event in ipairs(list) do
            if not pcall(frame.RegisterEvent, frame, event) then missing[#missing + 1] = event end
        end
    end
    say("listening to say, yell, party and raid chat, and to a summons arriving. Say a line in /s or party, ask a friend to say one, "
        .. "and on Zennit's client accept a summons and say something after you arrive. /sc probe chat again stops it, "
        .. "/sc probe chat copy opens what it printed to copy.")
    say("only your own words are printed; for everyone else it says whether the text could be read, and how long it was.")
    say("this client " .. (issecretvalue and "has" or "has no") .. " secret values; now: " .. where())
    if #missing > 0 then say("this client has no such event: " .. table.concat(missing, ", ")) end
end
