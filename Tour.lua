-- Tour: /sc tour, a guided tour of the Summon Core window, narrated by the Index. It opens the real window, moves through
-- its tabs, and outlines each part as the narrator talks about it, with the words typed out in a box under the window.
-- One recording per line (Media\tour\<id>.ogg, lengths in TourClips.lua); a step lasts as long as its recording, so it
-- runs by itself, and Back, Pause and Next take over at any point. Zennit's client gets his own lines for the two tabs
-- that are closed to one side or the other.
-- Rebuild the recordings with tools/intro/build_tour_audio.py after changing LINES (.claude/skills/zenit-narrator-audio).
local ADDON, ST = ...
setfenv(1, ST.env) -- the addon's own globals (Core.lua)
local Tour = {}
ST.Tour = Tour
local T = ST.Theme

local MEDIA = "Interface\\AddOns\\summoncore\\Media\\tour\\"
local GAP = 0.8      -- a breath between one line and the next
local CPS = 18       -- typing speed when a line has no recording (characters a second)

-- What the Index says, one id = "sentence" per line. The voice is given the same words, with /sc spelled "slash S C".
-- build_tour_audio.py reads this table, so keep each entry on one line in this form.
local LINES = {
    hello = "This is a short tour of Summon Core, conducted by the Index, which has been asked to be helpful and is doing its best. Close it whenever you like. The Index will not take it personally.",
    nothing_new = "First, the good news. You do not have to do anything new. Cast the ritual and click the portal as you always have, and the Index notices on its own.",
    caster = "One thing to remember. A summons of Zennit is filed if the caster or Zennit has Summon Core. The helpers are credited if the caster has it, or if anyone at the portal does.",
    z_nothing_new = "First, the good news. You do not have to do anything new. Answer the game's summons prompt as you always have, and the Index takes that as your answer.",
    window = "This is the window. Type /sc and it opens. Everything the Index knows about you is in here, which is either reassuring or not.",
    season = "Along the top runs the season. Zennit in pink, the group in cyan. Each block is a week won, and the first side to five takes the season.",
    week = "On the right is this week: who leads, and by how much, how many summons are filed, and how many dice Zennit has left.",
    party = "The Party tab is yours. It has a summary of you, the tally of who has cast and who has helped, and the badges you have earned.",
    tally = "The tally ranks everyone by summons of Zennit this season, which is the only thing the race counts.",
    zennit = "The Zennit tab belongs to Zennit. Please do not open it. The Index has arranged a small deterrent.",
    z_party = "The Party tab belongs to the group, and is closed to you. The Index apologises in advance for what happens if you try.",
    z_zennit = "This tab is yours. Here you answer the summons waiting for you, keep your secret list of five places, and may close the Index once five summons are filed.",
    log = "The Log is every summons filed: who cast it, who helped, where it landed, and what Zennit said.",
    story = "The Story is a tree of chapters. Each weekly win unlocks the next chapter on that side. Click a lit chapter to watch it.",
    sync = "Sync keeps everyone's Index the same, through your party and your guild. It works on its own. You need do nothing.",
    tools = "Tools holds the rest: the rules with this week's numbers, the titles, the silver owed, and the record of past seasons.",
    writ = "If you expect Zennit to refuse, play a writ before you cast, with /sc writ, or with a key of your own, set under Summon Core in the game's key bindings. You have two a week. If he declines, it costs him the points.",
    places = "Where he is summoned matters. A city is worth one point, a zone three, a dungeon entrance five, and a far-flung place ten. /sc where tells you what the spot you are standing on is worth, and /sc places lists them all.",
    briefing = "When you begin the ritual on Zennit, the Index briefs you in chat: which summons of the week this is, who leads, his dice, and what the place is worth. The first of the week says everything. After that, it keeps it short.",
    week_say = "To rally the group, /sc week say tells your party where the week stands, in one line. /sc week copy gives you the same line, to paste wherever you like.",
    z_cards = "You may sell summon cards: prepaid silver, punched once a summons, with /sc card sell. A summoner holding one pays with a punch, and the Index asks no questions.",
    z_away = "And when you win a week and go on leave, /sc zennit away sets your out-of-office, which the Index reads to anyone who tries to summon you.",
    status = "Along the bottom, the Index reports how many records it holds, and who it is talking to.",
    commands = "Three commands are worth remembering. /sc rules, for the race in a minute. /sc intro, for the story. And /sc help, for everything else.",
    popups = "Now and then, the Index will put something in front of you. Here is what to expect, so that none of it comes as a surprise.",
    assist = "When you cast, and the Index cannot tell who helped, it asks. Tick the two who clicked. Ignore it, and it saves itself after twenty seconds, as ticked.",
    dice = "If Zennit suggests dice, this appears. Press roll. Beat his roll, plus his edge, and the summons counts. Your helpers add to your roll.",
    z_popups = "When someone summons you, the Index puts its form in front of you. Here is a copy, so that it comes as no surprise.",
    z_summoning = "It says who summoned you, and where to, what it is worth, and how the week stands. You may simply answer the game's own prompt, and the Index takes that as your answer.",
    z_choices = "Or choose here. Accept it. Decline it: the first decline each week is free. Name a price, in silver. Or roll the dice, three times a week.",
    asks = "Once a week, the Index asks how the week went. One click, or close it to skip. Nobody sees who said what.",
    watch = "Sometimes a friend will show the group a chapter of the story, and the Index asks whether you would like to watch. Watch plays it. Not now does not. When a raid gathers, its leader may be offered last week's chapter in the same way.",
    z_price = "Name a price, and the Index asks how much. Fifty silver, two gold, whatever you fancy. The summons counts either way, and the silver goes on the tab.",
    z_paid = "When silver arrives by trade or by mail, the Index notices, and offers to mark the summons paid. Say yes, and the tab is settled.",
    reset = "Very rarely, the admin may ask everyone to start the Index afresh. Press reset only if the admin has told you it is coming. Otherwise, cancel.",
    goodbye = "That concludes the tour. The Index thanks you for your attention, which it has noted. Go and summon someone. Preferably Zennit.",
    z_goodbye = "That concludes the tour. The Index thanks you for your attention, which it has noted. Go and summon someone. Preferably not Zennit.",
}
Tour.LINES = LINES

