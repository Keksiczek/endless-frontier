# Backlog — what Keks has asked for, in one place

Everything requested, kept here so nothing is lost between sessions. The
ordering inside each section is my recommendation, not a promise.

Last updated: 2026-07-29.

---

## 1. The RimWorld line — everything is a pawn, everything is a thing

| # | Thing | State |
|---|---|---|
| 1.1 | Colonists are pawns with genes, a body, a life | **done** |
| 1.2 | Animals are pawns: body parts, wounds, illness, cold | **done** |
| 1.3 | Animals have a **stored position** and a think-step | **done** |
| 1.4 | Hunters take **named animals**; `deerHerd` retired to a view | **done** |
| 1.5 | Buildings have an **inside** — floor, walls, fittings, stations | **done** |
| 1.6 | **Mineable rock**: a massif of stone blocks you dig into | **done** |
| 1.7 | Pawn **needs that bite**: hunger, rest, warmth | **done** |
| 1.8 | A house is a **household**; sleeping rough hurts | **done** |
| 1.9 | **Haul jobs** — felled timber and cut stone carried to a store | **done** |
| 1.10 | Buildings are the truth: condition, damage, repair | **done** |
| 1.11 | Animals you can **tame**, and beasts of burden | **done** |
| 1.12 | Colonists carry **wounds by body part**, like animals already do | **done** |

## 2. What it looks like

| # | Thing | State |
|---|---|---|
| 2.1 | The ground stops being a spreadsheet of vertical strips | **done** |
| 2.2 | Fog falls off in steps instead of a black staircase | **done** |
| 2.3 | Buildings drawn bigger, the town spread wider (span 0.42 → 0.52) | **done** |
| 2.4 | Roof lifts off as you zoom in | **done** |
| 2.5 | Animals sized against people instead of against the canvas | **done** |
| 2.6 | Colonists huddling in the middle of town | **done** (own beds) |
| 2.7 | Battle was three enormous red blobs | **done** |
| 2.8 | Weapons visible in the hand — bow drawn and loosed, blade swung | **done** |
| 2.9 | An app icon | **done** |
| 2.10 | Ground still reads flat at a distance — wants light and shade | **done** |
| 2.11 | Seasons should change the *land*, not just its tint (snow lying, mud) | **done** |

## 3. The world beyond the valley

| # | Thing | State |
|---|---|---|
| 3.1 | **Trade** you can watch — traders with mules walking in | **done** |
| 3.2 | **Diplomacy** arriving as envoys rather than as a panel | **done** |
| 3.3 | Refugees from a neighbour's bad winter | **done** — and taking them in works: `visitors_refugees`, "take them in" costs 40 food and applies `add_pawn` twice |
| 3.4 | **Supply** between your own settlements — a caravan you can see leave | **done** |
| 3.5 | A visit the player can **answer** — accept the refugees, refuse the envoy | **done** |
| 3.6 | More **events**, each happening *somewhere* to *someone* | part done (3 disasters, 3 visits) |
| 3.7 | More **POIs** and more **items** | **done** (6 kinds → 12, 57 items → 71) |

## 4. Scale — a colony of sixty-five must still be a place

1. **A house is a household.** — **done.** Four sleepers to a tile, never more
   than the ledger claims; the roofless sleep badly and say so.
2. **Home is a place, not a pool.** — **done.** `Pawn.homeID`, a bed apiece.
3. **Districts.** — **done.** The colony fills its heart, opens a second
   quarter, fills that; a building whose quarter is full goes to the next one.
4. **Level of detail.** — **done.** Below zoom 1.5, people standing together
   draw as one group mark with a headcount and the commonest trade's colour.
5. **Manage by policy, not by pawn.** — **done.** `ColonyPolicy` on the
   settlement, set from *Standing orders* on the Council screen: a weight per
   trade (`.off` … `.priority`), the ration on the table, and whether an
   expedition may take hands off the trades you said matter. `LaborEngine`
   scales its own quotas by the weights and **renormalises** them — an
   unnormalised `.priority` means "only", and swallows the whole town.
   `LaborEngine.rebalance` moves one colonist per staffing pass, so a policy
   set on a town of sixty actually reaches it instead of waiting for sixty
   people to fall idle.

