-- Theme: the "Neon Index" look every window shares. Green-on-black terminal panels in the VT323 font
-- (Media\fonts, SIL Open Font License), cyan for the summoners, pink for Zennit, amber for his answers.
-- Windows, buttons, tabs, edit boxes, check boxes and scroll areas are drawn from flat colour textures,
-- so there is no art to rebuild.
local ADDON, ST = ...
setfenv(1, ST.env) -- the addon's own globals (Core.lua)
local Theme = {}
ST.Theme = Theme

Theme.FONT = "Interface\\AddOns\\summoncore\\Media\\fonts\\VT323-Regular.ttf"
local FALLBACK = "Fonts\\FRIZQT__.TTF" -- used if the theme font cannot be loaded
local WHITE = "Interface\\Buttons\\WHITE8X8"
local BEEP = "Interface\\AddOns\\summoncore\\Media\\sfx\\sfx_pop.ogg"

local HEX = {
    ground = "04060a", -- window background
    panel = "050b08",  -- boxes inside a window
    green = "4dff8f",  -- text, outlines
    dim = "2fa866",    -- headings, quiet text
    line = "1f6e44",   -- quiet outlines, disabled
    cyan = "5ce1ff",   -- the summoners
    pink = "ff6edb",   -- Zennit
    amber = "ffc94d",  -- his answers, warnings
    violet = "c9a6ff", -- "on his list"
    red = "ff5c5c",    -- refusals, resets
}
Theme.rgb = {}
for name, hex in pairs(HEX) do
    Theme.rgb[name] = { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
end

-- Wraps text in a colour code: Theme.Paint("pink", "Zennit").
function Theme.Paint(color, text)
    return "|cff" .. HEX[color] .. tostring(text) .. "|r"
end

local fonts = {}
-- The theme font at `size` in `color` (default green), as a shared font object.
function Theme.Font(size, color)
    color = color or "green"
    local key = size .. color
    if not fonts[key] then
        local fo = CreateFont("SummonCoreFont" .. key)
        -- a new font file is only found after WoW is restarted (/reload is not enough): fall back if it is missing
        if fo:SetFont(Theme.FONT, size, "") == false or not fo:GetFont() then
            fo:SetFont(FALLBACK, math.floor(size * 0.72), "")
        end
        fo:SetTextColor(unpack(Theme.rgb[color]))
        fo:SetShadowOffset(0, 0)
        fonts[key] = fo
    end
    return fonts[key]
end

-- A font string in the theme font.
function Theme.Text(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "ARTWORK")
    fs:SetFontObject(Theme.Font(size or 18, color))
    fs:SetJustifyH("LEFT")
    return fs
end

-- A flat colour texture.
function Theme.Fill(parent, color, alpha, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    local c = Theme.rgb[color]
    t:SetColorTexture(c[1], c[2], c[3], alpha or 1)
    return t
end

-- Four lines around `frame`, `out` pixels outside its edges. Returns them; lines.SetColor(color, alpha) repaints.
function Theme.Border(frame, color, alpha, width, out)
    out, width = out or 0, width or 1
    local lines = {}
    local function line()
        local t = frame:CreateTexture(nil, "BORDER")
        lines[#lines + 1] = t
        return t
    end
    local top, bottom, left, right = line(), line(), line(), line()
    top:SetPoint("TOPLEFT", -out, out)
    top:SetPoint("TOPRIGHT", out, out)
    top:SetHeight(width)
    bottom:SetPoint("BOTTOMLEFT", -out, -out)
    bottom:SetPoint("BOTTOMRIGHT", out, -out)
    bottom:SetHeight(width)
    left:SetPoint("TOPLEFT", -out, out)
    left:SetPoint("BOTTOMLEFT", -out, -out)
    left:SetWidth(width)
    right:SetPoint("TOPRIGHT", out, out)
    right:SetPoint("BOTTOMRIGHT", out, -out)
    right:SetWidth(width)
    function lines.SetColor(c, a)
        local rgb = Theme.rgb[c]
        for i = 1, 4 do lines[i]:SetColorTexture(rgb[1], rgb[2], rgb[3], a or 1) end
    end
    lines.SetColor(color, alpha)
    return lines
end

-- A dark box with an outline. opts: fill, alpha, color, width, glow (two faint rings outside it).
function Theme.Panel(frame, opts)
    opts = opts or {}
    local bg = Theme.Fill(frame, opts.fill or "panel", opts.alpha or 0.97, "BACKGROUND")
    bg:SetAllPoints()
    frame.border = Theme.Border(frame, opts.color or "line", 1, opts.width or 1)
    if opts.glow then
        Theme.Border(frame, opts.color or "green", 0.22, 2, 2)
        Theme.Border(frame, opts.color or "green", 0.08, 3, 4)
    end
    return frame
end

-- A short blip, for switching tabs. Quiet when Sounds is off.
function Theme.Beep()
    if ST.db and ST.db.settings and ST.db.settings.soundOn == false then return end
    pcall(PlaySoundFile, BEEP, "SFX")
end

----------------------------------------------------------------------
-- Buttons
----------------------------------------------------------------------
-- style: "normal" (green outline), "primary" (filled), "tab" (quiet until selected, then filled),
-- "danger" (red outline).
local function paint(b)
    local enabled = b:IsEnabled()
    local filled = enabled and (b.selected or b.style == "primary")
    local textColor, edge
    if not enabled then
        textColor, edge = "line", "line"
    elseif filled then
        textColor, edge = "ground", "green"
    elseif b.style == "tab" then
        textColor, edge = "dim", "line"
    elseif b.style == "danger" then
        textColor, edge = "red", "red"
    else
        textColor, edge = "green", "green"
    end
    local fill = Theme.rgb[filled and "green" or "ground"]
    b.bg:SetColorTexture(fill[1], fill[2], fill[3], filled and 1 or 0.85)
    b.border.SetColor(edge)
    b:SetNormalFontObject(Theme.Font(b.size, textColor))
    if b:GetFontString() then b:GetFontString():SetFontObject(Theme.Font(b.size, textColor)) end
end

function Theme.Button(parent, text, width, height, onClick, style)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height or 24)
    b.style, b.size = style or "normal", 18
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.border = Theme.Border(b, "green", 1, 1)
    local hl = Theme.Fill(b, "green", 0.18, "HIGHLIGHT")
    hl:SetAllPoints()
    b:SetNormalFontObject(Theme.Font(b.size, "green")) -- a button needs a font before its text is set
    b:SetDisabledFontObject(Theme.Font(b.size, "line"))
    b:SetPushedTextOffset(1, -1)
    b:SetText(text)
    if onClick then b:SetScript("OnClick", onClick) end
    b:SetScript("OnEnable", paint)
    b:SetScript("OnDisable", paint)
    function b.SetSelected(self, on)
        self.selected = on
        paint(self)
    end
    paint(b)
    return b
end

-- A text box with an outline that lights up while typing.
function Theme.EditBox(parent, width, height)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(width, height or 22)
    e:SetAutoFocus(false)
    e:SetFontObject(Theme.Font(18, "cyan"))
    e:SetTextInsets(6, 6, 0, 0)
    local bg = Theme.Fill(e, "ground", 0.9, "BACKGROUND")
    bg:SetAllPoints()
    local border = Theme.Border(e, "line", 1, 1)
    e:SetScript("OnEditFocusGained", function() border.SetColor("green") end)
    e:SetScript("OnEditFocusLost", function() border.SetColor("line") end)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    return e
end

-- A check box: an outlined square that fills when ticked, with a label (cb.Text).
function Theme.Check(parent, width)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(width or 240, 22)
    local box = CreateFrame("Frame", nil, cb)
    box:SetSize(14, 14)
    box:SetPoint("LEFT", 2, 0)
    Theme.Border(box, "green", 1, 1)
    cb:SetCheckedTexture(WHITE)
    local mark = cb:GetCheckedTexture()
    mark:ClearAllPoints()
    mark:SetPoint("CENTER", box, "CENTER")
    mark:SetSize(8, 8)
    mark:SetVertexColor(unpack(Theme.rgb.green))
    local hl = Theme.Fill(cb, "green", 0.1, "HIGHLIGHT")
    hl:SetAllPoints()
    cb.Text = Theme.Text(cb, 18, "cyan")
    cb.Text:SetPoint("LEFT", box, "RIGHT", 8, 0)
    return cb
end

----------------------------------------------------------------------
-- Scrolling
----------------------------------------------------------------------
-- A scroll area moved by the mouse wheel, with a thin position marker down its right edge (drawn just
-- outside it, so leave about 10 pixels). Returns the scroll frame and its child.
function Theme.Scroll(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    local track = Theme.Fill(parent, "line", 1)
    track:SetPoint("TOPLEFT", sf, "TOPRIGHT", 6, 0)
    track:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 6, 0)
    track:SetWidth(1)
    local thumb = Theme.Fill(parent, "green", 1, "OVERLAY")
    thumb:SetWidth(3)
    local function update()
        local range, h = sf:GetVerticalScrollRange() or 0, sf:GetHeight() or 0
        if range <= 0 or h <= 0 then
            track:Hide()
            thumb:Hide()
            return
        end
        local size = math.max(16, h * h / (h + range))
        thumb:SetHeight(size)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(h - size) * math.min(1, sf:GetVerticalScroll() / range))
        track:Show()
        thumb:Show()
    end
    local function scrollTo(y)
        sf:SetVerticalScroll(math.max(0, math.min(sf:GetVerticalScrollRange() or 0, y)))
        update()
    end
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(_, delta) scrollTo(sf:GetVerticalScroll() - delta * 40) end)
    sf:SetScript("OnScrollRangeChanged", function() scrollTo(sf:GetVerticalScroll()) end)
    sf:SetScript("OnSizeChanged", update)
    sf.ScrollTo = scrollTo
    update()
    return sf, child
