# Summon Core

A Ritual of Summoning logger for WoW Forever (12.0 addon API). It records each summon you complete,
credits the target and both assistants, shares the log with other users of the addon, and scores each
summon by destination, then turns the scores into a weekly contest, a season and a story ("Zennit and the Index").
Status: **v0.30.0, work in progress**. See [Status](#status) for what has and has
not been tested in the live client.

## For friends

**Install.** With WowUp: Get Addons > Install from URL, paste `https://github.com/summoncore/summoncore`, and install; WowUp
then offers each new version as an update. It is also on CurseForge (project 1731543). By hand: download the newest zip from
the GitHub Releases page and unzip it into `World of Warcraft\_classic_beta_\Interface\AddOns\`, so that the folder is
`AddOns\summoncore`. If it does not show in the game's AddOns list, tick "Load out of date AddOns".

**What changes for you.** Nothing you have to do: cast and click portals as usual. Whoever casts the ritual should have the addon,
so the summons is logged with its place and its helpers, and summons of Zennit count for the group in the weekly race. At your
first login the Index says three lines of welcome (`/sc welcome` says them again).

- `/sc` opens the window. `/sc intro` is the story (about four minutes), `/sc tour` shows you round the window (about six),
  `/sc rules` is the race in a minute, and `/sc week` is how this week stands. `/sc help` lists the rest.
- Once a week the Index asks how the last week was: three buttons, or close it to skip.

**Keep it updated.** Everyone should be on the same version. An older one still syncs, but it can count or say things
differently; the addon says so when a friend's version differs from yours.

**Something wrong?** `/sc errors` lists any problem the addon caught in itself. Send Aaron what it says.

## Install

Copy this folder to `World of Warcraft\_classic_beta_\Interface\AddOns\summoncore\` (the folder name must
match `summoncore.toc`). The TOC uses interface `16001`, which matches client 1.60.1 build 70205. If the
addon does not appear, enable "Load out of date AddOns".

**With WowUp:** Get Addons > Install from URL, paste `https://github.com/summoncore/summoncore`, and install. WowUp
then offers each new release as an update. It installs the newest GitHub release, so a version only reaches WowUp once
it is released: push a tag `v<version>`, or run Actions > Release on master (it tags the TOC version itself). Each
release carries a `release.json` (the BigWigs packager's metadata) that lists the zip for every game flavour, which is
what lets WowUp offer it to a Classic Beta install.

**The icon** is `Media/icon.tga` (256x256), which `## IconTexture` in the TOC shows next to the addon in the game's
AddOns list (where the client supports it). `tools/make_icon.ps1` draws it, with a 512 px PNG in `tools/icon/`. WowUp
shows the GitHub owner's avatar for an addon installed from GitHub, not this file.

Saved data lives in `WTF\Account\<account>\SavedVariables\summoncore.lua` (`SummonTrackerDB`).

**Who needs it.** Only the caster's client sees a Ritual of Summoning, so whoever casts should run Summon Core for the summons to be
logged with its place and helpers; Zennit needs it for his answers (what he presses at the game's prompt) to be his. Helpers are
credited from the caster's snapshot either way. **When the caster does not have it,** Zennit's client files the summons itself once he
answers the game's prompt and no record of it has arrived within a few seconds: the caster from the prompt (or the only warlock in his
group), the place from where he arrives (or, if he declines, from a helper's client), and the helpers only if someone in the group
runs the addon. Every client in the group that is not casting watches who channels a ritual and sends Zennit's client a note (`W`);
a helper's own client also gives the place. If the caster's own record turns up later, it replaces the filed one and his answer
moves to it. Nothing is filed if he never answers the prompt, and no writ can be played without the caster's addon. On the first login the addon says a
three-line welcome to this effect (`/sc welcome` says it again).

## Commands

| Command | What it does |
|---|---|
| `/sc` (also `/summoncore`) | Open the Summon Core window: Party (Summary, Tally, Leaders and Badges), Zennit (his answers), Log, Story, Sync and Tools tabs; the Party tab is closed to Zennit (he gets the "ah ah ah" gag) and Zennit's tab to the party (a gag of its own; the admin can open both); Story is a talent tree: the intro on top, then one trunk for Zennit and one for the group, a chapter per weekly win, with the next win pulsing, the reached chapters lit (click to play) and the rest hidden until the weekly race reaches them (everything below is in it too) |
| `/sc help` | Five lines: the commands a player needs (the window, rules, week, tab, cards, titles, report, seasons). `/sc help all` lists every command |
| `/sc errors [clear]` | The problems the addon caught in itself this session. Every slash command, event handler, login step and hub tab runs under a guard: a bug no longer fails silently (WoW shows nothing by default) or stops the steps after it; it is said once in chat, kept here, and still passed to the game's own error handler. Tell Aaron what it says |
| `/sc tips [on\|off]` | The one-line tip about a command, said once a Monday at login (they go round in order; two are for Zennit's client only). `/sc tips off` stops it |
| `/sc feelings [on\|off]` | **The weekly question**: once a week, at the first login after a week with summons, the Index asks "How was last week?" with three buttons (Good fun / It was fine / Not for me); Zennit is asked "How was being summoned?" (Bring it on / Fine / Too much). Close it to skip; `off` stops it. Answers go only to Zennit's and the admin's clients (each client re-sends its own with its hello, so they catch up), where `/sc feelings` (and Tools > General > How it felt, for the admin) shows **counts per week, never names** |
| `/sc panel` | Open the window on the Party tab |
| `/sc log [n]` | Recent summons |
| `/sc tally` | Cast, received and assisted counts and points per player, ranked by summons of Zennit this season (what the race counts), then points. The Party tab's Tally is the same list, with an "Of Zennit" column |
| `/sc badges` | Badge list |
| `/sc writ` | Arm a writ for your next ritual on Zennit (two a week): if he declines that summons in the game, it costs him its points. Again to withdraw it. It is also a **key binding** (Esc > Options > Key Bindings > AddOns > Summon Core: "Play a writ on your next summons of Zennit"), so it is one key in the middle of play; the binding (`Bindings.xml`) has never been tried in the client |
| `/sc week copy` | Opens the same "Week:" line `/sc week say` would send, in the copy window, to paste where you choose (nothing is sent). It says why not under the old rules |
| `/sc week say` | Tell the group (party or raid chat) where the week stands, in one line: the lead, his dice left, the last call. It uses `C_ChatInfo.SendChatMessage` (the global `SendChatMessage` is only a deprecation fallback on this client, kept as a last resort), which has never been tried under the 12.0 chat rules |
| `/sc check` | Admin only. The live-client checklist (`design/verification.md`), also the Tools tab's Checks section (RUN AUTO, NEXT, PASS, FAIL, SKIP, TRACE, REPORT, COPY: the output box cannot be selected, so COPY opens its text in a window that can): `/sc check auto` runs the automatic checks, `/sc check <id>` gives the steps for the rest, `pass`/`fail`/`skip <id> [note]` records a result, `trace` shows what the summon prompt did, `report` opens a copyable report to send back. Some checks turn green on their own when they happen for real |
| `/sc where` | Current map ID, subzone and how it scores |
| `/sc places` | What a place is worth (a city 1, a zone 3, a dungeon entrance 5, a far-flung place 10) and every map ID in the table, checked against the game's own name for it; a wrong or missing one is flagged. The ritual briefing on Zennit also says what the place you stand in is worth |
| `/sc undo` | Remove the newest summon you cast (earned badges are kept). Nobody can undo someone else's, and the deletion is shared so sync does not bring it back |
| `/sc admin` | Admin only. What the game reports as this account's BattleTag, and whether it is the admin's or Zennit's |
| `/sc reset [all]` | Wipe this client's summons, badges and story (it asks first). `all` is admin only: it asks everyone else to do the same |
| `/sc season [start\|stop]` | Whether a season is running. `start` and `stop` are admin only (each asks first): `stop` ends the season in progress now, with no finale; `start` begins a new one, 0 to 0, from this week. Everyone's client hears of it, now or at its next hello. Also Tools > General > **The season** |
| `/sc asplayer` | Admin's account only: see the addon as a player does (admin tools, help lines and spoilers hidden), and back. Also Tools > General > **View as player** |
| `/sc export`, `/sc import` | Import / Export window (copy-paste strings of the summon log) |
| `/sc sync` | Send a HELLO to party and guild, show sync status |
| `/sc synctest` | Admin only. Run the sync self-test with simulated clients (scratch data only) |
| `/sc comic [size]` | Admin only. Large-image test viewer (generate the textures first, see below) |
| `/sc test` | Admin only. Diagnostics panel; `/sc test ping <name>` adds a whisper ping |
| `/sc debug` | Admin only. Toggle detector messages |
| `/sc fake <target> [h1 h2]` | Admin only. Add a test summon (never broadcast) |
| `/sc fakeprompt <target> <members...>` | Admin only. Open the assistants prompt without a party |
| `/sc intro [scene\|z1..z5\|g1..g5\|2a\|2z1..\|now\|check]` | Play the illustrated story, "Zennit and the Index" (32 scenes, then "The Index today", which follows the season; season two's 26 scenes come after it); a scene number starts there, a chapter key plays that chapter (`2a`, `2b`, `2z1`, `2g1`... are season two's: see [Season two](#season-two)), `now` plays only "The Index today", `check` tests the sound files |
| `/sc titles` | Who leads each of the season's titles so far, with who is close behind: the heaviest hand, the best supporting role (assists), the lucky pair (whose bonus tipped most rolls), the prompt payer, the process server (whose writs cost him the most points), and Zennit's kind ones (the dice goblin, the hard bargain, the quick reply, and the good sport: ten summons or more that he went on in the season). The Index names them for good in the finale's keepsake. Praise in words, no points. Also the Tools tab's **The titles** |
| `/sc tab` | The silver tab as a statement: on Zennit's client, who owes him what across every week and what has been paid; on anyone else's, what you owe him and your card's punches. Also the Tools tab's **The tab** |
| `/sc leaders` (also `/sc leaderboard`) | **The leaderboard**, the top ten of two boards: who has summoned Zennit most (this season, which is what the race counts, then this week and in all) and who has given him the most fish (this week and in all, from the totals his client shares). The Party tab's **Leaders** section shows both in full, side by side; the Tools tab's **Leaderboard** prints them, which is how Zennit (who cannot open the Party tab) sees them. Rankings give no gag away, so his client shows them too |
| `/sc fish` | **The fish book**: on Zennit's client, who has given him fish and how many (this week and in all), by giver and by kind. Fish **traded** to him (counted when the trade completes) or **mailed** to him (counted as he takes them from the mail) go in by themselves; a mail no player sent (the Auction House) and, when the game does not say, one from a stranger are left out, as for silver. A fish is known by its item ID (the old world's raw and cooked fish) or a fish word in its name (cod, salmon, eel, anything ending in "fish"...), never a rod, bait or recipe. His client also has `/sc fish add <name> <count> [what]` to write one in by hand and `/sc fish undo` to take the newest out. The book stays on his client, but each giver's totals are shared with everyone (message `P`, only from his characters), so anyone's `/sc fish` lists the givers. Also the Tools tab's **Fish** |
| `/sc cards` | Who holds a summon card and how many punches are left. `/sc card` explains cards; Zennit's own: `/sc card sell <name> [punches [silver]]` and `/sc card offer <punches> <silver>`. Also the Tools tab's **Summon cards** |
| `/sc probe` | Listens to trade and mail events and prints what the client lets an addon see (who, how much, or a secret value), to learn how the fifty silver could be detected. Run it again to stop |
| `/sc probe chat` | The same kind of probe for chat (`Probe.lua`): listens to say, yell, party and raid chat and to the events around a summons arriving, and prints whether the text and the sender are readable or secret values, how long the text is, and how long after the summons prompt each event came. Your own words are printed, other players' never (only whether they could be read). It stores and sends nothing; it is there to learn whether logging what Zennit says after he arrives is possible. Run it again to stop; `/sc probe chat copy` opens what it printed in a window to copy |
| `/sc report` | What the log says about how the race is being played, for a playtest: summons a week, wins by how many summons counted, his answers and how fast, how he spends his dice, the list's hit rate, the helpers, whether he closes. The chat window cannot be selected, so `/sc report copy` opens the same text in a window to copy from (Ctrl+A, Ctrl+C), then paste it into the group chat. Also the Tools tab's **Playtest report**, which prints it and hands it to its COPY button; the script is `design/playtest.md` |
| `/sc rules` | The rules of the race on one card, with this week's live numbers (the cap and the close, his dice and edge with the catch-up and the whim, what a helper adds, his list, the points by place). `/sc rules copy` opens it in the copy window. Also the Tools tab's **The rules**, which prints it and hands it to COPY |
| `/sc seasons` | The Index's keepsake of each finished season, newest first: how it ended and how long it took, who was in the room (everyone who summoned him or helped), the silver paid, and a moment or two by name. Also the Tools tab's **Past seasons**, and printed in chat when a finale lands |
| `/sc tour [step]` | **The tour**: a narrated walk round the window for newcomers, in the Index's voice (about six minutes). It opens the window, moves through the tabs by itself and outlines each part in amber while the narrator talks about it, then shows copies of the popups a player meets (the caster's helpers prompt, the dice, the weekly question; on Zennit's client, his "A SUMMONING!" form and its four choices) with made-up names and buttons that do nothing, since the real ones would file a summons or make a real roll; then where points come from (a city 1, a zone 3, a dungeon entrance 5, a far-flung place 10, and `/sc where`), the briefing a caster gets in chat, the writ and its key binding, and `/sc week say`; on Zennit's client also summon cards and his out-of-office; then the game's own dialogs, shown for real with nothing behind their buttons (and never over a real one): "Watch now?" when someone shows the group a chapter, the admin's reset request, and on Zennit's client the silver price box and the payment that settles the tab; the words are typed in a box under the window, with BACK, PAUSE, NEXT, SOUND and END TOUR. Zennit's client gets his own lines for the Party and Zennit tabs (and no writ). Closing the window ends it; `/sc tour 5` starts at step 5. **It follows the story**: its jokes lean on the intro, so until this character has watched the intro from its first scene to its last, `/sc tour` plays the intro first and the tour starts by itself when it ends (`/sc tour skip` goes straight to the tour, for anyone who watched it before this was recorded). The first time the intro is seen through, the Index offers the tour once ("Take the tour" / "Later"). Also the Tools tab's **Take the tour**, and the welcome mentions it |
| `/sc welcome` | The three lines a newcomer gets at their first login: taking part needs nothing new, who needs the addon, and where the rules and the story are |
| `/sc intro previously` | **Previously on**: every chapter this season has reached, back to back, in the order the race reached them; closing the window stops it. For anyone catching up (the welcome mentions it). Nobody has to have watched anything to play any reached chapter |
| `/sc intro <key> group` | **Show the group a chapter** (design/lenses.md, Pleasure): it plays here, and everyone else in the party or raid who runs the addon is asked "Watch now?" (a newcomer whose log is still syncing too: the sender's client checked the season has reached it). Chapters unlock by the season's race, not by what you have watched, so nobody has to watch the earlier ones first. When a raid gathers (once a week), its leader is offered last week's chapter, and everyone else is told the command |
| `/sc week login` | Says this week's login lines again: the whim, when the Index closes the week (in your own time), a last call in the week's final day, a tip, and what is waiting for Zennit or what you owe. Last week's result is not repeated |
| `/sc week [z1..z5\|g1..g5\|2z1..]` | The weekly contest and the season: this week and last, whether Zennit is on his week off, and the season standing; a key replays that chapter |
| `/sc clip [category|file]` | Admin only. List or play voice clips from `Media/clips` |
| `/sc zennit list [add <place>\|remove <n>\|clear]` | Zennit's secret list (his client only, never synced; nobody else can edit one). Toward his week off (draft rules): winning the dice earns him the summon's points, a decline that costs takes them off, and a summon that lands at a place on his list earns them again; declining a listed place is free (unless the group played a writ on it). Also editable in the hub's Zennit tab. The list is bounded: at most **5** places of **4 letters or more** (an entry matches any part of a place's name, so a single letter would match most places and decide every week); older entries that are shorter, or past the fifth, stop counting. The list is **set for the week**: a place he adds counts from the next Monday (marked "from Monday"), and removing one takes effect at once, so it cannot be changed with a summons on screen |
| `/sc zennit postcard [<place>: <line>\|clear]` | Zennit writes his own postcard from a far-flung place (80 letters at most), used on every client instead of the Index's default; `clear` puts the default back. Anyone can read them with `/sc zennit postcard [<place>]`; only his characters can write them |
| `/sc zennit away [<line>\|clear]` | His out-of-office: whoever summons him on his week off sees "His out-of-office says: '...'" in the briefing, instead of the Index's "not hopeful" |
| `/sc ask [<question>]` | **Zennit's state, read by his own client** (`Ask.lua`); nothing is put to him and he presses nothing: `hearth` (is his hearthstone in his bags, and ready, or how many minutes are left on it), `playing` (how long he has been logged in; a `/reload` does not reset it). The question goes to the party or raid and the guild; only his client answers, whispering back within a few seconds, and he is told who asked and what the Index said. With no answer in 8 seconds the asker is told so; one question every 5 seconds. On his own client (or in Zennit test mode) it answers without the network. No rule uses an answer yet: it is the mechanism a challenge or a card can call later (`ST.Ask.Ask(key, arg, callback)`). Nothing else in his bags is looked at: what he carries is his business. The item calls have never run in the client (checks `a-ask`, `s-ask`, `d-ask`) |
| `/sc zennit ask [on\|off]` | Whether his client answers `/sc ask` (on until he switches it off); off, the asker is told questions are off |
| `/sc respond [test]` | Zennit answers a summon of him (accept, decline, ask for silver or dice); `test` (admin only) tries it on a pretend summon |
| `/sc gag` | Admin only. Preview the Zennit gag |
| `/sc zenit` | Admin only. Toggle Zennit test mode on this character |
| `/sc party` | Toggle party test mode (admin only): this character acts as an ordinary party member, even on the admin's or Zennit's own account, so Zennit's tab gives the party's gag. It turns Zennit test mode off, and the other way round. Both are also switches on the Tools tab |
| `/sc preview` | Toggle the season preview (admin only; Tools > Testing > PREVIEW NEXT SEASON is the same switch): the Story tab also shows the season after this one, as if it had begun, with its opening and chapters playable, so season two can be looked at before any finale has reached it. Nothing in the log changes |

## How it works

| File | Module | Job |
|---|---|---|
| `Core.lua` | Core | Load order, SavedVariables setup, slash commands |
| `Detector.lua` | Detector | Watches your Ritual of Summoning casts (spell 698), snapshots target, zone and which party or raid members are channeling |
| `Prompt.lua` | Prompt | Asks you to confirm the two assistants when detection is unclear |
| `Store.lua` | Store | The only code that touches `SummonTrackerDB`; tallies are derived from the event log |
| `Sync.lua` | Sync | The only code that touches the network |
| `Scoring.lua` | Scoring | Zone value table, points, badge rules |
| `Theme.lua` | Theme | The "Neon Index" look: windows, buttons, tabs, text boxes and scroll areas, all drawn from flat colours |
| `Respond.lua` | Respond | Zennit's answer to a summon of him (accept, decline, ask for silver, dice) |
| `Week.lua` | Week | The weekly contest, his week off, and the season; all derived from the log |
| `Reset.lua` | Reset | `/sc reset`: wipe this client, and the admin's request to everyone else |
| `Export.lua` | Export | Import / Export window and the string codec |
| `Tour.lua`, `TourClips.lua` | Tour | `/sc tour`, the narrated tour of the window (`TourClips.lua` is generated) |
| `Intro.lua`, `IntroCues.lua`, `Comic.lua` | Intro | The illustrated story player, its generated timings, and the large-image test viewer |
| `Voice.lua` | Voice | Pools of lines: the Index says a fact that repeats a few different ways, never the same one twice running |
| `Cards.lua` | Cards | Summon cards: prepaid silver Zennit sells, with punches counted from the log |
| `Silver.lua` | Silver | The money side: on Zennit's client, sees silver arrive by trade or mail and asks him what it pays; `/sc probe` |
| `Fish.lua` | Fish | The fish book: on Zennit's client, counts fish traded or mailed to him, by giver, and shares the totals; `/sc fish` |
| `Leaders.lua` | Leaders | The leaderboard: summons of Zennit and fish given to him, ranked; `/sc leaders` |
| `Probe.lua` | Probe | What the client lets an addon read of chat and of a summons arriving: `/sc probe chat` |
| `Ask.lua` | Ask | Questions only Zennit's client can answer (`/sc ask`): the questions, asking with a timeout, and his client's answers |
| `Report.lua` | Report | `/sc report`: the playtest numbers, worked out from the log |
| `Ledger.lua` | Ledger | "The Index today": the intro's last scene, written from the season tree each time it plays; and the log's memory of a season (named moments, the silver, the keepsake) |
| `Clips.lua`, `ClipList.lua` | Clips | Voice clips from `Media/clips` (`ClipList.lua` is generated) |
| `Hub.lua`, `Gag.lua` | UI | The one-window hub (tabs for the party, Zennit, the log, the story, sync and tools), and the Zennit access-denied gag |
| `Tests.lua`, `SyncTest.lua` | | Live-client diagnostics and the self-test (`/sc synctest`, admin only) |

Only the caster's client needs to see a summon; everyone else is credited from the caster's snapshot.

### Look

Every window the players use (the hub, the assistants prompt, Zennit's answer popup, the dice prompt, Import / Export,
and the intro's buttons) is drawn in one style, the "Neon Index": green-on-black terminal panels, cyan for the summoners,
pink for Zennit and amber for his answers. The hub shows the season race (each side's weekly wins out of five, and this
week's score) above every tab, and a command prompt with the log and sync counts along the bottom. `Theme.lua` holds the
colours and the pieces; there is no art to rebuild. The font is VT323 (`Media/fonts/VT323-Regular.ttf`, SIL Open Font
License, `Media/fonts/VT323-OFL.txt`); if the game cannot load it, the standard font is used instead. The admin tools
(Diagnostics, the large-image test) keep the standard Blizzard look.

### Assistants

Exactly two group members seen channeling the ritual are credited automatically, in a party or anywhere in a
raid. With any other count, the prompt opens with the detected helpers ticked (listed first; in a raid the list
stops at 12). It saves itself as ticked after 20 seconds, so you only need to touch it to correct the names;
changing a tick stops the countdown. Solo or in a two-person party it saves without asking.

### Scoring

Placeholder values, meant to be argued about. Edit the tables at the top of `Scoring.lua`.

| Kind | Points | Matched by |
|---|---|---|
| city | 1 | `mapKinds` (map ID) |
| zone | 3 | default for unlisted maps |
| dungeon | 5 | `subzoneKinds` (lowercase subzone text) |
| remote | 10 | `mapKinds` (ten far-flung zones, such as Silithus and Winterspring) or `subzoneKinds` |

A dungeon entrance sits inside an ordinary outdoor map, so it is matched by subzone. Stand at the spot and
run `/sc where` to read the exact string. Points go to the caster only.

Badges, named as the Index would (the Badges tab says what each takes): Entered in the Index (a first summons), Filed in Triplicate (ten), A Volume of Their Own (fifty), Admitted Below Stairs (a dungeon entrance), Beyond the Index's Jurisdiction (a far-flung place), Stamped in Five Places (five different maps), and four that come later and come from the log: Known to the Clerk (summoned him in four different weeks), Countersigned by Witnesses (helpers tipped a roll of yours), Paid in Full, No Receipt (your tab is clear) and Stamped to the Last Punch (used up a card). They are for the people who cast; helpers get titles, not badges.

### Sync

Sync shares events, not totals, so merging is a set union and nothing is double-counted. Messages use the
`SUMMONSYNC` prefix: `H` (hello), `E` (new event, broadcast), `R` (request, whispered), `B` (batch,
whispered, one record each, about 3 per second). Others: `Z` (Zennit's answer), `D` and `S` (the dice),
`T` (a summon its caster deleted), `K` (a summon card Zennit sold), `P` (one giver's fish totals, from Zennit's client only; the newest per giver wins, and a total of 0 takes them off the board), `A` (Zennit's client names the character he is playing, so others learn his
alts), `X` (a request to reset), `F` (how a player felt about a week, kept only by Zennit's and the admin's clients), `V` (a chapter shown to the group, party or raid only), `L` (a line Zennit wrote for himself: a postcard or his out-of-office, only from his characters, the newest kept) `W` (what a group member saw of a ritual, kept only by Zennit's client: see below), `Q` and `Y` (a question for Zennit's client, sent to the group and the guild, and his answer whispered back to whoever asked: `/sc ask`) and `C` (the admin started or stopped
a season: see [The season](#the-season)). AceComm, LibSerialize and LibDeflate are not used; the addon has its own
small encoder and send queue.

A `H` carries the number of summons, the latest summon time, the version, the time of the newest answer from
Zennit, the newest reset everyone was asked to make (with the admin's stamp; a player's own reset is never sent) and the time of
the newest season mark, so a peer notices a missing summon, a changed answer, a missed reset or a missed season start or stop
(season marks are sent in reply to its `R`).

Merge rules:
- Same event ID: keep the confirmed copy; if both are (or neither is), keep the earlier write.
- Your own events are authoritative and nobody can add one against you.
- A live `E` is accepted only if the sender is the caster, or, for a record Zennit's client filed (a 12th field names him), Zennit.
  Only the summoned can file one, and only a summons of himself.
- A `B` is accepted only by whisper and only soon after you sent a `R` to that sender (the window renews with
  each batch message, so a long log still arrives whole).
- A deleted summon stays deleted: only its caster can send the `T`, and a copy of it is refused afterwards.
- Anything from before the last reset is refused.
- Of two answers from Zennit for one summon, the later wins.
- Points and kind are recomputed locally, never read from the wire.
- Messages from a newer protocol major version are ignored.

### Export and import

`/sc export` opens a window with the whole log as a string (compressed and base64-encoded, starting `!ST1!`);
`Export mine` limits it to summons you cast. To import, paste a string, press **Preview** to see how many are
new, would replace an existing copy, are already known or are rejected, then press **Import**. Imports use
the same merge rules as sync, with one difference: because you are doing it yourself, your own events missing
from your log can be restored, but an event you already have is never overwritten. Damaged, truncated or
newer-version strings are refused. This is the manual fallback if addon messages turn out to be restricted.

### Tour

`/sc tour` is the how-to, told by the same narrator as the story. Its words are the `LINES` table at the top of `Tour.lua`
(one sentence each, an id per line) and its order is `STEPS` (which tab to show, what to outline: the window, the season band,
this week, a tab, a Party section or the status line, via `Hub.Spot`, or a part of a popup copy from `DEMOS`). Each line is one recording, `Media/tour/<id>.ogg`,
rendered with the intro's recipe by `tools/intro/build_tour_audio.py` (`--stale` renders only the lines whose words
changed; it rewrites `TourClips.lua`, the lengths that time each step), and `tools/intro/check_audio.py` covers them too.
The voice is given `/sc` as "slash S C". A line with no recording is still typed, and its step lasts long enough to read it.

### Intro

`/sc intro` plays "Zennit and the Index": 32 scenes (scenes 1-10 are chapter 1; the rest are the season's chapters, see
[The season](#the-season)) of 3-frame flipbook art (about six flips a second), narrated, with
a quiet synth music bed. The whole narration is typed out, a sentence at a time and in step with the
voice, in a green-on-black terminal box under the picture, with a chirp and key clicks at each sentence. While the narrator mentions something (the three kinds of ritual, the book, the form, Zennit), a pulsing box lights up that part of the picture. The **Text**
button cycles: `full` (that box), `key` (only the punchlines, flashed over the picture) and `off`. Controls: previous/next scene, play/pause, restart, a Size button (small, medium,
large), a Look button
(`lines`: neon line drawing on black, the default; `storybook`: the original colours), and toggles for Sound and Music. `/sc intro 3` starts at
scene 3. `/sc intro check` tries every intro sound
file and lists the ones the game cannot play (after adding or replacing media, restart WoW: `/reload` does not pick
up new files). The art lives in `Media/intro_l<n>.blp` (lines) and `intro_<n>.blp` (storybook), one per scene: 2048x1024 sheets, DXT1, about 1.3 MB each.
`tools/intro/render_intro.ps1` rebuilds them from `tools/intro/source.html` using headless Edge or Chrome
(`-Format tga` writes uncompressed TGAs instead if BLPs misbehave in your client).

**Rebuilding the pieces** (needs ffmpeg for the audio, Edge or Chrome for the art):

- `tools/intro/render_intro.ps1 [-Style lines|storybook] [-SceneList 1,2]`: the picture sheets (`intro_l<n>.blp` for lines, `intro_<n>.blp` for storybook).
- `tools/intro/build_audio.ps1`: reads the narration takes in `tools/intro/narration/`, synthesises the music bed
  and the beeps, chirps and key clicks (`Media/sfx/`), mixes `Media/intro_<n>.ogg` (voice plus music, which ducks
  under the voice and swells in the pauses) and `Media/intro_<n>_voice.ogg` (voice only), and writes
  `IntroCues.lua` (scene lengths, key phrases, sentence times, and the highlight boxes: edit `$highlightSpec` in that script to change what lights up and when). The key phrases and what they say are listed in that script; each is timed from where its
  sentence sits in the audio (silence detection between sentences) and where the phrase sits in the sentence.
  Nothing is sampled from any existing recording.

The intro does not end where the recording does. After scene 10 it plays **The Index today** (`Ledger.lua`), a scene
written from the season each time it plays, so the story moves with the tree: who leads the season, how far down each
trunk the race has got (a line for the latest win on each side, and only for chapters already reached, so nothing is
spoiled), a warning when a side is one win from its finale, how the last season ended once there has been one, and how
this week stands (his week off, the Index closed, or the lead and the summons filed). Its picture is the latest chapter
reached, or "The week" before any. It is typed out under the key clicks, and the sentences that never change (the recaps, how last season ended, the empty file, the one-win warnings, the quiet weeks) are voiced from clips in `Media/ledger` (made by `tools/intro/build_ledger_audio.py` from the `LINES` table in `Ledger.lua`); the lines that carry a name or a number are never the same
twice, and it now tells the season's named moments (the roll a helper pair tipped, who has summoned him most, a run of dice he won) and the silver he has been paid, all worked out from the log; `/sc intro now` plays it alone. Tune the wording in `Ledger.lua` (`LINES` and `Ledger.Build`), then rerun the script for the voiced lines.

Scenes 9 and 10 explain the weekly challenge: only summons of Zennit count (summons between friends count for nothing), the group earns points by place, ten summons a week count, Zennit holds a secret list of five places that pays him too, and he may refuse, ask for fifty silver, suggest dice (three a week, which helpers can lean on), close the Index once five are filed, go on leave when he wins a week (summons of him are then filler), and the Index leans toward the side that is behind, with a whim some weeks. The first to five weeks takes the season. Both takes were re-voiced for this wording; when the words of any scene change, `python tools/intro/check_audio.py` lists the takes that no longer match, and `.claude/skills/zenit-narrator-audio` re-renders them (WoW then needs a full restart).

The narration is `Media/intro_1.ogg` to `intro_32.ogg`, and `intro_34.ogg` to `intro_59.ogg` for season two (scene 33 is "The Index today", which has no clip of its own) (the "rp" voice takes mixed with the music bed; `intro_<n>_voice.ogg` is voice only), one clip per scene, because
`PlaySoundFile` cannot start partway into a file, so pausing and resuming replays the current scene from its
start. Each clip is the length of its scene. The viewer plays them on the Dialog sound channel; the Sound button
mutes the narration.

### Voice clips

Drop `.ogg` takes into `Media/clips/`, named `<category>_<NN>_<who>.ogg`: `wag_01_aaron`, `zenit_land_02_sam`,
`zenit_refuse_03_sam`, `ritual_02_lewis`, `narrator_weekopen_01_lewis`. AddOns cannot list a folder, so run
`powershell -ExecutionPolicy Bypass -File tools\build_clip_manifest.ps1` (it writes `ClipList.lua` and warns about
badly named files), then `/reload`. `/sc clip` lists the categories; `/sc clip wag` or a file name plays one. The
addon picks a random clip per category and avoids repeating the last one. Plays on the Dialog sound channel.

- `wag`: used for the Zennit gag instead of the built-in sound.
- `zenit_land`: played on Zennit's client when a friend's live summon of him arrives.
- `zenit_refuse`: when Zennit refuses a summon (his client and the summoner's). `zenit_win`: when he wins the dice. `ritual`: as a ritual begins on your client. `narrator_weekopen`: when a finished week is announced.
  Clips are silent until recorded. The only take so far, `zenit_unsorted_01_aaron`, is in no category yet, so all of them are silent.

The house style for every line the addon says (the deadpan Index, the words to use, what stays plain) is `design/voice.md`; add to it when a new line breaks it.

`design/recording-sheet.md` lists lines to record for each category and how to convert and name the takes (it is in the repo, so treat its lines as prompts: Zennit can read them).

The clips are committed with the rest of the addon (and so go into the release zip), which means Zennit can listen to them in the
repo: the lines meant to surprise him will not be a surprise if he looks. Run the manifest script after adding clips and commit
`ClipList.lua` with them.

### Silver and summon cards

When Zennit asks for silver, **the summons counts at once** and the silver goes on the caster's **tab**: asking can never be a way
to reject a summons (it used to hold the points back until the silver was paid, which made a free, unlimited refusal that the group got the
blame for). **He names the price** (50 is only the default), and a holder of a card pays with a punch instead. The silver is paid in person.
Two things make it visible and countable:

- **Seeing it arrive** (Zennit's client only, `Silver.lua`). When money comes in by **trade** (a completed trade where the other side
  offered money) or **mail** (taking money from the mailbox), the addon works out what it pays and **asks him before touching anything**:
  "Bo paid you 200s by trade. Mark 1 of Bo's summons paid (200 silver)?" The payment covers the payer's oldest owed summons, each in full; if what is
  left covers his card offer, it offers to sell a card as well. A payment that settles nothing is only mentioned in chat. If the client
  hides the money from addons (the 12.0 API hides some values), it says so once, and `/sc probe` shows what does come through: it listens
  to the same trade and mail events and prints who, how much, or a secret value. **None of this has been tried in the live client.**
- **Summon cards, like a coffee card** (`Cards.lua`). A card is **prepaid silver**: N punches bought once at a price Zennit sets
  (`/sc card offer 5 200`: five punches for 200 silver, against 250 at the counter). Each time he asks for silver from the
  holder, **a punch pays it** at the card's price per punch and the Index says so ("Bo's card pays the 40 silver: a punch used, 3 left");
  his popup's button reads "Take a punch (card: 3 left)". Cards are issued only by Zennit's client (`/sc card sell Bo`, or from the payment popup) and sent to
  everyone (message `K`, with his hello and to anyone who asks for events), so a holder can see their balance in `/sc cards`.
  **Punches are not stored anywhere:** they are counted from the summons he settled with a punch (an answer carrying the card flag),
  oldest card first, so every client agrees and nothing drifts. A reset clears the cards with the summons. The answer's flags digit gains
  a bit (4 = paid by a punch): older clients would read it as "closed the Index", so update everyone together.

### Zennit's answer

When a live summon of Zennit reaches his client, a dialog gives him four choices:

| Choice | What happens to the summon |
|---|---|
| Accept it | Counts. |
| Decline | Does not count. Free or not by **one rule**, the same as the game's own Decline (below): free at a place on his list or with his free decline, otherwise it costs him the points, and a writ always costs. The button says **Decline (free)** when it is free, and the line above it says why |
| Ask for silver, in cash, no receipt | **Counts, like an accept.** He names the price (a small box, 50 by default; `50`, `2g`, `1g 20s`) and it goes on the caster's **tab** until he says it was paid ("They paid"); the log shows "owes 200 silver". A holder of a summon card pays with a punch instead, and he is not asked. Asking for silver can never be a way to reject a summons. |
| Roll the dice | One click: he rolls 1-100 (a real `/roll`, so the party sees it, and the rules are said as he waits); the summoner gets a prompt to roll back; Zennit adds 10 to his roll, each of the summoner's helpers (up to two) adds 5 to theirs, higher wins and a tie goes to him. If Zennit wins, the summon does not count. He has 3 dice a week. |

**What he presses in the game is his answer** (`Respond.Real`, and the lens of Resonance in `design/lenses.md`). The game puts its own
Accept / Decline prompt in front of him at the same moment. If he accepts it, the Index records "accepted" and the form is done.
If he declines it, the same rule as the form's Decline applies (`Respond.NoResult`, design/lenses.md, Simplicity/Complexity): the
summons did not happen, so there are no points for the caster, and it is **free** at a place on his list or as his **first decline of
the week** (`Week.RULES.declines`); otherwise it **costs him the summons' points** (a free decline with no limit would let him decide
every week: design/lenses.md, Balance), and a decline of a summons the group played a **writ** on always costs (below).
**Away from his keyboard** (design/lenses.md, Freedom). If he was already AFK when a summons came, and had been for five minutes or
more (`Respond.AWAY_MARGIN`), his client files it as **away** a few seconds after the prompt, unless he answers first: it did not
happen, it costs nobody anything, and it does not use his free decline. A `/afk` typed as the ritual starts does not count. The
caster's briefing warns when he shows as AFK ("It may be worth waiting"). Older clients cannot read the new answer, hence 0.23.0. The lines say
"declined (free)" or "declined (cost him 3)" whichever way he said it; the log keeps `declined`, `excused` and `refused` as before. His popup and his own "Week:" line say how many free declines he has left. A dice roll in flight is ended by what he presses in the game: that is his answer, and no die is spent. If nothing
is seen, the form works as above, and an unanswered summons still counts as accepted. This reads the prompt's own buttons
(`C_SummonInfo.ConfirmSummon` and `CancelSummon`, hooked, not changed), which has never been tried in the live client; where those
are missing it does nothing.

His answer is saved on the event, shown in the Log tab ("Zennit's answer"), and sent to everyone (message `Z`). Only his
own client can answer for him, a newer answer replaces an older one (owes, then paid), and the dice use two more
messages (`D`: his roll to the summoner, `S`: the roll back). Points, tallies and badges only count summons that
land. The same choices are in the hub window's **Zennit** tab (`/sc`, then ANSWER A SUMMON): the summons waiting for his answer with Previous/Next, the four choices drawn in the window, and a list of the ones he has already answered. `/sc respond` reopens the dialog for the latest summon that is still waiting; `/sc respond test` (or the
Tools tab's "Test a summoning") tries it on a pretend summon from "Tester", with a pretend summoner rolling back.

Test summons (`/sc fake`, the buttons that add them, and `respond test`) are marked and stay on that client: they
are not counted for sync, not sent in batches and not exported.

### Zennit mode

If the logged-in character is in `settings.zenitNames` (default `Zennit`), the panel, tally and badges are
hidden and the gag plays instead, and points and badge messages are hidden when he logs a summon. This is
a joke gate for friends, not security: addon files are plain text.

Each clip is a sprite sheet: all frames in one power-of-two texture (`.tga` or `.blp`), played left to right,
top to bottom, plus an optional short `.ogg`. Add an entry to `Gag.clips` in `Gag.lua`:
`{ sheet = { file = ..., cols = 4, rows = 2, frames = 8, fps = 8 }, sound = ... }`. One is picked at random
each time (add `duration = <seconds>` to keep a clip up as long as its recording). The bundled sheet, `Media/gag_wag_sheet.tga` (1024x512, 8 frames of 256), is a neon line-art cartoon man wagging his finger with "AH AH AH!" beside him, in the addon's look (an original drawing), made by
`tools/make_gag_sheet.ps1`; replace it with your friends' frames. Zennit's gag plays `Media/gag_zennit.ogg`, a recording of his voice line (normalised, trimmed and converted from `tools/gag/gag_zennit_source.m4a` with ffmpeg: highpass 80 Hz, loudnorm, limiter, mono Ogg Vorbis); the party's gag on his tab uses the same animation with one of 13 recordings for the party, picked at random and never the same twice running (`Media/gag_party.ogg` and `gag_party_02.ogg` to `gag_party_13.ogg`, from `tools/gag/gag_party_source.m4a` and `tools/gag/party/`, made by `tools/gag/make_gag_audio.ps1`, which also cuts the silence at each end; their lengths are in `Gag.lua`). The diagnostics Sound/flip row looks for `Media/test.ogg`.

### Large images

`/sc comic` shows generated test textures at 256 to 2048 px, at several on-screen sizes or tiled 2x2, and
reports texels per screen pixel. The textures are git-ignored; create them with
`powershell -ExecutionPolicy Bypass -File tools\make_test_patterns.ps1` (about 16 MB in `Media/`). Addon
textures must be `.tga` or `.blp` with power-of-two sides.

## Status

| Area | State |
|---|---|
| Skeleton, diagnostics panel, store, tallies, scoring, badges, panel, Zennit gag | Verified in the live client (solo, with `/sc fake`) |
| Sync merge rules and HELLO/REQUEST/BATCH exchange | Verified with simulated clients: `/sc synctest` passed 103/103 in the live client on 2026-10-06. It has 118 tests now; the ones added since (0.27 to 0.30) have only run outside the game, in a headless Lua 5.1 run with stubbed WoW calls |
| The live-client checklist (`/sc check`, `design/verification.md`) | The automatic checks passed in the live client on 2026-10-06. The checks done with a friend are still to do: they are how the rest of this table gets confirmed |
| Real Ritual of Summoning detection | Verified in the live client (with Poogs): the detector fired and the summons synced. Not yet confirmed: when the game reports the ritual done, which decides whether helpers are seen without the prompt (run one with `/sc debug` on the caster's client). Summons by a caster without the addon are filed by Zennit's client (never run live); what a target presses on the game's own summon prompt is read by hooking `C_SummonInfo` (written, never run live); raid helpers in other subgroups are checked now but not yet tried in a raid |
| Addon messages between two real clients | Verified: party, guild and whisper pings and replies arrive. Names show as `Name Surname` here (not `Name-Realm`), so the addon compares plain first-word names |
| Zennit's answer and the dice between two real clients | Not tested: the `/roll` text parsing, and whether `RandomRoll` is allowed in this client |
| Intro art and sound loading | Not tested after a full restart (`/sc intro check`) |
| Season two (`Season2.lua`) | Built (v0.26.0): seasons counted by finales, its own chapter keys, openings and "Index today" lines, the Story tab's season picker; checked outside the game with the self-test and stubbed WoW calls, never run in the client. Drawn and voiced (v0.27.0): 26 scenes of art, narration and key phrases, and its 13 "Index today" lines, rendered but not yet seen or heard in the client |
| Questions for Zennit's client (`/sc ask`) | Built (v0.28.0) and checked outside the game with the self-test and stubbed WoW calls; never run in the client. Whether the game lets an addon find the hearthstone and read its cooldown is check `a-ask` |
| The tour (`/sc tour`) | Written; never run in the client (check `s-tour`). Nobody has listened to the recordings yet |
| A real Monday rollover of the week and season, and `/sc reset all` reaching friends | Not tested |
| Scoring tables | Ten far-flung places and six cities are matched by map ID from memory; `/sc places` asks the game and flags any ID it does not know or names differently (its automatic check, `a-places`, passed in the live client on 2026-10-06). The dungeon entrance subzone strings are guesses the game cannot look up; confirm each with `/sc where` |
| Gag and voice clips | The gag is an original drawing (`Media/gag_wag_sheet.tga`) with Zennit's recorded line and 13 recorded party lines. The voice clip categories are silent: the one take so far is in no category |
| Release | Published on GitHub (v0.22.0, v0.25.3, v0.26.0) and, from v0.26.0, on CurseForge. Actions > Release publishes the TOC's version; a release zip carries whatever clips are committed |
| 0.28.1: resets, closed weeks, the silver watcher, BattleTag hashes | Checked outside the game only (the self-test and a headless run) |
| 0.29.0: the fish book (fish traded or mailed to Zennit) | Checked outside the game only (the self-test and a headless run); which trade and mail calls the 12.0 client lets an addon read is untested |
| 0.30.0: the leaderboard (summons of Zennit, fish), fish totals shared by sync | Checked outside the game only (the self-test, 118/118 in a headless run) |

Known limits of the 12.0 API: no combat log, party data may be secret, no web requests. Secret values on
other units (`UnitInRange`, `UnitHealth`) were confirmed, so the addon does not rely on them.

## Development

CI (`.github/workflows/ci.yml`) runs luacheck, installed through luarocks, on every push; `.luacheckrc` currently
reports only syntax errors and undefined or accidental globals. There is no Lua on the CI image to run the self-test,
so `/sc synctest` is run in the game. Pushing a tag such as `v0.19.0` (it must match `## Version` in the TOC)
runs `release.yml`, which zips the addon (without `tools/`) and publishes a GitHub release. Test textures
from `tools/` are git-ignored, so release zips do not include them and `/sc comic` shows green squares there.

## Parked for later

**The world tour** (from the group, for later). A challenge to take Zennit on a world tour: summon him to every capital city, and the
group is Alliance, so the Alliance capitals. Notes so far: a city is worth only 1 point and the `/sc places` table already knows the
six cities by map ID (Stormwind, Ironforge, Darnassus and the three Horde ones), so the tour would be its own tally, not a points
thing; it could ride on the log (a summons of Zennit whose place is in the list), the way the badges "Stamped in Five Places" and
"Beyond the Index's Jurisdiction" do, with the Index's voice ("filed in the capital of the Dwarves"). Open questions: which
capitals count on the client's Alliance side (the Exodar, if the client has it), whether it runs inside a season or beside it, and
whether his answer matters (a refused summons is not a stop on the tour). **Partly done:** postcards (design/lenses.md, Secrets) are the same idea aimed at the ten far-flung places, which pull with
the race (10 points) where the capitals (1 point) pull against it; the capitals tour stays parked.

**The Index's request of the week** (design/lenses.md, Indirect Control, C): one far-flung place drawn each week, as the whim is,
named on Monday ("The Index would like a postcard from Felwood this week"); a postcard from it that week adds "as requested". No
points. Parked because it would be a second weekly draw on top of the whim.

**Discord: the Index's noticeboard** (researched, for later; `design/discord.md`). The addon cannot reach the internet, so Discord
can only hear about a week after the fact, never a summons as it happens. The plan, in stages that each stand alone: `/sc report`,
`/sc rules` and the "Week:" line in a copy window; then `/sc discord`, a ready-to-paste digest (the week's result, the season, a
reached chapter, a pinned Record) worded by the addon; then, optionally, a small script on the admin's PC that posts the same text to
one Discord channel after a `/reload` or logout and edits it in place. Nothing comes back into the game, and the secret list, the
feelings and what anyone owes are never posted. The first stage is a fix the playtest needs now (its Monday report cannot be copied
out of the chat window) and is built (`/sc report copy`, `/sc rules copy`, `/sc week copy`); the rest is parked until the first week's report, two checks in the game (saved variables survive a
restart; whether Blizzard's own Discord link is on for Forever) and the group's say, Zennit's above all.

Challenge import strings, emote bonus challenges and Zennit's objective. (Catching summons by warlocks who do not run the addon is
built: Accessibility, G.)

## The weekly contest

Weeks run Monday to Monday (UTC) and are worked out from the event log, so every client agrees. If Zennit's score is at
least the group's at the end of the week, **Zennit wins the week** and the next seven days are his: summoning him gets a
warning, and `/sc week victory` (also offered at login) plays chapter 2 of the story.

From the week of **Monday 5 October 2026** the group has to beat Zennit at his own answers (the reasoning, with the
numbers behind it, is in `design/lenses.md`):

- **Only summons of Zennit count**, up to **10** of them each week. Any after that are logged as usual but "filed under
  'enthusiasm'": the race ignores them. Summons of each other still count for the tally and badges.
- **The Index keeps the season close.** Zennit's edge on the dice (the +10) moves with the season's lead, worked out from
  the weeks before the current one. At a lead of two weekly wins it is **+5** for the side behind: his edge shrinks when
  he is ahead (to +5), and grows when the group is ahead (to +15). At three or more it moves by **10** (to +0, or +20);
  a lead of one changes nothing. The first briefing of the week, the "Week:" line, his popup, the dice prompts and "The Index today" say
  so ("The Index, which takes no sides, has cut his edge on the dice to +5 this week"). Tune it in `Week.RULES.catchup`.
- **The silver is seen on both sides.** A summons he has asked silver for stays on the tab until he marks it paid, however old it
  is (it is paid in person, often after the week has closed, and the silver of a closed week can still be marked paid). The "Week:"
  line says "100 silver owed to him" (to you, on his client); at login his client says how much he is owed, and everyone else's says
  how much they owe him.
- **The week's clock is said in your own time.** The week turns over at Monday 00:00 UTC, which is Monday 11:00 on the east coast of
  Australia in summer (10:00 from April). The rules card ("The clock: this week closes Monday 11:00, your time") and a line at the
  Monday login say when it closes and when answers stop (two days later), using the player's own clock.
- **The briefing is long once and short after.** The first ritual on him each week (nothing filed yet) says everything: the helper
  rule, the catch-up and the whim. Later ones say only what changes cast to cast ("Summoning Zennit: summon 4 of 10, Zennit leads
  by 2, 2 dice left. From here (a zone) the summons is worth 3..."), the last call and anything waiting; the rest is on `/sc rules`.
- **Writs.** The group has **two a week** (`Week.RULES.writs`) to play on a summons of Zennit. `/sc writ` before the ritual arms one for
  your next summons of him (`/sc writ` again withdraws it); the briefing says so, and the Index files it with the summons ("2 left").
  His popup says the group has played a writ and what a decline would cost, so he knows before he decides. If he then declines that
  summons in the game, it costs him its points as a refusal does (his list does not excuse it); if he accepts, the writ is spent anyway
  and the group scores the summons as it would have. A writ costs the group nothing, so the only choice is which summons to put it on. Only the first two writs of a week count, worked out the same way on every client. A record
  carrying a writ has an 11th field (`w`), and a decline is a new answer (`declined`), so this needs everyone on 0.20 (a friend on 0.19
  is told once, and cannot read those records).
- **A writ only bites where a decline would have been free**: while his free decline is unspent, or at a place on his list. Once his
  free decline is used, the briefing says so ("a writ only bites if this place is on his list"), and where to put one is a guess at his
  secret list.
- **Postcards.** The first summons of him to each far-flung place (`Scoring.remoteNames`, 10 points) in a season that lands (he went:
  accepted, silver, or lost the dice) earns the Index a postcard from him, said on every client ("The Index has filed a postcard from
  Zennit, in Silithus: 'Sand. Also insects. Mostly sand.' Stamped: 1 of 10 far-flung places this season."). No points: the 10 are the
  reason to go, the postcard is the joke. `/sc week` ends with the season's postcards and the places still missing one ("Still no
  postcard from: Azshara, Felwood... The Index has stamps."), the Monday login names three of them, the rules card counts them, and
  the season's keepsake lists them. A second trip to the same place that season sends none, and a decline is not a trip. **Zennit can write his own**
  (`/sc zennit postcard Silithus: ...`), and his words replace the Index's on every client.
- **A last call.** In the last 24 hours of a week (`Week.RULES.lastCall`), the "Week:" line adds "the week closes in 9 hours", the
  briefing as a ritual on him begins ends "Last call: the week closes in 9 hours (Monday 11:00).", and a login in that stretch says it
  once with the standing ("The group leads by 1, 2 of 10 summons filed"). Not in a week off.
- **The group can see who is slow.** A summons of Zennit unanswered for an hour (`Week.RULES.overdue`) is counted as *waiting for
  his answer*, and the "Week:" line ("... 2 waiting for his answer") and the briefing as a ritual on him begins say how many, so the
  group can chase him. On his own client, a minute after login, the chat says how many summons are waiting for him and that
  `/sc respond` opens the latest. An unanswered summons still counts as accepted.
- **A provisional Monday.** He can still answer into a week until it closes, two days after it ends, so a result announced on Monday
  can change. While summons of him are unanswered, the Monday result ends "Provisional: N summons of him are still waiting for his
  answer, and the week closes on Wednesday"; once the week has closed, the next login says it is final, or that it changed and who
  it went to. A finale's keepsake waits for the final word.
- **A whim of the week.** About half the weeks, the Index draws one small twist, the same on every client (it follows from the week
  number, so nothing is synced or kept): **The Index is distracted** (his dice edge is 5 lower), **attentive** (5 higher), **a
  helpers' feast** (each helper adds +8 instead of +5) or **the helpers are tired** (+2). Each moves a normal week's chance by
  about 5 or 6 points, so no week is much easier than another, and the group can plan around it. It is said at login, in the
  first briefing of the week, in "The Index today" and in `/sc week`; never in a week off. `Week.RULES.whims = false`
  turns it off, and `Week.WHIMS` and the deck in `Week.lua` are where to add more.
- **His week off is real.** After a week Zennit wins, the next week is his: summons of him are still logged, answered and
  gagged as usual (the warnings, his popup, the dice), but they are filed as **disturbing his leave**: the race ignores them,
  nobody wins the week, and no chapter is unlocked. They still earn **postcards** from far-flung places and count for the
  **titles**, and the briefing says so ("it will not count for the race, but a far-flung place still earns a postcard"). The
  Index counts how often his leave was disturbed and who did it most; `/sc week` and the season's keepsake say so ("The Index
  notes that his leave was disturbed 6 times; Al did it most (4)."). No points. So a win for Zennit is a pause in the race and a
  small game of its own; the week after it is a normal one. His leave ends with a line at login.
- **Zennit can close the Index** for the rest of the week once **5** have been filed and the latest of them answered:
  a "Close the Index" button after his answer, and in the hub's Zennit tab. It is free, and it travels with his answer,
  so every client agrees. Summons after that are filed under 'enthusiasm', and their casters are told.
- The group's score is the points of those summons that landed. Zennit's starts at **2** (a head start), gains the
  summon's points when he wins the dice or accepts a summon to a place on his list, and loses them on a plain refusal.
- **Zennit has 3 dice a week.** When they are gone he has to accept, decline or ask for the silver. His roll gets **+10**;
  each helper on the summon (up to two) adds **+5** to the summoner's roll; a tie goes to him.
- **Where the week stands is shown when it changes**, not only in the hub:
  - as a ritual on Zennit begins, the caster is told whether it will count, who leads, his dice left and what helpers add;
  - after each summon of him and each of his answers, a chat line: "Week: the group leads by 1, 4 of 10 filed, 1 die left.";
  - his answer popup says the same, worded for him ("you lead by 2"), and reminds him that ignoring a summon
    counts as accepting it;
  - when the helpers' bonus is what beat him on the dice, the line names them ("Al and Cy's +10 tipped it.");
  - lines that repeat (his answers, "Summon logged", "Week:", the last die, the week's result) come in three variants with the same facts;
  - a place on his list that comes up again is noticed ("Darnassus again. The Index is beginning to see a pattern."), never the first time, so the list keeps its secret until it hits;
  - when his third die is spent, everyone is told that every summon from there is certain ("That was Zennit's last die this week…");
  - the hub's season band shows the lead (`WEEK: GROUP +1 · FILED 4/10 · DICE 1`, or `CLOSED`).

Earlier weeks keep the rules they were played under (his head start of 10, a week off that was only a warning, every landed summon counting for the group,
unlimited dice), so the season and the chapters already reached do not change. Tune the race in `Week.RULES`
(head start, the minimum before he can close and the limit, dice, helper bonus, the catch-up steps, and the week it starts) and `Respond.EDGE`. Scenes 9 and 10 of the intro
narrate these rules; if they change, re-voice those two scenes (`.claude/skills/zenit-narrator-audio`).

### The season

The weekly wins add up to a race: the first side (Zennit or the group) to **5 weekly wins** takes the finale, then the
count starts again. It is worked out from the log, so every client agrees. Each win plays its own chapter of the story:
`z1` to `z5` for Zennit's wins and `g1` to `g5` for the group's, so `/sc intro z2` or `/sc week g3` replays one. A chapter only plays once the season has reached it (the admin can play any).
All ten chapters are written (scenes 11 to 32). Zennit's track ends with him becoming the clerk of the Index,
the group's with Form 27B/6 turning out to be the receipt for the fifty silver, the Ritual getting its closure and Zennit
being freed. `/sc week` shows the standing.

#### Season two

A finale moves the story on to its next season (`Week.Season().number`), with chapters of its own: the keys carry the season
(`2z1` to `2z5`, `2g1` to `2g5`), and the season opens with a chapter chosen by how the one before ended (`2a` after Zennit's
finale, `2b` after the group's), which plays first in "Previously on". Season two is "Zennit and the Audit"
(`Season2.lua`, the outline in `design/season-two.md`). Its scenes come after "The Index today" (scene 33), so season one's
scene numbers, art and recordings do not move. Season two's 26 scenes are 34 to 59: each has its own art (`Media/intro_<n>`
and `intro_l<n>`, drawn in `tools/intro/source.html`, which has the Auditor and Poogs), its own narration (`Media/intro_<n>.ogg`, the same
voice as season one) and its key phrases and highlights in `IntroCues.lua`, and "The Index today" says season two's lines from
recordings of its own (`Ledger.LINES`, with `_2` after each id). A scene with no recording is typed and silent, timed to be read.
Only a finale changes the season: a season the admin stops and starts again is the same season, told from its start, so a
test season before the beta cannot skip one. A season this version has no story for (season three) shows its chapters as
not written and says an update will have them, and a client shown a chapter it does not have says so. The Story tab shows
the season in progress, with a button to look back at earlier seasons and replay their chapters. The admin can switch on a **preview** (`/sc preview`, or Tools > Testing) that adds the season after this one, as "PREVIEW SEASON 2", with every chapter playable.

The admin can also stop and start seasons (`/sc season stop|start`, or Tools > General > The season). A **stop** ends the
season in progress at once, with no finale (`Week.Season` lists it under `ended`), and no week counts while none is running:
summons are still filed, under "between seasons", and nobody wins the week. A **start** begins a new season, 0 to 0, from the
week it is made in, with no week off carried over. Each is a mark (`ST.db.seasonMarks`, `Week.Marks`) that every client keeps
and passes on (`C`), so a client that was offline catches up at its next hello and works out the same seasons. A mark is kept
only if it carries `ST.ADMIN_HASH`, a hash of the admin's BattleTag. That tag is in `Core.lua`, so the stamp keeps out mistakes
and mischief, not a friend who reads the code. With no marks at all the season runs from the first summon, as before.

### Admin and Zennit's account

The debug tools (`/sc test`, `fake`, `fakeprompt`, `comic`, `synctest`, `debug`, `gag`, `zennit` test mode, `respond test`, and the
matching buttons in the window) and every chapter of the story not yet reached by the season are for the admin's Battle.net
account only (`ST.ADMIN_HASH` in `Core.lua`: a hash of its BattleTag, so the tag itself is not in the addon). `/sc admin` says whether this account is the admin. `/sc asplayer` (Tools >
General > View as player) makes the admin's account see the addon as a player does, to check what friends see; that one
switch stays in reach while it is on, and data kept only for the admin (how the week felt) is still kept. Zennit's own account
(`ST.ZENNIT_HASH`, likewise) is treated as Zennit whichever character he plays. The check runs on each player's own computer, so it keeps
things out of the way but is not security.

### Tools tab, BattleTags and reset

The Tools tab has a button for every command that has no tab of its own, in three sections under a row of small buttons, like
the Party tab: **General** (windows, the record: week and season, the rules, the titles, the tab, cards, past seasons and the
playtest report; the sound switch, undo the last summon and reset), **Testing** (where am I, the Battle.net check, voice clips and,
admin only, the test summoning, the gags, the test modes, a test summon, the sync self-test and the BattleTag tests) and
**Checks** (the live checklist). The output box sits under whichever section is on show; admin-only buttons are hidden for
everyone else and the rows close up around them.
`/sc admin` (or the Battle.net check button) shows the BattleTag the game reports and whether it is the admin's or Zennit's; the
admin's **Run tag tests** button, and the last two lines of `/sc synctest`, check the matching with sample tags.

`/sc reset` (or **Reset my data...**) wipes this client's summons, badges and, because the season and story are worked out from
the log, the story too. It asks first. The admin's `/sc reset all` also asks everyone else running Summon Core, in the party, raid
and guild, to do the same: each of them gets a prompt and nothing changes on their client until they agree. A reset leaves a mark,
and sync refuses anything older than it, so a client that said no cannot put the old log back. Only the admin's request travels on:
a client that missed it is asked when it next meets someone who took part, and a client holding nothing from before it (a newcomer)
takes the mark without being asked. A player's own `/sc reset` stays on their client.

### Closed weeks and Zennit's alts

A week closes two days after it ends. Zennit can then no longer answer a summon from it, and sync refuses an answer made after
the close (the silver of a summons he asked silver for can still be paid, which moves no points). The week's result is worked out
from the log, never frozen on one client, so every client that holds the same log agrees on it; a summons made in the week that
reaches a client late still counts, the same way everywhere. Zennit's alts are learned over
sync: his own client announces the character he is playing, and everyone else scores a summon of any of them as a summon of
Zennit (up to 10 alts are kept).