## 6. Asked for 2026-08-01 — "everything is blocks or pawns"

The through-line Keks keeps coming back to: **the world is made of things,
not of numbers with pictures**. Blocks and pawns, all the way down. Our
buildings are the one deliberate exception — they are pre-made blocks that
hold the items belonging to that trade, and a place colonists walk to in
order to work and to make things.

| # | Thing | State |
|---|---|---|
| 6.1 | The valley is lit in **vertical stripes** — relief noise never got rule 10 | **done** |
| 6.2 | The land is **too restless** — 2.5-minute day, sweeping shadows, slab lots | **done** |
| 6.3 | **Not everything is tappable** — buildings hit at a point, no trees/rock/piles | **done** |
| 6.4 | The **colonist card is taller than the phone**, close button off-screen | **done** |
| 6.5 | **Fights are invisible** — played at the tick's pace, one exchange per 7.5s | **done** |
| 6.6 | Fights have **no readable order** — phases, pairings, blows on the beat | **done** |
| 6.7 | The commonest fight (wolves turned back) wrote **no record at all** | **done** |
| 6.8 | Colonists **always faced right**, stiff-armed | **done** |
| 6.9 | A **river crosses every map** whether the biome wants one or not | **done** — `RiverShape.flows`, biome-weighted |
| 6.10 | **Buildings want to be bigger** — the town is not legible at a glance | **done** — span 0.52 → 0.58 and the camera opens on the town (1.7×), together ≈ +90 % per building |
| 6.11 | **A raid you fight**, RimWorld-style: real time, on screen, not resolved in the background — and the player may **take colonists in hand** if they want to | **done** — `Siege` + `SiegeEngine` + `SiegeCommandCard` |
| 6.12 | **More animals, more flora** — the valley is thin | **done** — see 6.12 note |
| 6.13 | **Flora is not tappable by kind** — a birch, an oak, a bed of flowers should each answer for themselves | **done** — trees by species, rock by kind, and every scenery prop by name |
| 6.14 | **Crafting wants to be better** — what is made, where, out of what, and by whom | **done** — `CraftOrder` + the `crafting` trade |

### 6.12 — what the valley was actually missing

Three things, and two of them were dead code rather than thin content:

- **Predators were never seeded.** `isPredator` is honoured everywhere —
  hunters skip them, prey flee them, they stalk the weak — and not one wolf,
  fox or bear had ever been put on a map. The wild was a pressure number with
  deer drawn next to it. `AnimalFactory.mix(for:)` is biome-weighted now and
  `hazard` brings a pack, so a frontier valley really is worse than home.
- **Trees only grew inside forest *deposits*.** A valley the generator gave no
  forest node to had **not one tree on it** — which is the plains, the coast
  and the tundra. There is a wild scatter now, and stands are mixed species
  instead of one flat block of pine.
- Scenery counts up by about half, and every prop answers when tapped.

Cost control: the wild is 2.5× bigger, so `AnimalEngine.advanceOneTick` moved
onto the think cadence with a `steps:` multiplier (rule 4). Everything in it
is a rate; only the death roll is compounded rather than multiplied.

### 6.14 — the supply half, which turned out to be broken

Chasing a failing coast test found a real one, and it is the project's
recurring shape: **quarried rock produced nothing at all**. Timber falls at
the stump and hewn stone falls at the face, but the third and commonest
working — a pick into an *outcrop* — took only `.map` back from
`FloraEngine.quarry` and dropped the yield on the floor. On any valley with
no massif (every coast, most plains) four miners ground nine clay banks to
nothing over four hundred ticks and banked nothing. Clay is the **only**
route to the kiln, so the whole ceramics branch of the crafting tree was
unreachable by working for it.

Fixed: `quarry` returns what broke and where, `ResourceLoop` drops it as
piles, and part-units are banked in `LocalMap.quarryCredit` so hard rock is
slow rather than free or impossible. Job posting also round-robins outcrops
by kind — in id order every granite bank came before every clay bank and the
assigner takes from the front, so clay sat behind a queue miners could not
clear.

### 6.11 — what "a raid you fight" has to mean

