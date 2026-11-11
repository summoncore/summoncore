# Design journal: Summon Core through the lenses

Working through Jesse Schell's *The Art of Game Design: A Book of Lenses* on this addon, one lens at a time.
Lenses are named, not numbered (the numbers differ between editions). The book's questions are paraphrased
here; read the lens in the book first.

## How we use a lens

1. Pick one lens. Read it in the book.
2. Answer its questions in writing, about what is **built**, not what was meant. Use the code and real numbers.
3. Write down the gap between the answer and the build, and anything that surprised us.
4. Turn one finding into one change (or a decision not to change), and log it under Decisions.
5. Playtest with the group, and come back to the lens with what happened.
6. Add a live check (`Check.lua`, `design/verification.md`) for anything the change does that only the game can confirm: a call
   the stubs fake, a line said at login, a layout. Rules logic belongs in the self-tests instead, which `a-selftest` runs in the game.

Lenses will disagree with each other. Choosing between them is the design work, so the reasoning goes in here too.

## The path

| Lens | Why here | Status |
|---|---|---|
| Essential Experience | Anchors the rest: what should a summon, an answer and a week feel like? | Week answered; summoner and Zennit still open |
| Meaningful Choices | Zennit's four answers are the main decision in the game | Dice limited (3 a week); playtest |
| Fairness | The rules are loaded for Zennit on purpose; is that fair, and does it need to be? | New race built; playtest |
| Griefing / Friendship | A game about teasing a friend has to stay fun for the friend | Built: 5 to 10 a week, he closes; ask Zennit in playtest |
| Visible Progress / Feedback | The season band and answer colours in the hub | Built 1 to 4; the tracker waits for a playtest |
| The Player | One friend group, and one of them (Zennit) is the target | Built A to C; Zennit and "They paid" wait for the playtest |
| The Interest Curve | A season of five weekly wins, with story chapters as the rewards | Answered; C (his week off) and A (catch-up) built; playtest |
| Skill and Chance | Surfaced twice uninvited: the dice, the helpers' +5 and the catch-up edge are all luck dials | Answered; the last-die line built; playtest |
| Story and Emotion | The story now follows the tree; does it make the group feel something, or is it only a reward track? | Answered; A, C and D built; playtest |
| Surprise | A season is about 11 weeks of the same rules and the same lines; what will still surprise this group in week 9? | Answered; A, B, C and D built; playtest |
| Elegance | Twelve or so rules have piled up; which ones earn their place? | Answered; A, C built and D worded (audio pending); B (the head start) left |
| Playtesting | Every lens ended with questions for a playtest; the first new-rules week starts today | Answered; the report and the script built |
| Community | The race only works if the target turns up; what happens when he does not? | Answered; A and B built; C, D, E waiting for a playtest |
| Economy | The silver and the cards put real in-game money into the game; what flows, and what keeps it fair? | Answered; B built; the ask stays unbounded |
| Reward | What does each member get, and when? | Answered; A, B, C and D built |
| Interface | Thirty-odd commands and a full Tools tab have piled up; can people find and read what they need? | Answered; the Tools tab fixed (now three sections); the tip and the short help built; B and D left |
| Time | The week runs on UTC, a season runs about eleven weeks from 5 October, and nothing says when either ends | Answered; A and B built; the turnover stays |
| Risk Mitigation | 0.19.0 carries a great deal of code that has never run in the game; what could go wrong, and what do we do about it? | Answered; A and B built; C and D left |
| Unification | Is everything we have added still one game with one voice? | Answered; A, B and C built |
| Endogenous Value | What does the group actually care about inside this game, and is the game paying in it? | Answered; A built, B became `/sc places`, C kept |
| Cooperation | The group is one team against Zennit and also a ranked list of individuals; do those two pull the same way? | Answered; A and B built; the order is left to the group |
| The Toy | Is it pleasant to cast, answer and read, before any goal? | Answered; A built; B, C and D left |
| Resonance | Does the game ring true to what summoning someone in WoW is really like? | Answered; the real prompt answers, and a writ makes a decline cost; the popup's position waits for the game |
| Balance (dominant strategies) | After the decline and the writ, is any choice strictly better than the others? | Answered; found one (a free decline); fixed: one free decline a week |
| Flow | Can the group play WoW, and the contest, without stopping to do the addon's chores? | Answered; A, B and C built |
| Accessibility | A friend installs it in week three: what does their first hour say, and what must they learn? | Answered; A, B, C and G built; D waits on audio |
| Simplicity/Complexity | Elegance counted a dozen rules; since then the game's prompt, writs and free declines arrived. Which rules buy a decision, and which undo each other? | Answered; A and B built; the head start stays |
| Secrets | His list is the game's one secret; is each piece of information on the right side of hidden and open? | Answered; A, B and postcards built |
| Character | Zennit is a real friend playing a version of himself; who writes him, and does he get a say? | Answered; A and B built; C (recordings) waits |
| Inner Contradiction | Do the rules, the story and the players' goals pull the same way? His prize for winning is a week in which summoning him does nothing | Answered; A and B built |
| Indirect Control | What does the addon nudge the group to do, and does each nudge arrive when the decision is made? | Answered; A built, C parked, B after the playtest |
| Freedom | Is everyone free to just be a person for a while? A summons he never answers counts as accepted | Answered; A built |
| Pleasure | Which kinds of fun does it give, to whom, and when? The week's triumph and the story's wonder arrive to each person alone | Answered; A and B built, at the weekly raid |
| Playtesting, revisited | Every lens now ends in "watch in playtests", and nothing since 0.20 has run in the game. When is it ready to share? | A five-step gate; then a freeze until the first week's report |
| Judgment | What does the game praise each of them for? Nothing praises Zennit for being a good sport, or the group for being clever | Answered; A and B built |

## Entries

### 2026-10-04 · Lens of Meaningful Choices: Zennit's four answers

**Rules as built** (`Store.lua`, `Respond.lua`, `Week.lua`). For a summon worth P points:

| Answer | Group's points | Zennit's points | Gap (Zennit minus group) |
|---|---|---|---|
| Accept | +P | 0 | -P |
| Refuse | 0 | -P | -P |
| 50 silver (once paid) | +P | 0 | -P |
| Dice (he adds 10, ties are his: he wins 59.95%) | 0 if he wins, +P if not | +P if he wins | **+0.2P on average** |

On a place from his list: accept and refuse both leave the gap at 0, while dice average **+0.6P**.

**Findings**
- The dice are a **dominant strategy**: for any summon, of any value, rolling is his best answer for the race.
- Accept, refuse and 50 silver are **the same choice** as far as the scores go. Silver only delays the points and
  costs the summoner money.
- So the choice is meaningful only outside the scores: does he want to go there, and which answer is funniest.

**Open decision:** should the scores make the choice matter too? Ideas so far, none chosen:
- Make refusing cheaper than accepting (for example -P/2).
- Let paid silver earn Zennit something (the Ritual "accepts silver as a gesture").
- Limit the dice to a few rolls a week, so rolling becomes a decision about when.

### 2026-10-04 · Lens of Essential Experience: the group at the end of a week

**Our answer:** the group should have to *try* to beat him. A win is earned, not given, and not out of reach.

**What the build does today.** Zennit starts each week with 10 points. Every landed summon counts for the group,
not only summons of Zennit, and he rolls the dice on every summon of him (his best answer, above). The chance
that the group wins a week, with every summon in a zone (3 points), from 20,000 simulated weeks per cell:

| Summons of Zennit ↓ / of each other → | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 0% | 0% | 0% | 0% | 100% | 100% | 100% | 100% | 100% |
| 1 | 0% | 0% | 0% | 40% | 40% | 100% | 100% | 100% | 100% |
| 2 | 0% | 0% | 16% | 16% | 64% | 64% | 100% | 100% | 100% |
| 3 | 0% | 7% | 6% | 35% | 35% | 78% | 79% | 100% | 100% |
| 4 | 3% | 3% | 18% | 18% | 52% | 52% | 87% | 87% | 100% |

**The gap**
- "Trying" today means **volume**: four zone summons between friends beat the head start every time, and Zennit
  has no say in it.
- **Summoning Zennit makes it harder.** Each summon of him is a bet the group loses about 60% of the time. The
  group's best strategy is to leave him alone, the opposite of the joke the addon is built around.
- The code comment in `Week.lua` says the rules are tuned so that he "wins more weeks than he loses". That was
  the old intent; our answer above replaces it.

**Open questions**
- What should "trying" mean? Summoning more often, summoning to harder places (dungeons, far-flung zones), or
  beating Zennit at his own answers (the dice, his list)? Our answer decides which numbers to change.
- How active is the group in a normal week? Real weeks from the log (the Tools tab's "Week and season") will
  show where the head start sits now, instead of guessing.
- Still to answer: what a summon should feel like for the **summoner**, and for **Zennit** when the popup appears.

### 2026-10-04 · Essential Experience, continued: what "trying" means

**Our answer:** (c) **beating Zennit at his own answers.** Summoning him should be how the group wins, not a risk.
Keep it tongue in cheek.

**Today's rules work against it.** Going all out on him (6 far-flung summons, 2 helpers) won 18% of weeks, less than a
moderate push (31%): more effort, worse odds.

### 2026-10-04 · Lens of Fairness: the new race

Built from the answer above, each rule tied to a finding:

| Rule | Why |
|---|---|
| Only summons of Zennit count in the race (summons of each other still count for the tally and badges) | Essential Experience: he is the target, so volume between friends no longer wins |
| He has **3 dice a week**; then he must accept, refuse or ask for the silver | Meaningful Choices: the dice stop being always right; *when* to roll becomes his decision, and the group can outlast them |
| Each helper (up to two) adds **+5** to the summoner's roll | (c): the group beats his best answer by organising, not luck |
| Only the first **5** summons of him a week count; later ones are "filed under 'enthusiasm'" | Fairness and Friendship: hounding him past five earns nothing |
| Head start **2** (was 10) | The difficulty dial, chosen from the table below |

**Fairness, Zennit's side.** He still needs a real chance at his week off. His list provides it: some summons he
actually needs (his task list), and when one of those lands he gains the points too, so the gap does not move.

The group's chance to win a week (20,000 simulated weeks per cell; 1 in 4 summons lands on his list; he rolls while
he has dice):

| Kind of week | Head start 0 | **2 (chosen)** | 3 | 5 |
|---|---|---|---|---|
| Quiet: 2 zone summons, no helpers | 15% | **15%** | 9% | 9% |
| Normal: 3 zone summons, 1 helper | 27% | **28%** | 8% | 7% |
| Trying: 5 dungeon summons, 2 helpers | 64% | **64%** | 63% | 40% |
| All out: 8 far-flung, 2 helpers (only 5 count) | 64% | **64%** | 63% | 63% |

Effort pays (15% → 28% → 64%), and he still takes about a third of the weeks the group tries hard. The limit means
going all out is no better than trying, which is the point. Head start 2 gives the same curve as 0, but a week where he
wins every roll is clearly his.

**Built** in `Week.lua` (`Week.RULES`), `Respond.lua` and the hub's season band (`FILED 3/5 · DICE 2`), with
self-tests. It starts with the week of Monday 5 October 2026; earlier weeks keep their old rules, so the season and
the chapters already reached do not change.

**To watch in playtests**
- Does the group win about a quarter of normal weeks and two thirds of the weeks they try?
- Does Zennit save his dice for the big summons? (If he always rolls the first three, the choice is still not meaningful.)
- Is five a week the right limit, for the group and for Zennit? That is the Lens of Griefing / Friendship, next.
- Intro scenes 9 and 10 still narrate the draft rules; re-voice them once these settle.

### 2026-10-04 · Lens of Griefing / Friendship: Zennit's power to close the week

**The premise is griefing by design:** the whole group targets one friend. That can't be removed. The questions are
whether Zennit is still having fun, and whether he can say "enough". The limit of 5 a week bounds it, but the group
sets the pace, not him.

**Our idea:** Zennit has the power to cut off how many summons count in a week.

**The lens turned around:** could Zennit use that power to spoil the group's fun? His obvious move is to close the
week the moment he is ahead. The group's chance to win a week (30,000 simulated weeks each; same assumptions as the
Fairness entry):

| Version of the power | Normal week | Trying week |
|---|---|---|
| A. No power (built now) | 28% | 63% |
| B. He closes the week the moment he is ahead | 13% | 16% |
| C. B, but the Index takes one "last call" summon after he closes | 22% | 29% |
| D. He sets the week's limit in advance, before the first summon (his best is 2) | 19% | 24% |
| E. D, plus 2 points to the group for each slot under 5 | 28-100% | 43-100% |
| **F. He closes whenever he likes, but each slot he cuts off is filed as 5 points to the group** | **27%** | **63%** |

**Findings**
- A free "close" button (B) wipes out the last decision: trying drops from 63% to 16%. **The power that protects Zennit
  from griefing would let him grief the group.**
- Choosing the limit in advance (D) is less abusable, because he chooses blind. But a small limit makes the week a
  coin toss: with fewer summons, effort has less room to show. That is the Lens of Skill vs. Chance arriving uninvited.
- **Separate relief from scoring.** In F, closing buys him peace, not a win. Each cut-off slot is filed at 5 points, about
  one well-organised dungeon summon, so closing is neutral for the race (63% either way). He closes when he has had
  enough, or when the week is already decided.

**Recommendation:** F. In the game's voice: "Zennit has closed the Index for the week. The 3 forms left were stamped
APPROVED in his absence: +15 to the group."

**Our answer:** "We could go 5 to 10 a week and he will be OK. We can always change it later." Not playing yet, so
Zennit gets asked at the first playtest.

**That changes the recommendation.** With a floor (he can only close once 5 are filed), the versions behave differently
(30,000 simulated weeks each):

| Version | Normal | Trying | Busy (8 dungeon) | All out (10 far-flung) |
|---|---|---|---|---|
| Limit 5, no closing (what was built) | 28% | 64% | 63% | 63% |
| Limit 10, no closing | 27% | 64% | 94% | 99% |
| **Limit 10, he may close after the 5th, free** | **27%** | **63%** | **63%** | **63%** |
| Limit 10, close after the 5th, each cut-off slot 5 points | 27% | 63% | 94% | 99% |

- **A limit of 10 with no way out rewards hounding him** (94% for a busy week): exactly the griefing the lens is about.
- **The price stops helping once the limit is 10.** He either sits through it or pays, so hounding still wins.
- **Free closing after the 5th is the fit.** If he closes at 5, the week plays exactly like the limit-5 rules we already
  judged fair; the exploit only existed because he could close *before* 5. And summons to places on *his list* earn
  him points, so a friendly group gives him a reason to leave it open.
- **Lesson:** a new constraint (the floor of 5) changed which fix was best. Re-run the lens when the design moves.

