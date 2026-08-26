# Rules — what has already gone wrong, and must not again

<!-- Extracted from BACKLOG.md 2026-08-13 | 39 rules -->

**Every one of these cost a session at least once.** They are the project's
troubleshooting guide and its lessons learned in one list: when something in the
simulation does nothing, or does far too much, the cause is usually already
written down here.

## How to use this

- **Before writing a threshold**, read rules 6, 23, 24 and 30.
- **Before adding anything to the per-tick path**, read rule 4.
- **After fixing anything that makes the colony richer or bigger**, read rules
  27 and 31 — every affordability guard and every priority chain above the fix
  has just changed meaning.
- **When a number looks fine and the game still feels dead**, read rules 12, 13,
  16, 20 and 22. Those are the ones that hide behind healthy-looking metrics.
- **When a list comes back empty**, read rule 28 before believing the obvious
  reading.

The recurring shape, stated once: **a threshold beyond the reach of the rate
meant to cross it.** Rule 6 is the general case; rules 12, 14, 20, 21, 24, 25,
30 and 32 are all instances of it in different clothes. If a mechanic never
fires, do the arithmetic before you rewrite the mechanic.

---

1. **Presentation never writes the simulation.**
2. **Determinism** — seeds from stable ids; new RNG draws at the *end* of a
   generation pass, never inserted in the middle.
3. **Decode-if-present** — every new field optional with a sane default.
4. **The per-tick path is replayed tens of thousands of times.** Anything
   O(entities) goes on a cadence (`LaborEngine.staffingInterval`,
   `JobBoard.interval`, `AnimalEngine.thinkInterval`, all 10).
5. **`isEmpty` is not "has no layer"** — `usesEntityLand`, `usesEntities`,
   `StoneField.usesBlocks`.
6. **Check a threshold is reachable by the rate meant to cross it.** This has
   now bitten seven times; the newest was winter being unable to make anyone
   cold. Write a test named for the reachability, not for the behaviour.
7. **Content is data, CZ+EN, in the same change.**
8. **Two numbers that must agree live in one place** — `SettlementGeometry.span`
   and `SettlementRenderer.colonySpan` are one number in two files.
9. **Ground tiles overlap by a hair, so every layer over them must be opaque.**
   The overlap hides seams under an opaque fill and *doubles* under a
   translucent one, so a see-through snow or light sheet paints a bright line
   along every tile edge and the whole valley turns into brickwork. Resolve
   cover, season skin and light band into one colour and fill it solid —
   `SettlementGround.Tone`.
9b. **`GameDataRegistry.bundled()` loads items with `try?`.** One malformed
   effect anywhere in `items.json` silently empties the *entire* table — no
   loot, no equipment, no error. `colony_production` takes `perTick`, not
   `amount`. Guarded by "A single bad item cannot silently empty the whole
   table".
9c. **A standing order has to *reach* a town that is already full.** The
   assigner only ever touches the idle — rightly, or it would undo the
   player's own choices — so a policy alone changes nothing in a colony where
   nobody is idle, which is every colony past its first decade. `rebalance`
   is the slow hand that makes the rule bite. Same shape as rule 6: a lever
   whose effect cannot reach the thing it is aimed at.
10. **A cell one tile wide is against both its side borders.** With the fog grid
   three times taller than it is wide, `subX` comes out as 1 and a dither that
   only borrows from an edge it is strictly on borrows vertically alone — which
   drew the valley as vertical stripes for as long as the ground has existed.
10b. **The map is not square, and every field drawn over it has to know.**
   Rule 10 was fixed for the ground *cover* and not for the **relief** the
   light reads, so noise that is round in `(u, v)` came out four times
   stretched in pixels and the valley went back to being striped the moment
   it was lit. `SettlementLight.relief` and `slopeLight` take an `aspect`;
   anything else sampling a normalised field across the whole map needs the
   same. Guarded by "Hills come out round on a phone, not as vertical stripes".
11. **Playback pace is not simulation pace.** A tick is a real minute and a
   battle is eight rounds; played at the tick's own speed that is one
   exchange every seven and a half seconds, which reads as nothing happening.
   A *record* may be replayed at whatever speed makes it legible —
   `SettlementBattle.playSeconds`. Do not confuse "how long it took" with
   "how long to show it for".
12. **A threat that does not scale with what it threatens is scenery.** Rule 6
   in the danger direction, and it hid behind "the numbers look fine": predator
   pressure is capped by the era, so the same ten-strong pack came at a colony
   of five and a colony of four hundred. Guarded by "The wild answers a colony
   that has grown".
13. **A feedback loop needs an input from outside itself.** Grudge could only be
   made by a quarrel, a quarrel needed standing below −15, and standing drifts
   toward +62. Every term inside the loop, so the loop never started: six
   peoples at +75…+82 and not one war in two hundred years. Anything that is
   supposed to *build up* has to be fed by something that is true whether or not
   it has already started — here, the colony being the bigger neighbour.
14. **A rate multiplied by an entity count is a rate with no ceiling.** Rule 6
   read backwards. Defection was `0.30 per discovered tribe per year`, which is
   fine at one tribe and fatal at six — and the count only started growing when
   something *else* (the council exploring) changed. Ask of any per-entity roll:
   what bounds the number of entities, and what happens to the colony when that
   number is at its maximum? If the answer is "it dies quietly", the roll
   belongs on the colony, asked once.
15. **An autonomous standing order must be priced as a standing order.** Every
   `dispatch` in the game is written for a player who tapped it once and knew
   what it cost. Handing the same call to the council turns "once, deliberately"
   into "four times a year, for ever" — so the council needs its own, stricter
   gates on top: a cadence, a surplus bar above the one building has to clear,
   and a cap on how much of the workforce may be abroad.
16. **An income is not a store, and a council that watches the store builds too
   late.** The larder being full says nothing about whether the fields can fill
   it again next year. Anything that raises capacity — farms, beds, storage —
   has to be triggered by a *rate against a need*, never by a stock level:
   `plotsWanted(for: population)` against `plotsStanding`, not `food < 25 %`.
   The failure is silent right up until it is total, because a buffer hides it.
17. **A trade with no members cannot acquire any.** `assignIdleAdults` only
   touches the idle, by design, so every mechanism that is supposed to *reach*
   a working town has to be checked against a town where nobody is idle — which
   is every town past its first decade. `rebalance` is that mechanism, and it
   had a guard on it that switched it off for exactly the colonies that needed
   it. Rule 9c is the same lesson; this is the case where the count starts at
   zero and therefore never moves at all.