end

----------------------------------------------------------------------
-- Windows
----------------------------------------------------------------------
-- A movable window: black ground, a glowing green outline, and a filled title strip with "[ X ]".
-- frame.TitleText is the strip's text. opts: strata (default HIGH), escape (false: Escape does not close it).
function Theme.Window(name, width, height, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", name, UIParent)
    f:Hide() -- a new frame is visible; the caller shows it
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata(opts.strata or "HIGH")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Theme.Panel(f, { fill = "ground", color = "green", width = 2, glow = true })

    local strip = Theme.Fill(f, "green", 1)
    strip:SetPoint("TOPLEFT", 2, -2)
    strip:SetPoint("TOPRIGHT", -2, -2)
    strip:SetHeight(24)
    f.TitleText = Theme.Text(f, 20, "ground", "OVERLAY")
    f.TitleText:SetPoint("LEFT", strip, "LEFT", 10, 0)

    local close = CreateFrame("Button", nil, f)
    close:SetSize(52, 24)
    close:SetPoint("TOPRIGHT", -4, -2)
    close:SetNormalFontObject(Theme.Font(20, "ground"))
    close:SetText("[ X ]")
    local hl = Theme.Fill(close, "ground", 0.2, "HIGHLIGHT")
    hl:SetAllPoints()
    close:SetScript("OnClick", function() f:Hide() end)
    f.CloseButton = close

    if name and opts.escape ~= false then tinsert(UISpecialFrames, name) end
    return f
end

-- A blinking block cursor, like the one at a command prompt.
function Theme.Cursor(parent)
    local c = Theme.Fill(parent, "green", 1, "OVERLAY")
    c:SetSize(8, 14)
    local blink = c:CreateAnimationGroup()
    blink:SetLooping("BOUNCE")
    local fade = blink:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(0.55)
    blink:Play()
    return c
end