-- The tour, in order. tab: the window's tab to show (a Party section opens the Party tab on it); spot: what to outline
-- (Hub.Spot, or "demo" and "demo:<part>" for the popup on show, "popup" for a game dialog); demo: a copy of a popup to
-- show (DEMOS, below); popup: one of the game's own dialogs to show, with buttons that do nothing (POPUPS, below);
-- only: "party" or "zennit", for the steps one side gets instead of the other.
local STEPS = {
    { line = "hello", spot = "window" },
    { line = "nothing_new", only = "party" },
    { line = "z_nothing_new", only = "zennit" },
    { line = "caster", only = "party" },
    { line = "window", spot = "window" },
    { line = "season", spot = "season" },
    { line = "week", spot = "week" },
    { line = "party", tab = "summary", spot = "tab:party", only = "party" },
    { line = "tally", tab = "tally", spot = "section:tally", only = "party" },
    { line = "zennit", spot = "tab:zennit", only = "party" },
    { line = "z_party", spot = "tab:party", only = "zennit" },
    { line = "z_zennit", tab = "zennit", spot = "tab:zennit", only = "zennit" },
    { line = "log", tab = "log", spot = "tab:log" },
    { line = "story", tab = "story", spot = "tab:story" },
    { line = "sync", tab = "sync", spot = "tab:sync" },
    { line = "tools", tab = "tools", spot = "tab:tools" },
    { line = "places" },
    { line = "briefing", only = "party" },
    { line = "status", spot = "status" },
    { line = "popups", only = "party" },
    { line = "assist", demo = "assist", spot = "demo", only = "party" },
    { line = "dice", demo = "dice", spot = "demo:roll", only = "party" },
    { line = "z_popups", demo = "summoning", spot = "demo", only = "zennit" },
    { line = "z_summoning", demo = "summoning", spot = "demo:text", only = "zennit" },
    { line = "z_choices", demo = "summoning", spot = "demo:buttons", only = "zennit" },
    { line = "z_price", popup = "price", spot = "popup", only = "zennit" },
    { line = "z_paid", popup = "paid", spot = "popup", only = "zennit" },
    { line = "z_cards", only = "zennit" },
    { line = "z_away", only = "zennit" },
    { line = "asks", demo = "asks", spot = "demo" },
    { line = "watch", popup = "watch", spot = "popup" },
    { line = "reset", popup = "reset", spot = "popup" },
    { line = "writ", only = "party" },
    { line = "week_say", spot = "week", only = "party" },
    { line = "commands" },
    { line = "goodbye", spot = "window", only = "party" },
    { line = "z_goodbye", spot = "window", only = "zennit" },
}