18. **What is in the simulation is on the canvas.** Keks's standing rule, given
   twice now (2026-08-06, 2026-08-07). Not "the canvas looks plausible" — the
   canvas shows *the thing the engine is doing*, and anything that describes a
   colonist reads the same source the drawing does. The two ways this breaks:
   a value the renderer invents beside one the engine owns (the farm's painted
   furrows next to real plots; five ruled rows that always looked ripe), and two
   readers of the same colonist answering from different fields (`workplace`
   reading `currentJob` while `activityLabel` read `assignedWork` — "je uvnitř,
   píše to venku"). Before adding any drawing, ask what in the Core it is a
   picture *of*; if the answer is "nothing", that is the bug.
19. **A birth rate is not a population knob.** Births and deaths are both
   per-capita, so their ratio is independent of how many people there are:
   there is no equilibrium population, only growth or collapse, and the only
   thing that bends the curve is housing (`headroomFactor`). Cutting births to
   make a colony "smaller" bought a colony that peaked at 51 and was dying at
   19 with an empty granary a century later. Size comes from the roofs; pace
   comes from `realSecondsPerTick`; the birth rate only decides whether the
   place has a future.
20. **A rate that is linear in population, against an opportunity space that is
   quadratic in it, shrinks as the world succeeds.** Rule 6's social form, and
   the one that hid longest: `SocialEngine` held one encounter per ten
   colonists per tick while the *pairs* who could meet grow as n². So a bond in
   a village of seventeen gained two points every two years against a decay
   that never slowed — forty-five years to a wedding, and every marriage in the
   colony's history made in its first fifteen years. Ask of any per-tick
   opportunity: how many *pairs*, *sites* or *combinations* is it being spread
   over, and does that grow faster than the rate does?
21. **A rate that saves up for an indivisible batch has to reach the *dearest*
   batch, not the cheapest.** Rule 6 in an accumulate-then-spend loop, and it
   killed the colony twice over in one session. `CookingEngine` banked effort
   and capped the bank at one batch of the cheapest meal — a sound rule against
   hoarding — while `best(for:)` chose the meal by what the *shelf* could spare.
   A full shelf reached for the 2.0-work stew every tick against a ceiling of
   0.8 plus one cook's 1.0, so nothing was ever cooked and the cheaper pot was
   never even considered. Ask of any bank: what does the thing being saved for
   cost, and can one worker's rate plus the carry-over ever reach it? Aggregate
   throughput tests go straight past this — `cooksKeepUpWithFarmers` divides a
   thousand cooks by the dearest meal and was green the whole time.
22. **A convenience threshold on a survival path is a death sentence.**
   `ErrandEngine.furthestWorthGoing` means "not worth the walk", which is right
   for a mild need and lethal for hunger: anybody working further than half the
   valley from the granary was refused the errand every tick from `hungryBelow`
   down to zero and starved beside a full store. Of any "not worth it" rule,
   ask what happens when the need behind it kills. It hides perfectly, because
   every food metric reads fine — the granary was at 1148 of 1150 the whole
   time.
23. **A threshold against a field must be set from the field's own
   distribution, not from what the number "feels like".** Rule 6's measuring
   half, and it went wrong in *both* directions in one sitting: a peak had to
   stand 0.10 above all six neighbours, when the 99th percentile of that
   measure is +0.018, so no peak could exist — while a plateau had to be flat
   to within 0.22, which is the 33rd percentile, so every high hex was one.
   Twenty-nine plateaus in a world and never a pass. Print the percentiles
   first (`MapProbe.relief`), and prefer definitions that need **no magnitude
   at all** — a peak is higher than everything it touches — because those
   cannot drift when the field's scale is retuned. The same arithmetic slip
   killed `Climate.wobble`: a generator whose *range* is wrong makes every
   constant that reads it a lie.
24. **A per-tick rate is a per-year rate multiplied by sixty.** `upkeepRateOfCost`
   read as "three per cent" and meant **a hundred and eighty per cent of a
   building's price every year, for ever**. Measured, seed 4242: twenty-three
   buildings by year thirty, materials at 1, and `StewardEngine.buildableHere`
   empty for the next hundred and seventy years — the colony paying to stand
   still while food, energy and influence sat pinned at the cap. Of any rate
   written per tick, say it out loud times `ticksPerYear` before believing it.
   Guarded by "A century in, the colony can still afford to build".
25. **A sink that grows with everything you own, against an income that grows
   only when you can afford one of three buildings, is a trap and not a
   balance.** The store clamps at zero, so there is no way back out of it: the
   council could not buy the lumberyard that would have paid for the upkeep.
   Rule 20's shape in the ledger. Ask of any cost that scales with the colony:
   what income scales with it, and can the colony still reach that income from
   the floor?
26. **An effect written into a field the engine recomputes every tick does
   nothing.** `PawnEngine` derives `mood` from needs, so every `pawn_mood` in
   `events.json` was overwritten on the following tick and no event was ever
   *felt* — a golden age and a plague moved the same number for the same one
   tick. Anything an event does to a derived quantity has to land in a term the
   derivation reads (`Pawn.moodShift`) and fade on its own. Guarded by "A good
   year is still remembered a tick later".
27. **When a "cannot afford" bug is fixed, every `if canAfford` above it becomes
   a new bug.** `StewardEngine.sendSomebodyOut` tries charting the fog first and
   the branch *returns* — harmless while the store was never brimming, and once
   `upkeepRateOfCost` stopped draining it the branch was affordable every single
   sitting. Measured, seed 4242: thirteen regions charted in forty years, four
   workable landmarks standing in the colony's own valley the whole time, and
   **not one party ever sent to any of them**. Rule 6 wearing an `if`: a
   priority chain whose first branch became always-true starved everything
   under it. After any change that makes the colony richer, re-read every
   affordability guard that used to fail. Guarded by "A colony nobody steers
   works the landmarks in its own valley".
28. **An empty option list is not a diagnosis — ask *why* it is empty.**
   `buildableHere` came back empty at the hundredth year and the obvious
   reading was the freeze it had just been fixed for. It was the opposite: the
   colony held its store at the cap and wanted nothing, because the repeat cap
   is `1 + population / 15` and it already had one of everything it was allowed.
   Empty because **full**. A test of "can it still build" that asks for appetite
   measures the wrong thing; ask whether the ledger can *pay*, which is what the
   trap actually took away.
29. **Two call sites that both fire on launch will both fire on launch.**
   `EndlessFrontierApp` opens the session from `.task` *and* from
   `scenePhase == .active`, so a cold start opened it twice and the world
   advanced twice for one absence — every catch-up tick simulated again, and the
   summary computed off a world that had already moved. `isCatchingUp` only
   covered the long path, and only by luck of ordering. Guard the *operation*
   (`isOpeningSession`), not the symptom, and keep both call sites: a relaunch
   and a return from the background are not the same event.
30. **A constant derived from a rate must be checked against what the
   simulation *realises*, not against what the rate permits.**
   `FarmEngine.peoplePerPlot` was four because a plot's ground yields about 5.6
   mouths' worth of food — true, and irrelevant: a crop only counts once a
   farmer has cut it, what is cut waits to be hauled, and what is hauled waits
   for a cook. Every one of those is a valve and four assumed all three open.
   Measured, the fields delivered about half. Rule 24's sibling — that one is
   about the units of a rate, this one is about believing a rate at all.
   Guarded by "A plot feeds what it is built for", which now asserts the
   council's number sits at least 1.8× under the ceiling.
31. **Fixing a growth ceiling promotes every ordering that was only ever safe
   because nothing grew.** `StewardEngine.nextBuilding` put roofs before
   fields, which was fine while the colony was not really growing: a town that
   has stopped growing is not short of beds, so the housing clause fell through
   and the fields got their turn. The moment the fertility clock was fixed,
   housing was short every year for two centuries and the field clause was
   never reached again — `plots` at 38 while `plotsWanted` climbed to 49 and the
   colony starved. Rule 27's shape a second time. After any change that makes a
   colony grow, re-read every priority chain in the engine and ask which branch
   has just become permanently true.
32. **A demand list that names one consumer gets read as if it named them all.**
   `StewardEngine.wantedMaterials` was the only list of wanted materials in the
   game, and it was built from what *buildings* ask for. So when the
   quartermaster arrived and wanted `leather` for coats, nothing anywhere asked
   anybody to tan a hide: the tannery never ran, `bestGear` never found an
   armour it could work, and a colony that armed forty of its fifty-five in a
   decade clothed **nobody in two hundred years** — with hides stacked in the
   store the whole time. Rule 6 in the supply chain: the last link was
   reachable, and the one before it was never asked for. When a new consumer
   appears, it publishes its own wants and the council unions them in; nobody
   edits a list that belongs to somebody else.
33. **A claim that is only ever taken fills up at whatever rate it is issued.**
   `HaulPile.claimedBy` was set when a colonist reserved a heap and cleared in
   exactly one place — `piles.remove(at:)`, when the carrier arrived. Anyone who
   claimed a heap and then died, sickened, or walked out to a landmark took it
   with them for ever, because `nearestUnclaimed` skips a claimed heap. Two
   centuries of ordinary deaths leak claims steadily, and the harvest quietly
   stops arriving.
   Measured, seed 4242: goods lying reaped and uncarried climbed
   **9 → 42 → 136 → 228 → 318 → 354 and never once came down**, the raw shelf
   went 4118 → 516 → **0**, and the colony fell 197 → 44 — while plots stood at
   140 against 79 wanted, and cooks and farmers both scaled correctly with the
   population. *Nothing was short.* The food was reaped, dropped, and owned by
   somebody no longer alive to fetch it. Releasing dead claims took the same
   colony to **298 and still growing** at year two hundred, with nothing left
   lying from year forty on.
   Rule 6 in a place nobody thinks to look: it is not a threshold or a rate that
   fails here, it is a *release* rate of zero. Of any claim, lock, reservation
   or assignment, ask what clears it when the holder is gone — and note that
   this hides perfectly behind healthy production numbers, because production
   was never the problem.
34. **Check what a rate is *per* before deciding it is too small.** Everyday
   walking was `0.06` for a hauler and `0.09` for somebody on an errand, both
   **per world tick** — and a world tick is two real minutes and about six
   in-game days. So a colonist fetching a sack from the far side of the village
   spent sixteen ticks on it: three in-game months, half an hour of real time,
   to cross a place you can see all of at once. On the canvas that is about one
   and a half points a second, which is under the eye's threshold for motion.
   The report was "the figures don't move", and they were moving — **thirty
   times slower than the colonist standing next to them**, who was drawn from
   the day clock at 4.5 map widths per five-minute day. Two clocks on one
   screen, in two units, and nothing in the simulation ever complained: the food
   still arrived, the store still filled, and the only symptom was that the
   working half of the town read as scenery. `SiegeEngine.pace` was the single
   movement rate measured per **action step**, and it was the single movement
   that looked alive — the answer was in the codebase, being used by one system.
   So: a rate expressed in the wrong unit is not a balance choice, it is an
   arithmetic mistake wearing one. Before tuning a number, convert it to the
   unit the *player experiences* — map widths per real second, deaths per year,
   loads per day — and compare it to the other things in that unit. Two rates
   that describe the same act (a person walking) must be measured on the same
   clock, or one of them is furniture. Guarded by `WalkPaceTests` and, across
   the layer boundary, `WalkPaceAgreementTests`.
35. **A number that must equal another number should *be* that number.**
   `SettlementRenderer.colonySpan` was a literal `0.58` carrying a comment
   saying it must agree with `SettlementGeometry.span` in the Core, plus a test
   guarding that it did. Widening the valley changed the Core's number and left
   the canvas's behind — which draws every building in a different place from
   where colonists are sent to work in it, the exact failure the comment was
   written to prevent. The comment and the test were both doing work that one
   `=` does better and cannot forget. Prose that says "keep these in sync" is a
   note that the code should have said it instead; reach for the assignment
   before the assertion, and keep the assertion only for things that genuinely
   cannot be derived.
36. **A standing order is read where the work is done, not where the work is
   handed out.** `LaborEngine` refused to *assign* anybody to a trade the
   policy had switched off, and that was taken to be the whole of it. It is
   not: a colony is founded with Nadia already scouting (`GameWorldFactory`), so
   a player who forbade scouting on day one had a scout walking out anyway
   until the labour engine got round to reassigning her — and how much ground
   she charted depended on which tick that landed on, which is to say on
   nothing the player did. The test that caught it had been passing on an
   ordering coincidence for months and broke when an unrelated change shifted
   the order by one tick. Of any policy, permission or prohibition, ask what
   reads it: gating the *assignment* leaves everybody already holding the job,
   and "already holding the job" includes every founder, every newcomer and
   everybody a save was written with.
37. **A synthesised `Codable` decoder does not fall back to a property's default
   value.** `Siege.Combatant` gained `kind` (a person, or a tower that fights
   from where it was built) with `= .person` written next to it, which reads
   exactly like "old saves get a person". It is not: Swift's synthesised
   `init(from:)` calls `decode`, not `decodeIfPresent`, so every raid saved
   before turrets existed would have failed to load — and a battle in progress
   is the one piece of state a player cannot shrug off, because the app is
   showing it to them when the update lands. The default value silences the
   *compiler*, which is what makes it convincing. Any new field on a type that
   is written to disk gets a hand-written `init(from:)` with `decodeIfPresent`,
   or it gets no default at all so the omission is loud. `Siege` itself already
   did this, one type up, for the same reason — the precedent was in the file.
38. **A derived property is computed once per comparison, and a sort compares
   n log n times.** `SettlementGround.Tone.order` read
   `GroundCover.allCases.firstIndex(of:)` and the same for `Skin` — two array
   allocations and two linear searches, per call, inside the comparator of a
   sort that runs **thirty times a second** for as long as the settlement is on
   screen. Sampling a running build put *every single sample* inside that sort.
   Nothing about it looked expensive: `allCases` reads like a constant and
   `firstIndex` like a lookup, and the whole thing is four lines in a struct
   that exists to keep drawing order stable. Two lessons, and the second is the
   one that costs sessions: a computed property used by a comparator is on the
   hottest path in the program, so cache what it reads and map-then-sort rather
   than sorting on the property; and **a frozen UI is not always a stuck
   simulation** — the catch-up here was running perfectly on its own thread
   while the main actor, which is the only thing that can *end* the overlay,
   was busy rebuilding two constant arrays. Sample the process before believing
   the symptom.
39. **The work that keeps a thing has to outlive the making of it — and a budget
   charged per colony cannot answer a cost charged per entity.** `LaborEngine`
   opened the mason's trade only while `constructions` was non-empty, so the
   moment a colony finished building, it drained its builders to zero and never
   staffed them again. `BuildingEngine.repair` went on asking for masons every
   interval and taking `max(1, 0)`. Fifty years later: thirty-three of
   fifty-five buildings below `derelictBelow`, six empty dwellings, thirty-four
   colonists sleeping rough beside them, four thousand materials in store and
   thirteen adults idle. `needingRepair`, commented "everything that wants a
   mason", **had no callers at all** — the same fault written down twice, and
   the cheapest thing that would have caught it. Two halves, and fixing only the
   first leaves the bug: *who* (a trade whose work is upkeep must be open while
   anything needs upkeep) and *how many* (wear is charged per building, so the
   hands undoing it are counted per building — a flat 9 % share is the right
   answer at exactly one ratio of roofs to townsfolk, and the game grows
   straight through it). Rule 14 from the other side. Measured, not guessed:
   break-even is about ten roofs to the mason, so `roofsPerMason` is six.
   Found by looking at a night with no lights in it, which is worth its own
   note — **a rendering feature that shows the world honestly is a probe**, and
   the dark houses were the sim telling the truth.
40. **A generated draft is not a file until the run that writes it has stopped.**
   `generate.py draft` rewrites its output after every batch, on purpose: a run
   that dies keeps everything it had collected. That safeguard has a second
   face — while the run is alive the file is a moving target, and `merge` read
   one at 30 entries while the generator carried on to 40. Nothing was
   corrupted, and that is the trap: the merge was clean, the tests were green,
   and ten entries simply were not there. Anything that consumes a file some
   other process is appending to has to prove it has settled first
   (`still_being_written`: same size *and* same mtime after a pause), because
   "the data looked fine" is not evidence when the question is whether all of
   it arrived.
41. **A vocabulary collected from content can only ever be too small, and it
   fails silently in the one direction nobody checks.** The generator learns the
   legal values of a closed field by reading what the shipped content uses —
   which cannot invent a value the game rejects, and cannot offer a value the
   game accepts and the content has never reached for. `crafting` is a real
   `WorkKind`; not one of 76 items used it; so a model asked for a tanning
   bonus was shown a list without it and wrote `work: "materials"` instead. The
   check caught the invention, but only after it was written and paid for, and
   the *legal* word was never on the table. Where the enum is small and settled,
   name the values that the code knows and the content has not used yet
   (`SUPPLEMENTS` in `content_kinds.py`) — a model offered the real word writes
   the real word. Building glyph `temple` was sitting in the same hole:
   drawable, and unreachable by anything a generator would write.
42. **`try?` on a whole-file decode turns three bad lines into a dead
   subsystem, and it will hide the next bug too.** Rule 9b named this trap for
   `items.json` and it was never fixed, so it fired again: three generated items
   claimed an `equipSlot` the game does not have (`body`, `tool`, `leg` — only
   `weapon`, `armor`, `trinket` exist), one `DecodingError` emptied the entire
   item table, and 218 tests failed without the word "item" anywhere near the
   cause. Recipes pointed at nothing; an armed garrison fought exactly as well
   as an unarmed one. **Absent and malformed are different questions**:
   `bundled(from:)` now returns the fallback only for `missingResource` and
   rethrows anything else. Within a minute of that landing it caught a second
   one nobody knew about — `MotionDefinition.Wave` used the synthesised decoder,
   so `{"amplitude": 1.7, "frequency": 1}` threw `keyNotFound("phase")` and the
   *entire motion bank had been loading as empty* while the build was green.
   Every optional-with-defaults field needs `decodeIfPresent`; the synthesised
   decoder demands all of them.
43. **"It builds" and "ContentTests pass" do not mean the registry loaded it.**
   Both were true of a motion bank that was decoding to zero entries.
   `ContentTests` walks the JSON files directly; the build only proves the Swift
   compiles. Nothing between them asks the one question that matters — *does
   `GameDataRegistry.bundled()` come back with the rows in it* — so a new data
   file needs a test that counts what the registry actually holds, the way
   `itemTableIsActuallyLoaded` does for items. Claiming a system works on the
   strength of a green build is claiming more than the evidence carries.
44. **A hand-kept list of closed vocabularies is the same mistake as a
   hand-kept schema, and it fails in the direction nobody looks.** `ENUM_KEYS`
   in the content checker was wrong three times in one day. `equipSlot` was not
   in it, so `body`/`tool`/`leg` sailed through and emptied the item table.
   `class` was not in it, so `combat.class: "armor_bonus"` did the same thing an
   hour later. The fix is to stop listing and start measuring: a key whose
   content uses **few distinct values, many times over** is closed, whoever
   remembered to say so. The hand list survives as a floor, because it covers
   the keys with *many* legal values (`type`, `look`) that measurement cannot
   see; reference keys are excluded, because `references.py` judges those by
   whether the thing exists. Measuring found three nobody had listed —
   `class`, `era_from`, `mode`.
44b. **Then make sure the check asks the vocabulary it was given.**
   `strange_values` took `allowed` as an argument and still gated on
   `ENUM_KEYS`, so the measured half was computed, passed in, and thrown away
   at the point of use. `class: armor_bonus` passed a check that had the right
   answer sitting in front of it. Widening a source of truth is only half the
   job; the other half is grepping for every place the old one is still named.
45. **A merge gate that runs a narrower suite than the content can break is a
   gate that says yes to the breakage.** `merge` ran `swift test --filter
   ContentTests` and reported "tests green" on sixty recipes that then failed
   `CraftingTests`, `ProductionChainTests` and `FoodChainTests`. `ContentTests`
   judges an entry's *shape* — bilingual text, ids, era gates — and never asks
   whether the things it names can be reached. Six recipes asked for `flint`,
   which is not an item, and for a stone mortar, which exists and is a tool
   rather than something you use up. The gate now runs every suite the content
   can break.
46. **A reference can hide in a dictionary's keys.** `references.py` walked
   values and so never looked at `{"materials": {"flint": 2}}` — the ingredient
   list of every recipe and every meal, where the id is the *key*. Same hole
   found three meals that could never be cooked: `fish` and `mushrooms` are
   perfectly good words and nothing in the game produces either, so those pots
   would have sat in the table for ever. The rule generalises past JSON:
   whenever a check walks a structure, ask which half of each pair it is
   reading.
47. **A bank is only as big as the selector that reaches into it.** Forty-eight
   motion clips shipped and seventeen of them had never once been drawn,
   because the choice among clips that fit equally well was `.first` over an
   id-sorted list. Seven clips serve a farmer at work, `digging` sorts first,
   and so every farmer in every colony dug — `reaping_scythe`,
   `threshing_flail`, `sowing` and `tilling_hoe` were content that loaded
   perfectly and could never be seen. This is the shape of rule 43 one layer
   up: the row was not malformed, the table was not empty, the *reach* was one
   deep. Two consequences. First, ties need a seed — here the colonist and the
   job they are on, so a field shows three different jobs and nobody flickers
   between frames. Second, the test has to ask the selector, not the data:
   "every clip declares an activity" passed all forty-eight while a third of
   them were dead, and only sweeping every ask the canvas can make found it.
48. **A specific clip must not be able to fall back into a general slot.** The
   fix for 47 gave clips a `serves_buildings` and let the workplace outrank the
   trade — and then kept a "use the building-specific ones rather than nothing"
   fallback for trades with nothing generic left. Every clip serving `trade`
   names a market, a trade post or a bank, so a trader standing anywhere else
   was handed the bank's coin-counting: a clip written for one room, drawn in
   every room. When the specific pool is all there is, the answer is the plain
   general body one level up, not the specific one used out of place.
49. **A checker that compares against the file cannot see what the decoder just
   learned.** `generate.py` rejects any field no existing entry has — the check
   that catches a typo'd key silently dropped — which is right, and which makes
   the *first* entry to use a genuinely new field indistinguishable from a
   typo. Adding `serves_buildings` to `MotionDefinition` meant thirty-five
   correct clips were reported as thirty-five faults. The fix is not to weaken
   the check but to let a kind declare `new_fields`: one deliberate line saying
   the Swift has learned this and the file has not caught up. Deleting the
   check would have cost the fault it exists to catch; a bypass that has to be
   written down costs one line and leaves a record of why.
50. **A dictionary keyed by anything but `String` or `Int` does not decode from
   a JSON object.** `upkeep: [ResourceType: Double]` looks exactly like
   `cost: Resources` and behaves nothing like it: without `CodingKeyRepresentable`
   Swift encodes such a dictionary as a *flat array*, so `"upkeep": {"food": 0.35}`
   threw `typeMismatch` — and because the registry rethrows now (rule 40), one
   new three-entry file took **every other bank down with it** and failed five
   suites that have nothing to do with conveyances. The repository already had
   the answer: every other cost in it is a `Resources`. Reach for the type the
   data layer already uses before writing a new shape for the same idea.
51. **A recipe consumes stock, not things.** Five generated recipes spent a
   blanket, a sharpened antler and a museum shard — items with `slot`
   `.equipment` and `.artifact`. They read perfectly and would have quietly
   destroyed a colonist's kit to make something else. `CraftingTests` catches
   it, which is why the merge gate runs it; the lesson for the *prompt* is that
   "use these ids" has to say **which of them are materials**, because a model
   asked to spend a list will spend whatever is on it.
52. **A `switch` on the enum is not reading the data, however much the comment
   says it is.** `SettlementGround.mark` chose a grain by `GroundCover` case
   while `GroundDefinition.texture` sat in the file being validated by the
   checker, written by the generator, and read by nothing — with the comment
   two functions below stating the opposite intent out loud ("a thirteenth kind
   of country is an entry rather than four new `case`s"). The colour honoured
   the rule and the grain never had. When a data file has a field naming a
   drawing routine, grep for the field: if the only reader is the definition's
   own initialiser, the field is decoration.
53. **A want list that is a union over the cookbook is a divisor, and content
   is what divides it.** `QuartermasterEngine.wantedMaterials` was the union of
   the materials of *every* workable gear recipe. That was seven ids while ten
   such recipes shipped; a content pass took the recipes to thirty and the list
   to eighteen, and the colony **stopped arming itself entirely** — because
   `StewardEngine.keepMaterialsComing` places one standing order per wanted
   material, the bench is finite, and eighteen trickles never reach the amount
   any one recipe needs. Nothing was malformed and no test of the content could
   see it: the failure was in an engine, caused by the *size* of a correct data
   file. Rule 14 again, one layer up — this time the entity count that grew was
   the content itself.

   The fix is the honest one rather than a cap: the bench makes **one thing per
   slot**, so want the materials of that thing. Two per slot, in fact — the best
   it could work, *and* the best it could actually finish, because a colony with
   a workshop and no bloomery will otherwise stock for chainmail for ever and
   never tan the hide for a coat. An unreachable best starving a reachable one
   is [[ef-unreachable-mechanics]] inside a single function.

   **The general form, and the one worth carrying:** before adding content to a
   bank, ask what reads the bank *by the whole*. A `for recipe in all recipes`
   that accumulates is a number that grows with the file, and somewhere
   downstream something is dividing by it.
54. **A count that saturates is not a measurement of activity.** The first read
   of `EraProbe` reported "the tech tree is exhausted in year 60 and research
   does nothing for the next 190 years" — from `researchedTechs.count`, which
   stops at the size of the tree because a *repeatable* study stays in the set
   after it completes. The colony was studying the whole time: twenty-nine
   further completions, roughly one every six or seven years. The wrong version
   is the more quotable one, and it would have justified flattening a cost
   curve that turned out to be correctly tuned. Before drawing a conclusion
   from a number going flat, ask what that number is *able* to do — a set's
   size cannot exceed the set, and a probe that prints one is measuring the
   ceiling, not the work.
55. **`String(format:)` with `%s` shifts every argument after it.** The same
   probe printed a colony with zero settlements and thirty-one people in them.
   Neither was true: a Swift `String` bridged for `%s`, and a `Double` handed
   to `%d`, misalign the varargs on arm64 and every column after the mistake is
   another column's memory. Twenty minutes went into the simulation before the
   format string was suspected. In Swift, build a table with interpolation and
   padding; `String(format:)` earns its place for floats and nothing else.
56. **A neutral default has to be the *neutral* value, not zero.**
   `Bearing.edgePoint(along:spread:)` took `spread` as a 0…1 roll and defaulted
   it to 0 — which is not "no spread", it is *full spread to one side*, so
   every arrival that did not pass one was a quarter of a map off its own
   bearing. Caught by a test asserting east is east. When a parameter's
   identity value is in the middle of its range, the default is the middle.
57. **A shared constant becomes a bug the moment the thing it measures stops
   being uniform.** Every siege ran `Siege.stepsTotal` steps — three bandits
   and a tribe's warband alike — and two other numbers were derived from it:
   `meleePerStep` divided by it so that a line delivers its weight exactly once
   across a fight, and the canvas's beat divided by it so a volley lasts one
   step. Giving fights a length of their own broke both silently in opposite
   directions: a long siege would have landed its line's weight three times and
   drawn its beats three times too fast. When a constant is promoted to a
   variable, grep every division by it — each one encoded an assumption that
   the constant was the whole truth.
58. **A bench with no trade is a bench nobody can ever stand at — and it
   costs the colony for ever.** `ColonyBuilder.workKind(for:)` falls back to
   "whatever trade produces most of what this building makes", which answers
   `.idle` for anything that produces nothing and `logging` for anything that
   produces materials. Nine buildings therefore employed twenty-four people on
   paper and could be staffed by nobody at all — every energy building in the
   game, from the windmill to the fusion reactor — and because
   `ResourceLoop.staffingFactors` counts *every* building with `workers > 0`,
   all nine sat at `unstaffedFloor` (0.4× production) permanently, with
   consumption unscaled and nothing the player could do. Six more — the
   workshop, the foundry, the factory, the quarry — were staffed by the wrong
   trade for the same reason: the workshop was manned by woodcutters and no
   colonist whose trade is `crafting` had anywhere in the world to stand.
   `everyBenchCanBeFilled` is the guard. **State the trade; never let it be
   inferred from a by-product.**
59. **A sweep that walks every combination proves reachability in the API, not
   in the game.** `everyClipIsSelectable` walks activity × trade × building and
   passed on fourteen freshly written clips that no ask the simulation can
   produce would ever return — a clip written for the hunter's lodge and marked
   `crafting`, when the only trade ever posted to a lodge is `hunting`. The
   sweep asks what the *canvas can name*; the test that catches this asks only
   what the *simulation can produce*
   (`buildingClipsServeTheTradePostedThere`). When you write a totality test,
   write down which of the two it is.
60. **A gate that reads one stream reports "failed:" and nothing else.** The
   merge gate printed `result.stdout` on failure — so a test failure was
   legible and a *build* failure, or a second SwiftPM holding the lock, came
   out as an empty message under a headline saying the tests failed. Twenty
   minutes went into a content bug that was a lock. Print both streams, or the
   tool built to catch silent failures has one of its own.
61. **A vocabulary check knows the words; it does not know the grammar.**
   `SUPPLEMENTS["type"]` teaches the generator every string
   `EventEffect.init(from:)` switches on, which is what makes `unlock_tech` and
   `remove_pawn` reachable at all (rule 57). It says nothing about what each of
   them *reads*, so three drafts in a row passed every check and then failed to
   decode: `unlock_tech` with no `techId`, a `region_hazard` written in
   `region_kind`'s shape, a `remove_pawn` carrying a `count`. The first two are
   loud — the file will not load and every test that reads it fails at once.
   The third is the quiet one: `count` is not a `CodingKey`, so it decodes
   cleanly, takes **one** person, and the event that was meant to cost the
   colony two costs it one for ever. `EFFECT_SHAPES` in `content_kinds.py` is
   the grammar, taken from the decoder. **When you open a vocabulary, open the
   shapes with it.**
62. **Four spellings of one field, and only one of them was ever read.** The
   check written for rule 61 found forty-one of these in *shipped* content, none
   of them new. `damage_buildings` takes `strength`; twelve effects said so and
   eleven more said `delta`, `damage` or `amount`, every one of them ignored and
   every one of them falling back to `severity = 0.5` — so an authored landslide
   and an authored dam breach had always been exactly as bad as each other, and
   the numbers in the file were decoration. Seven more carried a `count` for an
   effect that already damages many buildings, and five a `selector` it has no
   place for. `EffectShapeTests` guards this in Swift now, by round-tripping
   each effect through the decoder and its own encoder: anything the encoded
   form has no place for is a key nothing reads. **No second list to keep in
   step — the decoder is the list.**
63. **A cull by array order drops the newest thing every time.**
   `maxVisibleBuildings = 30` was applied as `placements.prefix(30)`, so a town
   of seventy-nine drew what it built in its first twenty years and silently
   dropped everything after — including the roof the player had just paid for
   and watched go up. And the cut was inside `normalizedLayout`, which
   `AgentMotion` also reads for homes, beds and work posts, so those
   forty-nine buildings were not merely undrawn: nobody could live or work in
   them. **A frame budget belongs in the frame.** Cull by what is on screen,
   and when a budget still bites, keep what is nearest the middle of the view —
   a building leaves the drawing because you looked away from it, never because
   of when it was built.
64. **Two things sharing an archetype must not share a drawing.** Twenty-three
   of fifty-three buildings shared a `look`: five industries were one smoking
   block, four laboratories one glass one, and a player could not tell the place
   that builds lorries from the place that builds everything else. The tempting
   fix is seventeen more shapes; the fix that scales is composition, and the
   axes have to be **derived from the definition** so the difference is true —
   a clean industry raises no chimney however large it is, a building that keeps
   vehicles has a door one fits through, a building nobody works at night is
   dark. A random tie-breaker is worse than no tie-breaker: a coin toss on
   `bays` was itself making a 2-wide palisade and a 3-wide stone wall come out
   identical. `StructureVariant.signature` makes "no two are drawn alike" a
   thing a test can fail.
65. **A budget for a bank you have not measured is a guess, and the guess was
   wrong by twenty times.** `RoadEngine.trackThreshold` was sixty crossings —
   chosen to feel like "a busy lane wears a path inside a normal game". Total
   traffic across the *whole map* after two hundred measured years was **four**.
   Not one track could ever have been worn, in any world, ever. Rule 6 in the
   plainest form it takes, in a system written the same day as a rule about it.
   The decay compounded it: the first value erased three quarters of the
   evidence over a long game, on a four-journey budget. **Journeys between
   regions are rare** — a caravan every few years, an expedition when the
   council has hands to spare — so any threshold counting them belongs in single
   figures. `RoadProbe` is the instrument; run it before touching a number.
66. **A ladder that hands back its top rung has only one rung.**
   `RoadEngine.nextGrade` returned the best grade the world could reach, which
   sounds like generosity and is not: by the time a colony has traffic worth
   acting on it is modern, so the council laid **railways across bare country**
   and never built a road or a paved way in two centuries. Three of the four
   grades were content nothing could ever produce — the motion-bank shape (rule
   47) wearing a progression as a disguise. Return the *next* rung: a colony
   beats a path, levels it, paves it, and rails the route that has earned it.
67. **"Nothing was recorded" and "nothing happened" are the same number and
   different bugs.** A wiring test that asserts only `traffic > 0` fails
   identically whether the engine forgot to record the journey or the journey
   never took place — and the first cut of `RoadWiringTests` was the second: a
   caravan needs an escort, `canDispatch` refused an empty one, and the test
   read as a broken engine for as long as it took to look. **Assert the
   precondition first** (`caravans.count == 1`), then the thing you came for.
68. **A metric aimed at the wrong journey argues convincingly for breaking
   something that works.** `RoadProbe` reported a 5% saving through four rounds
   of tuning, and each round I changed a threshold to chase it. The roads were
   fine: the metric measured the longest journey to any *explored region* — a
   hex of wilderness at the edge of the map that nothing would ever build
   toward — while the roads between the towns were real and climbing the whole
   ladder from track to rail. The columns that told the truth were the ones
   added last, `busiest` and `routes`, because **a total says nothing about how
   it is spread** and a track is worn by traffic on one edge. Measure the thing
   the feature is *for*, and when a number will not move, suspect the number.
69. **A rate that only fires on an event is not a rate.** Roads were worn by
   caravan dispatches and expedition departures — thirteen of them in two
   hundred years, because supply only moves when somebody is short and the
   council only explores out of overflow. What actually wears a road is people
   going back and forth between towns that are near each other, which exists
   **as long as the towns do** and scales with how many live in them.
   `TradeRoute` looked like the answer and was a third dead end: `tradeRoutes`
   is empty in every world the harness plays, so that clause did nothing at all.
   When a system needs a background rate, find the thing that is *always true*,
   not the thing that happens sometimes.
70. **Editing a source file while its test build is running fails the build,
   not the test.** `input file ... was modified during the build` cost a
   twenty-minute probe run. Long measurements and appending to test files do
   not mix: let the build settle first.
71. **Fixing a saturated number by capping its source caps everything
   downstream of it.** `DiplomacyProbe` showed all five peoples pinned at
   maximum grudge, which is a real complaint: a figure every neighbour shares
   tells a people you have wronged from one you have not. The tempting fix —
   let *crowding* carry a people only to resentful, since being big is not the
   same grievance as being raided — reads well and took the measured war count
   from **67 in two hundred years to 2**, and fights from 92 to 53. The chain
   is crowding → grudge → `drift` pulls standing down → `standing < warStanding`
   → war, so a cap on the source is a cap on the conflict, and §8.5's whole
   finding was that a world nothing can anger has nothing in it. Reverted.
   **When a number saturates, attack the relief, not the source** — trade and
   marriage take three off a grudge that grows by eight a year, and §8.5 claimed
   they "work it off". They do not.
72. **Two changes, one measurement, and you cannot tell which did what.** The
   same probe run carried a genuine bug fix (a ceiling enforced at one of three
   places, so grudge overshot to 119) and a balance change made on a hunch. Both
   landed together; the numbers moved a long way; and separating "the overshoot
   is gone" from "the wars are gone" took reading the mechanism rather than the
   table. Change one thing per measurement, or write down in advance which
   column each change is supposed to move.
73. **A round-trip test proves nothing about a field that is empty on both
   sides.** `WorldState.roads` and `roadTraffic` had no `CodingKeys` case, so
   the synthesised encoder skipped them and the decoder never looked — **every
   road the colony built was thrown away on the next save** and came back an
   empty network. "Full round-trip is lossless" had been green over that bug
   since the day roads shipped, because the world it encoded had no roads in it
   yet. It only went red once the map began *generating* with ancient stone on
   it. A round-trip fixture has to carry a value in every field it claims to
   cover, and adding a stored property means adding it to the coding keys in
   the same edit.
74. **A gene that does not decide who has children is a label, not a gene.**
   `GeneProbe` measured two centuries: standing deviation 0.09–0.11, so there
   was plenty of variation, and a selection differential with **no sign at all**
   for any of the four dispositions. The reason was structural — `fertilityAt`
   returns a flat 1 through the middle of a life, and the two lifespan genes add
   their years *after* the fertile window shuts at forty to fifty-two, so both
   were invisible to selection by construction however large their coefficients
   looked. Before tuning a heritable number, check that the thing it moves
   happens **while people are still having children**.
75. **A newcomer rolled from a fixed distribution is a hole in the world's
   gene pool.** Every arrival — a settler party, an event's colonist, an
   outpost's founders — was built by `PawnFactory.generate` rolling
   `Genes.founder`, whose mean is exactly 0.5. So immigration reset the colony
   toward the middle every time somebody walked up the road, and it is a far
   stronger force than anything two hundred years of selection produces: all
   four means converged on 0.5 *even after* selection had been given real
   teeth. Anything that enters a closed system from "outside" has to come from
   somewhere the world actually models, or it is a leak into a constant.
76. **A guard that is right in general starves the one case it was never asked
   about.** `StewardEngine.canAffordToKeep` weighs a building's *materials
   production* against its upkeep — sound, and the reason a colony stopped
   building itself to death (rule 25). But a **warehouse produces nothing**, so
   a colony pinned at its materials cap was refused, permanently, the one
   building that raises the cap: being at the brim does not change the ledger
   the brake reads, so the refusal is stable for ever. Shelter already had an
   exemption for exactly this shape of trap. When a brake can refuse the answer
   to the problem the colony is actually having, the problem needs its own
   exemption, not a softer brake.
77. **A shared, finite queue with no share-out is a queue one party owns.**
   `CraftingEngine.maxOrders` is twelve. `StewardEngine.keepMaterialsComing`
   stood one *standing* order per wanted material — and `wantedMaterials` unions
   every building of every era the colony has reached plus everything the gear
   bench asks for, which is comfortably a dozen past the first age. So the
   council held the whole bench for ever, which silently did three things: the
   player's own orders were **refused** (`place` returns the settlement
   unchanged and the button just does nothing), `QuartermasterEngine` — which
   runs after it — could never queue a spear or a coat, and every material
   trickled at a twelfth of the bench's effort. Any queue an autopilot shares
   with the player needs a share, and the player's half must be the one that
   cannot be taken.
78. **A set sorted alphabetically is a priority list nobody wrote.**
   The same standing orders were walked in `wantedMaterials`' own order, which
   is `Set.sorted()` — so what the colony made first was decided by the first
   letter of an item id. Measured: a medieval colony at 600 of 600 materials
   could build **one** thing in the whole book, a well, because a warehouse
   wants four timber bundles and nothing had ever asked for them. When a list
   feeds a finite worker, order it by what it unblocks.
79. **A derived field added to a generated model is `nil` for ever in every
   world that already exists.** `Region.river` is written at generation, like
   the biome and the landform, so a save made the day before had no water on it
   and would have kept none — and `nil` is also the honest value for a dry hex,
   so nothing downstream could tell "this country is dry" from "this save
   predates rivers". The fix is a `SaveMigrator` step in the *same change*, and
   it is safe precisely because the field is derived: recomputing it from
   `(mapSeed, coord)` gives exactly the map the generator would have drawn, and
   the same map a newly explored hex on the frontier will get.
80. **A rate quoted per step in a fight whose length is decided by the fight is
   not a rate.** `meleePerStep` divides the line's weight by `steps` — one full
   weight across the fight — which is exactly right while the clock ends the
   fight, and a trap the moment the fight ends when somebody breaks: a line that
   can only ever deal its own weight cannot take a warband past
   `routAtShare`, so the fight **cannot end**. Measured with the clock taken
   out: ninety raiders against six defenders, eighty steps, 90 → 56 strength and
   three hundred more to go. If length becomes an outcome, every per-step number
   has to be re-read as a rate — or the clock has to stay as a backstop, which
   is what shipped.
81. **A filter on one side of a two-sided system is a system with one side.**
   `SiegeEngine.loose` filtered on `side == .colony`, so in every fight the game
   has ever run the raiders had **no ranged attack at all** — they walked toward
   people shooting at them and then swung. It reads as "the fighting is not very
   dynamic", which is a complaint about feel that turns out to be a missing
   half. Worth grepping for: any engine phase that names a side.
82. **Two circles drawn for different purposes will overlap somewhere.**
   `SiegeField.isInside` is `wallReach`, and the watch forms up at
   `formUpReach`, which is **smaller** — so the back rank of a well-manned line
   was standing inside the circle that means "among the stores", and a town of
   sixty was plundered through a line that never broke while a town of ten lost
   nothing. Being somewhere is not the same fact as having got past somebody;
   when a rule means the second, it has to ask the second.
83. **A standing order in a queue sorted by age holds its place for ever.**
   `CraftingEngine.workableBenches` takes the oldest workable order per shop,
   and a standing order (`wanted == nil`) never completes — so the first one
   ever placed owned that bench for the rest of the colony's history. Measured:
   fifty years of a council arming its people produced **seventeen weapons for
   sixty-eight colonists**, because the builders' standing orders for timber
   were older than every batch of spears. Anything finite must outrank anything
   endless in a shared queue, or the endless thing is the only thing.
84. **A decision remade from scratch every step is not a decision.** `aim`
   re-chose every fighter's target each action step off nothing but distance,
   so as the field moved everybody's nearest enemy kept changing: measured,
   **42–48 % of all marks changed from one step to the next** in a fight of
   sixty raiders, which is half the field turning round twice a second. It
   reads exactly as reported — *"dvě čáry lidí co se hýbají vedle sebe a sem
   tam někdo přiběhne nebo zmizí"* — and every individual step of it was
   correct. The fix is not a better rule for choosing, it is **hysteresis**: a
   mark is kept until it is gone or something is decisively better
   (`SiegeEngine.switchMargin`, two-thirds of the distance), which took the
   same fights to 8–13 %. Of any per-step choice, ask what it costs to change
   your mind; if the answer is nothing, the thing choosing has no intention,
   only a gradient. The second half is the same lesson upstream: everybody
   *wanting* the same thing converges a field however stable their marks are,
   so a warband musters with three purposes in it (`Combatant.Intent`).
85. **A `Dictionary` is not an order, and a sum has one.** `AssemblyEngine`
   added a colonist's six reasons with `terms.values.reduce(0, +)`. Swift draws
   a fresh hash seed per *process*, so the same six numbers were added in a
   different order on a replay and rounded one ulp differently — and a
   colonist standing one ulp from the line then voted the other way. Caught by
   "The same assembly reaches the same result twice", and the identical fault
   was already sitting in `loudest`, which picked the biggest term out of the
   same dictionary. Determinism is not only "the same rolls": **anything a
   dictionary iterates has to be walked in an order the program owns** — the
   enum's `allCases`, a sorted key list — before it is summed, compared or
   reported.
86. **A need is a satisfaction, not a complaint — read the field, not the
   name.** `PawnNeeds.hunger` counts *fullness*: `PawnEngine` decays it toward
   zero and `<= 0` is how somebody starves. `AssemblyEngine.hardship` read
   `hunger / 100` as suffering, so the assembly counted a colony with full
   bellies as the one desperate for change, and the test written alongside it
   set `hunger = 95` to mean "starving" and passed for the wrong reason. A
   green test proves the code and the test agree, not that either is right;
   when a field's meaning is not in its name, go and read the engine that
   writes it.
87. **A term has to be calibrated in both directions.** The vote's die started
   at `0.4 + U × 0.3` against biases that rarely reached 0.2, so the die
   decided and the reasons decorated — the fault rule 23 is about. Narrowing
   it to ±0.17 produced the mirror image: a trade favour of 0.4 could not be
   crossed by any doubt, and sixty loggers who had never felled a tree voted
   **60–0** on a hewing law. A term that nothing can cross is as dead as one
   that crosses everything. Write the arithmetic down next to the constants
   (`widestDoubt / 2 > widestLivelihood × greenShare`) and guard it with a test
   that reads the data, so the next law that stakes 0.9 on a trade fails in
   the suite rather than in a colony that votes as one body.
88. **A dependency graph orders things; it does not pace them.** Research was
   gated on `requires` alone, so the council took the **cheapest tech anywhere
   on the board** and a colony still living in the medieval era studied
   `computing` at year 110 and `space_program` at year 120 — and had all sixty
   techs finished by year 160 of a two-hundred-year game while three of its six
   ages were still ahead of it. A DAG says *what may follow what*; it says
   nothing about *when*, and a tree with no clock in it empties at whatever
   rate the colony banks knowledge. The pacing gate has to be a fact about the
   world — here `TechEngine.eraReach`, one age of reach, which is exactly the
   ladder `eras.json` needs because every era's key tech belongs either to the
   age before it or to the age itself (rule 66). What used to be "the tree ran
   out" becomes "the colony banks knowledge until it grows into the next age",
   which is a reason to grow.
89. **A fixture that omits the data the feature reads is a fixture for the
   fallback.** Every app test built its own two-building `GameDataRegistry`,
   and the day rooms started being furnished out of `fittings.json` those
   registries began laying out **empty rooms** — no bench, no bed, no station.
   The tests did not fail loudly: `stationSlots` returned zero places, a
   colonist posted to a bench fell back to a seeded spot on the floor, and
   "a posted colonist keeps their own station" failed as *non-determinism*
   rather than as missing content. The suite spent a day looking like a
   geometry bug. When a system starts reading a new bank, every fixture that
   builds a registry by hand is now testing the fallback path — give them the
   bundled bank (`TestBook.fittings`) or assert on the fallback deliberately.
90. **Measure the multiplier, not just the outcome.** Outlaw raids came out at
   eight in two centuries against sixty-three from peoples, and the obvious
   read is "the base chance is too small". It was not: `temptation` read
   **3.000 at the tenth, fiftieth and ninetieth percentiles** for two hundred
   years, because its haul term was capped at three and a colony passes that at
   about two thousand sacks. Doubling the base would have made a poor hamlet
   twice as likely to be robbed and left a rich city exactly as likely as a
   modest one — the same fault in a new place. Print the *inputs'* distribution
   before touching the rate: a rate that never fires is either a small chance
   or a chance multiplied by something that is always the same, and those want
   opposite fixes (rules 23, 54, 72).
91. **A content guard that walks the content directory cannot see text written
   in Swift.** `ObjectivesEngine` composed the player's whole *what should I do
   next* panel out of English string literals, and `ObjectivesPanel` printed
   them straight — for months, in a game with a test named "Every line of
   content reads in Czech as well as English". That test walks `GameData`, and
   an engine is not `GameData`. Every engine that composes a sentence is
   outside every content guard in the project: `ObjectivesEngine`,
   `StewardEngine.counsel`, `SiteOutcome.narrative`, each journal line written
   inline. The guard has to be a *test of the engine's output* — call it, sweep
   what it returns, and require `resolve(.cs) != resolve(.en)`. And assert the
   **coverage**, or a guard that quietly stops reaching half the sources reads
   exactly like a clean bill of health (rules 43, 78).
92. **Two lists of the same thing differ by the clause somebody forgot.**
   `placeableBuildings` and `buildableBuildings` sat eleven lines apart and
   were the same filter except for `|| $0.era == .earlySettlement` — so the
   canvas offered the hut and the farm and the drawer did not, and nobody
   noticed because each screen looked complete on its own. The fix is never to
   reconcile them; it is to delete one. If two surfaces answer the same
   question they must call the same function, and a second copy is a bug with a
   delay on it (rule 35's shape, applied to a list rather than a number).
93. **A doc comment that names a caller is a claim, and it is often false.**
   `ComfortEngine.isFreezing` — *"what the inspector shows and what the journal
   would report"* — was called by neither. `HaulEngine.waiting` — *"for the
   objective and the ledger to read"* — had no objective and no ledger. Both
   were written at the moment the surface was imagined and shipped before it
   was built, and both then read as finished work for months. Two greps find
   the whole class in a minute: view-model methods no view calls, and engine
   functions nothing outside their own file calls. Run them before writing
   anything new — half of what they turn up is not dead code, it is **a feature
   the simulation already has and the player cannot see**, which is this
   project's single most repeated bug.
94. **A guard on the writer is not a guard on the reader.** `items.json` had
   seventy-three entries saying `slot: equipment` and naming no `equipSlot`.
   Every schema check passed: the field is optional, the file parses, the
   registry loads them, the crafting panel lists them and the bench makes them.
   But `GameEngine.equipItem` requires *both* and silently returns the world
   unchanged, so eighty-nine recipes produced things that could never be
   equipped and whose every effect was therefore dead — for months, invisibly,
   with the player tapping Equip and watching nothing happen. Optionality in a
   model is a promise that **something** handles the nil; find the reader and
   check what it does when the field is absent. The guard belongs where the
   value is *consumed*, and the cheapest form of it is a content test that
   walks the bank asking "could this ever be used?" (rules 43, 91, 93).
95. **A rule that pins a quantity kills every rate computed from it.** The wood
   ran out on every long game, and the cause was two guards that each read
   correctly. `FloraEngine.fell` keeps `seedStand` bearing trees back so the
   valley can never be cleared; `reseeded` sets saplings in proportion to
   bearing trees, `bearers / bearersPerSapling`. Together: the axes take every
   tree the moment it bears, so bearing sits at **exactly 16 for a hundred and
   seventy years** (`WoodProbe`, seed 4242), so the seed term is 16/6 = 2 for
   ever — permanently under its own floor of 4. **The scaling term was dead
   code that compiled.** Wood supply was therefore a constant while the colony
   went 39 → 298 people; the shelf went 276 → 39 → 3 → 1, eight standing orders
   read "short of materials" for the rest of the run, and 123 of 411 recipes —
   thirty per cent of the book — were unmakeable. When something conserves a
   quantity, grep every rate derived from that quantity: each one is now a
   constant, and a constant against a growing town is rule 16. The fix is not a
   bigger number — it is a lever the player owns (here: a logger with nothing
   to fell plants instead, so supply scales with loggers).
