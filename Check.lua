-- Check: the live-client checklist (/sc check). Everything in this addon was built and tested against stubs; this lists what has
-- to be confirmed in the real game, runs what can be run by itself, watches the rest while you play, and says what to send back.
-- Results are kept in SummonTrackerDB (ST.db.checks) so they survive a reload, and /sc check report prints them to paste.
-- The plan around it is design/verification.md.
local ADDON, ST = ...
setfenv(1, ST.env) -- the addon's own globals (Core.lua)
local Check = {}
ST.Check = Check

----------------------------------------------------------------------
-- The trace: what the summon prompt and the answers did, newest last (the last 40)
----------------------------------------------------------------------
ST.trace = {}
local TRACE_MAX = 40

function ST.Trace(text)
    local log = ST.trace
    log[#log + 1] = { time = time(), text = tostring(text) }
    if #log > TRACE_MAX then table.remove(log, 1) end
end

----------------------------------------------------------------------
-- The list. kind: "auto" runs by itself (/sc check auto), "solo" needs only you, "duo" needs a friend who runs the addon.
-- seen: marked by the addon itself when it watches it happen (Check.Seen). fails: what the addon does if this does not work.
----------------------------------------------------------------------
-- The calls the addon depends on. required ones break something when missing; the optional one only costs a nicety.
Check.REQUIRED = {
    "C_SummonInfo.ConfirmSummon", "C_SummonInfo.CancelSummon", "hooksecurefunc", "RandomRoll", "C_ChatInfo.SendChatMessage",
    "C_Map.GetMapInfo", "C_Map.GetBestMapForUnit", "C_ChatInfo.SendAddonMessage", "C_Timer.NewTicker", "StaticPopup_Show",
}
Check.OPTIONAL = { "C_SummonInfo.GetSummonConfirmSummoner" }

-- Which of these dotted names ("C_Map.GetMapInfo") are not functions in `env` (the game's globals).
function Check.Missing(names, env)
    local out = {}
    for _, name in ipairs(names) do
        local obj = env
        for part in name:gmatch("[^%.]+") do
            obj = type(obj) == "table" and obj[part] or nil
        end
        if type(obj) ~= "function" then out[#out + 1] = name end
    end
    return out
end

local function joined(list) return #list == 0 and "none" or table.concat(list, ", ") end

Check.LIST = {
    -- ---------------------------------------------------------------- by themselves
    { id = "a-api", kind = "auto", title = "The game gives the addon the calls it relies on",
      fails = "the summon prompt is not read and the Index's form answers as it always did",
      run = function()
          local missing = Check.Missing(Check.REQUIRED, _G)
          local soft = Check.Missing(Check.OPTIONAL, _G)
          return #missing == 0, "missing: " .. joined(missing) .. "; optional missing: " .. joined(soft)
      end },
    { id = "a-ask", kind = "auto", title = "The game lets an addon find the hearthstone in the bags and read its cooldown (/sc ask)",
      fails = "Zennit's client answers /sc ask hearth with 'could not tell'",
      run = function()
          local count = Check.Missing({ "C_Item.GetItemCount" }, _G)[1] and Check.Missing({ "GetItemCount" }, _G)[1]
          local cd = Check.Missing({ "C_Container.GetItemCooldown" }, _G)[1] and Check.Missing({ "C_Item.GetItemCooldown" }, _G)[1]
              and Check.Missing({ "GetItemCooldown" }, _G)[1]
          return not count and not cd, string.format("item count: %s; item cooldown: %s", count and "missing" or "found",
              cd and "missing" or "found")
      end },
    { id = "a-hooks", kind = "auto", title = "The summon prompt's Accept and Decline calls are hooked",
      fails = "what he presses in the game is not seen; the Index's form answers as before",
      run = function()
          local h = ST.Respond and ST.Respond.hooks
          if not h then return false, "the hooks were never installed" end
          return h.confirm and h.cancel and h.event or false,
              string.format("accept hook %s, decline hook %s, CONFIRM_SUMMON event %s", tostring(h.confirm), tostring(h.cancel), tostring(h.event))
      end },
    { id = "a-places", kind = "auto", title = "Every city and far-flung map ID is a real map with the expected name",
      fails = "a place scores as a plain zone (3) instead of its kind",
      run = function()
          local lines = ST.Scoring.Places(function(id)
              local ok, info = pcall(C_Map.GetMapInfo, id)
              return ok and type(info) == "table" and type(info.name) == "string" and info.name or nil
          end)
          local last = lines[#lines]
          if last:find("knows every map", 1, true) then return true, last end
          local wrong = {}
          for _, line in ipairs(lines) do
              for part in line:gmatch("([^,:]+ %(%d+: the client[^%)]*%))") do wrong[#wrong + 1] = part:gsub("^%s+", "") end
          end
          return false, last .. (#wrong > 0 and (" Wrong: " .. table.concat(wrong, "; ") .. ".") or "")
      end },
    { id = "a-zones", kind = "auto", title = "The client lists the world's zones for the secret list box",
      fails = "the secret list box only suggests the Index's own places and where summons have landed",
      run = function()
          local names, has = ST.Respond.WorldZoneNames(), {}
          for _, n in ipairs(names) do has[n:lower()] = true end
          local missing = {}
          for _, n in pairs(ST.Scoring.remoteNames) do -- every far-flung place is a zone, so the client must list it
              if not has[n:lower()] then missing[#missing + 1] = n end
          end
          table.sort(missing)
          return #names > 0 and #missing == 0, string.format("%d zones from the client; far-flung places missing: %s", #names, joined(missing))
      end },
    { id = "a-selftest", kind = "auto", title = "The self-tests (/sc synctest) pass in the game",
      fails = "a rule or the sync format behaves differently in the game than in the stubs",
      run = function()
          local pass, total, failed = ST.SyncTest.Run(true)
          local detail = string.format("%d of %d passed", pass, total)
          if failed and #failed > 0 then detail = detail .. "; failed: " .. table.concat(failed, "; ") end
          return pass == total, detail
      end },
    { id = "a-window", kind = "auto", title = "Every tab of the window builds and refreshes without an error",
      fails = "a tab shows nothing or stops the window",
      run = function()
          local ok, err = ST.Hub.SelfCheck()
          return ok, ok and "all tabs refreshed" or tostring(err)
      end },
    { id = "a-binding", kind = "auto", title = "The writ key binding's function and names are registered",
      fails = "no key for the writ; /sc writ still works",
      run = function()
          local ok = type(_G["SummonCore_ToggleWrit"]) == "function" and type(_G["BINDING_NAME_SUMMONCORE_WRIT"]) == "string"
          return ok, ok and "the global and the binding names are set (the binding itself is checked by s-key)" or "not set"
      end },
    { id = "a-prefix", kind = "auto", title = "The addon message prefix is registered",
      fails = "friends' addons cannot hear each other",
      run = function()
          local reg = C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered
          if not reg then return false, "this client cannot say" end
          local ok, got = pcall(reg, ST.prefix)
          return ok and got == true, ok and tostring(got) or tostring(got)
      end },
    { id = "a-errors", kind = "auto", title = "No script error has been caught this session",
      fails = "something is breaking; /sc errors says what",
      run = function()
          local n = #ST.errors
          return n == 0, n == 0 and "none" or string.format("%d caught: /sc errors", n)
      end },
    -- ---------------------------------------------------------------- by yourself
    { id = "s-popup", kind = "solo", title = "A pretend summons: the Index's form, one-click dice, an answer",
      steps = { "/sc respond test opens the form for a pretend summons from Tester.",
          "It should say what a decline would do (free, with 1 free decline left) and the place's points.",
          "Click Roll the dice (1-100): it should roll at once and show the rules on the waiting screen, and a pretend roll should come back within a couple of seconds and give an answer line in chat." },
      expect = "the form, then a dice result line, with no extra click", fails = "answers cannot be given, or the dice need a click they should not" },
    { id = "s-key", kind = "solo", title = "The writ key binding exists and arms a writ",
      steps = { "Esc > Options > Key Bindings > AddOns: find Summon Core and bind a key to Play a writ on your next summons of Zennit.",
          "Press it: chat says a writ is armed (or why not). Press again: it says it is withdrawn." },
      expect = "the binding is listed and the key does what /sc writ does", fails = "no key; /sc writ still works" },
    { id = "s-fit", kind = "solo", title = "The window fits: Party (Of Zennit column), Badges, Tools",
      steps = { "/sc and click through Party, Zennit, Log, Story, Sync and Tools.",
          "Nothing should run off the edge: the Party tab's Of Zennit column, the Badges tab's third column and each of the Tools tab's sections (General, Testing, Checks)." },
      expect = "no clipped text or overlapping buttons", fails = "layout needs a fix (say which tab)" },
    { id = "s-lines", kind = "solo", title = "The chat lines read well on a test summons",
      steps = { "On a Zennit test (/sc zenit) or an alt: /sc fake Zennit, then /sc week, /sc rules, /sc tab and /sc report.",
          "Read them as the group would: are any too long, or wrong?" },
      expect = "short, plain, in the Index's voice", fails = "wording or length to fix (paste the line)" },
    { id = "s-sound", kind = "solo", title = "The intro sound files play after a full restart",
      steps = { "After a full WoW restart: /sc intro check." }, expect = "every file plays", fails = "a recording is missing or misnamed" },
    { id = "s-decline", kind = "solo", title = "The form's Decline says what it costs, by the same rule as the game's",
      steps = { "On a Zennit test (/sc zenit): /sc respond test opens the form for a pretend summons from Tester.",
          "The button says Decline (free) while his free decline is left, and the line above says why; press it.",
          "(Pretend summons never spend his free decline; once a real one has, the form says Decline and what it costs.) /sc rules says the same rule under Declines." },
      expect = "the cost on the form matches the rules card", fails = "the form and the rules disagree (paste both)" },
    { id = "s-list", kind = "solo", title = "His list is set for the week: a new place is marked 'from Monday'",
      steps = { "On a Zennit test (/sc zenit), or his own client: /sc zennit list add Silithus.",
          "The list (and the Zennit tab) should show 'Silithus (from Monday)'. /sc zennit list remove <n> takes it off at once." },
      expect = "the new place marked from Monday", fails = "a place counts the moment it is added (the mid-summons hole is open)" },
    { id = "s-previously", kind = "solo", title = "Previously on: this season's chapters, back to back",
      steps = { "/sc intro previously (once the season has reached a chapter or two).",
          "Each chapter plays to its end, and the next starts by itself after a breath. Closing the window stops it." },
      expect = "every reached chapter of the season, in order", fails = "it stops after the first, or plays one not reached" },
    { id = "s-login", kind = "solo", title = "The login lines: the week's close in your time, a tip, and what is waiting or owed",
      steps = { "/sc week login says this week's login lines again (they come once a week, a minute after login).",
          "Expect: 'The Index closes this week on <day and time>, your time': check it against your clock (the week ends Monday 00:00 UTC), then 'Still no postcard from: ...' (three places and a count).",
          "Then a 'Tip:' line. On Zennit's client, how many summons wait for his answer and the silver owed to him; on anyone else's, what you owe (only if anything is)." },
      expect = "the close in your own time, correct, and a tip", fails = "a wrong time zone, or a line missing (say which)" },
    { id = "s-band", kind = "solo", title = "The window's band and status line agree with /sc week",
      steps = { "/sc week, then /sc: the band across the top should show the same lead, summons filed and dice left (or CLOSED, or his week off).",
          "The line along the bottom: the records in your log, the queue, and LINK: the channels you are in (PARTY, GUILD, or NONE)." },
      expect = "the same numbers in both", fails = "the band is out of date or wrong (say what it showed)" },
    { id = "s-welcome", kind = "solo", title = "A newcomer's welcome: nothing new to do, who needs it, where the rules are", seen = true,
      steps = { "On a character's first login with the addon it says three lines (it marks this check itself). /sc welcome says them again.",
          "Read them as someone new would: that taking part needs nothing new, that the caster and Zennit need the addon, and /sc rules and /sc intro." },
      expect = "three short lines, after 'loaded'", fails = "wording or length to fix (paste the line)" },
    { id = "s-tour", kind = "solo", title = "The tour: /sc tour talks you through the window, outlining each part",
      steps = { "After a full restart (new sound files), type /sc tour. The window opens with a box under it and the Index starts talking.",
          "Let it run to the end. Each line is heard and typed, the amber outline lands on what is being talked about, and the tabs change by themselves. Near the end it shows copies of the popups over the window: their buttons do nothing and nothing is filed. Then the game's own dialogs (Watch now?, the reset request; Zennit: the price, the payment), each saying it is the tour's example: Reset, Ask and Yes must do nothing.",
          "On a character that has not watched the intro, /sc tour plays the intro first, and the tour starts by itself when it ends (closing the intro early does not start it). The first intro seen through also offers the tour, once. /sc tour skip goes straight to it.",
          "Try BACK, PAUSE, NEXT and SOUND, then END TOUR. On Zennit's client (or /sc zenit) the Party and Zennit lines are his own." },
      expect = "every line heard, every outline on the right thing", fails = "the step number and what was wrong (no voice, outline elsewhere, a tab gag)" },
    { id = "s-lastcall", kind = "solo", title = "The last call in a week's final day (any time Sunday UTC)", seen = true,
      steps = { "Log in during the last 24 hours of a week (from Sunday 00:00 UTC), or run /sc week login then.",
          "Expect 'Last call: the Index closes the week in ...' with the standing. A ritual briefing on Zennit then carries it too." },
      expect = "the last call, with the right hours left", fails = "the week's deadline is not felt (design/lenses.md, Time)" },
    { id = "s-ask", kind = "solo", title = "Questions about Zennit, answered by his own client (/sc ask)",
      steps = { "Turn Zennit test mode on (/sc zenit): this client now answers as his.",
          "/sc ask hearth should say whether your hearthstone is in your bags and ready; use it, then ask again: it should give the minutes left.",
          "/sc ask playing should say how long you have been logged in (a /reload should not reset it).",
          "/sc zennit ask off, then /sc ask hearth: it should say questions are off. /sc zennit ask on, and Zennit test mode off again." },
      expect = "the right answers, the cooldown in minutes, and 'off' when switched off", fails = "'could not tell': the item calls are hidden or named differently on this client" },
    -- ---------------------------------------------------------------- with a friend (both on the same version)
    { id = "d-sync", kind = "duo", title = "Two clients hear each other and are on the same version",
      steps = { "Both run /sc sync, then /sc.", "Each should see the other's summons arrive, and no 'is on another version' notice." },
      expect = "hello received both ways", fails = "nothing shared; check the prefix (a-prefix) and the channel" },
    { id = "d-ritual", kind = "duo", title = "A real ritual on Zennit: briefing, log line and his form",
      steps = { "The warlock casts a real Ritual of Summoning on Zennit with two helpers.",
          "The caster sees the briefing as it starts (long for the first of the week, short after, with the place's worth) and 'Summon logged'.",
          "Zennit's form should open within a few seconds, with his free decline line." },
      expect = "all three", fails = "the ritual is not seen, or the form does not arrive" },
    { id = "d-overlap", kind = "duo", title = "On his screen, the Index's form and the game's prompt do not cover each other",
      steps = { "When the game's own summon prompt and the Index's form are both up, look at where they sit.",
          "Mark pass if both can be read; fail if one hides the other (say which is on top)." },
      expect = "both readable", fails = "move the Index's form (design/lenses.md, Resonance, A)" },
    { id = "d-name", kind = "duo", title = "The game names the summoner at the prompt (informational)",
      steps = { "After a summons, /sc check trace: the CONFIRM_SUMMON line says summoner=Name or summoner=hidden.",
          "Either is fine: with a name the right summons is matched; hidden falls back to the newest one waiting." },
      expect = "a line is there", fails = "no CONFIRM_SUMMON line: the event does not fire in this client" , seen = true },
    { id = "d-accept", kind = "duo", title = "Pressing Accept in the game records 'accepted' by itself", seen = true,
      steps = { "Zennit presses the game's Accept without touching the Index's form.",
          "The Index should record accepted and everyone should see the answer line. The addon marks this one itself." },
      expect = "accepted, no click on the form", fails = "the form still has to be answered (the accept hook did not fire)" },
    { id = "d-decline", kind = "duo", title = "Pressing Decline in the game records 'declined' (his free one)", seen = true,
      steps = { "A new summons. Zennit presses the game's Decline.",
          "The Index should record declined: no points either way, and his Week line says 0 free declines left." },
      expect = "declined", fails = "the decline hook did not fire, or it recorded something else" },
    { id = "d-cost", kind = "duo", title = "A second decline in the week costs him the points", seen = true,
      steps = { "Another summons the same week. Zennit presses Decline again.",
          "The Index should say the free decline is used, and the decline costs him the points." },
      expect = "declined (cost him the points), with the note", fails = "the free decline count is wrong" },
    { id = "d-writ", kind = "duo", title = "A writ: armed by the key, on his form, and a decline costs", seen = true,
      steps = { "The warlock arms a writ with the key, then casts. The briefing should say a writ is played.",
          "Zennit's form should say so and what a decline costs. He presses Decline: it costs him, even with free declines left, and even at a place on his list." },
      expect = "declined, it cost him, the writ named", fails = "the writ is not sent (check both are on the same version) or not read" },
    { id = "d-dice", kind = "duo", title = "Dice: one click for him, one for the caster, an answer", 
      steps = { "Zennit clicks Roll the dice (1-100) once. The waiting screen shows the rules.",
          "The caster's prompt appears and one click rolls back. An answer line follows on both clients." },
      expect = "the answer after one click each", fails = "the roll is not picked up (RandomRoll or the system message)" },
    { id = "d-dice-ends", kind = "duo", title = "Accepting in the game during a roll ends the roll", seen = true,
      steps = { "Zennit starts the dice, and before the caster rolls back, presses the game's Accept.",
          "The answer should be accepted, and no die is spent (/sc week shows the dice unchanged)." },
      expect = "accepted, dice left unchanged", fails = "the roll still decides it" },
    { id = "d-expire", kind = "duo", title = "What happens when the game's prompt expires (informational)",
      steps = { "A new summons. Zennit does not touch the prompt or the form for two minutes.",
          "Then /sc check trace: did a CancelSummon line appear when the prompt closed, and what answer (if any) did the Index record?",
          "Mark pass once you have recorded what you saw in the note. If it recorded a decline it should not have, say so." },
      expect = "a note on what happened", fails = "an expiry that counts as a decline needs a fix" },
    { id = "d-firstbrief", kind = "duo", title = "A newcomer's first ritual on Zennit gets the full briefing, mid-week",
      steps = { "Someone who has never cast a summons of Zennit (in the log) casts one after others have this week.",
          "Their briefing should be the long one: it says what each helper adds, and offers /sc writ. Their next one is short." },
      expect = "long, then short", fails = "the newcomer gets the short one (their name may not match the log's casters)" },
    { id = "d-witness", kind = "duo", title = "A warlock without the addon: Zennit's client files the summons, with helpers from a witness", seen = true,
      steps = { "The warlock turns Summon Core off (AddOns at the character screen) and casts on Zennit with a helper who runs it.",
          "Zennit answers in the game's prompt. A few seconds later his chat says 'The Index filed this summons itself: <warlock> cast it without Summon Core, helped by <helper>'.",
          "Everyone with the addon should see the summons in the Log. /sc check trace on the helper's client shows 'witnessed a ritual'." },
      expect = "filed once, with the caster and the helper", fails = "nothing filed (the trace says why), or filed twice" },
    { id = "d-postcard", kind = "duo", title = "A postcard from a far-flung place, once a season", seen = true,
      steps = { "A summons of Zennit to a far-flung place (/sc places lists them: Silithus, Winterspring...) that he accepts.",
          "Everyone sees 'The Index has filed a postcard from Zennit, in <place>: ...' after his answer (it marks this itself).",
          "/sc week ends with the season's postcards and the far-flung places still missing one. A second summons to the same place this season sends no second postcard." },
      expect = "one postcard, and /sc week lists it", fails = "no postcard (check the map ID with /sc where against /sc places)" },
    { id = "d-lines", kind = "duo", title = "His own lines reach a friend: a postcard and his out-of-office",
      steps = { "On Zennit's client: /sc zennit postcard Silithus: <a line>, and /sc zennit away <a line>.",
          "On the friend's client: /sc zennit postcard Silithus and /sc zennit away show his words (a friend can read them, not write them).",
          "If they still show the Index's default, both /sc sync (his hello sends his lines) and look again." },
      expect = "his words, not the Index's, on the friend's client", fails = "the lines are not sent (check both are on the same version)" },
    { id = "d-leave", kind = "duo", title = "His week off: a summons of him disturbs his leave, and still counts for postcards and titles", seen = true,
      steps = { "In a week after one Zennit won, cast a ritual on him.",
          "The briefing says it will not count for the race, but a far-flung place still earns a postcard; the logged line says 'disturbing his leave (N this week)' (it marks this itself).",
          "/sc week ends with how often his leave was disturbed this season, and who did it most." },
      expect = "the leave lines and the count", fails = "the week off reads as 'do not bother' again (paste the line)" },
    { id = "d-away", kind = "duo", title = "Away from his keyboard: the briefing warns, and the summons is filed as away", seen = true,
      steps = { "Zennit types /afk (or idles until the game sets it) and waits five minutes.",
          "The warlock casts on him: the briefing says he is away from his keyboard and it may be worth waiting.",
          "Zennit does not touch anything. A few seconds after the prompt, the Index files it as away (it marks this itself): free, and /sc week still shows his free decline." },
      expect = "the warning, then 'away'", fails = "it counted as accepted (the AFK flag is not seen in this client)" },
    { id = "d-watch", kind = "duo", title = "Watching together: a chapter shown to the group, and the offer when the raid gathers",
      steps = { "In a party, one of you runs /sc intro g1 group (any chapter the season has reached; the admin may show any).",
          "The other gets 'X would like to show the group chapter 3: ... Watch now?'; Watch starts it there too.",
          "At the weekly raid, the raid leader (with the addon) is offered last week's chapter about ten seconds after the raid forms; the others are told the command." },
      expect = "the prompt, and the chapter on both (a newcomer whose log is still syncing too)", fails = "no prompt (check both are on the same version)" },
    { id = "d-feelings", kind = "duo", title = "The weekly question: a friend answers, and only the admin and Zennit see the count",
      steps = { "In a week after one with summons, a friend's first login asks 'How was last week?' about a minute in. They click an answer.",
          "On the admin's client (or Zennit's): /sc feelings, or Tools > General > How it felt, shows the count for that week, with no names.",
          "On the friend's client, /sc feelings says only Zennit and the admin see it. (If the admin was offline, the friend's next hello brings it.)" },
      expect = "the count on the admin's client, nothing on the friend's", fails = "no count (check both are on the same version)" },
    { id = "d-say", kind = "duo", title = "/sc week say sends one line to the group", 
      steps = { "In a party or raid, either person runs /sc week say.", "The other sees 'Summon Core: Week: ...' in party chat." },
      expect = "the line arrives", fails = "C_ChatInfo.SendChatMessage is blocked; the addon says so" },
    { id = "d-ask", kind = "duo", title = "A question reaches Zennit's client and his answer comes back (/sc ask)",
      steps = { "In a party (or the same guild), the friend runs /sc ask hearth, then /sc ask playing.",
          "Within a few seconds the friend sees 'Asked: ...' with the answer; Zennit's client says who asked and what the Index told them.",
          "Zennit runs /sc zennit ask off; the friend asks again and is told questions are off. Then /sc zennit ask on. Try it once from the guild alone, out of the party." },
      expect = "the answer on the friend's client within a few seconds, and the notice on Zennit's", fails = "'No answer': the question or the whisper back did not arrive (check both are on 0.28 or later)" },
    { id = "d-silver", kind = "duo", title = "Silver paid by trade or mail is noticed (existing /sc probe)",
      steps = { "Zennit runs /sc probe, the friend trades him some silver, then he checks the Index's popup.", "See README, 'Seeing it arrive'." },
      expect = "a confirmation popup", fails = "the client hides trade or mail money; payments are marked by hand" },
    { id = "d-chatprobe", kind = "duo", title = "Can an addon read what Zennit says? (/sc probe chat)",
      steps = { "Both run /sc probe chat. Zennit accepts a summons from the friend and, once he arrives, says a line in /s or party chat; the friend says one too.",
          "Each client prints what it could read of each line: your own words in full, everyone else's as readable or secret, with how long it was. Try it in the open world, then in an instance.",
          "Both run /sc probe chat copy and send the text back. (It stores and sends nothing.)" },
      expect = "Zennit's own lines show as readable on his client; the friend's client says readable or secret for his", fails = "the lines are secret values: logging what he says is not possible, at least there" },
}

local byId = {}
for i, c in ipairs(Check.LIST) do c.n = i; byId[c.id] = c end
Check.byId = byId

----------------------------------------------------------------------
-- Results (kept in the saved variables)
----------------------------------------------------------------------
local function store()
    ST.db.checks = ST.db.checks or {}
    return ST.db.checks
end

-- status: "pass", "fail" or "skip". A note is optional.
function Check.Record(id, status, note)
    local c = byId[id]
    if not c then return false, "no such check: " .. tostring(id) end
    if status ~= "pass" and status ~= "fail" and status ~= "skip" then return false, "say pass, fail or skip" end
    store()[id] = { status = status, at = time(), version = ST.version, note = note ~= "" and note or nil }
    return true
end

function Check.Status(id)
    local r = store()[id]
    return r and r.status or "todo", r
end

-- The addon watched this happen: marks it pass unless it already passed (and keeps the first note). Only the admin is told:
-- the checklist is an admin tool, so on a friend's client it is only recorded.
function Check.Seen(id, note)
    if not byId[id] or not ST.db then return end
    if Check.Status(id) == "pass" then return end
    Check.Record(id, "pass", "seen live: " .. tostring(note))
    if ST.IsAdmin() then ST.print(string.format("|cff33ff66Check passed by itself:|r %s (%s)", id, byId[id].title)) end
end

function Check.Counts()
    local n = { pass = 0, fail = 0, skip = 0, todo = 0 }
    for _, c in ipairs(Check.LIST) do
        local s = Check.Status(c.id)
        n[s] = n[s] + 1
    end
    return n
end

-- The first check that needs a person and has no result yet, or nil when they all have one.
function Check.Next()
    for _, c in ipairs(Check.LIST) do
        if c.kind ~= "auto" and Check.Status(c.id) == "todo" then return c.id end
    end
end

-- "3/25": how many have passed out of all of them.
function Check.Summary()
    local n = Check.Counts()
    return string.format("%d/%d", n.pass, #Check.LIST), n
end

function Check.RunAuto()
    local out = {}
    for _, c in ipairs(Check.LIST) do
        if c.kind == "auto" then
            local ok, good, detail = pcall(c.run)
            if not ok then good, detail = false, "ERROR " .. tostring(good) end
            Check.Record(c.id, good and "pass" or "fail", detail)
            out[#out + 1] = { id = c.id, ok = good and true or false, detail = detail, title = c.title, fails = c.fails }
        end
    end
    return out
end

----------------------------------------------------------------------
-- Words
----------------------------------------------------------------------
local ICON = { pass = "|cff33ff66PASS|r", fail = "|cffff4444FAIL|r", skip = "|cff888888skip|r", todo = "|cffffd100todo|r" }

function Check.Overview()
    local out, n = {}, Check.Counts()
    out[1] = string.format("Live checks for v%s: %d pass, %d fail, %d skipped, %d to do. /sc check <id> shows the steps; /sc check pass <id> [note] records one; /sc check auto runs the automatic ones.",
        tostring(ST.version), n.pass, n.fail, n.skip, n.todo)
    local group
    for _, c in ipairs(Check.LIST) do
        if c.kind ~= group then
            group = c.kind
            out[#out + 1] = ({ auto = "By themselves:", solo = "By yourself:", duo = "With a friend:" })[group]
        end
        out[#out + 1] = string.format("  %s %s  %s", ICON[Check.Status(c.id)], c.id, c.title)
    end
    return out
end

function Check.Detail(id)
    local c = byId[id]
    if not c then return { "No such check: " .. tostring(id) } end
    local status, r = Check.Status(id)
    local out = { string.format("%s  %s  [%s] %s", id, c.title, status, r and r.note and ("(" .. r.note .. ")") or "") }
    if c.kind == "auto" then
        out[#out + 1] = "Runs by itself: /sc check auto."
    else
        for i, s in ipairs(c.steps or {}) do out[#out + 1] = string.format("  %d. %s", i, s) end
        out[#out + 1] = "  Expect: " .. (c.expect or "it works") .. "."
        if c.seen then out[#out + 1] = "  The addon marks this itself when it sees it happen." end
        out[#out + 1] = string.format("  Then: /sc check pass %s [note]  or  /sc check fail %s [what happened]", id, id)
    end
    if c.fails then out[#out + 1] = "  If it fails: " .. c.fails .. "." end
    return out
end

-- The text to paste back: the counts, every failure or open item with its note, and the recent trace.
function Check.ReportText()
    local n = Check.Counts()
    local out = { string.format("Summon Core v%s live checks: %d pass, %d fail, %d skipped, %d to do.", tostring(ST.version), n.pass, n.fail, n.skip, n.todo) }
    for _, c in ipairs(Check.LIST) do
        local s, r = Check.Status(c.id)
        if s ~= "pass" or (r and r.note) then
            out[#out + 1] = string.format("%s %s: %s%s", s:upper(), c.id, c.title, r and r.note and (" -- " .. r.note) or "")
        end
    end
    out[#out + 1] = string.format("Errors caught this session: %d.", #ST.errors)
    for i = math.max(1, #ST.errors - 4), #ST.errors do
        local e = ST.errors[i]
        out[#out + 1] = string.format("  error in %s: %s", e.name, e.msg)
    end
    out[#out + 1] = "Trace (newest last):"
    for i = math.max(1, #ST.trace - 14), #ST.trace do
        local t = ST.trace[i]
        out[#out + 1] = string.format("  %s %s", date("%H:%M:%S", t.time), t.text)
    end
    return out
end

----------------------------------------------------------------------
-- The command and the copy window
----------------------------------------------------------------------
local window
local function showCopy(text)
    if not window then
        window = CreateFrame("Frame", "SummonCoreCheckReport", UIParent, "BasicFrameTemplateWithInset")
        window:SetSize(640, 420)
        window:SetPoint("CENTER")
        window:SetFrameStrata("DIALOG")
        window.TitleText:SetText("Summon Core live checks (Ctrl+A, Ctrl+C)")
        local sf = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 12, -30)
        sf:SetPoint("BOTTOMRIGHT", -32, 12)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(580)
        eb:SetScript("OnEscapePressed", function() window:Hide() end)
        sf:SetScrollChild(eb)
        window.edit = eb
    end
    window.edit:SetText(text)
    window:Show()
    window.edit:SetFocus()
    window.edit:HighlightText()
end

-- Chat colour codes removed, for text that is going to be pasted.
function Check.Plain(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Opens the copy window with this text (the Tools tab's COPY button: the output box there cannot be selected).
function Check.Copy(text)
    text = Check.Plain(text)
    if text == "" then return ST.print("There is nothing to copy yet. Run something first.") end
    if CreateFrame then showCopy(text) end
end

-- The lines a command prints, as the one text its copy window holds: the same lines, one to a row, without colour codes.
function Check.Joined(lines)
    return Check.Plain(table.concat(lines, "\n"))
end

-- Opens the copy window with these lines (/sc report copy, /sc rules copy). Returns the text it holds.
function Check.CopyLines(lines)
    local text = Check.Joined(lines)
    Check.Copy(text)
    return text
end

-- /sc check [auto | trace | report | reset | <id> | pass|fail|skip <id> [note]]
function Check.Command(rest)
    rest = rest or ""
    local word, tail = rest:match("^(%S*)%s*(.-)$")
    local function say(lines) for _, l in ipairs(lines) do ST.print(l) end end
    if word == "" then
        say(Check.Overview())
        for _, c in ipairs(Check.LIST) do
            if c.kind == "auto" and Check.Status(c.id) == "todo" then
                return ST.print("Start with /sc check auto: it runs the automatic checks by itself, then come back here for the rest.")
            end
        end
        local nextId = Check.Next()
        if nextId then
            ST.print("Next: " .. nextId)
            return say(Check.Detail(nextId))
        end
        return
    elseif word == "auto" then
        local results = Check.RunAuto()
        for _, r in ipairs(results) do
            ST.print(string.format("%s %s: %s (%s)%s", r.ok and ICON.pass or ICON.fail, r.id, r.title, tostring(r.detail),
                r.ok and "" or ("  If it fails: " .. tostring(r.fails))))
        end
        local n = Check.Counts()
        return ST.print(string.format("%d pass, %d fail so far. /sc check for the rest.", n.pass, n.fail))
    elseif word == "trace" then
        if #ST.trace == 0 then return ST.print("Nothing traced yet: it records the summon prompt and the answers as they happen.") end
        for _, t in ipairs(ST.trace) do ST.print(string.format("%s %s", date("%H:%M:%S", t.time), t.text)) end
        return
    elseif word == "report" then
        local text = table.concat(Check.ReportText(), "\n")
        if CreateFrame then showCopy(text) end
        return say(Check.ReportText())
    elseif word == "reset" then
        ST.db.checks = {}
        return ST.print("Live check results cleared.")
    elseif word == "pass" or word == "fail" or word == "skip" then
        local id, note = tail:match("^(%S+)%s*(.-)$")
        if not id then return ST.print("usage: /sc check " .. word .. " <id> [note]") end
        local ok, err = Check.Record(id, word, note)
        return ST.print(ok and string.format("%s: %s", id, word) or err)
    elseif byId[word] then
        return say(Check.Detail(word))
    end
    ST.print("usage: /sc check [auto | trace | report | reset | <id> | pass|fail|skip <id> [note]]")
end