-- The steps this client gets: Zennit's lines on his client, the party's on everyone else's.
function Tour.Steps(zennit)
    local list = {}
    for _, s in ipairs(STEPS) do
        if not s.only or (s.only == "zennit") == (zennit and true or false) then list[#list + 1] = s end
    end
    return list
end

-- How long a step lasts: its recording and a breath, or, with no recording, long enough to read it.
function Tour.Length(id)
    local len = ST.tourClips and ST.tourClips[id]
    if len then return len + GAP end
    return #LINES[id] / CPS + 1.5
end

local panel, text, counter, playBtn, glow
local steps, at, t, playing = {}, 1, 0, false
local handle, missing

----------------------------------------------------------------------
-- The popups, as copies: the same look and wording as the real ones, with made-up names and buttons that do nothing. The
-- real ones file a summons or make a real /roll, which a tour must not do. Each has its parts named for the outline.
----------------------------------------------------------------------
local demos = {}
local function demoWindow(title, width, height)
    local w = T.Window(nil, width, height, { strata = "DIALOG" })
    w.TitleText:SetText(title)
    w.CloseButton:SetScript("OnClick", nil)
    local note = T.Text(w, 16, "dim")
    note:SetPoint("BOTTOMRIGHT", -10, -18)
    note:SetText("THE TOUR'S COPY: NOTHING IS FILED")
    w.parts = {}
    return w
end
local function demoText(w, x, y, width, height, words)
    local fs = T.Text(w, 18, "green")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetSize(width, height)
    fs:SetJustifyV("TOP")
    fs:SetText(words)
    return fs
end
local function demoButton(w, label, width, style)
    return T.Button(w, label, width, 28, function() end, style)
end

local DEMOS = {
    -- the caster's prompt when the helpers are not clear (Prompt.lua)
    assist = function()
        local w = demoWindow("SUMMON LOGGED", 320, 230)
        demoText(w, 16, -36, 288, 44, "Who helped with the summon of " .. T.Paint("cyan", "Zennit") .. "? Tick up to two ritual assistants.")
        for i, name in ipairs({ "Helper", "Another", "Bystander" }) do
            local cb = T.Check(w, 280)
            cb:SetPoint("TOPLEFT", 20, -82 - (i - 1) * 26)
            cb.Text:SetText(name)
            cb:SetChecked(i < 3)
            cb:SetScript("OnClick", function(self) self:SetChecked(i < 3) end)
        end
        local ok = demoButton(w, "CONFIRM (20)", 110, "primary")
        ok:SetPoint("BOTTOMLEFT", 16, 12)
        demoButton(w, "SAVE UNCONFIRMED", 150):SetPoint("BOTTOMRIGHT", -16, 12)
        return w
    end,
    -- the summoner's side when Zennit suggests dice (Respond.lua)
    dice = function()
        local w = demoWindow("DICE!", 400, 200)
        demoText(w, 18, -40, 364, 90, "Zennit suggests dice for your summon of him, and has rolled 62.\n\nRoll 1-100: beat his roll plus his edge and "
            .. "the summon counts. A tie goes to him. Your helpers add to your roll.")
        w.parts.roll = demoButton(w, "ROLL 1-100", 170, "primary")
        w.parts.roll:SetPoint("BOTTOMLEFT", 18, 16)
        demoButton(w, "CLOSE", 170):SetPoint("BOTTOMRIGHT", -18, 16)
        return w
    end,
    -- Zennit's form when he is summoned (Respond.lua)
    summoning = function()
        local w = demoWindow("A SUMMONING!", 440, 380)
        w.parts.text = demoText(w, 18, -40, 404, 190, T.Paint("cyan", "Tester") .. " has summoned you to Sentinel Hill.\n("
            .. "zone, " .. T.Paint("amber", "3 points") .. ". Helped by Helper.)\nIf you decline it in the game it is free: you have 1 free "
            .. "decline this week.\nThe Index's tally for the week: you lead by 2, 3 of 10 filed, 3 dice left. How will you deal with it? "
            .. "(Ignore it and it counts as accepted.)")
        local labels = { "ACCEPT IT", "DECLINE (FREE)", "NAME A PRICE, IN SILVER (NO RECEIPT)", "ROLL THE DICE (1-100)" }
        local first, last
        for i, label in ipairs(labels) do
            local b = demoButton(w, label, 404, i == 1 and "primary" or nil)
            b:SetPoint("TOPLEFT", 18, -40 - 190 - 6 - (i - 1) * 34)
            first, last = first or b, b
        end
        w.parts.buttons = CreateFrame("Frame", nil, w)
        w.parts.buttons:SetPoint("TOPLEFT", first, "TOPLEFT")
        w.parts.buttons:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT")
        return w
    end,
    -- the weekly question (Feelings.lua)
    asks = function()
        local w = demoWindow("THE INDEX ASKS", 520, 150)
        demoText(w, 16, -36, 488, 50, ST.Gag.IsZennit()
            and "The Index is gathering opinions. How was being summoned last week? (Only the admin sees the count.)"
            or "The Index is gathering opinions. How was last week? (Nobody sees who said what. Close this to skip.)")
        local labels = ST.Gag.IsZennit() and { "BRING IT ON", "FINE", "TOO MUCH" } or { "GOOD FUN", "IT WAS FINE", "NOT FOR ME" }
        for i, label in ipairs(labels) do demoButton(w, label, 156, "normal"):SetPoint("BOTTOMLEFT", 16 + (i - 1) * 164, 16) end
        return w
    end,
}

local function demo(name)
    local zennit = ST.Gag.IsZennit() -- the weekly question is worded for one side or the other (and test mode can switch)
    if not demos[name] or demos[name].zennit ~= zennit then
        if demos[name] then demos[name]:Hide() end
        demos[name] = DEMOS[name]()
        demos[name].zennit = zennit
    end
    return demos[name]
end

local function hideDemos()
    for _, w in pairs(demos) do w:Hide() end
end

----------------------------------------------------------------------
-- The game's own dialogs (StaticPopup): these are shown for real, since their buttons only run what they are handed, and
-- the tour hands them nothing to do. Each gives the dialog's name, its words (as the real one says them, with made-up
-- names) and its data.
----------------------------------------------------------------------
local EXAMPLE = "\n\n(The tour's example: the buttons do nothing.)"
local nothing = function() end
local POPUPS = {
    watch = function()
        local title = ST.Intro.ChapterTitle("z1") or "chapter 2: The count"
        return "SUMMONCORE_ASK", "Tester would like to show the group " .. title .. ". Watch now?" .. EXAMPLE, nothing
    end,
    price = function()
        return "SUMMONCORE_ASK_SILVER", "The Index asks how much silver you ask of Tester, in cash, with no receipt. (50, 2g, 1g 20s.) "
            .. "The summons counts either way; the silver goes on the tab." .. EXAMPLE, { default = 50, go = nothing }
    end,
    paid = function()
        return "SUMMONCORE_SILVER", "Tester has paid you 50s by trade. The Index would like to mark 1 of Tester's summons paid (50 silver)."
            .. EXAMPLE, nothing
    end,
    reset = function()
        return "SUMMONCORE_RESET", "The admin asks everyone to reset all summons, badges and the story. Do it on this client?" .. EXAMPLE, nothing
    end,
}
Tour.POPUPS = POPUPS
local shown -- the dialog the tour put up: { which, dialog, data }

