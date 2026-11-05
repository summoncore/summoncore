local ADDON, ST = ...

ST.name = ADDON
ST.prefix = "SUMMONCORE"
ST.version = "0.28.1"

local DB_VERSION = 1

local function print_(msg)
    print("|cff33ccffSC|r " .. tostring(msg))
end
ST.print = print_

-- Errors are caught and said (design/lenses.md, Risk Mitigation). With script errors off, which is WoW's default, a bug in a
-- command or an event handler is otherwise silent: the feature just seems not to exist. Guard runs fn under pcall; a failure is
-- kept for /sc errors, said once in chat (per place and message), and still handed to the game's own error handler, so BugSack
-- and the red box behave as they always did. Returns ok and what fn returned.
ST.errors = {}
local MAX_ERRORS = 20
local told = {}
function ST.Guard(name, fn, ...)
    local results = { pcall(fn, ...) }
    if results[1] then return unpack(results) end
    local msg = tostring(results[2]):sub(1, 300)
    local log = ST.errors
    log[#log + 1] = { time = time(), name = name, msg = msg }
    if #log > MAX_ERRORS then table.remove(log, 1) end
    local key = name .. "|" .. msg
    if not told[key] then
        told[key] = true
        ST.print("|cffff6644hit a problem in " .. name .. ":|r " .. msg .. " (|cffffd100/sc errors|r lists them; please tell Aaron)")
    end
    local handler = geterrorhandler and geterrorhandler()
    if handler then pcall(handler, "Summon Core, " .. name .. ": " .. msg) end
    return false, msg
end

-- A function that always runs under Guard: for event handlers and scripts.
function ST.Safe(name, fn)
    return function(...) return ST.Guard(name, fn, ...) end
end

-- Stringify anything safely, including 12.0 secret values and errors.
function ST.safe(v)
    if v == nil then return "nil" end
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    local ok, s = pcall(tostring, v)
    return ok and s or "<error>"
end

function ST.isSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- A character name as the addon stores it: just the first word. This client shows names as "Name Surname"
-- (and other clients may use "Name-Realm"), but the plain UnitName is a single word, so that is what events,
-- tallies and sender checks all compare. nil for anything that is not a usable name.
function ST.baseName(name)
    if type(name) ~= "string" or ST.isSecret(name) then return nil end
    return name:match("^[^%s%-]+")
end

-- The admin is whoever is logged in to one Battle.net account, and Zennit's own account is Zennit whichever character he
-- plays. The check runs on the player's own computer, so it keeps the debug tools and unreached chapters out of the way; it is
-- not security. Both accounts are known by a hash of their BattleTag (ST.TagHash), so the tags themselves are not in the addon.
-- That keeps them out of sight, not secret: a BattleTag's number is short, so anyone who guesses the name can find it.

-- This account's BattleTag, or nil if the game does not give it (ST.bnGetInfo is a seam for the self-test).
function ST.BattleTag()
    local get = ST.bnGetInfo or BNGetInfo
    if not get then return nil end
    local ok, _, tag = pcall(get)
    if ok and type(tag) == "string" and not ST.isSecret(tag) then return tag end
end

-- A short hash of a BattleTag (case and stray spaces do not matter), or nil. Season commands and the reset request carry the
-- admin's (ST.ADMIN_HASH) so other clients know them for the admin's. Anyone who reads this file can stamp a message the same
-- way: it keeps out mistakes and mischief, not a determined friend.
function ST.TagHash(tag)
    if type(tag) ~= "string" then return nil end
    tag = tag:match("^%s*(.-)%s*$"):lower()
    if tag == "" then return nil end
    local h = 5381
    for i = 1, #tag do h = (h * 33 + tag:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

-- The two accounts, by ST.TagHash of their BattleTag. The admin's is also the stamp on season marks and reset requests (Sync),
-- which clients before 0.28.1 work out from the tag itself, so it must stay what it is.
ST.ADMIN_HASH = "dde6f852"
ST.ZENNIT_HASH = "31ce8f1c"

-- Is `tag` the account whose hash is `hash`? A missing tag is nobody's.
function ST.TagIs(tag, hash)
    local h = ST.TagHash(tag)
    return h ~= nil and h == hash
end

-- The admin's own account, whatever it is set to show.
function ST.IsAdminAccount()
    return ST.TagIs(ST.BattleTag(), ST.ADMIN_HASH)
end

-- The admin acting as one: the admin's account, unless it has switched to seeing the addon as a player does (/sc asplayer),
-- which hides the admin's tools, help lines and spoilers until it is switched back.
function ST.IsAdmin()
    return ST.IsAdminAccount() and not (ST.db and ST.db.settings and ST.db.settings.viewAsPlayer)
end

function ST.IsZennitAccount()
    return ST.TagIs(ST.BattleTag(), ST.ZENNIT_HASH)
end

-- Checks the BattleTag hash with sample tags, then the account lookups through the ST.bnGetInfo seam as the game would report
-- them, with sample accounts standing in for the admin's and Zennit's (their tags are not in the addon). Returns true or false
-- and a short description.
function ST.TagTest()
    local sample = ST.TagHash("Sample#1234")
    if not (sample and sample:match("^%x%x%x%x%x%x%x%x$")) then return false, "the BattleTag hash is malformed" end
    local cases = {
        { "Sample#1234", true }, { "  sample#1234 ", true }, { "SAMPLE#1234", true }, { "Sample#1235", false },
        { "Sample", false }, { "Sample#12345", false }, { "", false }, { "   ", false }, { nil, false }, { 5, false },
    }
    for i, c in ipairs(cases) do
        if ST.TagIs(c[1], sample) ~= c[2] then return false, "sample " .. i .. " matched wrongly" end
    end
    if ST.ADMIN_HASH == ST.ZENNIT_HASH or not ST.ADMIN_HASH:match("^%x%x%x%x%x%x%x%x$") or not ST.ZENNIT_HASH:match("^%x%x%x%x%x%x%x%x$") then
        return false, "the admin's or Zennit's hash is malformed"
    end
    -- as the game would report them: id, tag, ...
    local saved, savedView = ST.bnGetInfo, ST.db and ST.db.settings and ST.db.settings.viewAsPlayer
    local savedAdmin, savedZennit = ST.ADMIN_HASH, ST.ZENNIT_HASH
    local function report(tag) return function() return 1, tag end end
    local function view(on) if ST.db and ST.db.settings then ST.db.settings.viewAsPlayer = on end end
    local ok, out = pcall(function()
        ST.ADMIN_HASH, ST.ZENNIT_HASH = ST.TagHash("Admin#1"), ST.TagHash("Zennit#1")
        view(nil)
        ST.bnGetInfo = report(" ADMIN#1")
        if not (ST.IsAdmin() and not ST.IsZennitAccount()) then return "the admin account is not recognised" end
        view(true)
        if ST.db and ST.db.settings and (ST.IsAdmin() or not ST.IsAdminAccount()) then
            return "viewing as a player does not hide the admin, or loses the account"
        end
        view(nil)
        ST.bnGetInfo = report("zennit#1")
        if not (ST.IsZennitAccount() and not ST.IsAdmin()) then return "Zennit's account is not recognised" end
        ST.bnGetInfo = report("Someone#1")
        if ST.IsAdmin() or ST.IsZennitAccount() then return "a stranger is recognised" end
        ST.bnGetInfo = function() error("no Battle.net") end
        if ST.BattleTag() ~= nil or ST.IsAdmin() then return "a failing lookup is not handled" end
    end)
    ST.ADMIN_HASH, ST.ZENNIT_HASH = savedAdmin, savedZennit
    ST.bnGetInfo = saved
    view(savedView)
    if not ok then return false, "error: " .. tostring(out) end
    if out then return false, out end
    return true, string.format("%d samples and 4 account lookups behave. Live: %s", #cases, ST.TagReport())
end

-- One line saying what the game reports for this account and what the addon makes of it.
function ST.TagReport()
    local tag = ST.BattleTag()
    if not tag then return "BattleTag: the game does not report one (admin: no, Zennit's account: no)" end
    return string.format("BattleTag %s: admin %s, Zennit's account %s", tag,
        ST.IsAdminAccount() and (ST.IsAdmin() and "yes" or "yes (viewing as a player)") or "no",
        ST.IsZennitAccount() and "yes" or "no")
end

ST.RITUAL_ID = 698 -- Ritual of Summoning (classic ID; confirm with /sc test)

-- Spell name for an ID, or nil if unknown, secret or the lookup fails.
function ST.SpellName(id)
    if not id or ST.isSecret(id) then return nil end
    local fn = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
    if not fn then return nil end
    local ok, name = pcall(fn, id)
    return ok and name or nil
end

local function initDB()
    SummonTrackerDB = SummonTrackerDB or {}
    local db = SummonTrackerDB
    db.version = db.version or DB_VERSION
    db.events = db.events or {}
    db.badges = db.badges or {}
    db.settings = db.settings or { zenitNames = { "Zennit" }, soundOn = true }
    -- The name is spelt Zennit; earlier versions defaulted to "Zenit", so fix saved settings too.
    local names, seen = db.settings.zenitNames or {}, false
    for i, name in ipairs(names) do
        if name:lower() == "zenit" then names[i] = "Zennit" end
        if names[i]:lower() == "zennit" then seen = true end
    end
    if not seen then names[#names + 1] = "Zennit" end
    db.settings.zenitNames = names
    db.harness = db.harness or {}
    ST.db = db
    -- this character's badges, worked out quietly now if it has none kept yet (Scoring.Badges), so its next summons is
    -- what announces a new one
    if ST.Store.me() then ST.Scoring.Badges(ST.Store.me()) end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", ST.Safe("the login", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        initDB()
        -- Remember what the previous session left behind for the save/reload test.
        ST.previousToken = ST.db.harness.token
    elseif event == "PLAYER_LOGIN" then
        if ST.OnLogin then ST.OnLogin() end
        print_("loaded v" .. ST.version .. ". /sc for commands.")
    end
end))

local function words(str)
    local out = {}
    for w in (str or ""):gmatch("%S+") do out[#out + 1] = w end
    return out
end

local function fmtTime(t)
    return date("%Y-%m-%d %H:%M", t)
end

local commands = {}

function commands.test(rest)
    if ST.ToggleTests then ST.ToggleTests(rest) end
end

-- The live-client checklist: what has to be confirmed in the real game, and what the addon can confirm by itself.
function commands.check(rest)
    ST.Check.Command(rest)
end

function commands.where()
    local mapID, sub = C_Map.GetBestMapForUnit("player"), GetSubZoneText()
    local pts, kind = ST.Scoring.Score(mapID, sub)
    print_(string.format("mapID=%s zone=%s subzone='%s' -> %s (%d pts)", ST.safe(mapID), GetZoneText(), sub, kind, pts))
end

-- What each place is worth, with every map ID checked against the game's own name for it.
function commands.places()
    local lines = ST.Scoring.Places(function(id)
        local ok, info = pcall(C_Map.GetMapInfo, id)
        return ok and type(info) == "table" and type(info.name) == "string" and info.name or nil
    end)
    for _, l in ipairs(lines) do print_(l) end
end

-- Arms (or withdraws) a writ for your next ritual on Zennit: if he declines that summons in the game, it costs him its points.
function ST.ToggleWrit()
    local W, D = ST.Week, ST.Detector
    if D.writ then
        D.writ = false
        ST.Trace("writ withdrawn")
        return print_("The writ is withdrawn. Nothing is spent.")
    end
    local start = W.Start()
    if not W.NewRules(start) then return print_("There are no writs under the old rules.") end
    if W.IsOff(start) then return print_("It is Zennit's week off: the race is off, so a writ would have nothing to say.") end
    local left = W.WritsLeft(start)
    if left == 0 then return print_(string.format("The group has played all %d writs this week.", W.RULES.writs)) end
    D.writ = true
    ST.Trace("writ armed")
    print_(string.format("A writ is armed for your next summons of Zennit (%d left this week). If he declines it in the game, it costs him " ..
        "its points. If he accepts, the writ is spent anyway. /sc writ again withdraws it.", left))
end

function commands.writ() ST.ToggleWrit() end

-- The welcome a newcomer gets at their first login (Intro.lua), again.
function commands.welcome()
    for _, line in ipairs(ST.Intro.WelcomeLines(ST.Gag.IsZennit())) do print_(line) end
end

-- The key binding (Bindings.xml) calls this global: one key to arm or withdraw a writ, with nothing typed in the middle of play.
_G["SummonCore_ToggleWrit"] = ST.Safe("the writ key", ST.ToggleWrit)
_G["BINDING_HEADER_SUMMONCORE"] = "Summon Core"
_G["BINDING_NAME_SUMMONCORE_WRIT"] = "Play a writ on your next summons of Zennit"

-- Adds a test summon at your current location. It is never put on the network.
function ST.AddFake(target, assistants)
    local _, ev, badges = ST.Store.Add({
        caster = ST.Store.me(), target = target, assistants = assistants or {},
        mapID = C_Map.GetBestMapForUnit("player"), subzone = GetSubZoneText(), confirmed = true,
        fake = true, -- test summons stay on this client: not counted for sync, not sent, not exported
    }, true)
    return ev, badges
end

-- Solo testing: /sc fake <target> [helper1 helper2]
function commands.fake(rest)
    local w = words(rest)
    if not w[1] then return print_("usage: /sc fake <target> [helper1 helper2]") end
    local assistants = {}
    for i = 2, math.min(#w, 3) do assistants[#assistants + 1] = w[i] end
    local ev, badges = ST.AddFake(w[1], assistants)
    print_(string.format("fake summon saved: %s in %s (+%d, %s)", ev.target, ev.subzone, ev.points, ev.kind))
    for _, name in ipairs(badges) do print_("|cffffd100Badge earned:|r " .. name) end
end

-- Opens the assistants prompt without a party: /sc fakeprompt <target> <member> <member> ...
function commands.fakeprompt(rest)
    local w = words(rest)
    if #w < 2 then return print_("usage: /sc fakeprompt <target> <member> [member ...]") end
    local target = table.remove(w, 1)
    ST.Prompt.Ask(target, w, {}, function(names, confirmed)
        print_(string.format("prompt result: %s, confirmed=%s", #names > 0 and table.concat(names, ", ") or "none",
            tostring(confirmed)))
    end)
end

function commands.log(rest)
    local list = ST.Store.Recent(tonumber(rest) or 10)
    if #list == 0 then return print_("no summons logged yet") end
    for _, r in ipairs(list) do
        local ev = r.ev
        print_(string.format("%s  %s -> %s  helpers: %s  [%s %d pts]%s", fmtTime(ev.time), ev.caster, ev.target,
            #ev.assistants > 0 and table.concat(ev.assistants, ", ") or "none", ev.kind or "?", ev.points or 0,
            ev.confirmed and "" or " unconfirmed"))
    end
end

function commands.panel()
    ST.Hub.Open("summary")
end

function commands.hub()
    ST.Hub.Toggle()
end

-- His own lines (design/lenses.md, Character): /sc zennit postcard [<place> [<text>|clear]] and /sc zennit away [<text>|clear].
local function zennitLine(sub, arg)
    local S, L = ST.Sync, ST.Ledger
    local mine = ST.Gag.IsZennit() -- anyone may read his lines; only he may write them
    local function show(key, name, default)
        local his = S.ZennitLine(key)
        print_(string.format("%s: '%s'%s", name, his or default, his and "" or " (the Index's default)"))
    end
    if sub == "away" then
        if arg ~= "" then
            if not mine then return print_("only Zennit writes his own lines") end
            S.SetLine("away", arg == "clear" and "" or arg)
        end
        show("away", "His out-of-office (said to whoever summons him on his week off)", "none: the Index says it is not hopeful")
        return
    end
    local place, text = arg:match("^(.-)%s*:%s*(.*)$")
    if not place then place, text = arg, "" end
    local id
    if place ~= "" then
        for mid, name in pairs(ST.Scoring.remoteNames) do
            if name:lower():sub(1, #place) == place:lower() then id = mid end
        end
        if not id then return print_("no far-flung place called '" .. place .. "' (/sc places lists them)") end
    end
    if id and text ~= "" then
        if not mine then return print_("only Zennit writes his own lines") end
        S.SetLine("pc:" .. id, text == "clear" and "" or text)
    end
    local ids = {}
    for mid in pairs(ST.Scoring.remoteNames) do if not id or mid == id then ids[#ids + 1] = mid end end
    table.sort(ids, function(a, b) return ST.Scoring.remoteNames[a] < ST.Scoring.remoteNames[b] end)
    for _, mid in ipairs(ids) do show("pc:" .. mid, "Postcard from " .. ST.Scoring.remoteNames[mid], L.POSTCARDS[mid] or "") end
    if not id and mine then print_("/sc zennit postcard <place>: <your line> writes one (80 letters); 'clear' puts the Index's back.") end
end

-- Questions about him (Ask.lua): his client answers them unless he switches them off.
local function zennitAsk(arg)
    local s = ST.db.settings
    if arg == "off" or arg == "on" then
        if not ST.Gag.IsZennit() then return print_("only Zennit switches questions about him on or off") end
        s.askOff = arg == "off" or nil
    end
    print_(ST.Ask.IsOff() and "Questions about Zennit are off: his client answers none of them. /sc zennit ask on answers them again."
        or "Questions about Zennit are on: his client answers /sc ask, and tells him who asked. /sc zennit ask off stops it.")
end

-- Test switch: makes this character behave as Zennit's so the gag can be tried solo.
function commands.zenit(rest)
    local sub, arg = (rest or ""):match("^(%S*)%s*(.-)$")
    if sub == "postcard" or sub == "away" then return zennitLine(sub, arg) end
    if sub == "ask" then return zennitAsk(arg) end
    if sub ~= "list" and not ST.IsAdmin() then return print_("that is an admin tool") end
    if sub == "list" and not (ST.Gag.IsZennit() or ST.IsAdmin()) then return print_("only Zennit keeps his secret list") end
    if sub == "list" then
        -- his secret list: /sc zennit list [add <place> | remove <n> | clear]
        local R = ST.Respond
        local verb, what = arg:match("^(%S*)%s*(.-)$")
        if verb == "add" then
            local ok, why = R.ListAdd(what)
            print_(ok and ("added '" .. what .. "'") or why)
        elseif verb == "remove" then print_(R.ListRemove(what) and "removed" or "no such entry")
        elseif verb == "clear" then R.ListClear() print_("list cleared") end
        local list, shown = R.List(), {}
        for i, word in ipairs(list) do shown[i] = R.ListPending(word) and (word .. " (from Monday)") or word end
        print_(#list == 0 and "secret list is empty" or "secret list: " .. table.concat(shown, "; "))
        if #list > 0 then print_("a place added this week counts from next Monday; removing one takes effect at once") end
        if #R.ListActive() < #list then
            print_(string.format("only the first %d entries of %d letters or more count", R.LIST_MAX, R.LIST_MIN))
        end
        if ST.Hub then ST.Hub.Refresh() end
        return
    end
    ST.db.settings.zenitTest = not ST.db.settings.zenitTest
    if ST.db.settings.zenitTest then ST.db.settings.partyTest = false end -- the two test modes exclude each other
    print_("Zennit test mode " .. (ST.db.settings.zenitTest and "on" or "off"))
end

-- Test switch: makes this character behave as an ordinary party member (even the admin, or Zennit's own account),
-- so the party's gag on Zennit's tab can be tried solo.
function commands.party()
    if not ST.IsAdmin() then return print_("that is an admin tool") end
    ST.db.settings.partyTest = not ST.db.settings.partyTest
    if ST.db.settings.partyTest then ST.db.settings.zenitTest = false end
    print_("party test mode " .. (ST.db.settings.partyTest and "on" or "off"))
end
commands.zennit = commands.zenit -- either spelling works

function commands.tally()
    if ST.Gag.Blocked() then return end
    local rows = ST.Store.Ranked(ST.Store.Tallies(), ST.Ledger.Facts().casters)
    if #rows == 0 then return print_("no summons logged yet") end
    for i = 1, math.min(#rows, 15) do
        local name, t, ofZennit = rows[i][1], rows[i][2], rows[i][3]
        print_(string.format("%s: cast %d (%d of Zennit this season), received %d, assisted %d, %d pts", name, t.cast, ofZennit,
            t.received, t.assisted, t.points))
    end
end

function commands.badges()
    if ST.Gag.Blocked() then return end
    for _, b in ipairs(ST.Scoring.badges) do
        local got = ST.Scoring.Badges()[b.id]
        print_(string.format("%s %s%s", got and "|cff33ff66[x]|r" or "[ ]", b.name,
            got and (" (" .. fmtTime(got.earned) .. ")") or (b.how and (": " .. b.how) or "")))
    end
end

function commands.undo()
    local last = ST.Store.RemoveLast()
    if last then
        print_(string.format("removed %s -> %s (badges already earned are kept)", last.ev.caster, last.ev.target))
    else
        print_("nothing to undo")
    end
end

function commands.sync()
    ST.Sync.Hello()
    ST.Sync.Status()
end

function commands.export()
    ST.Export.Open("export")
end

function commands.import()
    ST.Export.Open("import")
end

function commands.intro(rest)
    local key = (rest or ""):match("^(%S+)%s+group$")
    if key then return ST.Intro.PlayForGroup(key) end -- shows the group a chapter (design/lenses.md, Pleasure)
    if rest == "previously" then return ST.Intro.PreviouslyOn() end -- this season's chapters, back to back
    ST.Intro.Toggle(rest)
end

-- The guided tour of the window, narrated by the Index (Tour.lua).
function commands.tour(rest) ST.Tour.Start(rest) end

function commands.clip(rest)
    if rest == "" then
        local cats = ST.Clips.Categories()
        if #cats == 0 then
            return print_("no voice clips yet: put .ogg files named <category>_<NN>_<who> in Media/clips, run tools/build_clip_manifest.ps1, then /reload")
        end
        for _, c in ipairs(cats) do print_(string.format("%s: %d clip%s", c[1], c[2], c[2] == 1 and "" or "s")) end
        return print_("/sc clip <category or file name> plays one")
    end
    local file = ST.Clips.Play(rest)
    print_(file and ("played " .. file) or ("nothing to play for '" .. rest .. "'"))
end

-- The weekly contest: how this week is going and how the last one ended.
function commands.week(rest)
    local W = ST.Week
    if rest == "victory" or rest == "group" or ST.Intro.ParseKey(rest) then return ST.Intro.Toggle(rest) end
    if rest == "login" then return W.Replay() end
    if rest == "say" then
        local ok, text = W.SayWeek({
            channel = function() return IsInRaid() and "RAID" or IsInGroup() and "PARTY" or nil end,
            -- The global SendChatMessage is only a deprecation fallback on 12.0-era clients (loaded when the
            -- loadDeprecationFallbacks setting is on, and removed at the next expansion), so prefer the namespaced call.
            send = function(msg, channel) ((C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage)(msg, channel) end,
        })
        ST.Trace("week say: " .. (ok and "sent" or text))
        return print_(ok and ("Told the group: " .. text) or text)
    end
    if rest == "copy" then -- the "Week:" line, in the copy window, to paste where /sc week say would send it
        local text, why = W.SayText()
        if not text then return print_(why) end
        return ST.Check.Copy(text)
    end
    local this, last = W.Score(W.Start()), W.Score(W.Start() - 7 * 86400)
    print_("This week: " .. W.Describe(this))
    print_("Last week: " .. W.Describe(last))
    local whim = W.WhimLine(W.Start())
    if whim and not W.IsOff(W.Start()) then print_("This week's whim: " .. whim) end
    local left = W.DeclinesLeft(W.Start())
    if W.NewRules(W.Start()) and not W.IsOff(W.Start()) then
        print_(string.format("His free declines this week: %d of %d left. Writs: %d of %d left.", left, W.RULES.declines,
            W.WritsLeft(W.Start()), W.RULES.writs))
    end
    local season = W.Season()
    if season.running then
        print_(string.format("Season %d: Zennit %d of %d wins, the group %d of %d. Finales so far: %d.", season.number, season.zennit, W.WINS,
            season.group, W.WINS, #season.finales))
    else
        print_(string.format("Season: none is running; the admin stopped the last one. Finales so far: %d.", #season.finales))
    end
    local facts = ST.Ledger.Facts(season)
    local leave = ST.Ledger.LeaveLine(facts)
    if leave then print_(leave) end
    print_(ST.Ledger.PostcardsLine(facts) or
        string.format("Postcards from Zennit: none yet this season (0 of %d far-flung places).", ST.Ledger.PostcardPlaces()))
    local missing = ST.Ledger.MissingLine(facts)
    if missing then print_(missing) end
    local immune, untilT = W.Immune(time())
    if immune then print_("Zennit is on his week off until " .. date("%a %d %b", untilT) .. ". /sc week victory plays the story.") end
end

-- Summon cards (the coffee card): prepaid silver, sold by Zennit. /sc cards lists the balances; /sc card sell <name> [punches
-- [silver]] and /sc card offer <punches> <silver> are his.
function commands.cards()
    for _, line in ipairs(ST.Cards.Lines()) do print_(line) end
end

function commands.card(rest)
    local verb, a, b, c = (rest or ""):match("^(%S*)%s*(%S*)%s*(%S*)%s*(%S*)")
    if verb == "sell" then
        local offer = ST.Cards.Offers()[1]
        local punches = tonumber(b) or offer.punches
        local silver = tonumber(c) or math.floor(offer.silver * punches / offer.punches + 0.5) -- the usual price per punch
        local card, why = ST.Cards.Issue(a, punches, silver)
        if not card then print_(why) end
    elseif verb == "offer" then
        if ST.Cards.SetOffer(a, b) then
            print_(string.format("offer: %d punches for %d silver", ST.Cards.Offers()[1].punches, ST.Cards.Offers()[1].silver))
        else
            print_("usage: /sc card offer <punches> <silver>")
        end
    else
        local offer = ST.Cards.Offers()[1]
        print_(string.format("A card is prepaid silver. Zennit sells %d punches for %d silver; each time he demands the fifty silver from the holder, a punch pays it.", offer.punches, offer.silver))
        print_("/sc cards lists who holds what; his: /sc card sell <name> [punches [silver]], /sc card offer <punches> <silver>")
    end
end

-- Listens to trade and mail events and prints what the client lets an addon see, to learn how silver could be detected.
-- "/sc probe chat" does the same for the lines said in chat and a summons arriving (Probe.lua), to learn whether what Zennit says
-- can be read.
function commands.probe(rest)
    local chat = (rest or ""):match("^chat%s*(.-)%s*$")
    if chat then return ST.Probe.Chat(chat) end
    ST.Silver.Probe()
end

-- Questions only Zennit's client can answer (Ask.lua): /sc ask lists them, /sc ask <question> asks one.
function commands.ask(rest)
    ST.Ask.Command(rest)
end

-- The problems this session has caught (see ST.Guard): the last ten, newest last; "clear" forgets them.
function commands.errors(rest)
    if rest == "clear" then
        for i = #ST.errors, 1, -1 do ST.errors[i] = nil end
        return print_("errors cleared")
    end
    if #ST.errors == 0 then return print_("No problems caught this session.") end
    for i = math.max(1, #ST.errors - 9), #ST.errors do
        local e = ST.errors[i]
        print_(string.format("%s  %s: %s", date("%H:%M:%S", e.time), e.name, e.msg))
    end
end

-- The Monday tip on or off.
-- How people feel about the game: counts for Zennit and the admin; anyone can switch the weekly question off or on.
function commands.feelings(rest)
    local s = ST.db.settings
    if rest == "off" then s.feelOff = true return print_("The weekly question is off. /sc feelings on brings it back.") end
    if rest == "on" then s.feelOff = nil return print_("The weekly question is on: once a week, at the first login.") end
    local lines = ST.Feelings.Summary(8)
    if not lines then return print_("Only Zennit and the admin see how the group feels, as counts. /sc feelings off stops the weekly question.") end
    for _, l in ipairs(lines) do print_(l) end
end

function commands.tips(rest)
    local s = ST.db.settings
    if rest == "off" then s.tipsOff = true elseif rest == "on" then s.tipsOff = nil end
    print_("Monday tips are " .. (s.tipsOff and "off" or "on") .. ". /sc tips " .. (s.tipsOff and "on" or "off") .. " changes it.")
end

-- The titles as they stand in this season (the Index names them for good at the finale).
function commands.titles()
    for _, line in ipairs(ST.Ledger.Standings()) do print_(line) end
end

-- The tab: who owes Zennit what (his client), or what you owe (everyone else's).
function commands.tab()
    for _, line in ipairs(ST.Silver.Lines()) do print_(line) end
end

-- Prints these lines to the chat window, and with the word "copy" puts them in the copy window instead (the chat window
-- cannot be selected). Copy is a word rather than the default because the window takes the keyboard: someone who only wants
-- to read the rules should not have to press Escape to get back to playing (design/lenses.md, Flow).
local function printOrCopy(lines, rest)
    if rest == "copy" then return ST.Check.CopyLines(lines) end
    for _, line in ipairs(lines) do print_(line) end
end

-- What the log says about how the race is being played (for a playtest). `/sc report copy` opens it to paste.
function commands.report(rest)
    printOrCopy(ST.Report.Lines(), rest)
end

-- The rules of the race, with this week's live numbers. `/sc rules copy` opens them to paste.
function commands.rules(rest)
    printOrCopy(ST.Week.RulesCard(), rest)
end

-- The Index's keepsake of each finished season, newest first.
function commands.seasons()
    local seasons = ST.Ledger.Seasons()
    if #seasons == 0 then return print_("No season has finished yet. The Index is keeping the file open.") end
    for _, s in ipairs(seasons) do
        for _, line in ipairs(s.lines) do print_(line) end
    end
end

function commands.respond(rest)
    if rest == "test" then
        if not ST.IsAdmin() then return print_("that is an admin tool") end
        ST.Respond.Test()
    else
        ST.Respond.Open()
    end
end

-- Says whether this account is the admin, and what the game reports as its BattleTag.
function commands.admin()
    print_(ST.TagReport())
end

-- The season: anyone can ask whether one is running; the admin starts one (0 to 0, from this week) or stops the one in progress.
function commands.season(rest)
    local kind = (rest or ""):lower()
    if kind == "start" or kind == "stop" then return ST.Reset.Season(kind) end
    if ST.Week.Running(ST.Week.Start()) then
        local s = ST.Week.Season()
        print_(string.format("a season is running: Zennit %d, the group %d, first to %d.", s.zennit, s.group, ST.Week.WINS))
    else
        print_("no season is running: the race counts nothing until the admin starts one.")
    end
    if ST.IsAdmin() then print_("/sc season start begins a new season; /sc season stop ends this one now (both ask first)") end
end

-- Test switch: the Story tab also shows the season after this one, as if it had begun, so the admin can look at a season
-- that no finale has reached yet. Nothing in the log changes. (Tools > Testing > PREVIEW NEXT SEASON is the same switch.)
function commands.preview()
    if not ST.IsAdmin() then return print_("that is an admin tool") end
    ST.db.settings.previewSeason = not ST.db.settings.previewSeason or nil
    print_(ST.db.settings.previewSeason and
        "previewing the next season: the Story tab shows it as if it had begun. /sc preview again to switch off." or
        "the Story tab shows the seasons that have begun.")
    if ST.Hub then ST.Hub.Refresh() end
end

-- The admin's account sees the addon as a player does, and back (the switch is the account's, so it works while on).
function commands.asplayer()
    if not ST.IsAdminAccount() then return print_("that is an admin tool") end
    ST.db.settings.viewAsPlayer = not ST.db.settings.viewAsPlayer or nil
    print_(ST.db.settings.viewAsPlayer and
        "viewing as a player: the admin's tools, help lines and spoilers are hidden. /sc asplayer again to switch back." or
        "viewing as the admin again.")
    if ST.Hub then ST.Hub.Refresh() end
end

-- /sc reset - wipes this client's summons, badges and story progress (asks first).
-- /sc reset all - the admin also asks every other Summon Core user in the party, raid and guild to do the same.
function commands.reset(rest)
    local everyone = rest == "all"
    if everyone and not ST.IsAdmin() then return print_("that is an admin tool") end
    ST.Reset.Ask(everyone)
end

function commands.gag()
    ST.Gag.Play()
end

function commands.comic(rest)
    ST.Comic.Toggle(rest)
end

function commands.synctest()
    ST.SyncTest.Run()
end

function commands.debug()
    ST.db.settings.debug = not ST.db.settings.debug
    print_("detector debug " .. (ST.db.settings.debug and "on" or "off"))
end

-- What a player needs: five lines. /sc help all has the rest (design/lenses.md, Interface).
local HELP_SHORT = {
    "/sc - the Summon Core window: the party's tally and badges, Zennit's answers, the log, the story and the tools    /sc tour - the Index shows you round it",
    "/sc rules - the rules of the race, with this week's live numbers    /sc week - how this week and the season stand (/sc week say tells the group, /sc week copy lets you paste it)",
    "/sc tab - what is owed in silver    /sc cards - who holds a summon card    /sc titles - who leads the season's titles",
    "/sc report - how the race is going (/sc report copy opens it to paste into the group chat)    /sc seasons - the record of every finished season",
    "/sc help all - every command (the rest are for setting up, testing and Zennit)    /sc tips off - stop the Monday tip",
}

-- Every command. A line tagged "admin" is listed only for the admin, and one tagged "zennit" for Zennit's account and the
-- admin: the rest of the party would learn the gags and his secrets from them (spoilers).
local HELP = {
    "/sc - open the Summon Core window (everything below is also in it)    /sc help - the short list    /sc help all - this list",
    "/sc tour [step|skip] - a narrated tour of the window: the Index outlines each part as it talks about it (again: stops it). Until you have seen the intro, it plays first; skip goes straight to the tour",
    { "admin", "/sc test - diagnostics panel (/sc test ping <name>)" },
    "/sc log [n] - recent summons    /sc tally - counts and points    /sc badges",
    "/sc panel - open the window on the Party tab",
    { "admin", "/sc zenit - toggle Zennit test mode    /sc party - toggle party test mode" },
    "/sc writ - arm a writ for your next ritual on Zennit: if he declines that summons in the game, it costs him its points",
    { "admin", "/sc check - the live-client checklist: run the automatic checks, follow the steps with a friend, and print a report to send back" },
    "/sc where - current map, subzone and how it scores    /sc places - what every place is worth, checked against the game",
    { "admin", "/sc fake <target> [h1 h2] - add a test summon    /sc fakeprompt <target> <members...>" },
    "/sc sync - say hello to party/guild and show sync status",
    { "admin", "/sc synctest - run the merge self-test" },
    "/sc export / /sc import - copy-paste strings of the summon log",
    "/sc intro [scene] - play the illustrated intro (/sc intro check tests its sound files; /sc intro g2 group shows a chapter to the group; /sc intro previously plays this season's chapters back to back)    /sc welcome - the newcomer's welcome again",
    { "admin", "/sc clip [category|file] - list or play voice clips from Media/clips" },
    { "zennit", "/sc zennit list [add <place>|remove <n>|clear] - his secret list: declining a summon there is free (unless a writ is on it)" },
    { "zennit", "/sc zennit postcard [<place>: <line>|clear] - his own postcard from a far-flung place    /sc zennit away [<line>|clear] - his out-of-office" },
    "/sc ask [<question>] - ask something only Zennit's client can answer (is his hearthstone ready, how long has he been logged in); he is told who asked",
    { "zennit", "/sc zennit ask [on|off] - whether his client answers /sc ask (it is on until he switches it off)" },
    { "admin", "/sc admin - what the game reports as this account's BattleTag, and whether it is the admin or Zennit's" },
    { "admin", "/sc asplayer - see the addon as a player does (admin tools, help lines and spoilers hidden); again to switch back" },
    { "admin", "/sc preview - the Story tab also shows the season after this one, as if it had begun (nothing in the log changes); again to switch off" },
    "/sc season - whether a season is running",
    { "admin", "/sc season start|stop - begin a new season (0 to 0, from this week) or end this one now, for everyone" },
    "/sc reset [all] - wipe summons, badges and the story (all: the admin asks everyone to do the same)",
    "/sc week [say|copy|login|z1..z5|g1..g5|2z1..] - the weekly contest and the season (first to 5 wins); say tells the group, copy opens the same line in a window you can copy from, login says this week's login lines again, a key plays that chapter of the story (2z1, 2g1... in season two)",
    "/sc titles - who leads each of the season's titles so far (heaviest hand, best supporting role, ...)",
    "/sc tab - who owes Zennit what (on his client), or what you owe him (on everyone else's)",
    "/sc cards - who holds a summon card and how many punches are left; /sc card - how cards work (Zennit sells them)",
    { "zennit", "/sc probe - listen to trade and mail events and print what the client shows (how silver could be detected)    /sc probe chat - the same for say, yell, party and raid chat and a summons arriving (can what Zennit says be read?); /sc probe chat copy opens what it printed" },
    "/sc report [copy] - what the log says about how the race is being played (for a playtest); copy opens it in a window you can copy from",
    "/sc rules [copy] - the rules of the race, with this week's live numbers; copy opens them in a window you can copy from",
    "/sc seasons - the Index's keepsake of each finished season (who was there, the silver, the moments)",
    { "zennit", "/sc respond - Zennit answers a summon of him (accept, decline, ask for silver, dice)" },
    { "admin", "/sc respond test - try the answer form on a test summons" },
    "/sc tips [on|off] - the one-line tip about a command, at the Monday login",
    "/sc feelings [on|off] - the weekly one-click question about how the week felt (Zennit and the admin see the counts)",
    "/sc errors [clear] - problems the addon caught in itself this session (tell Aaron what they say)",
    { "admin", "/sc gag - preview the Zennit gag" },
    { "admin", "/sc comic [256|512|1024|2048] - large-image test pattern viewer" },
    "/sc undo - remove the latest summon",
    { "admin", "/sc debug - toggle detector messages" },
}

-- Debug and test tools are for the admin's account only, and so is anything that gives the gags away: the live
-- checklist's steps, the voice clips, and the BattleTag report (it names Zennit's account).
for _, name in ipairs({ "test", "fake", "fakeprompt", "comic", "synctest", "debug", "gag", "check", "clip", "admin" }) do
    local run = commands[name]
    commands[name] = function(...)
        if not ST.IsAdmin() then return print_("that is an admin tool") end
        return run(...)
    end
end

SLASH_SUMMONCORE1 = "/sc"
SLASH_SUMMONCORE2 = "/summoncore"
SlashCmdList["SUMMONCORE"] = function(input)
    local cmd, rest = (input or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "" then
        ST.Guard("the window", ST.Hub.Toggle) -- no arguments: the window with everything in it
    elseif commands[cmd] then
        ST.Guard("/sc " .. cmd, commands[cmd], rest)
    else
        if cmd ~= "" and cmd ~= "help" then print_("unknown command '" .. cmd .. "'") end
        print_("v" .. ST.version)
        local all = cmd == "help" and rest:lower() == "all"
        local admin = ST.IsAdmin()
        local zennit = admin or ST.IsZennitAccount()
        for _, l in ipairs(all and HELP or HELP_SHORT) do
            if type(l) == "string" then print_(l)
            elseif (l[1] == "admin" and admin) or (l[1] == "zennit" and zennit) then print_(l[2]) end
        end
    end
end
