-- Diagnostics harness: /sc test. One table entry per API the plan depends on.
-- Each test returns status ("pass" | "fail" | "error" | "info"), detail text.
local ADDON, ST = ...
setfenv(1, ST.env) -- the addon's own globals (Core.lua)
local safe = ST.safe

local RITUAL_ID = ST.RITUAL_ID
local TEST_SOUNDFILE = "Interface\\AddOns\\summoncore\\Media\\test.ogg"
local LOG_MAX = 40

ST.castLog = {}
ST.msgLog = {}
ST.senderNames = {}

local function push(list, entry)
    list[#list + 1] = entry
    if #list > LOG_MAX then table.remove(list, 1) end
end

local function spellName(id)
    return ST.SpellName(id) or "?"
end

local function isRitual(spellID, name)
    if ST.isSecret(spellID) then return false end
    return spellID == RITUAL_ID or name == spellName(RITUAL_ID)
end

local function partyTokens()
    local t = {}
    for i = 1, 4 do t[#t + 1] = "party" .. i end
    return t
end

local function channelSnapshot()
    local out = {}
    for _, unit in ipairs(partyTokens()) do
        if UnitExists(unit) then
            local ok, name, _, _, _, _, _, _, spellID = pcall(UnitChannelInfo, unit)
            out[#out + 1] = unit .. "=" .. (ok and (safe(name) .. "/" .. safe(spellID)) or "ERR")
        end
    end
    return #out > 0 and table.concat(out, " ") or "no party members"
end

----------------------------------------------------------------------
-- Cast event logger (own casts only)
----------------------------------------------------------------------
local castFrame = CreateFrame("Frame")
local registered, regFailed = {}, {}
local CAST_EVENTS = {
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED",
}
for _, ev in ipairs(CAST_EVENTS) do
    local ok = pcall(castFrame.RegisterUnitEvent, castFrame, ev, "player")
    if ok then registered[#registered + 1] = ev else regFailed[#regFailed + 1] = ev end
end

castFrame:SetScript("OnEvent", function(_, event, unit, a2, a3, a4)
    -- SENT args: unit, target, castGUID, spellID. Others: unit, castGUID, spellID.
    local spellID, target
    if event == "UNIT_SPELLCAST_SENT" then
        target, spellID = a2, a4
    else
        spellID = a3
    end
    local name = spellName(spellID)
    local ritual = isRitual(spellID, name)
    local entry = {
        t = date("%H:%M:%S"),
        event = (event:gsub("UNIT_SPELLCAST_", "")),
        spellID = safe(spellID), name = safe(name), ritual = ritual,
        target = safe(target),
        tgt = safe(UnitName("target")),
    }
    if not target and UnitSpellTargetName then
        local ok, v = pcall(UnitSpellTargetName, "player")
        entry.spellTarget = ok and safe(v) or "ERR"
    end
    if ritual then entry.snap = channelSnapshot() end
    push(ST.castLog, entry)
    if ST.RefreshTests then ST.RefreshTests() end
end)

----------------------------------------------------------------------
-- Addon message ping
----------------------------------------------------------------------
local function groupChannel()
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local msgFrame = CreateFrame("Frame")
msgFrame:RegisterEvent("CHAT_MSG_ADDON")
msgFrame:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
    if prefix ~= ST.prefix then return end
    local me = UnitName("player")
    local isSelf = sender == me or sender == GetUnitName("player", true)
    push(ST.msgLog, string.format("%s RECV %s from %s via %s%s", date("%H:%M:%S"),
        safe(text), safe(sender), safe(channel), isSelf and " (self)" or ""))
    ST.senderNames[#ST.senderNames + 1] = safe(sender)
    if #ST.senderNames > 10 then table.remove(ST.senderNames, 1) end
    if not isSelf and type(text) == "string" and text:sub(1, 5) == "PING:" then
        local ok, res = pcall(C_ChatInfo.SendAddonMessage, ST.prefix,
            "PONG:" .. text:sub(6), "WHISPER", sender)
        push(ST.msgLog, string.format("%s SEND PONG to %s -> %s", date("%H:%M:%S"),
            safe(sender), ok and safe(res) or ("ERR " .. safe(res))))
    end
    if ST.RefreshTests then ST.RefreshTests() end
end)

local function registerPrefix()
    if ST.prefixRegistered or not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return end
    local ok, res = pcall(C_ChatInfo.RegisterAddonMessagePrefix, ST.prefix)
    ST.prefixRegistered = ok
    push(ST.msgLog, "register prefix -> " .. (ok and safe(res) or ("ERR " .. safe(res))))
end

function ST.SendPings(whisperTarget)
    registerPrefix()
    local id = tostring(math.floor(GetTime() * 1000) % 100000)
    local targets = {}
    local g = groupChannel()
    if g then targets[#targets + 1] = { g } end
    if IsInGuild() then targets[#targets + 1] = { "GUILD" } end
    if whisperTarget and whisperTarget ~= "" then targets[#targets + 1] = { "WHISPER", whisperTarget } end
    if #targets == 0 then push(ST.msgLog, "nothing to send to: not grouped, not in guild, no whisper name") end
    for _, tg in ipairs(targets) do
        local ok, res = pcall(C_ChatInfo.SendAddonMessage, ST.prefix, "PING:" .. id, tg[1], tg[2])
        push(ST.msgLog, string.format("%s SEND PING:%s %s%s -> %s", date("%H:%M:%S"), id, tg[1],
            tg[2] and (" " .. tg[2]) or "", ok and safe(res) or ("ERR " .. safe(res))))
    end
    if ST.RefreshTests then ST.RefreshTests() end
end

-- The prefix must be registered before CHAT_MSG_ADDON delivers anything.
function ST.OnLogin()
    registerPrefix()
end

----------------------------------------------------------------------
-- Sound and frame flip (manual, button-driven)
----------------------------------------------------------------------
local soundResult = "not run yet (press 'Sound/flip')"
local flip
function ST.RunSoundFlip()
    local parts = {}
    local ok1, willPlay = pcall(PlaySoundFile, TEST_SOUNDFILE, "Master")
    parts[#parts + 1] = "PlaySoundFile(Media/test.ogg) " ..
        (ok1 and ("willPlay=" .. safe(willPlay)) or ("ERR " .. safe(willPlay)))
    local kit = (SOUNDKIT and (SOUNDKIT.READY_CHECK or SOUNDKIT.IG_MAINMENU_OPEN)) or 8960
    local ok2, wp2 = pcall(PlaySound, kit, "Master")
    parts[#parts + 1] = "PlaySound(" .. safe(kit) .. ") " .. (ok2 and ("willPlay=" .. safe(wp2)) or ("ERR " .. safe(wp2)))
    if not flip then
        flip = CreateFrame("Frame", nil, UIParent)
        flip:SetSize(96, 96)
        flip:SetPoint("CENTER", 0, 160)
        flip.tex = flip:CreateTexture(nil, "ARTWORK")
        flip.tex:SetAllPoints()
        flip:Hide()
    end
    local frames = { "Interface\\Icons\\INV_Misc_QuestionMark", "Interface\\Icons\\Spell_Shadow_Teleport" }
    local n = 0
    flip:Show()
    if flip.ticker then flip.ticker:Cancel() end
    flip.ticker = C_Timer.NewTicker(0.25, function()
        n = n + 1
        flip.tex:SetTexture(frames[n % 2 + 1])
        if n % 2 == 0 then flip.tex:SetTexCoord(0, 1, 0, 1) else flip.tex:SetTexCoord(1, 0, 0, 1) end
        if n >= 8 then flip.ticker:Cancel() flip:Hide() end
    end)
    parts[#parts + 1] = "flip frame shown for 2s (did the icon swap and mirror? did you hear a sound?)"
    soundResult = table.concat(parts, "\n")
    if ST.RefreshTests then ST.RefreshTests() end
end

----------------------------------------------------------------------
-- Tests
----------------------------------------------------------------------
local function lastLines(list, n)
    local out = {}
    for i = math.max(1, #list - n + 1), #list do out[#out + 1] = list[i] end
    return out
end

ST.tests = {
    { name = "Client build", run = function()
        local v, b, d, toc = GetBuildInfo()
        local status = (toc == 16001) and "pass" or "info"
        return status, string.format("version=%s build=%s date=%s toc=%s (TOC file says 16001)",
            safe(v), safe(b), safe(d), safe(toc))
    end },

    { name = "API presence", run = function()
        local want = {
            { "C_ChatInfo.SendAddonMessage", C_ChatInfo and C_ChatInfo.SendAddonMessage },
            { "C_ChatInfo.RegisterAddonMessagePrefix", C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix },
            { "C_Map.GetBestMapForUnit", C_Map and C_Map.GetBestMapForUnit },
            { "C_Map.GetMapInfo", C_Map and C_Map.GetMapInfo },
            { "UnitChannelInfo", UnitChannelInfo },
            { "UnitSpellTargetName", UnitSpellTargetName },
            { "C_Spell.GetSpellName", C_Spell and C_Spell.GetSpellName },
            { "issecretvalue", issecretvalue },
            { "C_Timer.NewTicker", C_Timer and C_Timer.NewTicker },
            { "PlaySoundFile", PlaySoundFile },
        }
        local missing, have = {}, 0
        for _, w in ipairs(want) do
            if w[2] then have = have + 1 else missing[#missing + 1] = w[1] end
        end
        local detail = have .. "/" .. #want .. " present"
        if #missing > 0 then detail = detail .. "; missing: " .. table.concat(missing, ", ") end
        return (#missing == 0) and "pass" or "fail", detail
    end },

    { name = "Summon cast event", run = function()
        local lines, hit = {}, false
        for _, e in ipairs(lastLines(ST.castLog, 8)) do
            lines[#lines + 1] = string.format("%s %s id=%s '%s' target=%s spellTarget=%s tgtUnit=%s%s",
                e.t, e.event, e.spellID, e.name, e.target, e.spellTarget or "-", e.tgt,
                e.ritual and "  <== RITUAL" or "")
        end
        for _, e in ipairs(ST.castLog) do if e.ritual and e.event == "SUCCEEDED" then hit = true end end
        local head = "registered: " .. table.concat(registered, ",")
        if #regFailed > 0 then head = head .. " | FAILED to register: " .. table.concat(regFailed, ",") end
        if #lines == 0 then
            return "info", head .. "\nNo casts yet. Cast Ritual of Summoning (spell " .. RITUAL_ID .. ")."
        end
        return hit and "pass" or "info", head .. "\n" .. table.concat(lines, "\n")
    end },

    { name = "Summon target", run = function()
        local hit
        for i = #ST.castLog, 1, -1 do
            local e = ST.castLog[i]
            if e.ritual then hit = hit or e end
            if e.ritual and (e.target ~= "nil" or (e.spellTarget and e.spellTarget ~= "nil")) then
                return "pass", string.format("%s: target=%s spellTarget=%s targetUnit=%s",
                    e.event, e.target, e.spellTarget or "-", e.tgt)
            end
        end
        if hit then
            return "fail", string.format("ritual seen but no target field: target=%s spellTarget=%s; current target unit=%s",
                hit.target, hit.spellTarget or "-", hit.tgt)
        end
        return "info", "no ritual cast seen yet"
    end },

    { name = "Channel info on party", run = function()
        local ok, name, _, _, _, _, _, _, id = pcall(UnitChannelInfo, "player")
        local detail = "player=" .. (ok and (safe(name) .. "/" .. safe(id)) or "ERR") .. "  " .. channelSnapshot()
        local snaps = {}
        for _, e in ipairs(ST.castLog) do
            if e.snap then snaps[#snaps + 1] = e.t .. " " .. e.event .. ": " .. e.snap end
        end
        if #snaps > 0 then
            detail = detail .. "\nSnapshots taken at ritual events:\n" .. table.concat(lastLines(snaps, 4), "\n")
        end
        local pass = false
        for _, s in ipairs(snaps) do if s:find("Ritual", 1, true) then pass = true end end
        return pass and "pass" or "info", detail
    end },

    { name = "Roster snapshot", run = function()
        local out = {}
        for _, unit in ipairs(partyTokens()) do
            if UnitExists(unit) then
                local okR, inRange = pcall(UnitInRange, unit)
                out[#out + 1] = string.format("%s name=%s full=%s guid=%s inRange=%s connected=%s", unit,
                    safe(UnitName(unit)), safe(GetUnitName(unit, true)), safe(UnitGUID(unit)),
                    okR and safe(inRange) or "ERR", safe(UnitIsConnected(unit)))
            end
        end
        if #out == 0 then return "info", "not in a party (IsInGroup=" .. safe(IsInGroup()) .. ")" end
        return "pass", table.concat(out, "\n")
    end },

    { name = "Zone lookup", run = function()
        local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
        if not ok then return "error", safe(mapID) end
        if not mapID then return "fail", "GetBestMapForUnit returned nil (instance? restricted?)" end
        local okI, info = pcall(C_Map.GetMapInfo, mapID)
        local inInst, instType = IsInInstance()
        return "pass", string.format("mapID=%s name=%s zone=%s subzone=%s inInstance=%s(%s)", safe(mapID),
            okI and info and safe(info.name) or "?", safe(GetZoneText()), safe(GetSubZoneText()),
            safe(inInst), safe(instType))
    end },

    { name = "Addon messages", run = function()
        local lines = lastLines(ST.msgLog, 12)
        if #lines == 0 then
            return "info", "Nothing sent yet. Press 'Ping' (party+guild) or /sc test ping <name> for whisper."
        end
        local gotOther = false
        for _, l in ipairs(lines) do
            if l:find("RECV", 1, true) and not l:find("(self)", 1, true) then gotOther = true end
        end
        return gotOther and "pass" or "info", table.concat(lines, "\n")
    end },

    { name = "Save and reload", run = function()
        local h = ST.db and ST.db.harness
        if not h then return "error", "SummonTrackerDB not initialised" end
        if ST.previousToken then
            return "pass", string.format("token %s written %s survived reload/relog",
                safe(ST.previousToken), safe(h.writtenAt))
        end
        if not h.token then
            h.token = string.format("%d-%d", time(), math.random(1000, 9999))
            h.writtenAt = date("%Y-%m-%d %H:%M:%S")
        end
        return "info", "token " .. h.token .. " written. /reload, then reopen /sc test. (/sc test resetsave to retest)"
    end },

    { name = "Name resolution", run = function()
        local ok, name, realm = pcall(UnitFullName, "player")
        local out = {
            string.format("player: UnitName=%s UnitFullName=%s-%s GetUnitName(true)=%s", safe(UnitName("player")),
                ok and safe(name) or "ERR", ok and safe(realm) or "ERR", safe(GetUnitName("player", true))),
            "normalized realm: " .. safe(GetNormalizedRealmName and GetNormalizedRealmName()),
        }
        for _, unit in ipairs(partyTokens()) do
            if UnitExists(unit) then
                out[#out + 1] = string.format("%s: UnitName=%s GetUnitName(true)=%s", unit,
                    safe(UnitName(unit)), safe(GetUnitName(unit, true)))
            end
        end
        if #ST.senderNames > 0 then out[#out + 1] = "addon-msg senders: " .. table.concat(ST.senderNames, ", ") end
        return "info", table.concat(out, "\n")
    end },

    { name = "Sound and frames", run = function()
        return "info", soundResult
    end },

    { name = "Secret-value guard", run = function()
        local calls = {
            { "UnitName(player)", function() return UnitName("player") end },
            { "UnitChannelInfo(player)", function() return UnitChannelInfo("player") end },
            { "UnitChannelInfo(party1)", function() return UnitChannelInfo("party1") end },
            { "UnitGUID(party1)", function() return UnitGUID("party1") end },
            { "UnitInRange(party1)", function() return UnitInRange("party1") end },
            { "UnitHealth(party1)", function() return UnitHealth("party1") end },
            { "GetBestMapForUnit(player)", function() return C_Map.GetBestMapForUnit("player") end },
            { "GetBestMapForUnit(party1)", function() return C_Map.GetBestMapForUnit("party1") end },
        }
        local errs, secrets, clean = {}, {}, 0
        for _, c in ipairs(calls) do
            local res = { pcall(c[2]) }
            if not res[1] then
                errs[#errs + 1] = c[1] .. ": " .. safe(res[2])
            else
                local sec = false
                for i = 2, #res do if ST.isSecret(res[i]) then sec = true end end
                if sec then secrets[#secrets + 1] = c[1] else clean = clean + 1 end
            end
        end
        local detail = clean .. "/" .. #calls .. " clean"
        if #secrets > 0 then detail = detail .. "\nsecret returns: " .. table.concat(secrets, ", ") end
        if #errs > 0 then detail = detail .. "\nerrors: " .. table.concat(errs, "; ") end
        -- Secrets are expected for other units in 12.0; they only matter for what the addon relies on.
        if #secrets > 0 then detail = detail .. "\n(secrets on other units are expected; just don't branch on those calls)" end
        local status = #errs > 0 and "error" or (#secrets > 0 and "info" or "pass")
        return status, detail
    end },
}

function ST.RunTests()
    local results = {}
    for i, t in ipairs(ST.tests) do
        local ok, status, detail = pcall(t.run)
        if not ok then status, detail = "error", safe(status) end
        results[i] = { name = t.name, status = status, detail = detail }
    end
    ST.results = results
    return results
end

function ST.BuildReport()
    local results = ST.RunTests()
    local lines = { string.format("SummonCore v%s diagnostics %s", ST.version, date("%Y-%m-%d %H:%M:%S")) }
    for _, r in ipairs(results) do
        lines[#lines + 1] = string.format("[%s] %s", r.status:upper(), r.name)
        lines[#lines + 1] = "    " .. (tostring(r.detail):gsub("\n", "\n    "))
    end
    return table.concat(lines, "\n")
end

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------
local COLORS = { pass = "ff33ff66", fail = "ffff4444", error = "ffff8800", info = "ffffd100" }
local panel, rowStrings, report

local function makeButton(parent, text, width, onClick, x)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetText(text)
    b:SetPoint("BOTTOMLEFT", x, 12)
    b:SetScript("OnClick", onClick)
    return b
end

local function showReport()
    if not report then
        report = CreateFrame("Frame", "SummonCoreReport", UIParent, "BasicFrameTemplateWithInset")
        report:SetSize(600, 400)
        report:SetPoint("CENTER")
        report:SetFrameStrata("DIALOG")
        report.TitleText:SetText("SummonCore report (Ctrl+A, Ctrl+C)")
        local sf = CreateFrame("ScrollFrame", nil, report, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 12, -30)
        sf:SetPoint("BOTTOMRIGHT", -32, 12)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(540)
        eb:SetScript("OnEscapePressed", function() report:Hide() end)
        sf:SetScrollChild(eb)
        report.edit = eb
    end
    report.edit:SetText(ST.BuildReport())
    report:Show()
    report.edit:SetFocus()
    report.edit:HighlightText()
end

local function buildPanel()
    panel = CreateFrame("Frame", "SummonCoreTests", UIParent, "BasicFrameTemplateWithInset")
    panel:Hide() -- a new frame is visible; start hidden so the toggle shows it on the first command
    panel:SetSize(640, 560)
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel.TitleText:SetText("SummonCore diagnostics")
    tinsert(UISpecialFrames, "SummonCoreTests")

    local sf = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -30)
    sf:SetPoint("BOTTOMRIGHT", -32, 46)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(580, 10)
    sf:SetScrollChild(child)
    panel.child = child

    rowStrings = {}
    makeButton(panel, "Run all", 80, function() ST.RefreshTests() end, 12)
    makeButton(panel, "Ping", 80, function() ST.SendPings() end, 98)
    makeButton(panel, "Sound/flip", 90, function() ST.RunSoundFlip() end, 184)
    makeButton(panel, "Copy report", 100, showReport, 280)
end

function ST.RefreshTests()
    if not panel or not panel:IsShown() then return end
    local results = ST.RunTests()
    local prev
    local total = 0
    for i, r in ipairs(results) do
        local fs = rowStrings[i]
        if not fs then
            fs = panel.child:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            fs:SetWidth(570)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(true)
            if prev then fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -8)
            else fs:SetPoint("TOPLEFT", 4, -4) end
            rowStrings[i] = fs
        end
        fs:SetText(string.format("|c%s[%s]|r |cffffffff%s|r\n%s", COLORS[r.status] or COLORS.info,
            r.status:upper(), r.name, tostring(r.detail)))
        total = total + fs:GetStringHeight() + 8
        prev = fs
    end
    panel.child:SetHeight(total + 8)
end

function ST.ToggleTests(arg)
    arg = arg or ""
    local sub, name = arg:match("^(%S*)%s*(.-)$")
    sub = sub:lower()
    if sub == "ping" then
        ST.SendPings(name)
    elseif sub == "resetsave" then
        ST.db.harness.token, ST.db.harness.writtenAt, ST.previousToken = nil, nil, nil
        ST.print("save/reload token cleared")
    end
    if not panel then buildPanel() end
    if sub == "" and panel:IsShown() then panel:Hide() return end
    panel:Show()
    ST.RefreshTests()
end