local function hidePopup()
    local p = shown
    shown = nil
    -- only ours: StaticPopup_Hide with data hides the dialog holding that data, so a real request is left alone
    if p then StaticPopup_Hide(p.which, p.data) end
end

local function showPopup(name)
    local which, words, data = POPUPS[name]()
    if StaticPopup_Visible(which) then return end -- a real one is up: never write over it
    shown = { which = which, data = data, dialog = StaticPopup_Show(which, words, nil, data) }
end

-- The region a step outlines: a part of the window, or of the popup it shows. Builds the popup if need be (not shown).
function Tour.Spot(step)
    if not step.spot then return nil end
    if step.spot == "popup" then return shown and shown.dialog end
    if step.spot == "demo" then return demo(step.demo) end
    local part = step.spot:match("^demo:(%w+)$")
    if part then return demo(step.demo).parts[part] end
    return ST.Hub.Spot(step.spot)
end

local function stopVoice()
    if handle then
        pcall(StopSound, handle)
        handle = nil
    end
end

local function muted() return ST.db.settings.introSound == false end

local function outline(region)
    if not region then return glow:Hide() end
    glow:ClearAllPoints()
    glow:SetPoint("TOPLEFT", region, "TOPLEFT", -4, 4)
    glow:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 4, -4)
    glow:Show()
