# Rules — what has already gone wrong, and must not again

<!-- Extracted from BACKLOG.md 2026-08-13 | 35 rules -->

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
