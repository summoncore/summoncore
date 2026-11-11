-- Ledger: "The Index today", the part of the story that follows the season. The intro's ten fixed scenes are
-- narrated and drawn once; this is the last scene of them, written fresh from the season tree every time it plays:
-- who leads, how far down each trunk the race has got (only chapters already reached, so nothing is spoiled),
-- how the season ended before this one, and how this week stands. Build is pure (state in, sentences out) so it
-- can be tried without the game; State reads the live season.
local ADDON, ST = ...
setfenv(1, ST.env) -- the addon's own globals (Core.lua)
local Ledger = {}
ST.Ledger = Ledger

-- The scene's fixed sentences: no names and no numbers in them, so each one has a recorded clip
-- (Media/ledger/<id>.ogg, with its length in LedgerClips.lua). tools/intro/build_ledger_audio.py renders the clips from
-- this table, so keep every entry a single string on one line. The lines that carry a name or a number are built
-- below and stay typed and silent. The exception is the week's whim: there are four, each a fixed sentence with a rule's
-- number in it (Week.WHIMS), so each is recorded as the whole line; it plays only while the line the scene builds is
-- still word for word that one (see Ledger.WhimClip), and a self-test fails when a rule change makes a recording stale.
local LINES = {
    -- Where each trunk stands after its nth win of the season (the fifth is the finale, told as the last season's end).
    recap_z1 = "Zennit has had his week off, and has not yet decided whether he liked it.",
    recap_z2 = "Zennit holds a brass key to a side door, and has ticked the first item on his list.",
    recap_z3 = "Zennit has found that his list is a syllabus, and is studying it in a corridor, with a kettle.",
    recap_z4 = "The clerk has shown Zennit the desk, and is looking everywhere for his hat.",
    recap_g1 = "The group has had its cake, which Zennit did not trust.",
    recap_g2 = "The group keeps a carbon copy of Form 27B slash 6, and the Index would like it back.",
    recap_g3 = "The Ritual has handed up Form 27B slash 6, after sitting on it beneath a tavern.",
    recap_g4 = "The Ritual has named its price: fifty silver, in cash, and the third copy of the form.",
    -- How the season before this one ended.
    last_zennit = "Last season ended with Zennit in the clerk's chair. He accepts every summons, and the Index has asked him to stop apologising.",
    last_group = "Last season ended with a receipt, and Zennit free. The Index was asked to carry on regardless, and agreed, with misgivings.",
    -- The standing.
    empty_first = "The Index has opened a file on the season, and it is empty. Nobody has won a week.",
    empty_fresh = "The Index has opened a fresh file, and it is empty.",
    wait = "The Index is prepared to wait.",
    -- The pressure.
    end_both = "Both sides are one win from the end. The Index has stopped sleeping.",
    end_group = "The group is one win from the finale, and the Ritual has started to glow in a meaningful manner.",
    end_zennit = "Zennit is one win from the clerk's chair, and the kettle is on.",
    -- This week.
    week_leave = "This week is Zennit's. He is on leave, the race is off, and the Index files any summons as disturbing it.",
    week_closed = "Zennit has closed the Index for the week. Anything more is filed under enthusiasm.",
    week_none = "Nobody has summoned Zennit this week. The Index is patient.",
    evidence = "The Index is accepting further evidence.",
    -- The week's whim, as the scene says it (Week.WHIMS; the numbers are the rules' values with the whim applied).
    whim_distracted = "This week's whim: The Index is distracted. Zennit's edge on the dice is 5 lower this week.",
    whim_attentive = "This week's whim: The Index is attentive. Zennit's edge on the dice is 5 higher this week.",
    whim_feast = "This week's whim: A helpers' feast. Each helper adds +8 to the summoner's roll this week.",
    whim_tired = "This week's whim: The helpers are tired. Each helper adds only +2 to the summoner's roll this week.",
    -- Season two's story (Season2.lua): the same ids with _2 after them, which storyLine looks for first.
    recap_z1_2 = "Zennit is on gardening leave pending audit. He has no garden, and has asked for his file.",
    recap_z2_2 = "Zennit has looked the Auditor up in the Index, and found no such entry.",
    recap_z3_2 = "Zennit has found the bell for audits, a new rope, and a soul shard in the dust.",
    recap_z4_2 = "The Auditor has summoned Zennit from memory, and he recognised the ritual.",
    recap_g1_2 = "The party has been called to give evidence. Poogs sent apologies.",
    recap_g2_2 = "A notebook of summons, in familiar handwriting, has been entered as Exhibit A.",
    recap_g3_2 = "The Ritual has given Zennit a character reference, and greeted the Auditor like an old friend.",
    recap_g4_2 = "The Auditor has asked the party why they keep summoning him. The answer is due.",
    last_zennit_2 = "Last season ended with the Auditor unmasked as Poogs, and entered in the Index under P, in ink.",
    last_group_2 = "Last season ended with Poogs unmasked, a finding of affection, and Zennit holding Form 27B slash 7.",
    end_zennit_2 = "Zennit is one win from closing the audit, and would like the Auditor to spell their name.",
    end_group_2 = "The party is one win from answering the question, and has started rehearsing.",
    empty_fresh_2 = "The audit is open, and its file is empty. Nobody has won a week.",
}
Ledger.LINES = LINES