**Built:** up to 10 summons of him count; once 5 are filed and the latest answered, he can close the Index for free
(after his answer, or from the hub's Zennit tab). It travels as a flag on his answer, so every client agrees; later
summons are filed under 'enthusiasm', and their casters are told. A changed answer keeps the Index closed.

**Found while building:** an answer changed within the same second as the one before it (owes, then paid) never
reached other clients, because sync keeps the later of two answers and a tie keeps the old one. A new answer is now
always timestamped after the one it replaces. The closing self-test caught it: the two clients disagreed, 15 to 12.

**Ask Zennit at the first playtest**
- How do 5, 8 and 10 summons in a week feel?
- Does he use the close button? Early, late, never? If he always closes at 5, the extra five slots do nothing.
- Does closing feel like a fair way out, or like giving up?

### 2026-10-04 · Lens of Visible Progress, with the Lens of Feedback

**The questions (paraphrased):** what progress matters to the players, and can they see it at the moment they care?
After acting, what do they need to know, and does the game tell them clearly and quickly?

**What a player sees, moment by moment, as built:**

| Moment | They want to know | They see |
|---|---|---|
| Deciding to summon Zennit | Worth it now? Dice left, filed, will helpers matter? | Nothing, unless they open `/sc` |
| The ritual begins (caster) | Same | A voice clip |
| The summon is logged | Did that count? | "Summon logged: Zennit in X (+5, dungeon)": tally points, not the race |
| Zennit's popup | How close is his week off? | The summon, the cost of refusing, dice left; no week score |
| His answer arrives | Who is ahead now? | "+5 points", but not where the week stands |
| End of the week | Who won, where is the season? | A chat line about a minute after the next login |
| The hub's season band | Everything | Season wins, then `GROUP 9 / ZENNIT 8 · FILED 4/10 · DICE 1` |

**Findings**
1. **Progress is only visible where nobody is looking.** The race changes when a summon of Zennit is logged and when he
   answers; at both moments players are in the world, not in `/sc`.
2. **Feedback arrives too late to help decide.** Dice left and the helper bonus should decide whether and how to summon
   him now; the summoner only learns the bonus from the dice prompt, after the ritual.
3. **Totals, not distance to the goal.** "GROUP 9 / ZENNIT 8" makes you subtract; "GROUP LEADS BY 1" tells you whether to
   push.
4. **A legibility problem we introduced.** Fitting FILED and DICE into the band dropped the "THIS WEEK" label, so two
   ZENNIT/GROUP scoreboards (season wins, week points) sit side by side. The lens works on recent decisions too.

**Proposed changes**

| # | Change | Fixes |
|---|---|---|
| 1 | After each summon of Zennit and each answer, a chat line: "Week: group leads by 1 · 4 of 10 filed · 1 die left." | 1 |
| 2 | The band shows the lead, not two totals: `WEEK: GROUP +1 · FILED 4/10 · DICE 1` | 3, 4 |
| 3 | When a ritual on Zennit begins, brief the caster: filed, dice left, what two helpers add | 2 |
| 4 | Zennit's popup shows where the week stands | 1, for Zennit |
| 5 | An optional on-screen tracker | 1; held back: clutter is a cost, wait for a playtest to ask for it |

**Built: 1 to 4.**
- As a ritual on Zennit begins: "Summoning Zennit: summon 3 of 10 this week, and the group leads by 3. He has 3 dice
  left; each helper adds +5 to your roll if he suggests dice (two helpers at most)." Or that it won't count, or that
  he is on his week off.
- After each summon of him and each answer, everyone gets "Week: the group leads by 3, 2 of 10 filed, 3 dice left."
- Zennit's popup ends with the same line in his words ("Week: you lead by 2, …"); the separate dice count it replaced
  is gone, so the number appears once.
- The band reads `WEEK: GROUP +3 · FILED 2/10 · DICE 3`; a tie reads `ZENNIT (TIE)`, because a tie is his.

**To watch in playtests**
- Do people read the chat lines, or do they scroll past? If they scroll past, that is the case for the tracker (5).
- Two lines per answer, for everyone in the guild: welcome, or noise?
- Does the briefing change behaviour: do people wait for a second helper when he still has dice?

### 2026-10-04 · Lens of the Player

**The questions (paraphrased):** what do these players like, dislike and expect? In their place, what would I want?
Unlike the other lenses, this one is about real people, so the code can only show what each kind of player gets.

**What the game offers each kind of player, as built** (`Store.Tallies`, `Store.Stats`, `Scoring.badges`):

| Player | What they do | What they get back |
|---|---|---|
| Summoner (warlocks only: Ritual of Summoning is a warlock spell) | Casts, rolls back against his dice | Points, all six badges, the Tally, the briefing, the dice prompt, their name in every line |
| Helper (anyone who clicks the portal) | Makes the ritual possible; now +5 each to the summoner's roll | An "assisted" count in the Tally; no points, no badges, no mention when their +5 wins the roll |
| Zennit | Answers every summon, guards his list, spends dice, can close the Index | His week off, the story, his own wording; Summary, Tally and Badges are hidden from him (the gag) |
| Friends who are offline | Nothing in the moment | Chat lines at login, the hub, the story |
| The designer (also a player, and the admin) | All of the above, plus the admin tools | See finding 4 |

**Findings**
1. **The role the new rules made most important gets the least back.** Helpers decide the dice now; the game never
   names them when they do.
2. **The main action is warlock-only.** Everyone else can only be a helper: the role with no rewards.
3. **Zennit answers every summon himself.** Up to 10 popups a week: the best part of his week, or a chore?
4. **The designer is one of the players.** Watch for features that exist because *we* find them fun.

**Questions about the group, answered**

| Question | Answer | What it means |
|---|---|---|
| How many are warlocks? | Two or three | Most of the group plays as helpers, so that role matters a lot |
| Do helpers enjoy it? | Yes | They don't need paying (points, badges); they are happy to be there |
| What do they enjoy in WoW? | Banter, and doing things together (not achievements, not competing) | Badges and the friend-vs-friend Tally matter less than assumed; the group-vs-Zennit race and funny lines matter more. Helpers should be part of the story, not rewarded with badges |
| What would annoy them? | Bookkeeping (not chat spam, not popups) | The "Week:" lines are fine. Hunt down anything that makes people tick boxes or remember to click |
| What is Zennit like? | Not sure yet | Playtest |

**Where the build asks for bookkeeping**
- **The assistants prompt.** When detection is unsure, the summon is not saved until the caster ticks names and
  clicks, with no timeout. Since the new rules, those names also set the dice bonus.
- **Zennit's popup** never says that ignoring a summon is fine (an unanswered summon already counts as accepted).
- **"They paid"** relies on Zennit remembering; if he forgets, the group never gets the points.

**Proposed changes**

| | Change | From |
|---|---|---|
| A | When the helpers' bonus decides a roll, name them: "Al and Cy's +10 tipped it: 58+10 beats 63." | Banter; helpers in the story |
| B | The assistants prompt saves itself after 20 seconds with the detected helpers (a countdown on the button) | Bookkeeping |
| C | Zennit's popup says that ignoring a summon counts as accepting | Bookkeeping |
| — | "They paid": watch at the playtest first; it depends on how Zennit plays | Not sure yet |
| — | Dropped: helper badges or points | The group is not achievement-driven |

**Built: A to C.**
- A: "Zennit lost the dice (55 to 58+10): the summon counts. +5 points. Al and Cy's +10 tipped it." Only when the
  bonus decided the roll; a roll the summoner would have won anyway names nobody.
- B: Confirm counts down from 20 and saves with the ticked names (the detected helpers), marked unconfirmed because
  nobody confirmed them; ticking or unticking anything stops the countdown.
- C: the popup's question ends "(Ignore it and it counts as accepted.)"

**To watch in playtests**
- Do the helpers notice, and enjoy, being named? Does it start banter?
- Does anyone still have to touch the prompt? If the detected names are usually wrong, the countdown saves wrong names.
- Does Zennit answer, or ignore? If he ignores most summons, the dice and the list never come into play.

**A lesson about this lens:** I expected the answer to be "reward helpers". Asking showed the group doesn't care
about rewards; it cares about banter and not doing chores. Assumptions about players are exactly what this lens
exists to test.

### 2026-10-04 · Lens of the Interest Curve: a season

**The questions (paraphrased):** is there a hook to start? Does interest rise and fall with rests between the peaks,
rather than staying flat or peaking early? Is there a climax, and does it come last? Is the ending worth reaching? The
lens applies at every scale, so: a summon, a week, a season, and the story across seasons.

**The curve as built** (`Week.lua`, `Intro.lua`, `Hub.lua`; the season numbers are from 100,000 simulated seasons
using the Fairness entry's chance of the group winning a week: 15% quiet, 28% normal, 64% trying; he wins the rest)

| Scale | What the curve does | Verdict |
|---|---|---|
| A summon | Briefing, the ritual, his popup, his roll, the group's roll back, "Week: …" | A real peak at the dice; good |
| A week | Flat from Monday to Sunday (counters tick), then the result about a minute after the next login | **No climax inside the week** |
| A season | The race to five wins: 5 to 10 weeks, one chapter per win | Depends on how hard the group tries (below) |
| The story | The intro (3.6 minutes), then about a minute per chapter, 10 chapters in all | **Runs out after the first finale** |

**Findings**

1. **The hook is the intro; the first reward is a week away.** A new player gets 3.6 minutes of narration, then nothing
   from the story until the first week closes. In between the only feedback is numbers.
2. **The climax depends on the group's effort, not on the design.** A season ends 5 to 0 or 5 to 1 (a blowout) in
   **77%** of seasons when the group is quiet (15% a week), **47%** at normal effort (28%), and still **23%** at 45%.
   A close finish (the loser has 3 or more wins) is at best **53%**. Almost nothing makes a late lead change: 0.5 a
   season at normal effort.
3. **Zennit's side gets the rising action; the group's barely gets seen.** At normal effort the group wins 1.9 weeks a
   season and sees chapter g3 or later in **31%** of seasons; Zennit's trunk runs the full five in nearly all of them
   (4.9 chapters). So the best group chapters (the Ritual naming its price, the receipt, the freeing) are rarely played.
4. **The week off is a story beat with no mechanics.** The ending of chapter 2 says no ritual can find him, but
   `Week.Immune` only drives a warning: summons during it still count, and he still answers. A win for Zennit changes
   nothing in the next week, so his victories do not feel like one. (A season is 6.7 weeks for an active group; with a
   quarter of the weeks quiet, 9.)
5. **The story ends once.** All 10 chapters are written and the tree shows every reached chapter lit, so season 2
   replays season 1. "The Index today" now follows the season, but it is one scene, not new rising action.
6. **A result can be announced and then flip.** The Monday announcement uses the week's score, which is frozen only
   two days after the week ends, and Zennit can still answer into the week until then. A late answer can reverse a win
   after the chat line and the chapter have been given out.

**Proposed changes** (none built yet)

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **Catch-up**: the side two wins behind gets a small edge for the weeks it trails (for example, the group's helpers add more when Zennit leads by 2 or more; his head start or his dice shrink when the group leads by 2 or more). In the simulation, a 10 point shift in the weekly chance cuts blowouts from 47% to 35% and raises close seasons from 29% to 39% at normal effort; 20 points gives 25% and 49% | 2 | Rules, a README paragraph, a few numbers to playtest |
| B | **A beat inside the week**: a line of story at the moments that already exist: the first summon of him, the fifth filed (he may close), the lead changing hands, him closing, the last hour | 1, 4 | Wording only (no art, no voice) |
| C | **The week off is a week off**: while Zennit is on leave, summons of him are filed under "enthusiasm" and do not count, so winning is a pause and the story beat is real | 4 | A rule change; the group then wins nothing that week |
| D | **A match-point week**: when either side is one win from its finale, the week is announced as the deciding one (the Ledger already says it) and plays under one extra rule, such as a fourth die for him | 2 | A rule; needs the dice simulation |
| E | **Season 2 is new**: new chapters, or the old ones return changed (the Ledger's idea, per chapter) | 5 | Writing, art, voice: the largest |
| F | **Hold the announcement until the week is frozen**, or word it as provisional | 6 | Pacing: the payoff arrives two days later |

**Our answer:** build **C**, and keep the gags going: the week off is filler, not a rule that silences the joke, so his
popup, the dice, the warnings and the gag all carry on. A close finish is the goal, so **A** (catch-up) is next.

**Built: C.** Under the new rules, after a week Zennit wins, summons of him are filed as **filler**: logged, answered and
gagged as usual (the briefing and the warning say so), but the race ignores them, **nobody wins the week** and no chapter
unlocks. The week after is a normal one. A first simulation of the cost: with no week off a season is about 6.7 weeks at
normal effort (28% a week); with a rest after each of his wins it is **10.7**, and at 45% it goes from 7.5 to 11
(simulated, 100,000 seasons each). That is long: C and the season's five wins need to be looked at together (see below).

**Built: A, catch-up.** The lever is Zennit's edge on the dice, because it is the one dial that moves a week smoothly (his
head start does not: 2 and 0 are the same, and 3 drops a normal week from 28% to 8%). From the weekly model that reproduces the
Fairness table (15%, 28%, 64% at edge 10), his edge moves the group's chance like this:

| His edge | -10 | 0 | 5 | **10 (now)** | 15 | 20 |
|---|---|---|---|---|---|---|
| Quiet week | 32% | 23% | 19% | **15%** | 12% | 9% |
| Normal week | 50% | 39% | 33% | **27%** | 23% | 18% |
| Trying week | 82% | 74% | 69% | **63%** | 58% | 52% |

The rule: a lead of 2 weekly wins moves it by 5 for the side behind, and 3 or more by 10 (so it is +5 or +15, then +0 or
+20; never below 0, and a lead of 1 changes nothing). Simulated seasons (60,000 each):

| | Quiet | Normal | Trying |
|---|---|---|---|
| Blowout (loser has 0 or 1 win): without / with | 78% / 69% | 49% / 39% | 32% / 23% |
| Close finish (loser has 3 or more): without / with | 7% / 10% | 27% / 34% | 43% / 52% |
| Weeks to a finale | 5.9 / 6.1 | 6.7 / 6.9 | 7.2 / 7.5 |

It is gentle on purpose: it narrows the lopsided seasons without deciding them, and the group's effort still matters most.
A stronger version (steps of 5 at a lead of 1 and 10 from 2) gets normal-effort blowouts to 33% and close finishes to 41%,
but it penalises the side for leading by one win, which feels like punishment. Not chosen; `Week.RULES.catchup` is one line.
It shows in the briefing, the "Week:" line, his popup, the dice prompts and "The Index today", in the Index's voice:
"The Index, which takes no sides, has cut his edge on the dice to +5 this week."

**Found while building:** the week off had no effect on the score at all (only `Week.Warn` and `Week.Briefing` mentioned it),
so a win for Zennit left the group's next week unchanged. And a new week off must not become a free win for him: with
no summons counted his head start of 2 would beat 0, so a week off has no winner at all.

**To decide before building**
- Is a close finish the goal, or is a lopsided season fine when the group simply tries harder (or less hard)?
- Does a win for Zennit have to *cost* the group something, or is the story enough?
- How long should a season last? With C, about 11 weeks (nearly three months) at normal effort. Options: fewer wins to a
  finale (4), or letting the group win during his week off (no). **Decided: keep five wins for now**; revisit after the
  first real season shows how many weeks are quiet.

**To watch in playtests**
- How many weeks does a first season really take, and how many are quiet?
- Does anyone replay a chapter, or ask what comes next?
- Do the "Week:" lines build any excitement during the week, or is it only the Monday result?

### 2026-10-04 · Lens of Skill, with the Lens of Chance: what the group controls

**The questions (paraphrased):** what skills does the game ask of its players, and are they the ones we want? Is there room
for a better player to do better? Where does chance enter, and does it make skill matter or swamp it? (Chance averages out
over a long game, so the answer can differ by scale.)

**Who decides what, as built**

| | Decided by people (skill) | Decided by dice or luck (chance) |
|---|---|---|
| The group | How many summons (2 to 10), to which places (1, 3, 5 or 10 points), how many helpers (0 to 2), and the **order** of the summons against his dice left; getting 2 or 3 friends to the same spot in WoW | The summoner's roll back |
| Zennit | Accept, refuse, silver or dice; **when** to spend 3 dice; his secret list; when to close the Index | His roll; whether a place is on his list (the group cannot see this) |

**Numbers** (a weekly model that reproduces the Fairness table; 40,000 weeks per cell)

| Question | Answer |
|---|---|
| How much does a helper matter? | +5 each is worth about **6 points** of a week's win chance (five dungeons: 52%, 58%, 64%; three zone summons: 22%, 27%, 33%) |
| How much of a week is the group's plan, and how much dice? | Across 300 plausible plans, the plan explains **25%** of the variance in the result if he rolls the first three summons, **16%** if he saves dice for dungeons, **9%** if he rolls at random. The rest is dice and his choices |
| Does skill show up over a season? | Yes: a group that moves from a 39% to a 63% weekly chance goes from **25% to 79%** to take the finale (race to 5) |
| Is there a best order for the group? | **No: it depends on what he does.** One mixed week (three cheap summons, then three dungeons, 2 helpers): *cheap first* wins **97%** if he rolls the first three, **39%** if he saves for dungeons; *big first* wins **39%** and **97%** (the second against someone who rolls only on the last ones). Neither order beats every policy |

**Findings**
1. **A week is mostly chance; a season is mostly skill.** The best plan we sampled still loses 37% of weeks, and the group's
   plan explains at most a quarter of one week. But the same plan decides about three in four seasons. For a group that
   plays weekly, the drama sits in the week and the fairness in the season, which suits it.
2. **The deep skill is a guessing game, and it is the one we wanted.** Limiting the dice to three made *when to roll* his
   decision (the Meaningful Choices entry) and *what order to summon in* theirs. Each side's best move depends on the other's,
   so neither has a dominant play: the aim of that change.
3. **The moment skill pays is invisible.** When his last die is spent, every later summon is certain, which is exactly
   when a group that sent its cheap summons first collects. Nothing said so; only the "Week:" line's "0 dice left".
4. **The Fairness table assumed he rolls whatever comes first.** That is the best policy against a group that sends zone
   summons, and a poor one against a group that baits. The playtest should record how he really spends dice.
5. **Helpers are the dependable skill.** They are the one lever that needs no guess about the other side, and they ask for
   togetherness, not bookkeeping: what this group likes (the Player entry).

**Decision: no rule change.** Chance in a week is what makes the dice banter, and skill compounds across the season.
**Built: the last-die line.** When his third die is spent, everyone gets "That was Zennit's last die this week. Every summon
from here is certain: he can only accept, refuse or ask for the silver." (Zennit's own client: "That was your last die this
week. From here you can only accept, refuse or ask for the silver.") It also begins to answer the Interest Curve's flat week,
by giving the week one beat that comes from play.

**To watch in playtests**
- Does Zennit save dice, spend them at once, or forget he has them? Does his policy change after the first season?
- Does the group learn to send cheap summons first? Does anyone say so out loud?
- When the last-die line comes up, does the order of the summons change?
- Do the helpers' +5 get noticed, or does the group still treat them as optional?

### 2026-10-04 · Lens of Story, with the Lens of Emotion: does the group feel it?

**The questions (paraphrased):** does the game tell a story, and does the story give the players' actions meaning (and the
actions move the story)? What do I want players to feel, what do they feel, and at which moments? From the Player entry the
target is **banter and doing things together, with no bookkeeping**, and Zennit has to enjoy being the target.

**The feelings we want, and what the build gives at each moment** (`Detector.lua`, `Respond.lua`, `Week.lua`, `Intro.lua`)

| Moment | Feeling we want | What the build gives |
|---|---|---|
| The ritual begins | Mischief, anticipation | A briefing in facts ("summon 3 of 10 this week, the group leads by 3") |
| His popup | Dread, played for laughs; agency for him | Four buttons, his own wording, the gag: **works** |
| The dice | Tension, shared | A real `/roll` the party sees in chat: **the best moment in play** |
| The result | Triumph or a groan | "+5 points", the lead, the dice left |
| End of a week | Suspense, then release | One chat line a minute after the next login |
| A chapter | Warmth, curiosity | Narrated, drawn, typed out: **the strongest moment, and it is outside play** |
| A finale | Catharsis, affection | Chapters 10 and 11 (75 and 72 seconds); both end with Zennit welcome at a very small cake |
| His week off | Relief, a little missing him | A line at login |

**Findings**
1. **The story lives in a viewer; the play lives in chat, and the two do not talk.** A normal summon of Zennit prints five
   lines (the briefing, "Summon logged", "Week:", his answer, "Week:") and none is in the Index's voice. The voice shows up
   only in the warnings, the closure and the catch-up line. The group dislikes bookkeeping, and that is the tone of most of
   what they read while playing.
2. **Both endings are kind to Zennit.** If he wins he becomes the clerk, and if the group wins he is freed; each finale ends with
   him invited and the party at his table. The group gets a story for losing a week (his chapters) and he gets one for
   winning it (theirs). That meets the Griefing / Friendship entry; it is worth keeping.
3. **The players are not in it.** The 32 scenes name only Zennit; the group is "the party". The personal material exists in
   the log (who tipped a roll, who summoned him most, how many dice he won in a row) and surfaces only as a chat line that
   scrolls away. That is the part a friend group would repeat to each other.
4. **The story and the rules echo in places, not in others.** His list is the syllabus (z3), the fifty silver is the Ritual's
   price (g4), the week off is real now (z1). But the cake, the carbon copy and the cellar have no counterpart in play, and
   the silver Zennit asks for and marks paid ("They paid") never reaches chapter g5, where the group pays the Ritual.
5. **It runs out.** A normal season shows about 6.7 of the 10 chapters (about 6 minutes of story over 11 weeks, 33 seconds a
   week), and season 2 replays them; "The Index today" varies, but it is one scene.
6. **We do not know what Zennit wants.** The z chapters give him agency, but which ending he would pick, and whether being the
   clerk is the better one, is for the playtest.

**Proposed changes** (none built yet)

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **The Index remembers**: "The Index today" tells a moment or two from this season, named: the roll a helper pair tipped, who has summoned him most, a run of dice he won. Worked out from the log, so every client agrees | 3, 5 | Wording and one function; no art or voice |
| B | **The Index's voice in the five lines**: the same facts, said as the Index would ("The Index has noted a summons to Deadmines; he has been told") | 1 | Wording; risk of more reading in chat |
| C | **Silver reaches the story**: the silver paid to Zennit in a season is counted, and chapter g5 (or the Ledger) uses the number | 4 | A tally, and re-voicing scene 30 if the number is spoken |
| D | **A season keepsake**: when a finale lands, record it with who was there (a list of past seasons in the Tools tab, and a line in chat) | 3, 5 | Small; stored in the log or settings |
| E | **New chapters for season 2** | 5 | The largest: writing, art, voice |

**Our answer:** build **A, C and D**, and **name the players** by character name.

**Built** (`Ledger.lua`; every line is worked out from the log, so all clients tell the same story)
- **A, the Index remembers.** "The Index today" now tells up to two moments of the season: the roll a pair of helpers tipped
  ("Al and Cy's +10 tipped one of Bo's rolls: 52+10 against his 45+10. The Index has framed it."), who has summoned him most
  (three or more, and no tie), and a run of three or more dice he won. A tipped roll is the same test the chat line uses:
  he would have won without the bonus.
- **C, the silver reaches the story.** The silver Zennit marks as paid is counted for the season ("The group has paid Zennit
  100 silver, in cash, with no receipt. The Ritual has asked to be kept informed."), with what is still owed. It shows in the
  scene, in the keepsake, and on the tooltips of the group's last two chapters, where the Ritual names its price (g4) and
  receives it (g5). The recorded narration is unchanged: the number is not spoken.
- **D, the keepsake.** When a finale lands, the chat gets the Index's record of that season, and `/sc seasons` (or the Tools
  tab's **Past seasons**) lists them all: how it ended, how many weeks it took, who was in the room, the silver, the moments.
  Nothing is stored: each season is recomputed from the log, so a client that syncs later still gets it.

The scene grew, so it is capped at two lines of memory (the silver counts as one). `Week.Season` now gives each finale a
`from` (the first week of that season) and the season in progress a `since`.

**Not built.** B (the Index's voice in the five lines of a normal summon) and E (new chapters for season 2) wait for the
playtest: B adds reading to chat the group may not want, and E is the largest piece of work. E is now outlined in
`design/season-two.md` (2026-10-06): one arc, "Zennit and the Audit", with an opening for each of season one's endings.

**To decide before building**
- Which feeling matters most at the end of a season: the group's pride, affection for Zennit, or the joke? (Asked at the playtest.)

**To watch in playtests**
- Which lines does the group quote back to each other: the chapters, the chat, or the gags?
- Does Zennit say which ending he wanted? Does the clerk ending feel like a prize to him?
- Do people replay chapters, or skip them once heard?

### 2026-10-04 · Lens of Surprise, with the Lens of Curiosity: week 9

**The questions (paraphrased):** what will surprise the players, in the rules, the story and the people? What questions
does the game put in their heads, and are they worth answering? Surprise wears off, so the real test is a surprise that
still works the tenth time.

**Where surprise comes from, as built** (`Respond.lua`, `Gag.lua`, `Clips.lua`, `Intro.lua`, `Ledger.lua`)

| Source | Who it surprises | Variants shipped | Shelf life |
|---|---|---|---|
| Zennit's choice of answer (accept, refuse, silver, dice) | The summoner | Four, picked by a person | **Does not wear off**: it is a friend |
| The dice | Everyone in chat | A fresh pair of numbers each time | Long, but only the numbers change |
| A place on his secret list | The group, when it hits ("It is on his list: +3") | One per place on the list | Each place once, then it is known |
| A chapter | Everyone | 10, hidden as "???" until the race reaches them | Once each; season 2 is a replay |
| "The Index today": a named moment, the silver | The group | Worked out from the log | Fresh each time the facts change |
| The gag on the wrong tab | Zennit, or the party | **1** animation, 1 recording | A few viewings |
| Voice clips: `wag`, `zenit_land`, `zenit_refuse`, `zenit_win`, `ritual`, `narrator_weekopen` | The player who triggers them | **0** recorded (`ClipList.lua` is empty) | None yet: every random pick picks silence |
| The Index's chat lines | Nobody | About 11 templates | See finding 3 |

**Findings**
1. **The surprises are in the people and the story, which is where a friend group wants them.** Zennit's answers and the
   reveals in the story are the two sources that do not run out in a season, and neither is a random table.
2. **The authored randomness is empty.** The addon picks a random clip per category and avoids repeating, but no clip is
   recorded and only one gag exists, so a random pick is the same pick. The README says some lines are meant to surprise
   Zennit; none can yet.
3. **The lines that repeat are wallpaper by week 9.** A normal season has about 6.7 weeks of play and 3 summons of him a
   week, so about 20 summons. Each prints five lines (the briefing, "Summon logged", "Week:", his answer, "Week:") from
   fewer than a dozen templates: about 100 lines, each template seen 10 to 20 times, none varying but the numbers.
4. **Every week plays under the same rules.** Apart from the catch-up edge, week 9 is week 1 with different dice. The
   Interest Curve entry found the same thing from the other side (a flat week); a surprise inside the rules would help both.
5. **The list is the best-designed surprise we have and it is a one-shot.** It is secret, it reveals itself in front of
   the group at the moment it hits, and it gives Zennit something to lose and win. After a place is revealed the group
   knows it, and nothing in the game remembers.
6. **We do not know what surprises Zennit.** He sees every summon from the receiving end; the one thing he does not choose
   is who, where and when. The playtest should ask.

**Stale note found in passing:** the README's Status table said no place is marked `remote`, so the Far Flung badge could not
be earned. Ten far-flung maps have been marked for a while (from memory, to be confirmed with `/sc where`); the row is fixed.

**Proposed changes** (none built yet)

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **Pools of lines**: three to five variants for each line that repeats most (his answers, "Summon logged", the week's result, the last die), same facts, picked at random without an immediate repeat | 2, 3 | Wording and one small helper; more flavour in chat |
| B | **A whim of the week**: each Monday the Index draws one of about eight small rule twists (dungeons count double, ties go to the group, a helper adds +10), announced at login and shown in the briefing; it follows from the week number, so every client agrees and nobody keeps books | 4 | A rule layer: wording, the balance simulation, and a toggle |
| C | **A recording sheet**: the lines to record for each clip category, so the group can fill `Media/clips` in one evening | 2 | A page of wording; no code |
| D | **The list remembers**: when a place on his list hits a second time, the Index says so ("Darnassus again. The Index is beginning to see a pattern.") | 5 | Wording and a counter on the log |

**Our answer:** build all four.

**Built**
- **A, pools of lines** (`Voice.lua`). His seven answers, "Summon logged", the "Week:" line, the last die and the week's result
  each come in three variants with the same facts; one is picked at random and never the one before. The self-test checks that a
  variant is never repeated, that all three get used, and that every answer variant still names its numbers.
- **B, the whim of the week.** About half the weeks the Index draws one of four twists from the week number (the same on every
  client, nothing synced): *distracted* (his edge 5 lower), *attentive* (5 higher), *a helpers' feast* (+8 a helper) or *the
  helpers are tired* (+2). I measured each in the week model before choosing the size (group's chance, quiet / normal / trying):

  | Whim | Quiet | Normal | Trying |
  |---|---|---|---|
  | A plain week | 15% | 27% | 63% |
  | Distracted (edge 5) | 19% | 32% | 69% |
  | Attentive (edge 15) | 12% | 23% | 58% |
  | A helpers' feast (+8) | 15% | 31% | 70% |
  | The helpers are tired (+2) | 15% | 24% | 56% |

  Each moves a normal week 3 to 5 points either way, so the deck is about neutral and no week is much easier than another. I
  left out whims that change the dice (a fourth die moves a trying week from 63% to 45%, a second from 63% to 83%): too large for
  a week to survive, and he can already close the Index. Weeks off have none. `Week.RULES.whims = false` turns the layer off.
  It is said at login, in the briefing, in "The Index today" and in `/sc week`.
- **C, the recording sheet** (`design/recording-sheet.md`): the six clip categories, what triggers each and who hears it, and six
  or so lines to start from, with how to convert, name and install the takes. It makes the dormant random picks real. It is in
  the repo so it is not lost, and so are the takes, which means Zennit can read and hear them there.
- **D, the list remembers.** When a place on his list comes up a second time, the answer line adds "Darnassus again. The Index is
  beginning to see a pattern." (then "for the third time"). Never the first time, so the list keeps its secret until it hits. It
  reads only what his answers already say (`listed`), so every client agrees.

**To decide before building**
- How much extra flavour in chat before it becomes the reading the group dislikes? (Asked at the playtest.)

**To watch in playtests**
- Which lines does the group stop reading? Which do they repeat to each other?
- Does Zennit use his list to surprise, or does he forget it is there?
- Does anyone ask what next week's rules will be?

### 2026-10-04 · Lens of Elegance, with the Lens of Balance: which rules earn their place

**The questions (paraphrased):** what does each rule do for the game? Could it go without changing the experience? Do the
rules interact in ways the players cannot see? Is there a small core a player can hold in their head? We have added a rule
or two with every lens, so this is the moment to take stock.

**An ablation of the weekly race.** The weekly model that reproduces the Fairness table (15%, 28%, 64%), with one rule changed
at a time. The group's chance of winning a week: quiet (2 summons, no helpers), normal (3, one helper), trying (5 dungeons, 2 helpers).

| Rule changed | Quiet | Normal | Trying |
|---|---|---|---|
| **As built** | 15% | 27% | 63% |
| No head start (0 instead of 2) | 15% | 28% | 63% |
| No helper bonus | 15% | 23% | 52% |
| No edge for him on the dice (the most catch-up can give) | 23% | 39% | 74% |
| His edge at +20 (the most it can take) | 9% | 18% | 52% |
| No dice limit | 15% | 27% | **30%** |
| No secret list | 16% | **42%** | **87%** |
| The list on half of all places | 12% | 16% | 42% |
| The list on three places in four | 7% | 7% | 20% |
| **The list on every place** | **0%** | **0%** | **0%** |

**The rules, and what each is worth** (the numbers are points of a normal week's chance)

| Rule | What it does | Worth | Verdict |
|---|---|---|---|
| Only summons of him count | He is the target (Essential Experience) | The premise | Core |
| Three dice a week | Makes *when to roll* a choice | 33 points on a trying week | Core |
| His +10 edge, with catch-up and the whim | The one smooth dial | 12 points either way | Core |
| Helpers add +5 (two at most) | Gives the helpers a part | 4 to 11 points | Core: it is the helpers' story |
| Cap of 10, he may close after 5 | His way out, neutral by design (Griefing entry) | About 0 | Keep |
| His week off is filler | Makes his wins a pause | 0 a week, 4 weeks a season | Keep |
| Whims | Variety | 3 to 5 points, on purpose | Keep |
| **Head start of 2** | Was the difficulty dial | **0 to 1 point** | **Dead weight** |
| **His secret list** | Something for him to win | **15 to 24 points, unbounded** | **The strongest rule, and the one with no limit** |

**Findings**
1. **The list is the strongest rule and has no bound.** At the 1 in 4 we assumed, it is worth 15 points of a normal week. But it
   is whatever Zennit makes it: an entry matches any place whose subzone or zone name contains its text, with no minimum length and
   no limit on entries, so a single letter matches most places. At every place the group's chance is 0% at any effort.
   The design (Griefing entry) was that he can say "enough", not that he can decide the week; this decides it.
2. **The head start does nothing.** From 2 to 0 the chance moves by a point, because it only matters in a week of one or two
   points of summons (a city). It is still printed in several lines ("including a 2 point head start") and the season band.
3. **The rules are a dozen, and no line says them all.** A player has to hold what counts, the cap and the close, the dice,
   the edge, the helpers, the list, the week off, the catch-up, the whim, the season and the points by place. The intro narrates
   eight of them and was written before the catch-up, the whim, the filler and the last die; the README is the only whole list.
4. **Two edges stack.** The whim (5 either way) and the catch-up (5 or 10) both move his edge, so it ranges from 0 to 25 and
   the group's trying week from about 47% to over 74%. The floor at 0 stops it being a handicap; nothing else bounds it.

**Proposed changes** (none built yet)

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **Bound the list**: at most 5 entries, each at least 4 letters (a place, not a letter). Entries beyond the fifth or shorter than four letters stop matching | 1 | Two constants and a check |
| B | **Drop the head start** (0 for the new rules; the old weeks keep theirs): the lines and the band no longer mention it | 2 | One constant, a few strings, the Fairness table's note |
| C | **A rules card**: `/sc rules` (and a Tools button) prints this week's rules with the live numbers: what counts, the cap and the close, his dice, his edge with its catch-up and whim, what a helper adds, the list's size, the week off. One source of truth, never stale | 3, 4 | A function that reads the same numbers the game does |
| D | **Re-voice intro scenes 9 and 10** to the current rules | 3 | Wording, then re-recording: the largest |

**Our answer:** build **A, C and D**. **B (drop the head start) is not chosen**, so the head start stays at 2 for now.

**Built**
- **A, the list is bounded** (`Respond.lua`). At most 5 entries, each at least 4 letters: adding a shorter one or a sixth is refused
  with the reason (`/sc zennit list add`, and the Zennit tab prints it), and `Respond.OnList` only reads the first five entries of
  four letters or more, so an older short entry stops matching. The Zennit tab dims entries that do not count.
- **C, the rules card** (`Week.RulesCard`, `/sc rules`, the Tools tab's **The rules**). The race on one card with this week's live
  numbers: what counts and the cap and the close, the points by place and his head start, his dice and edge (the base, the whim and
  the catch-up already applied) and what a helper adds, his list, the catch-up steps, the season, and the week's whim or a week off.
  It reads the same numbers the game uses, so it cannot go stale. It prints to chat, which scrolls.
- **D, intro scenes 9 and 10 re-worded** to the current rules (`Intro.lua`, and the speech text in `render_takes.py`): only summons
  of him count, five places on his list, leave and filler, the Index leaning toward the side that is behind, a whim some weeks, five
  weeks to a season. Every phrase the cues and highlight boxes look for is still in the text, so the art and the scripts are unchanged.
  **The audio is not re-rendered.** The Kokoro model, `sherpa-onnx` and PowerShell (for `build_audio.ps1`) are on the Windows
  machine, not in this workspace; until `render_takes.py --only 9,10` and `build_audio.ps1` are run there, the narration and the
  typed text are still the old recording, which is consistent but out of date.

**Not chosen.** B, dropping the head start: it moves a week by about a point, but it only matters for weeks of one or two points,
and nobody asked for it to go.

**To decide before building**
- Is five places of four letters or more the right bound? (Asked at the playtest, with how wide he makes the list.)

**To watch in playtests**
- How wide does Zennit make his list, and how often does the Index say "again"?
- Can the group say the rules back? (If not, the card is not enough and the intro needs redoing.)

### 2026-10-05 · Lens of Playtesting: the first season

**The questions (paraphrased):** why am I playtesting, and what do I want to learn? Who should test, when, where, and how will I
learn it: by watching, listening, asking, or reading what the game recorded? Every lens so far ended in a list of things "to watch
in playtests"; the new rules start **today, Monday 5 October 2026 (UTC)**, so this is the moment to turn them into a plan.

**The lists, sorted.** Across the nine entries there are about 30 open questions.

| Kind | How many | How we learn |
|---|---|---|
| Numbers the log already holds (how many summons a week, how he spends his dice, whether he closes, the list's hit rate, who wins the weeks) | About 14 | **Read the log**: no one has to remember or keep notes |
| Feelings (what the group quotes back, what they stop reading, what Zennit enjoys, which ending he wants) | About 12 | **Ask people**, separately, and watch |
| Things never run in the live client (`/sc synctest`, the intro's new scene, the dice between two real clients, a real Monday rollover) | 6 | **A smoke test first**, before judging any design |

**Findings**
1. **The group dislikes bookkeeping (the Player entry), so the plan cannot rely on notes.** Most of the numbers are already in the log
   (every summon, helper, answer and roll is there); they only need counting.
2. **A design question is only settled by evidence we can name.** Each open decision (five wins or four, the list's bound, the cap
   and the close, the whim, the catch-up steps) now has the number that would change it, in the table at the end of the script.
3. **Several things we shipped have never run in the game.** The self-tests added since 4 October, the Ledger scene, the new dice
   edge flow and the whim: the first job of the playtest is a ten-minute smoke test, not a verdict on the design.
4. **A report in the group's own chat is also a way to play.** Pasting the week's numbers each Monday gives the group something to
   argue about (banter, the thing they like) while it gives us the data.

**Built**
- **`/sc report`** (`Report.lua`, and the Tools tab's **Playtest report**): what the log says about how the race is being played.
  Weeks with and without a summons of him, how many a week, the group's wins by how many summons counted, his answers and how fast
  he gives them, how he spends his dice (on the first three summons of a week or not, what a rolled summons is worth against an
  unrolled one, and what comes after his last die), how often the list hits, helpers per summons and the rolls they tipped, and
  when he closes. Nothing is stored or synced; paste it into the group chat.
- **`design/playtest.md`**, the script: the ten-minute smoke test, what to watch while playing, one command and three questions
  each Monday, the report-to-question table with the number that would change each decision, the questions only people can
  answer (separately for everyone, the warlocks, the helpers and Zennit), and the table of open decisions and what settles them.

**Not built.** No in-game survey or note-taking: it would be exactly the bookkeeping the group dislikes.

**To watch in playtests**
- Does the group paste the report, or does it have to be asked for? (If it is not read, it is not worth the chat lines.)
- Which question in the script gets the most honest answer, and which gets a shrug?

### 2026-10-05 · Lens of Community: what if Zennit is not at his desk?

**The questions (paraphrased):** what kind of community does the game assume, and what does each member owe it? What happens
when someone joins, leaves or goes quiet? Does the game depend on everyone behaving, and what does it do when they do not?
The group here is a handful of friends with real lives: holidays, flu, a month off WoW, a bad week.

**What the build assumes about each member** (`Respond.lua`, `Sync.lua`, `Week.lua`, `Store.lua`)

| Member | The game assumes | What happens if they are absent |
|---|---|---|
| A warlock | Casts when others want to be summoned | Nothing: the others carry on |
| A helper | Turns up at the portal | Fewer helpers; the bonus is smaller |
| A new friend | Joins the guild or party and runs the addon | Sync brings the log across (about three records a second); the story is derived from it, so they are caught up |
| The admin | One account (`ST.ADMIN_HASH`) | Debug tools wait; nothing in play depends on it |
| **Zennit** | **Answers every summon of him himself** | **Every unanswered summon counts as accepted, for good** |

**The numbers.** The group's chance of winning a week and of taking the finale, as the share of summons he actually answers falls
(the weekly model that reproduces the Fairness table; unanswered summons are accepted, and never on his list):

| He answers | Quiet week | Normal week | Trying week | Normal season: group takes the finale |
|---|---|---|---|---|
| All of them | 15% | 27% | 63% | 7% |
| Three in four | 30% | 51% | 74% | **52%** |
| Half | 49% | 75% | 87% | **95%** |
| One in four | 72% | 93% | 98% | 100% |
| None | 100% | 100% | 100% | 100% |

**Findings**
1. **The whole balance is hostage to his attendance.** If he skips one summons in four, a normal week goes from 27% to 51% and the
   season from a 7% chance of the group's finale to 52%. Every number in the Fairness, Interest Curve and Skill entries assumes
   he answers each one.
2. **Absence pays the group, and the story goes on without him.** An unanswered summons lands and counts as accepted (the popup says
   so), and there is no limit. A holiday gives the group chapters, and a finale where "Zennit is freed" can happen while he is away.
3. **Nothing reminds him, and the group cannot see it.** A summons arrives as a popup if he is online; if he is not, nothing greets
   him at login. The "Week:" line does not say how many are waiting, so the group cannot chase him: the banter the Player entry
   says they like has nothing to grab.
4. **A result can be announced and then change.** Monday's chat line (a minute after login) uses the week as it stands; he can still
   answer until the week closes two days later, so a late roll can reverse a win that was announced and whose chapter was unlocked.
   (The Interest Curve entry noted this; it is still open.)
5. **Joining, leaving and roles are fine.** Sync catches a new member up from the log, his alts are learned from his own client,
   and only the caster can delete a summons. A friend group does not need more machinery here.

**Proposed changes** (none built yet)

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **A nudge, and a number**: at login (and as a summons arrives while he is away) his client says "N summons are waiting for your answer", and the "Week:" line and the briefing give the count ("2 waiting for his answer") so the group can chase him | 1, 3 | Wording and a count |
| B | **A provisional Monday**: the week's result is announced as provisional while summons are still unanswered and the week is open, and again as final when it closes (and it says so if it changed) | 4 | Wording and one more line |
| C | **Held over**: a summons still unanswered when its week closes is filed as filler (the race ignores it), not accepted. An absent Zennit pauses the race; he cannot gain, but he can stall a win by staying silent | 1, 2 | A rule; changes what "ignoring" means |
| D | **A declared leave** (`/sc away`): he says he is away, the week is filled as filler like a week off, and the Index writes the line. Needs a new sync message and a limit per season | 1, 2 | A protocol change; the largest that stays honest |
| E | **The Index answers for him** after a day: a roll worked out from the summons' id, the same on every client, so the week keeps its balance without him | 1, 2 | A rule with a subtle consequence: the score can change when the clock passes a day |

**Our answer:** build **A and B**; **C, D and E wait**. An unanswered summons still counts as accepted for now, and the playtest report
will show how many he leaves, and for how long.

**Built**
- **A, a nudge and a number.** A summons of Zennit unanswered for an hour (`Week.RULES.overdue`) is "waiting for his answer". The
  "Week:" line says so ("... 2 waiting for his answer", and "waiting for your answer" on his own client) and so does the briefing as
  a ritual on him begins ("2 earlier summons of him are still waiting for his answer: a word to him might help"). A fresh summons is
  not counted, so the line is quiet right after "Summon logged". On his client, a minute after login, the chat says "N summons are
  waiting for your answer. /sc respond opens the latest."
- **B, a provisional Monday.** If summons of him are unanswered while his week is still open, the Monday announcement ends
  "Provisional: N summons of him are still waiting for his answer, and the week closes on Wednesday. The Index will say again if
  it changes." Once the week has closed, the next login says "The week of 12 Oct is now final: it stays with the group", or "The week
  of 12 Oct changed after Zennit's late answers: it went to Zennit, not the group." A finale's keepsake is held until the result is
  final. The announced result is remembered in settings (`weekAnnounced`) on each client; nothing is synced.

**To decide before building**
- When he does not answer, should the race wait for him (C), go on without him (E), or take his word that he is away (D)? (After the
  first weeks of the report.)

**To watch in playtests**
- How many summons does he leave unanswered, and for how long? (`/sc report` shows both.)
- Does the group chase him when they can see the number, or does it feel like nagging?
- Has a Monday announcement ever changed by Wednesday?

### 2026-10-05 · Lens of Economy: the silver, the cards and the points

**The questions (paraphrased):** what does the game count as currency, where does it come from, where does it go, and what keeps
it in balance? Is there a price players can anchor on? Can anyone create or destroy value without limit? Until now the game's
only currency was imaginary (points); the silver and the cards put **real in-game money** into it.

**The flows, as built** (`Respond.lua`, `Cards.lua`, `Scoring.lua`, `Store.lua`)

| Currency | Comes from | Goes to | Limit |
|---|---|---|---|
| **Points** (1, 3, 5 or 10 a summons) | A summons that lands, to the caster | The tally, the six badges, the race | None; they cannot be spent on anything |
| **Silver** (real) | The caster, when Zennit asks | Zennit, in cash | **None**: he names it, up to 100,000 silver (1,000 gold) |
| **Punches** (a card) | Bought once from Zennit | Spent one at a time against his asks | The card's size; they never expire |
| **A tab** | His asking for silver | The caster, until he marks it paid | None |

**How much, in a season** (about 20 summons of him over 11 weeks at normal effort, three warlocks, so about 7 each)

| If he asks | Silver a season (whole group) | A warlock's share |
|---|---|---|
| The usual 50 every time | 1,000 (10 gold) | about 350 |
| 200 every time | 4,000 (40 gold) | about 1,400 |
| 50, with a card of 5 for 200 (40 a punch) | 800 | about 280 |

**Findings**
1. **The silver is the only unbounded currency.** Points have a rate that is set by the places; punches are limited by what was
   bought; but how much silver he asks is up to Zennit alone, to 1,000 gold a summons. Nothing in the race depends on it (a summons
   counts either way), so it cannot hurt the balance, but it can hurt the mood.
2. **There is no anchor.** "The usual 50" is only the default of the box. A card of 5 for 200 is a bargain only compared with a
   price Zennit can change: if he asks 500, the card is a protection racket, and if he asks 20 it is a rip-off. Cards and asks are
   priced independently by the same person.
3. **Nothing enforces the tab, which is right, and nothing shows it.** An unpaid tab changes nothing in the game; it is trust
   between friends. But the only places the tab is seen are the "Week:" line (this week, in total) and one line at login. No
   statement says who owes what across the season.
4. **Points are a currency with nothing to buy.** They feed the tally and six badges; a warlock reaches Fifty Summons in about
   seven seasons. Helpers earn none, on purpose (the Player entry: the group likes banter, not badges).
5. **The story's silver is not this silver.** In chapters g4 and g5 the group pays the Ritual fifty silver. The silver the
   group has really paid appears only on the tooltips and in the keepsake.

**Proposed changes** (none built yet)

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **Bound the ask**: no more than 5 times the usual price per summons (250 silver) | 1 | A constant and a check |
| B | **A statement**: `/sc tab` lists who owes what, to Zennit across the season, and to each caster for themselves; and the tab is in the Tools tab | 3 | A function and a button |
| C | **Cards are always a discount**: a card's price per punch may not be above the usual 50 (so a card never costs more than asking), and an ask without a card may not be more than five times the card's price per punch | 2 | Two checks on his client |
| D | **Spend points**: points buy something small (a point towards a helper's bonus, or a reduction of his edge for one summons) | 4 | A rule, and balance |

**Our answer:** build **B**. On bounding the ask (A) the answer was **no bound: trust the group**, so the ask stays up to 1,000 gold and
nothing is built for A. C (cards always a discount) and D (spend points) were not chosen.

**Built: B, the statement.** `/sc tab` (and the Tools tab's **The tab**) prints the tab as a statement. On Zennit's client: the total owed
to him and the total paid so far, then one line per payer, largest debt first ("Bo owes 250 silver on 2 summons (the oldest from 12 Oct);
paid so far 150"), across every week. On anyone else's: only their own tab ("You owe Zennit 250 silver on 2 summons...") and their card's
punches. Test summons and summons of other people are left out.

**To decide before building**
- Do points need a use, or are they only a score? (Not chosen for now.)

**To watch in playtests**
- What does Zennit ask, and what do the casters say about it? (`/sc report` does not show it yet.)
- Does anyone buy a card, and at what price?

### 2026-10-05 · Lens of Reward: who gets what, and when

**The questions (paraphrased):** what rewards does the game give (praise, points, a gateway to more, spectacle, expression, powers,
resources, completion)? Does each kind of player get some? Do they arrive often enough, and do they stay surprising? And what
happens to someone who fails: is there a punishment, and is it one the friends would enjoy?

**What each member receives, as built** (`Scoring.lua`, `Ledger.lua`, `Intro.lua`, `Respond.lua`)

| | A warlock | A helper | Zennit | The group |
|---|---|---|---|---|
| Praise | "Summon logged", points, the Index's lines | Named when their bonus tips a roll | The Index's lines, his own popup | The keepsake |
| Points | The tally, the race | None (on purpose) | Hidden by the gag | The race |
| A gateway | Chapters, shared | Chapters, shared | Chapters, shared | A chapter a win, the finale |
| Spectacle | The story viewer, the gags | The same | The gag on the wrong tab | The same |
| Expression | Named in the keepsake and the moments | Named as "in the room" | Named in the keepsake | None to choose |
| Powers and resources | Cards (a discount) | None | Silver, cards he sells, his list | None |
| Completion | Six badges, a season | A season | A season | The finale |

**How often** (about 20 summons of him over 11 weeks at normal effort; three warlocks, so about 7 each)

| Reward | Arrives |
|---|---|
| The first one (a logged summons, points, "First Summon") | At once |
| A chapter | About every 1.6 weeks (a win a week-and-a-bit), shared |
| The finale and its keepsake | About week 11 |
| A warlock's badges | **Five of six in the first season or two** (First Summon, Dungeon Doorman, Far Flung, Well Travelled, Ten Summons); then nothing until Fifty Summons, about **seven seasons** away |
| A helper's named line ("Al and Cy's +10 tipped it") | About **once every other season**: roughly 14 rolls a season, about 6 with helpers, each tipped about 7% of the time |

**Findings**
1. **The rewards are collective, which fits the group.** Chapters, the finale and the keepsake belong to everyone; the Player entry
   says the group likes banter and doing things together, not achievements.
2. **The individual rewards are front-loaded, and only warlocks get them.** After the first season or two a warlock has one badge
   left, seven seasons off. Nothing new to chase.
3. **A helper's only reward is the named line, and it comes about once every other season.** Helpers are most of the group (two or
   three warlocks, the rest helpers), and the game asks them for togetherness, which it barely acknowledges. (No badges for them: the
   group said so. Recognition in words is a different thing.)
4. **Zennit has no named recognition of his own.** He gets the results of his answers, silver and chapters, but his tally is hidden
   (the gag) and the keepsake names the group more than him.
5. **The weeks between rewards are filled with numbers.** A chapter every 1.6 weeks is a good pace, but what comes between is "Week:"
   lines and the tab.
6. **Punishment is fine.** Losing a week gives the group Zennit's chapter; a refusal costs him points; the only thing that stings
   is a tab, and that is owed to a friend. Nothing needs changing.

**Proposed changes** (none built yet)

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **Season titles**: when a season ends, the Index gives out a handful of titles, each to one person by name (the heaviest hand; the best supporting role, for most assists; the lucky pair, whose bonus tipped most rolls; the prompt payer, who paid the most silver), worked out from the log, shown in the keepsake and `/sc seasons`. Titles for helpers and warlocks alike, praise and no points | 2, 3 | A function over the log; wording |
| B | **Standings mid-season**: `/sc titles` shows who leads each title now ("The best supporting role: Cy, 9 assists; Al, 7"), so there is banter to be had before the season ends | 5 | Reuses A |
| C | **Titles for Zennit**, in the same spirit and kind to him (the dice goblin, for his longest run; the hard bargain, for the biggest ask; the quick reply, for his fastest median answer) | 4 | Reuses A |
| D | **More individual badges** spread across the season (for example Ten Assists, a clean tab, a card used up) | 2 | New badge rules; helper badges were turned down |

**Our answer:** build **all four** (A, B, C, D).

**Built** (`Ledger.lua`; every figure is counted from the log, so every client names the same people)
- **A, season titles.** At a finale the keepsake (and `/sc seasons`) names up to seven titles, each to one person (or both, on a tie):
  *The Heaviest Hand* (most summons of him, at least 3), *The Best Supporting Role* (most assists, at least 3), *The Lucky Pair* (the
  helpers whose bonus tipped the most rolls), *The Prompt Payer* (most silver paid, at least 50). Praise in words, no points.
- **B, standings.** `/sc titles` (and the Tools tab's **The titles**) shows the same for the season in progress, with who is close
  behind ("The Heaviest Hand: Al, with 5 summons of him (Bo is next with 4)"), or says nothing has been earned yet.
- **C, Zennit's titles**, kind ones: *The Dice Goblin* (a run of three or more dice wins), *The Hard Bargain* (his biggest ask, at
  least twice the usual price, and of whom), *The Quick Reply* (his median time to answer, if it is within an hour: a slow one is
  not named, so there is no title for being late).
- **D, four badges that come later,** for the people who cast: *Regular* (summoned him in four different weeks), *Well Supported*
  (helpers tipped a roll of yours), *Clean Slate* (paid in full and owe nothing), *Card Sharp* (used up a card). They are checked when
  a summons is logged and when an answer arrives. Helper badges stay turned down (the Player entry), so helpers get titles instead.

**To decide before building**
- Are titles (praise in words, once a season) the right size of reward for helpers? (Asked at the playtest.)

**To watch in playtests**
- Which titles does the group argue about, and which does nobody care for?
- Does anyone ask where they stand before the season ends?

### 2026-10-05 · Lens of the Interface: finding and reading what you need

**The questions (paraphrased):** what does the player see, and what can they do, at each moment? Is each piece of information where
the player is looking when they need it? Is it easy to find the thing you do not know the name of? Does the interface grow in a
way that still reads, or does it only accrete? Every lens since Visible Progress has added a command or a button.

**The surfaces, as built** (`Core.lua`, `Hub.lua`, `Respond.lua`, `Silver.lua`)

| Surface | What it carries | How many |
|---|---|---|
| Chat | The moments of play (a briefing, "Summon logged", "Week:", his answer), reports, diagnostics | About 5 lines per summons of him, and the reports below |
| The hub (`/sc`) | The season band above six tabs: Party, Zennit, Log, Story, Sync, Tools | 6 tabs; Tools has 5 columns |
| Popups | Zennit's answer, the dice, the assistants prompt, the silver confirmation, the price box, reset | 6 |
| Slash commands | Everything above, again | 33 commands, 25 lines of `/sc help` |

**Findings**
1. **The Tools tab overflowed for the admin.** One column ("Try things") had grown to 15 buttons at 30 px each: 482 px down a 458 px
   tab, so for the admin the rows under it ran off the bottom and the output box had no height. It was my own doing: every lens
   added a button. (A non-admin column of 10 fit, with an output box of 80 px.)
2. **The reports are long and go to chat, where they scroll away.** The rules card is nine lines, the report ten, a season's
   keepsake seven or more, the titles up to seven. Chat is right for the moments of play and for pasting a report to the group; it is
   a poor place to *read* a rules card at leisure, and the Tools tab's output box is too small to hold one.
3. **The useful commands are the ones nobody knows to type.** `/sc rules`, `/sc tab`, `/sc titles` and `/sc cards` answer the
   questions players will actually have, and the only place they are listed is `/sc help`: 25 lines long.
4. **What is on screen all the time is right.** The season band shows the lead, the filed count and the dice; the briefing and the
   "Week:" line say the rest at the moment it matters. Nothing there needs changing.
5. **The silver takes two steps.** The button, then a small box for the price. That is the right size for a decision he makes
   rarely; a card holder skips it.

**Built: the Tools tab.** The reports moved into a column of their own, **The record** (week and season, the rules, the titles, the
tab, the cards, past seasons, the playtest report), so there are five columns of at most eight buttons: the admin's tallest column
now ends at 272 px and leaves an output box of about 110 px (it was 482 px and none). The button width went from 180 to 142 px, so the
longest labels were shortened ("Preview Zennit gag" is "Zennit gag", "Resets everyone..." is "Reset all..."). **Not seen in the
client**: the layout is worked out from the numbers, and the first thing to check at the smoke test is that the Tools tab fits.

**Proposed changes** (none built yet)

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **A weekly tip**: one line at the Monday login that names a command players may not know ("Tip: /sc rules prints the race with this week's numbers"), rotating through five or six and never repeating one in a row | 3 | Wording and a counter |
| B | **A Record tab** in the hub: the same reports in a scrolling text area, so a rules card or a keepsake can be read at leisure without chat | 2 | A new tab, to be checked in the client |
| C | **A short `/sc help`**: five lines for players (`/sc`, rules, tab, titles, report) and `/sc help all` for the rest | 3 | Wording |
| D | **Reports pasteable**: `/sc report say` (and the same for rules, tab, titles) sends the report to party chat instead of the local window, so the Monday report reaches the group without copying it | 2 | A channel check |

**Our answer:** build **A (the weekly tip)** and **C (the short help)**. B (a Record tab) and D (say the report to the group) were not
chosen: B carries layout risk in a client we cannot see, and D can wait until the group pastes the report by hand and says it is a chore.

**Built**
- **A, the weekly tip.** Once a Monday at login (after the week's result and its whim) the chat says one line about a command players
  may not know ("Tip: /sc tab shows what is owed in silver, and /sc cards who holds a summon card..."). They go round in order, so none
  comes twice running; two are for Zennit's client only (`/sc respond`, `/sc zennit list`). `/sc tips off` stops it (and `on` brings it
  back). Tips live in `Week.TIPS`.
- **C, the short help.** `/sc help` (and an unknown command) prints five lines for players; `/sc help all` prints every command.

**To decide before building**
- Do players need more than the tip? (Asked at the playtest.)

**To watch in playtests**
- Which commands does the group actually type? Does anyone ask "how do I see..."?
- Does the Tools tab fit, for the admin and for the others?

### 2026-10-05 · Lens of Time: the week's clock, the season's calendar

**The questions (paraphrased):** what clocks does the game run on, and do the players know them? Where are the deadlines, and does
anything make a deadline felt? When do the players actually play, and does the game fit that? What happens when real life (a holiday,
a daylight-saving change) lands on the game's calendar?

**The clocks, as built** (`Week.lua`, `Respond.lua`, `Week.RULES`)

| Clock | Length | When it turns over, for a group on Australia's east coast |
|---|---|---|
| A week | 7 days, **Monday 00:00 UTC** | **Monday 11:00** in summer time (AEDT), **10:00** from April (AEST) |
| A week closes (answers stop, the result freezes) | 2 days after it ends | Wednesday 11:00 (10:00 from April) |
| A summons is "waiting for his answer" | 1 hour | |
| The Monday result | A minute after the first login after the week ends | |
| A season | Five wins, about 11 weeks at normal effort | The first, from 5 October, ends about **14 to 21 December** |

(The commit times in this repository are +1100, so the group's evenings are used as the example. Nothing in the game knows the group's
time zone: it is UTC throughout.)

**Findings**
1. **The week turns over at 11 in the morning, and nothing says so.** For an east-coast evening player this is harmless: the
   evenings of Monday to Sunday all fall inside one week, and Monday morning before 11 still belongs to the week before. But the
   README is the only place that says "Monday (UTC)", the rules card does not give a time, and no line tells a player when *their*
   week ends.
2. **There is a deadline and nothing makes it felt.** The Interest Curve entry wanted a beat in the last hours of a week and it was
   never built. Players learn the week is over a minute after their next login; they are never told it is about to end.
3. **We do not know when the group plays.** The log has every summons with its time, so the answer is in it, but `/sc report` does
   not say: it counts weeks, not days.
4. **The first season runs into the holidays.** Eleven weeks from 5 October is the middle of December, and the end of the year is when
   people are away. The Community entry found that the whole balance depends on Zennit answering; a Christmas fortnight with half the
   group away would give the group free wins and chapters (or none) for reasons that have nothing to do with the game. Nothing in
   the rules can pause a season.
5. **Daylight saving does not matter.** The clock is UTC; the shift in April moves the turnover from 11:00 to 10:00 for the group and
   changes nothing in the rules.

**Proposed changes** (none built yet)

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **Say the week's clock in the group's time**: the rules card, the briefing and the Monday line give when the week closes ("this week closes Monday 11:00, your time"), using the player's own clock | 1 | Wording and a `date` call |
| B | **A last call**: in the last 24 hours of a week, the briefing for a summons of him and the login say "the week closes in 9 hours: the group leads by 1, 2 summons filed" | 2 | Wording |
| C | **Days in the report**: `/sc report` says which days and evenings the group plays, so the week's clock can be chosen from evidence | 3 | A few lines in `Report.lua` |
| D | **A holiday pause**: a list of dates in `Week.RULES.pauses`; any week inside one is filler for everyone (like his week off, but for all), nobody wins it, and the season waits. Empty until the group says when they are away | 4 | A rule and a list |

**Our answer:** build **A and B**. The group is on the east coast of Australia, so **the turnover stays** (Monday 00:00 UTC, which is
Monday 11:00 in summer and 10:00 from April). C (days in the report) and D (a holiday pause) were not chosen.

**Built**
- **A, the week's clock in the player's time.** `Week.ClosesText` formats the close and the last answer with the player's own clock.
  The rules card says "The clock: this week closes Monday 11:00, your time (answers stop Wednesday 11:00). A week is Monday to Monday,
  UTC." and the Monday login says "This week closes Monday 11:00, your time; he can still answer until Wednesday 11:00."
- **B, a last call.** In the last 24 hours (`Week.RULES.lastCall`): the "Week:" line adds "the week closes in 3 hours", the briefing
  for a ritual on him ends "Last call: the week closes in 3 hours (Monday 11:00).", and a login in that stretch says it once with the
  standing. Not in a week off.

**To decide before building**
- When is the group away over the holidays, if at all? (Then a pause, D, can be written in.)

**To watch in playtests**
- Which days and hours do the summons fall on? Does anyone ask when the week ends?
- Is anyone away in December, and what does the group want to happen then?

### 2026-10-05 · Lens of Risk Mitigation: what could go wrong with 0.19.0

**The questions (paraphrased):** what could go wrong with this release, how likely is each, and how bad? What can we do now to make
it less likely, or less bad? Is there a cheap way to find out early? The group has not started yet (they are building it now), so
this is the last moment when a mistake costs nothing.

**The risks, ranked** (likelihood and impact are judgements, the numbers are measured)

| # | Risk | Likelihood | Impact | What exists | What is missing |
|---|---|---|---|---|---|
| 1 | **A Lua error in code that has never run in the game** (about 15 modules and a dozen self-tests were only exercised in a stub) | High | A feature, or the whole login, silently does nothing: with script errors off (the default) WoW shows nothing | The smoke test in `design/playtest.md` | Nothing catches an error and says so: a failing slash command prints nothing, and one failing login job stops the ones after it |
| 2 | **Clients on different versions** (the answer's wire format gained a flag bit and a silver amount; 0.18 reads the card flag as "closed the Index") | Medium | Wrong answers shown to some players | "Update together" in the README | Nothing tells a player that a friend is on an older version |
| 3 | **The client hides trade and mail amounts** (the 12.0 API hides some values) | Medium | The silver is not seen automatically | `pcall`, secret-value checks, a one-time notice, `/sc probe` | Nothing more can be done before it is tried |
| 4 | **A client's clock is wrong**: a summons is stamped with the caster's own clock, and the week is cut from it | Low | A summons lands in the wrong week on one client | None | No warning |
| 5 | **The addon gets slow as the log grows** | Low now | The window or the chat lags | Everything is derived, so it cannot drift | A measurement (below) |
| 6 | **A rogue guild member forges a message** | Very low | A fake card, or being named one of Zennit's alts | Names and values are validated; an answer needs the summoned character as sender; a card needs one of Zennit's characters | `A` (an alt announcing itself) is taken from anyone, up to ten |
| 7 | **Zennit is the single point of failure** (answers, cards, silver) | Medium | The Community entry | Waiting count, a provisional Monday | Left open on purpose |

**Cost as the log grows** (measured, plain Lua 5.1, so a game client will be somewhat slower or faster; 30 weeks of log)

| Events in the log | `Week.Season` | `/sc rules` | `Ledger.Seasons` | `/sc report` | The hub's refresh |
|---|---|---|---|---|---|
| 300 (about 15 seasons) | 40 ms | 43 ms | 284 ms | 333 ms | about 100 to 150 ms (it asks for the season several times) |
| 1,500 | 203 ms | 208 ms | 1,556 ms | 1,874 ms | about 0.5 to 1 s |

A first year is about 100 events, which is 10 ms or less. The cost is linear in the log and in the weeks: every call walks every
event for every week, and `Week.Edge` asks for the whole season each time it is asked. It is fine for years; if a refresh ever feels
slow, the fix is to remember the season until the log changes.

**Findings**
1. **The biggest risk is the one we cannot see.** We have measured, simulated and stubbed; we have not run. The smoke test is the
   plan, but a failure there should say what failed.
2. **A silent failure is worse than a loud one.** With script errors off, a bug looks like the feature not existing. A slash command
   that fails today prints nothing.
3. **Version skew is cheap to detect** and expensive to debug: the hello message already carries each client's version.
4. **A wrong clock is cheap to detect** too: the client knows both the server's time and the computer's.
5. **Speed is not a problem yet**, and has a known threshold.

**Proposed changes** (none built yet)

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **Say when a friend is on another version**: when a hello shows a different version, say once, "Bo is on 0.18.0 and you are on 0.19.0: update together" | 2 | A comparison and a line |
| B | **Catch errors and say so**: every slash command and every login job runs under `pcall`; a failure prints one line ("Summon Core hit a problem in /sc rules: ... Please tell Aaron.") and is kept for `/sc errors`, and one failing job no longer stops the others | 1 | A wrapper |
| C | **A clock check at login**: if the computer's time and the server's differ by more than five minutes, say so once | 4 | One comparison |
| D | **Remember the season** until the log changes, so the hub and the commands stay quick as the log grows | 5 | A cache and the care it needs |

**Our answer:** build **B and A**. The clock check (C) and remembering the season (D) were not chosen: a clock off by hours is rare
and the cost of the season is small for years.

**Built**
- **B, catch errors and say so** (`ST.Guard` and `ST.Safe` in `Core.lua`). Every slash command, the login, the Ritual detector, the
  silver watcher, the sync handler, the story viewer's frame update, each hub tab's refresh and each step of the Monday login (the
  week's result, the whim, the clock, the tip, what is waiting) now runs under `pcall`. A failure is said once in chat ("hit a
  problem in /sc rules: Week.lua:123: ... (/sc errors lists them; please tell Aaron)"), kept for `/sc errors` (the last twenty), and
  still handed to the game's own error handler so BugSack and the red box behave as before. One failing step no longer stops the
  steps after it.
- **A, a version notice.** When a friend's hello shows a different major.minor version, the chat says once per session: "Bo is on
  0.18.0 and you are on 0.19.1: ask them to update (answers and cards are read wrongly across versions)", or the newer-than-yours
  version of it. A patch difference is not mentioned.

**To decide before building**
- Do we want the clock check (C) once the group is playing, if a summons ever lands in the wrong week?

**To watch in playtests**
- Does `/sc errors` show anything? Does anyone see the version notice?

### 2026-10-05 · Lens of Unification: is it still one game?

**The questions (paraphrased):** what is the theme, in a sentence? Does every element (rules, story, look, sound, words) serve it?
Which ones do not, and do they have to change, or does the theme? A game that has grown by one lens at a time can end up as a pile
of good ideas that do not belong together.

**The theme, as the story states it:** *a deadpan bureaucracy of the impossible.* The Cosmic Index of Summonable Persons files
everything, accepts most things, never takes sides, and wants a receipt. Its vocabulary is paperwork: filed, stamped, evidence,
enthusiasm, a form in triplicate.

**Where each element stands** (`Intro.lua`, `Ledger.lua`, `Theme.lua`, `Week.lua`, `Respond.lua`, `Silver.lua`, `Cards.lua`, `Scoring.lua`)

| Element | Serves the theme? | How |
|---|---|---|
| The story (32 scenes, "The Index today") | **Yes** | The source of the theme; the Ledger scene is 70% in its voice |
| The look (green-on-black terminal, key clicks, a typed narration) | **Yes** | The Index is a filing computer |
| The rules' names (enthusiasm, filler, close the Index, the Ritual's price, a tab) | **Yes** | Paperwork words for game rules |
| The titles and the keepsake ("The Heaviest Hand", "the Index has framed it") | Yes | Written in the voice |
| The play-time chat lines | **Partly** | The week and the answers are 35% and 18% in the voice; the rest is plain |
| The silver and the cards (the newest systems) | **No** | Plain: "Take a punch", "Ask for silver (you name it), no receipt", "N summons are waiting for your answer" |
| The badges | **No** | Game-ish names (First Summon, Ten Summons, Regular, Clean Slate, Card Sharp) with none of the Index in them |
| The gag (a finger-wag with "ah ah ah") | Off-theme, on purpose | A pop-culture joke aimed at Zennit |

**Counted:** of about 270 player-facing sentences in the code, about 68 (a quarter) are in the Index's voice (a rough count by
its vocabulary). Most of the rest are diagnostics and labels, where a plain voice is right. The ones that matter are the lines read
*while playing*: the week (Week.lua) 35%, answers (Respond.lua) 18%, the silver popups and cards 0 to 16%.

**Findings**
1. **The theme is strong where the story is and thin where the play is.** The group reads a typed Index monologue now and then, and
   reads plain bookkeeping in chat every time they summon. That is the same gap the Story entry found (finding 1), and the
   pooled lines only partly closed it.
2. **The two newest systems have no voice at all.** Silver and cards arrived after the voice work; every line in them is neutral.
3. **The badges are the most visible rewards and the least themed.** Their names read as any game's.
4. **One-off words drift.** "Summons" and "summon", "leave" and "week off" and "filler", "punch" and "stamp" are used for the same
   things in different places. Nothing is wrong; it is a style guide that does not exist yet.
5. **The gag is the one deliberate exception**, and should stay.

**Proposed changes**

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **A voice pass on the lines read while playing**: the silver confirmation and the price box, the card lines, the waiting and tab lines, the last call, `/sc tab` lines; each in the Index's voice with the same facts (pooled where they repeat) | 1, 2 | Wording, and the tests that read exact words |
| B | **Index names for the badges**: display names only, ids unchanged ("First Summon" becomes "Entered in the Index", "Ten Summons" becomes "Filed in Triplicate"...), so what is on the Badges tab and in chat reads as the Index's | 3 | A names table |
| C | **A house style page** (`design/voice.md`): the words to use and avoid, five examples, so later text keeps one voice | 4 | One page |

**Our answer (built: A, B and C)**
- **A.** The lines read while playing are in the Index's voice with the same facts: the silver confirmation and the price box, the
  card lines, the waiting and tab lines, the last call and `/sc tab` ("The Index has Bo down for 250 silver on 2 summons...").
  The self-tests that read exact words were updated to match.
- **B.** Witty, in the Index's voice (the answer to the question below): "Entered in the Index", "Filed in Triplicate", "Known to the
  Clerk", "Paid in Full, No Receipt", "Stamped to the Last Punch" and so on. Ids are unchanged, so earned badges carry over. Because
  a witty name no longer says what it takes, each badge has a plain `how` line, shown next to a locked badge on the Badges tab and in
  `/sc badges`.
- **C.** `design/voice.md`: the words to use, what stays plain on purpose (labels, errors, anything the player must act on exactly),
  five before-and-after examples and a checklist for new lines.

**Decided:** the voice goes as far as the badges, and witty beats readable at a glance, because the plain `how` line carries the meaning.

**To watch in playtests**
- Which lines does the group quote? Are they the voiced ones?
- Does anyone ask what a badge is for? (The `how` line should answer it.)
- Nothing here has run in the live client; the voiced lines are checked only against stubs.

### 2026-10-05 · Lens of Endogenous Value: what is worth something here?

**The questions (paraphrased):** what do the players value *inside* the game, as opposed to what the designer decided to count? Which
objects, places and actions have value in the game's own world? Does the game pay out in things players care about, and can they
see what a choice is worth when they make it?

**What is worth something, as built**

| Thing | Who values it | Is it paid in the game's own currency? |
|---|---|---|
| Zennit's week off | Zennit, and the group's pride in earning it | **A promise.** The addon cannot stop anyone summoning him; it files the summons as filler ("not hopeful") and the group keeps the bargain |
| Winning a week, then the season finale | The group | Yes: the next chapter, the keepsake, the titles (`Week.lua`, `Ledger.lua`) |
| Silver | Everyone, and the only value that exists outside the addon | Yes, and real: it goes on the tab and is paid in the game (the Economy entry) |
| A summon's points | Nobody for their own sake | **They are stakes, not wealth.** They cannot be saved or spent, they stand only inside one week, and a week stores nothing but its winner |
| The place of a summon (1, 3, 5, 10) | The caster, if they can see it | Only as a lever on those stakes (below) |
| Badges and titles | The caster, a little | Recognition: the Reward entry found that this group does not play for it |

**Findings**
1. **The things that matter are all outside the points.** A week off, a chapter, silver and a laugh are what the group wants; the
   points are only how the race is kept. That is how it should be for this group (they hate bookkeeping), and there is no hoard to
   inflate: nothing carries over from one week to the next except the wins.
2. **A place's worth is a stake, and it is invisible when the choice is made.** A summons worth P pays the group P if he accepts, pays
   Zennit P if he wins the roll, and takes P from him if he refuses. So a dearer place raises the stakes on *both* sides; it does not
   just pay more. By the simulation (five summons of one kind, two helpers, `skill.py`): five cities win 15 to 23% of weeks (his
   head start of 2 is large against 1-point summons), but zone, dungeon and far-flung all win about 52 to 63%, since the ratio, not
   the size, decides, and above a city the head start no longer matters. The place matters most through the *mix* and the *order*
   (the Skill entry: his dice go on the first summons, so put the dear ones after them).
3. **The briefing does not say what this place is worth.** `Week.Briefing` names the count, the lead, his dice and the helpers, but not
   the worth of where the caster is standing, which is the one thing they are about to decide. The worth appears only after the cast
   ("+3, zone") and on the rules card. A group that wants to play the order has to remember the table.
4. **The table is a guess.** Six cities, ten far-flung zones and thirteen dungeon entrances are from memory and have never been
   checked in the game; everything else is a zone (3). A far-flung place missing from the table scores 3, quietly, and nobody is told.
   `/sc where` shows the kind of the place you stand in, but nothing asks anyone to use it.

**Proposed changes**

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **Say the worth of the place in the ritual briefing**, in the Index's voice and with what is at stake: "From here (a far-flung place) the summons is worth 10: his roll could take 10, and so could yours." A city says it is worth 1 and that his head start is bigger | 3 | The briefing takes the map and subzone (the detector already has them); one test |
| B | **Check the place table in the playtest script**: stand in each far-flung zone and dungeon entrance you pass, run `/sc where`, and note any that read "zone". `design/playtest.md` says how and what to fix | 4 | A paragraph |
| C | **Leave the numbers alone** (1, 3, 5, 10): the stakes are doing their job, and a rebalance without a real week is a guess | 1, 2 | Nothing; recorded as a decision |

**Our answer (built: A, with B as a lookup, and C)**
- **A.** The ritual briefing on Zennit now says what the place is worth and what rides on it, with both sides named (the answer to the
  question below): "From here (a far-flung place) the summons is worth 10: his roll could take 10, and so could yours." A second wording
  says the same ("The Index values this place (a zone) at 3: that is 3 on his roll, or 3 on yours."). In a city it says it is worth less
  than his head start of 2 and that "the Index would not call that a plan." Nothing is said when the place is unknown.
- **B, as asked ("we should be able to look this up").** Instead of a manual checklist, **`/sc places`** prints what a place is worth and
  asks the game for the name of every map ID in the table (`C_Map.GetMapInfo`). A city or far-flung ID the client does not know, or
  names differently, is flagged as a guess to fix. Dungeon entrances are matched by subzone text, which the game cannot look up, so
  those stay a `/sc where` job. The smoke test in `design/playtest.md` now starts with it.
- **C.** The numbers (1, 3, 5, 10) are unchanged.

**Decided:** the briefing names both sides of the stakes; the place table is checked by the game, not by memory; no rebalance before a
real week.

**To watch in playtests**
- Does the group choose where to summon, or only whom? (If they do not, A is only noise.)
- Does anyone say "that should have been worth more"? That is a table entry to fix.
- Does `/sc places` flag anything? (It has never run in the live client, and neither has the lookup it relies on.)

### 2026-10-05 · Lens of Cooperation, with Competition: one team, or a list of people?

**The questions (paraphrased):** who is cooperating with whom, and who is competing with whom? Does the game make people need each other,
and can they talk enough to cooperate? Where a team contains a ranking, do the two pull the same way?

**The layers, as built**

| Layer | Who | What decides it |
|---|---|---|
| Team against the opponent | The group against Zennit, who is also a friend | The weekly race and the season (`Week.lua`) |
| Cooperation inside the team | A caster and two helpers on each summons | The helpers' +5 each to the roll (two at most), and what they are credited with |
| Competition inside the team | The casters, with each other | The Party tab's ranking, the Heaviest Hand title, the badges |
| Opposition by agreement | Zennit | His four answers; nobody else sees his dice until he rolls |

**Findings**
1. **The team layer works, and it is mostly built into the game.** The ritual itself needs two other people to click, so the helpers are
   always there, and the helpers' +5 is nearly always +10. Cooperation here is not a decision the rules make for the group; it is
   what warlocks and their friends do anyway, and the addon only notices it (the Lucky Pair, the Best Supporting Role).
2. **The ranking counts something the race does not.** The Party tab sorts by *all-time points of every summons a caster has
   landed* (`Store.Tallies`): summons of anyone, from before 5 October, with no cap. The race counts only summons of Zennit, ten a
   week. So the one list everyone looks at says nothing about who is carrying *this* race. The nearest thing is the Heaviest Hand
   title (summons of him, by count) in `/sc titles`, which is a different place and a different number.
3. **The one real pull in two directions is the order.** The Skill entry found that a good week puts the cheap summons first, where
   his dice are spent, and the dear ones after. A caster who takes the cheap slot for the team earns the fewest points on the Party
   tab, and no far-flung badge. The Heaviest Hand counts summons, not points, so that title is not hurt, but the Party tab's ranking is.
   This only bites a group with two or more warlocks, and the group has not said how many it has.
4. **What the plan needs is seen by the caster only.** After an answer, every client prints where the week stands. But the briefing
   (his dice left, what the place is worth, the last call) prints on the caster's client alone, as the ritual starts. The people
   who would plan the order, "you take the cheap one, then I go to Silithus", do it in voice chat from memory unless each runs
   `/sc week`.

**Proposed changes**

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **Count the race on the Party tab**: a column "Of Zennit" (summons of him cast this season) beside Cast and Points, and sort by it, so the list ranks what the race counts and the cheap slot is not last | 2, 3 | One column on the tab, one count in `Store.Tallies`, one test |
| B | **A way to say the week to the group**: `/sc week say` sends the "Week:" line (the lead, his dice left, the last call) to party chat, so the plan starts from one shared line | 4 | One argument; it uses `SendChatMessage`, which has never been tried under the 12.0 chat rules |
| C | **Do nothing about the order**: it is a good tension (a friend takes the cheap slot for the team, and that is a story), and the group may have one warlock | 3 | Nothing; recorded as a decision |

**Our answer (built: A and B; C is the decision on the order)**
- **Warlocks:** two or more (the answer to the question above), so the cheap-slot tension is real and A is worth having.
- **A.** The Party tab's Tally has an **Of Zennit** column, the summons of him each person has cast this season, and is ranked by it,
  then by points, then by name. `/sc tally` prints the same list with "(N of Zennit this season)". The count is the Ledger's
  season facts, so it follows the season and the same names the titles use (`Store.Ranked`).
- **B.** `/sc week say` sends the "Week:" line (the lead, his dice left, the last call) to party or raid chat as "Summon Core: Week: ...".
  Anyone can run it; it says why when it cannot (not in a group, the old rules, or the game refusing the message). It uses
  `SendChatMessage`, which has never been tried in the live client under the 12.0 chat rules, so it is the first thing to try there.
- **C.** The order is left to the group: nobody is made to take the cheap slot, and nothing advises them (the Skill entry: the best
  order depends on how he rolls).

**Decided:** the Party tab ranks by what the race counts; the group can say the week to itself in one command; the cheap-slot
trade stays a thing friends do for each other.

**To watch in playtests**
- Does anyone say "I'll take the cheap one"? That is the cooperation working, and a line for the Index to quote.
- Does anyone run `/sc week` before a cast, or ask in chat where the week stands?
- Does `/sc week say` actually send? If the game blocks it, it says so in chat and the line is still on `/sc week`.
- Nothing here has run in the live client.

### 2026-10-05 · Lens of the Toy: is it nice to play with, before the goals?

**The questions (paraphrased):** if you took away the score, the week and the story, would summoning someone, and answering a summons,
still be pleasant to do? Does it respond when you touch it? Is there something worth doing for its own sake?

**What the toy is.** The goals are the weeks and the season; the *toy* is one cycle: cast the ritual, see what it is worth, hear it,
watch Zennit's answer arrive, read what it did. Most of that is a recorded line, a dice popup and chat text.

**What one summons costs the reader, in chat** (measured on the stub, from the real functions, in a normal mid-season week)

| Moment | Where | Characters |
|---|---|---|
| The briefing as the ritual starts | the caster only | about 335 (about 400 in a week with a whim and a last call) |
| "Summon logged: Zennit in Sentinel Hill (+3, zone)" | the caster | about 50 |
| "Week: the group leads by 1, 1 of 10 filed, 2 dice left." | the caster, straight after | about 80 |
| His answer ("Zennit accepted the summon from Alpha. +3 points.") | everyone | about 75 |
| "Week: ..." again after the answer | everyone | about 80 |
| Sometimes: the last-die line, a badge, a list note | varies | 60 to 120 |

That is about 600 characters, or six wrapped chat lines (at an assumed 110 characters a line), for one summons, on the caster's client;
the others see about three lines. A busy week of ten summons is sixty lines on the caster's chat, and the group plays in raids and
dungeons where chat is already scrolling.

**Findings**
1. **The toy is the ritual, the popup and the answer; the chat is the bookkeeping.** The group hates bookkeeping. The recorded lines
   (his refusal, his dice win, the ritual) and the dice popup are the parts that respond when you touch them; the chat is the part that
   was added to make the rules visible, and it is now most of the text.
2. **The longest line arrives at the worst moment.** The briefing prints as the cast begins, when the caster is channelling and
   watching the helpers, and it is the longest line of the cycle. Most of it is the same every time: "each helper adds +5 to your roll
   if he suggests dice (two helpers at most)" is true in week one and still printed on the tenth summons of the week.
3. **Two Week lines per summons, nearly the same.** One prints straight after "Summon logged", the next after his answer. The first
   repeats the standing the briefing gave a few seconds earlier; only the second changes (the answer moves the points).
4. **What works as a toy:** the answer lines are pooled and in the Index's voice; the popup is a real choice; the clips play on the
   best moments. Nothing here needs to be cut, only trimmed.

**Proposed changes**

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **A short briefing after the first of the week**: the first summons of the week keeps the full text (with the helper rule and the whim), later ones say only what changed: "Summon 4 of 10, Zennit leads by 2, 2 dice left. From here (a zone) worth 3." | 1, 2 | A second form of `Week.Briefing`; its tests |
| B | **Drop the Week line straight after "Summon logged"** when a briefing has just been printed (the answer's line is the one that moves) | 3 | A few lines in `Detector.lua`; the "Week:" test that reads it |
| C | **A chat setting**, `/sc chat short`: only "Summon logged", his answer and the standing after it; the rest on `/sc rules` and `/sc week`. Off by default | 1 | A setting, the print sites, tests |
| D | **Leave it**: the chat is the only place the rules show up, and a new group needs it | | Nothing |

**Our answer (built: A)**
- **A.** The first ritual on Zennit in a week (nothing filed yet) keeps the full briefing: the helper rule, the catch-up and the whim.
  Every later one says only what changes: "Summoning Zennit: summon 4 of 10, Zennit leads by 2, 2 dice left. From here (a zone) the
  summons is worth 3: his roll could take 3, and so could yours." The last call and any earlier summons waiting for his answer still
  appear, since those change. With no dice left it still says he must accept, refuse or ask for the silver. A normal mid-week
  briefing falls from about 335 characters to about 240 (the place line is most of what is left).
- **B, C and D** are left: the second Week line and a chat setting wait for a playtest to say whether the chat is read at all.

**To watch in playtests**
- Does anyone mute or move the addon's chat, or stop reading it? Which lines do they still quote?
- Does the caster read the briefing at all while the ritual is channelling?
- The measurements above are from stubs; the wrapped-line count depends on the player's chat window.

### 2026-10-05 · Lens of Resonance: does it ring true?

**The questions (paraphrased):** what is it about this game that feels real and strong to the people playing it? What in their own
experience does it touch, and where does the game sit at odds with that experience?

**What the group already knows, and the game plays with.** Everyone in a WoW group has asked for a summons, waited for a warlock to
set up the ritual and two friends to click, and then pressed Accept on the game's own prompt. That small, slightly absurd ritual
is the real thing the Index files. The paperwork joke has a true centre: the game's prompt really is a form (Accept, Decline).

**Where the build rings true:** the ritual is detected for real (verified live), the clips play at the real moments, the Index's
voice borrows the prompt's own bureaucratic tone, and the contest is about a real friend's real choices.

**Where it sits apart from the real thing**

1. **Two decisions arrive at once, and only one of them is real.** When the ritual completes, the game puts its own summon prompt in
   front of Zennit (Accept or Decline, with a timer). At the same moment the addon opens its own "A SUMMONING!" popup, with four
   answers and the dice (`Respond.Incoming`, from the live `E` message). The addon's answer is a statement in the contest. Whether he
   actually presses Accept on the game's prompt is a separate act that the addon never sees: nothing hooks `CONFIRM_SUMMON`, and the
   README parks it ("a notice when a summon is declined in game"). So he can say "accepted" in the Index and decline in the game, or
   the reverse, and the log cannot tell the difference.
2. **The two popups sit in nearly the same place.** The addon's dialog is anchored at the top of the screen, 140 pixels down
   (`Respond.lua`, `buildDialog`). From memory, the game's own prompt is anchored at the top, about 135 pixels down. If that is right,
   one covers the other at the one moment both matter. This is an inference from the default layout, not something seen in the
   client, so it is the first thing to look at in the game.
3. **The most resonant fact, did he actually arrive, is the least visible.** The contest is about whether Zennit came when called. The
   addon only knows what he said. A summons he accepted in the Index and did not actually take would be the funniest line the Index
   could file ("accepted, and is still in Ironforge"), and the information is available on his client: where he is after the answer,
   against where the summons was to (`ev.mapID`).

**Proposed changes**

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **Move the Index's popup off the game's prompt** (lower on the screen), and head it as the Index's form so the two are not confused | 2 | A position and a title; seen in the game to confirm |
| B | **The Index notes whether he arrived**: after an accepted (or unanswered) summons, his client checks for two minutes whether he is in the summons' map, and says so on his client: "The Index confirms that you arrived in Silithus, 40 seconds after you accepted." or "The Index notes that you accepted and are still in Ironforge." Banter only: it never changes a score | 1, 3 | A timer on his client, a map comparison and a test; a wrong "still in Ironforge" is possible when the arrival lands in another sub-map |
| C | **Tell the group too**: the same note sent with his answer so the group sees "accepted, and has not arrived". Needs a protocol bit and a resend after the answer | 3 | Sync format change (a new flag on the response); wait until B has run in the game |
| D | **Leave the two decisions independent**: the Index's paperwork and the game's prompt are two forms for one event, which is the joke | 1 | Nothing |

**Our answer.** Asked "why are we prompting him if he has arrived? surely we can detect this?", the design changed: instead of a note
about arrival (B and C), **what he really does at the game's prompt is his answer**, with the Index's form as the fallback.
- **He accepts in the game:** the Index records "accepted" and the form is done. (The silver ask belongs before he presses Accept.)
- **He declines in the game:** a new answer, **"declined"**: the summons did not happen, so no points for the caster and none for him.
  It is not a refusal, so a real-life decline (away, in combat) costs him nothing.
- **A writ turns a decline into a cost** (the group's idea: "a wild card, only a few times a week"). The group has two writs a week.
  `/sc writ` before the ritual arms one; his popup tells him before he decides; if he declines that summons it is a refusal and costs
  him its points (his list does not excuse it). If he accepts, the writ is spent anyway (and the group scores as it would have).
- **Nothing seen:** the form works as before, and an unanswered summons still counts as accepted.
- **How it listens:** the game's own buttons call `C_SummonInfo.ConfirmSummon` and `CancelSummon`; the addon hooks them (it does
  not change them) and matches the most recent summons of him still waiting, within the two minutes the prompt lasts, by the
  summoner's name when the game gives it. This is the part never run in the live client: where the functions are missing, or the
  client hides the name, it falls back as above.
- **Protocol:** a record with a writ has an 11th field, and "declined" is a new answer, so this is **0.20.0**; a friend on 0.19 is
  told once and cannot read those records.
- **Left:** A (moving the form off the game's prompt) needs a look in the game first; B and C are replaced by the above.

**Decided:** the real prompt answers; his first decline of a week costs nothing (a real-life exit), a later one and any on a writ
cost him the points (see the Balance entry, which found that unlimited free declines were a dominant move).

**To watch in playtests**
- Do the two popups cover each other on his screen? Does he miss one of them?
- Does he accept in the Index and decline in the game, or the reverse, and does anyone notice?
- Nothing here has run in the live client.

### 2026-10-05 · Lens of Balance: is any choice always the best?

**The questions (paraphrased):** are there choices that are simply better than the others whatever else is going on (a *dominant
strategy*), so that the other choices are never worth making? If so, the game has stopped being a game at that point: players find the
dominant choice and the others become traps. Do both sides have a real chance? Does the balance shift as people learn?

**How to use it:** list every choice a player has at a moment, work out what each one does to the score, and ask whether one of them is
at least as good as the rest in every case. A quick way is to simulate the week with each policy and compare how often each side wins.

**The choice under test: what Zennit can do with a summons, after the change in the Resonance entry**

| His choice | The group gets | He gets | Cost to him |
|---|---|---|---|
| Accept | + P | 0 (or + P on his list) | The group scores |
| Refuse, in the Index | 0 | - P | P points |
| **Decline, in the game (no writ)** | **0** | **0** | **Nothing** |
| Decline a summons with a writ | 0 | - P | P points |
| Dice (3 a week) | + P if he loses, 0 if he wins | + P if he wins | A coin toss |

**Findings** (simulated: five summons, two helpers, his +10 edge, a head start of 2; the numbers are the group's chance to win the
week; `decline.py` and `decline2.py` in the scratchpad)
1. **A free decline is a dominant move.** It does what a refusal does to the group (nothing scored) and costs him nothing, where the
   refusal costs him P. Pressing Decline in the game is better than "Refuse" in the Index every time, so the Index's Refuse is now a
   trap. If he declines everything and no writ is played, the group wins **0%** of weeks (his head start of 2 beats a score of 0). The
   old rules, with him rolling his dice on the first three summons, gave the group **63%** in a five-summons week.
2. **Each free decline he is allowed takes about 10 to 20 points off the group's chance.** Five zone summons, 63% with none; with one
   free decline a week, about 43%; with two, about 34%; with three, about 23%. A mixed week of [3, 3, 3, 10, 10] goes 91%, 56%, 38%.
   One a week is close to the middle of what the earlier lenses aimed for.
3. **A writ is not a gamble for the group.** If he declines, he loses P; if he accepts, the group scores P, which is what it would have
   scored without the writ. It costs nothing but one of only two a week, so the group should always play both, and the only decision is
   *which* summons. That matters: on the dear summons it is strong (mixed week, two free declines: the group's chance goes from 33% to
   91% with two writs on the 10s); on the cheap ones it barely moves anything. The earlier README and lens text called a writ "a gamble":
   that was wrong.
4. **The fiction.** The Index is a place where the target is summoned and goes. A rule that pays him most for never turning up pulls
   against that, even if no friend would play it that way.

**Proposed changes**

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **A limited number of free declines a week: one.** A decline with no writ is "declined" (no points either way) for his first one of the week; every later one costs him P, as a refusal does. A decline of a writ summons always costs him. It is counted from the log, like the writs | 1, 2 | `Week.RULES.declines = 1`, a count in the answer, a line saying how many he has left, and a test |
| B | **Say how many free declines he has left** in his popup and in the "Week:" line, as with his dice, so it is a visible resource | 2 | A phrase in two places |
| C | **Correct the wording on writs** ("the writ is spent either way", not "a gamble") in the README, the lens entry and the command text | 3 | Wording |
| D | **Leave declines free**, and trust the group to stay friendly | | Nothing; the simulation says he would win every week he chose to |

**Our answer (built: A, B and C; one free decline a week)**
- **A.** `Week.RULES.declines = 1`. His first decline of a week in the game is "declined" (no points either way); every later one,
  and any decline of a summons with a writ, is a refusal and costs him its points. The count comes from the log, like the writs. When it
  costs him the Index says so on his client ("your free decline this week is used, so this one costs you 3 points").
- **B.** His popup says what a decline would do before he decides (free, or costs P, or a writ is on it); his own "Week:" line ends with
  "1 free decline left"; `/sc week` and the rules card say how many he and the group have of each. The group's own lines are not
  longer (the Toy entry: chat is already busy).
- **C.** The writ wording is corrected: it is spent either way, and the group scores the summons as it would have if he accepts.

**Decided:** one free decline a week, the middle of what the simulation gave (about 43% for the group in a five-summons zone week, 56%
in a mixed one, against 63% and 91% on the old rules); two would leave about 34% and 38%.

**To watch in playtests**
- Does he ever press Decline in the game, and how does the group react? That is the real test of this.
- Nothing here has run in the live client.

### 2026-10-05 · Lens of Flow: does the addon stay out of the way?

**The questions (paraphrased):** does the activity have clear goals, direct feedback and a challenge that fits the player's skill? Is
there anything that distracts or interrupts, so the player drops out of what they were doing? Does the player feel in control?

**How to read it.** *Flow* is the state of being absorbed in something: hours go by, the next move is clear, you are neither bored
nor overwhelmed. Games produce it by keeping the goal clear, answering every action at once, matching the difficulty to the player,
and removing anything that pulls them out. For this addon the activity that matters is **playing WoW with friends**; the contest sits on
top of it. So the sharpest form of the question is: *how often does the addon make someone stop playing to do something for it?*

**The inputs, counted** (what a person has to do, beyond playing, for one summons; from `Detector.lua`, `Respond.lua`, `Core.lua`)

| Path | The caster | Zennit | Waits |
|---|---|---|---|
| An ordinary summons, he accepts | none (the ritual is the input) | the game's own Accept; the Index records it | none |
| He declines (free, or costing) | none | the game's own Decline | none |
| He asks for silver | none | a click, then a small box with the usual price and OK: about 2 to 3 | none |
| **Dice** | **one click** (the Roll button in the prompt) | **two clicks** ("Suggest dice", then "Roll 1-100", which only confirms) | up to 90 seconds |
| **A writ** | **typed `/sc writ` before the cast** | none (it is on his popup) | none |
| The assistants prompt | one click, only when the roster is unclear | none | none |

**Findings**
1. **The ordinary path needs nothing from anyone beyond what they would do anyway.** Since the game's own prompt became the answer,
   a plain summons costs the caster and Zennit no extra input at all. For the loop that happens most often, that is the best
   possible result for flow.
2. **Dice is the one real interruption: three clicks and a wait across two people.** Zennit clicks twice; the caster, who has just
   finished a ritual and may be back in a fight, has to click Roll; and the whole thing has a 90-second timer. The second of Zennit's
   clicks (the "Roll 1-100" confirm) exists to stop an accident spending one of his three dice, which is a fair reason.
3. **The writ is a typed command before the cast.** In a dungeon or a fight, typing `/sc writ` is a break in play, and if it is
   forgotten there is no taking it back: the ritual has started. It is rare (two a week), so the cost is small, but it is the one
   chore that falls on the whole group rather than on Zennit.
4. **The dice and the game's prompt run on separate clocks.** The game's prompt lasts about two minutes and the dice can take up to ninety
   seconds on top of a few clicks, so the two can overlap. In the code, while a roll is in flight the game's Accept or Decline is
   deliberately ignored (`Respond.Real` skips a summons with a roll pending), and the dice decide it later. So he can accept in the
   game and then "win the dice" so that it does not count. It is an honour-system joke today, but it is also two answers to one summons.
5. **Feedback is quick where it matters.** An accept or decline reaches everyone within a couple of seconds by sync, and the answer
   lines arrive straight after (the Toy entry covers the volume). A challenge that fits: the catch-up edge and the one free decline
   keep a week close, and the group's skill (ordering, which summons gets a writ) has room to grow.

**Proposed changes**

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **One-click dice**: "Suggest dice" rolls at once; the rules move to the button's own text and the line above it. Drops the confirm click | 2 | A little code; an accidental click now spends a die (he has three) |
| B | **A key binding for the writ** (`Bindings.xml`: "Summon Core: play a writ"), so arming it is one key, and the briefing already says whether one is armed | 3 | A bindings file and a global function the game calls; never tried in the client |
| C | **Let the game's prompt end the dice**: if he accepts or declines in the game while a roll is in flight, that is his answer and the dice are cancelled (no die spent). One answer per summons | 4 | A few lines in `Respond.Real`; a test. Open: whether the game also "declines" when the prompt merely expires, which would then end a roll that is still going |
| D | **Leave it**: dice are three a week and writs two, and each chore protects something scarce | | Nothing |

**Our answer (built: A, B and C)**
- **A.** The dice button is now "Roll the dice (1-100)" and rolls at once. The rules (his edge, the helpers' bonus, "a tie goes to
  you", "if you win the summon does not count") are said on the waiting screen after the roll. A mis-click now spends one of his
  three dice, which is the price of one click fewer.
- **B.** `Bindings.xml` adds a key binding under Key Bindings > AddOns > Summon Core, "Play a writ on your next summons of Zennit",
  which does what `/sc writ` does. The file is also packed by the release workflow. It is the standard form but has never been tried in
  the client, so `/sc writ` stays as it was.
- **C.** What he presses in the game now ends a dice roll in flight: his answer is the game's, the roll is dropped, a roll that comes
  back late is ignored, and no die is spent. One answer per summons. Open: if the game also "declines" when the prompt merely
  expires, that would end a roll that is still going, and cost him his free decline; to be seen in the game.

**Decided:** the game's prompt is final; the chores that remain (a roll, a writ) are one click or one key.

**To watch in playtests**
- Does anyone forget to arm a writ, or ask how? Does Zennit use dice at all, now that a free decline exists?
- Does a dice roll ever outlast the game's prompt?
- Nothing here has run in the live client.

### 2026-10-05 · Lens of Accessibility: a friend installs it mid-season

**The questions (paraphrased):** how will a player who has never seen the game know how to begin? Does it look like something they
already know how to play? What do they need to learn before they can take part, and how much of that can wait? Is there anything that
shuts some players out: the way it reads, colour, sound, or the effort to get started?

**How to read it.** Every lens so far has looked at the group that built the game with us. The first live week is also when people
install it for the first time, and a group of friends grows: someone's alt, a partner, a guildie who heard about it. So the player in
question here is **a friend who installs Summon Core in week three** and logs in. The question is what the first hour gives them, in
the order they get it, and whether they can take part without reading the README.

**The first hour, as built** (`Core.lua`, `Intro.lua`, `Week.lua`, `Sync.lua`, `Detector.lua`)

| When | What they see | Notes |
|---|---|---|
| Login | "loaded v0.20.0. /sc for commands." and "New here? Type /sc intro for the story so far." | The only line written for a newcomer |
| +5 s | Their client says hello; anyone with more summons answers, and the log streams in at about 3 a second | Silent until "Sync: received N new summons" |
| +60 s | The week's whim, "The Index closes this week on ...", a tip, and what they owe (nothing, yet) | Written for someone who knows the race |
| `/sc intro` | Ten narrated scenes, **about four minutes**; scenes 9 and 10 are the rules | The rules there predate Resonance and Balance (below) |
| `/sc rules` | Ten lines with this week's numbers | Up to date; nothing points a newcomer to it |
| Their first ritual on Zennit | The **short** briefing: "Summoning Zennit: summon 4 of 10, the group leads by 3, 2 dice left." | The long one is for the week's first summons, not the player's |

**Findings**
1. **Taking part asks almost nothing, and nobody says so.** A helper clicks the portal as they always would; the caster casts; Zennit
   answers in the game's own prompt. No one has to learn a command to play. That is the best possible answer to this lens, and it is
   invisible: the welcome says "the story so far", not "you do not have to do anything".
2. **The one thing a newcomer must do is install it if they cast, and nothing says that.** Only the caster's client sees a ritual
   (`Detector.lua`); everyone else is credited from its snapshot. A warlock without the addon logs nothing, so their summons of Zennit
   do not count. A helper without it loses only their credit. Zennit without it answers nothing, and unanswered summons count as
   accepted. Who needs it, and how much it matters, is written nowhere a player would look.
3. **The welcome points at four minutes of story, and the story's rules are out of date.** Scenes 9 and 10 say he "may refuse", ask for
   silver or roll dice, and close the Index. They do not mention that his answer is now the game's own prompt, that his first decline
   of a week is free and later ones cost, or that the group has two writs. A newcomer who does what the welcome says learns the race
   as it was before 0.20.0. The rules card (`/sc rules`) is current, a minute's read, and not mentioned.
4. **A newcomer's first briefing is the short one.** The long briefing (the helper bonus, the catch-up, the whim, the writ) is given
   for the week's first summons of Zennit. A newcomer's first cast is usually later in the week, so they get "summon 4 of 10, the group
   leads by 3, 2 dice left", which assumes they know what a summons counts for and what the dice are.
5. **The vocabulary is the Index's, and it is small.** To follow the chat a player needs about eight words: the Index, filed, filler,
   a writ, his list, closing the Index, the whim, the week off. Each is explained in the rules card or the line that uses it, and the
   theme is the fun of it (Unification). Nothing to change, but it is why the rules card matters to a newcomer.
6. **Reading, colour and sound hold up.** The answers are words as well as colours (accepted, refused, paid, won), so red against green
   is never the only signal; the band labels its meters ZENNIT and GROUP rather than relying on pink and cyan; the intro types its
   narration on screen as it plays, so it works with the sound off; sound has a switch. The one doubt is the VT323 pixel font at 18 px
   in the window, which may be hard going on a small or high-DPI screen. It has never been seen in the client.

**Proposed changes** (none built yet)

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **A newcomer's welcome**: the first login replaces "New here?" with three lines: you do not have to do anything (cast and click as usual; your summons of Zennit count for the group); `/sc rules` is the race in a minute; `/sc intro` is the story | 1, 3 | Wording; the `introSeen` flag already marks a first login |
| B | **Say who needs it**: the welcome, the README's Install, and the rules card say a caster must run the addon for their summons to count, and Zennit for his answers to be his | 2 | Wording |
| C | **A newcomer's first briefing in full**: the long briefing for a caster's first summons of Zennit ever, as well as the week's first | 4 | A flag and a test |
| D | **Bring the intro's rules up to date**: re-word scenes 9 and 10 for the game's prompt, the free decline and the writs, and re-render them | 3 | Wording now; the audio needs the Windows narrator tools (`tools/intro`), as Elegance's re-wording did |
| E | **Who in the group is missing it**: the Sync tab lists the group's members whose client has not said hello, warlocks first | 2 | Remembering who said hello; a roster check; a layout to see in the client |
| F | **Leave it**: the group is six friends who can explain it to each other in voice chat | | Nothing |

**Our answer (built: A, B and C).** They are wording and one rule, and they change what a newcomer's first hour says without adding
a surface. D is right but waits on the audio, so its wording can be written now and rendered with the next batch of narration. E is
the strongest fix for finding 2 but adds a list to a tab; it waits, and G (below) may make it less needed.

**Built**
- **A, the welcome** (`Intro.WelcomeLines`). The first login says three lines instead of "New here?": you do not have to do anything
  new (cast and click portals as usual; on Zennit's client, answer in the game's own prompt), who needs the addon, and that `/sc rules`
  is the race in a minute and `/sc intro` the story. `/sc welcome` says it again.
- **B, who needs it**: the welcome's second line, a line at the foot of the rules card, and a paragraph under the README's Install.
- **C, a newcomer's first briefing in full.** The long briefing is now given for the week's first summons of Zennit *or* the caster's
  first ever (`Week.FirstCast`: no summons of him in the log with them as the caster). It reads the log rather than keeping a flag,
  so a newcomer whose log has synced from the group is still a newcomer until they cast.
- **Live checks** (step 6): `s-welcome` (marks itself at a first login) and `d-firstbrief`; self-tests for both and the rules card.

**G, when the warlock does not have it (asked after the entry; not built).** Zennit's client sees the summons even when the caster's
does not: the game puts its prompt in front of him (`CONFIRM_SUMMON`) whoever cast it. So his client could log the summons itself when
no record of it arrives from a caster within a few seconds:

| What | Can his client know it? |
|---|---|
| That a summons happened, and when | **Yes**: the prompt is the summons |
| Who cast it | **Usually**: `GetSummonConfirmSummoner` names them, if the client does not hide it (`d-name` will tell us). If hidden, a warlock in his group is a good guess, and the only one when there is one |
| Where to | **Yes if he accepts**: once there, his own map and subzone score it exactly as the caster's client would. If he declines, only the prompt's area name (`GetSummonConfirmAreaName`), matched by name; a free decline scores nothing anyway |
| His answer | **Yes**: the same hooks as now |
| The helpers | **No, not reliably.** On arrival he can see who in his group is near him, but that is everyone standing at the stone, not the two who clicked, and helpers may have walked off. A helper's own client might see its own click on the portal; that is untested |

The cost: a record from his client has to give way to the caster's if both arrive (a few seconds' wait, then a merge rule in sync), a
writ cannot be played without the caster's addon, and the summons would be credited to the caster with no helpers. It is a gap worth
closing only if a warlock in the group does not install it.

**G, built (0.21.0).** And a helper with the addon does help: the caster's client already finds helpers by asking who in the group is
channeling the ritual (`UnitChannelInfo`, which works in this client), so any other client in the group can do the same.
- **The witness** (`Detector.lua`). A client that is not casting watches its group: the first to channel a ritual is the caster, their
  target is the one being summoned, and anyone who starts after is a helper; if this client clicks the portal itself, it is a helper
  too and its own place is the stone's. When the caster stops it sends a note (`W`) to the party or raid, for rituals on Zennit only.
- **Zennit's client files it** (`Respond.FileWitnessed`). When he presses Accept or Decline and no record of the summons has
  arrived, it looks again in five seconds; then it files one: the caster from the prompt, else a note, else the only warlock in his
  group, else "Unknown"; the helpers only from notes; the place from where he arrives if he accepted, else a helper's note, else the
  prompt's area name. The answer is recorded on it as on any other. The record carries a 12th field naming him, its id starts with
  his name, and sync accepts it only from him and only for a summons of himself.
- **If the caster's record turns up after all** (`Respond.Adopt`), his client moves the answer to it and deletes the one it filed.
- **Not covered:** a prompt he never answers files nothing; no writ without the caster's addon. Protocol: older clients cannot read
  the 12-field record, hence 0.21.0, and the version notice says so.
- **Live check** `d-witness` (marks itself), and four self-tests: the record and its rules in sync, the note, who is credited, and the
  file-then-adopt round trip.

**To watch in playtests**
- When someone new joins, what do they ask first? Did they read the rules card, watch the intro, or ask in voice?
- Does a summons ever go unlogged because the caster did not have the addon?
- Is the window readable for everyone at its size, on their screens?

### 2026-10-05 · Lens of Simplicity/Complexity: twenty-odd rules, and three ways to say no

**The questions (paraphrased):** what in the game is *innate* complexity (rules a player has to be told) and what is *emergent*
(interesting situations that grow out of a few rules)? Where does a rule add work without adding a decision? Is the complexity where
the fun is, or somewhere else? Are there rules that only make sense together, or that quietly undo each other?

**Why now.** Elegance took stock on 4 October with "a dozen or so" rules. Since then Resonance, Balance, Flow and Accessibility added
the game's own prompt as his answer, writs, the free decline, late answers, a provisional result, the silver tab and cards, the last
call and a summons filed from his side. Each was argued for on its own; this lens looks at them together.

**The innate rules, counted** (`Week.lua`, `Respond.lua`, `Store.lua`, the rules card)

| Group | Rules | Count |
|---|---|---|
| What counts | Only summons of him; points by place (four kinds); a cap of 10; he may close after 5; unanswered counts as accepted; late answers for two days, and the result is provisional until then | 6 |
| The score | Head start of 2; a tie is his; his list (five places, four letters) earns him the points | 3 |
| The dice | Three a week; his edge of +10; helpers +5 each, two at most; the catch-up; the whim | 5 |
| Saying no | Refuse costs the points; a refusal on his list is free; the first decline in the game is free; later declines cost; two writs a week make a decline cost | 5 |
| Money | Silver goes on a tab (he names the price); cards prepay it | 2 |
| The season | Five wins; his week off is filler | 2 |
| | | **23** |

The rules card says them in eleven lines, and that is about as small as they go. Emergent complexity, the part this lens wants more
of, comes from four of them: **the dice** (when to roll), **the writs** (which summons to put one on), **the close** (when to shut the
week) and **the order of summons** (Cooperation). Those are the decisions players talk about. Most of the rest are scoring detail
nobody chooses.

**Findings**
1. **Five of the 23 rules are about saying no, and they disagree with each other.** He can say no in two places: the game's own
   prompt (Decline) and the Index's form (Refuse). The two follow different rules (`Respond.Real` against the form's Refuse button):

   | He says no... | No writ, free decline left | No writ, none left | With a writ |
   |---|---|---|---|
   | **In the game**, an ordinary place | free (declined) | costs P (refused) | costs P |
   | **In the game**, a place on his list | free | **costs P** | costs P |
   | **On the form**, an ordinary place | **costs P** | costs P | costs P |
   | **On the form**, a place on his list | free (excused) | free | **free** |

   Three cells are wrong by the game's own words. The rules card says refusing at a place on his list is free, but a second decline
   in the game there costs P. It also says a writ makes a decline cost, but Refuse on the form at a list place ignores the writ, which
   gives him **a way round a writ**. And Refuse on the form at an ordinary place is never better than the game's Decline: it is a
   button that can only hurt him.
2. **Two surfaces for one decision.** Since Resonance, the game's prompt *is* the answer, and the form's Accept and Refuse are there for
   late answers (the prompt lasts two minutes, and an answer is taken for two days). That is a good reason for the buttons, but not
   for their following different rules. One rule, used by both, removes a row from everyone's head.
3. **Three words for no.** The log, the chat lines and the report show "refused", "declined" and "refused (on his list)". To a player
   these are one thing, "he said no", which either cost him or did not. The difference that matters is the cost, and that is what the
   line should say.
4. **The head start is still dead weight** (Elegance B, not chosen then): it moves a normal week by about a point and is in the rules
   card, the band and the briefing. It is innate complexity that buys no decision. It stays out of scope unless the group asks; noted
   here because this lens is the one that would cut it.
5. **The new rules from the last few lenses are cheap.** A writ is one choice with one effect; the free decline is a counter of one;
   the filed summons and late answers need no one to learn anything. Most of the complexity added since Elegance sits where it should:
   in the choices.

**Proposed changes** (none built yet)

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **One rule for no** (`Week.NoCost`): any no, in the game or on the form, is free if a free decline is left or the place is on his list, and costs the points otherwise; **a writ always costs**. The form's button becomes **Decline** and uses it | 1, 2 | A function both paths call; tests; the form's cost line reads from it |
| B | **One word for no** in the lines: "declined (free)" or "declined (cost him 3)", whatever the surface; `refused`/`excused`/`declined` stay as stored values, so old records and other clients still read | 3 | Wording in `Respond.Describe` and the answer lines |
| C | **Drop the head start** for weeks from now on (as Elegance B) | 4 | A constant and some lines; changes the numbers in the Fairness table a little |
| D | **Leave it** | | Nothing |

**Recommendation:** A and B. A closes a real hole (the writ dodge) and makes "saying no" one rule instead of two tables, which is the
largest single cut available. B is wording that follows from it. C is still optional; nothing has changed since it was last turned down.

**Our answer (built: A and B).** C (the head start) stays.

**Built**
- **A, one rule for no** (`Respond.NoResult`). The game's Decline (`Respond.Real`) and the form's button both call it: a writ that
  counts costs him the points, a place on his list is free (and does not spend his free decline), his first decline of the week is
  free, and every other costs. The form's button is now **Decline** ("Decline (free)" when it is), and the line above it says why
  (`Respond.NoText`). The three bad cells are gone: a second decline at a list place is free, a writ costs even at a list place, and
  the form's no is never worse than the game's. The stored results are unchanged (`declined`, `excused`, `refused`), so old records and
  other clients read as before.
- **B, one word for no.** The answer lines, the log (`Respond.Describe`: "declined (free)", "declined (free: his list)", "declined (cost
  him 3)"), the rules card ("Declines: in the game's prompt or on the Index's form..."), the last-die lines and the briefings ("accept,
  decline or ask for the silver") and the help all say *decline*.
- **Live check** `s-decline` (the form's cost line against the rules card), with `d-cost` and `d-writ` reworded; a self-test of the rule
  and the words.

**To watch in playtests**
- Does Zennit ever use the form to say no, or only the game's prompt?
- Can the group say what a no costs him, without the card?

### 2026-10-05 · Lens of Secrets: who knows what, and when

**The questions (paraphrased):** what does each player know that the others do not? What is hidden from everyone? Would the game be
better if something public were hidden, or something hidden were made public? Secrets make guessing, bluffing and surprise; open
information makes planning. The lens asks whether each piece is on the right side of that line.

**What is known, by whom** (`Respond.lua`, `Week.lua`, `Detector.lua`)

| Information | The group | Zennit | When it comes out |
|---|---|---|---|
| The score, the lead, summons filed, his dice left, the whim, his edge with the catch-up | Yes | Yes | Always (the band, the briefing, the rules card) |
| His free declines left | Only by `/sc week` | Yes (his popup and Week line) | Never said at the moment it matters |
| A writ armed for the next ritual | The caster | No | His popup says so **before** he answers |
| **His list** (five places) | **No** | Yes | A place leaks the first time a summons there is answered: "It is on his list", or "declined (free: his list)" |
| How many places are on his list | No | Yes | Never |
| The dice rolls | Yes | Yes | As rolled (`/roll`) |

There is one real secret: **his list**. Everything that decides the dice is open, which suits a race between friends (Fairness).

**Findings**
1. **His list can be changed in the middle of a summons, and that makes every no free.** The list is read when he answers
   (`Respond.OnList`), and he can edit it at any time (`/sc zennit list add`, or the Zennit tab). The prompt and his form both name
   the place. So he can see the place, add it to his list (removing another to stay under five), and decline for free, or accept and
   take the points himself. Either way the summons is worth nothing to the group. Repeated, it gives him unlimited free declines: the
   dominant strategy Balance closed, back through a side door. It takes about ten seconds of typing, so nobody would do it by accident,
   but it is one button away in the Zennit tab, and the secret list exists to give him something to *plan*, not to react with.
2. **The value of a writ depends on two facts, and the group sees neither when it decides.** After Simplicity/Complexity, a decline
   costs him unless it is his free one or the place is on his list, and a writ makes it cost anyway. So a writ only matters while his
   free decline is unspent, or at a place on his list. The briefing offers "/sc writ (2 left) makes a decline of this one cost him"
   on every first summons of a week, whether or not it can bite. One of those two facts is meant to be secret (the list), and guessing
   it is a good game: "is Silithus on his list?". The other (has he spent his free decline?) is public on `/sc week`, but nobody types
   that while channeling.
3. **The secret wears out over a season.** Each place leaks the first time it is answered. A known listed place is dead for the
   group: if he accepts, both sides score P, and if he declines it is free, so it moves the gap by nothing and uses one of the week's
   ten slots. With five places and a few hits a week, the group knows the whole list within two or three weeks unless he changes it.
   Changing it is what keeps the secret alive, so changing it should be a choice he makes at a set time, not something he does with a
   summons on screen (finding 1).
4. **The writ is shown to him before he answers, and that is right.** If a writ were hidden until after his answer, it would turn a
   decline he thought was free into a cost: a gotcha, not a bluff (Griefing). Open, it is a forcing move he can see coming. No change.
5. **The list's size is hidden too.** The group does not know whether he has five places or none. It adds a little to the guessing
   and costs nothing. No change.

**Proposed changes** (none built yet)

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **The list is set for the week**: a place added during a week counts from the next Monday; removing one takes effect at once (that only costs him). The Zennit tab and `/sc zennit list` mark new places "from Monday". A summons is judged against the list as it stood when its week began, so every answer in a week uses the same list | 1, 3 | A time on each entry (old entries count at once), a check in `Respond.OnList` against the summons' week, a test |
| B | **The briefing says whether a writ can bite**: while his free decline is unspent, as now; once it is spent, "His free decline is used: a writ only bites if this place is on his list." The writ's place in the decision is then the guessing game, and the public half is said where the decision is made | 2 | A clause in `Week.Briefing` |
| C | **Leave it** and trust the friendship: nobody would really edit the list mid-summons | | Nothing; the hole stays one button away |

**Recommendation:** A and B. A closes a dominant strategy and turns changing the list into a weekly decision, which is what keeps the
secret alive. B is one clause that tells the group the half of the writ decision it is allowed to know.

**Our answer (built: A and B), and postcards.** Asked with the answer: the group also needs a reason to go to places like Silithus,
and it should add to the joke. The 10 points are a reason, but with a secret list the far-flung places are the ones he is most
likely to list, so going there is a guess at his secret; the trip itself should leave a mark.

**Built**
- **A, the list is set for the week** (`Respond.ListActive(at)`, `Respond.ListPending`). Each place he adds is stamped with the time;
  a summons is judged against the list as it stood when its week began (`Respond.OnList` passes the summons' time), so a place added
  this week counts from the next Monday. Removing one takes effect at once. Entries from before the rule count as they did. The Zennit
  tab and `/sc zennit list` mark new places "(from Monday)", and the rules card says the list is set for the week.
- **B, when a writ can bite.** Once his free decline is used, the first briefing says "His free decline is used: a writ (/sc writ,
  2 left) only bites if this place is on his list", and an armed writ says the same; the rules card adds it to the writs line.
- **Postcards** (`Ledger.PostcardFor`, `Ledger.POSTCARDS`). The first summons of him to each of the ten far-flung places in a season
  that lands earns the Index a postcard from him, in his words and the Index's voice ("...in Silithus: 'Sand. Also insects. Mostly
  sand.' Stamped: 1 of 10 far-flung places this season."), said on every client when his answer arrives. A decline is not a trip, a
  second trip that season sends none, and a summons that already landed (silver paid later) does not send another. The tenth adds
  "The Index has run out of stamps, and has sent for more." No points: the 10 are the reason to go, the postcard is the joke, and the
  set of ten is a season-long thing to collect. `/sc week`, the rules card and the season's keepsake list them. It is also the world
  tour that was parked, aimed at the far-flung places instead of the capitals (a city is worth 1, so a capital tour would pull against
  the race; the far-flung tour pulls with it).
- **Live checks** `s-list` and `d-postcard` (marks itself); self-tests for the weekly list, the writ clause and the postcards.

**To watch in playtests**
- How often does he change his list, and does the group track which places have leaked?
- Do writs end up on guesses ("Silithus must be on it"), or only on his free decline?

### 2026-10-05 · Lens of Character: who writes Zennit?

**The questions (paraphrased):** who are the characters, and what makes each one interesting? What do they want, and what do they
do about it? Do they speak in their own voice, and is it consistent? Do the players get to shape the characters they play, or only
watch them?

**How to read it.** This game has an unusual character: **Zennit is a real friend playing a version of himself.** The addon draws him
three ways: the story's Licensed Summoning Liaison, Third Class, looking for Form 27B slash 6 (narrated); the Index's lines about what
he did ("Zennit declined the summon from Al, and it cost him"); and, since Secrets, postcards in his own words. The lens asks who
writes each of those, and whether the real Zennit gets a say.

**Who writes Zennit, as built**

| Where he appears | Who wrote it | Whose voice |
|---|---|---|
| The intro and the chapters | Us, narrated by a synthetic voice | The narrator's, about him |
| The answer lines, the briefings, the Week lines | Us | The Index's, about him (third person, by the house style) |
| The postcards | Us (Secrets, a day ago) | **His, in quotes, but written for him** |
| The gags (`gag_zennit.ogg`, `gag_party.ogg`, `gag_party_02.ogg` to `_13`) | His recordings | **His own** |
| The surprise clips when he is summoned (`zenit_land`, `zenit_refuse`, `zenit_win`) | The group, recorded for him | The group's. One clip so far (`Media/clips`), so none of these play |
| The price of the silver | Him, each time | His only written word in the game |

**Findings**
1. **Zennit is written by everyone but him.** His only authored text is a number (the silver price), and his only voice is two gag
   recordings. Everything else about him is our wording. For a game whose premise is teasing a friend, that is a gap: the
   best version of the joke is the one he is in on, and a character he can add to is one he will defend.
2. **The postcards put words in his mouth.** They are in quotes and signed with his name, but he did not write them. They are a
   decent default, and they are exactly the place where his own line would be funnier than ours.
3. **His week off is told entirely by the Index.** When a caster summons him on leave, the Index says it "is not hopeful". That is the
   moment a real person would have an out-of-office reply, and the joke writes itself if he writes it.
4. **The story's Zennit and the game's Zennit agree.** The weary liaison who wants the paperwork to end, and the answer lines ("with
   some dignity"), are one character. Nothing to change. The surprises he hears are the group's lines for him, which is the group's
   character work, and that is right as it is. It is just not recorded yet.
5. **The group is "the party" in the story and named people everywhere else** (titles, moments, helpers). That split works: the
   story is about the Index and him; the play is about the friends.

**Proposed changes** (none built yet)

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **His own postcards**: `/sc zennit postcard <place> <text>` sets what his postcard from that far-flung place says (a line, 80 letters at most); his client sends it to everyone (a new message, only from his characters, like his cards and alts), and every client uses his words instead of ours from then on. Ours stay as the default for places he has not written | 1, 2 | A message type, a store of his lines, a command, a test |
| B | **His out-of-office**: `/sc zennit away <text>` sets a line that a caster sees when summoning him on his week off ("Zennit's out-of-office: '...'"), in place of the Index's "not hopeful". Sent the same way as A | 1, 3 | The same mechanism, one more key |
| C | **A recording evening** for the three empty surprise categories (`zenit_land`, `zenit_refuse`, `zenit_win`), from `design/recording-sheet.md` | 4 | No code; the group's time |
| D | **Leave it**: we write him, and he reacts in voice chat | | Nothing |

**Recommendation:** A and B, built on one mechanism (his short lines, sent from his client like his alts). They give him two places
to write his own character, at the two moments the joke is about him: where he was dragged, and where he went on leave. C is worth
doing whenever the group has an evening; it needs no code.

**Our answer (built: A and B).** C waits for an evening.

**Built**
- **His lines** (`Sync.SetLine`, `Sync.ZennitLine`, message `L`). A short line he writes (80 letters at most, escape codes taken out)
  is kept on his client and sent to the group with a time; every client keeps the newest. Only his characters may send one, and only
  for a key he may write: a postcard for one of the ten far-flung places (`pc:<mapID>`), or `away`. His client sends them all again with
  his hello, so a friend who was offline catches up.
- **A, his postcards.** `/sc zennit postcard Silithus: <line>` (a prefix of the place will do); `clear` puts ours back.
  `Ledger.PostcardFor` uses his words when he has written them. Anyone can read them with `/sc zennit postcard`; only he can write.
- **B, his out-of-office.** `/sc zennit away <line>`: the briefing for a summons of him on his week off says "His out-of-office says:
  '...'" in place of the Index's "not hopeful". The line after logging the summons stays the Index's, so it is said once.
- **Live check** `d-lines`; a self-test of sending, the sender rule, the newest-wins rule, a bad key, and both uses.

**To watch in playtests**
- Does he write any? Are his funnier than ours?
- Does the group ask for lines of their own (a caster's signature on a summons)?

### 2026-10-05 · Lens of Inner Contradiction: his prize is a week of not playing

**The questions (paraphrased):** what is the game for, and does anything in it pull against that? Do the goals of the players, the
rules and the story agree? Where they disagree, is the disagreement the joke (and so worth keeping), or a crack?

**What the game is for.** The group summons Zennit to unreasonable places and he answers, in a race and a story kept by a deadpan
Index. Every summons of him is the game happening.

**Contradictions, sorted** (the code and the rules as of 0.21.0)

| | Says | Does | Verdict |
|---|---|---|---|
| 1 | "The Index takes no sides" | The catch-up and the whim lean on the dice | **The joke.** It says so with a straight face (`design/voice.md`) |
| 2 | His list: places he would like to go | He scores there if he goes, and declines there for free | **Fine.** It is his ground; Secrets fixed the way he could move it |
| 3 | A declined summons "did not happen" | A writ still charges him for it | **Fine.** A writ is paperwork served on him; the line says "it cost him" |
| 4 | Far-flung places earn postcards | His list makes the same places the riskiest | **Wanted.** It is the guessing game (Secrets) |
| 5 | His answer is the game's prompt (Resonance) | A prompt that runs out counts as accepted, though he did not go | **A crack, known** (`d-expire`, Risk Mitigation). Waits on what the game does |
| 6 | **Winning a week is his prize** | **The prize is a week in which summoning him does nothing** | **A crack.** Below |

**Findings**
1. **His prize is a week of not playing, for everyone.** When Zennit wins a week, the next is his week off: summons of him are filler,
   nobody can win it, and the briefing tells a caster "it will not count, and it is not hopeful". In the fiction that is exactly right:
   he wanted to be left alone. In play, the winner's reward removes the game for him *and* for the group. If he wins a little over half
   of the decided weeks (Balance's numbers), about **a third of all weeks** are weeks off (a win is followed by an off week, so the share
   is z / (1 + z) with z about 0.55). That is a lot of the season with the race switched off.
2. **The off week is not actually empty, and nothing says so.** Summons of him in his week off still go in the log, so they still earn
   **postcards** (a far-flung place still lands), still count toward the **titles** (the heaviest hand, the best supporting role) and the
   **keepsake**, and he still answers them (dice and silver included). The only thing switched off is the weekly race. But the one line
   the caster reads says it "will not count", which reads as "do not bother".
3. **What a summons on his leave *means* has no name.** The race has "filed", "enthusiasm" and "filler". A summons of a man on leave is
   the most on-premise thing in the game (the story's chapter 2 is about the party standing in a circle saying his name while he is
   away) and the Index files it as "filler".

**Proposed changes** (none built yet)

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **Say what still counts on his leave.** The briefing and the logged line on his week off say: it will not count for the race, but a far-flung place still earns a postcard and the titles still see it. His out-of-office (Character) stays where it is | 2 | Wording in `Week.Briefing` and `Week.Warn` |
| B | **Name it: disturbing his leave.** A summons of him on his week off is filed as "disturbing his leave" (in place of "filler"); the season's keepsake and `/sc week` say how many times his leave was disturbed and who did it most ("The Index notes that Al disturbed his leave four times."). No points; it is the chapter 2 joke made countable | 2, 3 | A count from the log, a line in the keepsake and `/sc week`, a word in the lines |
| C | **Shorten or soften the week off** (a half week, or the race running at half points) | 1 | A rule, and the Interest Curve's numbers move; turned down there once already |
| D | **Leave it** | | Nothing |

**Recommendation:** A and B. They do not change the race (the Interest Curve chose a real week off on purpose, and C would reopen that),
but they turn the third of the season the race is off into its own small game that is already half there: postcards, titles, and a
running count of how often the group disturbed a man on leave. It also makes his win feel like a win to the group too: something
new to do.

**Our answer (built: A and B).** C stays turned down.

**Built**
- **A, what still counts.** On his week off the briefing says "The Index will file this summons as disturbing his leave: it will not
  count for the race, but a far-flung place still earns a postcard, and the titles still see it" (and his out-of-office, if he has
  written one). The logged line says "filed as disturbing his leave (3 this week): not for the race, but the titles saw it". The rules
  card, the Week line and `/sc writ` say the race is off rather than "filler".
- **B, disturbing his leave.** The word replaces "filler" in the lines, the week's description ("his leave disturbed 3 times") and
  what the Index files it under. `Ledger.Collect` counts summons of him in his weeks off and who cast them; `Ledger.LeaveLine` says
  "The Index notes that his leave was disturbed 6 times; Al did it most (4)." in `/sc week` and the season's keepsake. No points.
- **Not changed:** the narrated "The Index today" line for his week (`Ledger.LINES.week_leave`) still says "filler", because it has
  a recording; it changes with the next batch of narration. The intro's scene 10 is the same.
- **Live check** `d-leave` (marks itself when a summons of him on his leave is logged); a self-test of the lines and the count.

**To watch in playtests**
- Does the group still summon him in his week off? Does the count make them try?
- Does he enjoy the leave, or miss the game?

### 2026-10-05 · Lens of Indirect Control: what the addon nudges the group to do

**The questions (paraphrased):** what do we want the players to do? Which of the game's goals, rewards, interface and characters
nudge them toward it without a rule forcing it? Does each nudge arrive when the decision is made? Do any nudge the wrong way?

**What we want the group to do:** summon him often but not endlessly, to unreasonable places, together, at times that keep the week
alive, and keep it friendly. And Zennit to answer, and enjoy it.

**The nudges, and when each arrives** (the code as of 0.21.x)

| Nudge | Toward | Arrives | When the decision is made | |
|---|---|---|---|---|
| Points by place (city 1, zone 3, dungeon 5, far-flung 10) | Unreasonable places | **At the cast** (the briefing) | **Before travelling** | Late |
| Postcards (Secrets) | All ten far-flung places in a season | When one lands | Before travelling | Late, and nothing says which are missing |
| His list (Secrets) | Guessing, varying places | Never (it is secret) | Before travelling | Right: it is meant to be unseen |
| The cap of 10 and the close | Not spamming him | The briefing, the Week line | At the cast | On time |
| The last call (Time) | Not letting the week drift | At login and the briefing, in the final day | That day | On time |
| "Waiting for his answer" (Community) | Chasing him | The Week line and the briefing | Any time | On time |
| The writ clause (Secrets) | Putting a writ where it bites | The first briefing of a week | At the cast | On time |
| The Monday tip (Interface) | Finding commands | Monday login | Any time | On time |
| **Helpers +5 each, two at most** | **Doing it together** | The first briefing | **Never: see below** | Steers nothing |

**Findings**
1. **The strongest nudges arrive after the decision they are meant to steer.** Where to summon him is decided before anyone travels:
   somebody says "let's get him to Silithus" and the group flies there. The addon first speaks about the place at the cast, when they
   are already standing in it. `/sc places` lists the values, but it is a reference, not a nudge, and nothing at all says which far-flung
   places still lack a postcard this season. The postcards are a collection with no checklist.
2. **The helper bonus does not steer anything.** A Ritual of Summoning needs two party members besides the caster to click the
   portal, so nearly every summons has two helpers and +10 on the roll, which cancels his +10 edge. The group cannot choose more or
   fewer helpers. What does vary is whether the log *credits* them: the assistants prompt asks the caster when the roster is unclear, and
   an uncredited helper is +5 lost. So the bonus's real effect is to make a roll depend on bookkeeping, which this group dislikes (the
   Player). The earlier simulations' "no helpers" rows (Elegance, Fairness) describe weeks that cannot happen. This should be confirmed
   with the playtest report, which already counts "Helpers on a summons: none, one, two".
3. **The working nudges are the timing ones.** The last call, the overdue count, the writ clause and the cap all arrive when the
   decision is being made, and each points one way. Nothing to change.
4. **The city line nudges against the most natural summons**, "The Index would not call that a plan" when a friend just wants him in
   Ironforge with the group. For the race that is right (a city is worth less than his head start), and a city summons does not hurt
   the group in a normal week (the cap is rarely reached). Leave it.

**Proposed changes** (none built yet)

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **Postcards still to collect**: `/sc week` and the Monday login (with the week's clock line) name the far-flung places with no postcard yet this season ("Still no postcard from: Azshara, Felwood and six more. The Index has stamps.") | 1 | A function from the season's postcards and a line in two places |
| B | **Decide the helper bonus from data**: after the first weeks, read the report's helper counts. If almost every summons has two helpers, drop both the bonus and his edge together (the roll is then even, as it is now in practice) and the assistants prompt stops mattering to the score | 2 | Nothing now; a rule change later, with the Fairness numbers recomputed |
| C | **The Index's request of the week**: one far-flung place drawn each week (as the whim is), named on Monday; a postcard from it that week adds "as requested". No points | 1 | A draw and two lines; more surprise than steer |
| D | **Leave it** | | Nothing |

**Recommendation:** A now, B after the playtest. A puts the postcards' checklist where the group plans the evening, which is the
cheapest way to make the place nudge arrive on time. B is the bigger simplification, but it should wait for the log to show how many
helpers a summons really has. C is fun but is a second weekly draw on top of the whim; keep it for later.

**Our answer (built: A; C noted; B after the playtest).**

**Built**
- **A, postcards still to collect** (`Ledger.MissingLine`). `/sc week` ends with every far-flung place that has no postcard yet this
  season ("Still no postcard from: Azshara, Blasted Lands... The Index has stamps."), and the Monday login, right after the week's
  clock, names three and counts the rest. Nothing when all ten are stamped.
- **C, noted** in the README's "Parked for later": the Index's request of the week, one far-flung place drawn weekly, no points.
- **B** waits for the report's helper counts.
- **Live checks:** `s-login` now expects the missing-postcards line, and `d-postcard` the list in `/sc week`; the postcards self-test
  covers both forms of the line.

**To watch in playtests**
- Does the group plan trips from the missing postcards?
- The report's "Helpers on a summons": is it nearly always two?

### 2026-10-05 · Lens of Freedom: when can he step away?

**The questions (paraphrased):** when do the players feel free, and when do they feel boxed in? Are they free in the ways that
matter to them? Is there anywhere they have too much freedom, so the game stops working? A game laid over a real friendship also
asks: is everyone free to just be a person for a while?

**The freedoms, as built**

| Who | Free to | Limited by | Feels |
|---|---|---|---|
| The group | Summon him anywhere, any time he is in their group | The ritual (three people, him in the party or raid), the cap of 10 | Free; the limits are the game's own |
| The group | Choose where to put two writs a week | Two a week | A real choice (Balance, Secrets) |
| Zennit | Accept, decline (one free), silver at his price, dice (three), close the Index after 5 | The one rule for no | Many real choices |
| Zennit | Set his list for next week, write his postcards and out-of-office | Five places, set weekly | His (Character, Secrets) |
| Zennit | **Not be in their group** | Nothing: it is the game's rule that only party members can be summoned | Total, and right: absent weeks have no winner |
| Zennit | **Step away for ten minutes while still in the group** | **Nothing protects it** | Below |

**Findings**
1. **A summons he never answers counts as accepted, so he is not free to step away.** If he is in the group but away from the
   keyboard (dinner, a phone call, the kettle), a summons still arrives, the game's prompt runs out, and the Index records nothing, so
   the summons counts as accepted: the group scores it, and he did not go. Up to ten a week can land this way while he is away. When he
   comes back his late answers (the form, for two days) are all ways of saying no, which the one rule makes cost him the points once
   his free decline is spent, the same as accepting. So in practice, being away during a session is a loss he cannot undo.
   The friends would not farm it on purpose, but it happens by accident every time someone summons him without checking, and the
   game's own words ("unanswered counts as accepted") make it the correct play.
2. **The rule exists for a reason.** "Unanswered counts as accepted" was there so he could not dodge by ignoring the Index's form
   (before Resonance, the form was the only answer). With the game's prompt now his answer, ignoring the prompt is not going, so the old
   reason is weaker, but making silence free would hand him an unlimited free decline again (Balance). So silence cannot simply become
   free.
3. **The game already knows when he is away.** WoW has an AFK flag (`/afk`, or set by itself after a few minutes idle), and other
   clients can see it on a party member. So the caster's client can know before the ritual, and his own client can know when the prompt
   arrives. The risk is the reverse: `/afk` typed the moment a summons starts would be a dodge. It is a visible one, but it is still a
   dodge, so a fix should only honour an AFK that started before the ritual did.
4. **Everything else is free in the right places.** The group's limits are the ritual's; his are the race's; and his biggest
   freedom, not grouping with them, is real life and correctly scores nothing.

**Proposed changes** (none built yet)

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **Away means not home.** If he was already AFK when the ritual began (his AFK flag set before the prompt, by a margin), his client files the summons as **"away"**: it did not happen, it is free, and it does not use his free decline. The caster's briefing warns at the cast when he shows as AFK ("Zennit is away from his keyboard: the Index will file this as away and it will not count"), so the ritual can wait | 1, 3 | A new answer (`away`), his client watching his AFK flag (`PLAYER_FLAGS_CHANGED`, `UnitIsAFK`), a line in the briefing; older clients cannot read the new answer, so a version bump |
| B | **Silence is a decline** under the one rule instead of an accept: free if his free decline is left, otherwise it costs him | 1 | Small; but an away week still costs him, and the group gains nothing for it |
| C | **Leave it**: friends check before they summon | | Nothing; the accident stays the correct play |

**Recommendation:** A. It gives him the one freedom he lacks, stepping away for a few minutes, without making silence a dodge: only
an AFK that began before the ritual counts, and the group is told before they spend a ritual on it. B is simpler but punishes
being away instead of excusing it. Both wait partly on the open `d-expire` check (what the game does when the prompt runs out), and A's
"by a margin" needs a number (five minutes is proposed: the game's own idle AFK starts after five).

**Our answer (built: A, 0.23.0).**

**Built**
- **A new answer, `away`** (`Store.RESULTS`): no points either way, no cost to him, and it does not count as his free decline.
- **His client watches his AFK flag** (`PLAYER_FLAGS_CHANGED`, `UnitIsAFK`) and remembers when it was set. When the game's prompt
  arrives and he has been AFK for five minutes or more (`Respond.AWAY_MARGIN`, the game's own idle time), it waits a few seconds
  and, if he is still AFK and has not answered, files the summons as away (`Respond.FileAway`). An AFK of less than five minutes is not
  honoured, so `/afk` as the ritual starts is not a dodge. With a caster who has no addon, his client files the summons itself (G)
  and records it as away.
- **The caster is warned** at the cast when he shows as AFK (`Detector.IsAway`, `Week.Briefing`): "If he has been away a while, the
  Index will file this summons as away... It may be worth waiting."
- **Lines:** "Zennit was away from his keyboard when the summons from Al came. The Index files it as away: it did not happen, and it
  costs nobody anything." The log says "away from his keyboard (free)"; the report counts it.
- **Version 0.23.0:** older clients refuse the new answer.
- **Live check** `d-away` (marks itself); a self-test of the margin, the free decline untouched, the wire, the briefing, and his
  coming back before the check.
- **Still open:** what the game does when the prompt runs out (`d-expire`); an unanswered summons when he was *not* AFK still counts
  as accepted.

**To watch in playtests**
- How often does a summons of him go unanswered, and was he away? (`/sc report` counts unanswered summons.)
- Does anyone use `/afk` as a shield?

### 2026-10-05 · Lens of Pleasure: the big moments arrive alone

**The questions (paraphrased):** which pleasures does the game give, and which could it give but does not? The book lists kinds of
pleasure to check against: anticipation, completion, delight in another's misfortune, gift giving, humour, possibility, pride,
purification, surprise, thrill, triumph over adversity, wonder. For each: does the game deliver it, to whom, and *when*?

**The pleasures, as built**

| Pleasure | Where it comes from | Who gets it | When, and with whom |
|---|---|---|---|
| Delight in another's misfortune | Summoning Zennit somewhere unreasonable; the gags | The group | At the cast, together (they are in a party) |
| Humour | The Index's voice, postcards, his out-of-office | Everyone | As it happens, together |
| Thrill | The dice: his roll, the caster's roll back | Him and the caster | Live, together, with a real `/roll` the party sees |
| Possibility | His answers; where to put a writ; his list | Both sides | At the moment of choice |
| Surprise | The whim, "Darnassus again", the Index today | Everyone | Monday, or as it happens |
| Completion | Postcards (10), badges, titles | Everyone | Over a season |
| Pride | Titles, his kind titles, moments named in the keepsake | Named players | At the finale, and `/sc titles` |
| Anticipation | The last call, the provisional result | Everyone | The week's final day |
| **Triumph over adversity** | **A week won; a finale** | **The winning side** | **Monday, at each person's own login, alone** |
| **Wonder** | **The story chapters, narrated and illustrated** | **Everyone** | **Alone, when each person types `/sc intro <key>`** |
| Gift giving | Silver (to him), cards (from him) | Between him and a caster | When it happens |

**Findings**
1. **The two biggest moments are delivered to each person alone.** A week's result is said by each client at its first login after
   the week closes (`checkLastWeek`): one friend reads "The group won the week" at 7am, another at 9pm, and by then it has been said
   in voice chat. A won week also unlocks a chapter of the story: a narrated, illustrated scene, the most produced thing in the addon.
   Each person plays it on their own with `/sc intro g2`, if they bother. The triumph and the wonder are the payoff of a whole week of
   play, and they are the only pleasures the game gives in private.
2. **Everything played live is shared, and that is the strength.** The summons, the dice, the answer lines, the postcards all
   arrive in a party at the same moment. The design already knows how to make a moment shared; it just does not do it for the payoff.
3. **The tools to share it exist.** Sync reaches every addon user in the group; `/sc week say` speaks to the party; the story viewer
   can play any reached chapter. Nothing joins them up.
4. **The rest is in good shape.** Thrill and possibility are live and two-sided; completion has its checklists now (Indirect
   Control); pride is named and kept. Gift giving is narrow (silver and cards), but it is his money and his cards, and the friends give
   each other the evening; nothing to add.

**Proposed changes** (none built yet)

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **Watch it together**: when someone in the group plays a chapter (`/sc intro <key>`, or the Story tab), they can **play it for the group**: every addon client in the party gets a prompt ("Al would like to show the group chapter 3: The group wins. Watch now?") and those who accept start it at the same moment. A new message, only for chapters that are reached; nobody is made to watch | 1, 3 | A message, a small prompt, a button in the viewer and the Story tab; timing is "within a second or so", not frame-exact |
| B | **Say the result in the group**: the week's result line at login ends with "(/sc week say tells the group)", and the first time a group forms after the week closes, the Index suggests it to one person. Speaking in party chat stays a person's choice | 1 | Wording; the "first group of the week" check |
| C | **Leave it**: people tell each other in voice | | Nothing |

**Recommendation:** A. It turns the most produced part of the addon, the narrated chapters, into the shared payoff of the week, at
the moment the group chooses, and it is opt-in on both sides. B is a small nudge that can ride along. Both depend on addon messages
the group already relies on; neither sends chat on its own.

**Our answer (built: A and B, at the weekly raid).** Asked with the answer: the moment to watch it is the start of the group's weekly
raid, when everyone is there.

**Built**
- **A, watch it together** (`Intro.PlayForGroup`, `Intro.OnWatch`, message `V`). `/sc intro <key> group` plays a reached chapter
  and sends its key to the party or raid; every other addon client that has reached it asks "Al would like to show the group chapter
  3: The group wins. Watch now?", and Watch plays it there. It starts when each person clicks, so it is a shared moment, not a
  frame-exact one. Only chapters the season has reached can be shown (the sender's client checks; the admin may show any). A client
  whose log has not caught up yet (a newcomer at their first raid) is asked too and can watch it: nobody has to have watched the
  earlier chapters, or wait for their log to sync, to see this week's. (Asked while building: chapters are unlocked by the season's
  race in the synced log, never by what a person has watched, so a newcomer can play any reached chapter as soon as the log arrives.)
- **At the weekly raid** (`Intro.RaidGathered`). About ten seconds after this client joins a raid, once a week: the raid leader is
  asked whether to play last week's chapter for the raid; everyone else with the addon is told `/sc intro <key> group`. With no
  chapter last week, the leader is reminded that `/sc week say` tells the raid where the week stands.
- **B, saying it in the group.** The week's result line at login now ends "The story: /sc intro g2 group shows it to the group, at
  the raid perhaps."; the raid prompt mentions `/sc week say`. Speaking in chat stays a person's choice.
- **Previously on** (asked while building: how does a newcomer catch up?). `/sc intro previously` plays every chapter this season
  has reached, back to back, in the order the race reached them (`Intro.SeasonSoFar`, `Intro.PreviouslyOn`); each chapter plays to its
  end and the next starts after a breath; closing the window stops it. The welcome mentions it. `/sc intro` (the setup and "The Index
  today") stays the four-minute version.
- **Live checks** `d-watch` and `s-previously`; self-tests of the message, who is asked (a newcomer still syncing included), last
  week's chapter, the once-a-week raid offer, and the season's chapters in order.

**To watch in playtests**
- Does the group watch a chapter together? Do they ask for it?
- When do people hear a week's result: in game, or in voice first?

### 2026-10-05 · Lens of Playtesting, revisited: when is it ready to share?

**Why this lens, and not a new one.** Thirty-odd entries in, every lens ends the same way: "to watch in playtests". The lenses that
fit a small addon for one group of friends are largely done (the book has about a hundred, many about studios, budgets, technology
and large worlds), and each new one now finds smaller things than the last. Meanwhile almost everything since 0.19 has only run
against stubs. The most useful lens now is the one that asks what the game needs before people play it, so this entry is a gate,
not a design change.

**Where it stands**
- **Built and self-tested:** the race, the answers, the story, sync, and every change in this journal. The self-test (`/sc synctest`,
  100 tests) passes in the stub except the window test, which needs the real UI.
- **Confirmed in the game:** ritual detection, the addon messages, the solo tools (from earlier versions). Nothing from 0.20 on.
- **The live checklist** (`/sc check`) has 42 checks: 9 run by themselves, 12 need one person, 21 need a friend.

**Ready to share when** (in order; stop at the first failure and send `/sc check report`)

| Step | Who, how long | What must pass | If it fails |
|---|---|---|---|
| 1. The build | Anyone, 2 minutes | Everyone installs the same tagged release (`v0.23.x` from the release workflow), not a copy of a working folder | Mixed versions misread answers (the version notice says so) |
| 2. By itself | One person, 2 minutes | `/sc check auto`: all nine, above all **a-api**, **a-hooks**, **a-selftest** | Stop: the rest depends on them |
| 3. By yourself | One person, 15 minutes | `s-popup`, `s-fit`, `s-decline`, `s-list`, `s-welcome` (fresh character), `s-login`, `s-sound` | A layout or wording fix; not a blocker unless the popup fails |
| 4. With one friend | Two people (one as Zennit, or `/sc zenit`), an hour | **d-sync**, **d-ritual**, **d-accept**, **d-decline**, **d-cost**, **d-dice**, then d-writ, d-expire, d-away, d-watch | d-sync or d-ritual failing is a blocker; the rest each have a fallback (verification.md) |
| 5. Quiet evening | Same two, an evening of normal play | `/sc errors` is empty afterwards | Paste the errors |

**Then share it.** Everything else on the list (d-postcard, d-leave, d-lines, d-witness, d-firstbrief, d-silver, s-lastcall,
d-overlap) happens in normal play and marks itself, or is a judgement the group makes; it belongs to the playtest, not before it.
Phase 3 of `design/verification.md` and `design/playtest.md` take over from there: the Monday report and three questions.

**A freeze.** From the moment it is shared, no new rules until the first week's report is read. Fixes for what the checks find, and
wording, are fine. The open decisions that wait on data are already named: the helper bonus (Indirect Control, B), the head start
(Elegance, Simplicity/Complexity), what an expired prompt does (`d-expire`), and whether five weekly wins is the right season.

**Built with it: the weekly question** (asked after the entry: should the game ask how people feel?). The Monday questions in
`design/playtest.md` are asked out loud, which misses the two people who matter most: Zennit (the game is aimed at him, and he is the
least likely to say "too much" in front of everyone) and the quiet ones (who stop logging in rather than complain). So, once a week,
at the first login after a week with summons, the Index asks one question with three buttons ("How was last week?": Good fun / It
was fine / Not for me; Zennit: "How was being summoned?": Bring it on / Fine / Too much). One click, or close it to skip;
`/sc feelings off` stops it. **Only Zennit's and the admin's clients keep the answers** (message `F`; each client re-sends its own with
its hello so they catch up), and `/sc feelings` there shows counts per week, never names. It is a playtest tool, not a rule, so it
fits the freeze. The cue to act: a "Too much" from Zennit, or "Not for me" twice running from anyone. Live check `d-feelings`.

**Lenses left for after the first week**, when there is something to look at: Expected Value (the writ and the free decline,
with real numbers), the Interest Curve again (how a real season felt), and Balance again (whatever the group found).

### 2026-10-05 · Lens of Judgment: what the game praises each of them for

**The questions (paraphrased):** what does the game judge about the players, and how does it tell them? Is the judgment fair and
visible? Is it judging what the players want to be judged on, and what the designer wants them to do more of? Players do more of
what a game praises.

**What the game judges, as built** (`Scoring.lua` badges, `Ledger.Titles`, the report, the leave count)

| Who | Praised for | Kind of thing | Where it is said |
|---|---|---|---|
| A caster | Volume (Entered, Filed in Triplicate, A Volume of Their Own, the Heaviest Hand, most disturbing of his leave); places (Below Stairs, Beyond the Jurisdiction, Five Places); regularity (Known to the Clerk) | Effort | Badges as earned; titles at the finale and `/sc titles` |
| A helper | Helping (the Best Supporting Role) | Effort | Titles |
| A pair | Their bonus tipping a roll (the Lucky Pair, Countersigned by Witnesses) | **Luck** | Titles, a badge |
| A caster | Paying his silver (the Prompt Payer, Paid in Full, Stamped to the Last Punch) | Good conduct | Titles, badges |
| Zennit | Winning the dice in a row (the Dice Goblin) | **Luck** | His titles |
| Zennit | Asking a high price (the Hard Bargain) | Mischief | His titles |
| Zennit | Answering quickly (the Quick Reply) | Good conduct | His titles |

**Findings**
1. **Nothing praises Zennit for being a good sport.** His three titles are for luck, for mischief and for speed. The thing the
   whole game hopes he does, going where he is sent and laughing about it, is the one thing nothing ever praises. Every rule
   pays him for avoiding summons (dice he wins, declines that cost the group), and the only "kind" judgment of him is about
   speed. The Griefing lens worried about the game staying fun for him; the judgment does not help, because it never thanks him.
2. **Nothing praises the group's skill.** The group's real decisions are the writ (where to play it) and the order of summons
   (Skill and Chance, Secrets). A writ that bites, costing him a decline he would have taken for free, is the cleverest move the group
   can make, and it goes unremarked. Everything the group is praised for is effort or luck.
3. **The judgment is fair and agreed.** Every title and badge is worked out from the synced log, so every client says the same, and
   none of it moves the score. Nothing to change.
4. **The report judges in public.** `/sc report` (pasted to the group chat on Mondays) shows his median time to answer and how many
   summons went unanswered. That is the playtest's data, and the Community lens chose to make the waiting visible; but it is the one
   place the game judges him in front of everyone without a joke attached. Watch how it lands; the weekly question will say.

**Proposed changes** (none built yet)

| # | Change | Fixes | Cost |
|---|---|---|---|
| A | **The Good Sport**, one of Zennit's titles: the summons of him he went on this season (accepted, or the silver named), from about ten: "The Good Sport: Zennit, who went where he was sent 14 times, including Silithus." In `/sc titles` and the keepsake like the others | 1 | A count and a line in `Ledger.Titles` |
| B | **The Process Server**, a group title: the caster whose writs cost him the most ("The Process Server: Al, whose writs cost him 13 points."), so the group's cleverest move has a name | 2 | A count of writs that bit, per caster, and a line |
| C | **Leave it** | | Nothing |

**Recommendation:** A and B. They are titles, not rules (no points, nothing to learn), so they fit before the freeze; and they
praise the two things the judgment now misses: him being a good sport, and the group being clever.

**Our answer (built: A and B).**

**Built** (`Ledger.Collect`, `Ledger.Titles`)
- **A, the Good Sport.** The season's summons of him that he went on (accepted, or the silver named or paid) are counted, with the
  first far-flung place among them. From ten (`Ledger.GOOD_SPORT`) he holds it: "The Good Sport: Zennit, who went where he was sent
  14 times, including Silithus."
- **B, the Process Server.** Each caster's writs that bit (a writ that counted, on a summons he declined at a cost) add up its points:
  "The Process Server: Al, whose writs cost him 13 points.", with who is close behind, like the other titles.
- Both appear in `/sc titles` and the season's keepsake, with the other titles; no points. A self-test covers both, and the threshold.

**To watch in playtests**
- Does Zennit care about his titles? Does the group compete for the Process Server?
- How does the report's "time to answer" land with him?

## Parked ideas

Not built: the Playtesting entry holds new rules until the first week's report. Each waits for a lens (or the report) to pick it up.

- **Stranded: summon him to the middle of nowhere when he has no hearthstone** (2026-10-06, from the group). A challenge
  summons: the group drags him somewhere remote while his hearthstone is on cooldown (or not in his bags), so the trip back is
  his problem. Today the place is always the caster's choice and the only randomness is the dice and the whim; "the middle of
  nowhere" just scores as a zone (3). Open questions:
  - *Can the addon tell?* Only his client can see his hearthstone (item 6948: its cooldown and whether he carries it), at the
    moment the game's prompt appears; never tried in this client. A mage's portal or a friend's summons home would undo it.
  - *What is "nowhere"?* The game gives a map and a subzone name, not a distance to the nearest flight path. An empty subzone,
    or a short list of truly empty spots, is the likeliest test; the far-flung list (10) is the nearest thing we have.
  - *What does it pay?* Points on top of the place, a badge or title ("Left in the Wilds"), or a postcard only, to keep it a joke.
  - *Is it fair on him?* A walk back costs him real time (Griefing / Friendship, Freedom): his free decline already covers a
    summons he cannot afford, and it should stay rare, like a writ (say once a week, or once a season).
- **Built since (v0.28.0): the mechanism, not the rule.** Questions only Zennit's client can answer (`/sc ask`, `Ask.lua`): is his
  hearthstone in his bags and ready (or how long until it is), and how long has he been logged in. The question
  goes to the group and the guild, his client whispers the answer back, and he is told who asked; `/sc zennit ask off` stops it.
  Nothing scores an answer yet. A challenge (the stranded summons) or a card the group plays to learn something about him calls
  `ST.Ask.Ask(key, arg, callback)`; a new question is one entry in `Ask.QUESTIONS`. Still open for that rule: should a card spend
  a question (today anyone may ask, one every five seconds), and should he be told before the answer goes out, or only after.
  **Not asked (2026-10-08):** what else is in his bags. A question about any item could be misused to go through his inventory;
  only the hearthstone is looked at.
- **A place the Index draws each week**, picked from the week number like the whim (so nothing is synced), worth extra; or a
  spot Zennit names himself as the week's dare. Both answer "who chooses where", which today is always the caster.

## Decisions

| Date | Decision | Lens | Why |
|---|---|---|---|
| 2026-10-04 | The group should have to try to beat Zennit; "he wins more weeks than he loses" no longer holds | Essential Experience | A win should be earned and reachable |
| 2026-10-04 | "Trying" means beating him at his own answers; keep it tongue in cheek | Essential Experience | Summoning Zennit should be how to win, not a risk to avoid |
| 2026-10-04 | New race from 5 Oct 2026: only summons of him count, 5 a week, 3 dice a week, +5 per helper, head start 2 | Fairness, Meaningful Choices | See the Fairness entry: effort pays, and his list keeps his week off within reach |
| 2026-10-04 | 5 to 10 summons of him count a week; he can close the Index for free once 5 are filed | Griefing / Friendship | He gets a way out; closing can't lock in a lead before the fair minimum |
| 2026-10-04 | Show where the week stands when it changes: briefing at the ritual, a chat line after summons and answers, in his popup, and the lead in the band | Visible Progress, Feedback | Progress was only in the hub, and the facts that decide how to summon him came too late |
| 2026-10-04 | Helpers named when their bonus wins a roll; the assistants prompt saves itself; Zennit told he can ignore a summon; no helper badges | The Player | The group likes banter and doing things together, and hates bookkeeping; rewards don't motivate them |
| 2026-10-04 | His week off is real: summons of him are filler, the race skips the week, and the gags carry on | Interest Curve | His wins were a story beat with no effect; a pause makes them count without silencing the joke |
| 2026-10-04 | Catch-up: Zennit's dice edge moves 5 (a lead of 2 wins) or 10 (3 or more) toward the side that is behind | Interest Curve | Blowouts were 49% of seasons at normal effort; the Index now leans on the scale, gently |
| 2026-10-04 | Keep five weekly wins to a finale (a season of about 11 weeks at normal effort) until a real season shows how long it takes | Interest Curve | Simulated length is long, but the group's real pace is unknown; shortening later is one constant (`Week.WINS`) |
| 2026-10-04 | No rule change for Skill and Chance; say so when his last die is spent | Skill and Chance | A week is mostly chance and a season mostly skill, and the group's best order depends on how he rolls; the moment their ordering pays off was invisible |
| 2026-10-04 | The Index remembers named moments, the silver he is paid, and a keepsake of each finished season; players named by character | Story and Emotion | The personal material was in the log and scrolled away; naming players is what a friend group repeats |
| 2026-10-04 | Pools of lines, a whim of the week (four small twists, about half the weeks), a recording sheet and a list that remembers | Surprise | The surprises were in the people and the story only; the repeating lines were wallpaper by week 9 and every week played under the same rules |
| 2026-10-04 | Bound the list (five places of four letters or more), add a rules card (`/sc rules`), and re-word intro scenes 9 and 10 (audio to be re-rendered); keep the head start | Elegance | An unbounded list could decide every week; no one place said all the rules; the narration predated four rules |
| 2026-10-05 | Playtest from the log: `/sc report` counts the numbers, `design/playtest.md` is the script (smoke test, Monday routine, questions for people, what settles each open decision) | Playtesting | The group dislikes bookkeeping; most of the open questions are numbers the log already holds, and nothing had ever been run live |
| 2026-10-05 | The group sees how many summons are waiting for his answer; Monday's result is provisional while he can still answer; unanswered still counts as accepted for now | Community | The balance is hostage to his attendance (a quarter skipped doubles a normal week's chance), nothing reminded him, and a late answer could reverse an announced win |
| 2026-10-05 | A demand for silver no longer holds the summons back: it counts at once and the silver goes on a tab; Zennit names the price, and a card's punch pays it | Meaningful Choices | Under the new rules a silver demand cost him nothing and blocked the group's points until paid, so it beat refusing, had no weekly limit, and put the blame for paying late on the group |
| 2026-10-05 | A `/sc tab` statement of who owes what; the ask is not bounded (trust the group); cards are not forced to be a discount and points stay a score | Economy | The tab was only visible as a total and a login line; the silver cannot hurt the race, so a bound would only police the mood of friends |
| 2026-10-05 | Season titles, mid-season standings (`/sc titles`), kind titles for Zennit, and four later badges for the people who cast; helpers get titles, not badges | Reward | Individual rewards were front-loaded and for warlocks only; a helper's only reward was a named line about every other season |
| 2026-10-05 | The Tools tab is five columns (the reports have their own, The record); a one-line command tip each Monday (`/sc tips off`); `/sc help` is five lines and `/sc help all` is the rest | Interface | One Tools column had grown past the tab for the admin; the useful commands were listed only in a 25-line help |
| 2026-10-05 | The week's turnover stays at Monday 00:00 UTC (11:00 on the east coast of Australia in summer); the week's close is said in the player's time, and the last day of a week has a last call | Time | Nothing said when a week ends, and the deadline was never felt; the group's evenings fit the UTC week |
| 2026-10-05 | Errors are caught, said once and kept for `/sc errors`, and a friend on another version is noticed; the clock check and a season cache wait | Risk Mitigation | The biggest risk is code that has never run in the game, and with script errors off a bug is silent; a mixed-version group reads answers wrongly |
| 2026-10-05 | The lines read while playing, the silver and card lines and the badge names are in the Index's voice; a plain `how` line says what each badge takes; `design/voice.md` is the house style | Unification | The theme was strong in the story and thin in the play; the newest systems had no voice, and the badges read as any game's |
| 2026-10-05 | The ritual briefing says what the place is worth and what it puts at stake for both sides; `/sc places` checks every map ID against the game's own name; the point values stay | Endogenous Value | A place's worth is the stake of a summons and was invisible when the choice was made; the place table was from memory and never checked |
| 2026-10-05 | The Party tab and `/sc tally` rank by summons of Zennit this season (an "Of Zennit" column), then points; `/sc week say` tells the group where the week stands; the cheap-slot order is left to the group | Cooperation | The one list everyone reads counted all-time points of every summons, not what the race counts, and the plan for the order lived in the caster's chat alone |
| 2026-10-05 | The ritual briefing is long once a week (the first summons of him) and short after; the second Week line and a chat setting wait for a playtest | The Toy | One summons cost about six wrapped lines of chat, and the longest, most repeated line arrived while the caster was channelling |
| 2026-10-05 | What he presses at the game's own summon prompt is his answer (accept: accepted; decline: declined, worth nothing either way); the group has two writs a week that make a decline of one summons cost him its points; the version is 0.20.0 | Resonance | The addon asked him to answer a summons he had already taken or declined for real, and could not tell the two apart; a decline needed to be a move the group could price, not a punishment for real life |
| 2026-10-05 | His first decline of a week in the game is free; every later one, and any on a writ, costs him the summons' points; the popup and his own Week line say how many free declines are left | Balance | A free decline with no limit was better than refusing every time and let him win every week he chose to (simulated: the group won 0% against 63% on the old rules); one a week leaves about 43% |
| 2026-10-05 | Dice are one click; a key binding arms a writ; what he presses at the game's prompt ends a roll in flight | Flow | The ordinary summons needed nothing from anyone, but dice cost three clicks across two people and a writ had to be typed mid-play; a roll and the game's prompt could give two answers to one summons |
| 2026-10-05 | The Tools tab is three sections (General, Testing, Checks) and opens on the one used last; each lens now ends with a live check for what only the game can confirm, and the earlier lenses have theirs (`s-login`, `s-band`, `s-lastcall`, and `/sc week login` to say the login lines again) | Interface, the method | Five columns and three rows left the output box three lines; the live checks arrived after Flow, so the lenses before it had no way to be confirmed in the game beyond the rules the self-tests cover |
| 2026-10-05 | A welcome at the first login (nothing new to do, who needs the addon, the rules card); the rules card and README say who needs it; a caster's first summons of Zennit gets the full briefing whatever the day | Accessibility | A newcomer was pointed at four minutes of out-of-date story, nothing said that a caster without the addon logs nothing, and their first briefing assumed they knew the race |
| 2026-10-05 | When the caster has no addon, Zennit's client files the summons from the game's prompt, with the caster, place and helpers that clients in the group saw (a witness note); the caster's own record replaces it if it arrives; version 0.21.0 | Accessibility | A warlock without the addon logged nothing, so their summons of him did not count; his client always sees the prompt, and anyone in the group can see who channels the ritual |
| 2026-10-05 | One rule for no: a decline in the game or on the form is free at a place on his list or with his free decline, otherwise it costs, and a writ always costs; every no reads as "declined (free)" or "declined (cost him N)" | Simplicity/Complexity | The two surfaces followed different rules, so a form refusal at a list place dodged a writ and the form's Refuse could only hurt him; three words for one act |
| 2026-10-05 | His list is set for the week (a new place counts from Monday); the briefing says a writ only bites at his list once his free decline is used; postcards from far-flung places, once each a season, no points | Secrets | The list could be changed with a summons on screen, which made every decline free; the group could not see when a writ mattered; the far-flung trips earned points but no part in the joke |
| 2026-10-05 | Zennit writes his own postcards and an out-of-office for his week off; sent from his characters only, the newest kept, used on every client in place of ours | Character | Every word about him was ours; the two moments the joke is about him (where he was dragged, where he went on leave) are where his own line is funniest |
| 2026-10-05 | A summons of him on his week off is "disturbing his leave": the lines say the race is off but postcards and titles still count, and the Index counts who disturbed it most; the week off itself stays | Inner Contradiction | About a third of weeks are his weeks off, and the only line the caster read said "do not bother", though most of the game still ran |
| 2026-10-05 | The far-flung places still missing a postcard are named in `/sc week` and at the Monday login; the helper bonus waits for the report's helper counts; the Index's weekly request is parked | Indirect Control | The place nudges (points, postcards) arrived at the cast, after the group had already travelled; a ritual needs two helpers anyway, so the bonus steers only the bookkeeping |
| 2026-10-05 | A summons that comes while he has been AFK for five minutes or more is filed as away: free, not his free decline; the caster is warned at the cast; version 0.23.0 | Freedom | Stepping away from the keyboard in the group let summons count as accepted with nothing he could do; silence cannot be free in general (Balance), but an AFK that began before the ritual is not a dodge |
| 2026-10-05 | A chapter can be shown to the whole group (each person asked "Watch now?"), and the raid leader is offered last week's chapter when the weekly raid gathers | Pleasure | The week's triumph and the story's wonder were the only pleasures delivered alone, at each person's login; the weekly raid is when everyone is there |
| 2026-10-05 | Share it with the group once the five-step gate passes (one release for everyone, the automatic checks, the solo checks, an hour with one friend, a quiet evening); then no new rules until the first week's report | Playtesting | The lenses that fit are largely done and each finds less; everything since 0.20 has only run in stubs, and the next answers are in the group's play |
| 2026-10-05 | A one-click weekly question on how the week felt (Zennit asked his own); answers only reach Zennit's and the admin's clients, shown as counts, never names | Playtesting | The Monday questions are asked out loud, which misses Zennit and the quiet ones; a "Too much" or a run of "Not for me" is the cue to change something |
| 2026-10-05 | Two titles: the Good Sport (Zennit, ten summons he went on in a season) and the Process Server (the caster whose writs cost him the most) | Judgment | The game praised the group for effort and luck and him for luck, mischief and speed; never him for being a good sport, or the group for being clever |
| 2026-10-08 | Build the way to ask Zennit's client what only it knows (`/sc ask`: his hearthstone and time logged in; nothing else in his bags), with no rule on it; he is told who asked and can switch it off | Parked ideas (the stranded summons) | A challenge or a card needs facts only his client has; the mechanism can be built and checked before anyone decides what an answer is worth |
| 2026-11-11 | Achievements for everything the Index counts (46, with progress), helpers included: summons helped with and rolls tipped as a helper. This reverses "no helper badges" (2026-10-04, 2026-10-05) | Reward | Asked for by the admin: an achievement for all the things tracked. Fish and snowballs had boards but nothing to earn; the ten badges were the only individual rewards and went only to casters |