This is the one that changes the shape of the game, so it is worth writing
down before any of it is built. Today a raid is `BattleResolver.resolve` —
eight rounds of arithmetic inside one tick, settled before the canvas is
told anything, with the record replayed afterwards. That is why it can never
be *fought*: by the time you can see it, it is over.

What it has to become:

1. **The battle owns real time.** A raid suspends the ordinary tick loop and
   runs on the action-step clock at a pace a person can act at — a step every
   second or two — rather than resolving eight steps between two frames.
2. **Orders, not autopilot.** The default stays hands-off (the whole colony
   is run by standing orders; a battle should not demand micromanagement).
   But a tap on a colonist during a fight must be able to say *hold here*,
   *fall back*, *take that one* — and the resolver has to read those orders
   instead of picking the weakest defender by itself.
3. **Determinism survives.** The outcome may depend on player orders, but
   given the same seed *and the same orders* it must replay identically. The
   orders become part of the recorded input, not a hole in it.
4. **Leaving is allowed.** Backgrounding the app mid-fight must resolve the
   rest exactly as the current resolver would, so a battle is never a thing
   you must sit through.

### 6.14 — the making half

Crafting was instant, free of labour, and done by nobody: a recipe named a
workshop, the colony had to *have* a workshop, and no colonist could ever be
a person who worked in one — `WorkKind` had no `crafting`. The whole tree was
a vending machine bolted to the side of a settlement.

Now: `CraftOrder` is a queue on the settlement (make one, make five, or a
standing "always be making these"), `WorkKind.crafting` is a real trade that
`LaborEngine` staffs — but only while there is something on the bench, the
same guard `.building` uses — and `CraftingEngine.advanceOneTick` sinks
worker-ticks into the oldest order that can actually be worked. Skill and
numbers both matter; a master is a little over twice a beginner.

Things that had to be got right, each of which fails silently:

- Materials are spent **when the piece is finished**, not when it is started,
  or a half-made sword holds two ingots hostage across a save and a famine.
- An order that cannot be worked is **skipped, not blocking** — a colony
  waiting on iron still makes its arrows.
- Work banked against a bare shelf is **capped at one piece**, or the moment
  one ingot arrives the colony pops out the whole order at once.
- Every one of the 29 shipped recipes states no work cost, because there was
  none to state. `workPerUnit` derives one from what the thing is made of and
  whether it needs a shop, so nothing is free and nothing is unreachable.

### 6.15 — the bench, finished (2026-08-02)

The five loose ends from 6.14 and 6.11, closed:

| # | Thing | State |
|---|---|---|
| 6.15.1 | Crafters were never drawn **at the shop** — a trade is not a place | **done** — `JobKind.craftItem`, posted at a shop with an unpaused order |
| 6.15.2 | **One bench per settlement** — a second forge bought nothing | **done** — one bench per *kind* of shop, worked in parallel |
| 6.15.3 | Skill made a smith **faster and nothing else** | **done** — `ItemQuality` on the piece, rolled from the best hand in the shop |
| 6.15.4 | Beasts still resolved **instantly** — the commonest fight was the one you could not stand in | **done** — a pack opens a `Siege` like a raid |
| 6.15.5 | `GameEngine.craft` still **bypassed the bench** | **done** — deleted, and the tests moved onto the real path |

Quality is a property of the **piece**, not the definition: `ItemRarity` says
what kind of thing this is, `ItemQuality` says whose hands it came out of. It
reaches the fight — a masterwork blade really does hit harder and a masterwork
harness turns more aside — and armour still never makes anybody invulnerable.
Nobody is ever guaranteed a masterwork; that is what makes it one.

### 6.16 — the tail end (2026-08-02)

| # | Thing | State |
|---|---|---|
| 6.16.1 | Autumn went **purple every dusk** | **done** — the night wash was the most saturated layer in the stack |
| 6.16.2 | The ground still read as a **ruled lattice** | **done** — tiles dovetail instead of meeting on a line |
| 6.16.3 | Events, techs, quests, biomes and the five resource words were **English only** | **done** — 196 strings, CZ+EN |
| 6.16.4 | **Caravans and visitors** answered nothing when tapped | **done** |