-- The scene's lines that belong to a season's story (where its trunks stand, how it ended, the pressure near its finale):
-- season one's are in LINES, and so are season two's, with _2 after the id (recap_z1_2). A later season whose lines are not
-- recorded yet has them in ST.seasonLines (Season2.lua), typed and silent. A season with no lines of its own says none of
-- these, rather than season one's. Returns the text and its recording's id.
local STORY = { recap_ = true, last_ = true, end_zennit = true, end_group = true }
local function storyLine(number, id)
    if number <= 1 then return LINES[id], LINES[id] and id or nil end
    local recorded = id .. "_" .. number
    if LINES[recorded] then return LINES[recorded], recorded end
    local own = ST.seasonLines and ST.seasonLines[number]
    if own and own[id] then return own[id], nil end
    if STORY[id] or STORY[id:match("^%a+_")] then return nil end
    return LINES[id], LINES[id] and id or nil -- a line that is the same in every season
end
Ledger.StoryLine = storyLine

-- Spliced lines, like a station announcement: the lines that carry only numbers are said by playing short recordings
-- one after another (Media/ledger/<id>.ogg, lengths in LedgerClips.lua). A phrase's ending sets how it is said: a comma
-- means more follows, a full stop ends the sentence. tools/intro/build_ledger_audio.py renders these too, so keep every
-- entry a single string on one line. The numbers 0 to 99 are fragments of their own (see numberClips); a number outside
-- that, or a name, has no recording and the line is only typed.
local FRAGMENTS = {
    level_at = "The season stands level at",
    week_each = "week each.",
    weeks_each = "weeks each.",
    not_taking_sides = "The Index would like it noted that it is not taking sides.",
    group_leads_season = "The group leads the season,",
    zennit_leads_season = "Zennit leads the season,",
    to = "to",
    nobody_expected = "which nobody expected, least of all Zennit.",
    edge_group_behind = "The Index, which takes no sides, has noticed that the group is behind, and has taken",
    off_dice = "off Zennit's dice this week.",
    edge_zennit_behind = "The Index, which takes no sides, has noticed that Zennit is behind, and has put",
    on_dice = "on his dice this week.",
    this_week = "This week,",
    of = "of",
    summons_filed_and = "summons are filed, and",
    group_leads_by = "the group leads by",
    zennit_leads_by = "Zennit leads by",
    level_tie = "it is level, and a tie is Zennit's.",
    week_group_has = "This week, the group has",
    points_to = "points to Zennit's",
}
Ledger.FRAGMENTS = FRAGMENTS

Ledger.GAP = 0.04   -- seconds between one fragment and the next (their own silence is trimmed)
Ledger.PAUSE = 0.7  -- the "|" part of a splice: a breath between two sentences

-- The recordings that say the whole number n, in order: n<k>c / n<k>f for 0-19, t<k>c / t<k>f for the tens, and a tens word
-- t<k>m followed by its units for the rest. c: more of the sentence follows; f: this ends it. nil beyond 99 (or not a whole number).
local function numberClips(n, final)
    if type(n) ~= "number" or n < 0 or n > 99 or n ~= math.floor(n) then return nil end
    local ending = final and "f" or "c"
    if n < 20 then return { "n" .. n .. ending } end
    local tens, units = math.floor(n / 10) * 10, n % 10
    if units == 0 then return { "t" .. tens .. ending } end
    return { "t" .. tens .. "m", "n" .. units .. ending }
end
Ledger.NumberClips = numberClips

