-- Export: copy-paste strings of the summon log, and a window to export and import them.
-- This is the manual fallback for sync (same merge rules) and the base for later challenge strings.
--
-- String format: "!ST1!<codes>!<checksum>!<base64>"
--   The records (Sync.Encode, joined by "~") are LZW-compressed into 12-bit codes, packed into bytes and
--   base64-encoded. <codes> is the number of 12-bit codes, <checksum> an Adler-32 of the plain text.
local ADDON, ST = ...
setfenv(1, ST.env) -- the addon's own globals (Core.lua)
local Export = {}
ST.Export = Export
local T = ST.Theme

local Codec = {}
Export.Codec = Codec

local VERSION = 1
local MAX_CODES = 400000    -- about 600 KB of packed data
local MAX_TEXT = 4000000
local MAX_RECORDS = 20000
local DICT_LIMIT = 4096     -- 12-bit codes

----------------------------------------------------------------------
-- LZW (codes 0-255 are bytes; new entries stop being added at 4096)
----------------------------------------------------------------------
local function lzwEncode(s)
    local dict, size = {}, 256
    for i = 0, 255 do dict[string.char(i)] = i end
    local codes, w = {}, ""
    for i = 1, #s do
        local c = s:sub(i, i)
        local wc = w .. c
        if dict[wc] then
            w = wc
        else
            codes[#codes + 1] = dict[w]
            if size < DICT_LIMIT then
                dict[wc] = size
                size = size + 1
            end
            w = c
        end
    end
    if w ~= "" then codes[#codes + 1] = dict[w] end
    return codes
end

local function lzwDecode(codes)
    if #codes == 0 then return "" end
    local dict, size = {}, 256
    for i = 0, 255 do dict[i] = string.char(i) end
    local w = dict[codes[1]]
    if not w then return nil end
    local out = { w }
    for i = 2, #codes do
        local k = codes[i]
        local entry
        if dict[k] then
            entry = dict[k]
        elseif k == size then
            entry = w .. w:sub(1, 1)
        else
            return nil
        end
        out[#out + 1] = entry
        if size < DICT_LIMIT then
            dict[size] = w .. entry:sub(1, 1)
            size = size + 1
        end
        w = entry
    end
    return table.concat(out)
end

----------------------------------------------------------------------
-- 12-bit codes <-> bytes
----------------------------------------------------------------------
local floor = math.floor

local function packCodes(codes)
    local bytes = {}
    for i = 1, #codes, 2 do
        local a, b = codes[i], codes[i + 1]
        bytes[#bytes + 1] = floor(a / 16)
        if b then
            bytes[#bytes + 1] = (a % 16) * 16 + floor(b / 256)
            bytes[#bytes + 1] = b % 256
        else
            bytes[#bytes + 1] = (a % 16) * 16
        end
    end
    return bytes
end

local function unpackCodes(bytes, count)
    local expected = floor(count / 2) * 3 + (count % 2 == 1 and 2 or 0)
    if #bytes ~= expected then return nil end
    local codes, i = {}, 1
    while #codes < count do
        local b1, b2, b3 = bytes[i], bytes[i + 1], bytes[i + 2]
        codes[#codes + 1] = b1 * 16 + floor(b2 / 16)
        if #codes < count then
            codes[#codes + 1] = (b2 % 16) * 256 + b3
            i = i + 3
        else
            i = i + 2
        end
    end
    return codes
end

----------------------------------------------------------------------
-- Base64
----------------------------------------------------------------------
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local enc, dec = {}, {}
for i = 1, 64 do
    local ch = ALPHABET:sub(i, i)
    enc[i - 1] = ch
    dec[ch] = i - 1
end

local function b64encode(bytes)
    local out = {}
    for i = 1, #bytes, 3 do
        local b1, b2, b3 = bytes[i], bytes[i + 1], bytes[i + 2]
        local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)
        out[#out + 1] = enc[floor(n / 262144) % 64] .. enc[floor(n / 4096) % 64]
            .. (b2 and enc[floor(n / 64) % 64] or "=") .. (b3 and enc[n % 64] or "=")
    end
    return table.concat(out)
end

local function b64decode(s)
    if #s % 4 ~= 0 then return nil end
    local bytes = {}
    for i = 1, #s, 4 do
        local c = { s:sub(i, i), s:sub(i + 1, i + 1), s:sub(i + 2, i + 2), s:sub(i + 3, i + 3) }
        local v1, v2 = dec[c[1]], dec[c[2]]
        if not v1 or not v2 then return nil end
        local v3, v4 = dec[c[3]], dec[c[4]]
        if (c[3] == "=" and c[4] ~= "=") or (c[3] ~= "=" and not v3) or (c[4] ~= "=" and not v4) then return nil end
        if (c[3] == "=" or c[4] == "=") and i + 3 < #s then return nil end -- padding only at the end
        local n = v1 * 262144 + v2 * 4096 + (v3 or 0) * 64 + (v4 or 0)
        bytes[#bytes + 1] = floor(n / 65536)
        if v3 then bytes[#bytes + 1] = floor(n / 256) % 256 end
        if v4 then bytes[#bytes + 1] = n % 256 end
    end
    return bytes
end

local function adler(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

----------------------------------------------------------------------
-- Pack / Unpack
----------------------------------------------------------------------
-- text -> export string
function Codec.Pack(text)
    local codes = lzwEncode(text)
    return string.format("!ST%d!%d!%.0f!%s", VERSION, #codes, adler(text), b64encode(packCodes(codes)))
end

-- export string -> text, or nil, reason
function Codec.Unpack(str)
    str = tostring(str or ""):gsub("%s+", "")
    local ver = str:match("^!ST(%d+)!")
    if not ver then return nil, "not a Summon Core string" end
    if tonumber(ver) > VERSION then return nil, "made by a newer version of the addon" end
    local count, sum, payload = str:match("^!ST%d+!(%d+)!(%d+)!([%w%+/=]*)$")
    if not count then return nil, "damaged string (bad header)" end
    count, sum = tonumber(count), tonumber(sum)
    if count > MAX_CODES then return nil, "string is too large" end
    local bytes = b64decode(payload)
    if not bytes then return nil, "damaged string (bad encoding)" end
    local codes = unpackCodes(bytes, count)
    if not codes then return nil, "damaged string (truncated)" end
    local text = lzwDecode(codes)
    if not text or #text > MAX_TEXT then return nil, "damaged string (bad data)" end
    if adler(text) ~= sum then return nil, "damaged string (checksum mismatch)" end
    return text
end

----------------------------------------------------------------------
-- Build / Preview / Apply
----------------------------------------------------------------------
-- scope: "all" or "mine". Returns the string and the number of summons, or nil, reason.
function Export.Build(scope)
    local me = ST.Sync.myName()
    local records = {}
    for _, r in ipairs(ST.Store.Since(0)) do
        if scope ~= "mine" or r.ev.caster == me then records[#records + 1] = ST.Sync.Encode(r.id, r.ev) end
    end
    if #records == 0 then return nil, "nothing to export" end
    return Codec.Pack(table.concat(records, "~")), #records
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

-- Reads a string and reports what importing it would do, without changing anything.
-- Returns { items = {{id, ev}}, counts = {added, replaced, kept, rejected}, reasons = {} } or nil, reason.
function Export.Preview(str)
    local text, err = Codec.Unpack(str)
    if not text then return nil, err end
    local parts = split(text, "~")
    if #parts > MAX_RECORDS then return nil, "too many summons in one string" end
    local result = { items = {}, counts = { added = 0, replaced = 0, kept = 0, rejected = 0 }, reasons = {} }
    for _, rec in ipairs(parts) do
        local id, ev = ST.Sync.Decode(rec)
        local action
        if id then
            action = ST.Sync.Merge(id, ev, "", false, { dryRun = true, allowSelf = true })
            result.items[#result.items + 1] = { id = id, ev = ev }
        else
            action = "rejected:" .. tostring(ev)
        end
        local kind = action:match("^rejected") and "rejected" or action
        result.counts[kind] = result.counts[kind] + 1
        if kind == "rejected" then result.reasons[action] = (result.reasons[action] or 0) + 1 end
    end
    return result
end

-- Writes a previewed import. Merge is run again so the rules apply to the log as it is now.
function Export.Apply(preview)
    local counts = { added = 0, replaced = 0, kept = 0, rejected = 0 }
    for _, item in ipairs(preview.items) do
        local r = ST.Sync.Merge(item.id, item.ev, "", false, { allowSelf = true })
        local kind = r:match("^rejected") and "rejected" or r
        counts[kind] = counts[kind] + 1
    end
    return counts, ST.Achieve.Evaluate()
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
local window, preview

local function setStatus(text, good)
    window.status:SetText(good == true and T.Paint("green", text) or good == false and T.Paint("red", text) or text)
end

local function describe(p)
    local c = p.counts
    local text = string.format("%d new, %d would replace, %d already known, %d rejected", c.added, c.replaced,
        c.kept, c.rejected)
    local why = {}
    for reason, n in pairs(p.reasons) do why[#why + 1] = reason .. " x" .. n end
    if #why > 0 then text = text .. " (" .. table.concat(why, ", ") .. ")" end
    return text
end

local function doExport(scope)
    local str, n = Export.Build(scope)
    if not str then return setStatus("Nothing to export.", false) end
    preview = nil
    window.importBtn:Disable()
    window.edit:SetText(str)
    window.edit:SetFocus()
    window.edit:HighlightText()
    setStatus(string.format("Exported %d summon%s (%d characters). Press Ctrl+C to copy.", n, n == 1 and "" or "s",
        #str), true)
end

local function doPreview()
    if window.edit:GetText():match("^%s*$") then
        preview = nil
        window.importBtn:Disable()
        return setStatus("Paste a Summon Core string into the box first.")
    end
    local p, err = Export.Preview(window.edit:GetText())
    preview = nil
    window.importBtn:Disable()
    if not p then return setStatus("Can't import: " .. err, false) end
    local c = p.counts
    if c.added + c.replaced == 0 then return setStatus("Nothing new to import. " .. describe(p), false) end
    preview = p
    window.importBtn:Enable()
    setStatus("Preview: " .. describe(p) .. ". Press Import to apply.", true)
end

local function doImport()
    if not preview then return end
    local counts, badges = Export.Apply(preview)
    preview = nil
    window.importBtn:Disable()
    setStatus(string.format("Imported %d new and %d replaced; %d already known.", counts.added, counts.replaced,
        counts.kept), true)
    ST.Achieve.Say(badges)
end

local function button(parent, text, width, x, onClick, y, style)
    local b = T.Button(parent, text:upper(), width, 24, onClick, style)
    b:SetPoint("BOTTOMLEFT", x, y or 12)
    return b
end

local function build()
    window = T.Window("SummonCoreExport", 640, 490, { strata = "DIALOG" })
    window.TitleText:SetText("IMPORT / EXPORT")

    local box = CreateFrame("Frame", nil, window)
    window.box = box
    box:SetPoint("TOPLEFT", 12, -34)
    box:SetPoint("BOTTOMRIGHT", -12, 104)
    T.Panel(box)
    local sf = T.Scroll(box)
    sf:SetPoint("TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", -14, 6)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(0)
    eb:SetFontObject(T.Font(18, "cyan"))
    eb:SetWidth(580)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    sf:SetScrollChild(eb) -- the edit box grows with its text; keep the cursor in view
    eb:SetScript("OnCursorChanged", function(_, _, y, _, h)
        local top, view = sf:GetVerticalScroll(), sf:GetHeight()
        if -y < top then sf.ScrollTo(-y) elseif -y + h > top + view then sf.ScrollTo(-y + h - view) end
    end)
    sf:EnableMouse(true)
    sf:SetScript("OnMouseDown", function() eb:SetFocus() end)
    eb:SetScript("OnTextChanged", function(_, userInput)
        if userInput then
            preview = nil
            window.importBtn:Disable()
            setStatus("Press Preview to check the pasted string.")
        end
    end)
    window.edit = eb

    window.status = T.Text(window, 18, "green")
    window.status:SetPoint("BOTTOMLEFT", 16, 76)
    window.status:SetPoint("RIGHT", -16, 0)
    window.status:SetJustifyH("LEFT")

    button(window, "Export all", 90, 14, function() doExport("all") end)
    button(window, "Export mine", 100, 110, function() doExport("mine") end)
    button(window, "Preview", 80, 316, doPreview)
    window.importBtn = button(window, "Import", 80, 402, doImport, nil, "primary")
    window.importBtn:Disable()
    button(window, "Clear", 70, 556, function()
        window.edit:SetText("")
        preview = nil
        window.importBtn:Disable()
        setStatus("Paste a Summon Core string, then press Preview.")
    end)

    -- Test tools (the admin's): build a log to export, empty it again, and run the self-test, all without leaving
    -- the window.
    local tools = CreateFrame("Frame", nil, window)
    tools:SetAllPoints()
    window.testTools = tools
    local names, added = { "Bob", "Al", "Cy", "Di", "Ed" }, 0
    button(tools, "Add fake summon", 130, 14, function()
        added = added + 1
        local i = (added - 1) % #names + 1
        local ev, badges = ST.AddFake(names[i], { names[i % #names + 1], names[(i + 1) % #names + 1] })
        ST.Achieve.Say(badges)
        setStatus(string.format("Added test summon: %s (%s, +%d). The log now holds %d.", ev.target, ev.kind,
            ev.points, ST.Store.Count()), true)
    end, 44)
    button(tools, "Undo last", 90, 150, function()
        local last = ST.Store.RemoveLast()
        if last then
            setStatus(string.format("Removed the latest summon (%s). The log now holds %d.", last.ev.target,
                ST.Store.Count()), true)
        else
            setStatus("Nothing to undo.", false)
        end
    end, 44)
    button(tools, "Run self-test", 110, 246, function()
        ST.SyncTest.Run()
        setStatus("Self-test results are in the chat window.")
    end, 44)
    local label = T.Text(tools, 16, "dim")
    label:SetPoint("BOTTOMLEFT", 370, 50)
    label:SetPoint("RIGHT", -14, 0)
    label:SetText("Test tools (fake summons are never shared)")
end

-- mode: "export" fills the box with the whole log; "import" opens it empty for pasting.
function Export.Open(mode)
    if ST.Gag.Blocked() then return end
    if not window then build() end
    -- the test tools row is the admin's; everyone else gets the text box down to the status line
    local admin = ST.IsAdmin()
    window.testTools:SetShown(admin)
    window.box:SetPoint("BOTTOMRIGHT", -12, admin and 104 or 72)
    window.status:SetPoint("BOTTOMLEFT", 16, admin and 76 or 44)
    window:Show()
    if mode == "export" then
        doExport("all")
    else
        window.edit:SetText("")
        window.edit:SetFocus()
        preview = nil
        window.importBtn:Disable()
        setStatus("Paste a Summon Core string, then press Preview.")
    end
end