Two things worth remembering from it:

- The night wash was `(0.03, 0.05, 0.12)` at 0.30 alpha — the strongest *and*
  most saturated layer over the ground, so every dusk dragged the valley
  toward blue. Over autumn, which is the one season whose earth is genuinely
  brown, brown plus that much blue is purple. Night should **darken**, not
  paint.
- Overlapping tiles by a third of themselves means **which tone is drawn last
  decides what the ground looks like** — and Swift dictionary iteration order
  is not stable, so the buckets had to be sorted or the valley would reshuffle
  its own edges every frame. See `SettlementGround.Tone.order`.

## 7. The frozen world (2026-08-02) — the biggest thing found so far

Measured on a fresh world, twelve thousand ticks, nobody touching it:

```
t=1000   pop=27  beds=30  cap=500  buildings=3  building=0  techs=0  era=earlySettlement
t=12000  pop=26  beds=30  cap=500  buildings=3  building=0  techs=0  era=earlySettlement
```

Two hundred in-game years: three buildings, no construction ever started, no
tech ever researched, still in the first era, every store pinned at the cap,
deaths only from old age. The colony was not dying — it was **frozen**.

Every link of the chain was reachable only from the UI:

- `activeResearch` is set nowhere but the tech screen → no tech → no era → no
  building unlocked.
- `GameEngine.build` is called nowhere but the build bar → not even the
  *unlocked* buildings were raised, including the hut that lifts the housing
  ceiling and the granary that lifts the storage cap.
- `CraftingEngine.place` is called nowhere but the crafting panel → the
  `timber_bundle` half the early buildings ask for was never made.

`StewardEngine` closes it: the council studies the cheapest thing it can
reach, keeps a standing order for building materials, and raises whatever the
colony is most short of — beds, then store, then food, then breadth. It acts
**only in the gaps**, so an explicit choice by the player is never touched,
and `WorldState.stewardEnabled` switches it off entirely.

After: pop 5 → 80, two eras, 31 techs, ~48 buildings by t=5000, then a
plateau where materials become the binding constraint.

### Two traps found while balancing it

1. **A reserve as a share of capacity is a trap.** Keeping 35 % of the
   warehouse back looks reasonable — but granaries multiply the cap, the
   reserve grows with it, and a colony whose income never changed can suddenly
   never afford anything again. Measured: capacity 500 → 2750 and the town
   stopped building for ten thousand ticks. The reserve is a multiple of the
   **cost** now.
2. **Founding buildings had random UUIDs.** `ConstructionEngine` already
   derived the id of a building it finished; `GameWorldFactory`,
   `ExpansionEngine` and `ColonyBuilder.place` used the `UUID()` default, so
   two worlds from the same seed came out with the same buildings under
   different ids. Caught by a determinism test on the steward, not by anything
   aimed at it.

### Still open after this

- **Births do not keep pace with old age.** With beds and food no longer
  binding, population peaks near 80 and drifts back to 40 while the only
  deaths are old age. That was always true; it was simply unreachable behind
  the frozen ceiling.
- Era stops at `ancient` with the whole tech tree researched — the later era
  milestones want population or settlement counts the colony does not reach.

### 6.6 — what shipped, so the next pass builds on it rather than over it

`SettlementBattle` now has named phases (`marching`, `volley`, `melee`,
`breaking`), a caption naming the phase and the standing tally, raider ↔
defender pairings, a rank that thins as the colony holds, per-defender harm
bars read from the record's wounds, and blows that land on the beats the
resolver actually wrote. The playback is 20 real seconds whatever tick the
fight happened on, and `BattleReportCard` can replay it. All of that is
presentation reading a `BattleLog`; 6.11 is the simulation half.

## 5. Housekeeping

- Notifications — permission state is now **visible and settable** in Settings.
  If it says *Refused*, that is an iOS record only the user can undo.
- Animals: stutter, stacking and un-tappability all fixed 2026-07-29.
- The old English content (events, buildings, techs) is still untranslated;
  everything new ships CZ+EN in the same change.

---

## Rules any of this must not break

Every one of them has cost a session at least once:

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
