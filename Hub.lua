-- Hub: one window for everything the slash commands do. Tabs: Party (Summary, Tally and Badges), Zennit (his answers),
-- Log, Story, Sync, Tools. The slash commands still work; /sc with no arguments opens this window. Each of the first
-- two tabs is closed to the other side: Zennit gets the "ah ah ah" gag on the Party tab, and the party gets a gag of
-- its own on his. Drawn in the Neon Index look (Theme.lua):
-- a title strip, the tabs, the season race on every tab, and a command-prompt status line along the bottom.
local ADDON, ST = ...
local Hub = {}
ST.Hub = Hub
local T = ST.Theme

local ROW_H = 20
local ORDER = { "party", "zennit", "log", "story", "sync", "tools" }
local LABELS = { party = "PARTY", zennit = "ZENNIT", log = "LOG", story = "STORY", sync = "SYNC", tools = "TOOLS" }
-- The old tab names still open the tab that now holds them (Hub.Open("tally") shows the Party tab's Tally section).
local TAB_OF = { summary = "party", tally = "party", badges = "party", leaders = "party", answer = "zennit" }
local SECTION_OF = { summary = true, tally = true, badges = true, leaders = true }

local window
local tabs = {}      -- name -> { button, frame, refresh }
local current
local chrome = {}    -- the season band and the status line

local function fmtTime(sec, pattern) return date(pattern or "%Y-%m-%d %H:%M", sec) end

-- A name in its colour: Zennit pink, everyone else cyan.
local function who(name)
    return T.Paint(ST.Week.IsZennit(name) and "pink" or "cyan", name)
end

-- Zennit's answer in its colour, or "" if there is none.
local ANSWER_COLORS = { accepted = "green", paid = "green", lost = "green", refused = "red", excused = "violet", declined = "dim", away = "dim",
    owed = "amber", won = "pink" }
local function answerText(ev)
    local text = ST.Respond.Describe(ev)
    if not text then return "" end
    return T.Paint(ANSWER_COLORS[ev.response.result] or "amber", text)
end

----------------------------------------------------------------------
-- Building blocks
----------------------------------------------------------------------
local function button(parent, text, x, y, width, onClick, style)
    local b = T.Button(parent, text, width, 24, onClick, style)
    b:SetPoint("TOPLEFT", x, y)
    return b
end

-- A button along the bottom edge of a tab.
local function bottomButton(parent, text, x, width, onClick, style)
    local b = T.Button(parent, text, width, 24, onClick, style)
    b:SetPoint("BOTTOMLEFT", x, 4)
    return b
end

local function label(parent, text, x, y, color, size)
    local fs = T.Text(parent, size or 18, color or "dim")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function bodyText(parent, x, y, width, height)
    local fs = T.Text(parent, 18, "green")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetSize(width, height)
    fs:SetJustifyV("TOP")
    fs:SetSpacing(2)
    return fs
end

-- A scrolling table. columns = { { title, width, "LEFT"|"RIGHT" }, ... }; list.Set(rows) takes arrays of strings.
local function scrollList(parent, columns, bottomMargin)
    local list = { rows = {} }
    local xs, x = {}, 8
    for i, col in ipairs(columns) do
        xs[i] = x
        local head = T.Text(parent, 18, "dim")
        head:SetPoint("TOPLEFT", x, -6)
        head:SetWidth(col[2] - 6)
        head:SetJustifyH(col[3] or "LEFT")
        head:SetText(col[1]:upper())
        x = x + col[2]
    end
    local rule = T.Fill(parent, "line", 1)
    rule:SetPoint("TOPLEFT", 4, -25)
    rule:SetPoint("TOPRIGHT", -14, -25)
    rule:SetHeight(1)
    local sf, child = T.Scroll(parent)
    sf:SetPoint("TOPLEFT", 4, -30)
    sf:SetPoint("BOTTOMRIGHT", -14, bottomMargin or 8)
    child:SetSize(x, 1)
    list.empty = T.Text(parent, 18, "dim")
    list.empty:SetPoint("CENTER", sf, "CENTER")

    function list.Set(rows, emptyText)
        for i, row in ipairs(rows) do
            local r = list.rows[i]
            if not r then
                r = {}
                for c, col in ipairs(columns) do
                    local fs = T.Text(child, 18, "green", "OVERLAY")
                    fs:SetPoint("TOPLEFT", xs[c], -(i - 1) * ROW_H - 2)
                    fs:SetWidth(col[2] - 6)
                    fs:SetJustifyH(col[3] or "LEFT")
                    fs:SetWordWrap(false)
                    r[c] = fs
                end
                list.rows[i] = r
            end
            for c = 1, #columns do
                r[c]:SetText(row[c] or "")
                r[c]:Show()
            end
        end
        for i = #rows + 1, #list.rows do
            for _, fs in ipairs(list.rows[i]) do fs:Hide() end
        end
        child:SetHeight(math.max(1, #rows * ROW_H + 4))
        list.empty:SetText(#rows == 0 and (emptyText or "Nothing here yet.") or "")
    end
    return list
end

----------------------------------------------------------------------
-- Tab contents
----------------------------------------------------------------------
local function whereText()
    local mapID, sub = C_Map.GetBestMapForUnit("player"), GetSubZoneText()
    local pts, kind = ST.Scoring.Score(mapID, sub)
    return string.format("Here: %s, %s (map %s) scores as %s, %s.", GetZoneText(),
        sub ~= "" and sub or "no subzone", ST.safe(mapID), kind, T.Paint("amber", pts .. " point" .. (pts == 1 and "" or "s")))
end

local function buildSummary(f)
    local text = bodyText(f, 16, -8, 740, 410)
    return function()
        local me = ST.Store.me()
        local t = ST.Store.Tallies()[me] or { cast = 0, received = 0, assisted = 0, points = 0 }
        local lines = {
            T.Paint("dim", "C:\\INDEX> whoami"),
            who(me),
            string.format("Cast %s    Received %s    Assisted %s    Points %s", T.Paint("amber", t.cast),
                T.Paint("amber", t.received), T.Paint("amber", t.assisted), T.Paint("amber", t.points)),
            whereText(),
            "",
            T.Paint("dim", "BADGES.SYS"),
        }
        for _, b in ipairs(ST.Scoring.badges) do
            local got = ST.Scoring.Badges()[b.id]
            lines[#lines + 1] = got and ("[X] " .. b.name .. "  " .. T.Paint("dim", fmtTime(got.earned, "%Y-%m-%d")))
                or T.Paint("dim", "[ ] " .. b.name)
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = T.Paint("dim", "RECENT.LOG")
        local recent = ST.Store.Recent(6)
        if #recent == 0 then lines[#lines + 1] = T.Paint("dim", "none yet") end
        for _, r in ipairs(recent) do
            local ev = r.ev
            lines[#lines + 1] = string.format("%s  %s => %s  (%s, +%d)", T.Paint("dim", fmtTime(ev.time, "%m-%d %H:%M")),
                who(ev.caster), who(ev.target), ev.kind or "?", ev.points or 0)
        end
        text:SetText(table.concat(lines, "\n"))
    end
end

local function buildLog(f)
    local list = scrollList(f, { { "When", 100 }, { "Summoner => target", 190 }, { "Helpers", 140 },
        { "Zennit says", 190 }, { "Kind", 70 }, { "Pts", 40, "RIGHT" } }, 36)
    local function refresh()
        local zenit = ST.Gag.IsZennit()
        local rows = {}
        for _, r in ipairs(ST.Store.Recent(300)) do
            local ev = r.ev
            rows[#rows + 1] = {
                T.Paint("dim", fmtTime(ev.time, "%m-%d %H:%M")),
                who(ev.caster) .. " => " .. who(ev.target) .. (ev.confirmed and "" or " ?") .. (ev.fake and T.Paint("dim", " (test)") or ""),
                #ev.assistants > 0 and table.concat(ev.assistants, ", ") or T.Paint("dim", "-"),
                answerText(ev),
                zenit and "" or (ev.kind or ""),
                zenit and "" or T.Paint("amber", ev.points or 0),
            }
        end
        list.Set(rows, "No summons logged yet.")
    end
    bottomButton(f, "UNDO LAST", 4, 120, function()
        local last = ST.Store.RemoveLast()
        ST.print(last and ("removed " .. last.ev.caster .. " -> " .. last.ev.target) or "nothing to undo")
        Hub.Refresh()
    end)
    local addTest = bottomButton(f, "ADD TEST SUMMON", 130, 160, function()
        local names = { "Bob", "Al", "Cy", "Di", "Ed" }
        local n = ST.Store.Count() % #names + 1
        ST.AddFake(names[n], { names[n % #names + 1], names[(n + 1) % #names + 1] })
        Hub.Refresh()
    end)
    local answer = bottomButton(f, "ANSWER A SUMMON", 296, 160, function() Hub.Open("zennit") end, "primary")
    return function()
        local admin = ST.IsAdmin()
        addTest:SetShown(admin) -- an admin tool
        answer:SetShown(admin or ST.Gag.IsZennit()) -- his tab is closed to everyone else
        answer:ClearAllPoints()
        answer:SetPoint("BOTTOMLEFT", admin and 296 or 130, 4)
        refresh()
    end
end

local function buildAnswer(f)
    local info = label(f, "", 16, -8, "green")
    info:SetWidth(570)
    -- once enough summons of him are filed this week, Zennit may close the Index for the rest of it
    local closeIndex = button(f, "CLOSE THE INDEX", 600, -6, 156, function()
        ST.Respond.CloseIndex()
        Hub.Refresh()
    end, "danger")
    local surface
    surface = ST.Respond.NewSurface(f, 16, -36, 740, function()
        ST.Respond.Clear(surface)
        Hub.Refresh()
    end, 2)
    local counter = label(f, "", 252, -232, "dim")

    -- the summons already answered, below
    local recentFrame = CreateFrame("Frame", nil, f)
    recentFrame:SetPoint("TOPLEFT", 0, -282)
    recentFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    local recent = scrollList(recentFrame, { { "When", 100 }, { "Summoner", 150 }, { "Your answer", 300 }, { "Pts", 60, "RIGHT" } }, 8)

    local function indexOf(pending, id)
        for i, r in ipairs(pending) do if r.id == id then return i end end
    end

    local function go(step)
        local pending = ST.Respond.Pending()
        if #pending == 0 then return end
        local at = surface.current and indexOf(pending, surface.current.id)
        local target = at and ((at - 1 + step) % #pending) + 1 or (step > 0 and 1 or #pending)
        ST.Respond.Select(surface, pending[target].id, pending[target].ev)
        Hub.Refresh()
    end
    button(f, "< PREV", 16, -228, 110, function() go(-1) end)
    button(f, "NEXT >", 132, -228, 110, function() go(1) end)

    -- his secret list: declining a summon to one of these costs him nothing (kept on this client only, so it is
    -- only shown on Zennit's client, and the admin's to try it)
    local secret = CreateFrame("Frame", nil, f)
    secret:SetAllPoints()
    label(secret, "SECRET LIST", 360, -231, "dim")
    local entry = T.EditBox(secret, 150, 22)
    entry:SetPoint("TOPLEFT", 460, -229)
    local function addEntry()
        local ok, why = ST.Respond.ListAdd(entry:GetText())
        if ok then entry:SetText("") elseif why then ST.print(why) end
        entry:ClearFocus()
        Hub.Refresh()
    end
    entry:SetScript("OnEnterPressed", addEntry)
    -- autocomplete: as he types, the rest of the first place that starts with it is filled in and highlighted, so typing on
    -- replaces it, Tab or Enter takes it, and Backspace drops it
    local typed, places = 0, nil
    entry:HookScript("OnEditFocusGained", function(self) -- hooked: the box lights its outline on focus too
        places = ST.Respond.ListSuggestions()
        typed = #self:GetText()
    end)
    entry:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = self:GetText()
        local grew = #text > typed
        typed = #text
        if not grew or text == "" or not places then return end
        local low = text:lower()
        for _, name in ipairs(places) do
            if #name > #text and name:sub(1, #text):lower() == low then
                self:SetText(text .. name:sub(#text + 1))
                self:SetCursorPosition(#text)
                self:HighlightText(#text, #name)
                return
            end
        end
    end)
    entry:SetScript("OnTabPressed", function(self)
        self:HighlightText(0, 0)
        self:SetCursorPosition(#self:GetText())
        typed = #self:GetText()
    end)
    button(secret, "ADD", 616, -228, 60, addEntry)
    button(secret, "CLEAR", 682, -228, 74, function() ST.Respond.ListClear() Hub.Refresh() end, "danger")
    local listText = label(secret, "", 360, -256, "violet")
    listText:SetWidth(396)
    listText:SetWordWrap(false)

    return function()
        secret:SetShown(ST.Gag.IsZennit() or ST.IsAdmin())
        closeIndex:SetShown(ST.Gag.IsZennit() and ST.Week.CloseTarget(ST.Week.Start()) ~= nil)
        local list, active = ST.Respond.List(), ST.Respond.ListActive()
        local shown, used = {}, {}
        for _, word in ipairs(active) do used[word] = (used[word] or 0) + 1 end
        for _, word in ipairs(list) do
            if (used[word] or 0) > 0 then
                used[word] = used[word] - 1
                -- a place added this week counts from Monday: the list is set for the week (design/lenses.md, Secrets)
                shown[#shown + 1] = ST.Respond.ListPending(word) and (word .. T.Paint("dim", " (from Monday)")) or word
            else
                shown[#shown + 1] = T.Paint("dim", word) -- too short, or past the fifth: it does not count
            end
        end
        listText:SetText(#list == 0 and T.Paint("dim", "empty: only your free decline is free") or table.concat(shown, ", "))
        local pending = ST.Respond.Pending()
        local cur = surface.current
        -- keep what is on show (a summon being answered, or its outcome) until the user moves on
        if not (cur and (indexOf(pending, cur.id) or ST.Respond.Stage(surface) == "done")) then
            if #pending > 0 then
                ST.Respond.Select(surface, pending[1].id, pending[1].ev)
            else
                ST.Respond.Clear(surface)
            end
        end
        local n = #pending
        if n == 0 and not ST.Gag.IsZennit() then
            info:SetText("This tab is for Zennit's character: summons of him wait here for his answer." ..
                (ST.IsAdmin() and " Try it with Tools > Testing > Test a summoning." or ""))
        else
            info:SetText(n == 0 and "Nothing is waiting for your answer." or
                string.format("%s summon%s waiting for your answer", T.Paint("amber", n), n == 1 and "" or "s"))
        end
        local at = surface.current and indexOf(pending, surface.current.id)
        counter:SetText(at and string.format("%d of %d", at, n) or "")

        local me, rows = ST.Store.me(), {}
        for _, r in ipairs(ST.Store.Recent(200)) do
            local ev = r.ev
            if ev.target == me and ev.response and ev.response.result ~= "owed" and #rows < 40 then
                rows[#rows + 1] = { T.Paint("dim", fmtTime(ev.time, "%m-%d %H:%M")), who(ev.caster) .. (ev.fake and T.Paint("dim", " (test)") or ""),
                    answerText(ev), T.Paint("amber", ST.Store.Lands(ev) and (ev.points or 0) or 0) }
            end
        end
        recent.Set(rows, "No answered summons yet.")
    end
end

local function buildTally(f)
    local list = scrollList(f, { { "Player", 200 }, { "Cast", 70, "RIGHT" }, { "Of Zennit", 90, "RIGHT" },
        { "Received", 85, "RIGHT" }, { "Assisted", 85, "RIGHT" }, { "Points", 80, "RIGHT" } })
    return function()
        local out = {}
        for _, r in ipairs(ST.Store.Ranked(ST.Store.Tallies(), ST.Ledger.Facts().casters)) do
            local t = r[2]
            out[#out + 1] = { who(r[1]), tostring(t.cast), T.Paint("amber", r[3]), tostring(t.received), tostring(t.assisted),
                T.Paint("amber", t.points) }
        end
        list.Set(out, "No summons logged yet.")
    end
end

-- The leaderboard (Leaders.lua), three boards side by side: who has summoned Zennit most, who has given him the most fish, and who
-- has thrown the most snowballs at him.
local function buildLeaders(f)
    local function third(i)
        local p = CreateFrame("Frame", nil, f)
        p:SetPoint("TOPLEFT", (i - 1) * 258, 0)
        p:SetPoint("BOTTOM")
        p:SetWidth(254)
        return p
    end
    local summons = scrollList(third(1), { { "Summons", 110 }, { "Season", 50, "RIGHT" }, { "Week", 40, "RIGHT" }, { "All", 36, "RIGHT" } })
    local fish = scrollList(third(2), { { "Fish", 130 }, { "Week", 45, "RIGHT" }, { "All", 60, "RIGHT" } })
    local snow = scrollList(third(3), { { "Snowballs", 130 }, { "Week", 45, "RIGHT" }, { "All", 60, "RIGHT" } })
    return function()
        local rows = {}
        for i, r in ipairs(ST.Leaders.SummonRows()) do
            rows[#rows + 1] = { i .. ". " .. who(r.name), T.Paint("amber", r.season), tostring(r.week), tostring(r.all) }
        end
        summons.Set(rows, "No summons of Zennit yet.")
        rows = {}
        for i, r in ipairs(ST.Fish.Board()) do
            rows[#rows + 1] = { i .. ". " .. who(r.name), tostring(r.week), T.Paint("amber", r.count) }
        end
        fish.Set(rows, "No fish yet.")
        rows = {}
        for i, r in ipairs(ST.Snowball.Board()) do
            rows[#rows + 1] = { i .. ". " .. who(r.name), tostring(r.week), T.Paint("amber", r.count) }
        end
        snow.Set(rows, "No snowballs yet.")
    end
end

local function buildBadges(f)
    local list = scrollList(f, { { "Badge", 270 }, { "Status", 90 }, { "Earned, or what it takes", 380 } })
    return function()
        local rows = {}
        for _, b in ipairs(ST.Scoring.badges) do
            local got = ST.Scoring.Badges()[b.id]
            rows[#rows + 1] = { got and ("[X] " .. b.name) or T.Paint("dim", "[ ] " .. b.name),
                got and "EARNED" or T.Paint("dim", "LOCKED"), got and T.Paint("dim", fmtTime(got.earned)) or T.Paint("dim", b.how or "") }
        end
        list.Set(rows)
    end
end

-- The story as a talent tree: the intro at the top, then one trunk for each side of the season race (z = Zennit's,
-- g = the group's). Each weekly win unlocks the next chapter down its side; the fifth win is that side's finale.
-- Chapters the race has reached light up in the side's colour and play when clicked; the next win on each side
-- pulses; the rest stay dark, and their titles stay hidden (spoilers) unless you are the admin.
local TREE = {
    zennit = {
        { "z1", "the week off" },
        { "z2", "the key to the side door" },
        { "z3", "the list is training modules" },
        { "z4", "the clerk shows him the desk" },
        { "z5", "he becomes the clerk" },
    },
    group = {
        { "g1", "the cake" },
        { "g2", "the carbon copy of the Form" },
        { "g3", "the Ritual holds the Form" },
        { "g4", "the Ritual names its price" },
        { "g5", "the receipt, and Zennit is freed" },
    },
}
local SIDES = { "zennit", "group" }
local SIDE_COLOR = { zennit = "pink", group = "cyan" }
local SIDE_HEAD = { zennit = "ZENNIT", group = "THE GROUP" }
local SIDE_OWN = { zennit = "Zennit's", group = "The group's" }
local ORDINAL = { "1st", "2nd", "3rd", "4th" }

-- Where everything sits inside the tab (776 x 458): two trunks either side of the middle, the intro on top.
local NODE_W, NODE_H, PITCH = 330, 46, 70
local MID_X, SIDE_X = 388, { zennit = 194, group = 582 }
local ROOT_W, ROOT_TOP, BAR_Y, TIER_TOP = 220, -22, -80, -92

local function tierTop(tier) return TIER_TOP - (tier - 1) * PITCH end

local function paintTexture(tex, color, alpha)
    local c = T.rgb[color]
    tex:SetColorTexture(c[1], c[2], c[3], alpha or 1)
end

local function treeNode(f, cx, top, width)
    local n = CreateFrame("Button", nil, f)
    n:SetSize(width, NODE_H)
    n:SetPoint("TOPLEFT", cx - width / 2, top)
    T.Panel(n, { color = "line" })
    local hl = T.Fill(n, "green", 0.14, "HIGHLIGHT")
    hl:SetAllPoints()
    n.tag = T.Text(n, 16, "dim", "OVERLAY")
    n.tag:SetPoint("TOPLEFT", 8, -4)
    n.state = T.Text(n, 16, "dim", "OVERLAY")
    n.state:SetPoint("TOPRIGHT", -8, -4)
    n.state:SetJustifyH("RIGHT")
    n.title = T.Text(n, 18, "green", "OVERLAY")
    n.title:SetPoint("TOPLEFT", 8, -22)
    n.title:SetWidth(width - 16)
    n.title:SetWordWrap(false)
    n:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tip[1], 1, 1, 1)
        for i = 2, #self.tip do GameTooltip:AddLine(self.tip[i], 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    n:SetScript("OnLeave", function() GameTooltip:Hide() end)
    n:SetScript("OnClick", function(self)
        if not (self.key and self.playable) then return end
        GameTooltip:Hide()
        window:Hide() -- the viewer sits under this window; it comes back when the viewer is closed
        ST.Intro.Play(self.key, function() Hub.Open("story") end)
    end)
    -- the next win on a side breathes amber
    n:SetScript("OnUpdate", function(self)
        if self.pulse then self.border.SetColor("amber", 0.55 + 0.45 * math.sin(GetTime() * 4)) end
    end)
    return n
end

-- Sets a node's colours and wording. look: { border, pulse, tag, state, stateColor, title, titleColor, glow }
local function setNode(n, look)
    n.pulse = look.pulse
    n.border.SetColor(look.border, 1)
    n.tag:SetText(look.tag)
    n.state:SetFontObject(T.Font(16, look.stateColor))
    n.state:SetText(look.state)
    n.title:SetFontObject(T.Font(18, look.titleColor))
    n.title:SetText(look.title)
    if n.glow then
        for _, ring in ipairs(n.glow) do
            for i = 1, 4 do ring[i]:SetShown(look.glow == true) end
        end
    end
end

local function buildStory(f)
    label(f, "Each weekly win unlocks the next chapter on its side. Click a lit chapter to replay it.", 16, -2):SetWidth(744)

    -- connectors first, so the nodes draw over them
    local function stroke(x, y, w, h)
        local tex = T.Fill(f, "line", 1, "BACKGROUND")
        tex:SetPoint("TOPLEFT", x, y)
        tex:SetSize(w, h)
        return tex
    end
    local rootStem = stroke(MID_X - 1, ROOT_TOP - NODE_H, 2, (ROOT_TOP - NODE_H) - BAR_Y)
    local bars = {
        zennit = stroke(SIDE_X.zennit - 1, BAR_Y - 1, MID_X - SIDE_X.zennit + 1, 2),
        group = stroke(MID_X, BAR_Y - 1, SIDE_X.group - MID_X + 1, 2),
    }
    local sides = {}
    for _, side in ipairs(SIDES) do
        local col = { nodes = {}, links = {} }
        col.drop = stroke(SIDE_X[side] - 1, BAR_Y - 1, 2, BAR_Y - TIER_TOP + 1)
        col.head = T.Text(f, 22, SIDE_COLOR[side])
        col.head:SetPoint("TOPLEFT", SIDE_X[side] - 120, -34)
        col.head:SetWidth(240)
        col.head:SetJustifyH("CENTER")
        for tier = 1, #TREE[side] do
            if tier < #TREE[side] then
                col.links[tier] = stroke(SIDE_X[side] - 1, tierTop(tier) - NODE_H, 2, PITCH - NODE_H)
            end
            local node = treeNode(f, SIDE_X[side], tierTop(tier), NODE_W)
            node.key = TREE[side][tier][1]
            if tier == ST.Week.WINS then -- the finale: ringed in the side's colour while it is lit
                node.glow = { T.Border(node, SIDE_COLOR[side], 0.22, 2, 2), T.Border(node, SIDE_COLOR[side], 0.08, 3, 4) }
            end
            col.nodes[tier] = node
        end
        sides[side] = col
    end
    local root = treeNode(f, MID_X, ROOT_TOP, ROOT_W)
    -- once there is more than one season, a button picks which season's tree is shown (the season in progress by default)
    local viewing
    -- the seasons the tab can show: those that have begun, and for the admin's preview (Tools > Testing, /sc preview) the next
    local function lastShown(began)
        return (ST.IsAdmin() and ST.db.settings.previewSeason) and began + 1 or began
    end
    local pick = button(f, "", 596, -26, 170, function()
        local current = lastShown(ST.Week.Season().number or 1)
        viewing = (viewing or current) % current + 1
        Hub.Refresh()
    end)

    return function()
        local season = ST.Week.Season()
        local began = season.number or 1
        local current = lastShown(began)
        local number = math.min(viewing or current, current)
        local thisSeason = number == current
        local previewing = number > began -- a season that has not begun: the admin's preview, nothing in the log changes
        pick:SetShown(current > 1)
        pick:SetText(previewing and string.format("PREVIEW SEASON %d", number) or string.format("SEASON %d OF %d", number, current))
        local reached, count = {}, { zennit = 0, group = 0 }
        for _, c in ipairs(season.chapters) do
            if (c.season or 1) == number then
                reached[c.key] = true
                count[c.side] = count[c.side] + 1
            end
        end
        local admin = ST.IsAdmin()
        local silver = thisSeason and number == 1 and ST.Ledger.SilverLine(ST.Ledger.Facts(season)) -- the Ritual's price (g4, g5)
        local titles = number > 1 and ST.seasonTrees and ST.seasonTrees[number]
        -- a trunk's chapter: its key and its short title
        local function chapter(side, tier)
            if number == 1 then return TREE[side][tier][1], TREE[side][tier][2] end
            return ST.Week.ChapterKey(number, side, tier), titles and titles[side][tier] or "not written yet"
        end

        if number == 1 then
            root.key, root.playable = "1", true
            root.tip = { "The intro: Zennit and the Index", "Click to play. It ends with the Index today: where the season stands, and how far down each trunk the race has got." }
            setNode(root, { border = "green", tag = "THE INTRO", state = "", stateColor = "dim", title = "Zennit and the Index",
                titleColor = "green" })
        else
            -- a later season starts with its opening, chosen by how the season before it ended
            local open
            for _, o in ipairs(season.openings or {}) do
                if o.season == number then open = o end
            end
            if not open and previewing then open = { key = ST.Week.OpeningKey(number, "zennit") } end -- the other opening: /sc intro <n>b
            local title = open and ST.Intro.ChapterTitle(open.key)
            root.key, root.playable = open and open.key, title ~= nil
            root.tip = title and { "Season " .. number .. " opens" .. (previewing and " (preview)" or ""),
                previewing and ("Click to play the opening after Zennit's finale. /sc intro " .. number .. "b plays the one after the group's.")
                    or "Click to play." }
                or { "Season " .. number .. " opens", "This season's story is not in this version of Summon Core. An update will have it." }
            setNode(root, { border = title and "green" or "line", tag = "THE OPENING", state = title and "" or "NOT WRITTEN",
                stateColor = title and "dim" or "line", title = title and title:match(": (.+)$") or "Season " .. number,
                titleColor = title and "green" or "line" })
        end
        paintTexture(rootStem, "dim")

        for _, side in ipairs(SIDES) do
            local col, color = sides[side], SIDE_COLOR[side]
            local done = previewing and 0 or thisSeason and season[side] or count[side]
            col.head:SetText(string.format("%s  %d/%d", SIDE_HEAD[side], done, ST.Week.WINS))
            for tier, node in ipairs(col.nodes) do
                local key, short = chapter(side, tier)
                node.key = key
                local finale = tier == ST.Week.WINS
                local written = ST.Intro.HasChapter(key)
                local isReached = reached[key] == true
                local full = finale and ("FINALE, " .. (side == "zennit" and "Zennit" or "the group") .. ": " .. short)
                    or (SIDE_OWN[side] .. " " .. ORDINAL[tier] .. " win: " .. short)
                local show = isReached or admin -- the title gives the chapter away, so it waits for the race
                local look = { tag = finale and "FINALE" or (ORDINAL[tier]:upper() .. " WIN"), title = show and short or "???" }
                if isReached then
                    look.border, look.titleColor, look.glow = color, color, finale
                    look.state, look.stateColor = not thisSeason and ("SEASON " .. number)
                        or tier <= done and "THIS SEASON" or "REACHED", "green"
                    node.tip = { full, "Click to play." }
                elseif not written then
                    look.border, look.titleColor, look.state, look.stateColor = "line", "line", "NOT WRITTEN", "line"
                    node.tip = { show and full or "???", "This chapter is not written yet." }
                elseif thisSeason and tier == done + 1 then
                    look.border, look.pulse, look.state, look.stateColor = "amber", true, "NEXT WIN", "amber"
                    look.titleColor = admin and "dim" or "line"
                    node.tip = { show and full or "???", "Unlocks when " .. (side == "zennit" and "Zennit" or "the group") ..
                        " wins the week." .. (admin and " (Admin: click to play.)" or "") }
                else
                    look.border, look.state, look.stateColor = "line", admin and "ADMIN" or (thisSeason and "LOCKED" or "NOT REACHED"),
                        admin and "amber" or "line"
                    look.titleColor = admin and "dim" or "line"
                    node.tip = { show and full or "???", (thisSeason and "Not reached yet." or "Not reached that season.") ..
                        (admin and " (Admin: click to play.)" or "") }
                end
                if silver and side == "group" and tier >= ST.Week.WINS - 1 and node.tip then
                    node.tip[#node.tip + 1] = silver -- the Ritual's price, as the season stands
                end
                node.playable = written and show or false
                setNode(node, look)
                -- the line into this node is lit once the node is
                local link = tier == 1 and col.drop or col.links[tier - 1]
                paintTexture(link, isReached and color or "line")
                if tier == 1 then paintTexture(bars[side], isReached and color or "line") end
            end
        end
    end
end

local function buildSync(f)
    local info = bodyText(f, 16, -10, 740, 120)
    local out = bodyText(f, 16, -250, 740, 140)
    button(f, "SAY HELLO NOW", 16, -140, 160, function()
        ST.Sync.Hello()
        Hub.Refresh()
    end, "primary")
    local selfTest = button(f, "RUN SELF-TEST", 182, -140, 160, function()
        ST.SyncTest.Run()
        out:SetText("Self-test results are in the chat window.")
    end)
    local importExport = button(f, "IMPORT / EXPORT", 348, -140, 160, function() ST.Export.Open("import") end)
    label(f, "Sync shares your summons with other Summon Core users in your party, raid and guild.\n" ..
        "'Say hello now' announces your log size so anyone with newer or older entries swaps them with you.", 16, -184):SetWidth(740)
    return function()
        local admin = ST.IsAdmin()
        selfTest:SetShown(admin) -- an admin tool
        importExport:ClearAllPoints()
        importExport:SetPoint("TOPLEFT", admin and 348 or 182, -140)
        local st = ST.Sync.state
        local channels = ST.Sync.channels()
        info:SetText(string.format(
            "Summons in your log: %s\nLatest: %s\nQueued to send: %s\nChannels right now: %s",
            T.Paint("amber", ST.Store.Count()), ST.Store.Latest() > 0 and fmtTime(ST.Store.Latest()) or "never",
            T.Paint("amber", #st.queue),
            #channels > 0 and T.Paint("cyan", table.concat(channels, ", ")) or T.Paint("dim", "none (not in a group or guild)")))
    end
end

-- Tools: three sections under one row of small buttons, like the Party tab. General holds what everyone uses (windows,
-- the record, settings); Testing holds the things to try and the test switches; Checks holds the live checklist. Each
-- section is a stack of titled groups, five buttons to a row; admin-only tools are hidden for everyone else and the rows
-- close up around them, so nobody sees gaps. One output box sits under whichever section is on show. The tab opens on
-- the section used last. Checks is the admin's only: its steps talk about the gags and Zennit's secrets (spoilers).
local TOOL_SECTIONS = { { "general", "GENERAL" }, { "testing", "TESTING" }, { "checks", "CHECKS", true } }
local tools = {} -- tools.select(name) shows one of the sections

local function buildTools(f)
    local COL_W, GAP, PER_ROW, STEP = 142, 8, 5, 30 -- five buttons across the 776 px tab
    local sections, sectionButtons = {}, {}

    local out = bodyText(f, 16, -300, 740, 140)
    local shown = "" -- what the output box says, so COPY can hand it over: the box itself cannot be selected
    local function show(text, full) -- full: the longer text COPY hands over, when the box only has room for a summary
        shown = full or text
        out:SetText(text)
    end

    -- A section's contents, top to bottom: groups (a title and a grid of buttons) and rows (a frame of its own).
    local function section(name)
        local frame = CreateFrame("Frame", nil, f)
        frame:SetPoint("TOPLEFT", 0, -34)
        frame:SetPoint("BOTTOMRIGHT")
        sections[name] = { frame = frame, blocks = {}, height = 0 }
        return sections[name]
    end
    local function group(sec, title, adminOnly)
        local g = { kind = "group", title = label(sec.frame, title, 16, 0), items = {}, admin = adminOnly }
        sec.blocks[#sec.blocks + 1] = g
        return g
    end
    local function tool(g, text, onClick, adminOnly, style)
        local b = T.Button(g.title:GetParent(), text, COL_W, 24, onClick, style)
        g.items[#g.items + 1] = { widget = b, admin = adminOnly }
        return b
    end
    local function row(sec, title, adminOnly)
        local r = CreateFrame("Frame", nil, sec.frame)
        r:SetSize(740, 24)
        local fs = label(r, title, 0, -3)
        sec.blocks[#sec.blocks + 1] = { kind = "row", widget = r, admin = adminOnly }
        return r, fs
    end

    -- GENERAL ------------------------------------------------------------------------------------------------------
    local general = section("general")
    local windows = group(general, "WINDOWS")
    tool(windows, "IMPORT / EXPORT", function() ST.Export.Open("import") end)
    tool(windows, "TAKE THE TOUR", function()
        if not ST.Intro.Watched() then window:Hide() end -- the intro plays first: out of its way
        ST.Tour.Start()
    end)
    tool(windows, "PLAY THE INTRO", function()
        window:Hide()
        ST.Intro.Play("1", function() Hub.Open("tools") end)
    end)
    tool(windows, "DIAGNOSTICS", function() ST.ToggleTests("") end, true)
    tool(windows, "LARGE-IMAGE TEST", function() ST.Comic.Toggle("") end, true)

    local record = group(general, "THE RECORD")
    tool(record, "WEEK AND SEASON", function()
        local W = ST.Week
        local season = W.Season()
        local immune, untilT = W.Immune(time())
        show(table.concat({
            "This week: " .. W.Describe(W.Score(W.Start())),
            "Last week: " .. W.Describe(W.Score(W.Start() - 7 * 86400)),
            season.running and string.format("Season %d: Zennit %d of %d wins, the group %d of %d. Finales so far: %d.", season.number, season.zennit,
                W.WINS, season.group, W.WINS, #season.finales)
                or string.format("Season: none is running; the admin stopped the last one. Finales so far: %d.", #season.finales),
            immune and ("Zennit is on his week off until " .. date("%a %d %b", untilT) .. ".") or "Zennit is on the list.",
        }, "\n"))
    end)
    tool(record, "THE RULES", function() -- long: it goes to the chat window, which scrolls
        local lines = ST.Week.RulesCard()
        for _, line in ipairs(lines) do ST.print(line) end
        show("The rules of the race, with this week's numbers, are in the chat window; COPY copies them.", ST.Check.Joined(lines))
    end)
    tool(record, "THE TITLES", function()
        for _, line in ipairs(ST.Ledger.Standings()) do ST.print(line) end
        show("Who leads each of the season's titles is in the chat window.")
    end)
    tool(record, "THE TAB", function()
        for _, line in ipairs(ST.Silver.Lines()) do ST.print(line) end
        show("The tab, who owes what, is in the chat window.")
    end)
    tool(record, "SUMMON CARDS", function()
        for _, line in ipairs(ST.Cards.Lines()) do ST.print(line) end
        show("Who holds a summon card, and the punches left, are in the chat window.")
    end)
    tool(record, "LEADERBOARD", function() -- also for Zennit, who cannot open the Party tab
        for _, line in ipairs(ST.Leaders.Lines(10)) do ST.print(line) end
        show("The leaderboard, summons of Zennit, fish given to him and snowballs thrown at him, is in the chat window.")
    end)
    tool(record, "FISH", function()
        for _, line in ipairs(ST.Fish.Lines()) do ST.print(line) end
        show("The fish book, who has given Zennit fish, is in the chat window.")
    end)
    tool(record, "PAST SEASONS", function() -- a few lines for each season: they go to the chat window, which scrolls
        local seasons = ST.Ledger.Seasons()
        for _, s in ipairs(seasons) do
            for _, line in ipairs(s.lines) do ST.print(line) end
        end
        show(#seasons > 0 and "The Index's keepsake of each finished season is in the chat window." or
            "No season has finished yet. The Index is keeping the file open.")
    end)
    tool(record, "HOW IT FELT", function() -- the weekly question's counts: the admin's (and Zennit's) eyes only
        for _, line in ipairs(ST.Feelings.Summary(8) or {}) do ST.print(line) end
        show("How the group felt, week by week, is in the chat window. Counts only, never names.")
    end, true)
    tool(record, "PLAYTEST REPORT", function() -- long: it goes to the chat window, which scrolls
        local lines = ST.Report.Lines()
        for _, line in ipairs(lines) do ST.print(line) end
        show("What the log says about how the race is being played is in the chat window; COPY copies it.", ST.Check.Joined(lines))
    end)

    local paints = {} -- every switch repaints after any click, because the two test modes turn each other off
    local function switch(g, name, get, set, adminOnly)
        local b
        local function paint() b:SetText(name .. ": " .. (get() and "ON" or "OFF")) end
        b = tool(g, "", function()
            set(not get())
            for _, repaint in ipairs(paints) do repaint() end
        end, adminOnly)
        paints[#paints + 1] = paint
        paint()
    end

    local data = group(general, "SETTINGS AND YOUR DATA")
    switch(data, "SOUNDS", function() return ST.db.settings.soundOn ~= false end,
        function(v) ST.db.settings.soundOn = v end)
    tool(data, "UNDO LAST SUMMON", function()
        local last = ST.Store.RemoveLast()
        show(last and string.format("Removed %s -> %s (badges already earned are kept).", last.ev.caster, last.ev.target) or
            "Nothing to undo.")
        Hub.Refresh()
    end)
    tool(data, "RESET MY DATA...", function() ST.Reset.Ask(false) end, nil, "danger")
    tool(data, "RESET ALL...", function() ST.Reset.Ask(true) end, true, "danger")
    -- the admin's account sees the addon as a player does: this one switch stays in reach while it is on
    switch(data, "VIEW AS PLAYER", function() return ST.db.settings.viewAsPlayer == true end, function(v)
        ST.db.settings.viewAsPlayer = v or nil
        Hub.Refresh()
    end, true)
    data.items[#data.items].account = true

    -- the season, for everyone: the admin starts a new one or stops the one in progress (each asks first)
    local season = group(general, "THE SEASON (ADMIN)", true)
    tool(season, "START NEW SEASON...", function() ST.Reset.Season("start") end, true)
    tool(season, "STOP SEASON...", function() ST.Reset.Season("stop") end, true, "danger")

    -- TESTING ------------------------------------------------------------------------------------------------------
    local testing = section("testing")
    local try = group(testing, "TRY THINGS")
    tool(try, "WHERE AM I?", function() show(whereText()) end)
    -- the next three are the admin's: the BattleTag report names Zennit's account, and the clips may hold gag lines (spoilers)
    tool(try, "BATTLE.NET CHECK", function() show(ST.TagReport()) end, true)
    tool(try, "LIST VOICE CLIPS", function()
        local cats = ST.Clips.Categories()
        if #cats == 0 then
            return show("No voice clips yet: put .ogg files named <category>_<NN>_<who> in Media/clips, run " ..
                "tools/build_clip_manifest.ps1, then /reload.")
        end
        local lines = {}
        for _, c in ipairs(cats) do lines[#lines + 1] = string.format("%s: %d", c[1], c[2]) end
        show("Voice clips: " .. table.concat(lines, ",  "))
    end, true)
    tool(try, "TEST A SUMMONING", function() ST.Respond.Test() end, true)
    tool(try, "HELPERS PROMPT", function()
        ST.Prompt.Ask("Target", { "Alice", "Bob", "Cara" }, {}, function(names, confirmed)
            show(string.format("Prompt result: %s (%s)", #names > 0 and table.concat(names, ", ") or "nobody",
                confirmed and "confirmed" or "unconfirmed"))
        end)
    end, true)
    tool(try, "ZENNIT GAG", function() ST.Gag.Play() end, true)
    tool(try, "PARTY GAG", function() ST.Gag.PlayParty() end, true)
    tool(try, "SOUND CHECK", function() ST.Intro.Check() end, true)

    local clipRow = row(testing, "VOICE CLIP", true)
    local clip = T.EditBox(clipRow, 170, 22)
    clip:SetPoint("TOPLEFT", 110, -1)
    local function playClip()
        local file = ST.Clips.Play(clip:GetText())
        show(file and ("Played " .. file) or "Nothing to play. Type a category or file name.")
    end
    clip:SetScript("OnEnterPressed", playClip)
    button(clipRow, "PLAY", 288, 0, 80, playClip)

    local pingRow = row(testing, "PING PLAYER", true)
    local ping = T.EditBox(pingRow, 170, 22)
    ping:SetPoint("TOPLEFT", 110, -1)
    button(pingRow, "SEND PING", 288, 0, 120, function()
        ST.SendPings(ping:GetText())
        show("Ping sent. Replies appear in Diagnostics > Addon messages.")
    end)

    local modes = group(testing, "TEST MODES", true)
    switch(modes, "ZENNIT TEST", function() return ST.db.settings.zenitTest == true end,
        function(v)
            ST.db.settings.zenitTest = v
            if v then ST.db.settings.partyTest = false end
        end, true)
    switch(modes, "PARTY TEST", function() return ST.db.settings.partyTest == true end,
        function(v)
            ST.db.settings.partyTest = v
            if v then ST.db.settings.zenitTest = false end
        end, true)
    switch(modes, "DETECTOR", function() return ST.db.settings.debug == true end,
        function(v) ST.db.settings.debug = v end, true)
    -- the Story tab also shows the season after this one, as if it had begun (admin only; nothing in the log changes)
    switch(modes, "PREVIEW NEXT SEASON", function() return ST.db.settings.previewSeason == true end,
        function(v)
            ST.db.settings.previewSeason = v or nil
            Hub.Refresh()
        end, true)

    local selfTests = group(testing, "TEST DATA AND SELF-TESTS", true)
    tool(selfTests, "ADD TEST SUMMON", function()
        local ev = ST.AddFake("Tester", {})
        show(string.format("Test summon saved: %s in %s (+%d, %s). It stays on this client.", ev.target, ev.subzone ~= "" and ev.subzone or "nowhere", ev.points, ev.kind))
        Hub.Refresh()
    end, true)
    tool(selfTests, "SYNC SELF-TEST", function()
        ST.SyncTest.Run()
        show("Self-test results are in the chat window.")
    end, true)
    tool(selfTests, "RUN TAG TESTS", function()
        local ok, detail = ST.TagTest()
        show((ok and T.Paint("green", "PASS ") or T.Paint("red", "FAIL ")) .. detail)
    end, true)

    -- CHECKS: the live checks (design/verification.md): run the automatic ones, then step through the rest with the buttons
    local checks = section("checks")
    local intro = T.Text(checks.frame, 18, "dim")
    intro:SetSize(740, 60)
    intro:SetJustifyH("LEFT")
    intro:SetJustifyV("TOP")
    intro:SetText("The live-client checklist. RUN AUTO runs the checks the addon can do itself; NEXT shows the steps " ..
        "for the next one that needs a person, then PASS, FAIL or SKIP records it. REPORT opens the results to send back.")
    checks.blocks[#checks.blocks + 1] = { kind = "row", widget = intro, height = 64, admin = true }
    local checkRow, checkLabel = row(checks, "CHECKS", true)
    local current -- the check on show
    local function paintChecks()
        checkLabel:SetText("CHECKS " .. (ST.Check.Summary()))
    end
    -- the output box has room for a few lines, so the steps and the results go to the chat window, which scrolls, with a headline here
    local function tellChat(lines, headline)
        for _, l in ipairs(lines) do ST.print(l) end
        show(headline .. " The details are in the chat window; COPY copies them.", table.concat(lines, "\n"))
    end
    local function showCheck(id)
        current = id
        if not id then
            return show("Every check that needs a person has a result. REPORT opens the report to send back.")
        end
        local lines = ST.Check.Detail(id)
        tellChat(lines, lines[1]:sub(1, 150))
    end
    local function mark(status)
        if not current then return showCheck((ST.Check.Next())) end
        ST.Check.Record(current, status, "")
        showCheck((ST.Check.Next()))
        paintChecks()
    end
    button(checkRow, "RUN AUTO", 112, 0, 90, function()
        local lines, bad = {}, {}
        for _, r in ipairs(ST.Check.RunAuto()) do
            if not r.ok then bad[#bad + 1] = r.id end
            lines[#lines + 1] = string.format("%s %s: %s (%s)", r.ok and "PASS" or "FAIL", r.id, r.title, tostring(r.detail))
        end
        tellChat(lines, #bad == 0 and "Automatic checks: all passed." or ("Automatic checks: " .. #bad .. " FAIL (" .. table.concat(bad, ", ") .. ")."))
        paintChecks()
    end)
    button(checkRow, "NEXT", 206, 0, 56, function() showCheck((ST.Check.Next())) end)
    button(checkRow, "PASS", 266, 0, 56, function() mark("pass") end)
    button(checkRow, "FAIL", 326, 0, 56, function() mark("fail") end)
    button(checkRow, "SKIP", 386, 0, 56, function() mark("skip") end)
    button(checkRow, "TRACE", 446, 0, 64, function()
        local lines = {}
        for i = math.max(1, #ST.trace - 11), #ST.trace do
            lines[#lines + 1] = date("%H:%M:%S", ST.trace[i].time) .. " " .. ST.trace[i].text
        end
        if #lines == 0 then return show("Nothing traced yet: it records the summon prompt and the answers as they happen.") end
        tellChat(lines, "The last " .. #lines .. " things the summon prompt and the answers did.")
    end)
    button(checkRow, "REPORT", 514, 0, 80, function() ST.Check.Command("report") end)
    button(checkRow, "COPY", 598, 0, 60, function() ST.Check.Copy(shown) end)

    -- Lays a section out top to bottom for this player, and returns how far down it ran.
    local function layout(sec, admin, account) -- account: the admin's own account, even while viewing as a player
        local y = -6
        for _, block in ipairs(sec.blocks) do
            local visible = admin or not block.admin
            if block.kind == "group" then
                local n = 0
                for _, item in ipairs(block.items) do
                    local on = visible and (admin or not item.admin or (item.account and account))
                    item.widget:SetShown(on)
                    if on then
                        item.widget:ClearAllPoints()
                        item.widget:SetPoint("TOPLEFT", 16 + (n % PER_ROW) * (COL_W + GAP), y - 24 - math.floor(n / PER_ROW) * STEP)
                        n = n + 1
                    end
                end
                visible = n > 0
                block.title:SetShown(visible)
                if visible then
                    block.title:ClearAllPoints()
                    block.title:SetPoint("TOPLEFT", 16, y)
                    y = y - 24 - math.ceil(n / PER_ROW) * STEP - 8
                end
            else
                block.widget:SetShown(visible)
                if visible then
                    block.widget:ClearAllPoints()
                    block.widget:SetPoint("TOPLEFT", 16, y)
                    y = y - (block.height or STEP + 4)
                end
            end
        end
        sec.height = -y
    end

    local selected = "general"
    local function placeOutput()
        out:ClearAllPoints()
        out:SetPoint("TOPLEFT", 16, -34 - sections[selected].height - 8)
        out:SetPoint("BOTTOMRIGHT", -16, 4)
    end
    function tools.select(name)
        selected = name
        ST.db.settings.toolsSection = name -- the tab opens on the section used last, across reloads
        for _, s in ipairs(TOOL_SECTIONS) do
            local on = s[1] == name
            sections[s[1]].frame:SetShown(on)
            sectionButtons[s[1]]:SetSelected(on)
        end
        placeOutput()
    end
    for i, s in ipairs(TOOL_SECTIONS) do
        sectionButtons[s[1]] = button(f, s[2], 4 + (i - 1) * 126, -4, 120, function() tools.select(s[1]) end, "tab")
    end
    tools.select(sections[ST.db.settings.toolsSection] and ST.db.settings.toolsSection or "general")

    return function()
        paintChecks()
        local admin = ST.IsAdmin()
        for _, s in ipairs(TOOL_SECTIONS) do
            sectionButtons[s[1]]:SetShown(admin or not s[3]) -- an admin-only section is the last, so no gap is left
            layout(sections[s[1]], admin, ST.IsAdminAccount())
        end
        for _, s in ipairs(TOOL_SECTIONS) do
            if s[1] == selected and s[3] and not admin then return tools.select("general") end
        end
        placeOutput()
    end
end

-- The Party tab: the party's own pages (Summary, Tally, Leaders, Badges) as sections under one row of small buttons.
local SECTIONS = { { "summary", "SUMMARY", buildSummary }, { "tally", "TALLY", buildTally }, { "leaders", "LEADERS", buildLeaders },
    { "badges", "BADGES", buildBadges } }
local party = {} -- party.select(name) shows one of the sections

local function buildParty(f)
    local sections, buttons = {}, {}
    function party.select(name)
        for _, s in ipairs(SECTIONS) do
            local on = s[1] == name
            sections[s[1]].frame:SetShown(on)
            buttons[s[1]]:SetSelected(on)
        end
    end
    for i, s in ipairs(SECTIONS) do
        local sub = CreateFrame("Frame", nil, f)
        sub:SetPoint("TOPLEFT", 0, -34)
        sub:SetPoint("BOTTOMRIGHT")
        sections[s[1]] = { frame = sub, refresh = s[3](sub) }
        buttons[s[1]] = button(f, s[2], 4 + (i - 1) * 126, -4, 120, function() party.select(s[1]) end, "tab")
    end
    party.select("summary")
    party.buttons = buttons
    return function() -- the sections are small, so refresh them all (this also lets the self-check cover each one)
        for _, s in ipairs(SECTIONS) do sections[s[1]].refresh() end
    end
end

local BUILDERS = { party = buildParty, zennit = buildAnswer, log = buildLog, story = buildStory, sync = buildSync,
    tools = buildTools }

----------------------------------------------------------------------
-- The season band and the status line, shown on every tab
----------------------------------------------------------------------
local function buildChrome()
    local band = CreateFrame("Frame", nil, window)
    chrome.band = band
    band:SetPoint("TOPLEFT", 12, -64)
    band:SetPoint("TOPRIGHT", -12, -64)
    band:SetHeight(26)
    T.Panel(band)
    local head = T.Text(band, 18, "dim")
    head:SetPoint("LEFT", 8, 0)
    head:SetText("SEASON.DAT")

    -- one side of the race: its name, a block per weekly win needed, and the count
    local function meter(anchor, name, color)
        local fs = T.Text(band, 18, color)
        fs:SetPoint("LEFT", anchor, "RIGHT", 18, 0)
        fs:SetText(name)
        local m = { blocks = {}, color = color }
        local prev = fs
        for i = 1, ST.Week.WINS do
            local b = T.Fill(band, color, 1)
            b:SetSize(14, 10)
            b:SetPoint("LEFT", prev, "RIGHT", i == 1 and 8 or 3, 0)
            m.blocks[i], prev = b, b
        end
        m.count = T.Text(band, 18, color)
        m.count:SetPoint("LEFT", prev, "RIGHT", 8, 0)
        return m
    end
    chrome.zennit = meter(head, "ZENNIT", "pink")
    chrome.group = meter(chrome.zennit.count, "GROUP", "cyan")
    chrome.week = T.Text(band, 18, "green")
    chrome.week:SetPoint("RIGHT", -8, 0)

    -- the bottom line: a command prompt with a blinking cursor, and the log and sync counts
    local prompt = T.Text(window, 18, "dim")
    prompt:SetPoint("BOTTOMLEFT", 14, 10)
    prompt:SetText("C:\\INDEX>")
    T.Cursor(window):SetPoint("LEFT", prompt, "RIGHT", 6, 0)
    chrome.status = T.Text(window, 18, "dim")
    chrome.status:SetPoint("BOTTOMRIGHT", -14, 10)
    chrome.status:SetJustifyH("RIGHT")
end

local function refreshChrome()
    local W = ST.Week
    local season = W.Season()
    for _, side in ipairs({ "zennit", "group" }) do
        local m, wins = chrome[side], season[side]
        for i, b in ipairs(m.blocks) do b:SetAlpha(i <= wins and 1 or 0.2) end
        m.count:SetText(string.format("%d/%d", wins, W.WINS))
    end
    local immune, untilT = W.Immune(time())
    if not season.running then
        chrome.week:SetText(T.Paint("amber", "NO SEASON RUNNING · THE RACE IS OFF"))
    elseif immune then
        chrome.week:SetText(T.Paint("amber", "ZENNIT IS ON HIS WEEK OFF UNTIL " .. date("%a %d %b", untilT):upper()))
    else
        local week = W.Score(W.Start())
        if week.new then
            -- the new race: who leads the week and by how much (a tie is his), how many summons of him have been filed,
            -- and his dice left (or the Index closed)
            local side, by = W.Lead(week)
            local lead = side == "group" and T.Paint("cyan", "GROUP +" .. by) or
                T.Paint("pink", by == 0 and "ZENNIT (TIE)" or ("ZENNIT +" .. by))
            chrome.week:SetText(string.format("WEEK: %s · FILED %d/%d · %s", lead, week.counted, W.RULES.cap,
                week.closed and T.Paint("amber", "CLOSED") or ("DICE " .. W.DiceLeft(W.Start()))))
        else
            chrome.week:SetText(string.format("THIS WEEK  %s / %s", T.Paint("cyan", "GROUP " .. week.group),
                T.Paint("pink", "ZENNIT " .. week.zennit)))
        end
    end
    local channels = ST.Sync.channels()
    chrome.status:SetText(string.format("%d RECORDS · %d QUEUED · LINK: %s", ST.Store.Count(), #ST.Sync.state.queue,
        #channels > 0 and table.concat(channels, ", "):upper() or "NONE"))
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
-- Each of the first two tabs is closed to the other side, as a joke (not security): Zennit may not open the Party tab
-- and the party may not open Zennit's. The admin may open both, to try them, unless a test mode is on: Zennit test
-- mode closes the Party tab, party test mode closes Zennit's. Returns true after playing the gag that side gets.
local function gagged(name)
    if name == "party" and ST.Gag.IsZennit() then
        ST.Gag.Play()
        return true
    end
    if name == "zennit" and not ST.Gag.IsZennit() and (ST.Gag.IsPartyTest() or not ST.IsAdmin()) then
        ST.Gag.PlayParty()
        return true
    end
    return false
end

local function selectTab(name)
    if gagged(name) then return false end
    current = name
    for key, tab in pairs(tabs) do
        local on = key == name
        tab.frame:SetShown(on)
        tab.button:SetSelected(on)
    end
    tabs[name].refresh()
    refreshChrome()
    return true
end

local function build()
    window = T.Window("SummonCoreHub", 800, 590)
    window.TitleText:SetText("SUMMON_CORE.EXE  ·  v" .. ST.version)
    buildChrome()

    for i, name in ipairs(ORDER) do
        local content = CreateFrame("Frame", nil, window)
        content:SetPoint("TOPLEFT", 12, -98)
        content:SetPoint("BOTTOMRIGHT", -12, 34)
        content:Hide()
        local tabButton = T.Button(window, i .. " " .. LABELS[name], 122, 24, function()
            if current ~= name then T.Beep() end
            selectTab(name)
        end, "tab")
        tabButton:SetPoint("TOPLEFT", 12 + (i - 1) * 128, -34)
        tabs[name] = { button = tabButton, frame = content, refresh = BUILDERS[name](content) }
    end
    window:SetScript("OnShow", function()
        if current then
            tabs[current].refresh()
            refreshChrome()
        end
    end)
end

-- Refreshes the open tab (call after anything that changes the log).
function Hub.Refresh()
    if window and window:IsShown() and current and tabs[current] then
        ST.Guard("the " .. current .. " tab", tabs[current].refresh)
        ST.Guard("the season band", refreshChrome)
    end
end

-- Opens the window on a tab (default: the last one used, or the player's own: Party, or Zennit's for Zennit). The old
-- names summary, tally and badges open the Party tab on that section, and answer opens Zennit's.
function Hub.Open(name)
    if not window then build() end
    local tab = TAB_OF[name] or name
    if tab and not tabs[tab] then tab = nil end
    local zenit = ST.Gag.IsZennit()
    tab = tab or current or (zenit and "zennit" or "party")
    if gagged(tab) then -- the other side's tab: the gag, then this player's own tab instead
        tab = zenit and "zennit" or "party"
    end
    if SECTION_OF[name] then party.select(name) end
    if not window:IsShown() then window:Show() end
    selectTab(tab)
end

function Hub.Window() return window end

-- A part of the window, for the tour to outline: "window", "season" (the band), "week" (this week, on the band), "status"
-- (the line along the bottom), "tab:<name>" (a tab's button) or "section:<name>" (a Party section's button). nil if unknown.
function Hub.Spot(name)
    if not window then build() end
    local tab = name:match("^tab:(%w+)$")
    if tab then return tabs[tab] and tabs[tab].button end
    local section = name:match("^section:(%w+)$")
    if section then return party.buttons and party.buttons[section] end
    return ({ window = window, season = chrome.band, week = chrome.week, status = chrome.status })[name]
end

function Hub.Toggle()
    if window and window:IsShown() then window:Hide() else Hub.Open() end
end

-- Builds the window if needed and refreshes every tab, returning true or false, error.
-- Used by the self-test to catch mistakes in the window code without showing it.
function Hub.SelfCheck()
    if not window then build() end
    for _, name in ipairs(ORDER) do
        local ok, err = pcall(tabs[name].refresh)
        if not ok then return false, name .. ": " .. tostring(err) end
    end
    local ok, err = pcall(refreshChrome)
    if not ok then return false, "season band: " .. tostring(err) end
    -- the admin's season preview draws a season that has not begun (it only shows on the admin's account)
    local preview = ST.db.settings.previewSeason
    ST.db.settings.previewSeason = true
    local shown, why = pcall(tabs.story.refresh)
    ST.db.settings.previewSeason = preview
    if not shown then return false, "story preview: " .. tostring(why) end
    return true
end