-- Assembles a spoken line from parts and returns its text and the recordings that say it (nil when some part has none).
-- A part is a FRAGMENTS id, a number, "," or "." (appended to the text before it, no recording: the number or phrase
-- before it already carries that ending) or "|" (a breath: silence). A number ends the sentence, and so falls, when it
-- is last or followed by ".". The text is built from the same parts, so what is said and what is shown cannot differ.
function Ledger.Splice(parts)
    local text, clips = "", {}
    for i, part in ipairs(parts) do
        local piece
        if type(part) == "number" then
            piece = string.format("%d", part)
            local say = clips and numberClips(part, parts[i + 1] == nil or parts[i + 1] == ".")
            if say then
                for _, id in ipairs(say) do clips[#clips + 1] = id end
            else
                clips = nil
            end
        elseif part == "," or part == "." then
            text = text .. part
        elseif part == "|" then
            if clips then clips[#clips + 1] = "_" end
        else
            piece = FRAGMENTS[part]
            if not piece then error("no spliced phrase called " .. tostring(part)) end
            if clips then clips[#clips + 1] = part end
        end
        if piece then text = (text == "" and piece) or (text .. " " .. piece) end
    end
    return text, clips
end

-- How long one clip of a splice takes before the next may start, or nil when its length is not known. "_" is the breath.
function Ledger.ClipDelay(id)
    if id == "_" then return Ledger.PAUSE end
    local len = ST.ledgerClips and ST.ledgerClips[id]
    return len and (len + Ledger.GAP) or nil
end

-- The week's standing in a few words, from a Week.Score result.
local function weekLine(s)
    local w = s.score
    if s.immune then
        return LINES.week_leave, "ZENNIT IS ON LEAVE", "week_leave"
    elseif w.closed then
        return LINES.week_closed, "THE INDEX IS CLOSED", "week_closed"
    elseif w.summons == 0 then
        return LINES.week_none, "NO SUMMONS YET", "week_none"
    end
    -- the lead, as the cue words it and as the spliced line says it ("level_tie" carries its own full stop)
    local lead, leadParts
    if w.group > w.zennit then
        lead, leadParts = string.format("the group leads by %d", w.group - w.zennit), { "group_leads_by", w.group - w.zennit, "." }
    elseif w.group == w.zennit then
        lead, leadParts = "it is level, and a tie is Zennit's", { "level_tie" }
    else
        lead, leadParts = string.format("Zennit leads by %d", w.zennit - w.group), { "zennit_leads_by", w.zennit - w.group, "." }
    end
    local parts
    if w.new then
        parts = { "this_week", w.counted, "of", s.cap, "summons_filed_and" }
        for _, p in ipairs(leadParts) do parts[#parts + 1] = p end
    else
        parts = { "week_group_has", w.group, "points_to", w.zennit, "." }
    end
    local text, clips = Ledger.Splice(parts)
    return text, "THIS WEEK: " .. lead:upper(), clips
end

----------------------------------------------------------------------
-- What the log remembers (the players, named): the roll a pair of helpers tipped, who has summoned him most, a run of
-- dice he won, and the silver he has been paid. Worked out from the summons of Zennit in a window, so every client
-- tells the same story, and used for the scene, the keepsake of a finished season, and `/sc seasons`.
----------------------------------------------------------------------

local function joined(names)
    if #names <= 1 then return names[1] or "" end
    return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

-- ctx: { isZennit(name), name(name), bonus(ev), edge(ev), resolve(zroll, sroll, bonus, edge), silver, helpersMax }
-- Returns { summons, casters = { name = n }, present = { name = true }, silverPaid, silverOwed (in silver), tipped,
-- streak (his longest run of dice wins), heaviest = { name, n } or nil }.
function Ledger.Collect(events, from, to, ctx)
    local d = { summons = 0, casters = {}, present = {}, silverPaid = 0, silverOwed = 0, streak = 0, usualAsk = ctx.silver,
        -- for the titles and the badges
        assists = {}, helperTips = {}, tipPairs = {}, by = {}, delays = {} }
    local weekOf = ctx.weekStart or function(t) return math.floor(t / (7 * 86400)) end
    local list = {}
    for id, ev in pairs(events) do
        if not ev.fake and ev.time >= from and ev.time < to and ctx.isZennit(ev.target) then list[#list + 1] = { id = id, ev = ev } end
    end
    table.sort(list, function(a, b)
        if a.ev.time ~= b.ev.time then return a.ev.time < b.ev.time end
        return tostring(a.id) < tostring(b.id)
    end)
    local run = 0
    d.postcards = {} -- the first landed summons of him to each far-flung place, in order (design/lenses.md, Secrets)
    d.leave = { n = 0, by = {} } -- summons of him on his week off (design/lenses.md, Inner Contradiction)
    -- what the titles praise beyond effort and luck (design/lenses.md, Judgment): the summons he went on, and the writs that bit
    d.went, d.wentFarthest, d.writs = 0, nil, {}
    local stamped = {}
    for _, item in ipairs(list) do
        local ev = item.ev
        local caster = ctx.name(ev.caster)
        if ctx.off and ctx.off(ev) then
            d.leave.n = d.leave.n + 1
            d.leave.by[caster] = (d.leave.by[caster] or 0) + 1
        end
        local place = ctx.remote and ev.mapID and ctx.remote(ev.mapID)
        if place and not stamped[ev.mapID] and ctx.lands(ev) then
            stamped[ev.mapID] = true
            d.postcards[#d.postcards + 1] = { place = place, mapID = ev.mapID, caster = caster, time = ev.time }
        end
        d.summons = d.summons + 1
        d.casters[caster] = (d.casters[caster] or 0) + 1
        d.present[caster] = true
        local me = d.by[caster]
        if not me then
            me = { summons = 0, weeks = {}, weekCount = 0, tipped = 0, paid = 0, owed = 0 }
            d.by[caster] = me
        end
        me.summons = me.summons + 1
        local week = weekOf(ev.time)
        if not me.weeks[week] then me.weeks[week], me.weekCount = true, me.weekCount + 1 end
        for _, helper in ipairs(ev.assistants or {}) do
            local h = ctx.name(helper)
            d.present[h] = true
            d.assists[h] = (d.assists[h] or 0) + 1
        end
        local r = ev.response
        local result = r and r.result
        if result == "accepted" or result == "owed" or result == "paid" then -- he went
            d.went = d.went + 1
            local far = ctx.remote and ev.mapID and ctx.remote(ev.mapID)
            if far and (not d.wentFarthest or ev.time < d.wentFarthest.time) then d.wentFarthest = { place = far, time = ev.time } end
        end
        if result == "refused" and ev.writ and ctx.writCounts and ctx.writCounts(ev) then -- a writ that cost him
            d.writs[caster] = (d.writs[caster] or 0) + (ev.points or 0)
        end
        local amount = (r and r.amount) or ctx.silver
        if result == "paid" then d.silverPaid, me.paid = d.silverPaid + amount, me.paid + amount end
        if result == "owed" then d.silverOwed, me.owed = d.silverOwed + amount, me.owed + amount end
        if r and (result == "owed" or result == "paid") and not r.card and (not d.maxAsk or amount > d.maxAsk.amount) then
            d.maxAsk = { amount = amount, caster = caster }
        end
        if r and r.time and r.time >= ev.time then d.delays[#d.delays + 1] = r.time - ev.time end
        if result == "won" or result == "lost" then
            run = result == "won" and run + 1 or 0
            d.streak = math.max(d.streak, run)
            local bonus = ctx.bonus(ev)
            -- his roll would have won without the helpers: they tipped it
            if result == "lost" and bonus > 0 and ctx.resolve(r.zroll, r.sroll, 0, ctx.edge(ev)) == "won" then
                d.tippedCount = (d.tippedCount or 0) + 1
                me.tipped = me.tipped + 1
                local names = {}
                for i = 1, math.min(#(ev.assistants or {}), ctx.helpersMax) do names[i] = ctx.name(ev.assistants[i]) end
                local sorted = { unpack(names) }
                table.sort(sorted)
                for _, h in ipairs(sorted) do d.helperTips[h] = (d.helperTips[h] or 0) + 1 end
                if #sorted > 0 then
                    local key = joined(sorted)
                    d.tipPairs[key] = (d.tipPairs[key] or 0) + 1
                end
                d.tipped = { caster = caster, helpers = names, bonus = bonus, sroll = r.sroll, zroll = r.zroll, edge = ctx.edge(ev) }
            end
        end
    end
    local top, tie
    for name, n in pairs(d.casters) do
        if not top or n > top.n then top, tie = { name = name, n = n }, false
        elseif n == top.n then tie = true end
    end
    if top and not tie then d.heaviest = top end
    return d
end

-- The silver line, or nil: what the group has paid Zennit, in cash, with no receipt.
function Ledger.SilverLine(d)
    if d.silverPaid > 0 then
        return string.format("The group has paid Zennit %d silver, in cash, with no receipt. The Ritual has asked to be kept informed.%s",
            d.silverPaid, d.silverOwed > 0 and string.format(" A further %d is owed.", d.silverOwed) or "")
    elseif d.silverOwed > 0 then
        return string.format("Zennit is owed %d silver, and has been very good about not mentioning it.", d.silverOwed)
    end
end

-- Up to two moments worth remembering, as { text, cue }: a tipped roll first, then the heaviest hand, then a run of
-- dice. Each names the players.
function Ledger.Moments(d)
    local found = {}
    local t = d.tipped
    if t then
        local who = #t.helpers > 0 and (joined(t.helpers) .. "'s") or "The helpers'"
        found[#found + 1] = { text = string.format("%s +%d tipped one of %s's rolls: %d+%d against his %d+%d. The Index has framed it.",
            who, t.bonus, t.caster, t.sroll, t.bonus, t.zroll, t.edge), cue = "THE HELPERS TIPPED IT" }
    end
    if d.heaviest and d.heaviest.n >= 3 then
        found[#found + 1] = { text = string.format("%s has summoned Zennit %d times, and the Index has begun to recognise the handwriting.",
            d.heaviest.name, d.heaviest.n), cue = d.heaviest.name:upper() .. " KEEPS COMING BACK" }
    end
    if d.streak >= 3 then
        found[#found + 1] = { text = string.format("He once won the dice %d times in a row. The Index checked the dice. They were dice.",
            d.streak), cue = "THE DICE WERE DICE" }
    end
    while #found > 2 do found[#found] = nil end
    return found
end

-- The leader or leaders of a count map with at least `min`, and who is next: { names, n, next = { names, n } } or nil.
local function leaders(map, min)
    local best, second = 0, 0
    for _, n in pairs(map) do
        if n > best then second, best = best, n elseif n < best and n > second then second = n end
    end
    if best < min then return nil end
    local names, nextNames = {}, {}
    for name, n in pairs(map) do
        if n == best then names[#names + 1] = name elseif second > 0 and n == second then nextNames[#nextNames + 1] = name end
    end
    table.sort(names)
    table.sort(nextNames)
    return { names = names, n = best, next = #nextNames > 0 and { names = nextNames, n = second } or nil }
end

local function median(list)
    if #list == 0 then return nil end
    table.sort(list)
    return list[math.ceil(#list / 2)]
end

local function duration(sec)
    if sec < 120 then return sec .. " seconds" end
    if sec < 7200 then return math.floor(sec / 60) .. " minutes" end
    return math.floor(sec / 3600) .. " hours"
end

Ledger.GOOD_SPORT = 10 -- summons of him he went on in a season before he is the Good Sport

-- Titles: praise in words, no points, for what the log shows (design/lenses.md, Reward). The same people can hold several, and
-- Zennit has some too. Each is { id, title, text, next } where `next` says who is close behind (for the mid-season standings).
-- `d` is a Ledger.Collect result.
function Ledger.Titles(d)
    local out = {}
    local function add(id, title, who, sentence, nextText)
        out[#out + 1] = { id = id, title = title, text = title .. ": " .. who .. sentence, next = nextText }
    end
    local function nextOf(l, unit)
        if not l.next then return nil end
        return string.format("%s %s next with %d%s", joined(l.next.names), #l.next.names > 1 and "are" or "is", l.next.n, unit or "")
    end
    local function who(l) return joined(l.names) .. (#l.names > 1 and ", " .. l.n .. " each" or "") end

    local heavy = leaders(d.casters, 3)
    if heavy then
        add("heaviest", "The Heaviest Hand", who(heavy), string.format(", with %d summons of him.", heavy.n), nextOf(heavy))
    end
    local support = leaders(d.assists, 3)
    if support then
        add("support", "The Best Supporting Role", who(support), string.format(", who helped %d times.", support.n), nextOf(support))
    end
    local lucky = leaders(d.tipPairs, 1)
    if lucky then
        add("lucky", "The Lucky Pair", joined(lucky.names), string.format(", whose bonus tipped %d roll%s.", lucky.n, lucky.n == 1 and "" or "s"),
            nextOf(lucky))
    end
    local server = leaders(d.writs or {}, 1)
    if server then
        add("server", "The Process Server", who(server), string.format(", whose writs cost him %d point%s.", server.n, server.n == 1 and "" or "s"),
            nextOf(server, " points"))
    end
    local paid = {}
    for name, e in pairs(d.by) do
        if e.paid > 0 then paid[name] = e.paid end
    end
    local payer = leaders(paid, 50)
    if payer then
        add("payer", "The Prompt Payer", who(payer), string.format(", who paid %d silver.", payer.n), nextOf(payer, " silver"))
    end
    -- Zennit's: kind ones
    if d.streak >= 3 then
        add("goblin", "The Dice Goblin", "Zennit", string.format(", who won the dice %d times in a row.", d.streak))
    end
    if d.maxAsk and d.maxAsk.amount >= 2 * (d.usualAsk or 50) then
        add("bargain", "The Hard Bargain", "Zennit", string.format(", who asked %s for %d silver.", d.maxAsk.caster, d.maxAsk.amount))
    end
    if (d.went or 0) >= Ledger.GOOD_SPORT then
        add("sport", "The Good Sport", "Zennit", string.format(", who went where he was sent %d times%s.", d.went,
            d.wentFarthest and (", including " .. d.wentFarthest.place) or ""))
    end
    local mid = #d.delays >= 5 and median(d.delays)
    if mid and mid <= 3600 then
        add("quick", "The Quick Reply", "Zennit", string.format(", whose usual answer came within %s.", duration(math.max(mid, 1))))
    end
    return out
end

-- The titles as they stand in the season in progress, for chat: one line each, with who is close behind.
function Ledger.Standings()
    local titles = Ledger.Titles(Ledger.Facts())
    local lines = {}
    for _, t in ipairs(titles) do
        lines[#lines + 1] = t.text .. (t.next and (" (" .. t.next .. ".)") or "")
    end
    if #lines == 0 then lines[1] = "Nothing has been earned yet this season. The Index is watching." end
    return lines
end

-- The Index's keepsake of a finished season: how it ended, how long it took, who was there, the silver and the moments.
-- finale = { start, side, from } from Week.Season; `number` is which season it was. Returns a list of sentences.
function Ledger.Keepsake(number, finale, d)
    local weeks = math.floor((finale.start - finale.from) / (7 * 86400)) + 1
    local out = { string.format("Season %d, %s. %s", number, weeks == 1 and "1 week" or (weeks .. " weeks"),
        finale.side == "group" and "The group took the finale, and Zennit was freed." or
            "Zennit took the finale, and became the clerk of the Index.") }
    local names = {}
    for name in pairs(d.present) do names[#names + 1] = name end
    table.sort(names)
    if #names > 0 then
        local more = #names > 12 and string.format(", and %d more", #names - 12) or ""
        while #names > 12 do names[#names] = nil end
        out[#out + 1] = "In the room: " .. joined(names) .. more .. "."
    end
    local silver = Ledger.SilverLine(d)
    if silver then out[#out + 1] = silver end
    local cards = Ledger.PostcardsLine(d)
    if cards then out[#out + 1] = cards end
    local leave = Ledger.LeaveLine(d)
    if leave then out[#out + 1] = leave end
    for _, m in ipairs(Ledger.Moments(d)) do out[#out + 1] = m.text end
    for _, t in ipairs(Ledger.Titles(d)) do out[#out + 1] = t.text end
    return out
end

-- What this character has done, for the badges: { weekCount, tipped, paid, owed }, from every summons of Zennit they cast.
function Ledger.CasterStats(name)
    local d = Ledger.Collect(ST.db.events, 0, math.huge, Ledger.Context())
    return d.by[ST.baseName(name) or name] or { weekCount = 0, tipped = 0, paid = 0, owed = 0 }
end

function Ledger.Context()
    local W, R = ST.Week, ST.Respond
    local edges, offs = {}, {}
    return { isZennit = W.IsZennit, name = function(n) return ST.baseName(n) or n end, bonus = W.HelperBonus,
        edge = function(ev)
            local start = W.Start(ev.time)
            if not edges[start] then edges[start] = (W.Edge(start)) end
            return edges[start]
        end,
        resolve = R.Resolve, silver = R.SILVER, helpersMax = W.RULES.helpersMax, weekStart = W.Start,
        remote = function(id) return ST.Scoring.remoteNames[id] end, lands = ST.Store.Lands, writCounts = W.WritCounts,
        off = function(ev)
            local start = W.Start(ev.time)
            if offs[start] == nil then offs[start] = W.IsOff(start) end
            return offs[start]
        end }
end

----------------------------------------------------------------------
-- Postcards (design/lenses.md, Secrets): a reason to drag him somewhere far-flung beyond the points, and part of the joke. The first
-- time in a season a summons of him to a far-flung place lands (he went), the Index files a postcard from him.
----------------------------------------------------------------------
Ledger.POSTCARDS = {
    [1451] = "Sand. Also insects. Mostly sand.",
    [1452] = "Cold. A yeti was polite about it.",
    [1447] = "Ruins, naga and a view. The view was fine.",
    [1448] = "Everything here is the wrong colour, now including me.",
    [1449] = "Something large has been following me. It is not the party.",
    [1423] = "The locals are dead, and still more welcoming than the Index.",
    [1428] = "It is on fire. All of it. Do not send a coat.",
    [1419] = "The name was accurate.",
    [1430] = "Nobody is here, and nobody wants to be. I have joined them.",
    [1450] = "Peaceful. I was summoned out of a nap to be told so.",
}

-- How many far-flung places there are to collect.
function Ledger.PostcardPlaces()
    local n = 0
    for _ in pairs(ST.Scoring.remoteNames) do n = n + 1 end
    return n
end

-- This season's postcards, oldest first.
function Ledger.Postcards(season)
    return Ledger.Facts(season).postcards
end

-- The keepsake's line: "Postcards from Zennit: Silithus and Moonglade (2 of 10)." Nil when there are none.
function Ledger.PostcardsLine(d)
    if #d.postcards == 0 then return nil end
    local names = {}
    for i, p in ipairs(d.postcards) do names[i] = p.place end
    return string.format("Postcards from Zennit: %s (%d of %d).", joined(names), #names, Ledger.PostcardPlaces())
end

-- The far-flung places with no postcard yet this season, as a line for where to go next (design/lenses.md, Indirect Control).
-- short: name three and count the rest, for the Monday login. Nil when every one has been stamped.
function Ledger.MissingLine(d, short)
    local have, missing = {}, {}
    for _, p in ipairs(d.postcards) do have[p.mapID] = true end
    for id, name in pairs(ST.Scoring.remoteNames) do if not have[id] then missing[#missing + 1] = name end end
    if #missing == 0 then return nil end
    table.sort(missing)
    if short and #missing > 4 then
        local n = #missing - 3
        while #missing > 3 do missing[#missing] = nil end
        return string.format("Still no postcard from: %s and %d more. The Index has stamps.", table.concat(missing, ", "), n)
    end
    return string.format("Still no postcard from: %s. The Index has stamps.", joined(missing))
end

-- The line for a summons of him that has just landed, if it is this season's first to its far-flung place; else nil.
-- before: the answer it had until now, so a summons that already landed (silver later paid) does not send a second postcard.
function Ledger.PostcardFor(ev, before)
    if ev.fake or not ev.mapID or not ST.Scoring.remoteNames[ev.mapID] or not ST.Store.Lands(ev) then return nil end
    if before and ST.Store.Lands({ response = before }) then return nil end
    local cards = Ledger.Postcards()
    for i, p in ipairs(cards) do
        if p.mapID == ev.mapID then
            if p.time ~= ev.time then return nil end -- he has been there already this season
            -- his own words when he has written them (design/lenses.md, Character), else ours
            local words = ST.Sync.ZennitLine("pc:" .. ev.mapID) or Ledger.POSTCARDS[ev.mapID] or "Wish you were here. I was."
            local line = string.format("The Index has filed a postcard from %s, in %s: '%s' Stamped: %d of %d far-flung places this season.",
                ev.target, p.place, words, i, Ledger.PostcardPlaces())
            if i == Ledger.PostcardPlaces() then
                line = line .. " That is every one. The Index has run out of stamps, and has sent for more."
            end
            return line
        end
    end
    return nil
end

-- How often the group disturbed his leave, and who did it most: "His leave was disturbed 6 times; Al did it most (4)." Nil when
-- nobody did (design/lenses.md, Inner Contradiction).
function Ledger.LeaveLine(d)
    if not d.leave or d.leave.n == 0 then return nil end
    local best, most, tie = nil, 0, false
    for name, n in pairs(d.leave.by) do
        if n > most or (n == most and best and name < best) then best, most, tie = name, n, false end
    end
    for name, n in pairs(d.leave.by) do if n == most and name ~= best then tie = true end end
    local times = d.leave.n == 1 and "once" or (d.leave.n .. " times")
    if d.leave.n == 1 then return string.format("The Index notes that %s disturbed his leave once.", best) end
    return string.format("The Index notes that his leave was disturbed %s; %s did it most (%d)%s.", times, best, most,
        tie and ", jointly with others" or "")
end

-- The facts for the season in progress.
function Ledger.Facts(season)
    season = season or ST.Week.Season()
    return Ledger.Collect(ST.db.events, season.since or 0, math.huge, Ledger.Context())
end

-- Past seasons, newest first: { { number, side, lines } }.
function Ledger.Seasons()
    local out, finales = {}, ST.Week.Season().finales
    local ctx = Ledger.Context()
    for i = #finales, 1, -1 do
        local f = finales[i]
        local d = Ledger.Collect(ST.db.events, f.from, f.start + 7 * 86400, ctx)
        out[#out + 1] = { number = i, side = f.side, lines = Ledger.Keepsake(i, f, d) }
    end
    return out
end

-- state: { season = Week.Season(), score = Week.Score(this week), immune = bool, wins = Week.WINS, cap = summons a week,
--          edgeMoved, whim (the week's whim as a sentence, or nil), facts = Ledger.Collect result for the season }
-- Returns a list of { text, cue }, where cue is the punchline for the Text: key mode (or nil).
function Ledger.Build(s)
    local out = {}
    -- clip: the id of a fixed line's recording (see LINES); nil for the lines built from names and numbers
    -- A line's recording is clip (the id of a fixed line) or a list of clips to play one after another (a spliced line).
    local function say(text, cue, clip)
        local item = { text = text, cue = cue }
        if type(clip) == "table" then item.clips = clip else item.clip = clip end
        out[#out + 1] = item
    end
    local function splice(parts, cue)
        local text, clips = Ledger.Splice(parts)
        say(text, cue, clips)
    end
    local z, g, wins = s.season.zennit, s.season.group, s.wins
    local finales = s.season.finales
    local number = s.season.number or #finales + 1
    local function story(id, cue)
        local text, clip = storyLine(number, id)
        if text then say(text, cue, clip) end
    end

    -- how the season began, or how the last one ended (told in that season's words)
    if number > 1 then
        local text, clip = storyLine(finales[#finales].season or number - 1, "last_" .. finales[#finales].side)
        if text then say(text, "SEASON " .. number, clip) end
    end

    -- the standing
    if z == 0 and g == 0 then
        story(number > 1 and "empty_fresh" or "empty_first", "NOBODY HAS WON A WEEK")
        say(LINES.wait, nil, "wait")
    elseif z == g then
        splice({ "level_at", z, z == 1 and "week_each" or "weeks_each", "|", "not_taking_sides" }, "LEVEL AT " .. z)
    elseif g > z then
        splice({ "group_leads_season", g, "to", z, "." }, "THE GROUP LEADS, " .. g .. " TO " .. z)
    else
        splice({ "zennit_leads_season", z, "to", g, ",", "nobody_expected" }, "ZENNIT LEADS, " .. z .. " TO " .. g)
    end

    -- how far down each trunk
    if z > 0 then story("recap_z" .. z) end
    if g > 0 then story("recap_g" .. g) end

    -- what the Index remembers of this season, by name, and the silver
    if s.facts then
        local silver = Ledger.SilverLine(s.facts)
        local moments = Ledger.Moments(s.facts)
        for i, m in ipairs(moments) do
            if i <= (silver and 1 or 2) then say(m.text, m.cue) end -- two lines of memory at most, the silver among them
        end
        if silver then say(silver, "THE SILVER") end
    end

    -- the pressure
    if z == wins - 1 and g == wins - 1 then
        say(LINES.end_both, "ONE WIN FROM THE END", "end_both")
    elseif g == wins - 1 then
        story("end_group", "ONE WIN FROM THE FINALE")
    elseif z == wins - 1 then
        story("end_zennit", number == 1 and "ONE WIN FROM THE CHAIR" or "ONE WIN FROM THE FINALE")
    end

    -- the Index's thumb on the scale, when the season is lopsided (Week.Edge)
    if s.edgeMoved and s.edgeMoved ~= 0 then
        splice(s.edgeMoved < 0 and { "edge_group_behind", -s.edgeMoved, "off_dice" } or { "edge_zennit_behind", s.edgeMoved, "on_dice" },
            "THE INDEX TAKES NO SIDES")
    end

    local text, cue, clip = weekLine(s)
    say(text, cue, clip)
    if s.whim and not s.immune then
        local text = "This week's whim: " .. s.whim
        say(text, "THE WHIM OF THE WEEK", Ledger.WhimClip(text))
    end
    say(LINES.evidence, nil, "evidence")
    return out
end

-- The recording of a whim line, when the line is word for word what was recorded; nil otherwise (it is then typed and silent,
-- never read out wrongly).
function Ledger.WhimClip(text)
    for id, line in pairs(LINES) do
        if id:find("^whim_") and line == text then return id end
    end
    return nil
end

-- Reading speed of the typed-out lines: a sentence stays up for a second and a bit, plus a share of its length.
local LEAD, PER_CHAR = 1.2, 1 / 16

-- Times the sentences for the viewer. Returns sentences { { t, text, clip } }, cues { { t, text } } and the total
-- length. A line with a recording lasts as long as its clip (which has its own breath of silence at each end); the
-- rest are timed to be read.
function Ledger.Timed(list)
    local sentences, cues, t = {}, {}, 0
    for _, item in ipairs(list) do
        local len, clips, lead = nil, nil, 0.45
        if item.clips then
            -- a spliced line lasts as long as its fragments one after another; they carry no silence of their own
            len = 0
            for _, id in ipairs(item.clips) do
                local delay = Ledger.ClipDelay(id)
                if not delay then len = nil break end
                len = len + delay
            end
            clips, lead = len and item.clips or nil, 0.15
        else
            len = item.clip and ST.ledgerClips and ST.ledgerClips[item.clip]
        end
        sentences[#sentences + 1] = { t = t, text = item.text, clip = len and not clips and item.clip or nil, clips = clips }
        if item.cue then cues[#cues + 1] = { t = t + (len and lead or 0.3), text = item.cue } end
        t = t + (len or (LEAD + #item.text * PER_CHAR))
    end
    return sentences, cues, t
end

-- The chapter key whose picture the scene borrows: the latest win, or a later season's opening until it has one; nil before any.
function Ledger.ArtKey(season)
    local last = season.chapters[#season.chapters]
    local open = season.openings and season.openings[#season.openings]
    if open and (not last or last.start < open.start) then return open.key end
    return last and last.key or nil
end

function Ledger.State()
    local W = ST.Week
    local now = time()
    local start = W.Start(now)
    local season = W.Season(now)
    return { season = season, facts = Ledger.Facts(season), score = W.Score(start), immune = (W.Immune(now)), wins = W.WINS,
        cap = W.RULES.cap, edgeMoved = select(2, W.Edge(start)), whim = W.WhimLine(start) }
end
