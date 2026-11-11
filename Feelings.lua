-- Feelings: one click a week on how the last week felt (design/lenses.md, Playtesting revisited). Asked once, at the first login of a
-- week, after the week's own lines; three buttons, or close it to skip. Zennit is asked his own question. Answers go to Zennit's and
-- the admin's clients only (Sync, message F), and `/sc feelings` there shows counts, never who said what. `/sc feelings off` stops it.
local ADDON, ST = ...
local Feelings = {}
ST.Feelings = Feelings
local T = ST.Theme

Feelings.PARTY = { "Good fun", "It was fine", "Not for me" }
Feelings.ZENNIT = { "Bring it on", "Fine", "Too much" }

-- Records this client's answer for the week starting at `week` (n: 1 good to 3 bad) and sends it.
function Feelings.Answer(week, n)
    local s = ST.db.settings
    local a = { role = ST.Gag.IsZennit() and "z" or "p", n = n }
    s.feelMine = s.feelMine or {}
    s.feelMine[week] = a
    for w in pairs(s.feelMine) do if w < time() - ST.Sync.FEEL_KEEP then s.feelMine[w] = nil end end
    ST.Sync.PutFeeling(ST.Sync.myName(), week, a.role, n) -- Zennit's and the admin's own answers count too
    ST.Sync.SendFeeling(week, a)
    ST.print("The Index has filed your opinion. Thank you. It will not be read aloud.")
    ST.Achieve.Soon()
end

-- The week to ask about: last week, if it had any summons and has not been asked about; else nil.
function Feelings.Due()
    local s = ST.db and ST.db.settings
    if not s or s.feelOff then return nil end
    local last = ST.Week.Start() - 7 * 86400
    if s.feelAsked == last then return nil end
    if ST.Week.Score(last).summons == 0 then return nil end
    return last
end

local window
local function ask(week)
    if not window then
        window = T.Window("SummonCoreFeelings", 520, 150)
        window.TitleText:SetText("THE INDEX ASKS")
        window.text = T.Text(window, 18, "green")
        window.text:SetPoint("TOPLEFT", 16, -36)
        window.text:SetWidth(488)
        window.text:SetJustifyH("LEFT")
        window.buttons = {}
        for i = 1, 3 do
            local b = T.Button(window, "", 156, 26, function()
                window:Hide()
                Feelings.Answer(window.week, i)
            end, i == 3 and "danger" or nil)
            b:SetPoint("BOTTOMLEFT", 16 + (i - 1) * 166, 14)
            window.buttons[i] = b
        end
    end
    local zennit = ST.Gag.IsZennit()
    local words = zennit and Feelings.ZENNIT or Feelings.PARTY
    window.week = week
    window.text:SetText(zennit and "The Index is gathering opinions. How was being summoned last week? (Only the admin sees the count.)"
        or "The Index is gathering opinions. How was last week? (Nobody sees who said what. Close this to skip.)")
    for i = 1, 3 do window.buttons[i]:SetText(words[i]) end
    window:Show()
end
Feelings.ask = ask -- a seam for the self-test

-- At login, once a week: ask about last week.
function Feelings.Check()
    local week = Feelings.Due()
    if not week then return end
    ST.db.settings.feelAsked = week
    Feelings.ask(week)
end

-- What Zennit and the admin see: counts per week, newest first, never names. Lines, or nil for anyone else.
function Feelings.Summary(weeks)
    if not (ST.Gag.IsZennit() or ST.IsAdmin()) then return nil end
    local all = ST.db.settings.feelings or {}
    local list = {}
    for w in pairs(all) do list[#list + 1] = w end
    table.sort(list, function(a, b) return a > b end)
    local out = {}
    for i = 1, math.min(#list, weeks or 4) do
        local w = list[i]
        local p, z = { 0, 0, 0 }, nil
        for _, a in pairs(all[w]) do
            if a.role == "z" then z = a.n else p[a.n] = p[a.n] + 1 end
        end
        out[#out + 1] = string.format("Week of %s: %d %s, %d %s, %d %s; Zennit: %s.", date("%d %b", w), p[1], Feelings.PARTY[1]:lower(),
            p[2], Feelings.PARTY[2]:lower(), p[3], Feelings.PARTY[3]:lower(), z and Feelings.ZENNIT[z]:lower() or "no answer")
    end
    if #out == 0 then out[1] = "No opinions filed yet. They are asked once a week, at the first login." end
    return out
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function() C_Timer.After(75, function() ST.Guard("the weekly question", Feelings.Check) end) end)
