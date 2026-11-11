-- Comic: /sc comic shows generated test textures at different sizes, to find out how large and how
-- sharp images can get in this client. Textures come from tools\make_test_patterns.ps1.
local ADDON, ST = ...
setfenv(1, ST.env) -- the addon's own globals (Core.lua)
local Comic = {}
ST.Comic = Comic

local PATH = "Interface\\AddOns\\summoncore\\Media\\comic_test_"
local TEX_SIZES = { 256, 512, 1024, 2048 }
local SHOW_SIZES = { 256, 512, 1024, "Full" }
local state = { tex = 1024, show = 512, tiled = false }
local controls, view
local buttons = { tex = {}, show = {} }

local function showSide()
    if state.show == "Full" then return math.floor(UIParent:GetHeight()) end
    return state.show
end

-- Screen pixels per UI unit, so we can say how many texels land on each screen pixel.
local function pixelsPerUnit()
    local ok, _, physH = pcall(GetPhysicalScreenSize)
    if ok and physH then return physH / UIParent:GetHeight(), physH end
    return UIParent:GetEffectiveScale(), nil
end

local function updateInfo()
    local ppu, physH = pixelsPerUnit()
    local side = showSide()
    local cell = state.tiled and side / 2 or side
    local screenPx = cell * ppu
    local ratio = state.tex / screenPx
    local verdict = ratio <= 1 and "sharp (texels <= screen pixels)" or "downscaled (more texels than pixels)"
    local w, h = GetPhysicalScreenSize()
    controls.info:SetText(string.format(
        "Screen %sx%s, UI scale %.2f\nTexture %d px, shown %d units%s = %d screen px each\n%.2f texels per screen pixel: %s\n" ..
        "Corners: TL red, TR green, BL blue, BR magenta. A plain green square means the file did not load.\n" ..
        "Right-click the image to hide it. Drag to move.",
        ST.safe(w), ST.safe(h), UIParent:GetEffectiveScale(), state.tex, side,
        state.tiled and " (2x2 tiles)" or "", math.floor(screenPx + 0.5), ratio, verdict))
end

local function refresh()
    if not view then return end
    local side = showSide()
    view:SetSize(side, side)
    local file = PATH .. state.tex
    if state.tiled then
        local half = side / 2
        for i, t in ipairs(view.tiles) do
            t:ClearAllPoints()
            t:SetSize(half, half)
            t:SetPoint(i % 2 == 1 and "TOPLEFT" or "TOPRIGHT", view, i % 2 == 1 and "TOPLEFT" or "TOPRIGHT", 0,
                i <= 2 and 0 or -half)
            t:SetTexture(file)
            t:Show()
        end
    else
        for i, t in ipairs(view.tiles) do
            t:ClearAllPoints()
            if i == 1 then
                t:SetAllPoints(view)
                t:SetTexture(file)
                t:Show()
            else
                t:Hide()
            end
        end
    end
    for _, b in ipairs(buttons.tex) do b:SetText((b.value == state.tex and "|cff33ff66" or "") .. b.value) end
    for _, b in ipairs(buttons.show) do b:SetText((b.value == state.show and "|cff33ff66" or "") .. b.value) end
    controls.tileBtn:SetText(state.tiled and "|cff33ff66Tile 2x2" or "Tile 2x2")
    updateInfo()
end

local function buildView()
    view = CreateFrame("Frame", "SummonCoreComicView", UIParent)
    view:Hide()
    view:SetFrameStrata("DIALOG")
    view:SetPoint("CENTER")
    view:SetMovable(true)
    view:EnableMouse(true)
    view:RegisterForDrag("LeftButton")
    view:SetScript("OnDragStart", view.StartMoving)
    view:SetScript("OnDragStop", view.StopMovingOrSizing)
    view:SetScript("OnMouseUp", function(self, button) if button == "RightButton" then self:Hide() end end)
    view.bg = view:CreateTexture(nil, "BACKGROUND")
    view.bg:SetAllPoints()
    view.bg:SetColorTexture(0, 0, 0, 1)
    view.tiles = {}
    for i = 1, 4 do view.tiles[i] = view:CreateTexture(nil, "ARTWORK") end
end

local function addRow(parent, label, y, sizes, key, onPick)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 16, y - 4)
    fs:SetText(label)
    for i, v in ipairs(sizes) do
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(60, 22)
        b:SetPoint("TOPLEFT", 110 + (i - 1) * 64, y)
        b.value = v
        b:SetScript("OnClick", function() onPick(v) refresh() end)
        buttons[key][i] = b
    end
end

local function buildControls()
    controls = CreateFrame("Frame", "SummonCoreComicControls", UIParent, "BasicFrameTemplateWithInset")
    controls:Hide()
    controls:SetSize(520, 230)
    controls:SetPoint("TOP", 0, -40)
    controls:SetFrameStrata("FULLSCREEN_DIALOG")
    controls:SetMovable(true)
    controls:EnableMouse(true)
    controls:RegisterForDrag("LeftButton")
    controls:SetScript("OnDragStart", controls.StartMoving)
    controls:SetScript("OnDragStop", controls.StopMovingOrSizing)
    controls.TitleText:SetText("Comic image test")
    tinsert(UISpecialFrames, "SummonCoreComicControls")
    controls:SetScript("OnHide", function() if view then view:Hide() end end)

    addRow(controls, "Texture px", -34, TEX_SIZES, "tex", function(v) state.tex = v end)
    addRow(controls, "Shown units", -64, SHOW_SIZES, "show", function(v) state.show = v end)
    controls.tileBtn = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
    controls.tileBtn:SetSize(100, 22)
    controls.tileBtn:SetPoint("TOPLEFT", 110, -94)
    controls.tileBtn:SetScript("OnClick", function() state.tiled = not state.tiled refresh() end)
    controls.info = controls:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    controls.info:SetPoint("TOPLEFT", 16, -126)
    controls.info:SetPoint("RIGHT", -16, 0)
    controls.info:SetJustifyH("LEFT")
    controls.info:SetJustifyV("TOP")
end

function Comic.Toggle(arg)
    local n = tonumber(arg)
    for _, v in ipairs(TEX_SIZES) do if v == n then state.tex = v end end
    if not controls then buildControls() end
    if not view then buildView() end
    if controls:IsShown() and not n then
        controls:Hide()
        return
    end
    controls:Show()
    view:Show()
    refresh()
end