end

-- Shows step i: its tab, its outline, its line typed from the start, and its recording.
local function go(i)
    at = math.max(1, math.min(#steps, i))
    t = 0
    local s = steps[at]
    for k = at, 1, -1 do -- the tab this step is on: its own, or the last one opened before it (so Back puts it right)
        if steps[k].tab then
            ST.Hub.Open(steps[k].tab)
            break
        end
    end
    hideDemos()
    hidePopup()
    if s.popup then showPopup(s.popup) end
    if s.demo then
        local w = demo(s.demo)
        w:ClearAllPoints()
        w:SetPoint("CENTER", ST.Hub.Window(), "CENTER", 0, 20)
        w:Show()
    end
    outline(Tour.Spot(s))
    counter:SetText(string.format("TOUR.EXE  %d/%d", at, #steps))
    if at == #steps then ST.db.settings.tourSeen = true end
    stopVoice()
    if playing and not muted() then
        local ok, willPlay, h = pcall(PlaySoundFile, MEDIA .. s.line .. ".ogg", "Dialog")
        missing = not (ok and willPlay)
        handle = h
    end
end

local function setPlaying(p)
    playing = p
    playBtn:SetText(p and "PAUSE" or "PLAY")
    if p then go(at) else stopVoice() end -- a recording cannot resume mid-way: playing again starts the line over
end

local function build()
    panel = CreateFrame("Frame", "SummonCoreTour", UIParent)
    panel:Hide()
    panel:SetSize(800, 132)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    T.Panel(panel, { fill = "ground", color = "amber", width = 2, glow = true })
    tinsert(UISpecialFrames, "SummonCoreTour")

    counter = T.Text(panel, 18, "amber")
    counter:SetPoint("TOPLEFT", 12, -8)
    local cursor = T.Cursor(panel)
    cursor:SetPoint("LEFT", counter, "RIGHT", 6, 0)
    text = T.Text(panel, 20, "green")
    text:SetPoint("TOPLEFT", 12, -30)
    text:SetPoint("TOPRIGHT", -12, -30)
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)

    local x = 12
    local function btn(label, width, onClick, style)
        local b = T.Button(panel, label, width, 24, onClick, style)
        b:SetPoint("BOTTOMLEFT", x, 10)
        x = x + width + 6
        return b
    end
    btn("< BACK", 90, function() go(at - 1) end)
    playBtn = btn("PAUSE", 90, function() setPlaying(not playing) end, "primary")
    btn("NEXT >", 90, function()
        if at < #steps then go(at + 1) else panel:Hide() end
    end)
    local sound
    sound = btn("", 120, function()
        ST.db.settings.introSound = muted()
        ST.db.settings.introMute = muted() -- the story viewer's copy of the same switch
        sound:SetText("SOUND: " .. (muted() and "OFF" or "ON"))
        if muted() then stopVoice() elseif playing then go(at) end
    end)
    sound:SetText("SOUND: " .. (muted() and "OFF" or "ON"))
    local close = T.Button(panel, "END TOUR", 110, 24, function() panel:Hide() end, "danger")
    close:SetPoint("BOTTOMRIGHT", -12, 10)

    -- the outline: amber, over the window, pulsing gently
    glow = CreateFrame("Frame", nil, UIParent)
    glow:SetFrameStrata("FULLSCREEN_DIALOG") -- over the popups on show too
    glow:EnableMouse(false)
    T.Border(glow, "amber", 1, 3)
    T.Border(glow, "amber", 0.3, 3, 3)
    glow:Hide()
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.35)
    fade:SetDuration(0.6)
    glow:SetScript("OnShow", function() pulse:Play() end)

    panel:SetScript("OnUpdate", ST.Safe("the tour", function(_, elapsed)
        local window = ST.Hub.Window()
        if not (window and window:IsShown()) then return panel:Hide() end -- closing the window ends the tour
        local s = steps[at]
        if playing then
            t = t + elapsed
            if t >= Tour.Length(s.line) then
                if at < #steps then return go(at + 1) end
                setPlaying(false)
            end
        end
        -- typed slightly faster than it is said, so the words are all there before the voice finishes
        local line = LINES[s.line]
        local cps = math.max(CPS, #line / (math.max(1, Tour.Length(s.line) - GAP) * 0.8))
        local typed = playing and line:sub(1, math.floor(t * cps) + 1) or line
        text:SetText(typed .. (missing and not muted() and T.Paint("dim", "   (recording missing: restart WoW fully)") or ""))
    end))
    panel:SetScript("OnHide", function()
        playing = false
        stopVoice()
        glow:Hide()
        hideDemos()
        hidePopup()
    end)
end

-- /sc tour: opens the window and starts the tour from the top (again: stops it). /sc tour <n> starts at step n.
-- The tour's jokes lean on the story (the form, the deterrent, the Index's manner), so until the intro has been seen through
-- it plays first and the tour follows by itself; /sc tour skip goes straight to the tour.
function Tour.Start(arg)
    if not panel then build() end
    if panel:IsShown() and not tonumber(arg or "") then return panel:Hide() end
    if arg == "skip" then
        arg = nil
    elseif not ST.Intro.Watched() then
        ST.print("The tour follows the story, so the intro plays first (about four minutes) and the tour starts when it ends. "
            .. "|cffffd100/sc tour skip|r goes straight to the tour.")
        return ST.Intro.Play("1", function() -- closed before the end: the tour too, if the story's last scene was reached
            if ST.Intro.Watched() then return Tour.Start("skip") end
            ST.print("The tour is waiting for the story: |cffffd100/sc tour|r plays the intro and then the tour, "
                .. "|cffffd100/sc tour skip|r goes straight to it.")
        end, function() Tour.Start("skip") end)
    end
    if SummonCoreIntro and SummonCoreIntro:IsShown() then SummonCoreIntro:Hide() end -- the story viewer would sit over the tour
    steps = Tour.Steps(ST.Gag.IsZennit())
    ST.Hub.Open()
    local window = ST.Hub.Window()
    panel:ClearAllPoints()
    panel:SetPoint("TOP", window, "BOTTOM", 0, -6)
    panel:SetWidth(window:GetWidth())
    panel:Show()
    missing = false
    at = tonumber(arg or "") or 1
    setPlaying(true)
end

function Tour.IsShown() return panel and panel:IsShown() or false end

-- At the end of the first intro seen through, the Index offers the tour, once (not to anyone who has taken it already).
StaticPopupDialogs["SUMMONCORE_TOUR"] = {
    text = "The Index can show you round the Summon Core window now: the tabs, what to press, and the popups you will meet (about six minutes). Take the tour?",
    button1 = "Take the tour", button2 = "Later",
    OnAccept = function() Tour.Start("skip") end,
    OnCancel = function() ST.print("|cffffd100/sc tour|r takes the tour whenever you like.") end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function Tour.Offer()
    local s = ST.db.settings
    if s.tourSeen or s.tourOffered or Tour.IsShown() then return false end
    s.tourOffered = true
    StaticPopup_Show("SUMMONCORE_TOUR")
    return true
end
