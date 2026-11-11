-- Gag: Zennit detection and the "ah-ah-ah" access-denied clip. A joke gate for friends, not security.
local ADDON, ST = ...
setfenv(1, ST.env) -- the addon's own globals (Core.lua)
local Gag = {}
ST.Gag = Gag

local MEDIA = "Interface\\AddOns\\summoncore\\Media\\"

-- Each clip is a sprite sheet (all frames in one power-of-two texture) plus an optional sound:
--   sheet = { file = <path without extension>, cols = n, rows = n, frames = n, fps = n }
--   sound = ".ogg path" (optional; a built-in sound plays if missing)
--   duration = seconds the clip stays up (optional; DURATION below), so it can last as long as its recording
-- Frames run left to right, top to bottom. One clip is picked at random per block, so add more entries
-- as friends record them. Convert each recording outside the game into an .ogg plus a sheet (.tga/.blp).
-- The sheet (tools/make_gag_sheet.ps1) is a neon line-art man wagging his finger, with "AH AH AH!" beside him; the
-- sound is a recording (tools/gag).
local WAG = { file = MEDIA .. "gag_wag_sheet", cols = 4, rows = 2, frames = 8, fps = 10 }
Gag.clips = {
    { sheet = WAG, sound = MEDIA .. "gag_zennit.ogg", duration = 2.9 },
}
-- The party's gag, on Zennit's tab: the same finger, with one of his recordings for the party, picked at random and never the
-- same twice running. gag_party.ogg runs 7.9 s; gag_party_NN.ogg (tools/gag/party, made by tools/gag/make_gag_audio.ps1) run
-- 1.5 to 4.1 s, and stay up a beat longer, and never less than DURATION.
local PARTY_LENGTHS = { ["02"] = 3.6, ["03"] = 1.5, ["04"] = 1.6, ["05"] = 1.9, ["06"] = 3.0, ["07"] = 3.7, ["08"] = 3.0,
    ["09"] = 2.3, ["10"] = 3.8, ["11"] = 4.1, ["12"] = 3.4, ["13"] = 1.8 }
Gag.partyClips = { { sheet = WAG, sound = MEDIA .. "gag_party.ogg", duration = 7.9 } }
for n, secs in pairs(PARTY_LENGTHS) do
    Gag.partyClips[#Gag.partyClips + 1] = { sheet = WAG, sound = MEDIA .. "gag_party_" .. n .. ".ogg", duration = math.max(2.5, secs + 0.3) }
end
table.sort(Gag.partyClips, function(a, b) return a.sound < b.sound end)
local lastParty

local DURATION = 2.5
local SHOW_SIZE = 192
local CAPTION = "Ah ah ah! You didn't say the magic word!"
local PARTY_CAPTION = "Zennit's paperwork. Your curiosity has been filed." -- the gag for the party, on his tab

function Gag.IsZennit()
    local s = ST.db and ST.db.settings
    if not s then return false end
    if s.partyTest then return false end -- party test mode: behave as an ordinary party member, even on his account
    if s.zenitTest then return true end
    if ST.IsZennitAccount() then return true end -- his Battle.net account counts, whichever character he plays
    local me = (UnitName("player") or ""):lower()
    for _, n in ipairs(s.zenitNames or {}) do
        if n:lower() == me then return true end
    end
    return false
end

-- True while the admin is trying the party's side: the admin's usual way into Zennit's tab is closed.
function Gag.IsPartyTest()
    local s = ST.db and ST.db.settings
    return s ~= nil and s.partyTest == true
end

local frame, ticker

-- Points the texture at one cell of the sheet.
local function setFrame(tex, sheet, index)
    local col = index % sheet.cols
    local row = math.floor(index / sheet.cols)
    tex:SetTexCoord(col / sheet.cols, (col + 1) / sheet.cols, row / sheet.rows, (row + 1) / sheet.rows)
end

local function playSound(clip)
    if ST.db.settings.soundOn == false then return end
    if clip and clip.sound then
        local ok, willPlay = pcall(PlaySoundFile, clip.sound, "Master")
        if ok and willPlay then return end
    end
    if ST.Clips.Play("wag") then return end -- a recorded "ah-ah-ah" from Media/clips
    pcall(PlaySound, SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST or 857, "Master")
end

-- caption (optional): what the gag says under the picture; the default is Zennit's "ah ah ah".
-- clip (optional): which clip to play; the default is one of Gag.clips, picked at random.
function Gag.Play(caption, clip)
    clip = clip or Gag.clips[math.random(#Gag.clips)]
    local sheet = clip.sheet
    local duration = clip.duration or DURATION
    playSound(clip)
    if not frame then
        frame = CreateFrame("Frame", nil, UIParent)
        frame:SetSize(SHOW_SIZE, SHOW_SIZE)
        frame:SetPoint("CENTER", 0, 100)
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame.tex = frame:CreateTexture(nil, "ARTWORK")
        frame.tex:SetAllPoints()
        frame.text = ST.Theme.Text(frame, 28, "pink", "OVERLAY")
        frame.text:SetPoint("TOP", frame, "BOTTOM", 0, -6)
    end
    frame.text:SetText(caption or CAPTION)
    frame.tex:SetTexture(sheet.file)
    local n = 0
    setFrame(frame.tex, sheet, 0)
    if ticker then ticker:Cancel() end
    frame:Show()
    ticker = C_Timer.NewTicker(1 / sheet.fps, function()
        n = n + 1
        if n / sheet.fps >= duration then
            ticker:Cancel()
            frame:Hide()
            return
        end
        setFrame(frame.tex, sheet, n % sheet.frames)
    end)
end

-- The same gag for the other side: the party opened Zennit's tab.
function Gag.PlayParty()
    local i = math.random(#Gag.partyClips)
    if #Gag.partyClips > 1 and i == lastParty then i = i % #Gag.partyClips + 1 end
    lastParty = i
    Gag.Play(PARTY_CAPTION, Gag.partyClips[i])
end

-- Returns true (after playing the gag) when the player is Zennit and the content is hidden.
function Gag.Blocked()
    if Gag.IsZennit() then
        Gag.Play()
        return true
    end
    return false
end
