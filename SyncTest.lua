-- /sc synctest: exercises Sync encoding, merge rules and the HELLO/REQUEST/BATCH exchange with
-- fake events and simulated clients. Real data is never touched: each client gets a scratch DB.
local ADDON, ST = ...
local Sync, Store = ST.Sync, ST.Store
local T = {}
ST.SyncTest = T

local BASE = 1717000000
local clock = 1000
local realEventClosed, realLateAnswer -- set in T.Run (Week.lua loads after this file)

local function newClient(name)
    return {
        name = name, out = {}, state = Sync.newState(),
        db = { version = 1, events = {}, badges = {}, settings = {}, harness = {} },
    }
end

-- Runs fn with the addon globals pointed at client c, then restores them.
local function with(c, fn)
    local saved = {
        db = ST.db, state = Sync.state, name = Sync.nameOverride, transport = Sync.transport,
        channels = Sync.channels, quiet = Sync.quiet, now = Sync.now, onAdd = Store.onAdd, onRemove = Store.onRemove,
    }
    ST.db, Sync.state, Sync.nameOverride, Sync.quiet = c.db, c.state, c.name, true
    Sync.transport = function(channel, target, payload)
        c.out[#c.out + 1] = { channel = channel, target = target, payload = payload }
    end
    Sync.channels = function() return { "PARTY" } end
    Sync.now = function() return clock end
    Store.onAdd = function(id, ev) Sync.BroadcastEvent(id, ev) end
    Store.onRemove = function(id) Sync.SendTombstone(id) end
    local ok, a, b = pcall(fn)
    ST.db, Sync.state, Sync.nameOverride, Sync.transport = saved.db, saved.state, saved.name, saved.transport
    Sync.channels, Sync.quiet, Sync.now, Store.onAdd = saved.channels, saved.quiet, saved.now, saved.onAdd
    Store.onRemove = saved.onRemove
    if not ok then error(a, 0) end
    return a, b
end

-- Adds a confirmed summon cast by c. localOnly keeps it off the simulated network.
local function cast(c, i, localOnly, over)
    local ev = {
        caster = c.name, target = "Target" .. i, assistants = { "H1", "H2" }, mapID = 1436,
        subzone = "Sentinel Hill", time = BASE + i, confirmed = true,
    }
    for k, v in pairs(over or {}) do ev[k] = v end
    return with(c, function() return (Store.Add(ev, localOnly)) end)
end

-- Delivers queued messages between clients until the network is quiet.
local function settle(clients)
    local counts, rounds = { H = 0, E = 0, R = 0, B = 0 }, 0
    repeat
        local moved = 0
        for _, c in ipairs(clients) do with(c, function() Sync.Pump(100000) end) end
        for _, c in ipairs(clients) do
            local out = c.out
            c.out = {}
            for _, m in ipairs(out) do
                moved = moved + 1
                local typ = m.payload:match("^%d+~(%a)~")
                counts[typ] = (counts[typ] or 0) + 1
                for _, r in ipairs(clients) do
                    if r ~= c and (m.channel ~= "WHISPER" or m.target == r.name) then
                        with(r, function() Sync.OnMessage(m.payload, m.channel, c.name) end)
                    end
                end
            end
        end
        rounds = rounds + 1
    until moved == 0 or rounds > 40
    return counts, rounds
end

local function signature(c)
    local parts = {}
    for id, ev in pairs(c.db.events) do parts[#parts + 1] = Sync.Encode(id, ev) end
    table.sort(parts)
    return table.concat(parts, "\n"), #parts
end

local function sample(over)
    local ev = {
        caster = "Beta", target = "Tgt", assistants = { "A", "B" }, mapID = 1436, subzone = "Sentinel Hill",
        time = BASE + 100, wrote = BASE + 200, confirmed = true,
    }
    for k, v in pairs(over or {}) do ev[k] = v end
    return "Beta-" .. ev.time, ev
end

local function mutate(record, idx, value)
    local f = {}
    for part in (record .. "|"):gmatch("([^|]*)|") do f[#f + 1] = part end
    f[idx] = value
    return table.concat(f, "|")
end

local tests = {}
local function add(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

add("encode/decode round trip with awkward characters", function()
    local id, ev = sample({ target = "We|ird,%~x", assistants = { "A%b", "C,d" }, subzone = "Sub,Zone|x" })
    local rid, out = Sync.Decode(Sync.Encode(id, ev))
    if not rid then return false, "decode failed: " .. tostring(out) end
    local same = rid == id and out.target == ev.target and out.subzone == ev.subzone and out.assistants[1] == "A%b"
        and out.assistants[2] == "C,d" and out.time == ev.time and out.wrote == ev.wrote and out.confirmed == true
        and out.mapID == 1436
    return same, same and "" or "fields differ after round trip"
end)

add("typical record fits one addon message", function()
    local id, ev = sample({ caster = "Charactername", target = "Anothername", assistants = { "Helperone", "Helpertwo" },
        subzone = string.rep("s", 40) })
    id = "Charactername-" .. ev.time
    local len = #("1~B~" .. Sync.Encode(id, ev))
    return len <= 250, len .. " bytes"
end)

add("malformed records are rejected", function()
    local id, ev = sample()
    local rec = Sync.Encode(id, ev)
    local cases = {
        { rec .. "|x|y|z", "fields" },
        { rec .. "|w|Bob", "by" },                                       -- only the summoned may file a record for someone else
        { mutate(rec, 7, "abc"), "time" },
        { mutate(rec, 7, tostring(time() + 10 * 86400)), "future" },
        { mutate(rec, 1, "Other-1717000100"), "id" },
        { mutate(rec, 2, string.rep("x", 30)), "name" },
        { mutate(rec, 5, "12x"), "map" },
        { mutate(rec, 8, "2"), "confirmed" },
        { mutate(rec, 4, "A,B,C"), "assistants" },
    }
    for _, c in ipairs(cases) do
        local ok, reason = Sync.Decode(c[1])
        if ok or reason ~= c[2] then return false, string.format("expected '%s', got %s", c[2], tostring(reason or "accepted")) end
    end
    return true, #cases .. " cases"
end)

add("newer protocol, garbage and own echoes are ignored", function()
    local a = newClient("Alpha")
    local r1 = with(a, function() return Sync.OnMessage("2~H~1|1|x", "GUILD", "Beta") end)
    local r2 = with(a, function() return Sync.OnMessage("garbage", "GUILD", "Beta") end)
    local r3 = with(a, function() return Sync.OnMessage("1~H~0|0|x", "GUILD", "Alpha") end)
    return r1 == "ignored:version" and r2 == "bad" and r3 == "ignored:self", r1 .. ", " .. r2 .. ", " .. r3
end)

add("new event added once; repeating adds nothing", function()
    local a = newClient("Alpha")
    local id, ev = sample()
    local r1 = with(a, function() return Sync.Merge(id, ev, "Beta", false) end)
    local _, ev2 = sample()
    local r2 = with(a, function() return Sync.Merge(id, ev2, "Beta", false) end)
    local _, n = signature(a)
    return r1 == "added" and r2 == "kept" and n == 1, r1 .. ", " .. r2 .. ", count " .. n
end)

add("points are recomputed locally, never trusted", function()
    local a = newClient("Alpha")
    local id, ev = sample({ mapID = 1453 }) -- Stormwind: a city
    ev.points, ev.kind = 999, "remote"
    with(a, function() Sync.Merge(id, ev, "Beta", false) end)
    local got = a.db.events[id]
    return got.points == 1 and got.kind == "city", "points=" .. tostring(got.points) .. " kind=" .. tostring(got.kind)
end)

add("live EVENT must come from its own caster", function()
    local a = newClient("Alpha")
    local id, ev = sample()
    local r = with(a, function() return Sync.OnMessage("1~E~" .. Sync.Encode(id, ev), "PARTY", "Gamma") end)
    local _, n = signature(a)
    return r == "rejected:sender" and n == 0, r
end)

add("nobody can forge entries against the receiver", function()
    local a = newClient("Alpha")
    local fid, fev = sample({ caster = "Alpha", target = "Fake" })
    fid = "Alpha-" .. fev.time
    local r1 = with(a, function() return Sync.Merge(fid, fev, "Beta", false) end)
    cast(a, 100, true, { target = "Real" })
    local realID = "Alpha-" .. (BASE + 100)
    local _, f2 = sample({ caster = "Alpha", target = "Fake", time = BASE + 100, wrote = 1 })
    local r2 = with(a, function() return Sync.Merge(realID, f2, "Beta", false) end)
    local ok = r1 == "rejected:self" and r2 == "kept" and a.db.events[realID].target == "Real"
    return ok, r1 .. ", " .. r2 .. ", target=" .. a.db.events[realID].target
end)

add("confirmed beats unconfirmed; earlier write wins a tie", function()
    local a = newClient("Alpha")
    local id, base = sample({ confirmed = false, wrote = 500 })
    with(a, function() Sync.Merge(id, base, "Beta", false) end)
    local steps = {
        { { confirmed = true, wrote = 600 }, "replaced", true },
        { { confirmed = false, wrote = 100 }, "kept", true },
        { { confirmed = true, wrote = 400 }, "replaced", true },
        { { confirmed = true, wrote = 700 }, "kept", true },
    }
    for i, s in ipairs(steps) do
        local _, ev = sample(s[1])
        local r = with(a, function() return Sync.Merge(id, ev, "Beta", false) end)
        if r ~= s[2] or a.db.events[id].confirmed ~= s[3] then return false, "step " .. i .. " gave " .. r end
    end
    return a.db.events[id].wrote == 400, "final wrote=" .. a.db.events[id].wrote
end)

add("unsolicited or non-whisper BATCH is refused", function()
    local a = newClient("Alpha")
    local id, ev = sample()
    local msg = "1~B~" .. Sync.Encode(id, ev)
    local r1 = with(a, function() return Sync.OnMessage(msg, "WHISPER", "Beta") end)
    a.state.requested["Beta"] = clock
    local r2 = with(a, function() return Sync.OnMessage(msg, "PARTY", "Beta") end)
    local r3 = with(a, function() return Sync.OnMessage(msg, "WHISPER", "Beta") end)
    return r1 == "rejected:unrequested" and r2 == "rejected:channel" and r3 == "added", r1 .. ", " .. r2 .. ", " .. r3
end)

add("REQUEST is rate limited per sender", function()
    local b = newClient("Beta")
    cast(b, 1, true)
    local r1 = with(b, function() return Sync.OnMessage("1~R~0", "WHISPER", "Alpha") end)
    local r2 = with(b, function() return Sync.OnMessage("1~R~0", "WHISPER", "Alpha") end)
    clock = clock + 11
    local r3 = with(b, function() return Sync.OnMessage("1~R~0", "WHISPER", "Alpha") end)
    return r1 == "batch:1" and r2 == "ignored:ratelimit" and r3 == "batch:1", r1 .. ", " .. r2 .. ", " .. r3
end)

add("a new summon broadcasts live and lands on the other client", function()
    local a, b = newClient("Alpha"), newClient("Beta")
    local id = cast(a, 1, false)
    local counts = settle({ a, b })
    local got = b.db.events[id]
    return got ~= nil and counts.E >= 1 and got.points == a.db.events[id].points,
        "E messages: " .. counts.E .. ", arrived: " .. tostring(got ~= nil)
end)

add("three clients with different logs converge, then stay quiet", function()
    local a, b, g = newClient("Alpha"), newClient("Beta"), newClient("Gamma")
    for i = 1, 3 do cast(a, i, true) end
    for i = 10, 11 do cast(b, i, true) end
    clock = clock + 100
    for _, c in ipairs({ a, b, g }) do with(c, function() Sync.Hello() end) end
    local c1, rounds = settle({ a, b, g })
    local sa, na = signature(a)
    local sb, nb = signature(b)
    local sg, ng = signature(g)
    if not (sa == sb and sb == sg and na == 5) then
        return false, string.format("counts a=%d b=%d g=%d (want 5, identical)", na, nb, ng)
    end
    clock = clock + 100
    for _, c in ipairs({ a, b, g }) do with(c, function() Sync.Hello() end) end
    local c2 = settle({ a, b, g })
    local quiet = c2.E == 0 and c2.B == 0 and c2.R == 0
    return quiet, string.format("first pass: %d rounds, %d batch msgs; repeat: R=%d B=%d E=%d", rounds, c1.B, c2.R, c2.B, c2.E)
end)

add("export codec round-trips text, including a full 12-bit dictionary", function()
    local Codec = ST.Export.Codec
    local samples = { "a", "ab", "abc", string.rep("Alpha-1717000001|Target|H1,H2|1436|Sentinel Hill|", 40) }
    local rnd = {}
    for i = 1, 20000 do rnd[i] = string.char(math.random(0, 255)) end
    samples[#samples + 1] = table.concat(rnd)
    for i, s in ipairs(samples) do
        local back, err = Codec.Unpack(Codec.Pack(s))
        if back ~= s then return false, string.format("sample %d failed: %s", i, tostring(err)) end
    end
    local empty = Codec.Unpack(Codec.Pack(""))
    return empty == "", #samples .. " samples"
end)

add("export strings: damage, truncation, newer versions and stray whitespace", function()
    local Codec = ST.Export.Codec
    local good = Codec.Pack(string.rep("hello world ", 30))
    local flipped = good:sub(1, -6) .. (good:sub(-5, -5) == "A" and "B" or "A") .. good:sub(-4)
    local cases = {
        { good:sub(1, #good - 8), false }, -- truncated
        { flipped, false },                -- one character changed
        { "!ST2!1!1!AAAA", false },        -- newer version
        { "hello", false },                -- not ours
        { "", false },
        { (good:gsub("(.......)", "%1\n ")), true }, -- whitespace is ignored
    }
    for i, c in ipairs(cases) do
        local text = Codec.Unpack(c[1])
        if (text ~= nil) ~= c[2] then return false, "case " .. i .. " gave " .. tostring(text ~= nil) end
    end
    return true, #cases .. " cases"
end)

add("export all, import on a fresh client, then re-import adds nothing", function()
    local a, b = newClient("Alpha"), newClient("Beta")
    for i = 1, 3 do cast(a, i, true) end
    with(a, function()
        local id, ev = sample()
        Sync.Merge(id, ev, "Beta", false)
    end)
    local str, n = with(a, function() return ST.Export.Build("all") end)
    local p = with(b, function() return ST.Export.Preview(str) end)
    -- Beta's own event is a restore for the client named Beta, so all four are new.
    if n ~= 4 or not p or p.counts.added ~= 4 then
        return false, "preview wrong: exported " .. tostring(n) .. ", added " .. tostring(p and p.counts.added)
    end
    with(b, function() ST.Export.Apply(p) end)
    local sa, sb = signature(a), signature(b)
    local again = with(b, function() return ST.Export.Preview(str) end)
    return sa == sb and again.counts.added == 0 and again.counts.replaced == 0,
        string.format("identical=%s, repeat: added=%d known=%d", tostring(sa == sb), again.counts.added, again.counts.kept)
end)

add("import restores your own lost events but never overwrites existing ones", function()
    local a = newClient("Alpha")
    for i = 1, 2 do cast(a, i, true) end
    local mine = with(a, function() return ST.Export.Build("mine") end)
    local lost = newClient("Alpha") -- same character, empty log (SavedVariables lost)
    local p = with(lost, function() return ST.Export.Preview(mine) end)
    with(lost, function() ST.Export.Apply(p) end)
    if signature(lost) ~= signature(a) then return false, "restore did not match the original" end
    -- A tampered copy of an event you already have must not replace it.
    local id = "Alpha-" .. (BASE + 1)
    local _, fake = sample({ caster = "Alpha", target = "Fake", time = BASE + 1, wrote = 1, confirmed = true })
    local forged = ST.Export.Codec.Pack(Sync.Encode(id, fake))
    local p2 = with(lost, function() return ST.Export.Preview(forged) end)
    with(lost, function() ST.Export.Apply(p2) end)
    local target = lost.db.events[id].target
    return target == "Target1" and p2.counts.kept == 1, "target=" .. target
end)

add("import ignores points in the string and rejects bad records", function()
    local b = newClient("Beta")
    local id, ev = sample({ caster = "Gamma", time = BASE + 5, mapID = 1453 })
    id = "Gamma-" .. ev.time
    local text = Sync.Encode(id, ev) .. "~" .. "garbage|record" .. "~" .. Sync.Encode("Other-1", ev)
    local p = with(b, function() return ST.Export.Preview(ST.Export.Codec.Pack(text)) end)
    with(b, function() ST.Export.Apply(p) end)
    local got = b.db.events[id]
    return p.counts.added == 1 and p.counts.rejected == 2 and got and got.points == 1,
        string.format("added=%d rejected=%d points=%s", p.counts.added, p.counts.rejected, tostring(got and got.points))
end)

add("voice clips: names parse, categories count, picks do not repeat", function()
    local Clips = ST.Clips
    local c, n, who = Clips.Parse("zenit_refuse_03_sam")
    if c ~= "zenit_refuse" or n ~= 3 or who ~= "sam" then return false, "parse gave " .. tostring(c) end
    if Clips.Parse("narrator_weekopen_01_lewis") ~= "narrator_weekopen" then return false, "multi-word category" end
    if Clips.Parse("notaclip") or Clips.Parse("_01_x") or Clips.Parse("wag_x_y") then return false, "bad names parsed" end
    Clips.SetList({ "wag_02_b", "wag_01_a", "ritual_01_c", "bad name" })
    local cats = Clips.Categories()
    local counted = #cats == 2 and cats[1][1] == "ritual" and cats[2][1] == "wag" and cats[2][2] == 2
    local repeated, prev = false, nil
    for _ = 1, 60 do
        local p = Clips.Pick("wag")
        if p == prev then repeated = true end
        prev = p
    end
    local missing = Clips.Pick("nothing") == nil
    Clips.SetList(ST.clipFiles) -- restore the real list
    return counted and not repeated and missing, string.format("counted=%s repeated=%s", tostring(counted), tostring(repeated))
end)

add("Zennit hears a recorded complaint when summoned live, not from history", function()
    local z = newClient("Zennit")
    z.db.settings.zenitTest = true
    local calls = {}
    local realPlay, realIncoming = ST.Clips.Play, ST.Respond.Incoming
    ST.Clips.Play = function(category) calls[#calls + 1] = category end
    ST.Respond.Incoming = function() end -- the simulated client's summons is not in the real log: the real form would open and could not be answered
    local ok, err = pcall(function()
        local function record(target, i)
            local id, ev = sample({ caster = "Alpha", target = target, time = BASE + i })
            return "Alpha-" .. ev.time, ev
        end
        local id, ev = record("Zennit", 300)
        with(z, function() Sync.OnMessage("1~E~" .. Sync.Encode(id, ev), "PARTY", "Alpha") end)       -- live: yes
        id, ev = record("Zennit", 301)
        z.state.requested["Alpha"] = clock
        with(z, function() Sync.OnMessage("1~B~" .. Sync.Encode(id, ev), "WHISPER", "Alpha") end)     -- history: no
        id, ev = record("Someone", 302)
        with(z, function() Sync.OnMessage("1~E~" .. Sync.Encode(id, ev), "PARTY", "Alpha") end)       -- someone else: no
    end)
    ST.Clips.Play, ST.Respond.Incoming = realPlay, realIncoming
    if not ok then return false, tostring(err) end
    return #calls == 1 and calls[1] == "zenit_land", #calls .. " clip call(s)"
end)

add("intro key phrases: shown at the right time, typed out, and every cue falls inside its scene", function()
    local I = ST.Intro
    local cues = { { t = 1, text = "ONE" }, { t = 3, text = "TWO" } }
    local before = I.CueAt(cues, 0.5)
    local first, firstElapsed = I.CueAt(cues, 1.5)
    local stillFirst = I.CueAt(cues, 2.9)
    local second = I.CueAt(cues, 3.1)
    local expired = I.CueAt({ { t = 1, text = "X" } }, 6)
    local none = I.CueAt(nil, 1)
    if before or first ~= 1 or stillFirst ~= 1 or second ~= 2 or expired or none then
        return false, "cue lookup is wrong"
    end
    if math.abs(firstElapsed - 0.5) > 1e-6 then return false, "elapsed time is wrong" end
    if I.Typed("HELLO", 0) ~= "H" or I.Typed("HELLO", 0.1) ~= "HEL" or I.Typed("HELLO", 10) ~= "HELLO" then
        return false, "typing is wrong"
    end
    local bad = {}
    for si, list in pairs(ST.introCues or {}) do
        local length = ST.introLength and ST.introLength[si]
        local prev = -1
        for _, c in ipairs(list) do
            if c.t <= prev or (length and c.t >= length) or #c.text == 0 then bad[#bad + 1] = si .. ":" .. tostring(c.text) end
            prev = c.t
        end
    end
    return #bad == 0, #bad == 0 and "all generated cues are ordered and inside their scenes" or table.concat(bad, ", ")
end)

add("senders shown as 'Name Surname' or 'Name-Realm' are matched by their plain name", function()
    local a = newClient("Alpha")
    local id, ev = sample({ caster = "Beta", time = BASE + 400 })
    id = "Beta-" .. ev.time
    local r1 = with(a, function() return Sync.OnMessage("1~E~" .. Sync.Encode(id, ev), "PARTY", "Beta Mcbane") end)
    local id2, ev2 = sample({ caster = "Gamma", time = BASE + 401 })
    id2 = "Gamma-" .. ev2.time
    local r2 = with(a, function() return Sync.OnMessage("1~E~" .. Sync.Encode(id2, ev2), "GUILD", "Gamma-SomeRealm") end)
    local r3 = with(a, function() return Sync.OnMessage("1~H~0|0|x", "GUILD", "Alpha Zennit") end) -- our own echo
    return r1 == "added" and r2 == "added" and r3 == "ignored:self", r1 .. ", " .. r2 .. ", " .. r3
end)

add("plain names: first word only, nothing for unusable values", function()
    local b = ST.baseName
    local ok = b("Poogs Mcbane") == "Poogs" and b("Club-Zennit") == "Club" and b("Solo") == "Solo"
        and b("") == nil and b(nil) == nil and b(42) == nil and b(" x") == nil
    return ok, "Poogs Mcbane -> " .. tostring(b("Poogs Mcbane"))
end)

add("intro subtitles: the sentence being spoken, and the generated times are ordered", function()
    local I = ST.Intro
    local _, idx, since, span = I.SentenceAt({ { t = 1, text = "a" }, { t = 4, text = "b" } }, 2, 9)
    local _, lastIdx, _, lastSpan = I.SentenceAt({ { t = 1, text = "a" }, { t = 4, text = "b" } }, 5, 9)
    if idx ~= 1 or math.abs(since - 1) > 1e-6 or span ~= 3 or lastIdx ~= 2 or lastSpan ~= 5 then
        return false, "sentence index or span is wrong"
    end
    local fast, slow = I.SentenceSpeed(100, 5), I.SentenceSpeed(100, 20)
    if not (fast > slow) or I.SentenceSpeed(50, nil) ~= 26 or I.SentenceSpeed(1, 100) < 8 then
        return false, "typing speed is wrong"
    end
    local list = { { t = 0.4, text = "first" }, { t = 10, text = "second" } }
    if I.SentenceAt(list, 0) ~= nil or I.SentenceAt(list, 5) ~= "first" or I.SentenceAt(list, 10) ~= "second"
        or I.SentenceAt(list, 99) ~= "second" or I.SentenceAt(nil, 1) ~= nil then
        return false, "sentence lookup is wrong"
    end
    local bad = {}
    for si, sentences in pairs(ST.introSentences or {}) do
        local prev = -1
        for _, s in ipairs(sentences) do
            if s.t <= prev or #s.text == 0 then bad[#bad + 1] = si end
            prev = s.t
        end
    end
    return #bad == 0, #bad == 0 and "generated sentence times are ordered" or ("scenes " .. table.concat(bad, ","))
end)

add("hub window: builds and every tab refreshes without errors", function()
    local ok, err = ST.Hub.SelfCheck()
    return ok, ok and "every tab refreshed" or tostring(err)
end)

add("tour: every step has a line and a recording, every outline finds its part of the window, each side gets its own", function()
    local bad = {}
    local party, zennit = ST.Tour.Steps(false), ST.Tour.Steps(true)
    for _, list in ipairs({ party, zennit }) do
        for i, s in ipairs(list) do
            if not ST.Tour.LINES[s.line] then bad[#bad + 1] = i .. ": no line " .. tostring(s.line) end
            if not (ST.tourClips and ST.tourClips[s.line]) then bad[#bad + 1] = i .. ": no recording of " .. s.line end
            if s.popup then -- a game dialog: shown only while its step plays, so check it names a real one
                local which = ST.Tour.POPUPS[s.popup] and ST.Tour.POPUPS[s.popup]()
                if not (which and StaticPopupDialogs[which]) then bad[#bad + 1] = i .. ": no dialog for " .. s.popup end
            elseif s.spot and not ST.Tour.Spot(s) then bad[#bad + 1] = i .. ": nothing at " .. s.spot end
        end
    end
    local function has(list, id)
        for _, s in ipairs(list) do if s.line == id then return true end end
    end
    if not (has(party, "writ") and not has(zennit, "writ") and has(zennit, "z_zennit") and not has(party, "z_zennit")
        and has(party, "goodbye") and has(zennit, "z_goodbye") and not has(zennit, "goodbye")) then
        bad[#bad + 1] = "the two sides do not get their own lines"
    end
    return #bad == 0, #bad == 0 and string.format("%d steps for the party, %d for Zennit", #party, #zennit) or table.concat(bad, "; ")
end)

add("intro highlights: a box is up while its subject is mentioned, and the generated boxes fit the picture", function()
    local I = ST.Intro
    local list = { { t = 1, x = 0, y = 0, w = 10, h = 10 }, { t = 6, x = 5, y = 5, w = 10, h = 10 } }
    local before = I.HighlightAt(list, 0.5)
    local first = I.HighlightAt(list, 2)
    local expired = I.HighlightAt(list, 5)
    local second = I.HighlightAt(list, 6.5)
    if before or first ~= 1 or expired or second ~= 2 or I.HighlightAt(nil, 1) then
        return false, "highlight lookup is wrong"
    end
    local bad = {}
    for si, boxes in pairs(ST.introHighlights or {}) do
        local prev = -1
        for _, b in ipairs(boxes) do
            if b.t <= prev or b.w <= 0 or b.h <= 0 or b.x < 0 or b.y < 0 or b.x + b.w > 960 or b.y + b.h > 540 then
                bad[#bad + 1] = si
            end
            prev = b.t
        end
    end
    return #bad == 0, #bad == 0 and "all generated boxes are ordered and inside the picture" or ("scenes " .. table.concat(bad, ","))
end)

add("the Index today: the intro's last scene follows the season, and holds back chapters not yet reached", function()
    local L = ST.Ledger
    local function state(z, g, finales, score)
        return { wins = 5, cap = 10, immune = false, season = { zennit = z, group = g, finales = finales or {}, chapters = {} },
            score = score or { summons = 0, group = 0, zennit = 2, counted = 0, new = true } }
    end
    local function say(s)
        local all = {}
        for _, item in ipairs(L.Build(s)) do all[#all + 1] = item.text end
        return table.concat(all, " ")
    end
    local fresh, ahead, behind = say(state(0, 0)), say(state(1, 3)), say(state(3, 1))
    if not fresh:find("empty") or not ahead:find("group leads") or not behind:find("Zennit leads") then
        return false, "the standing does not follow the season"
    end
    if fresh:find("syllabus") or ahead:find("syllabus") or not behind:find("syllabus") then
        return false, "a trunk is recapped before the race reached it"
    end
    if not say(state(4, 4)):find("Both sides are one win") or not say(state(0, 4)):find("one win from the finale") then
        return false, "the last win is not flagged"
    end
    if not say(state(0, 0, { { side = "group" } })):find("receipt") then return false, "last season is not recalled" end
    local sentences, cues, length = L.Timed(L.Build(state(2, 2)))
    for i = 2, #sentences do
        if sentences[i].t <= sentences[i - 1].t then return false, "sentence times are not ordered" end
    end
    for _, c in ipairs(cues) do
        if c.t >= length then return false, "a cue falls outside the scene" end
    end
    local key = L.ArtKey({ chapters = { { key = "z1" }, { key = "g1" } } })
    return key == "g1" and L.ArtKey({ chapters = {} }) == nil, "standing, trunks, last wins and last season all follow the tree"
end)

add("the Index today: each whim has a recording that says what the whim now says, and a changed whim falls silent", function()
    local L, W = ST.Ledger, ST.Week
    local stale = {}
    for id in pairs(W.WHIMS) do
        if L.LINES["whim_" .. id] ~= "This week's whim: " .. W.WhimSentence(id) then stale[#stale + 1] = id end
        if L.WhimClip("This week's whim: " .. W.WhimSentence(id)) ~= "whim_" .. id then stale[#stale + 1] = id .. " (no clip)" end
    end
    if #stale > 0 then
        table.sort(stale)
        return false, "the recorded whim line no longer matches the rules for: " .. table.concat(stale, ", ")
            .. " (update LINES in Ledger.lua and run tools/intro/build_ledger_audio.py --stale)"
    end
    local good = L.WhimClip("This week's whim: The Index is distracted. Zennit's edge on the dice is 6 lower this week.") == nil
    return good, "a whim whose number moved must be typed and silent, not read out wrongly"
end)

add("the Index today: spliced lines show what they say, from recordings that all exist, and last as long as they play", function()
    local L = ST.Ledger
    local function has(id) return ST.ledgerClips and ST.ledgerClips[id] end
    -- every phrase and every number from 0 to 99, in both endings, has a recording
    local missing = {}
    for id in pairs(L.FRAGMENTS) do if not has(id) then missing[#missing + 1] = id end end
    for n = 0, 99 do
        for _, final in ipairs({ true, false }) do
            for _, id in ipairs(L.NumberClips(n, final)) do if not has(id) then missing[#missing + 1] = id end end
        end
    end
    if #missing > 0 then
        table.sort(missing)
        return false, "no recording for " .. table.concat(missing, ", ", 1, math.min(#missing, 8)) .. " (run tools/intro/build_ledger_audio.py)"
    end
    -- the text is built from the same parts as the clips, and reads as the lines always did
    local function splice(parts) local text, clips = L.Splice(parts) return text, clips and table.concat(clips, ",") or nil end
    local cases = {
        { { "group_leads_season", 3, "to", 2, "." }, "The group leads the season, 3 to 2.", "group_leads_season,n3c,to,n2f" },
        { { "zennit_leads_season", 3, "to", 1, ",", "nobody_expected" }, "Zennit leads the season, 3 to 1, which nobody expected, least of all Zennit.",
            "zennit_leads_season,n3c,to,n1c,nobody_expected" },
        { { "level_at", 2, "weeks_each", "|", "not_taking_sides" }, "The season stands level at 2 weeks each. The Index would like it noted that it is not taking sides.",
            "level_at,n2c,weeks_each,_,not_taking_sides" },
        { { "level_at", 1, "week_each", "|", "not_taking_sides" }, "The season stands level at 1 week each. The Index would like it noted that it is not taking sides.",
            "level_at,n1c,week_each,_,not_taking_sides" },
        { { "this_week", 6, "of", 10, "summons_filed_and", "group_leads_by", 3, "." }, "This week, 6 of 10 summons are filed, and the group leads by 3.",
            "this_week,n6c,of,n10c,summons_filed_and,group_leads_by,n3f" },
        { { "this_week", 6, "of", 10, "summons_filed_and", "level_tie" }, "This week, 6 of 10 summons are filed, and it is level, and a tie is Zennit's.",
            "this_week,n6c,of,n10c,summons_filed_and,level_tie" },
        { { "week_group_has", 14, "points_to", 21, "." }, "This week, the group has 14 points to Zennit's 21.", "week_group_has,n14c,points_to,t20m,n1f" },
        { { "edge_group_behind", 5, "off_dice" }, "The Index, which takes no sides, has noticed that the group is behind, and has taken 5 off Zennit's dice this week.",
            "edge_group_behind,n5c,off_dice" },
        { { "edge_zennit_behind", 30, "on_dice" }, "The Index, which takes no sides, has noticed that Zennit is behind, and has put 30 on his dice this week.",
            "edge_zennit_behind,t30c,on_dice" },
        { { "week_group_has", 40, "points_to", 99, "." }, "This week, the group has 40 points to Zennit's 99.", "week_group_has,t40c,points_to,t90m,n9f" },
        { { "week_group_has", 100, "points_to", 7, "." }, "This week, the group has 100 points to Zennit's 7.", nil }, -- beyond 99: shown, not said
    }
    for _, c in ipairs(cases) do
        local text, clips = splice(c[1])
        if text ~= c[2] or clips ~= c[3] then return false, string.format("%q gave %q [%s]", c[2], text, tostring(clips)) end
    end
    -- the scene builds them: the level standing, and the week in both forms
    local function item(state, cue)
        for _, it in ipairs(L.Build(state)) do if it.cue == cue then return it end end
    end
    local function state(z, g, score)
        return { wins = 5, cap = 10, immune = false, season = { zennit = z, group = g, finales = {}, chapters = {} }, score = score }
    end
    local zero = { summons = 0, group = 0, zennit = 0, counted = 0, new = true }
    local level = item(state(2, 2, zero), "LEVEL AT 2")
    if not (level and table.concat(level.clips or {}, ",") == "level_at,n2c,weeks_each,_,not_taking_sides" and not level.clip) then
        return false, "the level standing should be spliced from clips"
    end
    local week = item(state(1, 0, { summons = 6, group = 9, zennit = 6, counted = 6, new = true }), "THIS WEEK: THE GROUP LEADS BY 3")
    if not (week and week.text == "This week, 6 of 10 summons are filed, and the group leads by 3."
        and table.concat(week.clips or {}, ",") == "this_week,n6c,of,n10c,summons_filed_and,group_leads_by,n3f") then
        return false, "the week line should be spliced: " .. tostring(week and week.text)
    end
    local points = item(state(1, 0, { summons = 6, group = 9, zennit = 12, counted = 6, new = false }), "THIS WEEK: ZENNIT LEADS BY 3")
    if not (points and points.text == "This week, the group has 9 points to Zennit's 12." and points.clips) then
        return false, "the points line should be spliced: " .. tostring(points and points.text)
    end
    -- a spliced line lasts as long as its recordings one after another; one without a known length is only typed
    local expect = 0
    for _, id in ipairs(level.clips) do expect = expect + L.ClipDelay(id) end
    local sentences = L.Timed({ level, { text = "Poogs has summoned Zennit 4 times." } })
    if math.abs(sentences[2].t - expect) > 0.001 or not sentences[1].clips then return false, "a spliced line should last the sum of its clips" end
    local unknown = L.Timed({ { text = "x", clips = { "n3c", "no_such_clip" } } })
    if unknown[1].clips ~= nil then return false, "a line with a missing recording must not be played half-said" end
    return true, "spliced lines match their text, every number 0-99 and phrase is recorded, and the lengths add up"
end)

add("the Index today: every fixed line has a recorded clip, and a clip sets how long its line lasts", function()
    local L = ST.Ledger
    local missing = {}
    for id in pairs(L.LINES) do
        if not (ST.ledgerClips and ST.ledgerClips[id]) then missing[#missing + 1] = id end
    end
    if #missing > 0 then
        table.sort(missing)
        return false, "no clip length for " .. table.concat(missing, ", ") .. " (run tools/intro/build_ledger_audio.py)"
    end
    local list = { { text = L.LINES.wait, clip = "wait" }, { text = "Poogs has summoned Zennit 4 times." } }
    local sentences = L.Timed(list)
    if sentences[1].clip ~= "wait" or sentences[2].clip ~= nil then return false, "only the fixed line should carry a clip" end
    if math.abs(sentences[2].t - ST.ledgerClips.wait) > 0.001 then return false, "a clip should set its line's length" end
    -- every fixed line the scene can say for this season is tagged with the clip that records it
    local function state(z, g, finales, score)
        return { wins = 5, cap = 10, immune = false, season = { zennit = z, group = g, finales = finales or {}, chapters = {} },
            score = score or { summons = 0, group = 0, zennit = 2, counted = 0, new = true } }
    end
    for _, s in ipairs({ state(0, 0), state(4, 4, { { side = "zennit" } }), state(0, 4), state(3, 1) }) do
        for _, item in ipairs(L.Build(s)) do
            if item.clip and L.LINES[item.clip] ~= item.text then return false, "clip " .. item.clip .. " does not match its line" end
        end
    end
    return true, "all fixed lines are recorded"
end)

add("Zennit's answer rides on the record; malformed answers are rejected", function()
    local id, ev = sample({ target = "Zennit", response = { result = "won", zroll = 64, sroll = 31, time = BASE + 300 } })
    local rid, back = Sync.Decode(Sync.Encode(id, ev))
    local r = back and back.response
    if not (rid == id and r and r.result == "won" and r.zroll == 64 and r.sroll == 31 and r.time == BASE + 300) then
        return false, "answer lost in the round trip"
    end
    local rec = Sync.Encode(id, ev)
    for _, bad in ipairs({ "nonsense:1:2:3", "won:101:2:5", "dance:1:2:5", "won:1:2" }) do
        local ok, reason = Sync.Decode(mutate(rec, 10, bad))
        if ok or reason ~= "response" then return false, bad .. " gave " .. tostring(reason or "accepted") end
    end
    local plainID, plain = sample()
    local _, noAnswer = Sync.Decode(Sync.Encode(plainID, plain))
    return noAnswer ~= nil and noAnswer.response == nil, "4 bad answers refused; no answer stays no answer"
end)

add("points only count for summons that land", function()
    local a = newClient("Alpha")
    local results = { "accepted", "refused", "owed", "paid", "won", "lost" }
    for i, res in ipairs(results) do
        cast(a, 700 + i, true, { target = "Zennit", response = { result = res, zroll = 40, sroll = 10, time = BASE + 5 } })
    end
    cast(a, 800, true, { target = "Zennit" }) -- no answer yet: counts
    local tally, stats
    with(a, function()
        tally = ST.Store.Tallies().Alpha
        stats = ST.Store.Stats("Alpha")
    end)
    -- accepted, owed (the silver goes on a tab), paid, lost and the unanswered one land: 5 summons x 3 points
    return tally.cast == 7 and tally.points == 15 and stats.cast == 5,
        string.format("cast=%d points=%d landed=%d", tally.cast, tally.points, stats.cast)
end)

add("a refusal costs Zennit the points unless the place is on his list", function()
    local a = newClient("Alpha")
    local plain = cast(a, 950, true, { target = "Zennit", response = { result = "refused", zroll = 0, sroll = 0, time = BASE + 5 } })
    local free = cast(a, 951, true, { target = "Zennit", response = { result = "excused", zroll = 0, sroll = 0, time = BASE + 5 } })
    local won = cast(a, 952, true, { target = "Zennit", response = { result = "won", zroll = 80, sroll = 20, time = BASE + 5 } })
    local listed = cast(a, 953, true, { target = "Zennit", response = { result = "accepted", zroll = 0, sroll = 0, time = BASE + 5, listed = true } })
    -- the listed flag survives the wire format
    local back = select(2, Sync.Decode(Sync.Encode(listed, a.db.events[listed])))
    if not (back and back.response and back.response.listed) then return false, "listed flag lost in the codec" end
    local onList, offList, tally
    with(a, function()
        ST.Respond.ListClear()
        ST.Respond.ListAdd("Stormwind")
        onList = ST.Respond.OnList({ subzone = "Trade District", mapID = 1453 }) -- zone name needs the client's map data
        offList = ST.Respond.OnList({ subzone = "Mudsprocket", mapID = 0 })
        ST.Respond.ListClear()
        tally = ST.Store.Tallies().Zennit
    end)
    local pts = a.db.events[plain].points
    -- refused -P, excused 0, dice won +P, accepted at a listed place +P
    local want = -pts + pts + pts
    return offList == false and onList ~= nil and tally.points == want and not Store.Lands(a.db.events[free])
        and won ~= nil, string.format("Zennit points=%d (expected %d), off-list=%s", tally.points, want, tostring(offList))
end)

add("the secret list box suggests known places, sorted, without the ones already on the list", function()
    local a = newClient("Alpha")
    cast(a, 960, true, { target = "Zennit", subzone = "Mudsprocket" })
    local got
    with(a, function()
        ST.Respond.ListClear()
        ST.Respond.ListAdd("Silithus")
        got = ST.Respond.ListSuggestions()
        ST.Respond.ListClear()
    end)
    local has, problems = {}, {}
    for i, name in ipairs(got) do
        local key = name:lower()
        if has[key] then problems[#problems + 1] = "twice: " .. name end
        if #name < ST.Respond.LIST_MIN then problems[#problems + 1] = "too short: " .. name end
        if i > 1 and got[i - 1]:lower() > key then problems[#problems + 1] = "out of order: " .. name end
        has[key] = true
    end
    for _, want in ipairs({ "stormwind city", "winterspring", "wailing caverns", "the temple of atal'hakkar", "mudsprocket" }) do
        if not has[want] then problems[#problems + 1] = "missing: " .. want end
    end
    if has["silithus"] then problems[#problems + 1] = "suggests Silithus, already on the list" end
    return #problems == 0, #problems == 0 and string.format("%d places", #got) or table.concat(problems, "; ")
end)

add("the week: Zennit's head start wins small weeks, the group needs more, and a win is a week off", function()
    local a = newClient("Alpha")
    local W = ST.Week
    local out
    with(a, function()
        local last = W.Start() - 7 * 86400
        local function put(n, pts, extra)
            local ev = { caster = "Alpha", target = "Zennit", assistants = {}, time = last + 3600 * n, points = pts, kind = "zone" }
            for k, v in pairs(extra or {}) do ev[k] = v end
            a.db.events["w-" .. n] = ev
        end
        put(1, 3)
        local small = W.Score(last)
        for n = 2, 5 do put(n, 3) end
        local big = W.Score(last)
        a.db.events["w-5"].response = { result = "won", zroll = 80, sroll = 10, time = last + 20000 } -- he won a roll: -3 group, +3 him
        local rolled = W.Score(last)
        local immune = W.Immune(time())
        out = { small = small, big = big, rolled = rolled, immune = immune }
    end)
    local s, b, r = out.small, out.big, out.rolled
    return s.winner == "zennit" and b.group == 15 and b.winner == "group" and r.winner == "zennit" and out.immune == true
        and W.Start(W.Start() + 1) == W.Start(), string.format("small=%s big=%s/%d-%d rolled=%s", s.winner, b.winner, b.group, b.zennit, r.winner)
end)

add("the season: first to five weekly wins takes the finale, then the count starts again", function()
    local a = newClient("Alpha")
    local season
    with(a, function()
        local this = ST.Week.Start()
        -- seven finished weeks, oldest first: five Zennit wins (3 points loses to his 10 head start), a group win
        -- (20 points), then another Zennit win
        local points = { 3, 3, 3, 3, 3, 20, 3 }
        for i, pts in ipairs(points) do
            a.db.events["s-" .. i] = { caster = "Alpha", target = "Target1", assistants = {}, points = pts, kind = "zone",
                time = this - (8 - i) * 7 * 86400 + 3600 }
        end
        season = ST.Week.Season()
    end)
    local c = season.chapters
    return #c == 7 and c[5].key == "z5" and c[6].key == "2g1" and c[7].key == "2z1" and #season.finales == 1
        and season.finales[1].side == "zennit" and season.zennit == 1 and season.group == 1 and season.number == 2,
        string.format("%d chapters, %d finale(s), season %d: z%d g%d", #c, #season.finales, season.number, season.zennit, season.group)
end)

add("season two: a finale opens the next season with its own chapters, and a restart by the admin is the same season", function()
    local a = newClient("Alpha")
    local I, L, out = ST.Intro, ST.Ledger, {}
    local realAdmin, realPrint = ST.IsAdmin, ST.print
    local printed = {}
    ST.IsAdmin = function() return false end
    ST.print = function(text) printed[#printed + 1] = text end
    local ok, err = pcall(function()
        with(a, function()
            local W, this = ST.Week, ST.Week.Start()
            -- nine finished weeks: Zennit takes season one 5 to 0, then the group, Zennit, the group, the group in season two
            local points = { 3, 3, 3, 3, 3, 20, 3, 20, 20 }
            for i, pts in ipairs(points) do
                a.db.events["s-" .. i] = { caster = "Alpha", target = "Target1", assistants = {}, points = pts, kind = "zone",
                    time = this - (10 - i) * 7 * 86400 + 3600 }
            end
            out.season = W.Season()
            out.soFar = table.concat(I.SeasonSoFar(), ",")
            out.reached = I.Reached("2a") and I.Reached("2g3") and not I.Reached("2b") and not I.Reached("2g4")
            out.title = I.ChapterTitle("2g1")
            out.art = L.ArtKey(out.season)
            local texts = {}
            for _, item in ipairs(L.Build(L.State())) do texts[#texts + 1] = item.text end
            out.today = table.concat(texts, " ")
            I.Toggle("3z1")
            out.later = printed[#printed]
            -- the admin stops and starts the season again: still season two, from 0 to 0
            W.PutMark("stop", this - 7 * 86400 + 100)
            W.PutMark("start", this + 100)
            out.restart = W.Season()
        end)
    end)
    ST.IsAdmin, ST.print = realAdmin, realPrint
    if not ok then return false, "ERROR " .. tostring(err) end
    local s, r = out.season, out.restart
    local good = s.number == 2 and #s.openings == 1 and s.openings[1].key == "2a" and s.chapters[6].season == 2
        and out.soFar == "2a,2g1,2z1,2g2,2g3" and out.reached and out.title == "season 2, chapter 3: Witnesses" and out.art == "2g3"
        and out.today:find("Last season ended with Zennit in the clerk's chair", 1, true)
        and out.today:find(L.LINES.recap_g3_2, 1, true) and not out.today:find("Ritual has handed up", 1, true)
        and out.later and out.later:find("season 3 of the story is not in this version", 1, true)
        and r.number == 2 and r.zennit == 0 and r.group == 0
    return good, string.format("season %d, so far %s, art %s, after a restart season %d", s.number, out.soFar, tostring(out.art),
        r.number)
end)

add("the admin's seasons: a stop ends the season with no finale and no week counts, a start begins again 0 to 0", function()
    local a = newClient("Alpha")
    local out = {}
    with(a, function()
        local W, this = ST.Week, ST.Week.Start()
        local function week(i) return this - (8 - i) * 7 * 86400 end
        -- seven finished weeks as above (Zennit, Zennit, Zennit, Zennit, Zennit, group, Zennit); stopped in week 3, started in week 5
        local points = { 3, 3, 3, 3, 3, 20, 3 }
        for i, pts in ipairs(points) do
            a.db.events["s-" .. i] = { caster = "Alpha", target = "Target1", assistants = {}, points = pts, kind = "zone",
                time = week(i) + 3600 }
        end
        W.PutMark("stop", week(3) + 100)
        W.PutMark("start", week(5) + 100)
        out.dupe = W.PutMark("start", week(5) + 100)
        out.bad = W.PutMark("pause", week(5) + 200)
        out.season = W.Season()
        out.paused, out.week4, out.week5 = W.Score(week(3)), W.Running(week(4)), W.Running(week(5))
        W.PutMark("stop", time())
        out.now = W.Season()
        out.thisWeek = W.Score(this)
    end)
    local s, n = out.season, out.now
    local ok = not out.dupe and not out.bad and s.running and s.zennit == 2 and s.group == 1 and #s.chapters == 5
        and #s.finales == 0 and #s.ended == 1 and s.ended[1].zennit == 2 and s.ended[1].group == 0
        and out.paused.paused and out.paused.winner == nil and out.week4 == false and out.week5 == true
        and not n.running and n.zennit == 0 and n.group == 0 and #n.ended == 2 and out.thisWeek.paused
    return ok, string.format("season z%d g%d (%s), %d chapters, %d ended; after a stop: %s, %d ended", s.zennit, s.group,
        tostring(s.running), #s.chapters, #s.ended, tostring(n.running), #n.ended)
end)

add("season marks travel: the admin's stamp is kept, another is refused, and a client that missed one catches up", function()
    local a, b, c = newClient("Alpha"), newClient("Beta"), newClient("Cara")
    local saved, savedAdmin = ST.bnGetInfo, ST.ADMIN_HASH
    local out = {}
    local ok, err = pcall(function()
        ST.ADMIN_HASH = ST.TagHash("Admin#1") -- a sample account stands in for the admin's (its tag is not in the addon)
        ST.bnGetInfo = function() return 1, "Someone#1" end
        out.refused = with(a, function() return (Sync.MarkSeason("stop")) end)
        ST.bnGetInfo = function() return 1, "Admin#1" end
        out.made = with(a, function() return (Sync.MarkSeason("stop")) end)
        settle({ a, b }) -- Cara is offline
        out.forged = with(b, function() return Sync.OnMessage("1~C~start|" .. (BASE + 9) .. "|deadbeef", "PARTY", "Mallory") end)
        out.badKind = with(b, function() return Sync.OnMessage("1~C~pause|" .. (BASE + 9) .. "|" .. ST.ADMIN_HASH, "PARTY", "Mallory") end)
        with(c, function() Sync.Hello() end) -- Cara logs in: Beta holds the mark (Alpha has gone), so Beta passes it on
        a.out = {}
        settle({ b, c })
    end)
    ST.bnGetInfo, ST.ADMIN_HASH = saved, savedAdmin
    if not ok then return false, "ERROR " .. tostring(err) end
    local function has(cl) return with(cl, function() local m = ST.Week.LastMark() return m and m.kind == "stop" end) end
    local good = out.refused == nil and out.made and has(b) and has(c) and out.forged == "rejected:stamp" and out.badKind == "bad"
        and with(b, function() return #ST.Week.Marks() end) == 1
    return good, string.format("refused %s, made %s, Beta %s, Cara %s, forged %s, bad kind %s", tostring(out.refused),
        tostring(out.made and out.made.kind), tostring(has(b)), tostring(has(c)), tostring(out.forged), tostring(out.badKind))
end)

add("whispers go to the name the game gave (Father-Realm), not the first word the addon keeps", function()
    local a = newClient("Alpha")
    cast(a, 1, true) -- Alpha holds a summon Father lacks, so it whispers him a hello back
    local out = with(a, function()
        Sync.OnMessage("1~H~0|0|0.9.0|0|0", "GUILD", "Father-Realm")
        local back
        for _, m in ipairs(a.state.queue) do if m.channel == "WHISPER" then back = m.target end end
        Sync.SendDice("x", 50, "Father") -- a later whisper by the kept name (a record's caster) finds him too
        return { back = back, dice = a.state.queue[#a.state.queue].target, stranger = Sync.Address("Nobody") }
    end)
    return out.back == "Father-Realm" and out.dice == "Father-Realm" and out.stranger == "Nobody",
        string.format("hello back to %s, dice to %s, a stranger to %s", tostring(out.back), tostring(out.dice), tostring(out.stranger))
end)

add("the party's gag: one of his recordings at random, every one reachable, never the same twice running", function()
    local G, saved, played = ST.Gag, ST.Gag.Play, {}
    G.Play = function(_, clip) played[#played + 1] = clip end
    local ok, err = pcall(function() for _ = 1, 400 do G.PlayParty() end end)
    G.Play = saved
    if not ok then return false, "ERROR " .. tostring(err) end
    local seen, n, twice = {}, 0, false
    for i, clip in ipairs(played) do
        if not seen[clip] then seen[clip], n = true, n + 1 end
        if played[i - 1] == clip then twice = true end
        if not (clip.sound:match("\\gag_party[_%d]*%.ogg$") and clip.duration >= 2.5) then return false, "a bad clip: " .. clip.sound end
    end
    return n == #G.partyClips and #G.partyClips == 13 and not twice,
        string.format("%d of %d clips played, the same twice running: %s", n, #G.partyClips, tostring(twice))
end)

add("BattleTags: the admin and Zennit's account are told apart, case and spaces ignored", function()
    return ST.TagTest()
end)

add("reset: wipes the log, refuses older events afterwards, and a request only asks", function()
    local a, b = newClient("Alpha"), newClient("Beta")
    local id1 = cast(a, 1, false)
    cast(a, 2, false)
    settle({ a, b })
    local had = 0
    for _ in pairs(b.db.events) do had = had + 1 end
    local stamp = BASE + 50
    local removed = with(b, function() return ST.Reset.Apply(stamp) end)
    local left = 0
    for _ in pairs(b.db.events) do left = left + 1 end
    local _, old = Sync.Decode(Sync.Encode(id1, a.db.events[id1]))
    local late = with(b, function() return Sync.Merge(id1, old, "Alpha", false) end)
    local asked, from, forStamp
    local realAsk = Sync.onReset
    Sync.onReset = function(sender, s) asked, from, forStamp = true, sender, s end
    local ask = with(a, function() return Sync.OnMessage("1~X~" .. (BASE + 60), "PARTY", "Beta") end)
    local stale = with(b, function() return Sync.OnMessage("1~X~" .. stamp, "PARTY", "Alpha") end)
    local bad = with(a, function() return Sync.OnMessage("1~X~soon", "PARTY", "Beta") end)
    Sync.onReset = realAsk
    local keptOwn = 0
    for _ in pairs(a.db.events) do keptOwn = keptOwn + 1 end
    return had == 2 and removed == 2 and left == 0 and late == "rejected:reset" and ask == "asked" and asked and from == "Beta"
        and forStamp == BASE + 60 and stale == "kept" and bad == "bad" and keptOwn == 2,
        string.format("had %d removed %d left %d, late=%s ask=%s stale=%s bad=%s, requester kept %d", had, removed, left, late, ask, stale, bad, keptOwn)
end)

add("only Zennit can answer for himself, and a newer answer wins", function()
    local a, z = newClient("Alpha"), newClient("Zennit")
    local id = cast(a, 900, false, { target = "Zennit" })
    settle({ a, z })
    with(z, function() ST.Respond.Decide(id, "refused") end)
    settle({ a, z })
    local first = a.db.events[id].response
    if not (first and first.result == "refused") then return false, "the refusal did not reach the summoner" end
    local landsAfterRefusal = with(a, function() return Store.Lands(a.db.events[id]) end)
    local body = id .. "|accepted|0|0|"
    local forged = with(a, function() return Sync.OnMessage("1~Z~" .. body .. (time() + 5), "PARTY", "Gamma") end)
    local old = with(a, function() return Sync.OnMessage("1~Z~" .. body .. (first.time - 100), "PARTY", "Zennit") end)
    local newer = with(a, function() return Sync.OnMessage("1~Z~" .. body .. (first.time + 100), "PARTY", "Zennit") end)
    return forged == "rejected:sender" and old == "kept" and newer == "applied" and a.db.events[id].response.result == "accepted"
        and not landsAfterRefusal, string.format("%s, %s, %s", forged, old, newer)
end)

add("a friend who missed Zennit's answer gets it from the next HELLO", function()
    local a, b, z = newClient("Alpha"), newClient("Beta"), newClient("Zennit")
    local id = cast(a, 910, false, { target = "Zennit" })
    settle({ a, b, z })
    with(z, function() ST.Respond.Decide(id, "owed") end)
    settle({ a, z }) -- Beta is offline for the broadcast
    if b.db.events[id].response then return false, "Beta should have missed the answer" end
    with(a, function() Sync.Hello() end)
    settle({ a, b, z })
    local got = b.db.events[id].response
    return got ~= nil and got.result == "owed", got and got.result or "still missing"
end)

add("a closed week comes from the log alone: no answer is made or synced into it late, and clients that synced at different times agree", function()
    local a, b = newClient("Alpha"), newClient("Beta")
    local W = ST.Week
    local fakeClosed, fakeLate = W.EventClosed, W.LateAnswer
    W.EventClosed, W.LateAnswer = realEventClosed, realLateAnswer -- the other tests use old summons, so Run turns closing off
    local ok, res = pcall(function()
        local out = {}
        -- two summons of Zennit in a week that closed long ago; only Alpha holds them so far
        local id = cast(a, 3600, true, { target = "Zennit" })
        local id2 = cast(a, 3700, true, { target = "Zennit" })
        local week = W.Start(BASE + 3600)
        out.closed = W.Closed(week)
        with(a, function()
            out.made = ST.Respond.Decide(id, "refused")                                                    -- too late to answer
            out.late = Sync.OnMessage("1~Z~" .. id .. "|accepted|0|0|" .. time(), "PARTY", "Zennit")       -- made late: refused
            out.inTime = Sync.OnMessage("1~Z~" .. id .. "|refused|0|0|" .. (BASE + 3650), "PARTY", "Zennit") -- made in time, came late
            out.owed = Sync.OnMessage("1~Z~" .. id2 .. "|owed|0|0|" .. (BASE + 3750), "PARTY", "Zennit")
            out.paid = Sync.OnMessage("1~Z~" .. id2 .. "|paid|0|0|" .. time(), "PARTY", "Zennit")         -- paying is never late
        end)
        -- Beta first hears of the refused summons from a client that kept a late answer: the late answer is dropped, and Alpha's
        -- in-time one wins when it comes
        local _, stale = Sync.Decode(Sync.Encode(id, a.db.events[id]))
        stale.response = { result = "accepted", zroll = 0, sroll = 0, time = time() }
        out.staleAdd = with(b, function() return Sync.Merge(id, stale, "Alpha", false) end)
        out.staleKept = b.db.events[id] and b.db.events[id].response
        for _, key in ipairs({ id, id2 }) do
            local _, rec = Sync.Decode(Sync.Encode(key, a.db.events[key]))
            with(b, function() Sync.Merge(key, rec, "Alpha", false) end)
        end
        out.bAnswer = b.db.events[id].response and b.db.events[id].response.result
        out.a1 = with(a, function() return W.Score(week).winner end)
        out.b1 = with(b, function() return W.Score(week).winner end)
        -- three summons made in that week reach both clients only now: they count, the same way on both
        for n = 1, 3 do
            local ev = { caster = "Gamma", target = "Other", assistants = {}, mapID = 1436, subzone = "Sentinel Hill",
                time = BASE + 7200 + n, confirmed = true }
            local _, rec = Sync.Decode(Sync.Encode("Gamma-" .. n, ev))
            local _, rec2 = Sync.Decode(Sync.Encode("Gamma-" .. n, ev))
            with(a, function() Sync.Merge("Gamma-" .. n, rec, "Gamma", false) end)
            with(b, function() Sync.Merge("Gamma-" .. n, rec2, "Gamma", false) end)
        end
        out.a2 = with(a, function() return W.Score(week).winner end)
        out.b2 = with(b, function() return W.Score(week).winner end)
        out.aAnswer = a.db.events[id].response and a.db.events[id].response.result
        out.aPaid = a.db.events[id2].response and a.db.events[id2].response.result
        return out
    end)
    W.EventClosed, W.LateAnswer = fakeClosed, fakeLate
    if not ok then return false, tostring(res) end
    local r = res
    return r.closed and r.made == nil and r.late == "rejected:late" and r.inTime == "applied" and r.owed == "applied"
        and r.paid == "applied" and r.aAnswer == "refused" and r.aPaid == "paid" and r.staleAdd == "added" and r.staleKept == nil
        and r.bAnswer == "refused" and r.a1 == "zennit" and r.b1 == "zennit" and r.a2 == "group" and r.b2 == "group",
        string.format("made %s, late %s, in time %s, paid %s; stale %s (answer %s), Beta then %s; winners %s/%s, after the late summons %s/%s",
            tostring(r.made), tostring(r.late), tostring(r.inTime), tostring(r.paid), tostring(r.staleAdd),
            tostring(r.staleKept and r.staleKept.result), tostring(r.bAnswer), tostring(r.a1), tostring(r.b1), tostring(r.a2),
            tostring(r.b2))
end)

add("paying the silver keeps the list bonus it was owed with, and a week already announced says so when late summons change it", function()
    local z = newClient("Zennit")
    local W = ST.Week
    local out, printed = {}, {}
    local realPrint = ST.print
    ST.print = function(text) printed[#printed + 1] = text end
    local ok, err = pcall(with, z, function()
        -- owed at a place that was on his list then; the list has changed since (it is empty now)
        z.db.events["Bo-1"] = { caster = "Bo", target = "Zennit", assistants = {}, time = BASE + 10, points = 3, kind = "zone",
            response = { result = "owed", zroll = 0, sroll = 0, time = BASE + 20, listed = true, amount = 50 } }
        local resp = ST.Respond.Decide("Bo-1", "paid")
        out.listed = resp and resp.listed
        -- the week was announced as his; three summons made in it reach this client late and give it to the group
        local week = W.Start(BASE + 10)
        out.before = W.Score(week).winner
        z.db.settings.weekAnnounced = { start = week, winner = out.before }
        for n = 1, 3 do
            z.db.events["Gamma-" .. n] = { caster = "Gamma", target = "Other", assistants = {}, time = BASE + 100 + n, points = 10,
                kind = "far" }
        end
        local mark = #printed
        W.Recheck()
        out.said, out.after = printed[mark + 1], z.db.settings.weekAnnounced.winner
        mark = #printed
        W.Recheck()
        out.again = #printed - mark
    end)
    ST.print = realPrint
    if not ok then return false, tostring(err) end
    return out.listed == true and out.before == "zennit" and out.after == "group" and out.said ~= nil
        and out.said:find("changed", 1, true) ~= nil and out.again == 0,
        string.format("paid keeps listed %s; week %s then %s, said %s, again %d", tostring(out.listed), tostring(out.before),
            tostring(out.after), tostring(out.said ~= nil), out.again or -1)
end)

add("undo only removes your own summon, and the deletion sticks across sync, even for a friend who was offline", function()
    local a, b = newClient("Alpha"), newClient("Beta")
    local mine = cast(a, 920, false)
    local theirs = cast(b, 921, false)
    settle({ a, b })
    local removed = with(a, function() return Store.RemoveLast() end)
    if not removed or removed.id ~= mine then return false, "undo removed " .. tostring(removed and removed.id) end
    settle({ a }) -- Beta is offline when the deletion is broadcast
    if not b.db.events[mine] then return false, "Beta should still hold it" end
    with(b, function() Sync.Hello() end)
    settle({ a, b })
    local gone = b.db.events[mine] == nil and a.db.events[theirs] ~= nil
    -- it must not come back by sync from a client that still holds it
    local c = newClient("Gamma")
    local back = with(c, function()
        local _, ev = Sync.Decode(Sync.Encode(mine, { caster = "Alpha", target = "Target920", assistants = {}, time = BASE + 920, confirmed = true }))
        c.db.deleted = { [mine] = 1 }
        return Sync.Merge(mine, ev, "Beta", false)
    end)
    local forged = with(b, function() return Sync.OnMessage("1~T~" .. theirs, "PARTY", "Gamma") end)
    return gone and back == "rejected:deleted" and forged == "rejected:sender" and b.db.events[theirs] ~= nil,
        string.format("gone=%s back=%s forged=%s", tostring(gone), back, forged)
end)

add("a reset everyone was asked to make is asked again from the next HELLO; a player's own reset is never passed on", function()
    local a, b, c = newClient("Alpha"), newClient("Beta"), newClient("Gamma")
    cast(a, 930, false)
    settle({ a, b })
    local stamp = BASE + 5000
    local asked = {}
    local realAsk = Sync.onReset
    Sync.onReset = function(sender, s) asked[#asked + 1] = sender .. ":" .. s end
    local function hello(c)
        with(c, function() Sync.Hello() Sync.Pump(100000) end)
        local found
        for _, m in ipairs(c.out) do
            if m.payload:match("^%d+~H~") then found = m.payload end
        end
        c.out = {}
        return found or ""
    end
    -- Alpha resets only its own client: its hello does not carry it
    with(a, function() ST.Reset.Apply(stamp) end)
    local own = hello(a)
    with(b, function() Sync.OnMessage(own, "PARTY", "Alpha") end)
    local afterOwn = #asked
    -- a client before 0.28.1 sends its own reset in the same field, unstamped: ignored
    with(b, function() Sync.OnMessage("1~H~0|0|0.28.0|0|" .. stamp .. "|0", "WHISPER", "Alpha") end)
    local afterOld = #asked
    -- the admin's reset-all (Beta never heard the request) travels with the admin's stamp, and is asked
    a.db.resetAll = stamp
    local all = hello(a)
    with(b, function() Sync.OnMessage(all, "PARTY", "Alpha") end)
    Sync.onReset = realAsk
    -- a newcomer holding nothing from before it takes the mark without being asked (a prompt would leave it unset)
    with(c, function() Sync.OnMessage(all, "PARTY", "Alpha") end)
    -- Beta, who holds a summons from before it, says yes: the reset is made, and Beta passes the request on in turn
    local realPrint = ST.print
    ST.print = function() end
    local okAccept, errAccept = pcall(with, b, function() ST.Reset.Accept("Alpha", stamp) end)
    ST.print = realPrint
    if not okAccept then return false, tostring(errAccept) end
    local passed = hello(b)
    local left = 0
    for _ in pairs(b.db.events) do left = left + 1 end
    return afterOwn == 0 and afterOld == 0 and #asked == 1 and asked[1] == "Alpha:" .. stamp and own ~= ""
        and not own:find(tostring(stamp), 1, true) and all:find(ST.ADMIN_HASH, 1, true) ~= nil
        and c.db.resetAt == stamp and c.db.resetAll == stamp
        and left == 0 and b.db.resetAt == stamp and b.db.resetAll == stamp and passed:find(stamp .. "|", 1, true) ~= nil
        and passed:find(ST.ADMIN_HASH, 1, true) ~= nil,
        string.format("own reset asked %d, old client's %d, reset-all asked %s; newcomer's mark %s/%s; Beta accepted: %d left, passes it on %s",
            afterOwn, afterOld - afterOwn, tostring(asked[1]), tostring(c.db.resetAt), tostring(c.db.resetAll), left,
            tostring(passed:find(ST.ADMIN_HASH, 1, true) ~= nil))
end)

add("Zennit's alts are learned from his own client, and only a few", function()
    local a, z = newClient("Alpha"), newClient("Zennit")
    local savedGet, savedZennit = ST.bnGetInfo, ST.ZENNIT_HASH
    ST.ZENNIT_HASH = ST.TagHash("Zennit#1") -- a sample account stands in for his (its tag is not in the addon)
    ST.bnGetInfo = function() return 1, "Zennit#1" end
    local okHello, errHello = pcall(with, z, function() Sync.Hello() Sync.Pump(100000) end) -- messages only reach c.out once pumped
    ST.bnGetInfo, ST.ZENNIT_HASH = savedGet, savedZennit
    if not okHello then return false, tostring(errHello) end
    local sentA
    for _, m in ipairs(z.out) do if m.payload:match("^%d+~A~") then sentA = m.payload end end
    if not sentA then return false, "Zennit's client did not announce itself" end
    local before = with(a, function() return ST.Week.IsZennit("Bankalt") end)
    local r1 = with(a, function() return Sync.OnMessage(sentA, "PARTY", "Bankalt") end)
    local r2 = with(a, function() return Sync.OnMessage(sentA, "PARTY", "Bankalt") end)
    local after = with(a, function() return ST.Week.IsZennit("Bankalt-SomeRealm") end)
    local other = with(a, function() return ST.Week.IsZennit("Gamma") end)
    local capped
    with(a, function() for i = 1, 12 do capped = Sync.OnMessage(sentA, "PARTY", "Alt" .. i) end end)
    return not before and r1 == "learned" and r2 == "kept" and after and not other and capped == "rejected:full",
        string.format("before=%s %s %s after=%s other=%s capped=%s", tostring(before), r1, r2, tostring(after), tostring(other), tostring(capped))
end)

add("test summons are not counted in tallies or badge stats", function()
    local a = newClient("Alpha")
    cast(a, 940, true)
    cast(a, 941, true, { fake = true })
    local tally, stats
    with(a, function()
        tally = ST.Store.Tallies().Alpha
        stats = ST.Store.Stats("Alpha")
    end)
    return tally.cast == 1 and stats.cast == 1, string.format("tally %d, stats %d", tally.cast, stats.cast)
end)

add("assistants prompt in a raid: helpers from any subgroup come first, the list is capped, target and caster are left out", function()
    local members = {}
    for i = 1, 30 do members[i] = "Raider" .. i end
    members[#members + 1] = "Target"
    members[#members + 1] = "Me"
    local list = ST.Detector.PickCandidates(members, { "Raider28", "Raider3", "Gone" }, "Target", "Me", 12)
    local seen = {}
    for _, n in ipairs(list) do seen[n] = (seen[n] or 0) + 1 end
    local dupes = false
    for _, c in pairs(seen) do if c > 1 then dupes = true end end
    return #list == 12 and list[1] == "Raider28" and list[2] == "Raider3" and not seen.Target and not seen.Me
        and not seen.Gone and not dupes, table.concat(list, ",")
end)

add("scoring: cities, far-flung maps and dungeon entrances score by kind, and a dungeon subzone beats its map", function()
    local S = ST.Scoring
    local cityPts, city = S.Score(1453, "Trade District") -- Score gives the points, then the kind
    local zone = S.Score(1436, "Sentinel Hill")
    local remotePts, remote = S.Score(1451, "Cenarion Hold")
    local dungeonPts, dungeon = S.Score(1451, "The Deadmines")
    local wc = S.Kind(1413, "Wailing Caverns")
    local ok = city == "city" and cityPts == 1 and zone == 3 and remote == "remote" and remotePts == 10
        and dungeon == "dungeon" and dungeonPts == 5 and wc == "dungeon"
    return ok, string.format("%s %s %s %s", tostring(city), tostring(remote), tostring(dungeon), tostring(wc))
end)

add("places: /sc places checks each map ID against the game's name for it, and flags a wrong or missing one", function()
    local S = ST.Scoring
    local function nameOf(wrong)
        return function(id)
            if id == wrong.missing then return nil end
            if id == wrong.renamed then return "Somewhere Else" end
            return S.cityNames[id] or S.remoteNames[id]
        end
    end
    local good = table.concat(S.Places(nameOf({})), "\n")
    local bad = table.concat(S.Places(nameOf({ missing = 1451, renamed = 1453 })), "\n")
    local ok = good:find("a city 1, a dungeon entrance 5, a far-flung place 10, anywhere else 3", 1, true)
        and good:find("Cities: ", 1, true) and good:find("Silithus", 1, true) and good:find("wailing caverns", 1, true)
        and good:find("The client knows every map above", 1, true) and not good:find("client has no such map", 1, true)
        and bad:find("Silithus (1451: the client has no such map)", 1, true)
        and bad:find("Stormwind City (1453: the client calls it 'Somewhere Else')", 1, true)
        and bad:find("2 maps above did not match the client", 1, true)
    return ok, bad:sub(1, 160)
end)

add("the Party tab ranks by summons of Zennit this season, then points, then name", function()
    local tallies = {
        ["Al-Realm"] = { cast = 9, received = 0, assisted = 1, points = 60 },   -- many summons of others, none of him
        ["Bo"] = { cast = 3, received = 0, assisted = 0, points = 3 },          -- took the cheap slots for the team
        ["Cy"] = { cast = 3, received = 0, assisted = 2, points = 15 },
        ["Di"] = { cast = 0, received = 0, assisted = 4, points = 0 },
        ["Zennit"] = { cast = 0, received = 12, assisted = 0, points = 5 },
    }
    local rows = ST.Store.Ranked(tallies, { Bo = 3, Cy = 3, Al = 0 })
    local order = {}
    for _, r in ipairs(rows) do order[#order + 1] = r[1] .. ":" .. r[3] end
    local got = table.concat(order, " ")
    return got == "Cy:3 Bo:3 Al-Realm:0 Zennit:0 Di:0", got
end)

-- Runs fn with the new race rules (Week.RULES) in force for every week; T.Run keeps the old rules for the rest.
-- (Defined here, before the first test that uses it.)
local function newRules(fn)
    local saved = ST.Week.RULES.from
    ST.Week.RULES.from = 0
    local ok, good, detail = pcall(fn)
    ST.Week.RULES.from = saved
    if not ok then return false, "ERROR " .. tostring(good) end
    return good, detail
end

add("/sc week say: one line to the party or the raid, and a reason when it cannot", function()
    return newRules(function()
        local W, a = ST.Week, newClient("Alpha")
        local out, sent = {}, {}
        local function chat(channel, fail)
            return { channel = function() return channel end,
                send = function(text, ch) if fail then error("blocked") end sent[#sent + 1] = ch .. ": " .. text end }
        end
        with(a, function()
            out.party = { W.SayWeek(chat("PARTY")) }
            out.raid = { W.SayWeek(chat("RAID")) }
            out.alone = { W.SayWeek(chat(nil)) }
            out.blocked = { W.SayWeek(chat("PARTY", true)) }
            W.RULES.from = math.huge
            out.old = { W.SayWeek(chat("PARTY")) }
            W.RULES.from = 0
        end)
        local ok = out.party[1] and out.party[2]:find("^Summon Core: Week:") and sent[1]:find("^PARTY: Summon Core: Week:")
            and out.raid[1] and sent[2]:find("^RAID: ")
            and not out.alone[1] and out.alone[2]:find("not in a group", 1, true) and #sent == 2
            and not out.blocked[1] and out.blocked[2]:find("would not send", 1, true)
            and not out.old[1] and out.old[2]:find("old rules", 1, true)
        return ok, tostring(out.party[2])
    end)
end)

add("copy window: /sc report copy, /sc rules copy and /sc week copy hold the printed lines, without colour codes", function()
    return newRules(function()
        local C, W, a = ST.Check, ST.Week, newClient("Alpha")
        local out = {}
        with(a, function()
            out.report, out.rules = ST.Report.Lines(), W.RulesCard()
            out.sayText = W.SayText()
            local sent
            W.SayWeek({ channel = function() return "PARTY" end, send = function(text) sent = text end })
            out.sent = sent
            W.RULES.from = math.huge
            out.old = { W.SayText() }
            W.RULES.from = 0
        end)
        local function plain(lines)
            local t = {}
            for i, l in ipairs(lines) do t[i] = (l:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
            return table.concat(t, "\n")
        end
        local painted = { "|cff33ff66PASS|r one", "two", "|cffff4444FAIL|r three" }
        local ok = C.Joined(painted) == "PASS one\ntwo\nFAIL three"
            and #out.report > 0 and C.Joined(out.report) == plain(out.report) and not C.Joined(out.report):find("|", 1, true)
            and #out.rules > 0 and C.Joined(out.rules) == plain(out.rules) and not C.Joined(out.rules):find("|", 1, true)
            and out.sayText and out.sayText == out.sent and out.sayText:find("^Summon Core: Week:")
            and out.old[1] == nil and out.old[2]:find("old rules", 1, true)
        return ok, tostring(out.sayText)
    end)
end)

add("voice clips: a refusal and a dice win each play their own category, other answers are silent", function()
    local a = newClient("Alpha")
    local id = cast(a, 950, true, { target = "Zennit" })
    local calls = {}
    local realPlay = ST.Clips.Play
    ST.Clips.Play = function(category) calls[#calls + 1] = category end
    local ok, err = pcall(function()
        for _, result in ipairs({ "refused", "won", "accepted", "excused" }) do
            with(a, function()
                ST.Respond.OnResponse(id, a.db.events[id], { result = result, zroll = 50, sroll = 20, time = BASE + 9 })
            end)
        end
    end)
    ST.Clips.Play = realPlay
    if not ok then return false, tostring(err) end
    return table.concat(calls, ",") == "zenit_refuse,zenit_win,zenit_refuse", table.concat(calls, ",")
end)

add("dice: Zennit rolls, the summoner rolls back, higher wins and a tie goes to Zennit", function()
    if ST.Respond.Resolve(64, 31) ~= "won" or ST.Respond.Resolve(20, 80) ~= "lost" or ST.Respond.Resolve(50, 50) ~= "won"
        or ST.Respond.Resolve(45, 50) ~= "won" or ST.Respond.Resolve(30, 50) ~= "lost" then -- his +10 edge
        return false, "Resolve is wrong"
    end
    local a, z = newClient("Alpha"), newClient("Zennit")
    local realDice = Sync.onDice
    local summonerRoll
    Sync.onDice = function(id, ev, zroll) Sync.SendDiceReply(id, summonerRoll, ev.target) end -- the summoner's side, rolling back
    local out = {}
    local ok, err = pcall(function()
        for i, c in ipairs({ { 64, 31, "won" }, { 20, 80, "lost" }, { 50, 50, "won" } }) do
            local id = cast(a, 910 + i, false, { target = "Zennit" })
            settle({ a, z })
            summonerRoll = c[2]
            with(z, function() ST.Respond.StartDice(id, c[1]) end)
            settle({ a, z })
            local resp = a.db.events[id].response
            out[#out + 1] = resp and (resp.result .. " " .. resp.zroll .. "-" .. resp.sroll) or "no answer"
            if not (resp and resp.result == c[3] and resp.zroll == c[1] and resp.sroll == c[2]) then
                error("roll " .. i .. " gave " .. out[#out])
            end
        end
    end)
    Sync.onDice = realDice
    return ok, ok and table.concat(out, ", ") or tostring(err)
end)

add("dice challenges and replies are only accepted from the right player", function()
    local a, z = newClient("Alpha"), newClient("Zennit")
    local id = cast(a, 930, false, { target = "Zennit" })
    settle({ a, z })
    local seen = {}
    local realDice, realReply = Sync.onDice, Sync.onDiceReply
    Sync.onDice = function() seen.dice = (seen.dice or 0) + 1 end
    Sync.onDiceReply = function() seen.reply = (seen.reply or 0) + 1 end
    local r = {}
    r[1] = with(a, function() return Sync.OnMessage("1~D~" .. id .. "|50", "WHISPER", "Gamma") end)   -- not the target
    r[2] = with(a, function() return Sync.OnMessage("1~D~" .. id .. "|50", "WHISPER", "Zennit") end)  -- the real thing
    r[3] = with(z, function() return Sync.OnMessage("1~S~" .. id .. "|50", "WHISPER", "Gamma") end)   -- not the summoner
    r[4] = with(z, function() return Sync.OnMessage("1~S~" .. id .. "|50", "WHISPER", "Alpha") end)   -- the real thing
    r[5] = with(a, function() return Sync.OnMessage("1~D~" .. id .. "|500", "WHISPER", "Zennit") end)  -- out of range
    Sync.onDice, Sync.onDiceReply = realDice, realReply
    local ok = r[1] == "rejected:sender" and r[2] == "dice" and r[3] == "rejected:sender" and r[4] == "dice-reply"
        and r[5] == "rejected:values" and seen.dice == 1 and seen.reply == 1
    return ok, table.concat(r, ", ")
end)

add("test summons never count for sync or export", function()
    local a = newClient("Alpha")
    cast(a, 1, true)
    with(a, function() ST.AddFake("Bob", {}) end)
    local count = with(a, function() return Store.Count() end)
    local since = with(a, function() return #Store.Since(0) end)
    local _, exported = with(a, function() return ST.Export.Build("all") end)
    return count == 1 and since == 1 and exported == 1,
        string.format("count=%d since=%d exported=%s", count, since, tostring(exported))
end)

add("pending summons: the unanswered and the ones owing silver, newest first", function()
    local a = newClient("Alpha")
    local me = ST.Store.me()
    cast(a, 940, true, { target = me })
    cast(a, 941, true, { target = me, response = { result = "owed", zroll = 0, sroll = 0, time = BASE + 1 } })
    cast(a, 942, true, { target = me, response = { result = "accepted", zroll = 0, sroll = 0, time = BASE + 2 } })
    cast(a, 943, true, { target = "Somebody" })
    local pending = with(a, function() return ST.Respond.Pending() end)
    local ok = #pending == 2 and pending[1].ev.time == BASE + 941 and pending[2].ev.time == BASE + 940
    return ok, ok and "2 waiting: the one owing silver, then the unanswered one" or ("found " .. #pending)
end)

add("the new race: only summons of Zennit count, ten a week, and a summon to his list pays him too", function()
    return newRules(function()
        local a = newClient("Alpha")
        local W = ST.Week
        local out = {}
        with(a, function()
            local last = W.Start() - 7 * 86400
            local function put(key, n, target, pts)
                a.db.events[key] = { caster = "Alpha", target = target, assistants = {}, time = last + 3600 * n,
                    points = pts, kind = "zone" }
            end
            for n = 1, 3 do put("f" .. n, n, "Target1", 10) end -- summons of each other are not in the race
            out.friends = W.Score(last)
            for n = 1, 11 do put("z" .. n, 20 + n, "Zennit", 3) end -- eleven of him: the first ten count
            out.six = W.Score(last)
            out.first, out.sixth = W.Counts(a.db.events.z1), W.Counts(a.db.events.z11)
            local resp = { result = "accepted", zroll = 0, sroll = 0, time = last + 99999 }
            out.enthusiasm = ST.Respond.Announce(a.db.events.z11, resp):find("enthusiasm") ~= nil
                and not ST.Respond.Announce(a.db.events.z1, resp):find("enthusiasm")
            a.db.events.z1.response = { result = "accepted", zroll = 0, sroll = 0, time = last + 99999, listed = true }
            out.listed = W.Score(last)
        end)
        local f, s, l = out.friends, out.six, out.listed
        local ok = f.group == 0 and f.zennit == W.RULES.headstart and f.winner == "zennit"
            and s.counted == 10 and s.extra == 1 and s.group == 30 and s.winner == "group"
            and out.first and not out.sixth and out.enthusiasm and l.zennit == W.RULES.headstart + 3 and l.group == 30
        return ok, string.format("friends %d-%d, eleven: %d counted, %d extra, %d-%d, listed: Zennit %d, enthusiasm %s",
            f.group, f.zennit, s.counted, s.extra, s.group, s.zennit, l.zennit, tostring(out.enthusiasm))
    end)
end)

add("the new dice: three a week, and each helper (up to two) adds 5 to the summoner's roll", function()
    return newRules(function()
        local W, R = ST.Week, ST.Respond
        -- his 55+10 = 65 against the summoner's 60: he wins alone, loses to two helpers, and a tie is still his
        local resolve = R.Resolve(55, 60, 0) == "won" and R.Resolve(55, 60, 10) == "lost" and R.Resolve(50, 50, 10) == "won"
        local a = newClient("Alpha")
        local out = {}
        with(a, function()
            local this = W.Start()
            local ev = { caster = "Alpha", target = "Zennit", time = this + 60, points = 3, assistants = { "H1" } }
            out.one = W.HelperBonus(ev)
            ev.assistants = { "H1", "H2", "H3" }
            out.three = W.HelperBonus(ev)
            out.fresh = W.DiceLeft(this)
            for n = 1, 3 do
                a.db.events["d" .. n] = { caster = "Alpha", target = "Zennit", assistants = {}, time = this + n * 60, points = 3,
                    response = { result = n == 2 and "lost" or "won", zroll = 50, sroll = 40, time = this + n * 60 + 1 } }
            end
            a.db.events.d4 = { caster = "Alpha", target = "Zennit", assistants = {}, time = this + 300, points = 3,
                response = { result = "accepted", zroll = 0, sroll = 0, time = this + 301 } }
            out.used = W.DiceLeft(this)
            W.RULES.from = math.huge -- and under the old rules: no limit, no bonus
            out.old = W.DiceLeft(this) == nil and W.HelperBonus(ev) == 0
            W.RULES.from = 0
        end)
        local ok = resolve and out.one == 5 and out.three == 10 and out.fresh == 3 and out.used == 0 and out.old
        return ok, string.format("bonus %s/%s, dice %s then %s, old rules unlimited: %s", tostring(out.one),
            tostring(out.three), tostring(out.fresh), tostring(out.used), tostring(out.old))
    end)
end)

add("closing the Index: allowed after five answered, it travels to everyone, and later summons stop counting", function()
    return newRules(function()
        local W, z, a = ST.Week, newClient("Zennit"), newClient("Alpha")
        local ids = {}
        for n = 1, 7 do ids[n] = cast(a, 960 + n, false, { target = "Zennit", assistants = {}, points = 3 }) end
        settle({ a, z })
        local start = W.Start(BASE + 961)
        local out = {}
        with(z, function()
            -- a closes flag before the fifth is ignored, and he can't close until the fifth is answered
            z.db.events[ids[3]].response = { result = "accepted", zroll = 0, sroll = 0, time = BASE + 2000, closes = true }
            out.early = W.IsClosed(start)
            for n = 1, 4 do ST.Respond.Decide(ids[n], "accepted") end
            out.before = W.CloseTarget(start)
            ST.Respond.Decide(ids[5], "refused")
            out.target = W.CloseTarget(start)
            out.closed = ST.Respond.CloseIndex(start)
            out.again = W.CloseTarget(start) -- once closed, it can't be closed again
            ST.Respond.Decide(ids[5], "accepted") -- a changed answer keeps the Index closed
        end)
        settle({ a, z })
        local rz = with(z, function() return W.Score(start) end)
        local ra = with(a, function() return W.Score(start) end)
        local later = with(a, function() return W.Counts(a.db.events[ids[6]]) end)
        local back = select(2, Sync.Decode(Sync.Encode(ids[5], a.db.events[ids[5]])))
        local ok = out.early == false and out.before == nil and out.target == ids[5] and out.closed and out.again == nil
            and rz.closed and ra.closed and ra.counted == 5 and ra.extra == 2 and rz.group == ra.group
            and later == false and back and back.response and back.response.closes == true
        return ok, string.format("early %s, target %s, closed %s/%s, counted %d, extra %d, group %d/%d, codec %s",
            tostring(out.early), tostring(out.target == ids[5]), tostring(rz.closed), tostring(ra.closed), ra.counted,
            ra.extra, rz.group, ra.group, tostring(back and back.response and back.response.closes))
    end)
end)

add("closing the Index keeps the answer it closes on: a card's punch and a named price stay", function()
    return newRules(function()
        local W, z = ST.Week, newClient("Zennit")
        local out = {}
        with(z, function()
            local start = W.Start(BASE + 980)
            for n = 1, 5 do
                z.db.events["Alpha-" .. n] = { caster = "Alpha", target = "Zennit", assistants = {}, time = start + n, points = 3,
                    kind = "zone", response = { result = "accepted", zroll = 0, sroll = 0, time = start + 10 + n } }
            end
            z.db.events["Alpha-5"].response = { result = "paid", zroll = 0, sroll = 0, time = start + 20, card = true, amount = 75 }
            out.closed = ST.Respond.CloseIndex(start)
            out.resp = z.db.events["Alpha-5"].response
        end)
        local r = out.resp or {}
        return out.closed and r.closes == true and r.card == true and r.amount == 75 and r.result == "paid",
            string.format("closed %s on %s, card %s, amount %s", tostring(out.closed), tostring(r.result), tostring(r.card),
                tostring(r.amount))
    end)
end)

local silverRuns = 0
add("the silver watcher leaves mail from no player alone (the Auction House), and a mail it cannot place to people it knows", function()
    local z = newClient("Zennit")
    local out, printed = {}, {}
    local realPrint = ST.print
    ST.print = function(text) printed[#printed + 1] = text end
    -- 50 silver settles nothing and buys no card, so each payment the watcher takes up is one line in chat (a payment is said once a
    -- minute, so each run of the tests pays a copper more)
    silverRuns = silverRuns + 1
    local copper = 5000 + silverRuns
    local function lines(fn) local before = #printed fn() return #printed - before end
    local ok, err = pcall(with, z, function()
        z.db.events["Bo-1"] = { caster = "Bo", target = "Zennit", assistants = { "Cy" }, time = BASE + 1, points = 3, kind = "zone" }
        z.db.cards = { k1 = { id = "k1", holder = "Di", punches = 2, silver = 100, time = BASE } }
        out.ah = ST.Silver.Known("Alliance Auction House")
        out.stranger = ST.Silver.Known("Mallory")
        out.caster = ST.Silver.Known("Bo Bravo") -- this client shows names as "Name Surname"
        out.helper = ST.Silver.Known("Cy-Realm")
        out.holder = ST.Silver.Known("Di")
        out.auction = lines(function() ST.Silver.Mail("Alliance Auction House", copper, false) end) -- the game: no player sent it
        out.unsure = lines(function() ST.Silver.Mail("Mallory", copper, nil) end)                   -- the game does not say, a stranger
        out.player = lines(function() ST.Silver.Mail("Mallory", copper, true) end)                  -- a player's mail (an alt, say)
        out.friend = lines(function() ST.Silver.Mail("Bo Bravo", copper, nil) end)                  -- does not say, but someone it knows
    end)
    ST.print = realPrint
    if not ok then return false, tostring(err) end
    return out.ah == false and out.stranger == false and out.caster and out.helper and out.holder and out.auction == 0
        and out.unsure == 0 and out.player == 1 and out.friend == 1,
        string.format("known: auction house %s, stranger %s, caster %s, helper %s, card holder %s; lines: auction %d, unsure %d, player %d, friend %d",
            tostring(out.ah), tostring(out.stranger), tostring(out.caster), tostring(out.helper), tostring(out.holder), out.auction or -1,
            out.unsure or -1, out.player or -1, out.friend or -1)
end)

add("a check the addon sees for itself is recorded quietly on a friend's client, and said on the admin's", function()
    local a = newClient("Alpha")
    local out, printed = {}, {}
    local realAdmin, realPrint = ST.IsAdmin, ST.print
    ST.print = function(text) printed[#printed + 1] = text end
    local ok, err = pcall(with, a, function()
        ST.IsAdmin = function() return false end
        ST.Check.Seen("s-welcome", "test")
        out.friend, out.friendSaid = ST.Check.Status("s-welcome"), #printed
        ST.IsAdmin = function() return true end
        ST.Check.Seen("s-lastcall", "test")
        out.admin, out.adminSaid = ST.Check.Status("s-lastcall"), #printed - out.friendSaid
    end)
    ST.IsAdmin, ST.print = realAdmin, realPrint
    if not ok then return false, tostring(err) end
    return out.friend == "pass" and out.friendSaid == 0 and out.admin == "pass" and out.adminSaid == 1,
        string.format("friend %s (%d lines), admin %s (%d lines)", tostring(out.friend), out.friendSaid or -1, tostring(out.admin),
            out.adminSaid or -1)
end)

add("his week off is real: summons of him are filler, nobody wins it, and the week after is a normal one", function()
    return newRules(function()
        local a = newClient("Alpha")
        local W = ST.Week
        local out = {}
        with(a, function()
            local this = W.Start()
            local last = this - 7 * 86400
            local function put(key, at, resp)
                a.db.events[key] = { caster = "Alpha", target = "Zennit", assistants = {}, time = at, points = 3, kind = "zone",
                    response = resp }
            end
            put("won", last + 3600, { result = "won", zroll = 90, sroll = 10, time = last + 3700 }) -- he wins last week
            out.last = W.Score(last)
            for n = 1, 3 do put("off" .. n, this + 3600 * n, { result = "accepted", zroll = 0, sroll = 0, time = this + 3600 * n + 5 }) end
            out.week = W.Score(this)
            out.counts = W.Counts(a.db.events.off1)
            out.said = ST.Respond.Announce(a.db.events.off1, a.db.events.off1.response):find("disturbing his leave", 1, true) ~= nil
            out.season = W.Season()
            out.next = W.IsOff(this + 7 * 86400) -- nobody won this week, so the next one is not off
        end)
        local l, w, season = out.last, out.week, out.season
        local ok = l.winner == "zennit" and not l.off and w.off and w.winner == nil and w.counted == 0 and w.extra == 3
            and w.group == 0 and not out.counts and out.said and season.zennit == 1 and season.group == 0
            and #season.chapters == 1 and not out.next
        return ok, string.format("last: %s; off week: %s, %d counted, %d filler, winner %s; season %d-%d; next week off: %s",
            tostring(l.winner), tostring(w.off), w.counted, w.extra, tostring(w.winner), season.zennit, season.group,
            tostring(out.next))
    end)
end)

add("the Index remembers: tipped rolls, the heaviest hand, a run of dice and the silver, by name, over one season", function()
    local L = ST.Ledger
    local ctx = { isZennit = function(n) return n == "Zennit" end, name = function(n) return n end,
        bonus = function(ev) return math.min(#(ev.assistants or {}), 2) * 5 end, edge = function() return 10 end,
        resolve = ST.Respond.Resolve, silver = 50, helpersMax = 2 }
    local function ev(t, caster, helpers, result, zroll, sroll)
        return { caster = caster, target = "Zennit", assistants = helpers or {}, time = t,
            response = result and { result = result, zroll = zroll or 0, sroll = sroll or 0, time = t + 1 } }
    end
    local events = {
        a = ev(10, "Bo", { "Al", "Cy" }, "lost", 45, 52),   -- 45+10 beats 52 alone, but 52+10 beats 55: the helpers tipped it
        b = ev(20, "Bo", {}, "paid"), c = ev(30, "Bo", {}, "owed"), d = ev(40, "Bo", { "Al" }, "won", 90, 10),
        e = ev(50, "Di", {}, "won", 90, 10), f = ev(60, "Di", {}, "won", 90, 10),
        g = { caster = "Bo", target = "Someone", assistants = {}, time = 70 },   -- not a summon of him
        h = ev(500, "Bo", {}, "paid"),                                          -- outside the window
    }
    local d = L.Collect(events, 0, 100, ctx)
    local tip = d.tipped
    if not (d.summons == 6 and d.silverPaid == 50 and d.silverOwed == 50 and d.streak == 3 and d.heaviest
        and d.heaviest.name == "Bo" and d.heaviest.n == 4 and tip and tip.caster == "Bo" and #tip.helpers == 2) then
        return false, string.format("facts wrong: %d summons, silver %d/%d, streak %d", d.summons, d.silverPaid, d.silverOwed, d.streak)
    end
    local moments = L.Moments(d)
    if #moments ~= 2 or not moments[1].text:find("Al and Cy's %+10 tipped") or not moments[2].text:find("Bo has summoned Zennit 4") then
        return false, "the moments do not name the players"
    end
    local keep = table.concat(L.Keepsake(1, { start = 7 * 86400, side = "group", from = 0 }, d), " ")
    if not (keep:find("Season 1, 2 weeks") and keep:find("In the room: Al, Bo, Cy and Di") and keep:find("paid Zennit 50 silver")
        and keep:find("freed")) then
        return false, "the keepsake is missing something"
    end
    local tie = L.Collect({ x = ev(1, "Al"), y = ev(2, "Bo") }, 0, 100, ctx)
    return tie.heaviest == nil, "tipped roll, heaviest hand, dice run, silver and who was there, and a tie names nobody"
end)

add("pools of lines: a variant is never the one before it, every variant carries the facts, and the plain one is first", function()
    local V = ST.Voice
    local fixedBefore = V.fixed
    V.fixed = false
    local seq, prev, repeated = {}, nil, false
    for i = 1, 200 do
        local pick = V.Choose("selftest", 3)
        if pick == prev then repeated = true end
        prev = pick
        seq[pick] = true
    end
    local one = V.Choose("selftest-one", 1)
    V.fixed = true
    local plain = V.Choose("selftest", 3)
    local line = V.Say("selftest-say", { "%s and %d", "%d with %s" }, "x", 2)
    V.fixed = fixedBefore
    -- every answer pool names the same facts: the dice numbers, the points and the silver
    local R, a = ST.Respond, newClient("Alpha")
    local ok, bad = true, nil
    V.fixed = false
    with(a, function()
        local ev = { caster = "Alpha", target = "Zennit", assistants = {}, time = ST.Week.Start() + 60, points = 5, kind = "dungeon" }
        for _, r in ipairs({ "accepted", "refused", "excused", "owed", "paid", "won", "lost" }) do
            for _ = 1, 12 do
                local text = R.Announce(ev, { result = r, zroll = 77, sroll = 31, time = 1 })
                local needs = (r == "won" or r == "lost") and "77" or (r == "owed" or r == "paid") and "50" or "Alpha"
                if not text or not text:find(needs, 1, true) then ok, bad = false, r end
            end
        end
    end)
    V.fixed = fixedBefore
    return not repeated and seq[1] and seq[2] and seq[3] and one == 1 and plain == 1 and line == "x and 2" and ok,
        bad and ("a variant of '" .. bad .. "' lost a fact") or "never the same twice running; all three used; the facts survive"
end)

add("the whim of the week: the same on every client, about half the weeks, and each moves one rule a little", function()
    return newRules(function()
        local W = ST.Week
        local saved = W.RULES.whims
        W.RULES.whims = true
        local counts, none, again = {}, 0, true
        local start = W.Start()
        for n = 0, 199 do
            local at = start + n * 7 * 86400
            local whim, id = W.Whim(at)
            if whim then counts[id] = (counts[id] or 0) + 1 else none = none + 1 end
            if (W.Whim(at)) ~= whim then again = false end
        end
        local edge, helper = W.Rule("edge", start), W.Rule("helperBonus", start)
        -- find a week of each kind and read its rule
        local seen = {}
        for n = 0, 199 do
            local at = start + n * 7 * 86400
            local whim, id = W.Whim(at)
            if id then seen[id] = at end
        end
        local ok = again and none > 60 and none < 140 and counts.distracted and counts.attentive and counts.feast and counts.tired
            and W.Rule("edge", seen.distracted) == ST.Respond.EDGE - 5 and W.Rule("edge", seen.attentive) == ST.Respond.EDGE + 5
            and W.Rule("helperBonus", seen.feast) == W.RULES.helperBonus + 3 and W.Rule("helperBonus", seen.tired) == W.RULES.helperBonus - 3
            and W.WhimLine(seen.feast):find("Each helper adds %+8") and W.WhimLine(seen.distracted):find("5 lower")
        local plainWeek
        for n = 0, 199 do local at = start + n * 7 * 86400 if not W.Whim(at) then plainWeek = at break end end
        ok = ok and W.WhimLine(plainWeek) == nil and W.Rule("edge", plainWeek) == ST.Respond.EDGE
        W.RULES.whims = false
        ok = ok and W.Whim(start) == nil and W.Rule("edge", seen.distracted) == ST.Respond.EDGE
        W.RULES.whims = saved
        W.RULES.from = math.huge
        local old = W.Whim(start) == nil -- the old rules have none
        W.RULES.from = 0
        return ok and old, string.format("200 weeks: %d plain, %d distracted, %d attentive, %d feast, %d tired", none,
            counts.distracted or 0, counts.attentive or 0, counts.feast or 0, counts.tired or 0)
    end)
end)

add("the list remembers: a place on his list that comes up again is noticed, and the first time is not", function()
    return newRules(function()
        local a = newClient("Alpha")
        local W, R = ST.Week, ST.Respond
        local out = {}
        with(a, function()
            local this = W.Start()
            local function put(key, n, where, listed)
                a.db.events[key] = { caster = "Alpha", target = "Zennit", assistants = {}, time = this + 60 * n, points = 3,
                    subzone = where, mapID = 1, kind = "zone",
                    response = { result = "accepted", zroll = 0, sroll = 0, time = this + 60 * n + 1, listed = listed } }
            end
            put("a", 1, "Darnassus", true); put("b", 2, "Stormwind", true); put("c", 3, "Darnassus", true)
            put("d", 4, "Darnassus", false); put("e", 5, "Darnassus", true)
            local function say(key) return R.Announce(a.db.events[key], a.db.events[key].response) end
            out.first, out.other, out.second, out.unlisted, out.third = say("a"), say("b"), say("c"), say("d"), say("e")
            out.hits = R.ListHits(a.db.events.e, a.db.events.e.response)
        end)
        local ok = not out.first:find("again") and not out.other:find("again") and out.second:find("Darnassus again", 1, true)
            and not out.unlisted:find("again") and out.third:find("third time", 1, true) and out.hits == 3
        return ok, string.format("first: %s | second: %s | third: %s", out.first:sub(-40), out.second:sub(-60), out.third:sub(-70))
    end)
end)

add("the list is bounded: places of four letters or more, five at most, and an old short entry stops matching", function()
    local a = newClient("Alpha")
    local R = ST.Respond
    local out = {}
    with(a, function()
        a.db.settings = a.db.settings or {}
        a.db.settings.zennitList = {}
        out.short = { R.ListAdd("a") }
        out.empty = { R.ListAdd("   ") }
        for _, place in ipairs({ "Darnassus", "Stormwind", "Orgrimmar", "Ironforge", "Undercity" }) do out[place] = R.ListAdd(place) end
        out.sixth = { R.ListAdd("Thunder Bluff") }
        out.count = #R.ListActive()
        local ev = { subzone = "Stormwind Harbor" }
        out.hit = R.OnList(ev)
        -- an entry saved before the bound: a single letter and a sixth place do not count
        a.db.settings.zennitList = { "e", "Darnassus", "Stormwind", "Orgrimmar", "Ironforge", "Undercity", "Thunder Bluff" }
        out.legacy = R.OnList({ subzone = "The Barrens" })          -- "e" would have matched
        out.sixthPlace = R.OnList({ subzone = "Thunder Bluff" })    -- past the fifth
        out.active = #R.ListActive()
    end)
    local ok = out.short[1] == false and out.short[2]:find("at least 4") and out.empty[1] == false
        and out.Darnassus and out.Undercity and out.sixth[1] == false and out.sixth[2]:find("holds 5")
        and out.count == 5 and out.hit and not out.legacy and not out.sixthPlace and out.active == 5
    return ok, string.format("one letter refused, five places held, a sixth refused (%s); old entries: 'e' %s, sixth place %s",
        tostring(out.sixth[2]), tostring(out.legacy), tostring(out.sixthPlace))
end)

add("the rules card: this week's live numbers, the whim, and the old rules when they apply", function()
    return newRules(function()
        local W = ST.Week
        local savedWhims = W.RULES.whims
        local a = newClient("Alpha")
        local out = {}
        with(a, function()
            W.RULES.whims = false
            out.plain = table.concat(W.RulesCard(), "\n")
            W.RULES.whims = true
            local start = W.Start()
            for n = 0, 99 do                                  -- a week with a whim
                local at = start + n * 7 * 86400
                if W.Whim(at) then out.whimCard = table.concat(W.RulesCard(at), "\n") out.whimLine = W.WhimLine(at) break end
            end
            W.RULES.from = math.huge
            out.old = table.concat(W.RulesCard(), "\n")
            W.RULES.from = 0
        end)
        W.RULES.whims = savedWhims
        local R = W.RULES
        local ok = out.plain:find("up to " .. R.cap .. " a week", 1, true) and out.plain:find("Once " .. R.minimum .. " are filed", 1, true)
            and out.plain:find("he has " .. R.dice .. " a week", 1, true) and out.plain:find("No whim this week", 1, true)
            and out.plain:find("up to " .. ST.Respond.LIST_MAX .. " places", 1, true)
            and out.whimCard and out.whimCard:find("This week's whim: " .. out.whimLine, 1, true)
            and out.old:find("old rules", 1, true) and not out.old:find("Counts:", 1, true)
        return ok, "cap, close, dice, list, whim and the old rules all read from the live numbers"
    end)
end)

add("the playtest report: weeks, answers, dice, the list and the helpers, counted from the log", function()
    local D = 7 * 86400
    local base = 100 * D
    local function ev(week, n, caster, helpers, points, result, listed)
        local t = base + week * D + n * 60
        return { caster = caster, target = "Zennit", assistants = helpers or {}, time = t, points = points,
            response = result and { result = result, zroll = 40, sroll = 60, time = t + 30, listed = listed } }
    end
    local events = {
        a = ev(0, 1, "Al", { "Cy", "Di" }, 3, "lost"), b = ev(0, 2, "Bo", {}, 3, "won", true), c = ev(0, 3, "Al", {}, 5, "accepted"),
        d = ev(2, 1, "Di", { "Al" }, 3, nil),                                           -- the current week, unanswered
        f = { caster = "Al", target = "Zennit", assistants = {}, time = base + 5, points = 9, fake = true },
        g = { caster = "Al", target = "Someone", assistants = {}, time = base + 6, points = 9 },
    }
    local lines = ST.Report.Build({
        events = events, isZennit = function(n) return n == "Zennit" end,
        weekStart = function(t) return t - (t % D) end, nowStart = base + 2 * D,
        score = function(start) return start == base and { winner = "group", counted = 3 } or { counted = 0 } end,
        whim = function() return nil end, dice = 3, tipped = 2 })
    local text = table.concat(lines, "\n")
    -- 4 real summons of Zennit: the test summon and the one of someone else are left out
    local ok = text:find("3 weeks of the log (the current one included), 4 summons of Zennit", 1, true)
    ok = ok and text:find("2 with a summons of him, 1 without", 1, true) and text:find("the group won 1", 1, true)
        and text:find("3 or 4: 1 of 1", 1, true) and text:find("unanswered 1", 1, true)
        and text:find("Dice: 2 rolled", 1, true) and text:find("Rolls the helpers tipped: 2", 1, true)
        and text:find("33% of his answers were on it", 1, true)
    local none = ST.Report.Build({ events = {}, isZennit = function() return false end, weekStart = function(t) return t end,
        nowStart = 0, score = function() return {} end, whim = function() end, dice = 3 })
    return ok and #none == 1, "weeks, answers, dice, the list and the helpers read from the log; an empty log says so"
end)

add("waiting for his answer: counted once overdue, said to the group and in his own words", function()
    return newRules(function()
        local W = ST.Week
        local a = newClient("Alpha")
        local savedOverdue = W.RULES.overdue
        local out = {}
        with(a, function()
            local this = W.Start()
            local function put(key, answered)
                a.db.events[key] = { caster = "Alpha", target = "Zennit", assistants = {}, time = this, points = 3, kind = "zone",
                    response = answered and { result = "accepted", zroll = 0, sroll = 0, time = this + 1 } or nil }
            end
            put("a", true); put("b", false); put("c", false)
            W.RULES.overdue = math.huge
            out.quiet = W.StatusLine(this)                       -- nothing is overdue yet
            out.none = W.Overdue(this)
            W.RULES.overdue = 0
            out.all = W.Unanswered(this)
            out.waiting = W.Overdue(this)
            out.group = W.StatusLine(this)
            out.you = W.StatusLine(this, true)
            out.brief = W.Briefing("Zennit")
            W.RULES.overdue = savedOverdue
        end)
        local ok = not out.quiet:find("waiting", 1, true) and out.none == 0 and out.all == 2 and out.waiting == 2
            and out.group:find("2 waiting for his answer", 1, true) and out.you:find("2 waiting for your answer", 1, true)
            and out.brief and out.brief:find("2 earlier summons of him are still waiting", 1, true)
        return ok, tostring(out.group)
    end)
end)

add("a provisional Monday: announced as provisional while he can still answer, then said again as final or as changed", function()
    return newRules(function()
        local W = ST.Week
        local a = newClient("Alpha")
        local printed, realPrint, realTime = {}, ST.print, time
        local out = {}
        local function say() return table.concat(printed, "\n") end
        local ok, err = pcall(function()
            with(a, function()
                local monday = W.Start()
                local last = monday - 7 * 86400
                -- last week: one summons accepted, one never answered; both land, so the group leads 6 to 2
                a.db.events.x = { caster = "Alpha", target = "Zennit", assistants = {}, time = last + 3600, points = 3, kind = "zone",
                    response = { result = "accepted", zroll = 0, sroll = 0, time = last + 3700 } }
                a.db.events.y = { caster = "Alpha", target = "Zennit", assistants = {}, time = last + 7200, points = 3, kind = "zone" }
                ST.print = function(text) printed[#printed + 1] = text end
                rawset(_G, "time", function() return monday + 86400 end)          -- Tuesday: he can still answer
                W.Check()
                out.first = say()
                out.provisional = a.db.settings.weekAnnounced and a.db.settings.weekAnnounced.provisional
                out.announced = a.db.settings.weekAnnounced and a.db.settings.weekAnnounced.winner
                -- his late answer: he wins the dice, and the week is his
                a.db.events.y.response = { result = "won", zroll = 90, sroll = 10, time = monday + 80000 }
                printed = {}
                rawset(_G, "time", function() return monday + 3 * 86400 end)      -- Thursday: the week has closed
                W.Check()
                out.second = say()
                out.settled = a.db.settings.weekAnnounced and a.db.settings.weekAnnounced.provisional
            end)
        end)
        rawset(_G, "time", realTime)
        ST.print = realPrint
        if not ok then return false, "ERROR " .. tostring(err) end
        local pass = out.first:find("Provisional:", 1, true) and out.first:find("1 summons of him is still waiting", 1, true)
            and out.provisional == true and out.announced == "group"
            and out.second:find("changed", 1, true) and out.second:find("went to Zennit, not the group", 1, true) and out.settled == nil
        return pass, string.format("announced provisional (%s), then: %s", tostring(out.provisional), tostring(out.second):sub(1, 90))
    end)
end)

add("silver owed: counted by week and overall, shown to both sides, and payable after the week has closed", function()
    return newRules(function()
        local W, R = ST.Week, ST.Respond
        local a = newClient("Alpha")
        local out = {}
        local me = ST.Store.me()
        local realClosed = W.EventClosed
        with(a, function()
            local this = W.Start()
            local function put(key, caster, target, result, at)
                a.db.events[key] = { caster = caster, target = target, assistants = {}, time = at, points = 3, kind = "zone",
                    response = result and { result = result, zroll = 0, sroll = 0, time = at + 1 } or nil }
            end
            put("s1", "Bo", "Zennit", "owed", this + 10); put("s2", "Bo", "Zennit", "owed", this + 20)
            put("s3", "Bo", "Zennit", "paid", this + 30)
            out.n, out.silver = W.Owed(this)
            out.group = W.StatusLine(this)
            out.you = W.StatusLine(this, true)
            -- what I am owed, and what I owe, across all weeks
            put("t1", "Bo", me, "owed", this - 21 * 86400); put("t2", me, "Zennit", "owed", this - 21 * 86400 + 5)
            out.owedToMe, out.silverToMe = R.Owed("target")
            out.iOwe, out.silverIOwe = R.Owed("caster")
            -- the silver of a closed week can still be paid, and nothing else can be answered into it
            W.EventClosed = function() return true end
            a.db.events.t1.target = me
            out.paid = R.Decide("t1", "paid")
            out.lateAccept = R.Decide("t2", "accepted")
            W.EventClosed = realClosed
        end)
        W.EventClosed = realClosed
        local ok = out.n == 2 and out.silver == 100
            and out.group:find("100 silver owed to him", 1, true) and out.you:find("100 silver owed to you", 1, true)
            and out.owedToMe == 1 and out.silverToMe == 50 and out.iOwe == 1 and out.silverIOwe == 50
            and out.paid and out.paid.result == "paid" and out.lateAccept == nil
        return ok, string.format("2 owe (%s silver); owed to me %s, I owe %s; closed week: paid %s, accepted %s", tostring(out.silver),
            tostring(out.silverToMe), tostring(out.silverIOwe), tostring(out.paid ~= nil), tostring(out.lateAccept))
    end)
end)

add("summon cards: sold by Zennit, synced to everyone, punched by his demand for silver, counted from the log", function()
    return newRules(function()
        local W, R, C, Sy = ST.Week, ST.Respond, ST.Cards, ST.Sync
        local z, a = newClient("Zennit"), newClient("Alpha")
        local out = {}
        local realClosed = W.EventClosed
        with(z, function()
            z.db.settings.zenitNames = { "Zennit" }
            out.card = C.Issue("Bo-Realm", 2, 100)                       -- he sells Bo a card of two punches
            out.sold = Sy.state.queue[#Sy.state.queue] and Sy.state.queue[#Sy.state.queue].payload
        end)
        out.noOne = select(2, with(a, function() return C.Issue("Bo", 2, 100) end)) -- anyone else cannot
        -- another client takes the card, from Zennit only
        with(a, function()
            local body = out.sold and out.sold:match("^%d+~K~(.*)$")
            out.fromZennit = body and Sy.OnMessage("1~K~" .. body, "PARTY", "Zennit")
            out.fromAnyone = body and Sy.OnMessage("1~K~" .. body, "PARTY", "Mallory")
            out.again = body and Sy.OnMessage("1~K~" .. body, "PARTY", "Zennit")
            out.bad = Sy.OnMessage("1~K~card-1|Bo|99|10|" .. time(), "PARTY", "Zennit")
        end)
        local n = 0
        with(a, function()
            for _ in pairs(a.db.cards or {}) do n = n + 1 end
            out.cards = n
            out.left = C.Left("Bo")
            -- Bo summons Zennit twice; Zennit demands the silver both times: the card pays, a third time it does not
            local this = W.Start()
            local function put(key, at) a.db.events[key] = { caster = "Bo", target = "Zennit", assistants = {}, time = at, points = 3, kind = "zone" } end
            put("b1", this + 10); put("b2", this + 20); put("b3", this + 30)
            a.db.settings.zenitNames = { "Zennit" }
            for _, id in ipairs({ "b1", "b2" }) do
                a.db.events[id].response = { result = "paid", zroll = 0, sroll = 0, time = this + 40, card = true }
            end
            out.after = C.Left("Bo")
            out.lines = table.concat(C.Lines(), " ")
            out.paidLine = R.Announce(a.db.events.b2, a.db.events.b2.response)
            -- the card flag survives the wire
            local id, ev = Sy.Decode(Sy.Encode("Bo-1", { caster = "Bo", target = "Zennit", assistants = {}, time = this, wrote = this,
                response = { result = "paid", zroll = 0, sroll = 0, time = this + 5, card = true, listed = true } }))
            out.flag = ev and ev.response and ev.response.card and ev.response.listed and not ev.response.closes
        end)
        local m = ST.Silver.Match(30000, { { id = "s1", amount = 50 }, { id = "s2", amount = 50 } }, { { punches = 5, silver = 200 } })
        local m2 = ST.Silver.Match(1200, {}, { { punches = 5, silver = 200 } })
        local ok = out.card and out.card.punches == 2 and out.noOne == "only Zennit can sell cards"
            and out.fromZennit == "card" and out.fromAnyone == "rejected:sender" and out.again == "kept" and out.bad == "rejected:values"
            and out.cards == 1 and out.left == 2 and out.after == 0 and out.lines:find("0 of 2 punches left", 1, true)
            and out.paidLine:find("card pays the 50 silver", 1, true) and out.flag
            and #m.owed == 2 and m.card and m.card.punches == 5 and m.left == 0
            and #m2.owed == 0 and m2.card == nil and m2.left == 12
        return ok, string.format("sold %s, synced %s/%s, left %s then %s; 300s pays 2 owed + a card: %s", tostring(out.card ~= nil),
            tostring(out.fromZennit), tostring(out.fromAnyone), tostring(out.left), tostring(out.after), tostring(m.card ~= nil))
    end)
end)

add("silver is a tab, not a veto: the summons counts, Zennit names the price, and the amount travels with the answer", function()
    local R, Sy = ST.Respond, ST.Sync
    local a = newClient("Alpha")
    local out = {}
    local id = cast(a, 960, true, { target = "Zennit", assistants = {} })
    with(a, function()
        local ev = a.db.events[id]
        -- he asks 200 silver: the summons still lands, and the tab is 200
        ev.response = { result = "owed", zroll = 0, sroll = 0, time = BASE + 970, amount = 200 }
        out.lands = ST.Store.Lands(ev)
        out.describe = R.Describe(ev)
        out.amount = R.AmountOf(ev.response)
        out.default = R.AmountOf({ result = "owed" })
        out.line = R.Announce(ev, ev.response)
        local rid, back = Sy.Decode(Sy.Encode(id, ev))
        out.wire = back and back.response and back.response.amount == 200 and back.response.result == "owed"
        -- an amount on an answer that asks for none is refused
        local rec = Sy.Encode(id, ev):gsub("owed:0:0:" .. (BASE + 970) .. ":0:200", "accepted:0:0:" .. (BASE + 970) .. ":0:200")
        out.refused = select(2, Sy.Decode(rec))
        local rec2 = Sy.Encode(id, ev):gsub(":0:200$", ":0:0")
        out.zero = select(2, Sy.Decode(rec2))
    end)
    local parse = R.ParseSilver
    local ok = out.lands and out.describe == "owes 200 silver" and out.amount == 200 and out.default == 50
        and out.line:find("200 silver", 1, true) and out.line:find("The summons counts", 1, true) and out.wire
        and out.refused == "response" and out.zero == "response"
        and parse("50") == 50 and parse("2g") == 200 and parse("1g 20s") == 120 and parse("30s") == 30 and parse("0") == nil
        and parse("abc") == nil and parse("100001") == nil
    return ok, string.format("lands %s, %s, wire %s, parse 2g=%s", tostring(out.lands), tostring(out.describe), tostring(out.wire), tostring(parse("2g")))
end)

add("the tab as a statement: per payer for Zennit, and only your own for a caster", function()
    local D = 86400
    local base = 100 * 7 * D
    local function ev(caster, at, result, amount, target)
        return { caster = caster, target = target or "Zennit", assistants = {}, time = at,
            response = { result = result, zroll = 0, sroll = 0, time = at + 1, amount = amount } }
    end
    local events = {
        a = ev("Bo-Realm", base + 10, "owed", 200), b = ev("Bo", base + D, "owed", 50), c = ev("Bo", base + 2 * D, "paid", 150),
        d = ev("Cy", base + 20, "owed", 50), e = ev("Di", base + 30, "paid", 50), f = ev("Al", base + 40, "accepted"),
        g = ev("Bo", base + 50, "owed", 999, "Someone"),                       -- not a summons of Zennit
        h = { caster = "Bo", target = "Zennit", assistants = {}, time = base + 60, fake = true,
            response = { result = "owed", zroll = 0, sroll = 0, time = base + 61, amount = 999 } },
    }
    local ctx = { isZennit = function(n) return n == "Zennit" end, name = function(n) return (n:gsub("%-.*", "")) end,
        amount = function(r) return r.amount or 50 end }
    local all = ST.Silver.Statement(events, ctx)
    local mine = ST.Silver.Statement(events, ctx, "Bo-Realm")
    local nobody = ST.Silver.Statement({}, ctx)
    local none = ST.Silver.Statement(events, ctx, "Al")
    local text = table.concat(all.lines, " | ")
    local ok = all.owed == 300 and text:find("The tab: 300 silver owed to Zennit, 200 paid so far", 1, true)
        and text:find("The Index has Bo down for 250 silver on 2 summons", 1, true) and text:find("The Index has Cy down for 50 silver on 1 summons", 1, true)
        and text:find("The Index has Di down for nothing now, with 50 silver paid so far", 1, true) and not text:find("999", 1, true)
        and all.lines[2]:find("^The Index has Bo down for") and mine.lines[1]:find("The Index has you down for 250 silver on 2 summons", 1, true)
        and mine.lines[1]:find("150 paid so far", 1, true) and #mine.lines == 1
        and nobody.lines[1] == "The Index has nobody down for anything." and none.lines[1] == "The Index has you down for nothing."
    return ok, text:sub(1, 120)
end)

add("season titles: who leads what, named, with Zennit's kind ones, and the figures the badges read", function()
    local W = 7 * 86400
    local base = 100 * W
    local function ev(week, n, caster, helpers, result, z, sr, extra)
        local t = base + week * W + n * 60
        local r = result and { result = result, zroll = z or 0, sroll = sr or 0, time = t + 30 } or nil
        for k, v in pairs(extra or {}) do r[k] = v end
        return { caster = caster, target = "Zennit", assistants = helpers or {}, time = t, points = 3, response = r }
    end
    local events = {
        e1 = ev(0, 1, "Al", { "Cy", "Di" }, "lost", 45, 52), e2 = ev(0, 2, "Al", { "Cy", "Di" }, "lost", 45, 52),   -- both tipped
        e3 = ev(1, 3, "Al", { "Cy" }, "accepted"), e4 = ev(2, 4, "Al", {}, "accepted"), e10 = ev(3, 5, "Al", {}, "accepted"),
        e5 = ev(0, 6, "Bo", {}, "won", 90, 10), e6 = ev(0, 7, "Bo", {}, "won", 90, 10), e7 = ev(0, 8, "Bo", {}, "won", 90, 10),
        e9 = ev(0, 9, "Bo", {}, "paid", 0, 0, { amount = 150 }),
        e8 = ev(0, 10, "Cy", {}, "owed", 0, 0, { amount = 500 }),
    }
    local ctx = { isZennit = function(n) return n == "Zennit" end, name = function(n) return n end,
        bonus = function(e) return math.min(#(e.assistants or {}), 2) * 5 end, edge = function() return 10 end,
        resolve = ST.Respond.Resolve, silver = 50, helpersMax = 2 }
    local d = ST.Ledger.Collect(events, 0, math.huge, ctx)
    local titles = ST.Ledger.Titles(d)
    local by = {}
    for _, t in ipairs(titles) do by[t.id] = t end
    local ok = by.heaviest and by.heaviest.text == "The Heaviest Hand: Al, with 5 summons of him." and by.heaviest.next == "Bo is next with 4"
        and by.support and by.support.text:find("The Best Supporting Role: Cy, who helped 3 times", 1, true) and by.support.next == "Di is next with 2"
        and by.lucky and by.lucky.text:find("The Lucky Pair: Cy and Di, whose bonus tipped 2 rolls", 1, true)
        and by.payer and by.payer.text:find("The Prompt Payer: Bo, who paid 150 silver", 1, true)
        and by.goblin and by.goblin.text:find("3 times in a row", 1, true)
        and by.bargain and by.bargain.text:find("asked Cy for 500 silver", 1, true)
        and by.quick and by.quick.text:find("within 30 seconds", 1, true)
        and d.by.Al.weekCount == 4 and d.by.Al.owed == 0 and d.by.Bo.paid == 150 and d.by.Cy.owed == 500
        and d.by.Al.tipped == 2 and d.by.Bo.tipped == 0
    local keep = table.concat(ST.Ledger.Keepsake(1, { start = base + W, side = "group", from = base }, d), " ")
    ok = ok and keep:find("The Heaviest Hand", 1, true) and keep:find("The Dice Goblin", 1, true)
    -- too little to name anyone: no titles
    local few = ST.Ledger.Titles(ST.Ledger.Collect({ x = ev(0, 1, "Al", {}, "accepted") }, 0, math.huge, ctx))
    return ok and #few == 0, string.format("%d titles; Al: %d weeks, tipped %d", #titles, d.by.Al.weekCount, d.by.Al.tipped)
end)

add("the Monday tip: they go round without repeating, once a week, and can be switched off", function()
    local W = ST.Week
    local a = newClient("Alpha")
    local printed, realPrint = {}, ST.print
    local out = {}
    local ok, err = pcall(function()
        with(a, function()
            local seen, prev, repeated = {}, nil, false
            for _ = 1, #W.TIPS * 2 do
                local tip = W.NextTip()
                if tip == prev then repeated = true end
                prev = tip
                seen[tip] = (seen[tip] or 0) + 1
            end
            out.repeated, out.seen = repeated, 0
            for _ in pairs(seen) do out.seen = out.seen + 1 end
            ST.print = function(text) printed[#printed + 1] = text end
            a.db.settings.tipSeen = nil
            W.AnnounceTip()
            W.AnnounceTip()                       -- the same week: nothing more
            out.once = #printed
            a.db.settings.tipSeen = nil
            a.db.settings.tipsOff = true
            W.AnnounceTip()                       -- switched off: nothing
            out.off = #printed
            out.line = printed[1]
        end)
    end)
    ST.print = realPrint
    if not ok then return false, "ERROR " .. tostring(err) end
    local good = not out.repeated and out.seen >= 2 and out.once == 1 and out.off == 1 and out.line and out.line:find("Tip:", 1, true)
    return good, string.format("%d different tips in a round, printed %d then %d, %s", out.seen, out.once, out.off, tostring(out.line))
end)

add("the week's clock in the player's time, a last call in the final day, and /sc week login says them again", function()
    return newRules(function()
        local W = ST.Week
        local a = newClient("Alpha")
        local printed, realPrint, realTime, savedCall = {}, ST.print, time, W.RULES.lastCall
        local out = {}
        local ok, err = pcall(function()
            with(a, function()
                local start = W.Start()
                W.RULES.lastCall = 24 * 3600
                a.db.events.x = { caster = "Alpha", target = "Zennit", assistants = {}, time = start + 60, points = 3, kind = "zone",
                    response = { result = "accepted", zroll = 0, sroll = 0, time = start + 90 } }
                ST.print = function(text) printed[#printed + 1] = text end
                out.closes, out.answers = W.ClosesText(start)
                rawset(_G, "time", function() return start + 7 * 86400 - 3 * 3600 end)      -- three hours before the week closes
                out.left = W.LastCall()
                out.status = W.StatusLine(start)
                out.brief = W.Briefing("Zennit")
                W.AnnounceClock()
                W.AnnounceClock()                                                            -- once a week
                out.printed = table.concat(printed, " | ")
                out.seen = ST.Check.Status("s-lastcall")                                     -- the live check marks itself
                local errors = #ST.errors
                W.Replay()                                                                   -- /sc week login: said again
                out.replayed = select(2, table.concat(printed, " | "):gsub("closes this week on", ""))
                out.replayErrors = #ST.errors - errors
                rawset(_G, "time", function() return start + 2 * 86400 end)                  -- early in the week: no last call
                out.early = W.LastCall()
                out.earlyStatus = W.StatusLine(start)
                out.card = table.concat(W.RulesCard(start), "\n")
            end)
        end)
        rawset(_G, "time", realTime)
        ST.print = realPrint
        W.RULES.lastCall = savedCall
        if not ok then return false, "ERROR " .. tostring(err) end
        local start = W.Start()
        local good = out.closes == date("%A %H:%M", start + 7 * 86400) and out.answers == date("%A %H:%M", start + 9 * 86400)
            and out.left == 3 * 3600 and out.status:find("the week closes in 3 hours", 1, true)
            and out.brief:find("Last call: the Index closes the week in 3 hours (" .. out.closes .. ")", 1, true)
            and out.printed:find("The Index closes this week on " .. out.closes .. ", your time", 1, true)
            and out.printed:find("Last call:|r the Index closes the week in 3 hours", 1, true)
            and select(2, out.printed:gsub("closes this week on", "")) == 1 and select(2, out.printed:gsub("Last call", "")) == 1
            and out.early == nil and not out.earlyStatus:find("closes in", 1, true)
            and out.card:find("this week closes " .. out.closes .. ", your time", 1, true)
            and out.seen == "pass" and out.replayed == 2 and out.replayErrors == 0
        return good, string.format("closes %s, answers until %s; %s; s-lastcall %s, replayed %s, %s errors", tostring(out.closes),
            tostring(out.answers), tostring(out.status), tostring(out.seen), tostring(out.replayed), tostring(out.replayErrors))
    end)
end)

local guardRuns = 0
add("errors are caught and said once, kept for /sc errors, and a failing step does not stop the next", function()
    local printed, realPrint, realHandler = {}, ST.print, geterrorhandler
    local saved = ST.errors
    ST.errors = {}
    ST.print = function(text) printed[#printed + 1] = text end
    geterrorhandler = function() return function() end end                     -- the deliberate "boom" must not reach the game's error window
    local ran = false
    local bad = function() error("boom") end
    guardRuns = guardRuns + 1 -- a problem is said once a session, so each run of the tests needs a step of its own
    local step = guardRuns == 1 and "the first step" or ("the first step (run " .. guardRuns .. ")")
    local ok1, msg1 = ST.Guard(step, bad)
    local ok1b = ST.Guard(step, bad)                                            -- the same again: kept, not said again
    local ok2, value = ST.Guard("the second step", function() ran = true return "fine" end)
    local safe = ST.Safe("an event", function(a, b) return a + b end)
    local sum = select(2, safe(2, 3))
    ST.print, geterrorhandler = realPrint, realHandler
    local kept, said = #ST.errors, #printed
    local first = ST.errors[1]
    ST.errors = saved
    local good = ok1 == false and ok1b == false and msg1:find("boom", 1, true) and ok2 == true and value == "fine" and ran
        and sum == 5 and kept == 2 and said == 1 and first and first.name == step and printed[1]:find("/sc errors", 1, true)
    return good, string.format("kept %d, said %d, second step ran %s", kept, said, tostring(ran))
end)

add("a friend on another version is noticed (major and minor, once), and a patch is not", function()
    local note = ST.Sync.VersionNote
    local older = note("Bo", "0.18.0", "0.19.1")
    local newer = note("Bo", "0.20.0", "0.19.1")
    local patch = note("Bo", "0.19.0", "0.19.1")
    local same = note("Bo", "0.19.1", "0.19.1")
    local junk = note("Bo", "banana", "0.19.1")
    -- the hello carries the version: a client on another one is noticed once and the sync goes on
    local a, b = newClient("Alpha"), newClient("Beta")
    local result, again
    with(a, function()
        local body = string.format("%d|%d|%s|%d|%d", 0, 0, "0.18.0", 0, 0)
        result = Sync.OnMessage("1~H~" .. body, "PARTY", "Beta")
        again = Sync.OnMessage("1~H~" .. body, "PARTY", "Beta")
    end)
    local good = older and older:find("ask them to update", 1, true) and newer and newer:find("newer than your", 1, true)
        and patch == nil and same == nil and junk == nil and result and result:find("version", 1, true) and not again:find("version", 1, true)
    return good, tostring(older)
end)

add("the last die: said once, for everyone, when his third die is spent", function()
    return newRules(function()
        local a = newClient("Alpha")
        local W = ST.Week
        local out = {}
        with(a, function()
            local this = W.Start()
            local function put(n, result)
                a.db.events["d" .. n] = { caster = "Alpha", target = "Zennit", assistants = {}, time = this + n * 60, points = 3,
                    response = { result = result, zroll = 50, sroll = 40, time = this + n * 60 + 1 } }
            end
            put(1, "won"); put(2, "accepted")
            out.second = W.LastDie(a.db.events.d1)           -- two dice left: nothing to say
            put(3, "lost"); put(4, "won")
            out.third = W.LastDie(a.db.events.d4)            -- the third die: the line, for the group
            out.you = W.LastDie(a.db.events.d4, true)        -- and in his words
            out.plain = W.LastDie(a.db.events.d2)            -- an accepted summon is not a die
        end)
        local ok = out.second == nil and out.plain == nil and out.third and out.third:find("last die")
            and out.you and out.you:find("your last die")
        return ok, string.format("second die %s, third die %s, accepted %s", tostring(out.second), tostring(out.third ~= nil),
            tostring(out.plain))
    end)
end)

add("catch-up: the season's lead moves his dice edge toward the side that is behind, and never below zero", function()
    return newRules(function()
        local a = newClient("Alpha")
        local W, R = ST.Week, ST.Respond
        local out = {}
        with(a, function()
            local this = W.Start()
            -- weeks are won two apart, so his weeks off (the week after each of his wins) do not swallow the next win
            local function win(weeksAgo, side, key)
                local at = this - weeksAgo * 7 * 86400 + 3600
                a.db.events[key] = { caster = "Alpha", target = "Zennit", assistants = {}, time = at, points = 3, kind = "zone",
                    response = side == "zennit" and { result = "won", zroll = 90, sroll = 10, time = at + 5 }
                        or { result = "accepted", zroll = 0, sroll = 0, time = at + 5 } }
            end
            out.level = select(2, W.Edge(this))
            win(4, "zennit", "z1")
            out.one = select(2, W.Edge(this))                  -- Zennit ahead by one win: nothing yet
            win(6, "zennit", "z2")
            out.two = { W.Edge(this) }                         -- ahead by two: his edge shrinks by 5
            win(8, "zennit", "z3")
            win(10, "zennit", "z4")
            out.far = { W.Edge(this) }                         -- far ahead: shrinks by 10, to zero, not below
            for k in pairs(a.db.events) do a.db.events[k] = nil end
            for n = 1, 3 do win(2 * n + 2, "group", "g" .. n) end
            out.group = { W.Edge(this) }                       -- the group ahead by three: his edge grows by 10
            W.RULES.from = math.huge
            out.old = { W.Edge(this) }                         -- old rules: no catch-up
            W.RULES.from = 0
        end)
        -- the dice use it: 55+edge against 60 is won at +10 and lost at 0 (a tie is his)
        local dice = R.Resolve(55, 60, 0, 10) == "won" and R.Resolve(55, 60, 0, 0) == "lost" and R.Resolve(60, 60, 0, 0) == "won"
        local ok = out.level == 0 and out.one == 0 and out.two[1] == 5 and out.two[2] == -5 and out.far[1] == 0
            and out.far[2] == -10 and out.group[1] == 20 and out.group[2] == 10 and out.old[1] == 10 and out.old[2] == 0 and dice
        return ok, string.format("edge: level %s, ahead 1 %s, ahead 2 %s, far ahead %s, group ahead %s, old rules %s",
            tostring(out.level), tostring(out.one), tostring(out.two[1]), tostring(out.far[1]), tostring(out.group[1]),
            tostring(out.old[1]))
    end)
end)

add("where the week stands: the lead, a tie, Zennit's wording, and the briefing as a ritual on him begins", function()
    return newRules(function()
        local W, a = ST.Week, newClient("Alpha")
        local out = {}
        with(a, function()
            local this = W.Start()
            local function put(key, n, pts) -- a summon of Zennit this week
                a.db.events[key] = { caster = "Alpha", target = "Zennit", assistants = {}, time = this + 60 * n, points = pts, kind = "zone" }
            end
            out.empty, out.emptyYou = W.StatusLine(this), W.StatusLine(this, true) -- only his head start of 2
            out.first = W.Briefing("Zennit", 1436, "Sentinel Hill")                  -- nothing filed yet: the full briefing
            put("a", 1, 2)
            out.tie = W.StatusLine(this)
            put("b", 2, 3)
            out.ahead = W.StatusLine(this)
            out.brief = W.Briefing("Zennit", 1436, "Sentinel Hill")
            out.notHim = W.Briefing("Bob")
            W.RULES.from = math.huge
            out.old, out.oldBrief = W.StatusLine(this), W.Briefing("Zennit")
            W.RULES.from = 0
        end)
        local ok = out.empty == "Week: Zennit leads by 2, 0 of 10 filed, 3 dice left."
            and out.emptyYou == "Week: you lead by 2, 0 of 10 filed, 3 dice left, 1 free decline left."
            and out.tie == "Week: it is level, and a tie goes to Zennit, 1 of 10 filed, 3 dice left."
            and out.ahead == "Week: the group leads by 3, 2 of 10 filed, 3 dice left."
            and out.first:find("each helper adds +5 to your roll", 1, true) and out.first:find("summon 1 of 10 this week", 1, true)
            and out.brief ~= nil and out.brief:find("Summoning Zennit: summon 3 of 10, the group leads by 3, 3 dice left. From here", 1, true) ~= nil
            and not out.brief:find("each helper adds", 1, true) and #out.brief < #out.first
            and out.notHim == nil and out.old == nil and out.oldBrief == nil
        return ok, string.format("%s | %s | %s | %s", tostring(out.empty), tostring(out.tie), tostring(out.ahead), tostring(out.brief))
    end)
end)

add("a newcomer's first summons of Zennit gets the full briefing, whatever day it is; their second does not", function()
    return newRules(function()
        local W, a = ST.Week, newClient("Alpha")
        local out = {}
        with(a, function()
            local this = W.Start()
            local function put(key, caster, at) -- a summon of Zennit
                a.db.events[key] = { caster = caster, target = "Zennit", assistants = {}, time = at, points = 3, kind = "zone" }
            end
            put("a", "Bob", this + 60); put("b", "Cara", this + 120)                     -- the week is under way, by others
            out.newcomer = W.FirstCast()
            out.first = W.Briefing("Zennit", 1436, "Sentinel Hill")
            put("c", "Alpha", this - 3 * 86400)                                           -- Alpha cast one last week
            out.again = W.FirstCast()
            out.later = W.Briefing("Zennit", 1436, "Sentinel Hill")
        end)
        local ok = out.newcomer == true and out.again == false
            and out.first:find("summon 3 of 10 this week", 1, true) and out.first:find("each helper adds +5 to your roll", 1, true)
            and out.first:find("/sc writ (2 left)", 1, true)
            and not out.later:find("each helper adds", 1, true) and #out.later < #out.first
        return ok, string.format("%s | %s", tostring(out.first), tostring(out.later))
    end)
end)

add("the welcome says taking part needs nothing new, who needs the addon, and where the rules are; the rules card says who needs it", function()
    local party, zennit = ST.Intro.WelcomeLines(false), ST.Intro.WelcomeLines(true)
    local card = ""
    newRules(function() card = table.concat(ST.Week.RulesCard(), "\n") return true end)
    local p, z = table.concat(party, " "), table.concat(zennit, " ")
    local ok = #party == 3 and #zennit == 3
        and p:find("cast and click portals as usual", 1, true) and z:find("answer summons in the game's own prompt", 1, true)
        and p:find("filed if the caster or Zennit has Summon Core", 1, true) and z:find("filed if the caster or Zennit has Summon Core", 1, true)
        and p:find("/sc rules", 1, true) and p:find("/sc intro", 1, true)
        and card:find("Who needs Summon Core: the caster or Zennit", 1, true)
    return ok, party[1]
end)

add("a record carries a writ in an 11th field, and the old 10-field record still reads", function()
    local ev = { caster = "Alpha", target = "Zennit", assistants = {}, mapID = 1436, subzone = "Sentinel Hill", time = BASE + 5,
        wrote = BASE + 5, confirmed = true }
    local id = "Alpha-" .. (BASE + 5)
    local plain = Sync.Encode(id, ev)
    ev.writ = true
    local marked = Sync.Encode(id, ev)
    ev.response = { result = "refused", zroll = 0, sroll = 0, time = BASE + 9 }
    local answered = Sync.Encode(id, ev)
    local _, a = Sync.Decode(plain)
    local _, b = Sync.Decode(marked)
    local _, c = Sync.Decode(answered)
    local tooLong = select(2, Sync.Decode(marked .. "|x|y"))
    local badFlag = select(2, Sync.Decode((marked:gsub("|w$", "|q"))))
    local ok = a and a.writ == nil and b and b.writ == true and b.response == nil and c and c.writ == true
        and c.response.result == "refused" and tooLong == "fields" and badFlag == "writ" and not plain:find("|w", 1, true)
    return ok, string.format("plain %s, marked %s, tooLong %s, badFlag %s", tostring(a and a.writ), tostring(b and b.writ),
        tostring(tooLong), tostring(badFlag))
end)

add("writs: two a week count, the rest do not, and none in his week off or under the old rules", function()
    return newRules(function()
        local a, W, out = newClient("Alpha"), ST.Week, {}
        with(a, function()
            local this = W.Start()
            local function put(key, n, writ)
                a.db.events[key] = { caster = "Alpha", target = "Zennit", assistants = {}, time = this + 60 * n, points = 3,
                    kind = "zone", writ = writ or nil }
            end
            out.none = W.WritsLeft(this)
            put("a", 1, true)
            out.one = W.WritsLeft(this)
            put("b", 2)
            put("c", 3, true)
            put("d", 4, true)
            out.zero = W.WritsLeft(this)
            local e = a.db.events
            out.counts = table.concat({ tostring(W.WritCounts(e.a)), tostring(W.WritCounts(e.b)), tostring(W.WritCounts(e.c)),
                tostring(W.WritCounts(e.d)) }, " ")
            W.RULES.from = math.huge
            out.old = W.WritsLeft(this)
            W.RULES.from = 0
        end)
        local ok = out.none == W.RULES.writs and out.one == W.RULES.writs - 1 and out.zero == 0
            and out.counts == "true false true false" and out.old == 0
        return ok, string.format("left %s, %s, %s; counts %s; old rules %s", tostring(out.none), tostring(out.one), tostring(out.zero),
            tostring(out.counts), tostring(out.old))
    end)
end)

add("what he presses at the game's own prompt is his answer: accept, a free decline, then a decline costs, and a writ always costs", function()
    return newRules(function()
        local a, R, S, G, W, out = newClient("Zennit"), ST.Respond, ST.Store, ST.Gag, ST.Week, {}
        local realMe, realIs = S.me, G.IsZennit
        S.me = function() return "Zennit" end
        G.IsZennit = function() return true end
        local ok, err = pcall(with, a, function()
            local now = time()
            local this = W.Start(now)
            local function put(key, age, caster, writ)
                a.db.events[key] = { caster = caster, target = "Zennit", assistants = {}, time = now - age, points = 3, kind = "zone",
                    writ = writ or nil }
            end
            local function result(key) return a.db.events[key].response and a.db.events[key].response.result end
            out.free0 = W.DeclinesLeft(this)
            put("acc", 60, "Alpha");   out.acc = R.Real("accept", "Alpha")
            put("w1", 50, "Cy", true); put("w2", 49, "Di", true); put("w3", 48, "Ed", true)   -- the third writ of the week does not count
            out.w3 = R.Real("decline", "Ed")                  -- the first decline of the week: free
            out.free1 = W.DeclinesLeft(this)
            put("dec", 40, "Bo");      out.dec = R.Real("decline", "Bo")                      -- the free one is used: this costs
            out.w1 = R.Real("decline", "Cy")                  -- a writ always costs
            put("old", 400, "Gus");    out.stale = R.Real("decline", "Gus")
            put("mm", 5, "Hal");       out.mismatch = R.Real("accept", "Zed")
            put("nn", 1, "Ian");       out.newest = R.Real("accept", nil)
            out.again = R.Real("accept", "Alpha")             -- already answered
            out.results = table.concat({ tostring(result("acc")), tostring(result("w3")), tostring(result("dec")),
                tostring(result("w1")), tostring(result("old")), tostring(result("mm")), tostring(result("nn")) }, " ")
            out.w3Lands, out.w3Goal = S.Lands(a.db.events.w3), S.Goal(a.db.events.w3)
            out.decLands, out.decGoal = S.Lands(a.db.events.dec), S.Goal(a.db.events.dec)
            out.status = W.StatusLine(this, true)
            out.seen = table.concat({ ST.Check.Status("d-accept"), ST.Check.Status("d-decline"), ST.Check.Status("d-cost"),
                (ST.Check.Status("d-writ")) }, " ")
            G.IsZennit = function() return false end
            out.notHim = R.Real("accept", "Hal")
        end)
        S.me, G.IsZennit = realMe, realIs
        if not ok then return false, "ERROR " .. tostring(err) end
        local good = out.free0 == 1 and out.free1 == 0 and out.acc and out.acc.result == "accepted"
            and out.w3 and out.w3.result == "declined" and out.dec and out.dec.result == "refused"
            and out.w1 and out.w1.result == "refused" and out.stale == nil and out.mismatch == nil
            and out.newest and out.newest.result == "accepted" and out.again == nil
            and out.results == "accepted declined refused refused nil nil accepted"
            and not out.w3Lands and out.w3Goal == 0 and not out.decLands and out.decGoal == -3
            and out.status:find("0 free declines left", 1, true) and out.notHim == nil and out.seen == "pass pass pass pass"
        return good, tostring(out.results)
    end)
end)

add("a record Zennit's client files for a caster without the addon: carried by sync, only from him, and only of himself", function()
    local t = BASE + 50
    local ev = { caster = "Wally", target = "Zennit", assistants = { "Cy" }, mapID = 1436, subzone = "Sentinel Hill", time = t,
        wrote = t, confirmed = false, by = "Zennit" }
    local id = "Zennit-" .. t
    local rec = Sync.Encode(id, ev)
    local did, dev = Sync.Decode(rec)
    local plainID, plain = Sync.Decode(Sync.Encode("Alpha-" .. t, { caster = "Alpha", target = "Zennit", assistants = {}, time = t,
        wrote = t, confirmed = true }))
    local notHim = Sync.Decode(Sync.Encode("Bob-" .. t, { caster = "Wally", target = "Zennit", assistants = {}, time = t, wrote = t,
        confirmed = true, by = "Bob" }))                                                  -- only the target may file one
    local wrongID = Sync.Decode(Sync.Encode("Wally-" .. t, ev))                          -- the id must start with who filed it
    ev.writ = true
    local _, withWrit = Sync.Decode(Sync.Encode(id, ev))
    ev.writ = nil
    local w, z = newClient("Wally"), newClient("Ann")
    local fromHim, fromOther, toCaster
    with(z, function()
        fromHim = Sync.Merge(did, select(2, Sync.Decode(rec)), "Zennit", true)
        fromOther = Sync.Merge("Zennit-" .. (t + 1), select(2, Sync.Decode(Sync.Encode("Zennit-" .. (t + 1), ev))), "Wally", true)
    end)
    with(w, function() toCaster = Sync.Merge(did, select(2, Sync.Decode(rec)), "Zennit", true) end) -- the caster accepts it
    local ok = did == id and dev and dev.by == "Zennit" and dev.caster == "Wally" and dev.assistants[1] == "Cy"
        and plainID and plain.by == nil and notHim == nil and wrongID == nil and withWrit and withWrit.writ and withWrit.by == "Zennit"
        and fromHim == "added" and fromOther == "rejected:sender" and toCaster == "added"
    return ok, string.format("decoded %s by %s; from him %s, from another %s, at the caster %s", tostring(did),
        tostring(dev and dev.by), tostring(fromHim), tostring(fromOther), tostring(toCaster))
end)

add("a witness's note of a ritual: who cast it, on whom, the helpers and the place, read back whole or not at all", function()
    local note = { caster = "Wally", target = "Zennit", helpers = { "Cy", "Di" }, mapID = 1436, subzone = "Sentinel Hill",
        time = BASE + 9, helping = true }
    local back = Sync.DecodeWitness(Sync.EncodeWitness(note), "Cy")
    local blank = Sync.DecodeWitness(Sync.EncodeWitness({ helpers = {}, time = BASE, subzone = "" }), "Cy")
    local bad = Sync.DecodeWitness("Wally|Zennit|Cy|x|Hill|5|1", "Cy")
    local short = Sync.DecodeWitness("Wally|Zennit", "Cy")
    local ok = back and back.caster == "Wally" and back.target == "Zennit" and #back.helpers == 2 and back.mapID == 1436
        and back.subzone == "Sentinel Hill" and back.helping and back.from == "Cy"
        and blank and blank.caster == nil and blank.target == nil and bad == nil and short == nil
    return ok, back and (back.caster .. " helped by " .. table.concat(back.helpers, ",")) or "no note"
end)

add("who cast a summons with no record: the prompt's name, else a witness, else the only warlock; helpers only from a witness", function()
    local R = ST.Respond
    local notes = {
        { caster = "Wally", target = "Zennit", helpers = { "Cy", "Di", "Wally" }, mapID = 1451, subzone = "Cenarion Hold", helping = true },
        { caster = "Vic", target = "Zennit", helpers = { "Ed" }, subzone = "Elsewhere" },
        { caster = "Wally", target = "Bob", helpers = { "Fay" } },                       -- a ritual on someone else
    }
    local here = { mapID = 1436, subzone = "Sentinel Hill" }
    local named = R.Witnessed({ me = "Zennit", kind = "accept", summoner = "Wally", notes = notes, here = here, at = 5 })
    local declined = R.Witnessed({ me = "Zennit", kind = "decline", summoner = "Wally", notes = notes, here = here, area = "Silithus", at = 5 })
    local hidden = R.Witnessed({ me = "Zennit", kind = "accept", notes = notes, here = here, at = 5 })
    local lone = R.Witnessed({ me = "Zennit", kind = "decline", warlock = "Xan", here = here, area = "Westfall", at = 5 })
    local nobody = R.Witnessed({ me = "Zennit", kind = "accept", here = here, at = 5 })
    local ok = named.caster == "Wally" and table.concat(named.assistants, ",") == "Cy,Di" and named.mapID == 1436 and named.confirmed
        and named.by == "Zennit" and named.time == 5
        and declined.mapID == 1451 and declined.subzone == "Cenarion Hold"
        and hidden.caster == "Wally"
        and lone.caster == "Xan" and #lone.assistants == 0 and lone.mapID == nil and lone.subzone == "Westfall" and not lone.confirmed
        and nobody.caster == "Unknown"
    return ok, string.format("%s with %s; declined at %s; lone %s; nobody %s", named.caster, table.concat(named.assistants, ","),
        tostring(declined.subzone), tostring(lone.caster), tostring(nobody.caster))
end)

add("his client files a summons nobody logged, answers it, and hands the answer over when the caster's record turns up", function()
    return newRules(function()
        local a, R, S, G, out = newClient("Zennit"), ST.Respond, ST.Store, ST.Gag, {}
        local realMe, realIs, realLater, realPrint = S.me, G.IsZennit, R.later, ST.print
        S.me = function() return "Zennit" end
        G.IsZennit = function() return true end
        R.later = function(fn) fn() end                                                  -- no waiting in the test
        ST.print = function() end
        local ok, err = pcall(with, a, function()
            local now = time()
            Sync.AddWitness({ caster = "Wally", target = "Zennit", helpers = { "Cy" }, time = now - 10, subzone = "Hill", helping = true })
            R.SetPrompt(now - 3, "Westfall")
            out.waits = R.Real("decline", "Wally")                                       -- nothing from Wally: it looks again, then files
            for id, ev in pairs(a.db.events) do if ev.by == "Zennit" then out.id, out.ev = id, ev end end
            out.first = out.ev and out.ev.response
            out.again = R.Real("decline", "Wally")                                       -- the same prompt again: nothing more to file
            local count = 0
            for _ in pairs(a.db.events) do count = count + 1 end
            out.count = count
            -- Wally's own record arrives late
            local wid = "Wally-" .. (now - 4)
            a.db.events[wid] = { caster = "Wally", target = "Zennit", assistants = {}, time = now - 4, points = 3, kind = "zone" }
            out.adopted = R.Adopt(wid, a.db.events[wid])
            out.moved = a.db.events[wid].response and a.db.events[wid].response.result
            out.gone = out.id and a.db.events[out.id] == nil and a.db.deleted and a.db.deleted[out.id] ~= nil
            out.none = R.Adopt(wid, a.db.events[wid])                                    -- nothing left to adopt
        end)
        S.me, G.IsZennit, R.later, ST.print = realMe, realIs, realLater, realPrint
        R.SetPrompt(nil, nil)
        if not ok then return false, "ERROR " .. tostring(err) end
        local good = out.waits == nil and out.first and out.first.result == "declined" and out.ev and out.ev.caster == "Wally"
            and out.ev.assistants[1] == "Cy" and out.ev.subzone == "Hill" and out.id:sub(1, 7) == "Zennit-"
            and out.again == nil and out.count == 1 and out.adopted == true and out.moved == "declined" and out.gone and out.none == false
        return good, string.format("filed %s for %s (%s), adopted %s, moved %s", tostring(out.id), tostring(out.ev and out.ev.caster),
            tostring(out.first and out.first.result), tostring(out.adopted), tostring(out.moved))
    end)
end)

add("one rule for no, in the game or on the form: free on his list or with his free decline, else it costs; a writ always costs", function()
    return newRules(function()
        local a, R, W, out = newClient("Zennit"), ST.Respond, ST.Week, {}
        local ok, err = pcall(with, a, function()
            local now = time()
            a.db.settings.zennitList = { "Westfall" }
            local function put(key, age, subzone, writ)
                a.db.events[key] = { caster = "Al", target = "Zennit", assistants = {}, time = now - age, points = 3, kind = "zone",
                    subzone = subzone or "Goldshire", writ = writ or nil }
                return a.db.events[key]
            end
            local plain, listed, writOnList = put("p", 50), put("l", 40, "Westfall Farms"), put("w", 30, "Westfall Farms", true)
            out.plainFree, out.listFree, out.writList = R.NoResult(plain), R.NoResult(listed), R.NoResult(writOnList)
            out.textFree = R.NoText(plain)
            a.db.events.used = { caster = "Bo", target = "Zennit", assistants = {}, time = now - 60, points = 3, kind = "zone",
                response = { result = "declined", zroll = 0, sroll = 0, time = now - 55 } }          -- his free decline is spent
            out.plainCost, out.listStill = R.NoResult(plain), R.NoResult(listed)
            out.textCost, out.textWrit = R.NoText(plain), R.NoText(writOnList)
            out.d1 = R.Describe({ points = 3, response = { result = "refused" } })
            out.d2 = R.Describe({ points = 3, response = { result = "excused" } })
            out.d3 = R.Describe({ points = 3, response = { result = "declined" } })
        end)
        if not ok then return false, "ERROR " .. tostring(err) end
        local good = out.plainFree == "declined" and out.listFree == "excused" and out.writList == "refused"
            and out.plainCost == "refused" and out.listStill == "excused"
            and out.textFree:find("Declining is free", 1, true) and out.textCost:find("costs you 3 points", 1, true)
            and out.textWrit:find("writ", 1, true)
            and out.d1 == "declined (cost him 3)" and out.d2 == "declined (free: his list)" and out.d3 == "declined (free)"
        return good, string.format("free %s, list %s, writ on list %s; spent: %s, list %s", tostring(out.plainFree), tostring(out.listFree),
            tostring(out.writList), tostring(out.plainCost), tostring(out.listStill))
    end)
end)

add("his list is set for the week: a place added counts from next Monday, an old entry at once, and a removal at once", function()
    local a, R, W, out = newClient("Zennit"), ST.Respond, ST.Week, {}
    local ok, err = pcall(with, a, function()
        local now = time()
        local start = W.Start(now)
        a.db.settings.zennitList = { "Westfall" }                                        -- an entry from before the rule: counts at once
        out.old = R.OnList({ subzone = "Westfall Farms", time = now })
        R.ListAdd("Silithus")                                                            -- added with a summons on screen
        out.now = R.OnList({ subzone = "Silithus", time = now })
        out.nextWeek = R.OnList({ subzone = "Silithus", time = start + 7 * 86400 + 60 })
        out.lastWeek = R.OnList({ subzone = "Silithus", time = start - 60 })            -- not backwards either
        out.pending = R.ListPending("Silithus")
        out.active = #R.ListActive(now)
        R.ListRemove(1)
        out.removed = R.OnList({ subzone = "Westfall Farms", time = now })
    end)
    if not ok then return false, "ERROR " .. tostring(err) end
    local good = out.old == true and out.now == false and out.nextWeek == true and out.lastWeek == false and out.pending == true
        and out.active == 1 and out.removed == false
    return good, string.format("old %s, added now %s, next week %s, removed %s", tostring(out.old), tostring(out.now),
        tostring(out.nextWeek), tostring(out.removed))
end)

add("the briefing says when a writ can bite: while his free decline is left, else only at a place on his list", function()
    return newRules(function()
        local W, a, out = ST.Week, newClient("Alpha"), {}
        with(a, function()
            local now = time()
            out.fresh = W.Briefing("Zennit", 1436, "Sentinel Hill")
            out.armed = W.Briefing("Zennit", 1436, "Sentinel Hill", true)
            out.card = table.concat(W.RulesCard(), "\n")
        end)
        local b = newClient("Alpha")                                                        -- his free decline is spent this week
        out.now = time()
        with(b, function()
            local now = out.now
            b.db.events.d = { caster = "Bo", target = "Zennit", assistants = {}, time = now - 60, points = 3, kind = "zone",
                response = { result = "declined", zroll = 0, sroll = 0, time = now - 50 } }
            out.spentArmed = W.Briefing("Zennit", 1436, "Sentinel Hill", true)
            out.spentFirst = W.Briefing("Zennit", 1436, "Sentinel Hill")                  -- Alpha's first ever: the long one
        end)
        local good = out.fresh:find("/sc writ (2 left) makes a decline of this one cost him.", 1, true)
            and out.armed:find("A writ is played: if he declines this summons in the game, it costs him 3 points.", 1, true)
            and out.spentArmed:find("His free decline is used, so it only bites if this place is on his list: then a decline costs him 3 points.", 1, true)
            and out.spentFirst:find("His free decline is used: a writ (/sc writ, 2 left) only bites if this place is on his list.", 1, true)
            and out.card:find("Once his free decline is used, a writ only bites at a place on his list.", 1, true)
            and out.card:find("set for the week", 1, true)
        return good, tostring(out.spentFirst)
    end)
end)

add("postcards: the first landed summons of him to each far-flung place in a season, once, in the keepsake, and what is still missing", function()
    return newRules(function()
        local a, L, out = newClient("Alpha"), ST.Ledger, {}
        with(a, function()
            local now = time()
            local function put(key, age, mapID, result)
                a.db.events[key] = { caster = "Al", target = "Zennit", assistants = {}, time = now - age, mapID = mapID, subzone = "",
                    points = 10, kind = "remote", response = result and { result = result, zroll = 0, sroll = 0, time = now - age + 5 } or nil }
                return a.db.events[key]
            end
            local declined = put("x", 50, 1451, "declined")                                -- he did not go: no postcard
            local first = put("a", 40, 1451, "accepted")
            local again = put("b", 30, 1451, "accepted")                                   -- Silithus again: no second postcard
            local moon = put("c", 20, 1450, "owed")
            out.declined = L.PostcardFor(declined, nil)
            out.first = L.PostcardFor(first, nil)
            out.again = L.PostcardFor(again, nil)
            out.moon = L.PostcardFor(moon, nil)
            moon.response = { result = "paid", zroll = 0, sroll = 0, time = now }
            out.paid = L.PostcardFor(moon, { result = "owed" })                            -- paid later: it had landed already
            out.zone = L.PostcardFor(put("z", 10, 1436, "accepted"), nil)                  -- not far-flung
            out.count = #L.Postcards()
            out.line = L.PostcardsLine(L.Facts())
            out.missing, out.short = L.MissingLine(L.Facts()), L.MissingLine(L.Facts(), true)
        end)
        local good = out.declined == nil and out.first and out.first:find("in Silithus: 'Sand.", 1, true)
            and out.first:find("Stamped: 1 of 10", 1, true) and out.again == nil and out.moon and out.moon:find("2 of 10", 1, true)
            and out.paid == nil and out.zone == nil and out.count == 2
            and out.line == "Postcards from Zennit: Silithus and Moonglade (2 of 10)."
            and out.missing and out.missing:find("Still no postcard from: Azshara, Blasted Lands", 1, true)
            and not out.missing:find("Silithus", 1, true) and not out.missing:find("Moonglade", 1, true)
            and out.short == "Still no postcard from: Azshara, Blasted Lands, Burning Steppes and 5 more. The Index has stamps."
        return good, tostring(out.first)
    end)
end)

add("his own lines: a postcard and an out-of-office, sent only by him, the newest kept, and used in place of ours", function()
    return newRules(function()
        local z, a, W, L, out = newClient("Zennit"), newClient("Alpha"), ST.Week, ST.Ledger, {}
        local realIs, realOff = ST.Gag.IsZennit, W.IsOff
        local ok, err = pcall(function()
            with(z, function()
                ST.Gag.IsZennit = function() return true end
                out.set = Sync.SetLine("pc:1451", "Sand |cffff0000again|r.")                  -- escape codes are taken out
                out.away = Sync.SetLine("away", "Gone fishing. Do not summon.")
                out.bad = Sync.SetLine("pc:1436", "Not far-flung")                            -- not a far-flung place
                ST.Gag.IsZennit = realIs
            end)
            local sent = {}
            for _, m in ipairs(z.state.queue) do if m.payload:find("~L~", 1, true) then sent[#sent + 1] = m.payload end end
            out.sent = #sent
            with(a, function()
                for _, p in ipairs(sent) do out.got = Sync.OnMessage(p, "PARTY", "Zennit") end
                out.fromOther = Sync.OnMessage(sent[1], "PARTY", "Bob")
                out.older = Sync.OnMessage("1~L~away|5|old", "PARTY", "Zennit")
                out.badKey = Sync.OnMessage("1~L~pc:1436|" .. (time() + 5) .. "|x", "PARTY", "Zennit")
                out.line = Sync.ZennitLine("pc:1451")
                local now = time()
                a.db.events.s = { caster = "Al", target = "Zennit", assistants = {}, time = now - 30, mapID = 1451, subzone = "",
                    points = 10, kind = "remote", response = { result = "accepted", zroll = 0, sroll = 0, time = now - 20 } }
                out.postcard = L.PostcardFor(a.db.events.s, nil)
                W.IsOff = function() return true end
                out.brief = W.Briefing("Zennit")
                W.IsOff = realOff
                Sync.PutLine("away", "", time() + 10)                                       -- cleared: the Index's line again
                W.IsOff = function() return true end
                out.cleared = W.Briefing("Zennit")
                W.IsOff = realOff
            end)
        end)
        ST.Gag.IsZennit, W.IsOff = realIs, realOff
        if not ok then return false, "ERROR " .. tostring(err) end
        local good = out.set and out.away and not out.bad and out.sent == 2 and out.got == "stored"
            and out.fromOther == "rejected:sender" and out.older == "kept" and out.badKey == "bad"
            and out.line == "Sand cffff0000againr." and out.postcard and out.postcard:find("in Silithus: 'Sand cffff0000againr.'", 1, true)
            and out.brief:find("His out-of-office says: 'Gone fishing. Do not summon.'", 1, true)
            and out.cleared:find("still earns a postcard", 1, true) and not out.cleared:find("out-of-office", 1, true)
        return good, string.format("%s | %s", tostring(out.postcard), tostring(out.brief))
    end)
end)

add("his week off: summons of him disturb his leave, the briefing says what still counts, and the Index counts who did it", function()
    return newRules(function()
        local a, W, L, out = newClient("Alpha"), ST.Week, ST.Ledger, {}
        local realPrint = ST.print
        local printed = {}
        local ok, err = pcall(with, a, function()
            local this = W.Start()
            local last = this - 7 * 86400
            local function put(key, caster, at, resp)
                a.db.events[key] = { caster = caster, target = "Zennit", assistants = {}, time = at, points = 3, kind = "zone",
                    response = resp }
                return a.db.events[key]
            end
            put("won", "Cy", last + 3600, { result = "won", zroll = 90, sroll = 10, time = last + 3700 })    -- he won last week
            put("o1", "Al", this + 3600); put("o2", "Al", this + 7200); put("o3", "Bo", this + 9000)
            out.brief = W.Briefing("Zennit")
            ST.print = function(text) printed[#printed + 1] = text end
            W.Warn(a.db.events.o3)
            ST.print = realPrint
            out.facts = L.Facts()
            out.line = L.LeaveLine(out.facts)
            out.describe = W.Describe(W.Score(this))
            out.why = select(2, W.Why(this))
        end)
        ST.print = realPrint
        if not ok then return false, "ERROR " .. tostring(err) end
        local good = out.brief:find("disturbing his leave: it will not count for the race, but a far-flung place still earns a postcard", 1, true)
            and printed[1] and printed[1]:find("disturbing his leave (3 this week)", 1, true)
            and out.facts.leave.n == 3 and out.line == "The Index notes that his leave was disturbed 3 times; Al did it most (2)."
            and out.describe:find("his leave disturbed 3 times", 1, true) and out.why == "disturbing his leave"
        return good, string.format("%s | %s", tostring(out.line), tostring(printed[1]))
    end)
end)

add("away from his keyboard: an AFK that began well before the summons files it as away, free; a fresh /afk does not", function()
    return newRules(function()
        local a, R, S, G, W, out = newClient("Zennit"), ST.Respond, ST.Store, ST.Gag, ST.Week, {}
        local realMe, realIs, realAFK, realLater, realPrint = S.me, G.IsZennit, R.isAFK, R.later, ST.print
        S.me = function() return "Zennit" end
        G.IsZennit = function() return true end
        R.isAFK = function() return true end
        R.later = function(fn) fn() end
        ST.print = function() end
        local ok, err = pcall(with, a, function()
            local now = time()
            local function put(key, age)
                a.db.events[key] = { caster = "Al", target = "Zennit", assistants = {}, time = now - age, points = 3, kind = "zone" }
                return a.db.events[key]
            end
            put("fresh", 2)
            R.SetPrompt(now - 2, "Westfall")
            R.SetAFK(now - 60)                                                              -- /afk a minute ago: not honoured
            out.fresh = R.FileAway("Al")
            R.SetAFK(now - 600)                                                             -- away ten minutes: honoured
            out.away = R.FileAway("Al")
            local ev = a.db.events.fresh
            out.lands, out.goal = S.Lands(ev), S.Goal(ev)
            out.free = W.DeclinesLeft(W.Start(now))
            out.describe = R.Describe(ev)
            out.announce = R.Announce(ev, ev.response)
            local _, back = Sync.Decode(Sync.Encode("Al-" .. ev.time, ev))
            out.wire = back and back.response and back.response.result
            out.brief = W.Briefing("Zennit", 1436, "Sentinel Hill", false, true)
            R.isAFK = function() return false end                                           -- he came back before the check
            put("back", 1)
            out.back = R.FileAway("Al")
        end)
        S.me, G.IsZennit, R.isAFK, R.later, ST.print = realMe, realIs, realAFK, realLater, realPrint
        R.SetPrompt(nil, nil)
        R.SetAFK(nil)
        if not ok then return false, "ERROR " .. tostring(err) end
        local good = out.fresh == nil and out.away and out.away.result == "away" and not out.lands and out.goal == 0
            and out.free == W.RULES.declines and out.describe == "away from his keyboard (free)"
            and out.announce:find("was away from his keyboard", 1, true) and out.wire == "away"
            and out.brief:find("Zennit is away from his keyboard", 1, true) and out.back == nil
        return good, string.format("fresh %s, away %s, free declines %s, wire %s", tostring(out.fresh),
            tostring(out.away and out.away.result), tostring(out.free), tostring(out.wire))
    end)
end)

add("watching together: a chapter shown to the group, asked of those who reached it, and offered when the raid gathers", function()
    return newRules(function()
        local a, I, W, out = newClient("Alpha"), ST.Intro, ST.Week, {}
        local realAsk, realOnWatch, realPlay, realPrint = I.ask, Sync.onWatch, I.Play, ST.print
        local realRaid, realLeader = IsInRaid, UnitIsGroupLeader
        local asked, played, watched = {}, {}, {}
        I.ask = function(text, onAccept) asked[#asked + 1] = text onAccept() end
        I.Play = function(key) played[#played + 1] = key end
        ST.print = function() end
        local ok, err = pcall(with, a, function()
            local this = W.Start()
            local last = this - 7 * 86400
            a.db.events.g = { caster = "Alpha", target = "Zennit", assistants = {}, time = last + 3600, points = 10, kind = "remote",
                response = { result = "accepted", zroll = 0, sroll = 0, time = last + 3700 } }                  -- the group won last week
            out.key = I.LastWeeksChapter()
            Sync.onWatch = function(sender, key) watched[#watched + 1] = sender .. ":" .. key end
            out.party = Sync.OnMessage("1~V~g1", "PARTY", "Bo")
            out.guild = Sync.OnMessage("1~V~g1", "GUILD", "Bo")
            out.bad = Sync.OnMessage("1~V~x9", "PARTY", "Bo")
            Sync.onWatch = realOnWatch
            out.reached = I.OnWatch("Bo", "g1")
            out.notReached = I.OnWatch("Bo", "g2")                                             -- not reached here yet: Bo's client checked
            out.unwritten = I.OnWatch("Bo", "g9")
            rawset(_G, "IsInRaid", function() return true end)
            rawset(_G, "UnitIsGroupLeader", function() return true end)
            I.RaidGathered()
            I.RaidGathered()                                                                   -- once a week
        end)
        I.ask, Sync.onWatch, I.Play, ST.print = realAsk, realOnWatch, realPlay, realPrint
        rawset(_G, "IsInRaid", realRaid)
        rawset(_G, "UnitIsGroupLeader", realLeader)
        if not ok then return false, "ERROR " .. tostring(err) end
        local good = out.key == "g1" and out.party == "asked" and watched[1] == "Bo:g1" and out.guild == "rejected:channel"
            and out.bad == "bad" and out.reached == true and out.notReached == true and out.unwritten == false
            and asked[1] and asked[1]:find("Bo would like to show the group chapter 3", 1, true)
            and asked[2] and asked[2]:find("chapter 5", 1, true)
            and asked[3] and asked[3]:find("The raid has gathered. Last week unlocked chapter 3", 1, true) and asked[4] == nil
            and played[1] == "g1" and played[2] == "g2"
        return good, string.format("key %s; asked: %s", tostring(out.key), tostring(asked[3]))
    end)
end)

add("previously on: this season's chapters in the order the race reached them, or a word when there are none", function()
    return newRules(function()
        local a, b, I, W, out = newClient("Alpha"), newClient("Beta"), ST.Intro, ST.Week, {}
        local realPlay, realPrint = I.Play, ST.print
        local played, printed = {}, {}
        I.Play = function(key) played[#played + 1] = key end
        ST.print = function(text) printed[#printed + 1] = text end
        local ok, err = pcall(function()
            with(a, function()
                local this = W.Start()
                local function week(n, key, result)                                         -- a summons in the week n weeks ago
                    local at = this - n * 7 * 86400 + 3600
                    a.db.events[key] = { caster = "Alpha", target = "Zennit", assistants = {}, time = at, points = 10, kind = "remote",
                        response = { result = result, zroll = 90, sroll = 10, time = at + 60 } }
                end
                week(4, "w1", "accepted")                                                   -- the group wins: g1
                week(3, "w2", "won")                                                        -- Zennit wins: z1
                week(2, "w3", "accepted")                                                   -- his week off: nobody wins
                week(1, "w4", "accepted")                                                   -- the group wins: g2
                out.keys = I.SeasonSoFar()
                out.started = I.PreviouslyOn()
            end)
            with(b, function() out.none = I.PreviouslyOn() end)
        end)
        I.Play, ST.print = realPlay, realPrint
        if not ok then return false, "ERROR " .. tostring(err) end
        local good = table.concat(out.keys, ",") == "g1,z1,g2" and played[1] == "g1" and out.started and #out.started == 3
            and printed[1] and printed[1]:find("3 chapters of this season, back to back", 1, true)
            and out.none == nil and printed[2] and printed[2]:find("Nothing has happened this season yet", 1, true)
        return good, string.format("keys %s, played %s", table.concat(out.keys or {}, ","), tostring(played[1]))
    end)
end)

add("feelings: one answer a week, sent to everyone, kept and counted only by Zennit's and the admin's clients, never named", function()
    return newRules(function()
        local p, adm, other, F, W, out = newClient("Alpha"), newClient("Admin"), newClient("Bo"), ST.Feelings, ST.Week, {}
        local realIs, realAdmin, realAccount, realAsk, realPrint = ST.Gag.IsZennit, ST.IsAdmin, ST.IsAdminAccount, F.ask, ST.print
        local asked = {}
        F.ask = function(week) asked[#asked + 1] = week end
        ST.print = function() end
        local ok, err = pcall(function()
            local last = W.Start() - 7 * 86400
            with(p, function()
                p.db.events.x = { caster = "Alpha", target = "Zennit", assistants = {}, time = last + 60, points = 3, kind = "zone" }
                F.Check(); F.Check()                                                        -- asked once a week
                F.Answer(last, 1)
                out.mine = p.db.settings.feelMine[last] and p.db.settings.feelMine[last].n
            end)
            local sent
            for _, m in ipairs(p.state.queue) do if m.payload:find("~F~", 1, true) then sent = m.payload end end
            ST.IsAdmin, ST.IsAdminAccount = function() return true end, function() return true end
            with(adm, function()
                out.kept = Sync.OnMessage(sent, "PARTY", "Alpha")
                out.again = Sync.OnMessage("1~F~" .. last .. "|p|2", "PARTY", "Alpha")      -- a later answer replaces it
                out.bob = Sync.OnMessage("1~F~" .. last .. "|p|3", "PARTY", "Bo")
                out.fake = Sync.OnMessage("1~F~" .. last .. "|z|3", "PARTY", "Bo")          -- only Zennit answers as Zennit
                out.zen = Sync.OnMessage("1~F~" .. last .. "|z|1", "PARTY", "Zennit")
                out.summary = table.concat(F.Summary(4), " ")
            end)
            ST.IsAdmin, ST.IsAdminAccount = function() return false end, function() return false end
            ST.Gag.IsZennit = function() return false end
            with(other, function()
                out.ignored = Sync.OnMessage(sent, "PARTY", "Alpha")
                out.hidden = F.Summary(4)
                other.db.settings.feelOff = true
                out.off = F.Due()
            end)
        end)
        ST.Gag.IsZennit, ST.IsAdmin, ST.IsAdminAccount, F.ask, ST.print = realIs, realAdmin, realAccount, realAsk, realPrint
        if not ok then return false, "ERROR " .. tostring(err) end
        local good = #asked == 1 and out.mine == 1 and out.kept == "kept" and out.again == "kept" and out.bob == "kept"
            and out.fake == "rejected:role" and out.zen == "kept"
            and out.summary:find("0 good fun, 1 it was fine, 1 not for me; Zennit: bring it on.", 1, true)
            and not out.summary:find("Alpha", 1, true) and not out.summary:find("Bo", 1, true)
            and out.ignored == "ignored" and out.hidden == nil and out.off == nil
        return good, tostring(out.summary)
    end)
end)

add("titles for being a good sport and for clever writs: the Good Sport and the Process Server", function()
    return newRules(function()
        local a, L, W, out = newClient("Alpha"), ST.Ledger, ST.Week, {}
        local ok, err = pcall(with, a, function()
            local this = W.Start()
            local n = 0
            local function put(caster, result, mapID, points, writ, weeksAgo)
                n = n + 1
                local at = this - (weeksAgo or 0) * 7 * 86400 + n * 600
                a.db.events["e" .. n] = { caster = caster, target = "Zennit", assistants = {}, time = at, mapID = mapID, subzone = "",
                    points = points or 3, kind = "zone", writ = writ or nil, response = { result = result, zroll = 0, sroll = 0, time = at + 30 } }
            end
            for i = 1, 8 do put("Bo", "accepted", nil, 3, nil, 1) end                      -- last week: he went eight times
            put("Bo", "accepted", 1451, 10, nil, 1)                                         -- and to Silithus
            put("Cy", "owed", nil, 3)                                                        -- this week: a tenth, with silver named
            put("Al", "refused", 1436, 3, true)                                              -- two writs that bit
            put("Al", "refused", 1451, 10, true)
            put("Cy", "refused", nil, 3)                                                     -- a costed decline with no writ
            out.titles = L.Titles(L.Collect(a.db.events, 0, math.huge, L.Context()))
            a.db.events.e10 = nil                                                            -- nine: not yet
            out.fewer = L.Titles(L.Collect(a.db.events, 0, math.huge, L.Context()))
        end)
        if not ok then return false, "ERROR " .. tostring(err) end
        local by, fewer = {}, {}
        for _, t in ipairs(out.titles) do by[t.id] = t.text end
        for _, t in ipairs(out.fewer) do fewer[t.id] = true end
        local good = by.sport == "The Good Sport: Zennit, who went where he was sent 10 times, including Silithus."
            and by.server == "The Process Server: Al, whose writs cost him 13 points." and not fewer.sport
        return good, string.format("%s | %s", tostring(by.sport), tostring(by.server))
    end)
end)

add("the live checklist: well-formed, records results, marks what it sees, and says what to send back", function()
    local C = ST.Check
    local ids, bad, kinds = {}, {}, { auto = true, solo = true, duo = true }
    for _, c in ipairs(C.LIST) do
        if ids[c.id] then bad[#bad + 1] = "duplicate " .. c.id end
        ids[c.id] = true
        if not (c.title and kinds[c.kind]) then bad[#bad + 1] = "malformed " .. c.id end
        if c.kind == "auto" and type(c.run) ~= "function" then bad[#bad + 1] = "no run " .. c.id end
        if c.kind ~= "auto" and not (c.steps and #c.steps > 0 and c.expect) then bad[#bad + 1] = "no steps " .. c.id end
    end
    for _, id in ipairs({ "d-accept", "d-decline", "d-cost", "d-writ", "d-dice-ends", "d-name" }) do -- the ids the addon marks itself
        if not ids[id] then bad[#bad + 1] = "missing " .. id end
    end
    local env = { C_Map = { GetMapInfo = function() end }, hooksecurefunc = function() end, C_SummonInfo = { ConfirmSummon = function() end } }
    local missing = C.Missing({ "C_SummonInfo.ConfirmSummon", "C_SummonInfo.CancelSummon", "hooksecurefunc", "C_Map.GetMapInfo", "Nope.Nothing" }, env)
    local a, out = newClient("Alpha"), {}
    with(a, function()
        out.plain = C.Plain("|cffff4444FAIL|r a-hooks: the hook |cff33ff66fired|r")
        out.next1 = C.Next()
        out.todo = C.Status("a-api")
        out.good, out.err = C.Record("a-api", "pass", "fine"), select(2, C.Record("nope", "pass"))
        out.badStatus = select(2, C.Record("a-api", "maybe"))
        out.pass = C.Status("a-api")
        C.Seen("d-accept", "first")
        C.Seen("d-accept", "second")
        out.note = a.db.checks["d-accept"].note
        C.Record("s-popup", "pass")
        out.next2 = C.Next()
        out.sum = C.Summary()
        C.Record("d-cost", "fail", "free decline wrong")
        local n = C.Counts()
        out.counts = string.format("%d %d", n.pass, n.fail)
        for i = 1, 50 do ST.Trace("t" .. i) end
        out.trace = #ST.trace
        out.report = table.concat(C.ReportText(), "\n")
    end)
    local ok = #bad == 0 and #missing == 2 and missing[1] == "C_SummonInfo.CancelSummon" and missing[2] == "Nope.Nothing"
        and out.plain == "FAIL a-hooks: the hook fired" and out.next1 == "s-popup" and out.next2 == "s-key" and out.sum == "3/" .. #C.LIST
        and out.todo == "todo" and out.good and out.err:find("no such check", 1, true) and out.badStatus:find("pass, fail or skip", 1, true)
        and out.pass == "pass" and out.note == "seen live: first" and out.counts == "3 1" and out.trace == 40
        and out.report:find("FAIL d-cost: ", 1, true) and out.report:find("free decline wrong", 1, true) and out.report:find("Trace (newest last)", 1, true)
        and out.report:find("PASS a-api: ", 1, true) and out.report:find("-- fine", 1, true)
    return ok, table.concat(bad, "; ") .. " " .. tostring(out.counts)
end)

add("the game's prompt ends a dice roll in flight: one answer per summons, and no die is spent", function()
    return newRules(function()
        local a, R, S, G, W, out = newClient("Zennit"), ST.Respond, ST.Store, ST.Gag, ST.Week, {}
        local realMe, realIs = S.me, G.IsZennit
        S.me = function() return "Zennit" end
        G.IsZennit = function() return true end
        local ok, err = pcall(with, a, function()
            local now = time()
            local this = W.Start(now)
            local function put(key, age, caster)
                a.db.events[key] = { caster = caster, target = "Zennit", assistants = {}, time = now - age, points = 3, kind = "zone" }
            end
            local function result(key) return a.db.events[key].response and a.db.events[key].response.result end
            put("d1", 20, "Jo")
            R.StartDice("d1", 40)                                   -- a roll is in flight
            out.accepted = R.Real("accept", "Jo")                   -- he accepts in the game meanwhile
            R.OnDiceReply("d1", a.db.events.d1, 5)                  -- the summoner's roll comes back: too late
            put("d2", 10, "Kay")
            R.StartDice("d2", 90)
            out.declined = R.Real("decline", "Kay")                 -- he declines in the game: his free decline
            R.OnDiceReply("d2", a.db.events.d2, 5)
            out.results = result("d1") .. " " .. result("d2")
            out.diceLeft = W.DiceLeft(this)                         -- no die was spent
            out.seen = ST.Check.Status("d-dice-ends")
        end)
        S.me, G.IsZennit = realMe, realIs
        if not ok then return false, "ERROR " .. tostring(err) end
        local good = out.accepted and out.accepted.result == "accepted" and out.declined and out.declined.result == "declined"
            and out.results == "accepted declined" and out.diceLeft == W.RULES.dice and out.seen == "pass"
        return good, string.format("%s, dice left %s", tostring(out.results), tostring(out.diceLeft))
    end)
end)

add("the briefing says what the place is worth: both sides of the stakes, and a city is worth less than his head start", function()
    return newRules(function()
        local W, a = ST.Week, newClient("Alpha")
        local out = {}
        with(a, function()
            out.zone = W.Briefing("Zennit", 1436, "Sentinel Hill")
            out.remote = W.Briefing("Zennit", 1451, "Cenarion Hold")
            out.city = W.Briefing("Zennit", 1453, "Trade District")
            out.dungeon = W.Briefing("Zennit", 1451, "The Deadmines")
            out.noPlace = W.Briefing("Zennit")
            out.writ = W.Briefing("Zennit", 1436, "Sentinel Hill", true)
        end)
        local ok = out.zone:find("From here (a zone) the summons is worth 3: his roll could take 3, and so could yours.", 1, true)
            and out.remote:find("(a far-flung place) the summons is worth 10: his roll could take 10", 1, true)
            and out.dungeon:find("(a dungeon entrance) the summons is worth 5", 1, true)
            and out.city:find("(a city) the summons is worth 1, which is less than his head start of 2", 1, true)
            and not out.city:find("his roll could take", 1, true)
            and not out.noPlace:find("From here", 1, true)
            and out.zone:find("/sc writ (2 left) makes a decline of this one cost him.", 1, true)
            and out.writ:find("A writ is played: if he declines this summons in the game, it costs him 3 points.", 1, true)
            and not out.writ:find("/sc writ (", 1, true)
        return ok, tostring(out.remote)
    end)
end)

add("helpers are named when their bonus wins the roll, and only then", function()
    return newRules(function()
        local W, R, a = ST.Week, ST.Respond, newClient("Alpha")
        local out = {}
        with(a, function()
            local ev = { caster = "Alpha", target = "Zennit", assistants = { "Al", "Cy", "Ed" }, time = W.Start() + 60,
                points = 5, kind = "dungeon" }
            local function line(z, sr, result) return R.Announce(ev, { result = result, zroll = z, sroll = sr, time = W.Start() + 61 }) end
            out.tipped = line(55, 58, "lost") -- 65 against 58+10: without the helpers he'd have won
            out.anyway = line(20, 58, "lost") -- 30 against 68: the summoner won without them
            out.won = line(70, 58, "won")
        end)
        local ok = out.tipped:find("Al and Cy's +10 tipped it.", 1, true) ~= nil and not out.anyway:find("tipped", 1, true)
            and not out.won:find("tipped", 1, true)
        return ok, out.tipped
    end)
end)

-- Questions only Zennit's client can answer (Ask.lua): asked over the network, answered by his client alone, whispered back.
add("a question reaches only Zennit's client, which answers it by whisper; off, repeats, strangers and silence are handled", function()
    local A = ST.Ask
    local alpha, zennit, beta = newClient("Alpha"), newClient("Zennit"), newClient("Beta")
    alpha.db.settings.partyTest, beta.db.settings.partyTest = true, true -- ordinary players, even on Zennit's own account
    zennit.db.settings.zenitTest = true
    for _, c in ipairs({ alpha, zennit, beta }) do c.ask = A.newState() end
    local real = { state = A.state, later = A.later, count = A.itemCount, cd = A.cooldownLeft, now = A.now, clock = A.clock }
    local bags, cooldown, timers, got, out = { [A.HEARTHSTONE] = 1 }, 0, {}, {}, {}
    A.itemCount = function(item) return bags[item] or 0 end
    A.cooldownLeft = function() return cooldown end
    A.later = function(_, fn) timers[#timers + 1] = fn end
    A.now = function() return BASE + 7200 end
    A.clock = function() return clock end
    local function on(c, fn) return with(c, function() A.state = c.ask return fn() end) end
    -- settle() runs each client's handlers under with(); point Ask at that client's state for the delivery too
    local realOn = Sync.OnMessage
    Sync.OnMessage = function(text, channel, sender)
        for _, c in ipairs({ alpha, zennit, beta }) do if ST.db == c.db then A.state = c.ask end end
        return realOn(text, channel, sender)
    end
    local function ask(key, arg)
        local qid, why = on(alpha, function() return A.Ask(key, arg, function(r) got[#got + 1] = r end) end)
        settle({ alpha, zennit, beta })
        clock = clock + A.COOLDOWN
        return qid, why
    end
    local ok, err = pcall(function()
        ask("hearth");                     out.ready = got[#got]
        cooldown = 1500; ask("hearth");    out.cd = got[#got]
        bags[A.HEARTHSTONE] = nil; ask("hearth"); out.none = got[#got]
        zennit.db.settings.loginAt = BASE + 7200 - 3900
        ask("playing");                    out.playing = got[#got]
        out.tooSoon = select(2, on(alpha, function()
            A.Ask("playing", nil, function(r) got[#got + 1] = r end)
            return A.Ask("hearth", nil, function(r) got[#got + 1] = r end)
        end))
        settle({ alpha, zennit, beta })
        clock = clock + A.COOLDOWN
        out.unknownKey = select(2, ask("weather"))
        zennit.db.settings.askOff = true; ask("hearth"); out.off = got[#got]
        zennit.db.settings.askOff = nil
        out.answers = #got
        -- the same question by party and by guild is answered once; a second question inside the cooldown is not answered
        local q = "1~Q~Alpha-1-99|hearth|"
        out.first = on(zennit, function() return Sync.OnMessage(q, "PARTY", "Alpha") end)
        out.repeated = on(zennit, function() return Sync.OnMessage(q, "GUILD", "Alpha") end)
        out.rate = on(zennit, function() return Sync.OnMessage("1~Q~Alpha-1-100|hearth|", "PARTY", "Alpha") end)
        clock = clock + A.COOLDOWN
        out.unasked = on(zennit, function() return Sync.OnMessage("1~Q~Alpha-1-101|carries|Linen Cloth", "PARTY", "Alpha") end)
        -- a question in someone else's name, a client that is not his, a reply from a stranger or to nothing, or not whispered
        out.forged = on(zennit, function() return Sync.OnMessage("1~Q~Beta-1-1|hearth|", "PARTY", "Alpha") end)
        out.notHim = on(beta, function() return Sync.OnMessage("1~Q~Alpha-1-102|hearth|", "PARTY", "Alpha") end)
        out.stranger = on(alpha, function() return Sync.OnMessage("1~Y~Alpha-1-1|hearth|ok|ready", "WHISPER", "Beta") end)
        out.nothing = on(alpha, function() return Sync.OnMessage("1~Y~Alpha-1-1|hearth|ok|ready", "WHISPER", "Zennit") end)
        out.open = on(alpha, function() return Sync.OnMessage("1~Y~Alpha-1-1|hearth|ok|ready", "PARTY", "Zennit") end)
        out.badStatus = on(alpha, function() return Sync.OnMessage("1~Y~Alpha-1-1|hearth|maybe|ready", "WHISPER", "Zennit") end)
        -- nobody answers: the timer says so, once
        timers = {}
        local qid = on(alpha, function() return A.Ask("hearth", nil, function(r) got[#got + 1] = r end) end)
        on(alpha, function() for _, fn in ipairs(timers) do fn() end end)
        out.timeout = got[#got]
        out.late = on(alpha, function() return A.OnReply("Zennit", qid, "hearth", "ok", "ready") end)
        -- his own client answers itself, without the network
        local before = #zennit.state.queue
        on(zennit, function() A.Ask("hearth", nil, function(r) out.self = r end) end)
        out.selfSent = #zennit.state.queue - before
    end)
    Sync.OnMessage = realOn
    A.state, A.later, A.itemCount, A.cooldownLeft, A.now, A.clock = real.state, real.later, real.count, real.cd, real.now, real.clock
    if not ok then return false, "ERROR " .. tostring(err) end
    local function is(r, status, value) return r and r.status == status and (value == nil or r.value == value) end
    local good = is(out.ready, "ok", "ready") and out.ready.from == "Zennit"
        and is(out.cd, "ok", "cd:1500") and out.cd.text:find("25 minutes more", 1, true)
        and is(out.none, "ok", "none")
        and is(out.playing, "ok", "3900") and out.playing.text:find("1 hour 5 minutes", 1, true)
        and out.unknownKey == "no such question"
        and out.tooSoon == "one question every 5 seconds: ask again in a moment"
        and is(out.off, "off") and out.answers == 6
        and out.first == "answered:ok" and out.repeated == "ignored:repeat" and out.rate == "ignored:ratelimit"
        and out.unasked == "answered:unasked" and out.forged == "rejected:values" and out.notHim == "ignored"
        and out.stranger == "rejected:sender" and out.nothing == "rejected:unasked" and out.open == "rejected:channel"
        and out.badStatus == "bad" and is(out.timeout, "timeout") and out.late == "rejected:unasked"
        and is(out.self, "ok", "none") and out.selfSent == 0
    return good, string.format("ready %s, cd %s, none %s, playing %s (%s), off %s, %d answers; %s %s %s %s; %s %s %s %s %s %s; %s %s; self %s",
        tostring(out.ready and out.ready.value), tostring(out.cd and out.cd.value), tostring(out.none and out.none.value),
        tostring(out.playing and out.playing.value),
        tostring(out.playing and out.playing.text), tostring(out.off and out.off.status), out.answers or -1,
        tostring(out.first), tostring(out.repeated), tostring(out.rate), tostring(out.unasked), tostring(out.forged),
        tostring(out.notHim), tostring(out.stranger), tostring(out.nothing), tostring(out.open), tostring(out.badStatus),
        tostring(out.timeout and out.timeout.status), tostring(out.late), tostring(out.self and out.self.value))
end)

-- ===== [tests:FILING] filing a summons into the log exactly once =====

-- Runs fn(z) on a scratch client playing Zennit, with his client's seams in place, the new race rules, and the new filing rules
-- (Respond.FILING_FROM) in force unless `from` says otherwise. Returns ok, err.
local function asZennit(fn, from)
    local z, R, S, G, W = newClient("Zennit"), ST.Respond, ST.Store, ST.Gag, ST.Week
    local real = { me = S.me, is = G.IsZennit, later = R.later, print = ST.print, from = R.FILING_FROM, rules = W.RULES.from }
    S.me = function() return "Zennit" end
    G.IsZennit = function() return true end
    R.later = function(f) f() end
    ST.print = function() end
    R.FILING_FROM = from or 0
    W.RULES.from = 0
    local ok, err = pcall(with, z, function() fn(z) end)
    S.me, G.IsZennit, R.later, ST.print, R.FILING_FROM = real.me, real.is, real.later, real.print, real.from
    W.RULES.from = real.rules
    R.SetPrompt(nil, nil)
    return ok, err
end

-- A summons of Zennit his client filed itself for `caster`, answered `result` (as FileWitnessed leaves it).
local function filed(db, caster, t, result)
    local id = "Zennit-" .. t
    db.events[id] = { caster = caster, target = "Zennit", by = "Zennit", assistants = {}, mapID = 1436, subzone = "Sentinel Hill",
        time = t, wrote = t, points = 3, kind = "zone", confirmed = false,
        response = { result = result or "accepted", zroll = 0, sroll = 0, time = t + 5 } }
    return id
end

-- The caster's own record of the same summons, as it comes over the wire.
local function own(caster, t, over)
    local ev = { caster = caster, target = "Zennit", assistants = {}, mapID = 1436, subzone = "Sentinel Hill", time = t, wrote = t,
        confirmed = true }
    for k, v in pairs(over or {}) do ev[k] = v end
    return caster .. "-" .. t, ev
end

add("a caster's record that reaches his client by a batch, or that it already holds, takes over the summons it filed", function()
    local out = {}
    local ok, err = asZennit(function(z)
        local now = time()
        -- by a batch: added
        local fid = filed(z.db, "Wally", now - 30)
        local wid, wev = own("Wally", now - 10)
        z.state.requested["Wally"] = clock
        out.batch = Sync.OnMessage("1~B~" .. Sync.Encode(wid, wev), "WHISPER", "Wally")
        out.batchGone = z.db.events[fid] == nil and Store.IsDeleted(fid)
        out.batchMoved = z.db.events[wid] and z.db.events[wid].response and z.db.events[wid].response.result
        -- already held (merged before his client filed its own, say by an older version): a live copy is kept, and still adopts
        local vid, vev = own("Vic", now - 200)
        z.db.events[vid] = select(2, own("Vic", now - 200))
        local gid = filed(z.db, "Vic", now - 190, "declined")
        out.kept = Sync.OnMessage("1~E~" .. Sync.Encode(vid, vev), "PARTY", "Vic")
        out.keptGone = z.db.events[gid] == nil
        out.keptMoved = z.db.events[vid].response and z.db.events[vid].response.result
        local n = 0
        for _ in pairs(z.db.events) do n = n + 1 end
        out.count = n
    end)
    if not ok then return false, "ERROR " .. tostring(err) end
    local good = out.batch == "added" and out.batchGone and out.batchMoved == "accepted"
        and (out.kept == "kept" or out.kept == "replaced") and out.keptGone and out.keptMoved == "declined" and out.count == 2
    return good, string.format("batch %s (filed gone %s, moved %s); held %s (filed gone %s, moved %s); %d records", tostring(out.batch),
        tostring(out.batchGone), tostring(out.batchMoved), tostring(out.kept), tostring(out.keptGone), tostring(out.keptMoved), out.count or -1)
end)

add("by a batch, a caster's record leaves a closed week, or one before the new filing rules, as it was played", function()
    local out = {}
    local W, realClosed = ST.Week, ST.Week.EventClosed
    local function batch(z, t)
        local fid = filed(z.db, "Wally", t - 20)
        local wid, wev = own("Wally", t)
        z.state.requested["Wally"] = clock
        local res = Sync.OnMessage("1~B~" .. Sync.Encode(wid, wev), "WHISPER", "Wally")
        return res, z.db.events[fid] ~= nil and not z.db.events[wid].response
    end
    local ok, err = asZennit(function(z)
        W.EventClosed = function(ev) return ev.time < time() - 1000 end
        out.closedRes, out.closedLeft = batch(z, time() - 5000)
        out.openRes, out.openLeft = batch(z, time() - 100)
    end)
    W.EventClosed = realClosed
    if not ok then return false, "ERROR " .. tostring(err) end
    local ok2, err2 = asZennit(function(z)
        out.oldRes, out.oldLeft = batch(z, time() - 100)
        -- a live E is adopted as it always was, whatever the week
        local fid = filed(z.db, "Cy", time() - 60)
        local cid, cev = own("Cy", time() - 50)
        Sync.OnMessage("1~E~" .. Sync.Encode(cid, cev), "PARTY", "Cy")
        out.liveGone = z.db.events[fid] == nil
    end, math.huge)
    if not ok2 then return false, "ERROR " .. tostring(err2) end
    local good = out.closedRes == "added" and out.closedLeft and out.openRes == "added" and out.openLeft == false
        and out.oldRes == "added" and out.oldLeft and out.liveGone
    return good, string.format("closed week left %s, open week left %s, before the rules left %s, live adopted %s",
        tostring(out.closedLeft), tostring(out.openLeft), tostring(out.oldLeft), tostring(out.liveGone))
end)

add("after login his client adopts what it filed in the open weeks, nearest first, and leaves closed weeks and others' clients alone", function()
    local out = {}
    local W, realClosed = ST.Week, ST.Week.EventClosed
    local ok, err = asZennit(function(z)
        local now = time()
        W.EventClosed = function(ev) return ev.time < now - 1000 end
        -- an open week: two summons by Wally a minute apart, both filed by his client (the first declined, the second accepted)
        local f1, f2 = filed(z.db, "Wally", now - 120, "declined"), filed(z.db, "Wally", now - 60, "accepted")
        local w1, e1 = own("Wally", now - 115)
        local w2, e2 = own("Wally", now - 58)
        z.db.events[w1], z.db.events[w2] = e1, e2
        -- a closed week: left as it was played
        local f3 = filed(z.db, "Cy", now - 5000)
        local w3, e3 = own("Cy", now - 4990)
        z.db.events[w3] = e3
        out.n = ST.Respond.AdoptAll()
        out.r1 = e1.response and e1.response.result
        out.r2 = e2.response and e2.response.result
        out.gone = z.db.events[f1] == nil and z.db.events[f2] == nil
        out.closed = z.db.events[f3] ~= nil and e3.response == nil
        out.again = ST.Respond.AdoptAll()
        ST.Gag.IsZennit = function() return false end
        out.other = ST.Respond.AdoptAll()
    end)
    W.EventClosed = realClosed
    if not ok then return false, "ERROR " .. tostring(err) end
    local good = out.n == 2 and out.r1 == "declined" and out.r2 == "accepted" and out.gone and out.closed and out.again == 0
        and out.other == 0
    return good, string.format("adopted %s (%s, %s), closed week kept %s, again %s, on another client %s", tostring(out.n),
        tostring(out.r1), tostring(out.r2), tostring(out.closed), tostring(out.again), tostring(out.other))
end)

add("a decline his client filed, moved onto a caster's record with a writ, is decided again and costs him; not before the new rules", function()
    return newRules(function()
        local out = {}
        local function run(writ, from)
            local res = {}
            local ok, err = asZennit(function(z)
                local now = time()
                filed(z.db, "Wally", now - 30, "declined")
                local wid, wev = own("Wally", now - 20, { writ = writ, points = 3, kind = "zone" })
                z.db.events[wid] = wev
                res.adopted = ST.Respond.Adopt(wid, wev)
                res.result = wev.response and wev.response.result
                res.goal = Store.Goal(wev)
            end, from)
            if not ok then error(err, 0) end
            return res
        end
        local okRun, err = pcall(function()
            out.writ = run(true)
            out.plain = run(nil)
            out.old = run(true, math.huge)
        end)
        if not okRun then return false, "ERROR " .. tostring(err) end
        local good = out.writ.adopted and out.writ.result == "refused" and out.writ.goal == -3
            and out.plain.result == "declined" and out.plain.goal == 0 and out.old.result == "declined"
        return good, string.format("writ: %s (%s); none: %s; before the rules: %s", tostring(out.writ.result), tostring(out.writ.goal),
            tostring(out.plain.result), tostring(out.old.result))
    end)
end)

add("a warlock casting again after he declined is filed again; the same prompt, or a form answer, files nothing", function()
    local out = {}
    local R = ST.Respond
    local ok, err = asZennit(function(z)
        local now = time()
        R.SetPrompt(now - 70, nil)
        out.first = R.Real("decline", "Wally", true)                     -- no record from Wally: his client files it, declined
        out.same = R.Real("decline", "Wally", true)                      -- the same prompt again: nothing more
        R.SetPrompt(now, nil)                                        -- Wally casts again; this time he accepts
        out.second = R.Real("accept", "Wally", true)
        local n = 0
        for _ in pairs(z.db.events) do n = n + 1 end
        out.count = n
        -- a summons he answered on the Index's form, then in the game's prompt: the form's answer stands for it
        local vid, vev = own("Vic", now + 1)
        vev.response = { result = "accepted", zroll = 0, sroll = 0, time = now + 2 }
        z.db.events[vid] = vev
        R.SetPrompt(now + 3, nil)
        out.form = R.Real("accept", "Vic", true)
        n = 0
        for _ in pairs(z.db.events) do n = n + 1 end
        out.count2 = n
    end)
    if not ok then return false, "ERROR " .. tostring(err) end
    local good = out.first and out.first.result == "declined" and out.same == nil and out.second and out.second.result == "accepted"
        and out.count == 2 and out.form == nil and out.count2 == 3
    return good, string.format("first %s, same prompt %s, again %s, %d records; form-answered %s, %d records",
        tostring(out.first and out.first.result), tostring(out.same), tostring(out.second and out.second.result), out.count or -1,
        tostring(out.form), out.count2 or -1)
end)

add("the assistants prompt ticks at most two, and no record ever saves more than two, a repeat, the caster or the target", function()
    local P = ST.Prompt
    local three, two = P.PreTicks({ "Cy", "Di", "Ed" }), P.PreTicks({ "Cy", "Di" })
    local nThree = 0
    for _ in pairs(three) do nThree = nThree + 1 end
    local a = newClient("Wally")
    local id, ev = with(a, function()
        local i, e = Store.Add({ caster = "Wally", target = "Zennit", assistants = { "Cy", "Cy", "Wally", "Zennit", "Di", "Ed" },
            mapID = 1436, subzone = "Sentinel Hill", time = BASE + 7, confirmed = true }, true)
        return i, e
    end)
    local back = Sync.Decode(Sync.Encode(id, ev))
    local good = nThree == 0 and two.Cy and two.Di and table.concat(ev.assistants, ",") == "Cy,Di" and back ~= nil
    return good, string.format("three detected tick %d, two tick %s; saved %s; decodes %s", nThree,
        tostring(two.Cy and two.Di), table.concat(ev.assistants, ","), tostring(back ~= nil))
end)

-- Plays a ritual through the detector and the witness with the game's unit calls stood in for: the caster's client (Wally) in a
-- party with Cy and Di, targeting Zennit. Returns what was saved, what the prompt was asked, and any witness note sent.
local function ritual(steps)
    local D, P = ST.Detector, ST.Prompt
    local got = { saved = {}, asked = nil, notes = {} }
    local roster, channeling, target = { "Cy", "Di" }, {}, "Zennit"
    local gt, tickers = 10, {}
    local real = { UnitName = UnitName, UnitExists = UnitExists, UnitChannelInfo = UnitChannelInfo, IsInRaid = IsInRaid,
        GetTime = GetTime, time = time, NewTicker = C_Timer.NewTicker, NewTimer = C_Timer.NewTimer, ask = P.Ask,
        witness = Sync.SendWitness, print = ST.print, me = Store.me, lastCommit = D.lastCommit }
    D.lastCommit = 0 -- our clock starts at 10: a commit made on the real one must not look like a second SUCCEEDED
    local now = real.time()
    rawset(_G, "UnitName", function(u)
        if u == "player" then return "Wally" end
        if u == "target" then return target end
        if u == "party1target" or u == "party2target" then return "Zennit" end
        local i = tonumber((u or ""):match("^party(%d)$"))
        return i and roster[i] or nil
    end)
    rawset(_G, "UnitExists", function(u)
        local i = tonumber((u or ""):match("^party(%d)$"))
        return u == "player" or (i ~= nil and i <= #roster)
    end)
    rawset(_G, "UnitChannelInfo", function(u)
        if channeling[u] then return "Ritual of Summoning", "", 0, 0, 0, false, false, ST.RITUAL_ID end
    end)
    rawset(_G, "IsInRaid", function() return false end)
    rawset(_G, "GetTime", function() return gt end)
    rawset(_G, "time", function(t) if t then return real.time(t) end return now end)
    rawset(C_Timer, "NewTicker", function(_, fn)
        local t = { fn = fn }
        t.Cancel = function() t.dead = true end
        tickers[#tickers + 1] = t
        return t
    end)
    rawset(C_Timer, "NewTimer", function() return { Cancel = function() end } end)
    P.Ask = function(tgt, candidates, pre, onDone) got.asked = { target = tgt, pre = pre, done = onDone } end
    Sync.SendWitness = function(note) got.notes[#got.notes + 1] = note end
    ST.print = function() end
    Store.me = function() return "Wally" end
    local a = newClient("Wally")
    local ctl = {
        channel = function(u, on) channeling[u] = on or nil end,
        target = function(n) target = n end,
        wait = function(s)
            for _ = 1, s * 2 do
                gt, now = gt + 0.5, now + 0.5
                for _, t in ipairs(tickers) do if not t.dead then t.fn() end end
            end
        end,
        sent = function() D.OnCast(nil, "UNIT_SPELLCAST_SENT", "player", "Zennit", "guid", ST.RITUAL_ID) end,
        event = function(event, unit) D.OnCast(nil, event, unit or "player", "guid", ST.RITUAL_ID) end,
        witness = function(event, unit) D.OnWitness(nil, event, unit) end,
        now = function() return now end,
    }
    local ok, err = pcall(with, a, function() steps(ctl, got) end)
    -- whatever happened, the player's own channel ends, so the witness is free again on a real client
    channeling.player = nil
    pcall(with, a, function() D.OnWitness(nil, "UNIT_SPELLCAST_CHANNEL_STOP", "player") end)
    rawset(_G, "UnitName", real.UnitName)
    rawset(_G, "UnitExists", real.UnitExists)
    rawset(_G, "UnitChannelInfo", real.UnitChannelInfo)
    rawset(_G, "IsInRaid", real.IsInRaid)
    rawset(_G, "GetTime", real.GetTime)
    rawset(_G, "time", real.time)
    rawset(C_Timer, "NewTicker", real.NewTicker)
    rawset(C_Timer, "NewTimer", real.NewTimer)
    P.Ask = real.ask
    Sync.SendWitness, ST.print, Store.me = real.witness, real.print, real.me
    D.lastCommit = real.lastCommit
    if not ok then error(err, 0) end
    for _, ev in pairs(a.db.events) do got.saved[#got.saved + 1] = ev end
    return got
end

add("a ritual still channelling after 30 s keeps the target it was cast on and its helpers, and is filed at the time it was cast", function()
    local out = {}
    local got = ritual(function(c, g)
        c.sent()
        c.event("UNIT_SPELLCAST_CHANNEL_START")
        c.channel("player", true)
        c.channel("party1", true)
        c.channel("party2", true)
        c.target("Cy")                                              -- the caster clicks a helper while waiting for clickers
        c.wait(31)
        c.event("UNIT_SPELLCAST_SUCCEEDED")
        out.auto = g.saved and true
        -- a second ritual with one helper: the prompt saves it 20 s later, at the ritual's time
        c.channel("party2", false)
        c.target("Zennit")
        c.wait(10)
        c.sent()
        c.event("UNIT_SPELLCAST_CHANNEL_START")
        c.wait(2)
        out.castAt = c.now()
        c.event("UNIT_SPELLCAST_SUCCEEDED")
        c.wait(20)
        if g.asked then g.asked.done({ "Cy" }, false) end
    end)
    table.sort(got.saved, function(x, y) return x.time < y.time end)
    local first, second = got.saved[1], got.saved[2]
    local good = #got.saved == 2 and first.target == "Zennit" and table.concat(first.assistants, ",") == "Cy,Di" and first.confirmed
        and second.target == "Zennit" and second.time == out.castAt and table.concat(second.assistants, ",") == "Cy"
    return good, string.format("%d saved; first on %s with %s; second at %s (cast %s)", #got.saved, tostring(first and first.target),
        first and table.concat(first.assistants, ",") or "-", tostring(second and second.time), tostring(out.castAt))
end)

add("the target or the caster seen channelling is never credited as an assistant: two helpers with the target among them ask", function()
    local got = ritual(function()
        ST.Detector.Finish({ target = "Zennit", mapID = 1436, subzone = "Sentinel Hill", helpers = { "Cy", "Zennit" } })
    end)
    local pre = got.asked and table.concat(got.asked.pre, ",")
    local good = #got.saved == 0 and pre == "Cy"
    return good, string.format("%d saved without asking; prompt ticks %s", #got.saved, tostring(pre))
end)

add("the caster's own client never sends a witness note naming one of its helpers as the caster; a bystander's still does", function()
    local out = {}
    local got = ritual(function(c, g)
        -- Wally's own ritual, committed as the channel begins; Cy then clicks the portal and stops
        c.sent()
        c.event("UNIT_SPELLCAST_SUCCEEDED")
        c.channel("player", true)
        c.witness("UNIT_SPELLCAST_CHANNEL_START", "player")
        c.wait(10)
        c.channel("party1", true)
        c.witness("UNIT_SPELLCAST_CHANNEL_START", "party1")
        c.channel("party1", false)
        c.witness("UNIT_SPELLCAST_CHANNEL_STOP", "party1")
        c.channel("player", false)
        c.witness("UNIT_SPELLCAST_CHANNEL_STOP", "player")
        out.own = #g.notes
        if g.asked then g.asked.done({}, false) end
        -- later Wally only watches: Cy casts (on Wally's target stand-in), Di clicks, Cy stops
        c.wait(60)
        c.channel("party1", true)
        c.witness("UNIT_SPELLCAST_CHANNEL_START", "party1")
        c.channel("party2", true)
        c.witness("UNIT_SPELLCAST_CHANNEL_START", "party2")
        c.channel("party1", false)
        c.witness("UNIT_SPELLCAST_CHANNEL_STOP", "party1")
    end)
    local note = got.notes[1]
    local good = out.own == 0 and #got.notes == 1 and note.caster == "Cy" and table.concat(note.helpers, ",") == "Di"
    return good, string.format("notes during his own ritual %s; as a bystander %d (caster %s)", tostring(out.own), #got.notes,
        tostring(note and note.caster))
end)

-- ===== [end tests:FILING] =====

function T.Run(quiet)
    realEventClosed, realLateAnswer = ST.Week.EventClosed, ST.Week.LateAnswer
    ST.Week.EventClosed = function() return false end -- the other tests use old summons
    ST.Week.LateAnswer = function() return false end  -- answered now, so every answer to them would be late
    local rulesFrom = ST.Week.RULES.from
    ST.Week.RULES.from = math.huge -- and the old race rules (the new-rules tests switch them on themselves)
    local whims, fixed, overdue = ST.Week.RULES.whims, ST.Voice.fixed, ST.Week.RULES.overdue
    ST.Week.RULES.whims = false -- no whim of the week, and the plain variant of every line: the tests read exact words
    ST.Voice.fixed = true
    ST.Week.RULES.overdue = math.huge -- and nothing is "waiting for his answer" unless a test asks
    local lastCall = ST.Week.RULES.lastCall
    ST.Week.RULES.lastCall = nil     -- nor is a week "about to close"
    local pass = 0
    local results, failed = {}, {}
    for _, t in ipairs(tests) do
        local ok, good, detail = pcall(t.fn)
        if not ok then good, detail = false, "ERROR " .. tostring(good) end
        results[#results + 1] = { name = t.name, ok = good and true or false, detail = detail or "" }
        if good then pass = pass + 1 else failed[#failed + 1] = string.format("%s (%s)", t.name, tostring(detail or ""):sub(1, 120)) end
    end
    for _, r in ipairs(results) do
        if not (quiet and r.ok) then -- quiet: only the failures
            ST.print(string.format("%s %s%s", r.ok and "|cff33ff66PASS|r" or "|cffff4444FAIL|r", r.name,
                r.detail ~= "" and ("  (" .. r.detail .. ")") or ""))
        end
    end
    ST.Week.EventClosed, ST.Week.LateAnswer = realEventClosed, realLateAnswer
    ST.Week.RULES.from = rulesFrom
    ST.Week.RULES.whims, ST.Voice.fixed, ST.Week.RULES.overdue, ST.Week.RULES.lastCall = whims, fixed, overdue, lastCall
    ST.print(string.format("sync self-test: %d/%d passed", pass, #tests))
    return pass, #tests, failed
end
