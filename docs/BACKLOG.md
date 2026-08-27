# Backlog — what Keks has asked for, in one place

Everything requested, kept here so nothing is lost between sessions. The
ordering inside each section is my recommendation, not a promise.

Last updated: 2026-08-05.

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

## 8. Played it — 2026-08-02 feedback

Keks played the build. Three things, and the third is a design pivot:

| # | Thing | State |
|---|---|---|
| 8.1 | **No challenge.** Nothing kills, nothing is scarce | part done — see 8.4 |
| 8.2 | **Combat does not aim well; the rounds feel strange** | **done** — you pick who and they go |
| 8.3 | **Real-time walking, not rounds** — "I go somewhere and do something. The enemy comes, we prepare, then we kill him if we can" | **done** — the pivot, 8.4 |

### 8.4 — the pivot, as built (2026-08-03)

Fighters have positions the **Core** owns: `Siege.Combatant` (side, `at`,
strength, target, down) and `SiegeField`, which is the battlefield geometry
moved out of the app. `AgentMotion` stays presentation-only (rule 5) — it now
*reads* a colonist's position instead of interpolating one, which is the whole
difference. The precedent followed was `Pawn.currentJob.position` and
`HaulEngine.haulPosition`, exactly as §8.3 said.

Everything that used to be a step index is a distance now:

| Was | Is |
|---|---|
| `step >= approachSteps` | nobody is within `SiegeEngine.reach` yet |
| raider *i* fights colonist *i* | each picks the nearest enemy and walks to them |
| `Posture.cover` = 0.35 / 1 / 1.2 | `SiegeField.cover(at:)` — **cover is a place you stand** |
| `posture == .giveGround` spends grain | a raider inside `wallReach` is standing in the stores |
| all damage on the single weakest | every raider hits the person in front of them |

`Posture` no longer says how much of the wall counts; it says **how far out the
line will go** (`Posture.reach`), and the wall is read off the ground people are
standing on. Pressing costs the wall because it walks out from behind it.

Orders: a tap picks a colonist, the next tap sends them — `Siege.Order.moveTo`
or `.engage`, recorded on the siege exactly as the posture is, so the same seed
plus the same orders still replays to the same dead.

**What the retune actually changed** (measured, `DangerProbe`, not guessed):

- `attackerDamagePerStrength` 0.14 → 0.24. Spreading blows across a line made
  them slacker, so this is what puts the cost back.
- Raiders **work on whoever is already hurt** (`nearest(preferringWeak:)`),
  mildly. This is the mechanism that produces a casualty instead of twelve
  people evenly and harmlessly bruised.
- A held line **closes the last two steps** (`closingPoint`). Before it, a
  raider fighting your neighbour was a hand's breadth away and a third of the
  line never swung at all, because "the enemy is outside the muster ring".
- **Nothing knits while a wound is open** (`PawnEngine`). The flat 0.3-a-tick
  recovery ran unconditionally *on top of* the bleeding, so an untreated wound
  closed as fast as a tended one and the healer's trade bought nothing. Same
  recurring shape as rule 6: a system whose bite is cancelled by a number
  nothing gates.

One raid, twelve bare-handed colonists, measured end to end:

```
str  30  wall  0  →  hurt 2  worst −33        str  30  wall 50  →  hurt 2  worst −13
str  60  wall  0  →  hurt 4  worst −93        str  60  wall 50  →  hurt 4  worst −37
str 120  wall  0  →  2 dead, hurt 8           str 120  wall 50  →  hurt 8  worst −43
```

Survivable, expensive, and the wall is worth building.

### 8.5 — why there were no fights to be dangerous (2026-08-03)

Measuring the *rate* rather than the fights found two more of the project's
recurring shape, both worse than the combat numbers were:

**No tribe had ever raided anybody.** Two hundred measured years, six peoples,
final standings `0 / 0 / 0 / +75 / +80 / +82`, and every one of the 26 fights in
the run was wolves. Grudge had exactly one source — a quarrel over hunting
grounds — gated on standing already being **below −15**, while standing drifts
toward a compatibility of 62 or better at 12 % a year. Nothing could make a
people angry that was not angry already. `DiplomacyEngine.crowding` gives
friction a source that does not require hostility: a colony that outgrows its
neighbours is taking somebody's share of finite land, game and water. Trade and
marriage work it off, so it is a pressure to manage rather than a countdown.

**The wild never answered the colony.** Predator pressure is capped by the era
(8, +5 an era), so a pack was ten strong whether the settlement was five people
or four hundred — the first thirty years of a real world produced four fights
and a worst wound of *nothing at all*. The pack's weight now scales with how
much there is to come for (`WildlifeEngine.packPerColonist`), the watch that
turns out scales with the colony, and `attackChancePerPressure` went 0.00025 →
0.0004: a pack roughly every three and a half years.

Measured after, same seed, 200 years: **58 fights** (was 26), a genuine enemy on
the map (standings `−51 / −6 / −1 / …`), and wounds landing in the first thirty
years instead of never.

Still open under 8.1: **nothing has yet killed anybody but old age** in a long
run. A colony of four hundred shrugging off a warband of a hundred and forty is
correct, so the honest next step is scale — what a *late* colony is threatened
by — not another multiplier on the early game. Food is no longer pinned at the
cap in every run, but it is not scarce either.

### 8.1 — the measurement

Fresh world, 12 000 ticks (200 years), untouched:

```
battles = 26     live-siege ticks = 26     tribes = 6
deaths  = { old_age: 106 }        ← every single one
food 2500/2500 · colonists hurt at the end = 0 · broken = 0
```

Twenty-six fights in two centuries and not one death from anything but old
age, with nobody even carrying a wound. Four separate causes:

1. Nothing kills — no battle, starvation, cold or beast deaths at all.
2. A fight ends inside roughly **one world tick**: a forty-strong militia
   vastly outmatches a wolf pack of strength ~10, so it is over before it can
   be watched.
3. Food is pinned at the cap for two hundred years.
4. `SiegeEngine.wallShare` caps at 0.85 and a modest palisade already turns
   most of a raid aside.

Levers: `SiegeEngine` (`linePerStep`, `attackerDamagePerStrength`,
`fortificationHalfPoint`, `fortificationCeiling`),
`WildlifeEngine.attackChancePerPressure`, `DiplomacyEngine.warChance` /
`warStanding`, and `MedicineEngine` for how fast wounds close. **Do not just
multiply them** — the fix is that a fight should be survivable but expensive,
and the wound/body-part system already exists with nothing to do.

### 8.3 — what the pivot costs

What survives unchanged: the siege as live saved state, orders as recorded
inputs, a step fought once by whoever reaches it first, and offline
resolution identical to watched resolution.

What changes: the *unit*. Positions per combatant advancing per step, contact
by proximity rather than by round index.

The line it crosses: fighters' positions must move **into the Core**.
`AgentMotion` is presentation only (rule 5, load-bearing). The precedent to
follow is `Pawn.currentJob.position` and `HaulEngine`'s `haulPosition` — both
Core-owned positions that already exist. Make it deliberately; do not let the
renderer start writing state.

Order: positions into the Core → move/target orders on tap → *then* retune
difficulty. Balancing the old shape first is work thrown away.

## 9. Asked for 2026-08-03 — scale, charm, and a journey with a middle

| # | Thing | State |
|---|---|---|
| 9.1 | **Expeditions are instant** — you send them and a number comes back | **done** for the valley's places — see 9.4 |
| 9.2 | **Houses are too small**; the hut is comically full of colonists | **done** — 9.5 |
| 9.3 | **Buildings are all alike**, outside and in | **done** — 47 buildings, 29 shapes |
| 9.4 | Cannot quickly find a colonist, or equip one from their own card | **done** — 9.8 |

### 9.9 — three kinds of danger, and the one that gets worse as you get better

The last of §8.1: after everything, a long run still killed nobody but old age.
Not because the fighting was weak — a warband kills twelve bare-handed
colonists — but because **every threat scaled with the colony's own strength**.
Four hundred people with walls and iron turn back a hundred and forty raiders
and they *should*; a bigger warband is the same answer written larger.

Three things added, each a different shape:

- **Sickness** (`PlagueEngine`, `plagues.json`, five strains CZ+EN) runs the
  other way. It comes for a town *because* the town is big, crowded, fed by
  trade and sleeping four to a room. No wall keeps it out. What helps is what a
  prosperous colony puts off: healers, herbs, a clinic — and the willingness to
  shut the gates and lose half a season of work, which is the one order the
  player has (`OutbreakCard`). It stands on `AilmentKind.sickness` and
  `MedicineEngine`, which existed with nearly nothing to do.
- **Bandits** (`BanditEngine`) are the raid that belongs to nobody. Every fight
  came from a *relationship* — a people who hated you, or a wood you had not
  hunted — and both can be mended, so a colony with good neighbours and a quiet
  forest had no enemies however rich it got. Outlaws are drawn by a full granary
  and cannot be negotiated with: there is no standing to mend and no tribe to
  charge. Spears and a wall make you a poor target, never an impossible one.
  **They come from somewhere now** (2026-08-22, `OutlawCampEngine`): three
  camps live on the map from the first tick, each with a kind (deserters,
  starving, a walled hold), a strength of its own that grows while nobody
  troubles it, and a hoard of everything it has carried off your granary. A
  raid walks in on the bearing of the hex they live on, spends the camp that
  sent it, and a party can be sent out to burn them out and bring the plunder
  home — after which they lie low for a season and fill up again. Still not a
  faction: no standing, no grudge, no peace to buy.
- **Wolves stopped looting like a warband.** `Siege.carriesOff`: a warband came
  with sacks and a pack took a sheep, and both walked off with eight to
  thirty-five per cent of the granary. With a pack every three years that
  quietly emptied colonies that were never short of hands.

Measured, same seed, 200 years — and this is the first run in the project's
history where the tally is not one line long:

```
before   deaths { old_age: 274 }                                  pop 463
after    deaths { old_age 219, starvation 132, sickness 10,       pop 476
                  battle 1 }        4 epidemics · 91 fights
```

Two tuning notes worth keeping. The first cut of the sickness let the odds grow
with population without a ceiling: a town of 350 caught something every five
years, 782 people took sick across two centuries, and the place starved because
it was never well enough to farm. `sizeCeiling` and a four-year respite fixed
it. And starvation only came down to something survivable once the wolves
stopped robbing the granary — the two looked like one problem and were not.

### 9.5 — the hut that held thirty people

The joke Keks saw had a cause, and it is CLAUDE.md rule 8 again: **two numbers
for one thing**. `BuildingDefinition.housing` said a hut held thirty and fed the
population cap; the RimWorld layer gave that same hut *one tile* and
`sleepersPerTile` beds. So the ledger counted twenty-six people the building had
nowhere to put, and every one of them slept rough for ever at −8 mood.

`housing` is a **flag** now — non-zero means people live here — and
`BuildingDefinition.sleepers` is the number, derived from the ground the
building covers times `floors`. Both the ledger (`ResourceLoop.housingCapacity`)
and the beds (`HouseholdEngine.beds`) read it. An apartment block holds a
hundred and eighty because it is four by three and **five storeys**, which is a
thing you can point at.

Scale, all of a piece:

- Colony grid **18×18 → 24×24** (576 tiles).
- Every footprint up a tile in each direction: hut 1×1 → **2×2**, a works 3×3 →
  **4×4**. All forty-seven at the new sizes use 83 % of the grid, and no real
  colony builds one of each.
- The span on screen is *unchanged*, so a tile is smaller and a **building** —
  two to four tiles across instead of one to three — comes out larger. The hut
  gains half its size again; the camera opens at 2× instead of 1.7×.
- Dwelling costs fell with their capacity (hut 10 → 4 materials). Beds per
  material are roughly what they were: the fix was about geometry, not about
  making housing three times dearer. Without this the colony missed the first
  era milestone — caught by `StewardTests`, not by anything aimed at it.

### 9.6 — forty-seven buildings, eleven shapes

Thirty-six of the forty-seven stated no `look` at all, so the renderer *derived*
the shape from the numbers — and the numbers cannot tell a farm from a granary
from a well, because all three are "food or storage". Thirteen came out as the
same lecture hall and nine as the same smoking block.

Every building names its own archetype now, and there are **twenty-nine** of
them (was thirteen), no bucket above four. Seventeen are new and live in
`SettlementTrades`: farm, lodge, sawmill, forge, well, wall, barracks, clinic,
aqueduct, tenement, dish, rail, tanks, dam, lab, turbine, vault. Interiors are
furnished per archetype, so the inside of a forge is an anvil and a hearth and
the inside of a clinic is beds and a shelf.

Guarded by *"Every shipped building says what it looks like"* — deriving is the
fallback for content that has not caught up, and shipping content should never
need it.

### 9.7 — a place with something in it

A visit used to be: walk out for a few ticks, roll once against `hazardChance`,
add resources from a table, walk home. The walk was simulated at eight steps a
tick and the **destination was a number** — which is the whole of "you send them
and it is instant". Nothing was found, nobody could fail, and it happened to no
one.

`SiteEncounter` is a handful of **things** in places: caches worth prising open,
traps waiting to be sprung, and something living in there. `SiteVisitEngine`
walks the party between them on the action clock exactly as `SiegeEngine` fights
a raid — nearest thing first, anything alive before anything locked — and what
comes home is what they actually got the lid off. A party driven out comes back
with less. Scouting finally does something: a wary hand spots the floor before
standing on it.

The card shows the beats as they happen and the canvas draws the chests, the
snares and the thing breathing in the dark.

### 9.8 — finding one person, and arming them

The colonists panel reads as a *workforce* — grouped by trade, which is right
for seeing the shape of a town and useless for finding the one person who is
bleeding. It has a name field and five lenses now (hurt, unhappy, unarmed,
idle), and while either is in use the trades collapse into one flat list, worst
off first, because grouping is for browsing and a search is not browsing.

Equipping was **item-first**: open Items, find the sword, pick a name out of a
menu listing everyone in the town. At sixty people that menu is a wall, and it
is the wrong way round — you decide about a person, not about a sword. There was
no way at all to arm somebody from their own card; the only thing the card could
do was take a thing off. `EquipmentStrip` is three slots you tap, on both the
colonist row and the canvas inspector, offering only what actually fits and best
quality first.

### 9.10 — out of the valley (2026-08-04)

The other half of 9.1, and the last button in the game. `SiteEngine.interact`
took a region id and handed back an outcome in the same tick: nobody went,
nobody was gone, nobody could fail, and a lost city three regions away cost
exactly what one next door did.

`RegionExpedition` + `RegionExpeditionEngine`: hands leave the colony and are
*not there* — the labour engine notices — for `travelTicksPerHex` a hex each
way. At the far end the party works a `SiteEncounter` through the very same
`SiteVisitEngine` the valley's places use (`work(_:site:party:step:)` was split
out for it), with the guardians stiffened by the region's own hazard. What comes
home is what they opened, and the site's own table pays out **in proportion to
how much of it they cleared** — a party driven out brings back less.

### 9.11 — the duplication, and what work is aimed at

Three things Keks named, all one bug at heart: **the entity layer was invisible
in the places it should have been most obvious.**

- `AgentMotion.workplace` checked the deposit nodes **before** `currentJob`. A
  logger the job board had sent to a named tree was drawn standing on the
  abstract "forest" blob — and the comment three lines below already claimed the
  job outranked everything, while the code above it quietly won. Job first now,
  then a *real thing* of the right kind (a mature tree, a rock face, a
  non-predator), and only then the node.
- The renderer drew **every** node, so a "Forest · 87 %" glyph sat in the middle
  of an actual wood and a "Stone" blob on top of a massif. Entity-backed kinds
  are skipped now: a wood is trees, a massif is blocks. Fields and herb beds
  keep theirs, because a tilled plot really is one thing.
- The hit test offered those same phantom nodes, so tapping a wood selected
  "Forest · 87 %" instead of the birch under your thumb.

### 9.12 — houses

One drawing served every dwelling: a hut and a longhouse were the same gable at
two sizes with one window in the same place, so a street read as a stamp
repeated. A house now varies by roof pitch and whether it is thatched or
shingled, by **bays** (a long house is more rooms, not a stretched hut), by
which windows have a light behind them, by a chimney that smokes after dark, and
by what its household left in the yard — a woodpile, a washing line, a fence or
a lean-to. All fixed per building seed, so a house does not change its own roof
between frames.

## 10. Played it — 2026-08-05 feedback

| # | Thing | State |
|---|---|---|
| 10.1 | **Everyone swings a sword**, including the sixty who own nothing | **done** — `9f8cc01` |
| 10.2 | **A hit should be a hit**: real time, you see it land, blood from it — not blobs of colour everywhere | **done** — `ff06bf4` |
| 10.3 | **No dynamism** — people do not act on needs, surroundings or their own trade | **done** — `2f82c9d` |
| 10.4 | The **steward never sends expeditions** to explore | **done** — `2f82c9d` |
| 10.5 | **Temperature is cosmetic and does not match** the biome, for people or animals | **done** — `3cb1473` |
| 10.6 | Maybe **slow the pace**, once the above are in | todo — wants a phone in hand, not a probe |

Each is specified in `docs/handoffs/HANDOFF-2026-08-16.md` §2 with the diagnosis rather than the
wish. The short version of the two that matter most:

- **10.2 is a drawing problem, not a simulation one.** `SiegeEngine` already
  moves real fighters and lands blows on named people; `SettlementBattle` still
  paints the *aggregate* — a seam across the line, sparks at a computed front,
  bars floating over heads. Draw the impact between the two bodies that are
  touching, put blood on the person and the ground, and delete the seam.
- **10.3 had a precise cause: needs were satisfied by teleportation.** A hungry
  colonist ate out of the store wherever they were standing; nobody walked to a
  granary or a fire. Needs bit but never caused a *decision*, which is exactly
  what "no dynamism" means. Built as `Errand` + `ErrandEngine` rather than as a
  `JobKind`: an errand is a person's own business and has to *interrupt* work,
  not queue behind it for the same slot.

### 10.7 — what 10.3 and 10.4 turned over

Three things nobody was looking for, each found by measuring rather than by
reading:

1. **The same seed founded a different colony every launch.** `Pawn.init`
   defaults `id` to a fresh `UUID()` and the four founders were taking it, so
   per-entity randomness — which comes from `(mapSeed, entity.id, tick)` —
   diverged from tick zero. Every determinism test in the suite was comparing
   headcounts loose enough to pass on luck, and `DangerProbe` had never twice
   measured the same world. Rule 2, in the one place nobody looked: world
   creation. Fixed in `3cb1473`; the probe numbers below are the first
   reproducible ones the project has had.
2. **Defection was rolled per neighbour, not per colony.** `0.30 × however many
   peoples you had met`, with nothing capping the count. Invisible while the
   colony never explored; the moment the council started charting regions a town
   at 90 morale with a full granary bled from fifty souls to thirty with no
   deaths but old age. Rule 6 from the other side — not a rate too small to
   reach its threshold, but a rate multiplied by an entity count nobody bounded.
3. **A standing order is not a player's choice, and must not be priced like
   one.** `LocalPOIEngine.chooseParty` refuses to strip a settlement "bare",
   meaning *two people left standing* — right for a party the player asked for,
   ruinous four times a year for ever. The council keeps under an eighth of its
   adults abroad and only looks over the hill out of overflow.

### 10.8 — the famine, and what was under it — **done** (2026-08-06)

Two hundred years, seed 4242, on the commit before this one: **182 dead of
starvation** against 134 of old age, granary at 7 of 2000 for most of the run.

The arithmetic, once anybody did it. Food came out of `PawnEngine` as
`skill × 0.15 × season × gatherFactor`, and `gatherFactor` read how full the
`.field` deposits were. Those regrew at `capacity × 0.0009` a tick while each
farmer drew `harvestPerWorker` = `0.45` off them. Two field nodes of ~220 is
440 capacity, so the fields regrew **0.396 a tick against 0.45 a farmer** —
equilibrium under *one farmer*. Any real colony stripped its fields inside a
season and left `gatherFactor` pinned at `depositFloorFactor` (0.35) for the
next two centuries, and every extra farmer made it worse. Rule 14 exactly: a
rate multiplied by an entity count nobody bounded. It never *could* scale with
mouths, because the ground it drew on was a fixed patch of wilderness.

### 10.9 — what replaced it: a food chain (2026-08-06)

Asked for as *"lidi farmí přímo určité suroviny, ty mohou mít v sýpce nebo
skladu, ale pak musí ještě z toho kuchaři uvařit jídlo"* — and it is also the
fix, because the ceiling stops being a patch of wild ground and becomes **the
farms the colony builds**, which is a thing it can do more of.

`ResourceType.food` survives and means what every reader of it already assumed:
**cooked meals in the larder**. `ErrandEngine`, the famine, trade, caravans,
expedition provisions, events, laws and quests are untouched. What changed is
where the number comes from.

| Was | Is |
|---|---|
| a `.field` `ResourceNode` a farmer's presence subtracted from | `Crop` — a plot of tilled ground that ripens and is reaped |
| `production[.food]` on a farm building | `BuildingDefinition.plots`, derived from the footprint like `sleepers` |
| a farmer's skill becoming meals where they stood | grain/roots/greens dropped at the plot, hauled in like timber |
| hunting banking `.food` and a hide | `meat` off the carcass; the hide is what is left over |
| — | `WorkKind.cooking`, a `cookhouse`, and `meals.json` (8 meals, CZ+EN) |
| an uncapped `stockpile` | foodstuffs share the granary's ceiling; the rest goes over |

Measured, same seed, 200 years — **and the harness decides the answer**:

- unattended (`TickEngine.advance`, what `StewardEngine` runs): starvation
  **182 → 5**, colony alive, food near the cap;
- `DangerProbe` (driven by `BalanceHarness.autoPlay`, which builds "the one it
  has fewest of" and never consults the steward): starvation **182 → 451**,
  population 108, food 0 of 1850.

Both are wanted. Keks's call, 2026-08-06: *"umřít na hlad bez zásahu klidně
můžou"* — a colony nobody manages is allowed to starve. Manage the fields and
the famine is over; don't, and the valley buries you. Before this change neither
was possible, because no amount of management could move the number.

Five things this turned over, each of which had to be found by running it:

1. **Nobody could ever become a cook.** `assignIdleAdults` only touches the
   idle, and `rebalance` returned early whenever `policy.trades` was empty —
   which is every colony the player has not given orders to. So a town where
   nobody is idle (every town past its first decade) could not move one person,
   and a trade with *no members at all* stayed at zero for ever. Six hundred
   ticks, a cookhouse, 269 sacks of grain and a larder at zero. Rule 9c from
   the side nobody had tested; `rebalance` follows the engine's own quotas now.
2. **A farm in disrepair deleted its own harvest.** Plots were gated on
   `BuildingEngine.isWorking`, so four standing farms' plots fell 26 → 20 → 8 →
   0 and the colony starved with the buildings still there. Ground does not
   stop existing because the roof leaks.
3. **The council never built ahead of demand.** Its food clause fired on a thin
   larder, and a larder is a *buffer*: two farms fed seventy-four people at the
   cap right up to the season they didn't, then eighty-seven died. There is a
   clause on **capacity** now — `plotsWanted(for:)` against `plotsStanding` —
   and `FarmEngine.peoplePerPlot` is worked out from the crop table rather than
   guessed, with a test that fails if the crops stop being able to reach it.
4. **The kitchens burned the staple and hoarded the rest.** Picking the richest
   meal outright meant every pot took grain, greens piled to 2 852 against 17
   grain, and the colony went extinct with a full store of salad. Meals are
   scored against the *pressure* they put on the shelf, so cooks use up what
   there is most of.
5. **A chain has a new way to kill everybody.** Two valves, both load-bearing:
   a colony with no cookhouse cooks over the fire at half rate, and a colony
   with no cook eats raw off the shelf at `ErrandEngine.rawFoodValue` — hungry,
   not dead.

### 10.10 — the canvas catches up, and the card stops lying (2026-08-06)

Keks, playing it: *"nesedí popis pawna — je uvnitř, píše to venku. Chci to mít
přesně: co je v simulaci, to na plátně."*

He was right, and it was two bugs wearing one coat.

**The card and the canvas answered different questions.** `AgentMotion.workplace`
had been taught to prefer `pawn.currentJob` (§9.11); `activityLabel` had not, and
still read `(activity, assignedWork)`. A farmer with no plot job was *drawn at a
spot inside the farm building* and *described as out in the field*. The label
reads the job now — and names the thing: "Tending the grain — 6 % ripe",
"Reaping the roots", "At the fire in the cookhouse".

**And there was no field to be in.** `JobBoard` posted nothing for plots or
kitchens, so no farmer ever *had* a plot job. Now:

| # | Thing | State |
|---|---|---|
| 10.10.1 | `JobKind.workPlot` / `.cookMeal` posted, ripest plot first | **done** |
| 10.10.2 | `Job.cropID` — *this* furrow, not "the farm" | **done** |
| 10.10.3 | The farmer who was sent to a plot is the one who reaps it | **done** |
| 10.10.4 | Field nodes retire once a colony has plots (the §9.11 mistake, pre-empted) | **done** |
| 10.10.5 | `SettlementCrops` — tilled beds, shoots, ears, and a plot half-reaped | **done** |
| 10.10.6 | The farm glyph's **fake** five-row field, deleted | **done** |

Two things worth keeping from it:

- **The plots were invisible for a whole build**, and existed the entire time.
  Laid out over the farm's whole footprint, every one of them landed under the
  building drawn on top of it. `reconcile` gives the barn the lot's top row and
  the plots the rows below. The same shape as §9.11: the entity layer was right
  and the drawing put something else in front of it.
- **The farm was already drawing a field** — five ruled furrows, identical on
  every farm, always looking ripe, knowing nothing. Two numbers for one thing
  (rule 8) in the renderer rather than the engine. Deleted; `Crop.halfWidth` /
  `halfHeight` come off the plot, so the drawing cannot drift from the ground.

### 10.11 — the weather, checked (2026-08-06)

Asked for at the same time. `Climate` is sound — one shift per biome, read by
people, beasts and the status strip alike — and the seasonal bases reach past
the comfort bands they are measured against. The table it produces:

```
biome        shift  spring summer autumn winter
plains           0      11     31      9    -22
forest          -2       9     29      7    -24
desert          11      22     42     20    -11
tundra         -13      -2     18     -4    -35
mountains       -8       3     23      1    -30
coast            4      15     35     13    -18
```

Two holes, both now closed:

- **Nothing read the top of the range.** Crops had a `coldFloor` and no ceiling,
  so a desert summer of 42° did nothing at all to a field of greens. There is a
  `heatCeiling` now (greens 28, grain 34, roots 37) and `growthStep` measures
  how far outside the range the day is in *either* direction.
- **A farm sowed the same rotation everywhere.** Tundra spring is −2° and its
  autumn −4°, against a greens floor of +3 — so a quarter of every northern
  farm was under a crop that grows at an eighth rate. `CropSpecies.sown(inPlot:
  climate:)` sows what the land will carry: roots on the tundra, the full
  rotation at home. A biome that does not change what a farm plants is a colour.

## 11. Asked for 2026-08-07 — a village you know, at a pace you can watch

| # | Thing | State |
|---|---|---|
| 11.1 | **Slow the game down** (was §10.6) | **done** — 11.4 |
| 11.2 | **Fewer colonists**, so you have a bond with each one; grow gradually from nothing | **done** — 11.4 |
| 11.3 | **The map does not look like a map.** The tiles on the world map read as nothing — not terrain, not country, not a place | todo — 11.5 |
| 11.4 | **Battle and attacks** are to be reworked again | todo — 11.6 |
| 11.5 | **The colony starves in its second century** (found by probe, not asked for) | **done** — 11.9 |
| 11.6 | **Newcomers**, so a colony can grow at all | **done** — 11.11 |
| 11.7 | **The weather must be alive**, not four constants | **done** — 11.12 |
| 11.8 | **The world map must look like a map**, and follow its climate | **done** — 11.13 |
| 11.9 | **Bigger maps**, and places that are landmarks in themselves | **done** — 11.14 |

### 11.4 — the pace and the size of a colony, as built

Two complaints and one cause: *"začíná se od nuly"* was not true. A colony
arrived **nineteen strong** and was twenty-nine people by year ten, so the first
decade — the only decade in which you can hold everybody in your head — was
already a crowd. And a year went by in an hour of real time, so the people in it
aged while you were reading their card.

Three numbers, and it is worth saying which does what, because they were all
being asked to do the same job and none of them could:

- **`realSecondsPerTick` 60 → 120.** The pace lever, and the only one that moves
  nothing else: every rate in the game is per *tick*, so this halves how fast the
  world runs in real time and leaves every balance number exactly where it was. A
  year is two hours now. `maxOfflineTicks` halved with it, or the thirty-day
  catch-up ceiling would silently have become sixty (rule 6, in its quietest
  form: a cap in ticks is a cap in wall-clock time only until a tick changes).
- **The founding party 19 → 7** — five named founders and the two who came with
  them. This is most of the fix. It is the difference between meeting a colony
  and meeting a crowd.
- **`sleepersPerTile` 3 → 2.** A colony of thirty-seven had *a hundred and
  forty-seven beds standing empty*, so housing was never a claim on anything and
  `headroomFactor` — which is supposed to bend the growth curve as the roofs
  fill — never had anything to bend against. A hut is a household of eight now.

And one that had to be measured rather than reasoned about. **`baseBirthChancePerTick`
0.0018 → 0.0016**, not the 0.0012 the first cut used: at a third off the colony
was *below replacement*, peaked at 51 in year 90 and then fell to 19 with the
granary at zero by year 140. Births and old age are both per-capita, so their
ratio does not depend on the population — there is no self-correcting
equilibrium, only growth or collapse, and the only thing that damps it is
housing. A birth rate is therefore not a "size" knob, and treating it as one
buys a colony that dies quietly two centuries in.

Measured, seed 4242, same probe (`GrowthProbe`, `EF_PROBE=1`):

```
            before                  after
year 0        19                      7
year 10       29                     14
year 20       37                     25
year 50       52                     41
year 100      76                     48
year 200      81  (peak 95)          72  (peak 88)
starvation     5                      0
```

The first fifty years are a village and they take a hundred real hours to live
through, which is the whole of what was asked for.

### 11.7 — children come from bonds, not from a birth rate (2026-08-07)

Keks: *"ideálně by nemusela být porodnost, protože děti se budou rodit, když se
dva osadníci budou mít rádi… ať je to sociálními vazbami a simulací, ne
koeficientem."* And, on the fragility that came with it: *"líbí se mi, že to může
failnout na základě nějakého RNG… takovéto stavy jsou ok."*

Every fertile colonist used to roll a private dice each tick, and being married
multiplied it by 1.6 — so two people who had never met had children at nearly the
rate of two who had spent a life together. The roll is on the **bond** now:
`PopulationEngine.conceive` walks the `.partner` relationships, and a couple's
chance is their bond's strength, both their fertilities and both their moods. A
child takes after **both** parents (`Genes.blended`), and the bond remembers when
it last had one (`Relationship.lastChildTick`), which is what spaces a family.

Fertility is a person's own, not a shared window: `fertilityAt` runs from
`17 − gene×2` to `40 + gene×12` and **tapers over the last quarter** rather than
ending on a birthday.

What this cost, in the order it was found — every one of them a hard cliff that
only showed up as "the colony is gone by year 130":

1. **Everyone in the founding party was exactly twenty-five.**
   `Pawn.defaultAdultAgeTicks` is 25 years and the five named founders stated no
   age, so they left the fertile window in the same year.
2. **A founding party of 16–40 is too old to found anything.** A bond takes years
   of meeting to reach the wedding threshold, so somebody who lands at 38 marries
   at 44 and is past it. Measured: four married couples, not one of them able to
   have children, colony gone by year 70. Founders are 18–28 now and
   `PawnFactory` generates 16–30.
3. **Weddings *are* the growth curve now**, so 0.10 a meeting was a bachelor camp.
   0.22, and the age gap narrowed to 12 so couples stay fertile *together*.
4. **The era ladder was gated on populations this colony will never see** —
   `ancient` wanted 60 people against a village of eighteen. Rescaled
   (60/200/600/1500/4000 → 18/45/110/260/600). Rule 6, in the place it always
   hides: a threshold nobody re-checked after the thing it measures changed
   scale.

5. **The biggest one, and rule 6 again: friendships could not reach the wedding
   threshold at all.** `SocialEngine` ran *one encounter per ten colonists* per
   tick, while the pairs who might meet grow with the square of the population
   and `decayPerTick` eats every bond at the same rate whatever the size. In a
   village of seventeen a given two people met once every two and a third years
   and gained about two points net — **forty-five years to reach a wedding**,
   which is to say never. Every marriage in the colony was made in its first
   fifteen years, by the founders, and nobody born after year twenty ever
   married. One encounter per **two** colonists: a courtship is a couple of
   years, and it stays a couple of years as the town grows.

   This is the shape rule 6 keeps producing and it is worth naming in its social
   form: *a rate that is linear in population against an opportunity space that
   is quadratic in it is a rate that shrinks as the world succeeds.*

   It had a tail, and the test that caught it was asking the right question:
   five times the meetings at the same journal odds is five times the small
   talk, and a **wedding** was pushed out of the diary's buffer inside six
   hundred ticks. `chatJournalChance` and `quarrelJournalChance` cut by five.
   Anything that changes how often a thing *happens* has to change how often it
   is *written down*, or the journal stops being a chronicle and becomes a feed.

6. **The wedding age-gap rule went away** (Keks: *"to pravidlo nedává moc
   smysl"*). It existed to stop marriages that could not have children, and
   `fertilityAt` says that far better now — an older pair simply have few
   children rather than being forbidden a marriage. Two rules for one fact, and
   the blunter one was also the one stopping people marrying.

7. **So did the population gates on the eras** (same message). Progress is
   tech, prosperity and settlements now: things a player acts on, rather than a
   headcount a village will never reach.

Where it landed, seed 4242, 200 years: founded 12, **31 by year fifty**, then a
long decline to six. The social layer is no longer the limiter — nine couples,
four to six of them fertile, a real chance every tick.

**The new limiter is food, and it is measured: 17 dead of starvation against 37
of old age, with the granary at zero for eight of the twenty decades.** This is
*not* the famine §10.8 fixed — that was a colony of three hundred outgrowing its
fields. This is a colony of ten to twenty-five that cannot keep a *cook*:
`LaborEngine`'s 0.07 share of a dozen adults is less than one person, so a
village that loses its cook eats raw off the shelf (`ErrandEngine.rawFoodValue`)
until it starves. The whole labour quota table is shares of a workforce that used
to be eighty and is now twenty, and every trade in it needs re-checking against
the number of people who actually exist. First thing next session.

### 11.9 — the colony died because it built a kitchen (2026-08-07)

§11.7 handed the next session a diagnosis: *"a colony of ten to twenty-five that
cannot keep a cook"*. It was the right symptom read onto the wrong cause, and
the way to find that out was to put a second table under the growth curve —
`GrowthProbe.theChain`, which prints the food chain link by link, because
`food = 0` is four different colonies in trouble that want opposite fixes.

What it showed, seed 4242, and it is not what anybody expected:

```
year   pop  adult  farm  cook  plots want   shelf   food  hungry
  40    28    21     4     2      14    7    1132   1148       5
  80    25    21     4     2      14    7    1158   1150       0
 100    23    18     4     1      14    6    1147      0       9
 160     8     7     2     1      14    2    1156      0       3
```

Fourteen plots for a colony that wants six. Eleven hundred units of raw harvest
on the shelf, at the granary's ceiling, every single decade. A cook on the staff
the whole way. **And `storage[.food]` at zero for a hundred years.** Nothing
upstream was short of anything. Two defects, both rule 6, and neither of them
the quota table:

**1. A comfort cap on a need that kills.** `ErrandEngine.furthestWorthGoing`
(0.55) was written to stop a mild need eating a colonist's whole day. But the
valley is a unit square and work happens all over it — a logger's tree, a
scout's fog, a beast at the treeline — while the granary stands wherever the
town put it, and the colony grid alone is `span × √2` = 0.82 corner to corner.
Anybody whose day took them past the cap was refused the errand **every tick,
from `hungryBelow` all the way down to zero**, and starved beside a full store.
Eighteen dead of hunger with the granary at 1148 of 1150. Now
`desperateHunger` / `desperateWarmth`: below those, distance stops being a
*reason* while staying a *cost* — the walk is exactly as long as it was, which
is the only thing the cap was ever for.

**2. A bank capped below the batch it was saving for.** `CookingEngine` banked
`kitchenProgress` and capped it at one batch of the **cheapest** meal — 0.8 —
so a kitchen with a bare shelf could not hoard a decade of effort. Sound idea,
wrong batch. `best(for:)` chooses the meal by what the shelf can *spare*, not by
what the morning's work can *afford*, so a full shelf reached for the stew at
`work: 2.0` every tick — and one unskilled cook banks `0.8 + 1.0 = 1.8`. The
`while` loop never turned over once, and the gruel it could have afforded was
never considered. Cap is `bankCeiling` now: one batch of the **dearest**, which
is the same "no hoarding" rule stated so the dearest can actually be paid for.

Two details are why it hid for eighty years:

- **It needed a cookhouse.** Without one, stew is filtered out of the table and
  the dearest reachable meal is 1.2, which the old 0.8 ceiling *could* pay for.
  Every colony that had not built a kitchen yet ate fine. The colony died
  because it built one.
- **It needed exactly one cook.** Two unskilled cooks clear a stew in a single
  tick. So it appeared only as the village shrank — which read exactly like the
  labour-quota story §11.7 wrote down.

`cooksKeepUpWithFarmers` was green throughout: it divides a *thousand* cooks'
hands by the dearest meal. A batch is not divisible, and the rate that matters
is **one** pair of hands against **one** batch. That is the new test —
`aLoneCookCanReachTheDearestMeal`, plus `oneCookIsEnough` which runs it.

**3. The quota floors — §11.7's own item, which was also real.** `LaborEngine`
shares are shares of a workforce that used to be eighty. At seven adults, half a
person is `0.071` and cooking's entire share is `0.07`, so `rebalance` — which
moves nobody for a gap worth less than half a body — could never make the move
at all. `LaborEngine.floors` puts one farmer and one cook before any share
applies. A trade standing *at* its floor is never a surplus, so a village cannot
answer "nobody cooks" by taking its last farmer and then answer "nobody farms"
by taking the cook back. Standing orders still win: `.off` beats the floor, and
the colony eats raw off the shelf, which is a valve that already exists.

Three smaller things fell out of it:

- `rebalance` gated on `adultCount >= 4`, which switched the slow hand off for
  exactly the hamlets that cannot spare a missing cook. Two now — one to move
  and one to move them from.
- A trade with no work left in it (masons after the last scaffold, a priest with
  no temple, the watch with no wall) was skipped by *both* halves of the scan, so
  its members were unmovable. They are draftable now — but only while a floor is
  short, or draining the masons after every project would make the next one slow
  to man.
- The eviction loop walked `counts`, a `Dictionary`. Swift does not keep that
  order stable between runs, so two trades tied on surplus handed the colonist to
  whichever came out first — a different colony from the same seed. Sorted by
  `rawValue` now. Rule 2, hiding in a loop nobody was looking at.

Where it landed, seed 4242, 200 years: **0 dead of starvation against 46 of old
age** (was 18 against 38), the granary between 1134 and 1150 every decade of the
two centuries instead of empty for ten of them, and a peak of 30 rather than 28.

**What is still open, and it is now the only thing:** the colony peaks around
year forty and declines to nothing by year two hundred, entirely of old age.
Food is no longer any part of it. See §11.10.

### 11.10 — what is left when nothing is broken

With §11.9 in, seed 4242 over two centuries is: founded 12, **30 by year forty**,
then a steady decline to three. `starvation: 0`. `old_age: 46`. `sickness: 2`.

Nothing is *failing* any more. The colony is simply running below replacement,
and the numbers say where it is and where it is not:

```
year   pop  adult  cook  plots want   shelf   food  hungry  beds  headroom
  40    30    23     2      14    8    1146   1148      4     82     0.402
  70    22    19     1      14    6    1161   1147      2     82     0.535
 100    23    18     1      14    6    1166   1134      1     82     0.518
```

- **Not food.** The granary sits between 1134 and 1150 every decade of the two
  hundred years, and the shelf is at its ceiling throughout.
- **Not the roofs**, which is the thing rule 19 would have you check first:
  eighty-two beds against a population of twenty-three, and `headroomFactor`
  between 0.40 and 0.55 — a factor of two, not the factor of twenty a colony
  pressed against its housing would show.
- **Not the social layer** either, which §11.7 already cleared: seven to ten
  couples standing, three to six of them inside the fertile window, and a real
  per-tick chance on the best of them.

It is the ratio itself. Roughly **0.2 births a year against 0.24 deaths**, held
there by the arithmetic in `PopulationEngine.conceive` — `perTick` is
`1 / (yearsToConceive × ticksPerYear)`, halved again by headroom, multiplied by
a readiness slope and by the product of two fertilities. A closed founding party
is a positive-feedback loop and this one runs a hair under unity, so it decays
on a two-century timescale however well everything else works.

This is §2.4 of the handoff, and it is **not a bug to fix — it is a design
question nobody has answered**. Keks has said plainly that a colony being *able*
to fail is wanted (*"líbí se mi, že to může failnout na základě nějakého RNG"*),
so the target is a world where a village can die and a well-run one can grow, not
one where growth is guaranteed. Right now every village dies, which is the other
half of the same failure.

If it is picked up, answer it with **newcomers rather than a higher birth
chance** — `visitors_refugees`, the tribes and `add_pawn` all exist and are
event-rare. Raising `perTick` buys a colony that grows because the dice were
retuned; arrivals buy a colony that grows because people came, which is the same
number and a different game. Do not start until Keks says which.

### 11.11 — newcomers, and the two things that were not weather or a map (2026-08-07)

Keks, asked which way §11.10 should be answered: *"jj newcomers — rng event že
přijde člověk a chce pomoct, nebo můžeme zajímat ostatní co na nás útočí,
věznit je a konvertovat, nebo se k nám lidé přidají, zvandrovalci poutníci"*.

Three doors, and the difference between them turned out to be the design.

**The traveller asks.** `.wanderer` already walked in, told the evening's
stories and left — and `decision(for:)` returned nil for them, so they were the
one visitor who could not change anything. `visitors_wanderer` is the card.

**Settlers do not ask.** A new `VisitorKind.settler`, drawn by what the colony
looks like from outside: fourteen food per head, two beds standing empty, morale
above 55. All three, because any one alone is a number that drifts into range.

They carry **no card**, and that is the load-bearing decision.
`StoryPlanner.expireDecisions` applies *none* of a decision's effects when the
moment passes — deliberately — so a colony whose only door to growth needs a tap
is a colony that dies every time nobody is watching. One door has to survive an
empty chair. It also makes prosperity the growth lever and gives rule 19 a
second, literal meaning: beds are no longer merely permission to grow, they are
the reason somebody comes.

**Captives are taken.** A broken raid leaves people on the ground.
`CaptiveEngine` takes a third if there is room, and from there it is what the
place is like to live in: fed and in good heart and they come round over about a
decade; hungry and wretched and they go over the wall. Only from an attacker
that was *people* — the alternative is a colony that converts a bear. A
`Captive` is a separate list, not a flagged `Pawn`: `population` is derived from
`pawns.count` and forty-odd call sites walk that array, so the first one that
forgot to skip a prisoner would have married them off. Bounded at one per nine
colonists (rule 14).

Measured, seed 4242, 200 years: **peak 51 around year sixty, oscillating 28–51**
against a decline to three. Beds are the ceiling and `headroomFactor`
self-limits near 60% of them, so the player decides how big by what they build.

### 11.12 — the weather, alive (2026-08-07)

`Climate.base(season) + shift` meant every spring in a colony's life was exactly
11°. Three things are laid over it now, all off `(mapSeed, tick)` so a save
reloaded mid-winter comes back to the same winter: **the year**, milder or
harder and holding from one spring to the next; **the spell**, a month or so of
one sky, eased between anchors rather than switched; and rarely **the year
people talk about**, a fat tail, because an even spread never produces the
winter anybody remembers — it produces a slightly colder average.

One place to change and five things came alive from it, exactly as §11.8
predicted: `FarmEngine.growthStep` already measured the distance outside a
crop's range at both ends, so a hard year is a bad harvest; `ComfortEngine`
decides who freezes; `AnimalEngine` which beasts suffer; and the status strip
says which kind of year it is out loud.

`Climate` carries `ticksPerYear` rather than taking it as a parameter, so the
length of a year is stated once (rule 8) and `temperature(_:)` keeps the
signature its ten callers already had. A climate with **no world behind it** is
the ordinary run of things and has no weather — which is the right answer for
`CropSpecies.sown(inPlot:climate:)`, a decision a farm makes once about the
country it stands in and must not re-make every warm fortnight.

One bug found by its own test, and worth writing down: `wobble` shifted a
**53**-bit value and divided it by 2^52, so it returned −1…3 rather than −1…1
and every swing ran to three times the number written beside it. Caught by the
sky jumping 5.6° in a tick against a 5° spell. A generator whose range is wrong
makes every constant that reads it a lie — the range is asserted directly now.

### 11.13 — the world map is geography, not confetti (2026-08-07)

Keks: *"tiles na mapě nevypadají vůbec jako mapa"*, then *"mapa musí vypadat dle
klimatu — poušť, hory atd… ať je variabilní, živá a různorodá, aby mapy nebyly
stejné"*, then *"aby mapa světa dávala větší smysl"*.

It was not the drawing. `MapGenerator.rollBiome` rolled **every hex
independently** out of `biomeWeights`, so a desert sat beside a tundra beside a
coast and no feature was ever larger than one hex. A map made of independent
samples cannot look like a map however it is painted — and this is the same
family as rules 10 and 10b, one level up: a field that does not know what it is
a field *of*.

Biomes come off three smooth fields now — how high, how wet, how warm — sampled
at the hex's position on the plane. Because the fields are continuous,
neighbours get nearly the same answer, so mountains come in ranges, deserts
gather in the dry heat and a coast is a line rather than a speckle. Elevation
runs on the longest wavelength with a second finer octave, so a range has
foothills instead of one smooth dome.

Where each country belongs is **data**: `BiomeNiche` in `biomes.json` says what
ground a biome wants and how hard it insists, and the biome with the best fit
wins the hex. A biome with no niche is still placed by weight, so adding one
without an opinion keeps working. The homeland is drawn the same way among the
countries `homeland_weight` nominates — otherwise the one hex the player looks
at most is a desert capital ringed by forest.

Still a pure function of `(mapSeed, coord)` with no global pass, which is what
the endless map rests on: a hex ten rings out is generated on its own, in any
order, and always comes out the same.

Measured — **neighbour agreement 77%, against about 20% for independent rolls**
— and `MapProbe` (`EF_PROBE=1`) prints the thing so somebody can look at it:

```
        ~ . . ░ ░ ░ ~ ~ ~
      ♣ . ~ . ░ ░ ░ ░ . ~ ~
   ♣ ♣ ♣ . . . ~ ~ . . . ~ ~ ~
 . . ♣ . . . . ~ ~ ~ ~ ~ ~ ~ ~ ~
    . . . . . ♣ ♣ ♣ ♣ . ~ ~ ~
        . . ♣ ♣ ♣ ♣ ♣ ♣ ♣
```

### 11.14 — a bigger frontier, and places that are somewhere (2026-08-07)

Keks: *"udělej mapy 2-3× větší, je to malé — nemusí být víc POI, jeden dva"*,
and *"ty biomy nebo mapy by mohly samy o sobě být POI — kráterové jezero,
průsmyk."*

**The frontier.** `mapRadius` 3 → 5, which is 37 hexes to 91. The map has always
been endless and grown as it is explored, so this is the frontier you *begin
inside* rather than the size of the world — and at radius three that frontier
was one ring wider than the first expedition.

Every site chance came down with it, and finding the right numbers turned over a
bug that had been there all along: `specialChancePerRing` was added to **all five
site kinds independently**, so a ring-*r* hex got `4 × r × 0.015` of extra site
chance in total. At radius three that was invisible; at radius five it put
**twenty-nine specials in a starting world**, and on an endless map it passes 1.0
somewhere around ring twenty — every far hex a ruin, for ever. Rule 14 in the map
generator. The bonus is *split across* the kinds now and capped at
`maxRingBonus`, so the deep frontier is rich rather than paved.

**The places.** A region that is only ever "forest, hazard 3" is a colour with a
number. `RegionFeature` is what the land at a hex actually *is* — a pass, a
crater lake, an oasis, a gorge, a peak, a plateau, a fen, a headland — and every
one of them is **read off the ground** rather than rolled, because §11.13 put
elevation, moisture and warmth fields there. Keks asked for exactly this: *"vše
budou jen věci v simulaci, která bude mít nějaké podmínky, takže by to nemělo
být tak hard."* Nothing is authored per hex and a feature can never contradict
its country, because it *is* its country. The region keeps its own forged name,
so two crater lakes are still two distinct places.

Calibrating the thresholds is the part worth remembering, and it is rule 6 twice
in one sitting. The first cut guessed, and was wrong in **both directions at
once**: a peak had to stand 0.10 above all six neighbours, when the 99th
percentile of "this hex minus its highest neighbour" is **+0.018** — so no peak
could ever exist — while a plateau had to be flat to within 0.22, which is the
**33rd** percentile, so every high hex was one. Measured result: twenty-nine
plateaus in a world, and never a pass or a crater lake. Then oasis and headland
turned out to be dead the same way, on the moisture field, across ten thousand
hexes.

The fix was to stop guessing magnitudes and define the sharp features as **local
extrema** — a peak is simply higher than everything it touches — which needs no
magic number and cannot drift when a field's scale is retuned. `MapProbe.relief`
prints the percentiles the remaining thresholds are set against; read it before
touching `MapGenerator.feature`. Guarded by "Every landform the game can name is
one the ground can make", swept over forty seeds.

### 11.8 — the weather has to be alive too

Keks, immediately after: *"stejně tak počasí atd, vše bude proměnlivé, ne pevně
dané, dynamické dle simulace."*

Today `Climate.base(season)` is four constants and a per-biome shift, so every
spring in a colony's life is exactly 11 °C. It is *consistent* and it is not
*weather*. What it wants, in the same shape everything else in this project has
moved to: a temperature that wanders around the season's mean, years that are
harder or milder than usual, and the odd winter people still talk about — all
derived from `(mapSeed, tick)` so it stays deterministic and replayable.

Not started. Worth doing right after the map, because the crops, the comfort
bands, the animals and the status strip all already read `Climate` — there is
one place to change and five things that would come alive from it.

### 11.5 — the map does not look like a map

Keks, playing it: *"tiles na mapě nevypadají vůbec jako mapa"*.

Not yet diagnosed, and worth diagnosing before touching: the world map
(`WorldMapScreen`, hex `Region`s) and the settlement ground (`SettlementGround`,
`LocalTerrain`) are two different tilings with two different problems, and the
complaint does not say which. Whichever it is, the shape to look for is the one
this project keeps producing — a field drawn from noise that reads as *pattern*
rather than as *country*, because the noise is isotropic and the land is not.
Rule 10 and 10b are both about exactly this, and both were found in the ground
layer. Start by screenshotting each at three zooms.

### 11.15 — a battle that is two rows (2026-08-07) — **half done**

At last a specification for §11.6. Keks, watching one: *"bitva nevypadá jako
bitva ale jako dvě řady lidí co mávají mečem, chtěl bych aby bylo realnější —
co v simulaci to na plátně."*

It was **not the drawing**. `SiegeField.post` laid every fighter on a *single
arc* at one `reach`, both sides — defenders at `musterReach` 0.30, raiders at
`originReach` 0.48 — so twenty against twenty was two parallel lines by
construction, and no renderer could have made it look like anything else.

Two things turned over on the way:

- **The formation has depth now.** At most `abreast(of:)` stand shoulder to
  shoulder and the rest form up behind, each rank staggered half a place so
  nobody is directly behind anybody. `behind` says which way the rear runs,
  because that is the one thing a post cannot work out for itself — the
  defenders' rear is toward the town and the raiders' is out toward the country
  they came from.
- **The width had to scale with the number**, and this fixed something that had
  been wrong since the field was written: ninety raiders on one arc came out
  `rankSpacing × 89` = **1.69 wide, on a map one unit across**. Most of a
  warband stood off the edge of the world. Growing as the square root keeps a
  body about two and a half times as wide as it is deep at every size.

**What is not done, and why it stopped here.** The depth lasts exactly as long
as the walk in. `SiegeEngine.closingPoint` pulls every defender onto
`posture.reach` — one ring for the whole line — the moment they have a target,
so the defence flattens back into a row on contact. Holding each defender to
their own rank's ring was written, and reverted: it changes *who fights whom*,
and "A fight leaves the line hurt, not one person picked out of it" went from
eight defenders marked to **two** — the rear ranks stood a stride behind the
fighting and never reached anybody.

That is the real lesson and it is worth stating plainly: **the formation is a
presentation change; making ranks mean something in the melee is a combat
change.** They look like one job and they are two, and the second wants its own
pass with `DangerProbe` run beside it. The next move is probably not a ring at
all but a *scrum* — on contact the ranks should stop existing and the bodies
knot around the fighting, which is both what a melee looks like and what keeps
everyone in it.

`SiegeField.postReach` is left in place with the attempt written up next to it.

### 11.16 — through the houses, an indoor hunter, and wounds you can read (2026-08-10)

Three from Keks in one message, and the middle one came with a screenshot that
made it undeniable.

**People walked through the houses.** Every walk in the game was a straight
line: `ErrandEngine` set off from a job and arrived at a granary, `HaulEngine`
carried a load home, and the shortest way across a town runs over whatever is
standing in it. `ColonyRoute` is A* over the colony's own tile grid — the only
grid buildings occupy — straightened afterwards so a colonist cuts across a
square instead of walking a staircase of cell centres. The route is worked out
**once, when a walk begins** (rule 4), stored on the `Errand` as `via`, and the
canvas follows for free because `Errand.position(at:)` is what it already reads.

Two things it was careful about. The long way round **costs time**, because
distance was already the thing that made a far granary expensive and the walk
must not become free. And a colonist who cannot find a way round walks straight
anyway rather than not at all — refusing the walk is exactly the shape of rule
22, and it is how people starved beside a full granary last week.

**A hunter out stalking game had a roof over him.** The card said it in one
line: **"Venku 0 °C · střecha +26"** — outside, and credited a full roof.
`ComfortEngine` took `housed: pawn.homeID != nil`, which is *owning a bed* and
not *standing under one*, so everybody who had ever been given a house was warm
wherever they were. Rule 18's second shape, where two readers of one colonist
answer from different fields: the canvas drew him in the long grass and the
engine had him indoors.

`ComfortEngine.underRoof` now reads what the **simulation** knows about where
somebody is — the job they hold and whether they are on the road — and never
`AgentMotion`'s day cycle, which is presentation and must not feed back (rule
1). `JobKind.isUnderCover` makes every kind of work answer the question, so a
job added later cannot inherit a default.

**Wounds had no kind.** Combat has gone through `MedicineEngine.wound` for a
while, so a blow already landed on a named part with a severity — but there was
nothing to say *what made it*, and a wolf's bite and a spear through the
shoulder both read as "Left arm". `WoundKind` (cut, stab, bruise, bite, burn)
is drawn from the attacker: `attackerTribeID` is the same honest test of people
versus beasts that decides whether anybody can be taken alive. The name does
work rather than decorating — `bleedFactor` means a stab is what kills somebody
an hour after the fighting stopped and a bruise is what they walk off — and the
card reads "Bodná rána — levá paže · vážné · krvácí".

Still open on this one: the **battle log** does not carry the wound kind, so the
report still says "wounded" where it could say "a stab to the shoulder".
`BattleMoment` is where that goes.

### 11.32 — the figures do not move (asked 2026-08-14) — **the colonists, fixed**

Keks, watching the town: *"přijde mi že se postavičky nehýbou, předtím to byl
mezitick zobrazený, tak nevim jak to je ideálně aby bylo co nejvíc plynulé,
pohyb i boj"*.

**It was never a smoothness problem.** The canvas runs at 30 fps, `TickClock`
gives a fractional tick, `WalkPath.position(at:)` takes a `Double` and
interpolates correctly. All of that was right and none of it was the fault. The
figures were moving. They were moving *thirty times slower than the colonist
standing next to them*, which the eye reads as not moving at all.

Four movement rates shared one screen, in three different units:

| who | rate as written | crossing the whole map |
|---|---|---|
| a colonist living the drawn day | `AgentMotion.walkSpeed` 4.5 per 300 s day | **67 s** |
| a hauler | `HaulEngine.carrySpeed` 0.06 **per tick** | **33 min** |
| somebody on an errand | `ErrandEngine.pace` 0.09 **per tick** | **22 min** |
| a fighter closing on a raider | `SiegeEngine.pace` 0.030 **per action step** | **47 s** |

A world tick is two real minutes and about six in-game days, so a colonist
fetching a sack from the far side of the village was spending three in-game
months on it. In map widths per real second — the only unit the player's eye
works in — that is `0.0008` against the day walker's `0.015`.

The regression Keks remembers is real and has a shape: `pose` gives `haulWalk`
and `errand` **priority** over the day clock. So every system that moved a
colonist onto a simulated walk — the food chain, `HaulEngine`, `ErrandEngine` —
moved that colonist from the fast clock onto the slow one. The town got more
alive in the simulation and more frozen on the screen, at the same time, for the
same reason.

**The answer was already in the codebase, being used by exactly one system.**
`SiegeEngine` is the only movement that was measured per action step, and combat
is the only movement that looked alive. So walking moved onto the same grid:

- `WalkPace` — one place that says how fast a person walks, per action step.
  `0.08` empty-handed, `0.06` with a load. Crossing the valley is twelve and a
  half steps, an ordinary trip across town is two or three.
- `WalkPath` and `Errand` count **absolute action steps**, not ticks.
- `HaulEngine.advanceStep` and `ErrandEngine.advanceStep` run from `ActionLoop`,
  eight times inside the tick, instead of once from `ResourceLoop`.
- A hauler who puts a load down looks for the next heap **on the spot** rather
  than waiting for the ten-tick job board — a walk is a few steps now, so the
  old cadence would have left them standing in the doorway nine tenths of the
  day.
- Cost held to rule 4: the pile sweep stays on the tick, `ColonyRoute.Occupancy`
  is built lazily, and `ErrandEngine.hasBusiness` returns early for a colony
  where nobody is hungry, cold or on the road.

Guarded by `WalkPaceTests` (Core) and `WalkPaceAgreementTests` (App), which
compares the two clocks in map widths per real second across the layer boundary
— the comparison nobody had ever made. Written up as rule **34**.

**Combat needed nothing.** A live raid steps at 1.4 s (`GameViewModel.siegeLoop`,
ten times ahead of the world clock) and a finished skirmish replays over
`SettlementBattle.playSeconds = 20`. Both were already independent of the tick.

#### Still open — the same mistake, in two more places

Found while looking, **not fixed**, because both change simulation balance and
neither is what was reported:

1. **Visitors crawl.** `VisitorEngine.pace` is `0.03` **per tick** — a trader
   with mules covers `0.00025` map widths a second, sixty times slower than a
   colonist. There is a real tension here and it wants a decision rather than a
   constant: the approach is *supposed* to take several minutes so the player
   sees a party coming, and at that duration over that distance it cannot also
   move visibly. The fix is probably to make the beat "waiting at the edge"
   rather than "walking slowly", or to put visitors on the step grid the way
   colonists now are. `VisitorEngine.walk` mixes the walking with the
   `ticksRemaining` phase logic, so it wants splitting first.
2. **The wild is a still life.** `AnimalEngine.stride` is `0.012` over a
   `thinkInterval` of 10 ticks — `0.00001` map widths a second, which is a
   statue. Grazing should be slow, but two in-game months to cross one per cent
   of the valley is not slow, it is stopped. Changing it moves hunting yields
   and predator contact, so it wants `DangerProbe` on it rather than a guess.

### 11.33 — the green, the stores, the gait, and a valley worth walking (2026-08-14)

Four asks in one sitting, and three of them turned out to share a root with
§11.32 — a number measured against the wrong thing.

**The green.** Keks: *"vadí mi že je náves zastavěna když se tam hromadí lidé a
je tam budova nebo položené věci, chtělo by to sklady na materiál, itemy atd."*
The heart of the colony was an **address, not ground**. `ColonyBuilder.nearestFit`
measures from the district centre and the first district centre *is* the heart,
so the very first building a colony raised went on the one piece of ground the
game already treats as a place — the square visitors walk to, the square the
midday gathering stands on, the fire a colony with no hearth eats at. And
`HaulEngine` had nowhere else to put a load, so it piled the timber on it too.

Now: `SettlementGeometry.greenTiles` is a 4×4 square of reserved ground that
`fits` refuses (four, not three, because the grid's width is even and its centre
falls on a tile *boundary* — an odd green cannot sit symmetrically on it), and
unstored goods go to `goodsYard` at the green's edge.

**Stores by kind.** The old `storePosition` was wrong three ways at once, and
they compounded: it matched on the **id string** (`contains("granary")`), so a
store was a store because of what it was called; it took the **first** match in
placement order rather than the nearest; and grain and timber went to the same
building because neither the kind of the good nor the kind of the store was ever
asked about. Now the good says what it is (`CookingEngine.foodstuffs`, the same
list the kitchens read), the building says what it holds (`storage`, which is
data and already existed), and the destination is decided **at the heap** with
the load in hand — so a town of two quarters carries to its own quarter.

**The gait.** Keks, watching: *"nyní jak chodí tak někdy rychle popoběhnou,
hlavně mezi věcmi."* `dailyPose` capped travel at `leg * 0.8`, so when the
schedule asked for a trip longer than its leg the same ground was covered in
less time and **the pace rose without bound**. Capping the time was the wrong
end of it. A colonist who cannot reach the green inside the midday break does
not run there — they eat where they are working, which is what a farmer on the
far side of a valley has always actually done. The trip is dropped rather than
hurried, and one pace holds for everybody. It fixes the crowding too, and that
is not a coincidence: the green was packed because the *whole colony* was
dragged onto it however far away they were.

**Cover — §11.27, built.** Derived, never declared: `Cover.Stature` (how high it
stands) × `Cover.Substance` (what it is made of). The three cases that prove it
is a model rather than a table: a bush stops the eye and not the arrow (0.08), a
boulder stops both (0.55), and a **ravine stops neither** — impassable and no
shelter at all, because nothing rises from it. Old walls are the mirror:
passable *and* covering. `CoverField` stamps the map into one flat array once
(§11.23's discipline) and a trace takes the **greatest** thing on the line, never
the sum. Wired into `SiegeEngine.loose` with `coverBite = 0.8` — a heavy tax,
not a veto, because an archer facing a wall who never shoots is a fight that
stalls. Not built: a shot that is stopped damaging what stopped it, which wants
§11.26's wear to record it in.

**A valley twice the size, with more in it.** Grid 24×24 → 34×34 (1156 tiles
against 576). Span 0.58 → **0.70, not 0.82**: matching the grid exactly was
tried and the fog test caught it — at 0.82 a colony starts with 83% of the
valley charted and every landmark discovered, and a frontier of four corner
scraps is not a frontier. Landmarks now sit past the charted circle
(`LocalMapGenerator.frontierPoint`), because a treasure under the market square
is not a reason to go anywhere.

Variety: **two things made every valley look alike, and neither was the number
of kinds.** The kinds were asked in `allCases` order and the loop stopped at two,
so the first in the source file took both slots and a hollow was very nearly
unreachable — the list was a priority queue and nobody meant it to be. And
everything that was not a ravine was the same round blob of the same size. Now
the order is a seeded shuffle, up to four forms stand up, and a form picks a
**shape**: vein, round, ridge (long *and* thick), or scatter (lobes with gaps —
what old walls actually leave behind).

Two rules came out of it: **35** (a number that must equal another number should
*be* that number — `colonySpan` was a literal with a comment and a test guarding
it, and the widening left it behind anyway) and **36** (a standing order is read
where the work is done — forbidding scouting did not stop the founding scout,
and the test had been passing on an ordering coincidence).

Verified: 1101 Core tests in 142 suites green; 97 app tests in 15 suites green;
iOS BUILD SUCCEEDED.

### 11.34 — the wall stands somewhere, and the heap rots (2026-08-16)

Keks, picking the plan back up: *"mělo by to být krytí footprinty budov"* — and
then, watching it: *"jde mi o to aby co je na plátně je simulaci a naopak, aby to
bylo jako živá hra, lidi chodí, bojují, kryjí se za věci"*, plus *"sklady jsem
taky nenašel jako budovu kam se itemy a materiál nosí aby neleželo na zemi a
nenicilo se"*.

Cover itself was built in §11.33 and every part of it was right — derived from
height and substance, stamped into one field, read by a trace. What was still a
**number** was everything the cover was supposed to be *about*:

| Was | Is |
|---|---|
| all 49 buildings covered identically (`(.overhead, .stone)`) | `Cover.body(of:registry:)` — a wall is chest-high, a roof is total, and the substance is whatever the thing was built out of |
| `nearestFit` put a palisade wherever there was room, which is the middle of town | ramparts are placed on the ring the fighting happens at, and each new one goes round to the side nothing guards |
| `fortification` = one scalar off `stats.defense`, whatever side the attack came from | `SiegeEngine.facingShare` — a wall counts where it stands, down to `strayRampartShare` behind you. Garrisons are people and have no side |
| a defender was sheltered by *distance from the middle of town* | `CoverField.shelter` — the parapet at your shoulder, on the side they are coming from |
| people stood where the geometry put them | `SiegeEngine.sheltering` — a colonist with a wall, a boulder or the old walls within a stride of their post puts it between themselves and the attack, and the canvas draws them there because the canvas draws what the Core says |
| arrows fell into a palisade that never noticed | `CoverField.struck` names what stopped a shot, and `BuildingEngine.chip` wears it. A battered wall then turns aside less, so a fight's damage is a cost the *next* fight collects |
| a watchtower was 20 points of `defense` | `Siege.Combatant.Kind.emplacement` — the first building in the game that **acts**: it stands where it was built, shoots further than a bow in a hand, stops when it is a wreck, and can be pulled down by raiders who would rather be in the stores |

**Three things this turned over**, each found by running it rather than reading:

1. **The cover grid is 40 × 25, not square.** A "step" of one column (0.025) never
   leaves the row a person is standing in (0.04), so cover to the north or south
   was invisible and a defender could never move to it. Both the shelter sample
   and `coverSearch` are floored at the larger cell dimension now — a stride
   that cannot reach different ground is not a stride.
2. **Seeking cover against a distant origin moves nobody.** The first cut
   measured shelter along the line to `SiegeField.origin`, half a map away; every
   candidate within a stride looks at the *same two cells* as the post it came
   from, so the search always returned the post. It is measured against the
   **bearing** the attack comes in on instead.
3. **A default value does not make a `Codable` field optional** — rule **37**,
   and it would have cost a live raid its save.

**The stores half.** The buildings were there the whole time: `warehouse`
(*Sklad*, `materials: 350`) has been an early-settlement building for months, and
`granary`, `library`, `trade_post` and the rest each hold their own kinds since
§11.33. Two real faults under the report:

- **Nothing pushed the other way.** Deeper storage was a pure upgrade, and goods
  left in a heap in the mud were as safe as goods under a roof — so the store
  was optional for ever. `HaulEngine.weathered` rots what is lying about, at a
  rate read off `ItemDefinition.substance`: the harvest goes quickly, timber
  slowly, and **stone not at all**, because stone is stone rather than because
  anybody remembered to exempt it. On the tick, never the step (rule 34's tail).
- **It could not be found.** The build bar is one alphabetical strip of every
  building the colony can raise, so looking for the warehouse means scrolling
  past eleven things that are not it. `BuildingDefinition.purpose` — derived,
  not a list — and the bar filters by it: *Bydlení · Jídlo · Sklady · Obrana ·
  Práce · Věda*.

### 11.35 — everything wears, and the night looks like one (2026-08-16)

Two asks in one sitting. Keks: *"poškození by mělo být od všeho, co to poškodí,
ne jen šípy, ale i vlivy okolo, když na to přijde"* — and, watching a town go to
bed: *"teď všichni chodí spát, ale vypadá to stejně jako přes den, klidně i
hodiny k tomu, ať je přehled co se děje a lidé dělají."*

**Things wear out now** (§11.26 C, the half that was still open). `ItemInstance`
gained `wear`, a **second axis** beside `quality` rather than a worse grade of
it — quality is whose hands made it and never changes, wear is what has happened
since and only goes up, so a notched masterwork is still not a shoddy new one.

| Source | What it wears |
|---|---|
| swinging | the weapon in the hand (`SiegeEngine.wearGear`) |
| being swung at | the coat on the back |
| a day's work | tools that carry a `skillBonus` (`ItemEngine.wearTools`, on the building interval — this walks every colonist) |
| coming apart | `scrapBroken` takes it out of their hands and writes a line; a broken piece already fought like nothing and helped nobody |

Read by `CombatEngine.weaponProfile` and `woundMultiplier` (through
`ItemInstance.effectiveness` = made-well × kept-well) and by
`QuartermasterEngine.worth`, which is what closes §11.22's open note: gear that
never wore out was gear nobody ever had a reason to replace, so the
quartermaster's full slots stayed full for two centuries.

**Buildings are worn by what is around them**, which is the *"vlivy okolo"*
half. `BuildingEngine.weather` was one flat rate for every roof in the colony;
it now multiplies three things it can already ask about:

- **what it is made of** — `Cover.substance` again, its third reader: thatch and
  timber age half again as fast as mortared stone;
- **what the sky is doing** — `skyWear` off the same `Climate` the colonists are
  freezing in, so the hard year everybody remembers takes roofs off too, at both
  ends (frost splits, heat lifts);
- **where it stands** — a building on the rim takes the weather off the open
  valley; one in a street has its neighbours around it. Which is why a palisade
  is the thing a colony is always mending.

And harm in a fight comes from more than arrows: raiders **in** the stores wreck
the building they are standing in (`ransackDamagePerStep`), on top of what they
carry off, charged to the building their way in went through.

**The night.** The drawn day was all there — five real minutes, a schedule that
puts people to bed, a sun that sets at `SettlementLight.dusk` = 0.75 — and
`nightness` darkened only within 0.16 of *midnight*, reaching full dark inside
0.06 of it. So from sunset until 0.84 the sun was down, the shadows were gone,
the windows were lit, and the valley was painted in broad daylight: **a third of
every night was drawn as noon.** It is derived from `dusk`/`dawn` now (rule 35),
ramping over `nightFall` at each end, and the wash went 0.20 → 0.46 so a lit
window and a fire are the brightest things on the screen.

**And an hour you can read.** `DayClock` — one clock for the strip and the
canvas, off the same epoch, because two clocks for one day would put the strip's
midnight in the middle of the canvas's afternoon. The status strip carries the
time, the named part of the day (*Noc · Svítání · Dopoledne · Poledne ·
Odpoledne · Soumrak*), and a tally of what the colony is at — in a fight, at
work, hauling, on errands, away, asleep — read off the simulation and the hour,
never assigned by it (rule 5).

Guarded by `WearTests` (Core) and `NightTests` (App). The night test worth
keeping is `nightIsNeverDrawnAsDay`: it walks the whole day in 240 steps and
fails on any moment where `SettlementLight` says the sun is down and the
renderer darkens nothing — the reachability shape of rule 6, applied to light.

### 11.36 — the frame the valley was eating, and rooms that were not rooms (2026-08-16)

Keks: *"zkus zda najdeš nějaké [chyby] jak jsme si psali, kdyžtak větší zoom by
to chtělo, větší rozmanitost domů"* — then, at zoom: *"vypadají uvnitř budovy
skoro stejně, taky světlo z nich prosvítá přes stěny"*, *"pořád vidíme jen jedno
patro"*, and *"můžeš pak udělat vizuál kontrolu celé appky."*

**The bug worth the whole session: the canvas was spending its entire frame
budget rebuilding two constant arrays.** Sampling a running build put *1490 of
1490 samples* inside `SettlementGround.draw → sorted(by:)`. The comparator was
`Tone.order`, and `order` called `GroundCover.allCases.firstIndex(of:)` and
`Skin.allCases.firstIndex(of:)` — two array allocations and two linear searches
**per comparison**, and a sort asks O(n log n) times, thirty times a second.
Cached into two static dictionaries and computed once per key instead of once
per comparison; the same sample afterwards shows 8 samples in the whole render
path. It also explains what it looked like from outside: a colony opening after
a long absence appeared to hang on *"the years passed without you"*, because the
catch-up runs off the main actor and the main actor was busy sorting the ground.

**Light came through the walls, and the furniture was in the street.**
`SettlementInterior` sized its room from the **lot** (`footprint`, inset a
tenth) while `SettlementStructures` draws the body from `s`, which is the lot
over 2.2. On a 3×3 lot that is a room four fifths of the plot inside a house
half of it — so the floor, the fittings and the room's lamplight were laid
*outside* the walls meant to contain them, and after dark the light came with
them. There is one rect now, `SettlementStructures.bodyRect`, and three callers
read it: the structure draws it, the interior furnishes inside it, and
`AgentMotion` stands people at the fittings (in map units, via `bodySize`) —
which is what makes "the smith is drawn at the anvil that is drawn" true rather
than approximately true.

**Rooms of a kind were one room repeated.** Every house was furnished from the
same clutter list in the same order. A seeded shuffle picks which corners are
used and what stands in them, and a home draws from a longer list than a
workroom does.

**Walls now show what they are made of.** `Cover.substance` — the field the
cover model and the weathering already read — decides the wall's courses (log,
coursed stone, wattle, panel) and biases the roof: nobody thatches a stone house
they could tile, and a hut of sticks is never shingled. Third reader of one
field, no new data.

**Storeys are drawn** — `floors` had been in the data since the beginning and
was read by exactly one thing (`HouseholdEngine`, counting beds), so a building
that stacks people never looked like one. Note what this does *not* fix: only
`apartment_block` and `arcology` carry `floors` in `buildings.json`, and raising
it on a hut or a longhouse would change how many people sleep there, which is a
balance change and not a drawing one.

**Zoom goes to 8** (was 4). Everything the canvas draws for a close look tops
out well below it — the roof is off by 2.5, people are individuals from 1.5 —
so past 4 there was nothing left to reach for.

**Night reads as night.** Darkening alone left an autumn valley glowing orange
at two in the morning: a wash scales brightness and leaves saturation exactly
where it was, and the eye reads a saturated field as daylight however dim. A
saturation blend against grey goes on first — hue goes, shape stays.

### 11.37 — a raid a town can answer (2026-08-16)

Three complaints from one raid, and the third is the one that mattered. Keks:
*"v soubojích se ukazují efekty a krev na místě, kde postava stála když boj
začínal, battle logy nejdou nikde zobrazit, a stále nevím, když je nás hodně,
proč nás vykradou a nezabijeme je."*

**The line was `prefix(12)`, flat.** Twelve people held it whether the colony
was seven or seventy, so every raider past the twelfth walked into the stores
unopposed — and the one thing a player can obviously see themselves doing,
*growing*, bought them nothing at all in a fight. `SiegeEngine.lineSize` now
turns out `turnout` (0.55) of the able-bodied, floored at what a hamlet has and
capped at `lineCeiling` (28, a shield wall's worth — a town of three hundred is
not three hundred bodies on one contact surface). Guarded by a test that fights
the *same* raid against ten people and against sixty and expects the big town to
hurt them more and lose no more of its stores.

**Effects happened at the muster post.** A volley was a bare tally with no
place, so the canvas drew arrows off an imaginary wall; plunder was drawn on the
line between the muster point and the map edge. Both carry a `spot` now — the
volley lands where the last shaft struck, the ransack happens at the man doing
it — and the canvas draws them there. Wounds and deaths already carried their
impact point; what was missing was everything else.

**The arrow in the tree: closed, not built.** §11.27 left "a shot that is
stopped damages what stopped it" open for everything that is not a building, and
the honest answer to the tree half is *nothing*. A `Tree` has exactly one
mutable field — `chopped`, "axe-work banked in the tree" — so feeding arrow hits
into it would mean a warband shooting into your wood **pre-chops your timber**
and the next woodcutter finishes faster. A shaft in a trunk has nothing to take
from the tree; a shaft in a palisade has a condition and a mason, which is why
that half exists and this one does not.

**The colony kept one battle and threw it away when you closed the card.**
`Settlement.battleHistory` keeps the last `battlesKept` (8), newest first, and
`BattlesPanel` (Details → *Bitvy*) lists them with what each cost and reopens
any of them — the report card and its replay were reachable exactly once, on the
way past.

### 11.30 — the game makes no sound at all — **built 2026-08-17**

**Done, and with no audio files at all.** Every sound is generated a sample at a
time: wind and rain are filtered noise through a wandering band, a cricket is a
short burst of two beating sines, fire is noise with pops in it, and a bell is
three inharmonic partials ringing out. Nothing was downloaded and there is no
licence to keep — which also settles the sourcing question below by making it
moot for everything except music.

Why generated rather than looped, beyond the licence: the world is *continuous*.
The weather moves, the day turns, the colony grows. A recording can only be
crossfaded between states; a generator can be told the state and follow it, so
the wind genuinely rises as the cold comes on and the crickets genuinely stop
when the season turns.

- `Soundscape` — the whole mapping from world to mix, as a **pure function** of
  the same facts the canvas draws with (season, `Climate.weather`, nightness,
  who is awake, whether a raid is on, how many fires are lit). Tested: crickets
  in January, a loud village at three in the morning, snow that is as loud as
  rain — every complaint anybody will have about the ambience is an assertion
  about this type.
- `AudioEngine` — an `AVAudioSourceNode` doing the DSP, `.ambient` session so
  the game respects the silent switch and does not stop the player's music.
- Five stings, and deliberately only five: hammer, bell, horn, chime, knell,
  mapped off `ColonyLogEntry.Kind` at the one place every piece of news already
  passes through (`GameViewModel.show(_:)`). A sound per journal line is a game
  that gets muted.
- Settings: on/off and a volume, remembered.

**One trap, and it cost a crash loop before the app could finish launching.** A
closure formed inside a `@MainActor` method is *itself* main-actor isolated, so
Swift plants an executor check in it — and that check runs on the audio thread,
hits `dispatch_assert_queue` and takes the process out with SIGILL. The render
block has to be built in a `nonisolated` context. The stack said
`swift_task_checkIsolated` under `AudioSourceNode`, which is the whole diagnosis
if you have seen it once.

Still open: **music.** A theme wants a real track from a clean licence — a
generator does texture well and melody badly. The sourcing note below stands for
that, and for it alone.

**Original ask, kept for the licence analysis.** *"Ty bys teoreticky mohl najít na YT nějaké
vhodné royalty free audio a zvukové skladby, co bychom tam mohli dát."*

There is no audio anywhere in the project — no `AVFoundation`, no assets, no
mixer. A living-world canvas that is completely silent is a real gap, and it is
the cheapest big change in perceived quality on this list.

**On sourcing, before anything else, because it is the part that can go wrong
quietly.** Pulling audio off YouTube is not a licence, whatever the video's
title says. Downloading it breaks YouTube's terms regardless of the uploader's
claim, and "royalty free music" aggregator channels routinely re-upload tracks
they do not hold the rights to — so the risk lands on the App Store listing, not
on them. The *YouTube Audio Library* in Studio is first-party and clean, but its
grant is aimed at use in YouTube videos and is the wrong instrument for shipping
inside a paid app.

What is actually safe for a shipped game: **Freesound** (filter to CC0),
**OpenGameArt**, **Incompetech** (Kevin MacLeod, CC-BY — attribution is a real
obligation, not a courtesy), **Free Music Archive**, and cheap one-off
commercial libraries where the licence is written down. Whatever is chosen, the
licence text and its source URL want to live **in the repository** beside the
file — a year from now "where did this come from" has to have an answer, and
CC-BY without the credit in the app is simply infringement with extra steps.

**What the game would use it for**, in rough order of how much each is worth:

- **An ambient bed that follows the world.** The canvas already knows biome,
  season, weather and time of day, and those are exactly the axes a bed should
  cross-fade on. Wind over tundra, rain, insects on a summer night. This alone
  would carry most of the effect.
- **The colony as a sound.** Its size, not a loop: a hamlet is birdsong and one
  axe, a town of two hundred is a hum. Derived from what is already drawn.
- **Stings on the things the journal already reports** — a birth, a death, a
  raid, an era advancing. The journal→toast path exists; audio is one more
  reader of the same event.
- **The bench, the build, the tap.** Cheap, and the difference between a UI that
  feels dead and one that does not.
- **Battle**, which is the one place silence is most conspicuous.

**Two rules it must not break.** Presentation never writes the simulation
(rule 5) — audio reads `WorldState` and the frame clock and touches neither, the
same discipline `AgentMotion` and `PawnLook` already keep. And a mixer must not
call `Date()` or an RNG that the engine can see; if a sound wants randomness it
takes it from the same `(id, tick)` derivation everything else does, or it takes
it from a source the engine never reads.

Two smaller things that come with it: the app has **no volume or mute control**
of its own, and per §11.25 B it has no reduce-motion respect either — both belong
in the same settings pass. And audio has to survive the premise of the game,
which is that you close it and come back in a week: the session ends, the bed
stops, nothing keeps playing in the background.

**Sources checked 2026-08-13, with the catch that matters:**

| source | licence | note |
|---|---|---|
| [OGA — CC0 Background Ambience](https://opengameart.org/content/cc0-background-ambience) | CC0, author says no attribution required | a **collection** |
| [OGA — CC0 Calm / Relaxing Music](https://opengameart.org/content/cc0-calm-relaxing-music) | CC0, ~100 tracks, MP3/OGG/WAV | a **collection** |
| [OGA — CC0 Fantasy Music & Sounds](https://opengameart.org/content/cc0-fantasy-music-sounds) | CC0 | not checked item by item |
| [Freesound, tag cc0](https://freesound.org/browse/tags/cc0/) | CC0 once filtered | the default browse is mixed-licence |

**The catch:** those OpenGameArt pages are *collections* — somebody gathered
other people's submissions under a CC0 heading. That is the collector's claim,
not each author's licence, and OGA says so itself: *"properly attributing the
work you distribute with your project remains your responsibility."* The
authoritative licence is the field on the **individual submission page**. So
this list is a starting point for a search, **not** a set of files that can be
dropped into the bundle on its authority.

**Scope, to settle before doing it.** Three sizes, cheapest first: an ambient
bed alone (4–6 loops — forest, tundra, desert, rain, night — cross-faded on
biome and time of day, the most effect per kilobyte and the axes the canvas
already knows); the bed plus UI feedback (tap, build, confirm); or both plus
era music, which is the most megabytes in the bundle and the fastest to grate
when there are too few tracks.

**Deferred to its own round** (Keks, 2026-08-13: *"to jen zapiš a uděláme to ve
vlastním kole"*). Nothing downloaded, nothing added to the bundle. When it is
picked up: verify each track on its own submission page, and write a `CREDITS`
file into the repo naming author, licence and URL per file as it lands — not
afterwards, because afterwards is when provenance is already lost.

### 11.29 — fuel, and the things that move (asked 2026-08-13)

**Flagged by Keks, not yet built.** *"Taky by tam měla být elektrárna nebo nějaké
další budovy. Teoreticky v budoucnu může být benzín surovina a mít věci na to,
nebo i mít motorová vozidla — no, s tím by byly logické koně a karavany
předtím."*

**First, the correction that changes the ask: the power plant already exists.**
`buildings.json` has `windmill` (5), `power_plant` (22), `hydro_dam` (40),
`oil_refinery` (30), `solar_array` (35), `wind_farm` (28) and `fusion_reactor`
(90). The ladder is *built*. What is broken is that everything above the windmill
is priced in **knowledge**, and knowledge reads zero for a whole unattended run
(§11.28 item 4) — so a colony has one generator available to it, for ever, and
the other six are furniture. Fix the knowledge gate and most of this ask is
already shipped. Worth checking before building anything new.

**Fuel wants to be an item, not a sixth resource.** `ResourceType` has exactly
five cases — food, materials, energy, knowledge, influence — and they are the
*abstract* stores. `charcoal` already exists as an **item**, which is the right
precedent: fuel is a concrete thing you make, haul in a pile, and burn, in the
same way `timber_bundle` is. Adding a sixth `ResourceType` would put petrol in
the same bucket as *influence*, and would inherit the shared-storage-cap bug in
§11.26 for free. So: charcoal → coal → oil → petrol as items, with the refinery
turning one into the next, and generators consuming them — which also finally
gives energy an **input**, instead of buildings that make power out of nothing.

That is the deeper prize here. Right now a windmill produces 5 energy from
thin air, so the only question about power is how many you own. Fuel-burning
generators make energy a *chain* — the same shape the food chain already has
(plot → raw → cook → meal), and the same shape that made food interesting.

**Vehicles need a place to exist, and there is not one yet.** `Caravan` has
`ticksRemaining` and `totalTicks` — travel time is a **fixed number decided when
the caravan is created**. Nothing asks what is pulling it, so there is no hook a
horse or a truck could hang on. Before any vehicle: travel time has to be
*derived* — from distance, terrain, and what is drawing the load — or a motor
lorry and a man with a sack will arrive at the same hour.

**Horses first, and they are half-built.** `Animal` is already a pawn-like entity
with a body, wounds and illnesses, and `TamingEngine` already exists — a tamed
beast is a thing the game can already hold. What it has no notion of is **draught
or carriage**: no carry capacity, no speed contribution, nothing that makes owning
an ox different from owning a deer. That is the missing field, and it is the same
field a cart, a wagon and a lorry would each fill with a bigger number.

So the honest order is: derive travel time → give animals draught → tame horses
→ carts → fuel as items → motor vehicles. Each step is worthless without the one
before it, and the first two are small.

### 11.31 — the famine, found (2026-08-13) — **fixed**

§11.28 left the famine mechanism unknown, with fields, energy and cook headcount
all ruled out. It was **none of the things that were being measured**. It was a
lock that was only ever taken.

`HaulPile.claimedBy` is set when a colonist reserves a heap and cleared in
exactly one place: `piles.remove(at:)`, when the carrier arrives. A colonist who
claimed a heap and then died, sickened, or walked out to a landmark took it with
them permanently — `nearestUnclaimed` skips a claimed heap, so that food sat
where it fell for the rest of the game. Two centuries of ordinary deaths leak
claims steadily.

The column that showed it, once the probe printed it, was goods **lying reaped
and uncarried**: `9 → 42 → 136 → 228 → 292 → 318 → 354`, monotonic, never once
down. Against a raw shelf going `4118 → 3099 → 516 → 0`.

`HaulEngine.releasingDeadClaims` gives a heap back when its claimant can no
longer come for it. Measured, council alone, two hundred years:

| year 200 | before | after |
|---|---|---|
| seed 4242 population | 44 | **298**, still climbing |
| seed 4242 food / shelf | 0 / 0 | 4486 / 4403 |
| seed 2025 population | 33 | **157** |
| goods left lying | 354 | **0** from year forty |

The first run in this project's history where a colony left alone for two
centuries is **still growing at the end**. Rule **33**.

Three things this cost, worth naming because each wasted a measurement:

1. The famine hid behind healthy production numbers. Plots stood at 140 against
   79 wanted; farmers and cooks both scaled correctly with the population.
   Nothing that was being watched was short.
2. It was diagnosed from the outside twice and wrong both times — first as
   clause ordering in `nextBuilding`, then as cooking throughput. Both were
   arithmetic done on the right numbers and the wrong question.
3. It was only visible once the probe printed **`shelf` and `lying` together**.
   Either alone says nothing; the pair says the harvest exists and is not
   arriving.

Two smaller findings from the same run, both correcting earlier guesses:

- **Daughter towns do get founded** — seed 4242 reaches four settlements
  (years 110, 150, 180), seed 2025 three. The earlier guess that charting was
  the brake was wrong; twenty-five charted, empty regions sit unused because
  `soulsPerSettlement × (settlements + 1)` wants 225 people for a fifth town.
  They also did not help: four towns and the capital still collapsed, because
  every one of them had the same claim leak.
- **Upkeep was a real trap but not this one.** `canAffordToKeep` (rule 25) was
  added the same day after materials went `7886 → 3084 → 9`; it holds the
  building count flat and materials recover, but on its own it did not stop the
  collapse. A correct fix for a genuine second problem.

### 11.28 — what the council does with two centuries to itself (2026-08-13)

Measured by `ZZStewardProbe` (`EF_DIAG=1 swift test --filter ZZStewardProbe`),
which drives **nothing**: `TickEngine.advance` already calls
`StewardEngine.advanceOneTick` every tick, so an untouched world *is* the shipped
game left alone.

This matters because `BalanceHarnessTests` — the thing that has been used to
judge balance — is **not** that. It layers a hand-rolled policy (cheapest tech,
most productive affordable building, hut when crowded) on top, and because the
council acts only in the gaps, that policy **preempts and silences the
autopilot**. Its trace measures a player nobody is, with the shipped autopilot
switched off. Treat old balance traces accordingly.

| seed 2025 | y60 | y120 | y180 | y190 | y200 |
|---|---|---|---|---|---|
| population | 60 | 105 | 134 | **148** | 95 |
| food | 3500 | 4000 | 5902 | **0** | 20 |
| energy | 3500 | 4000 | 3978 | 1638 | **0** |
| E demand / E made | 0.9 / 5.0 | 5.2 / **5.0** | 6.7 / **5.0** | 7.4 / **5.0** | 4.8 / 5.0 |
| plots / wanted | 42/24 | 98/42 | **126/54** | **140/60** | 140/38 |

Seed 4242 is the same shape and worse: peak 119 at year 150, **50** at year 200,
food 4082 → 383 → 20 → 0 across the last thirty years.

**1. No energy clause — fixed here.** `Emake` is flat 5.0 from year sixty in
seed 2025 (one windmill, never a second) and **0.0 for the entire run** in seed
4242, while demand climbs to 7.4. The word `energy` appeared exactly once in
`StewardEngine.swift`, in a comment about an old bug. Clause `3c` in
`nextBuilding` now answers a brownout, guarded so it falls through when nothing
affordable generates.

**2. Energy does not cause the famine.** Worth stating because it was the first
guess and it is wrong: seed 4242 ends with **energy 5172 in the store and food
at zero**. Two independent failures, not a chain.

**3. The land is not the problem, and §11.21 is confirmed.** Plots run at
**126 standing against 54 wanted** — two and a half times over — and the colony
starves anyway. This is the `plots`-against-`want` comparison §11.21 asked for,
answered: the ground unblocked and was never the ceiling.

That makes the council's answer to a thin larder the **wrong lever**. Its clause
reads: if raw stuff on the shelf ≥ 20 *and kitchens == 0*, build a kitchen;
otherwise build a farm. With 126 plots and an empty larder it builds another
farm, every time. The `kitchens == 0` guard also means a second kitchen can
never be built — though that is moot, because throughput scales with **cooks**
(`CookingEngine` counts `assignedWork == .cooking`), not with kitchens, and
`LaborEngine` already scales cooks with population at `(.cooking, 0.07)`.

**So the famine mechanism is still unknown.** What is ruled out: fields, energy,
cook headcount. What is left: reaping, hauling, or something that stops work
outright. Next probe should sample the chain *between* the plot and the larder —
ripe-and-unreaped, reaped-and-unhauled, hauled-and-uncooked — which is the same
breakdown §11.24 wants to put in front of the player.

**4. Era stalls at `early_industrial` from year 110 in both seeds** — ninety
years, no advance. Related and mechanical: `power_plant` costs **35 knowledge**
and knowledge reads zero for the whole run, so every knowledge-priced building
is unreachable in an unattended game. Rule: a price in a currency the colony
never banks is not a price, it is a wall.

**5. Energy supply does not scale the way demand does.** `eraEnergyDemand` goes
`0, 0, 0.3, 1.0, 2.0, 3.5` **multiplied by population**, while supply is a fixed
5 per windmill and everything better is behind knowledge (see 4). A colony of 240
in the modern age wants 24 a tick — five windmills — and by `near_future` 42.
The clause added here will build them, but it is answering a curve with a flat
number, and that wants either energy buildings that scale or the knowledge gate
opening. Rule 16 again: build off a rate, not a stock.

### 11.27 — a building is a solid object, and one day something shoots past it (asked 2026-08-13)

**Flagged by Keks, not yet built.** *"Chci ty budovy mít opravdu unikátní proto,
co jsou — mít třeba v budoucnu turrety. Takže bude důležité, aby bylo vše na svém
místě, zabíralo plochy, když třeba bude krýt kulky nebo šípy ze zbraní."*

The through-line of the whole RimWorld layer, stated as a requirement rather
than a look: **a building's footprint is a physical fact, not a picture.** It is
already half true — `footprint` is real, lots are real, `ColonyRoute.Occupancy`
answers "what stands on this tile" from a flat array, and `Landform` (new
2026-08-13) put country on the same footing with `blocksMovement`. What does not
exist yet is the other half.

**Cover and movement are two different questions, and the code already implies
it.** `LandformKind.blocksMovement` says a ravine stops a walker and a ruin field
does not — with the comment *"you walk the streets, not the walls"*. That
sentence is exactly the distinction a projectile needs and cannot currently ask
about: the walls of a ruin should stop an arrow while the ruin as a whole stays
crossable. So cover wants its **own axis**, not a reuse of `blocksMovement`:

- **passable / impassable** — can a body cross this tile
- **cover / clear** — does this tile stop or slow a shot crossing it

A low wall is passable and covering. A ravine is impassable and *not* covering —
you shoot straight over it. Collapsing the two would get both wrong.

**The geometry is already paid for.** `ColonyRoute.Occupancy` was built to
answer tile → placement cheaply enough to run inside routing (§11.23), and a
line-of-sight trace asks the same question along a line. Whatever ships for
shooting should read that array rather than growing a second spatial index that
can disagree with the first — the same discipline that stopped the router
walking every building per sample.

**Turrets are the reason to do it properly rather than approximately.** A turret
is the first thing in the game that is a *building which acts*: it holds ground,
has an arc, needs a line to its target, and is worth attacking because of where
it stands. Every shortcut taken now — an abstract "defence" number, a battle
that resolves without positions — is a shortcut that a turret makes visibly
wrong. Combat already went real-time with fighter positions in the Core, so the
positions exist; what is missing is the world having an opinion about the line
between two of them.

**Cover comes from height and from what the thing is** — Keks, refining the
above: *"věci dle výšky a toho, co to je, poskytují krytí."* So cover is
**derived, not declared**: no hand-set `providesCover` flag on forty objects
that will drift apart, but a rule read off the two properties the object already
has to have. A waist-high wall is partial; a full storey is total; a bush stops
the eye and not the arrow; a boulder stops both; a ravine is *below* the line
and stops neither, which is the case that proves the rule is height and not
"is it solid".

**The height cover needs is not the height the buildings already have.** Keks:
*"ale my vidíme jen spodní patro, ne storeys?"* — correct, and it kills the
obvious shortcut. `BuildingDefinition.floors` exists, but it is read by
**`HouseholdEngine` alone**, to derive how many people a footprint sleeps. The
canvas is top-down: you see the ground floor, and a tenement reads as a tenement
because its `look` says so, not because `floors` is three. So `floors` is neither
drawn nor, for this purpose, meaningful — it measures **upward**, and cover is
decided at the height of a person standing on the ground. A one-storey wall and a
five-storey block stop an arrow identically.

Which means the axis is mostly about the *small* things, and none of them have it:
`Landform`, `Flora`, the rocks, and the piles from §11.26 carry no height at all.
That is where the interesting values live — ankle, knee, waist, chest, over-head —
because everything a building does is simply "total". Giving those a height is
worth doing **for the drawing anyway**: a renderer that knows how tall a thing is
can size and shade it honestly instead of by a species table, so the cover rule
rides on something the canvas wanted regardless.

`LocalTerrain.elevation` is a third thing again — the ground's own level, already
used to pick what a tile looks like — and it is what makes a ravine the case that
proves the rule: negative relative height, no cover.

The "what it is" half is the second term, and it is why height alone will not do:
at equal height a hedge, a palisade and a stone wall should behave differently
against an arrow. Two axes multiplied — **how high** and **how solid** — cover
that, and both are one field each.

Worth settling before the first turret rather than after: whether cover is
binary or a fraction, and whether a shot that is stopped hits the thing that
stopped it — because "arrows chip the palisade" is where this meets the wear
rule in §11.26, and a wall that soaks fire for ever is the same dead mechanic as
a sword that never dulls.

### 11.26 — nothing is stored and nothing wears out (asked 2026-08-13)

**Flagged by Keks, not yet built.** *"Chybí sklady, protože materiál a jídlo se
hromadí venku na hromadách ve vesnici — za co by měla být penalizace v
durability. Používáním, bojem atd. se věci poškodí, stejně tak když je necháš
ležet venku v hlíně (kameny ne třeba)."*

One observation with three separate things underneath it, and the first one is
a bug rather than a missing feature.

**A. There is one storage building in the whole game, and its capacity is not
typed.** `buildings.json` has exactly one: `granary`, `"storage": 250`,
described as *"Stores grain against the lean months."* But
`ResourceLoop.storageCapacity` returns **a single `Double`**, and
`s.storage.clamped(upper: s.storageCapacity)` applies that one number to every
`ResourceType` alike. So a granary deepens the store for knowledge and influence
exactly as much as for grain.

That is not theory — it is visible in the balance trace, where `materials` and
`influence` sit pinned at the **identical** value (7350) for half a two-century
run while food and energy go to zero. Two unrelated resources agreeing to four
digits is one cap wearing five hats.

So the ask is really: **storage should be a kind of building, not a number** —
a granary for food, a warehouse or timber yard for materials, a treasury or
archive for the abstract stores — and `storageCapacity` should answer
*per resource*. Everything else here sits on top of that.

**B. Goods lying in the open should suffer for it.** `HaulPile` already carries
`droppedTick` (it exists so the oldest heap is fetched first), so **the age of a
pile is already free** — a weathering rule needs no new state, just a reader.
Grain and food rot, timber and cloth spoil more slowly, and *stone does not*,
which Keks called out explicitly and which is right: `rough_stone` and ore have
no business rotting in a field.

This is also the honest pressure that makes (A) matter. Deeper storage is
currently a pure upgrade with no opposing force; a colony that leaves its
harvest in heaps because it has nowhere to put it should lose some of it. That
is the resource-sink rule again — a sink only bites when it scales with
something the player cannot simply out-build.

**C. Durability does not exist.** The string `durability` appears **nowhere** in
`Core/` or `App/`. What does exist is `ItemInstance.quality: ItemQuality`, with
a `multiplier` and a `label` — and it is written **only in `init`** and never
mutated anywhere in the codebase. So an item is graded when it is made and
frozen at that grade for ever: a sword carried through forty battles is exactly
the sword it was forged as.

The design question to settle before building it: does wear **lower `quality`**,
or is durability a second axis beside it? Lowering quality is fewer moving parts
and the label already reads back to the player, but it conflates "made badly"
with "worn out", and those should probably feel different — a masterwork blade
with a notched edge is not the same object as a shoddy new one.

Wear should come from the three sources named: **use** (a tool at work),
**combat** (`BattleResolver` is where the blows already land, so it knows), and
**exposure** (lying in a pile, sharing the clock from (B)). Stone exempt.

This is also the missing half of §11.22's open note — *"nothing re-arms a colony
whose gear has gone out of date"*. Gear that never wears out is gear nobody ever
has a reason to replace, so the quartermaster's full slots stay full for two
hundred years. Wear gives the "this is worse than what is on the shelf" want
something to actually measure.

### 11.25 — what an audit of the app layer found (2026-08-13)

Asked for by Keks — *"udělej další rozbor i GUI, features, grafika,
konzistence"* — so this is a survey, not a complaint. Ordered by whether it is
visible to a player.

**A. The same rock is two different greys, and only one of them knows it is
winter.** `SettlementStone.stoneColour` and a private `SettlementFlora.stoneColour`
both answer for `RockKind`, with different values (granite `0.31/0.31/0.34`
against `0.34/0.34/0.37`) — and Flora's takes **no `season`**, so it never gets
the winter wash the other one applies. `SettlementRenderer` calls both, one line
apart (`SettlementStone.draw` then `SettlementFlora.draw`), so both appear in the
same frame: two identical boulders, different greys, and in snow only one goes
pale. Fix is deletion — Flora should call `SettlementStone.stoneColour(_:season:)`.

Two other duplicates, neither a bug: `SettlementRenderer.coverColor` is a
forwarding shim to `SettlementGround`'s, and `canopyColor(_ season:)` against
`canopyColour(_ species:season:)` is scenery props (which have no species)
against flora entities (which do). The second is worth a decision rather than a
fix — it means a prop tree and a real tree of the same kind do not match.

**B. No light mode, and no way out of the motion.** `colorScheme` appears
**zero times** in `App/Sources`; `Theme` is fifteen fixed dark tokens. And
`reduceMotion` appears zero times, in a game that is a `TimelineView` + `Canvas`
animating continuously — there is no accessibility escape hatch from a screen
that never stops moving. Thirty-three `.font(.system(size:))` at fixed point
sizes means Dynamic Type does nothing either.

**C. The UI chrome is not bilingual, and nothing guards it.** `ContentTests`
walks `GameData/*.json` — which is genuinely clean — but no test looks at
`Text("…")` in Swift, and there are at least fourteen English-only strings
sitting in shipped panels: `TradePanel:40`, `ItemsPanel:43/90/96/107`,
`QuestsPanel:24`, `TechBuildPanel:32/56`, `WorldMapScreen:233`,
`ColonistsPanel:252`, `TechTreeView:53`. The rule is that languages ship
together, so this wants a test over `App/Sources/**/*.swift` that fails on a
`Text` literal with letters in it that did not come from `AppStrings`.

**D. Files past the ceiling.** `SettlementRenderer.swift` is **1969** lines
against a stated max of 800; `GameViewModel.swift` 1415; `SettlementStructures.swift`
1003. The renderer already has the seams marked in its own `MARK`s — scenery
(~520 lines), deposits, buildings/glyphs — and the sibling names to split into
already exist (`SettlementFlora`, `SettlementStone`, `SettlementPiles`). This is
mechanical, not a redesign.

**E. Smaller.** 204 hardcoded `Color(red:…)` in `Views/` against 15 `Theme`
tokens — legitimate inside the drawing files, much less so in the cards. Forty
files flat in `Views/` with only `Settlement/` grouped. Mixed `Color`/`Colour`
spelling in one module. Six test files for seventy-two sources, and neither
`PawnLook` nor `SettlementLandforms` has one — though `BuildingLookTests` is
exactly the pattern `PawnLook` wants, being a pure function of
`(id, age, genes)`.

### 11.24 — nothing on the screen is a door (asked 2026-08-13) — **done**

> **Built.** The resource pills are buttons; tapping one opens `StoreBreakdown`
> — the chain in the order goods actually move, with the first empty stage after
> a full one marked, and **the kinds named at each stage**. That last part was
> the actual ask (*"myslel jsem druhy jídla, druh materiálu — dřevo, kámen"*),
> and the crafting bench had been the only screen in the game that named a good.
>
> `GameViewModel.focusRequest` is the shared affordance for the click-throughs:
> `SettlementScreen.selection` is local `@State`, so no other screen could reach
> it. Colonist rows and journal lines post a *request*; the screen that owns the
> canvas adopts it, moves the camera, and clears it. Fourteen tap handlers would
> have disagreed about what a tap does inside a week.
>
> Still open: the chronicle, battle reports and event cards name things and do
> not link yet — same affordance, more call sites.

**Flagged by Keks, not yet built.** *"byly by fajn prokliky — na pawny, suroviny
atd. Taky horní panel surovin by mohl být klikatelný, abych věděl, co mám za
podsuroviny."*

Two asks that are the same ask: **the UI states things it will not let you
follow.** A name is printed, a number is printed, and neither is a door. The
game already knows everything behind them — the inspector cards exist, the food
chain exists — so this is wiring, not new simulation.

**The resource bar is the sharpest case, because it actively lies by omission.**
`StatusStrip.resourcePills` walks `ResourceType.allCases` and renders each as a
plain `HStack` of an icon and a `Text` — no `Button`, no `onTapGesture`, nothing
to press. And `storage[.food]` does not mean "food": CLAUDE.md is explicit that
it means **meals ready to eat and nothing else**. Everything upstream is
invisible:

- `Crop.Kind` — grain, roots, greens — ripening in the plots
- what has been reaped and is lying at the plot waiting for a hauler
- `meat` from hunting, `berries` from foraging
- `Settlement.rawProgress`, the part-done work
- `timber_bundle` and the rest of the bench's output

So a player watching `food: 0` cannot tell whether the colony has no crops, a
full harvest nobody carried in, or a granary full of grain and no cook — three
completely different problems with the same number on screen. That is the
§11.9 kitchen death spiral all over again, except this time it is the *player*
who cannot see it rather than the council.

A tap on the food pill should open the chain, in the order it actually flows:
**growing → reaped → hauled → cooked → eaten.** The same treatment fits
`materials` (timber against bundles), and `knowledge` (what is being studied and
what it is going toward), which is also the honest place to surface why
knowledge reads zero for two centuries.

**Prokliky generally.** Anywhere a pawn, a building, an animal or a resource is
*named*, it should open its card. The cards are already written —
`PawnInspectorCard`, `BuildingInspectorCard`, `AnimalInspectorCard`,
`POIInspectorCard` — and the places that name things without linking to them
include the chronicle, the journal toasts, `ColonistsPanel` rows, battle
reports, and the event decision cards. Right now the canvas is the only way in:
you have to find somebody by looking at them.

Worth doing as one shared affordance rather than fourteen tap handlers, or half
of them will be missed and the other half will disagree about what a tap does.

### 11.23 — the per-tick cost is quadratic in the colony (2026-08-10) — **both halves fixed (2026-08-11)**

> **Closed.** The social half went first (`Relationship.joins`,
> `Settlement.bondCount`, an index-taking `adjustRecreation`), and the hauling
> half is now gone too — but *not* by making the route cheaper. `HaulEngine`
> stopped re-planning every tick at all: a walk is decided once when it begins
> (`WalkPath`, the shape `Errand` already had), so the hundred-odd
> `crossesABuilding` samples per hauler per tick simply do not happen. The
> tile→placement map (`ColonyRoute.Occupancy`) is still there and still worth
> it, because the one route that *is* computed per walk asks the same question
> a hundred times.
>
> The second bug this fixed was not a performance bug at all. Because the route
> was re-planned every tick, `haulPosition` was a single point that jumped once
> every two real minutes and the canvas drew it raw — so most of the colony
> stood still with its legs swinging. See the note under §11.20.

Found by profiling a 12 000-tick probe rather than by a test, and it is the
ceiling that arrives next now that a colony really does reach a hundred and
twenty people.

`sample` on a running world, 2 089 samples: **2 004 of them in
`TickEngine.advance` → `ResourceLoop.advanceSettlement`, and 733 of the 794 in
that frame under `SocialEngine.advanceOneTick` → `encounter`** — almost all of it
in `Relationship.involves`, called from

```swift
let existing = s.relationships.firstIndex {
    $0.involves(first.id) && $0.involves(second.id)
}
```

That is a full scan of the bond list, once per encounter, and there are
`pawns.count / colonistsPerEncounter` encounters a tick against a bond list that
grows with the population — so the per-tick cost grows with the **square** of the
colony. It did not matter while a colony was fifty-five people and could not
grow; it matters now, and it will matter more on a phone than it does on a Mac.

**Fixed (2026-08-10), and `SocialEngine` is now absent from the profile
entirely.** Three changes, every one of them provably the same arithmetic:

- `Relationship.joins(_:_:)` in place of `involves(x) && involves(y)` — the same
  predicate for a pair of *distinct* colonists, settled on the first comparison
  instead of the fourth.
- `Settlement.bondCount(of:)` in place of `relationships(of:).count` — the same
  number **without building the array to throw it away**. Two of those happened
  on every encounter.
- `adjustRecreation(at:)` in place of `adjustRecreation(_ pawnID:)` where the
  caller already has the row. `encounter` draws its two people *by index* and
  then handed their ids to a linear search that found the row it had just come
  from — four scans of the roster a meeting.

Verified by replaying a 12 000-tick probe at a fixed seed before and after:
**the two tables are identical, line for line**, which is the only check that
matters for a change that must not move the world.

**The next hot spot, measured on the same run: `HaulEngine` → `ColonyRoute`.**
2 582 of 2 596 samples under `advanceSettlement`, all of it at the two calls to
`HaulEngine.step(..., around: s.colony)`. Every hauler re-plans its route **every
tick**: `ColonyRoute.crossesABuilding` samples the line at half a tile — about a
hundred and thirty samples now the grid can grow to 64×64 — and every sample
calls `ColonyMap.placement(at:)`, which is `placements.first { $0.covers(...) }`,
a linear scan of a hundred buildings. That is over ten thousand tile tests per
hauler per tick, and it got worse exactly when the land started growing (§11.21).

Two ways, and the first is cheap and behaviour-free:

1. **A tile → placement lookup built once per tick** and passed into
   `ColonyRoute`, so a sample is a dictionary hit rather than a scan of the
   colony. Same route, same corners, same world.
2. **Stop re-planning every tick.** A hauler walking to a heap could keep its
   corners and follow them, the way `JobBoard.interval` already gates *looking*
   for work — the comment at `HaulEngine.advanceOneTick` line 117 makes exactly
   this argument for the other half of the loop. Wants a stored `haulRoute` on
   the pawn (rule 3: decode-if-present), so it is the bigger of the two.

Not urgent for correctness; urgent for the promise the game makes about coming
back after a week away, since catch-up replays exactly this path.

### 11.22 — nobody was ever given anything (2026-08-10)

The last room the player was still standing in the doorway of.
`GameEngine.equipItem` is called from the UI and from nowhere else, and
`StewardEngine`'s standing orders knew about **building materials** and nothing
else. So a colony left to itself, for two hundred years:

- never made a weapon, though `craft_bronze_spear` needs no building, no tech
  and fifteen materials, against a store pinned at the cap;
- never made a coat, though `craft_leather_garb` wants two hides and the
  hunters' lodge had been tanning them the whole time;
- never handed anybody a tool, though `worn_tools` and `sturdy_axe` are worth two
  levels of a trade to the person holding them;
- and so walked into every raid bare-handed, which is half of why the danger
  numbers never moved (§8.1).

`QuartermasterEngine` is the answer, and it is the same answer as the frozen
world: the colony does the obvious thing on its own, and anything the player
chose stays chosen.

- **Orders against a shortfall, never a standing order.** Gear is a *stock* the
  colony can name the size of — one coat per pair of hands — not a tap like
  timber. An endless order would have the bench turning out spears until the iron
  ran out; rule 21's shape from the other side.
- **Best, not cheapest.** A town with a workshop and iron on the shelf turns out
  swords. What stops that beggaring it is the builders' reserve: order only what
  the colony could pay for twice, the same rule `StewardEngine` builds under.
- **The hand-out is a matching, not a queue.** A weapon-slot item is a tool as
  often as it is a weapon — `worn_tools`, `sturdy_axe` and `miners_pick` all hang
  where a spear does — so the same axe is worth a great deal to a woodcutter and
  almost nothing to a scholar. Each piece goes to whoever gains most from it.
- **It never takes anything off anybody.** A hand-out only ever fills an empty
  slot. Rule 1's cousin for the council: somebody who wants a better axe has to
  be *given* it.

**The link before the last one.** With the quartermaster in and nothing else
changed, the first measurement said: a colony of fifty-five armed **forty** of
them with spears and bows, and clothed **nobody, ever**. A coat is
`leather_garb`; leather is `tan_leather` out of hides the lodge had been stacking
the whole time — and leather is not a *building* material, so
`StewardEngine.wantedMaterials`, the only list of wanted materials in the game,
never asked for it. The tannery never ran, so `bestGear` could never find an
armour it was able to work, so the armour slot stayed empty for two centuries
while the weapon slot filled in a decade.

Rule 6 in the supply chain, and worth stating as its own shape: **a demand list
that names one consumer gets read as if it named them all.** The gear bench now
publishes its own wants (`QuartermasterEngine.wantedMaterials`) and the council
unions them in. Guarded by "The bench is asked for what the coats are made of".

Measured before that fix, seed 4242, two hundred years — the weapon half of it
working exactly as intended, and the armour half flat at nothing:

```
year   pop  armed  clothed
  10    21     14        0
  50    54     40        0
 100    88     66        1
 150   138    113        0
 200   134    108        0
```

Two things in that table beyond the coats. **The colony holds at 130-138 people
for the last seventy years** rather than peaking and collapsing — that is the
land fix (§11.21) and the fertility clock (§11.19) together, and it is the first
run in this project's history where the second century is not a decline. And
`armed` tracks about **eighty per cent of the population** from the first decade
on, which is the quartermaster doing its job: before it, that column was zero
for two hundred years.

Still open on this one: nothing re-arms a colony whose gear has gone out of date
— a town in the industrial age is still carrying the spears it made in its
first century, because the slots are full and the quartermaster will not strip
anybody. The honest fix is a colonist deciding for themselves that what they
hold is worse than what is on the shelf, which is a want and not a policy.

### 11.21 — the land ran out (2026-08-10)

Midsummer and the generational pass (§11.19) did what they were built to do, and
measured, seed 4242, they moved the curve a long way:

```
peak population   69 @ y80  →  121 @ y170
fert (couples both in the window)   1–4 in the second century  →  20–29
```

And then the colony **starved**. Sixty-nine dead the first time it was measured,
twenty-six after two rounds of fixing. Three ceilings under it, found in this
order, and only the last one is the real one:

**1. `FarmEngine.peoplePerPlot` was derived from the ceiling of a plot, not from
what a plot delivers.** Four mouths a plot is what the ground yields if every
valve downstream is open — but a crop only counts once a farmer has walked out
and cut it, what is cut waits to be hauled, and what is hauled waits for a cook.
Measured: the fields were delivering about half. Now **2.5**, and
`FoodChainTests` asserts the council's number sits at least 1.8× under the
ceiling so the valves have room. Rule 24's sibling: **a constant derived from a
rate has to be checked against what the simulation realises, not against what
the rate permits.**

**2. Roofs outranked fields, and growth made that permanent.**
`StewardEngine.nextBuilding` checked housing first. Survivable while the colony
was not really growing — a town that has stopped growing is not short of beds,
so the clause fell through and the fields got their turn. Fix the fertility
clock and the colony grows every year for two centuries, so housing is short
*every year for two centuries*. Rule 27 in a second place. Fields come first
now: you can sleep four to a room for a season; you cannot eat next year's
harvest this winter.

**3. And plots still froze at 38 — because the ground ran out.** The colony's
grid is a fixed **24×24** (`ColonyBuilder.defaultWidth`), and when
`ColonyBuilder.placeSiteAtFirstFit` finds no room `GameEngine.build` **enqueues
the building anyway**, with `placementID: nil`. `FarmEngine.reconcile` makes
plots out of *placements* — so a farm raised on a full grid **owns no ground and
grows nothing**. Every number agrees: `built` 79 → 107 while `plots` stood at 38
and `plotsWanted` climbed to 49, with materials pinned at the cap the whole way.
The colony was paying for farms that were a line in a ledger.

This was flagged as a rendering problem in the previous handoff — "a full colony
grows a ledger the canvas cannot show" — and it is not. It is a **production**
problem, and it is the ceiling the game now sits under.

**Fixed (2026-08-10), by (1) and (2) together:**

1. **Let the ground grow with the colony.** Expand the grid when a site cannot
   be placed (say +4 a side, to some sane maximum). `ColonyMap` already stores
   its own width and height and the renderer already divides by them, so
   everything scales; old saves keep the grid they had. This is the one that
   matches what the game is about.
2. **Refuse what cannot be sited.** A building the colony cannot put anywhere
   should not be enqueued, and `buildableHere` should not offer it — a silent
   ghost that eats materials is the worst of both. Do this whichever way (1)
   goes; it is correct on its own.
3. **Reclaim ground**: derelict buildings (`condition` below `derelictBelow`)
   hold land they no longer use. **Done 2026-08-11** —
   `ColonyBuilder.clearedOfDerelicts`, wired into `placeSiteAtFirstFit` *after*
   `grownOutward`. The ordering is the whole of it: `BuildingEngine.repair`
   takes anything under `repairBelow`, wrecks included, so a colony that pulled
   its ruins down the moment it fancied building would be demolishing the
   houses it was about to mend. The land has to actually run out first.

`ColonyBuilder.grownOutward` does (1): +4 a side, symmetric so the town keeps
its place in the middle, to a `maxSide` of 64. `GameEngine.build` does (2) —
sites *before* it pays, and refuses outright when there is nowhere to stand, so
the materials stay in the store for something the council can actually stand up.
(3), reclaiming the ground under derelicts, is done as of 2026-08-11 — see the
item above.

Still to do on this: re-run `GrowthProbe.theCurve` — `plots` against `want` is
the column that says whether the ground really unblocked the fields.

### 11.20 — colonists who look like different people (asked 2026-08-10) — **done 2026-08-11**

> **Built.** `PawnLook` in the App beside `AgentMotion`: 6 hair shapes × 5 hair
> colours × 4 beards × 3 builds × 3 heights × 5 skin tones, a pure function of
> `(pawn.id, age, genes)` and stored nowhere. Age shows — hair greys from 42,
> thins from 58, the shoulders come forward from 54 — so a colony that is all
> growing old together looks it without opening a panel. Genes tilt without
> deciding: a courageous colonist stands squarer. Each part reads its own slice
> of the hash, or hair colour would be welded to build and the colony would be
> five kinds of person. Line art, for the four reasons below.

**Flagged by Keks, not yet specified.** *"Chtěl bych, aby byli kolonisti
různorodější — vlasy, obličeje, trupy atd. jako v RimWorldu."*

Right now every colonist is drawn by the same `SettlementFigures.draw`: a head
circle, a two-line body, legs that swing on a `sin`, and a colour that comes
from their trade. Two hundred people in a two-hundred-year colony are two
hundred instances of one drawing. The simulation underneath already knows they
are different — `Pawn.genes` (industry, fertility, sociability, courage), age,
trait, wealth, skills, `Body` with its parts and wounds, equipment in three
slots — and *none* of that reaches the eye.

What this wants, in RimWorld's terms and this project's:

- **A `Look`, derived not stored.** Hair, face, build, skin. It must be a pure
  function of `pawn.id` (plus age, which changes it) exactly the way
  `AgentMotion` derives position — a stored appearance is a save-migration
  problem and a determinism risk for nothing. Rule 5: presentation never writes
  the simulation.
- **Parts that vary independently**: hair shape and colour, beard, face marks,
  torso width, height, stance. A handful of each multiplies into a crowd.
- **It has to survive the zoom**: `SettlementCrowd.showsIndividuals` already
  drops people into group marks when pulled back, so the detail only has to
  read close in — which is also where the player is when they care who somebody
  is.
- **Age should show.** A colony whose problem is that everybody grows old
  together (§11.17, §11.19) should let you *see* that without opening a panel.
- **What they are carrying and wearing** is already in the model
  (`SettlementFigures.Armament`, `equipment`) and is half-drawn; finish it.

**Decided (2026-08-10): line art.** Four reasons, in the order they matter:

1. **The whole settlement view is line art.** A sprite layer would be pasted on
   top of a `Canvas` world of paths, tones and seasons — the colonists would
   stop belonging to the place they stand in. That is a worse outcome than
   plainer people who look like they live there.
2. **The canvas zooms, and sprites do not.** `SettlementCrowd.showsIndividuals`
   drops people to group marks when pulled back and shows them close in, which
   is exactly where a raster figure would go soft.
3. **No asset pipeline, no catalogue, no artist.** This is a solo project and
   `docs/ASSET_SPECIFICATION.md` is a promise of work nobody is going to do.
   Paths cost one function each.
4. **It stays derived.** A `Look` computed from `pawn.id` needs no storage, no
   save migration and no determinism risk (rule 3, rule 5). A sprite system
   wants an index stored on the pawn, and that is a field that can drift.

**The shape to build**, following `RIMWORLD_LAYER.md`:

- `PawnLook`, in the **App** beside `AgentMotion` — presentation, derived, never
  written back. A pure function of `(pawn.id, ageYears, genes, trait)`.
- Parts that vary independently, each a small closed set so the combinations do
  the work: hair shape (6) × hair colour (5) × beard (4, adults) × build (3) ×
  height (3, plus a child's) × skin tone (5). That is a crowd of thousands off
  four bytes of hash.
- **Age shows**: hair pales and thins, the stance stoops, a child is shorter and
  narrower. The colony's real problem is everybody growing old together
  (§11.17, §11.19) and it should be visible without opening a panel.
- **Genes tilt it, they do not decide it** — a courageous colonist stands
  squarer — so the look carries a little information without becoming a readout.
- Finish what is half-drawn: `SettlementFigures.Armament` and the three
  equipment slots are in the model already, and now that the quartermaster
  actually arms people (§11.22) there is something to draw.

See also `docs/RIMWORLD_LAYER.md`, which did this for buildings and animals and
is the pattern to follow.

### 11.19 — midsummer (2026-08-10)

The colony does not die of hunger or of raiders. It dies because the people who
could still start a family stop being drawn next to each other.

`SocialEngine.encounter` draws a meeting as **two colonists taken uniformly from
everybody**. In a young colony most people are unattached adults, so most
meetings are courtships. In an old one they are two married elders, or a child
and a grandmother, and the handful of young people who could still start a
family spend their lives not standing next to each other. Measured, seed 4242:
`fert` — couples with *both* partners inside the fertile window — runs 9–12
while the colony grows and **1–4 for the whole second century**, while the store
sits at its cap and nothing is short of anything.

No rate fixes that. A uniform draw does not find a needle in a haystack faster
by being rolled more often; rule 6 has a sibling here, and it is that **when the
*population* you are drawing from is the problem, changing the *rate* is
arithmetic on the wrong number**. What fixes it is one night a year when the
draw stops.

`FestivalEngine`, at midsummer — deliberately half a year from the turn, where
`SocietyEngine.advanceYear` already pays wages, sorts classes and holds
elections:

- **The feast comes out of the larder**: `feastPerHead` 1.5, about three months'
  rations spent in a night, and never more than `mostOfTheLarder` (35%) of what
  is standing. A colony cannot feast itself to death — the fires burn lower
  instead. An empty granary is its own kind of year: no matches, morale down,
  and a line that says so.
- **Everybody eats**, and it sits with them: `moodShift` +9 fading over the
  season, and `PopulationEngine.conceive` already multiplies by mood (to 1.4×).
  The birth rate rises through a path that already existed. No special case.
- **The unattached stand beside their own age.** `whoMeetsWhom` sorts the free
  adults by age and walks each one outward to their nearest neighbours. This is
  the entire mechanism. It is a *weighting*, not the age-gap bar `SocialEngine`
  deleted on purpose — a forty-year-old with nobody their own age left simply
  meets whoever is nearest.
- **A full head makes room.** `maxRelationsPerPawn` is five and a sociable
  colonist is always full, so without this the one night meant to find somebody
  a match would do nothing for exactly the people it exists for. A bond made at
  the fire pushes out the weakest one they were carrying; partners never.
- **Courtship is easier by firelight**: threshold 30 rather than 45, chance 0.45
  rather than 0.22.
- Widows and widowers come back to the fire on their own, because "unattached"
  means "no partner".

Guarded by twelve tests, including the one that matters — six years of an
ageing colony (thirty souls, four of them young) run twice off the same seed,
with the fires and without, counting *young* couples rather than couples.

### 11.18 — the game and the diary were two different games (2026-08-10)

> *"asi by bylo fajn zoomovat na event nebo bitvu pokud se děje, teď musíš hledat
> kde to hra udělá a vypadá to jako když běží duplicitně."*

Two things, and the second one was literal.

**1. Nothing ever took the player to what happened.** A raid runs for half a
minute at whichever edge the warband came from; a fire takes hold in a corner of
a 24×24 colony; the storyteller's disasters now break real buildings and hurt
real colonists (§11.17). All of it announced itself as a line of text sliding
past the top of the screen, and finding the place meant panning the valley for
something that had already finished. So:

- The Core says **who or what** — `ColonyLogEntry.Subject` is `.pawn` /
  `.building(placementID)` / `.place`, optional, defaulted, and set where the
  engine already had the thing in its hand: the colonist a disaster picked out,
  the lot a fire took hold on (`BuildingEngine.damage` now returns its `seat`),
  the ground a raid was fought over, a finished roof, a newborn.
- The canvas says **where**, because only it knows: a colonist's position is a
  function of `(pawn.id, clock)` and lives in `AgentMotion`. `CanvasFocus`
  resolves a subject to a `LocalPoint`, `SettlementRenderer.Camera.framing`
  centres it under the same clamp the pan gesture uses, and
  `SettlementCanvasView.fly` flies there **once** — a camera that keeps
  re-centring is one you cannot look away from.
- It fires for a fight (live siege, the report card, a replay) and for any
  `danger` line that has a place. **Every toast with a subject is tappable**
  (a `scope` glyph marks it) and the tap takes you there, which also makes the
  quiet ones — a birth, a roof — reachable without being intrusive.

Layer 3 stays clean: the simulation still holds no screen position, and nothing
the camera does is written back.

**2. It really was running twice.** `EndlessFrontierApp` calls `openSession()`
from `.task` *and* from `scenePhase == .active`, and a cold launch fires both.
`isCatchingUp` guarded only the long path, and only by luck of ordering, so two
short opens ran back to back: the world advanced twice for one absence, and the
toasts and the "while you were away" summary were computed off a world that had
already moved. `isOpeningSession` closes it. Rule **29**.

**Two red tests came out of §11.17, and neither was the thing it looked like.**

- *The valley was never worked.* Not poverty: `spare` and `afford` were both
  true and four landmarks stood workable for forty years. Charting the fog is
  tried first and returns, and once the ledger stopped bleeding it could always
  afford to — so it took every outward sitting there was. The valley gets every
  other sitting now. Rule **27**.
- *`buildableHere` was empty at the hundredth year.* Not the freeze: the colony
  was at its material cap with seventy-nine buildings and wanted nothing,
  because the repeat cap is `1 + population / 15`. Empty because full. The test
  now measures whether the ledger can **pay**, which is what the trap took away.
  Rule **28**.

Still open, and now measured twice: the colony peaks at 79 buildings around year
eighty and then the population decays 69 → 29 while the store sits at the cap.
That is the fertility clock of §11.17, not the roofs and not the ledger.

### 11.17 — the colony was paying to stand still (2026-08-10)

The complaint was the ceiling: population pinned at 53–55, `headroom` 0.108, a
couple's best chance at a child 0.0007. Three things were under it, in the order
they were found, and only the first was the one that had been diagnosed.

**1. The council built against the last free bed.** `PopulationEngine.headroomFactor`
is `(1 − pop/beds)²`, so births are down to a ninth of their vigour at two-thirds
full, while `StewardEngine` did not ask for a roof until `population >= housing − 4`
— ninety-five per cent. The two thresholds could never meet. Rule 6, in rule 16's
clothes: a council watching a *stock* while the thing it governs is throttled by a
*ratio*. It builds against `bedsWanted` now — `population / crowdedAbove`, at 0.55
— and dwellings are exempt from the repeat cap while the colony is short of them,
because `1 + population/15` grows with the population and the population is bounded
by the beds. That one is the same freeze with a delay fuse.

**2. The colony could not afford anything, and had not been able to since year
thirty.** With the roofs fixed the beds went 82 → 100 and stopped, and the reason
was not housing at all: `buildableHere` came back **empty** from year thirty to
year two hundred, materials at 1, twenty-three buildings, while food, energy and
influence all sat pinned at the storage cap. `upkeepRateOfCost` is charged **per
tick** as a share of what a building cost to raise, and at 0.03 against a year of
sixty ticks that is *a hundred and eighty per cent of the price of everything you
own, every year*. Upkeep 15.4 a tick against a material income of 18 before
staffing and weather took their cut. Not a balance — a trap, because the store
clamps at zero, so the council could never buy the lumberyard that would have paid
for it. Now 0.005 (about thirty per cent a year), in `WorldConfig` and
`world-config.json` together. Rules **24** and **25**.

Measured after both, same seed, two hundred years: buildings 23 → **79**, beds 82
→ **160**, population peak 55 → **69**, a couple's best chance 0.0007 → 0.0031.

**3. Every authored mood effect in the game was decoration.** `PawnEngine`
recomputes `mood` from needs every tick, and `pawn_mood` wrote into `mood` — so a
golden age and a plague moved the same number for exactly one tick and were gone
before anybody could feel either. Effects land on `Pawn.moodShift` now, which the
mood formula reads and which halves over a season. Rule **26**.

Alongside: the **thirty-four** events that touched neither a person nor a place
(the handoff said thirty-nine; the difference is that `raid` and `region_*` do
count as somewhere) now break buildings, hurt the colonist least able to take it,
or lift the colony — and a disaster that picks somebody out **names them in the
chronicle**. The forty-eight English `narrative_hint` strings are Czech as well as
English. Both are guarded by tests in `ContentTests`, so neither can come back.

**Still the ceiling, after all of it:** the curve peaks at 69 around year eighty
and decays to 29 by year two hundred, of old age. The column that says why is
`fert` — couples with *both* partners inside the fertile window — which runs 9–12
while the colony grows and 1–4 for the whole second century. The founders age out
together and the bonds that would replace them form too slowly to catch it.
That is the social layer's clock (`SocialEngine.weddingMinStrength` and how fast
`Relationship.strength` climbs), not the roofs and not the ledger. Measure before
touching: `GrowthProbe.theCurve`'s `wed`/`fert` columns are already the instrument.

### 11.15b — the battle stopped being two rows (2026-08-10)

The half that was left. The formation had depth on the walk in and flattened the
instant anybody had a target, because `SiegeEngine.closingPoint` pulled every
defender onto `posture.reach` — one ring for the whole line.

Holding each defender to their *own rank's* ring was tried before and reverted: a
ring is a wall, so the flanks and the rear ranks could never reach anybody and six
of eight defenders came out of a raid unmarked. The fix runs the other way — **no
ring, a band and a crowd**:

- `closingPoint` clamps to `posture.reach + SiegeField.scrumDepth` instead of to
  `posture.reach`, so the line takes the shape of the warband pressing into it.
- `SiegeEngine.shoulder` parts anybody standing inside anybody else
  (`SiegeField.bodySpace`, three relaxation passes a step, off a snapshot so the
  result never depends on who is updated first). The depth is *emergent*: the
  people who got to the contact surface first are in the way, and the rest bank up
  behind them and spill round the ends.

Crowding never forbids anybody anything — it only makes them go round — which is
why it keeps the combat numbers a rank rule destroyed. Guarded by "The line does
not flatten when the fight is joined" and "Nobody in the press is standing on top
of anybody", with "A fight leaves the line hurt, not one person picked out of it"
unchanged beside them.

### 11.6 — battle and attacks, again

Flagged, not specified. `SiegeEngine` moves real fighters at real positions and
`SettlementBattle` draws blows between the two bodies that are touching, so the
mechanism is sound; what is being asked for is a different *feel*, and that wants
Keks to say what is wrong with the current one before anything is rebuilt. Do not
start from the numbers — §8.1 is two sessions of evidence that tuning a shape
nobody wants is work thrown away.

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
- **The rate limit ate the first message** (found 2026-08-03, from Keks
  reporting one notification and then nothing). `minimumGap` was measured from
  the moment the player left rather than from the previous message, so the one
  that is actually urgent — the council waiting on a decision, due at two hours
  — was silently pushed out to six, every single time. Fixed. What is still
  true by design: the earliest message is two hours out, so a short absence is
  meant to be silent, and a day with no pending decision and no trouble produces
  only the 22-hour digest. If that reads as "nothing", the fix is *more to say*
  (the world is deterministic — it could predict what will have happened), not a
  shorter timer.
- Animals: stutter, stacking and un-tappability all fixed 2026-07-29.
- The old English content (events, buildings, techs) is still untranslated;
  everything new ships CZ+EN in the same change.

---

## Rules any of this must not break

**Moved to [RULES.md](RULES.md)** on 2026-08-13 — 35 rules, each of which cost a
session at least once. They were buried at the bottom of this file and out of
order, which is the worst possible place for the one document you want to read
*before* writing code rather than after.

---

## 12. 2026-08-20 — the render cap, building identity, and the grammar of an effect

Five things, and three of them were faults that had shipped.

| # | Thing | State |
|---|---|---|
| 12.1 | A town past thirty buildings was **half a town** | **done** — rule 63 |
| 12.2 | Twenty-three buildings **shared a drawing** | **done** — rule 64 |
| 12.3 | The late eras had **almost no events** | **done** — modern 30 → 45, near_future 20 → 45 |
| 12.4 | Catch-up after an absence **looked like a hang** | **done** |
| 12.5 | Three whole eras had **no new dwelling**, and there was no seventh biome | **done** |

### 12.1 — the cap that always dropped the newest roof

`maxVisibleBuildings = 30`, applied as `placements.prefix(30)` — the first
thirty in *build order*, so a colony of seventy-nine drew what it raised in its
first twenty years and silently dropped the building the player had just paid
for and watched go up.

The half nobody had noticed is worse: the cut lived inside `normalizedLayout`,
which `AgentMotion` also reads for homes, beds and work posts. Those
forty-nine buildings were not merely undrawn — **nobody could live or work in
them**. The §9.11 shape again, in the one place it had been fixed once already.

The layout is complete now and `maxDrawnBuildings` (120) is a *frame* budget:
cull to the camera's rect, and if a town still overflows, keep what is nearest
the middle of the view. Ids come from the complete layout, so culling never
renumbers a selection. Five claims, five tests (`RenderBudgetTests`).

### 12.2 — twenty-three buildings, seventeen shared drawings

`factory`, `vehicle_works`, `assembly_plant`, `automated_factory` and `garage`
were one smoking block; `library`, `school` and `university` one hall. The
tempting fix is seventeen more shapes, which is the plan
`HANDOFF-GENERATION.md` warns against — it does not scale and the next twenty
buildings break it again.

`StructureVariant` derives how a building is put together **from its own
definition**: chimneys from what it burns (so a fusion reactor raises none,
however large), a wide door from whether `conveyances.json` keeps a vehicle
there, dark windows from having no workers, `tier` from what it cost, `heft`
from `defense`, `stores` from what it holds. `roofCap`, `roofFurniture` and
`frontDoor` compose it.

Worth keeping: **a random tie-breaker is worse than none.** A coin toss on
`bays` was itself making a 2-wide palisade and a 3-wide stone wall come out
identical. Every axis says something true now, and `signature` makes "no two
are drawn alike" a thing a test can fail.

### 12.3 — and what generating them turned over

Four rounds, because the draft passed `check` and then failed to *decode*
three times running: `unlock_tech` with no `techId`, a `region_hazard` in
`region_kind`'s shape, a `remove_pawn` carrying a `count`. The vocabulary check
knew every word `EventEffect` accepts and nothing about what each one reads.

Pointing the new grammar check at the **shipped** file found forty-one of the
same fault already in the game. `damage_buildings` reads `strength`; eleven
effects said `delta`, `damage` or `amount` — every one ignored, every one
falling back to severity 0.5, so an authored landslide and an authored dam
breach had always been exactly as bad as each other. Seven carried a `count`
for an effect that already damages many buildings; three `add_pawn`s asked for
people they never got. All repaired. Rules 61 and 62.

### 12.5 — a house for the middle of the game, and a country made of water

Only five buildings in the game have `housing`, and between the longhouse
(early settlement) and the apartment block (modern) there was **no new dwelling
for three entire eras**. Three added — `courtyard_house`, `townhouse_row`,
`brick_tenement` — priced off the beds-per-material curve the shipped dwellings
already describe (2.00 → 1.29 → 1.04 → 0.80) rather than off a guess, and each
opened by a tech that exists.

The seventh biome is **`wetlands` / Mokřiny**, and the handoff's estimate of
"two lines of Swift" was fourteen `switch`es plus two in the app. Every one has
a `default:` arm, so a biome added to the JSON alone generates cleanly and *is
the plains under a different name*. `BiomeCoverageTests` fingerprints each
biome across nine axes against the unknown-biome path and requires six to be
its own; `plains` is exempt by name because it genuinely is the fallback.

A fen eats easily and has no stone at all — massif weight 0.06, no iron in any
seam — so a colony founded on one must trade or move for the whole industrial
chain, and has peat to trade with. Its water lies through the middle of the map
rather than along an edge, which no other country does.

---

## 13. 2026-08-21 — the world map gets a shape, and three cheap things

Keks: *"klidně větší features"*. So the big one first.

### 13.1 — roads

The design is `docs/ROADS.md`; the short version is that the world map had no
road concept, so **distance was a number nothing the colony did could change**.
Three systems were the poorer for it in the same way — travel time was
`hexes × 26`, `TradeRoute` named two ends and no path, and forty-six
conveyances carried a `regionPace` of 0.7…50 that the world had nowhere to
spend. The third is the "bank with no reader" shape outright.

A road is **per hex-edge**. You do not build a road to the mountains, you build
the piece between here and the next hex — so a half-finished road is a real
state, a road can be cut, and the network grows where the world actually goes
rather than where a designer drew a line.

The council's rule is one line and does all the work: score every edge by
**traffic × how bad the country is**, and build the best. A made way across a
plain saves a tenth of the journey and one through a fen or over a pass saves
half of it, so the council ends up building the pass — the piece a player would
have chosen, arrived at from the numbers instead of from a list of cases.

### 13.2 — what the probe found, which is the point of having one

`RoadTests` (20) proved the system reachable *in the API*. `RoadProbe` walked
two hundred years of a real world and found three faults, none of which any
unit test could have seen:

| Measured | Fault |
|---|---|
| total traffic at year 200: **4** | `trackThreshold` was **60**. No track could ever be worn, in any world, ever |
| track 0, road 0, paved 0, rail 4 | `nextGrade` returned the *top* rung, so the council laid railways across bare country and never built a road |
| worst condition 0.04 | wear was scaled against the unreachable threshold, so nothing was ever "kept" |
| journey saved: **0–4%** | the network did nothing at all |

All three are the same family this project keeps finding — rules 65, 66, 67 —
and the first was written the same afternoon as a rule warning about it.
Re-measured after: see `RoadProbe`, and **read it before touching a number.**

A fourth, found by the wiring test: `RegionExpeditionEngine` had a
`routeHexes` helper and **never called it**. My own bank with no reader, in the
system whose doc warns about them.

### 13.3 — the cheap things

- **A colony lived in one file.** `.atomic` promises a save is never *half*
  written and promises nothing about it being loadable. `WorldStore` rotates to
  `.bak` and falls back when the current file will not decode; the order —
  encode, rotate, write — is what guarantees at least one loadable world
  survives any single failure. `loadRecovering()` says which one you got, so the
  app can tell the player rather than silently rewinding a session.
- **Three hundred and eleven recipes in one flat alphabetical list.** Grouped by
  what comes out, affordable first, with a search that collapses the groups
  while it is in use — grouping is for browsing and a search is not browsing,
  the same reasoning as §9.8.
- **The game had no introduction of any kind.** `FirstRunView`: four cards, once,
  in the game's own voice. Not a tutorial with arrows — the whole proposition is
  that it goes on without you, and hand-holding steps would promise something
  the rest of it does not keep. The four things that are not guessable: a tick
  is two real minutes, the council runs it in the gaps, food is a chain (a full
  granary and a hungry colony means *you have no cook*), and everything drawn is
  really there.


### 13.4 — the second century is not a graveyard any more (measured 2026-08-21)

The premise this batch was going to start from — *"the curve peaks at 69 around
year eighty and decays to 29 by year two hundred, of old age"* (§11.17) — is
**stale**, and measuring before touching it is the only reason that was found.

`GrowthProbe.theCurve`, seed 4242, on today's code:

```
year   pop  adult  young  pairs  wed  fert  waste  slots   chance
  40    55    43     29     18    70    10     37    93%   0.00345
 100    90    66     48     31    52    22     76   100%   0.00380
 200   283   229    150    103     8    68    214    90%   0.00282
```

Monotonic growth to 283, `fert` climbing 7 → 68. The housing work of §11.17 and
the three mid-era dwellings of §12.5 evidently fixed it between them, and
nobody re-ran the probe to notice.

**What the new columns found instead**, and it is a ceiling rather than a
decline:

- `slots` sits at **90–100% from year ten onward**. Every fertile adult has all
  five of `SocialEngine.maxRelationsPerPawn` full, always — so the hypothesis
  that started this (a young adult's slots filling with people too old to have
  children with) is confirmed as a *fact* and acquitted as a *cause*.
- `waste` climbs to 214 bonds joining a fertile adult to somebody past it,
  against 103 partnerships. Most of the colony's social life is, in fertility
  terms, spent.
- **`wed` collapses 70 → 8** while the population quintuples. In a town of 283
  with 150 fertile adults, eight pairs are close enough to marry. Courtship is
  choking on the slot cap: nobody has room for a new strong bond.

That last one is the thing to watch. It is not hurting the curve *yet* — births
still outrun deaths — but it is a ceiling sitting there from year ten, and a
colony cannot grow past what its social life can pair off. Whether to raise
`maxRelationsPerPawn`, prune bonds by usefulness rather than by weakness, or
leave it, is a decision nobody has taken. **Do not tune it without re-running
the probe either side.**


## 14. 2026-08-25 — played it, and said what was wrong

Ten complaints in one evening, each of which turned out to name a **system that
was in the simulation and not on the screen**, or a constant written when the
thing it measured was a different size. Shipped in five commits; the full write
-up is `docs/handoffs/HANDOFF-2026-08-25-evening.md`.

### 14.1 — what was actually wrong

| said | was |
|---|---|
| "války jen v diplomacii" | war was a counter, not a state — nothing could be asked whether one was on |
| "nejsou všechny národy" | seceding peoples were given the colony's own hex to live on |
| "umělý arch, kreslí se přes mapu" | the line formed at 0.30 while the town's edge stands at 0.35 — every raid was fought inside the town |
| "ať je souboj dle prostředí" | `CoverField` existed and the fight used it only for arrows in flight |
| "budovy levitují" | the lot stopped dead at the wall, with wild grass to a hard edge |
| "náves namačkaná mezi domy" | the green was reserved in the Core and never drawn |
| "v pozdějších érách nic okolo" | the grid grows to 90 tiles, `span` stayed at 0.70 |
| "co je na mapě světa není v osadě" | `RegionFeature` never reached `LocalMapGenerator` |
| "zranění neodpovídají plátnu" | `PawnLook` drew hair and age; `Body` had missing limbs nobody drew |

### 14.2 — and the three the handoff had already listed

- **Expeditions walked on water.** Fixing it needed rivers to have **fords**,
  because a channel that is deep for its whole length is a wall.
- **Outlaw cadence 8 raids in 200 years.** A saturated multiplier, not a small
  chance — `temptation` read 3.000 at every percentile (rule 90). Now 31.
- **Research ran out at 130, eras lagged.** A DAG paces nothing (rule 88):
  one age of reach, and the last two era milestones rescaled to a population
  the game actually produces.

### 14.3 — still open

1. `roofEnough` is still a guess.
2. Outlaw camps are never burned out — three of three stand after two centuries.
3. The melee reads as a swing and a blood mark; impacts and recoil are next.
4. Knowledge income swings ±7 000 a year in lumps; nobody has checked whether
   that stalls a study.

## 15. 2026-08-26 — the audit, and a war with two sides

Keks asked for an audit of the app rather than a feature: *"jake funkce ui atd
jsou spravne, je vse spravne napojene? nektere odkazy mezi strankami nedavaji
smysl, crafteni je moc velke."* Then, having gone looking: *"třeba diplomacie,
nebo nevím jak udělat nájezd na město — prostě je těžké tam něco vydolovat, i
když je to docela důležité."*

Everything below came out of that one sentence. Two commits: `72afa54`,
`99252e4`.

### 15.1 — what the audit found

| said | was |
|---|---|
| "diplomacie … těžké tam něco vydolovat" | 8 verbs at 56pt in a plain `HStack` — **504pt of buttons in 346pt of iPhone.** The last ones were off the edge, and *which* ones depended on the standing |
| "nevím jak udělat nájezd na město" | **it did not exist.** `WarState` counted only raids *they* made; `declareWar` set a flag and left you to be attacked |
| "odkazy mezi stránkami nedávají smysl" | two build flows, and the drawer's list omitted every early-settlement building; Construction could not start one; 3 of 4 `.expand` objectives routed to the wrong screen |
| "crafteni je moc velké" | 411 recipes in 4 flat groups. Now folded, with counts |
| — (found while looking) | **every objective was in English**, including `"Raise threatLevel to 60"` |

### 15.2 — the two build flows

`BuildPickerBar` on the canvas: filtered by purpose, priced, you place the
footprint. The drawer's list: called `GameEngine.build` straight, so the engine
sited it and you never saw where. And they were **not the same buildings** —
`buildableBuildings` read `unlockedBuildings` alone, without
`|| $0.era == .earlySettlement`, so the hut, the farm and everything the first
hour is made of were missing from it. Deleted; `buildRequest` carries the ask to
the canvas, same shape as `focusRequest`.

### 15.3 — objectives were never translated, and the guard could not see it

`ObjectivesEngine` was Swift string literals; `ObjectivesPanel` printed them
straight. The bilingual test walks `GameData`, and **none of this is in
`GameData`** — it is Swift in an engine. Months of a Czech player being told
what to do in English, on the one surface whose whole job is that.

`Objective.title/detail` are `LocalizedText` now, `Era.displayName` names the
age instead of `rawValue` with the underscores taken out, and `ResourceType`
learned its five words in the Core so the app and the engines stop keeping
separate copies (rule 35). `ObjectivesTests` builds three worlds — a new game, a
colony in trouble, one lone threatened settlement — and asserts **every source
fires** as well as that no Czech line is the English one falling through. The
coverage half is the part that matters: without it the test passes as happily
over three objectives as over eleven.

**Rule 91.** A bilingual guard that walks the content directory cannot see
player-facing text written in Swift. Every engine that composes a sentence —
`ObjectivesEngine`, `StewardEngine`, `SiteEngine.narrative` — is outside it.

### 15.4 — the march

A war had one direction. `TribeWarEngine` is the other, and it is deliberately
**not** a new system: a march is a `RegionExpedition` (same walk out, same days
there, same walk home) and what waits is a `SiteEncounter`, so the fight is the
one the player has already learned. `OutlawCampEngine` is the template.

What the file owns: a people as a place — `defense` divided among a share of
their grown population, their granary as the cache, a ditch and stake line if
`grudge > 30` — and what it costs, all scaled by share cleared, capped at
`maxPlunderShare` 0.35 and `maxPopulationShare` 0.18 so a war of extermination
takes summers rather than an afternoon. The difference from a camp is on
purpose: outlaws re-form, a people does not.

**Both ends of rule 6 are pinned**, through the real journey rather than the
arithmetic: a full party *can* clear `brokeInAtShare` against a middling people
(or the verb is decoration), and four people *cannot* break a people of four
hundred (or it is a free harvest).

### 15.5 — the sweep, and what it found

Two greps worth keeping, because this codebase's recurring bug is *built and
never surfaced*:

```bash
# view-model verbs no view calls
# engine functions nothing outside their own file calls
```

Dead and deleted: `GameEngine.interactWithSite` (a pass-through superseded by
`RegionExpeditionEngine`), `recipeOutputName`, `isActionable`, `ResourceChip`
(which took a `capacity` it never drew).

**Written for a surface that was never built** — the interesting half:

- `ComfortEngine.isFreezing`, whose own doc comment says *"what the inspector
  shows"*. The inspector never called it, so a colonist losing health to the
  cold looked like a low bar. Now a line on the card.
- `HaulEngine.waiting`, *"for the objective and the ledger to read"*. Neither
  existed, so a store that would not grow gave no way to tell a colony
  producing nothing from one producing plenty and carrying none of it in. Now
  on the stores line, with **no threshold** — what counts as too much depends
  on the size of the colony and nobody has measured it (rule 23).
- `GameViewModel.wouldOverrule`, which is the predicate for the sentence already
  written above `standingToggle`: *"spending standing only means anything when
  you're going against the council."* True and unimplemented, so half of every
  motion the player armed the switch, pressed the button they agreed with, and
  watched nothing happen.

### 15.6 — still open

1. **The crafting gate is still data.** Folding the groups hid the wall; it did
   not move it. 237 of 411 recipes carry no `requiresTech`, and building a
   `workshop` unlocks **122 at once** (`hut` 74, `hunters_lodge` 54). Depth 5–6
   recipes are 100% tech-gated and depth 1 is 73% ungated, so the generation got
   steadily lazier the earlier it went. The early ladder is sitting there unused
   — `snares` gates one recipe, `pit_props` and `yokes` gate none. Do not gate
   by guess: derive from material chain depth, and never push a recipe later
   than the era its inputs come from.
2. `SettlementRenderer.swift` is **2822 lines** against a stated max of 800 (the
   codemap says 1969 — stale). `GameViewModel.swift` is ~2000.
3. `preferredColorScheme(.dark)` is hard-wired in `EndlessFrontierApp`;
   `colorScheme` appears nowhere in the renderer, and `reduceMotion` nowhere in
   a continuously animating canvas.
4. The "Layout" button carries the same weight as "Build" while its own comment
   calls it the least-reached of the four.
5. Doc drift, again: `NEXT.md` says 37 techs / 306 recipes / 38 rules; the files
   say **60 techs, 411 recipes, 477 items**, and `BACKLOG` is past rule 90.

## 16. 2026-08-26 (later) — the crafting panel, and 73 items that did nothing

Continuing §15.6. The plan said "gate the recipes"; measuring first said the
gate was the wrong fix and found something larger.

### 16.1 — why the list felt enormous

It is 411 recipes, but that is not the complaint. **A hundred and sixteen of
them are weapons whose damage runs 1 to 42, and the row showed the name, a
rarity dot and an ingredient list** — the same information about a bone spear
and a steel halberd. A list you cannot compare is unnavigable at any length,
and no amount of scrolling helps. Gating would have moved the wall to year 60
(`EraProbe`: the tree finishes there) rather than removing it.

So: the row says what the thing *is* — damage and class for arms, material and
coverage for armour, and the effects, bilingual at last. The order is
`QuartermasterEngine.worth`, the game's own ranking, best first among what can
be made. And one chip, **"beats what we carry"**, against the best of that kind
anybody in the colony is already carrying — which is the only question a player
is really asking of a weapon list. In a real save at year 155 exactly one of
the fifty-one arms rows wore it.

The effects line matters more than it looks: `worth` counts a skill bonus at
three damage apiece, so a hunting bow at 5 outranks a bronze spear at 6, and
without the bonus on the line that order reads as arbitrary. A number shown
beside an order it does not explain is worse than neither.

Groups fold, with counts. A real colony at year 155: **ARMS 51 · ARMOUR 34 ·
GOODS 71 · MATERIALS 70** — four lines instead of two hundred and twenty-six.

### 16.2 — 73 items that could never be used

Found while measuring the groups. `GameEngine.equipItem` requires
`slot == .equipment` **and** a non-nil `equipSlot`, and returns the world
unchanged when either is missing. `ItemsPanel` switches on `slot` alone and
offers an Equip menu for anything marked equipment.

**Seventy-three items had the first and not the second.** The player picked a
colonist and nothing happened — no error, no message, the item still on the
shelf. **Eighty-nine recipes made them**, a fifth of the whole book, and since
`ItemEngine.equippedEffects` reads only what is *worn*, every skill bonus, mood
bonus and health regen on all seventy-three was dead the entire time.

Fixed by derivation, not by guess:

- **11** carried only `colony_*` effects, and `ItemEngine.artifactEffects`
  reads those from `slot: artifact` alone → artifact. (A woven clan banner is a
  thing the colony has, not a thing somebody wears.)
- **62** carried personal effects → `equipSlot: trinket`, which is where their
  shipped siblings already sit: `crude_harness` and `leather_packsaddle` are
  trinkets, and `simple_harness` was one of the dead ones.

Two guards in `ContentTests`: *"Every item a colonist can be handed has
somewhere to put it"* and *"No recipe makes a thing that cannot be used"* — the
second because the cost is the other half of the fault. A recipe whose output
cannot be used is materials and worker-ticks spent on nothing, and the bench
takes the order happily.

**Rule 94.**

### 16.3 — measured, deliberately not fixed

**64 items carry `colony_*` effects from a slot that never reads them.**
`artifactEffects` filters `slot == .artifact`; `barrow_blade` has
`colony_defense +6`, `leather_leggings` has `colony_defense`, `grave_torc` has
`colony_morale` — all inert, all properly-equipped gear. The panel now prints
them ("colony +6 defence"), so the claim is at least visible.

Whether a worn thing's colony effect *should* count is a design question with a
balance answer behind it — a colony where everyone wears leather leggings
plausibly is better defended — and changing `artifactEffects` to include
equipped items moves defence, morale and production at once, across every save.
**Do not do it blind.** Measure with `DangerProbe` either side.

### 16.4 — two things seen in a real save at year 155

- **All eight bench orders read "Short of materials"**, including Saw Timber
  (made 222) and Tan Leather (made 415). Every arms recipe past the stone age
  wants `Wood 0/1`, `Wood 0/2`, `Wood 0/3`. This is `ef-wood-chain-broken`
  still standing, in a colony holding 9,000 materials.
- **Catch-up sits at "0 years · 0%" for about forty seconds** before the first
  slice lands. `sliceTicks` is 240 and was chosen without measuring against a
  colony of 160. §2.2 declared the "looks like a hang" problem solved; at real
  colony size the bar is at zero for long enough that it is not. Slice by
  *time* rather than by a fixed tick count, or report inside the slice.

### 16.5 — reduce motion, and what it must not switch off

`accessibilityReduceMotion` appeared **zero times** in a continuously animating
app. The interesting part is deciding what it means here, because a colony sim
is *made* of motion and honouring it naïvely leaves a still photograph.

The line drawn: Reduce Motion is about the movement the interface does *around*
the content. So the camera flight becomes a cut (a half-second pan across a
valley at a changing zoom is the most nauseating thing the app does, and the
player still ends up looking at the thing — which was the whole point of the
flight); the fifteen bottom cards fade instead of sliding; the toast spring,
which overshoots on purpose, becomes an ease. **The colonists keep walking.**
Somebody who turned Reduce Motion on because pans make them ill is helped;
somebody who turned it on and still wants to watch their village still has one.

Routing the fifteen identical card transitions through one `cardEntrance`
property was the difference between one conditional and fifteen (rule 35).

Still open on accessibility: the canvas is unlabelled to VoiceOver, Dynamic Type
is ignored by 33 fixed `.font(.system(size:))` calls, and
`preferredColorScheme(.dark)` is hard-wired.

## 17. 2026-08-26 (evening) — the wood, measured

`WoodProbe` was written to test a hypothesis and disproved it, which is the
only reason the real cause was found. Suspicion: the council's two standing
orders eat every scrap of wood and `CraftingEngine.yieldsTheBench` cannot stop
them. Measurement said otherwise.

### 17.1 — what the probe found

Seed 4242, two centuries, before the fix:

```
year   pop  loggers  trees  bear  sap  spare   wood  timber  blocked
  30    39        4     51    16   35      0    202       1        1
 100    69        6     46    16   30      0    226      15        2
 140   109       10     44    16   28      0     39      58        1
 200   298       28     47    16   31      0      1     100        6
```

**`bear` is 16 at every reading from year 30 to year 200** — exactly
`FloraEngine.seedStand` — and `spare` is therefore 0 for a hundred and seventy
years. Two guards, each correct on its own:

- `fell` keeps `seedStand` bearing trees back, so a valley can never be cleared.
- `reseeded` scales seed by `bearers / bearersPerSapling`.

Together the axes take every tree the moment it bears, so the second guard's
input is a constant: 16/6 = **2**, for ever, permanently under its own
`thinWoodSaplings` floor of 4. The term meant to make wood supply respond to
the wood was dead code that compiled. Supply was a flat four saplings a pass
while the colony quadrupled; demand crossed it about year 135 and never came
back. Rule 95.

The cost: 123 of 411 recipes consume raw `wood` — thirty per cent of the book —
and all of them, plus `Saw Timber`, `Burn Charcoal` and everything downstream
of charcoal (the whole iron half), were permanently unmakeable.

### 17.2 — the fix, and why not a bigger number

Nature's rate cannot answer a colony, and raising it would only move the year
the curve crosses. **The colony gets a lever instead**: a logger sent to a wood
that is down to its seed stand has nothing to cut, and a woodsman standing at a
floor-bound wood plants (`FloraEngine.tended`). Supply now scales with loggers
— the number the player controls — and self-balances at both ends: plant while
`spare` is zero, fell once the stand bears again, stop at `woodCeiling`.

No new magnitude: a logger sets one sapling in the pass they would otherwise
have spent felling.

After, same seed:

```
year   pop  loggers  trees  bear  sap  spare   wood  timber  blocked
  30    39        4    160    16  144      0    202       1        1
 100    58        5    160    17  143      1   2209      49        1
 140   105        9    160    16  144      0   2971      97        3
 200   282       28    160    17  143      1   1912     312        2
```

Wood 1 → **1912**, timber 100 → 312, blocked orders 6 → 2, and `Saw Timber`,
`Burn Charcoal` and `Tan Leather` all read "short of []". Note the late
decline, 2971 → 1912: demand is catching up again as the town grows, which is
the shape this should have — a resource to manage, not a cliff.

### 17.3 — and what it cost the canvas

`SettlementFlora.draw` sorted and drew **every** tree on the map every frame,
with no camera cull — survivable at forty-odd trees, which is what a wood was
pinned at. A valley now sits at `woodCeiling`, so the per-frame cost roughly
quadrupled on the day the wood was fixed. It culls to the viewport before the
sort now, the same discipline the buildings got in §2.1.

### 17.4 — still open

Everything in §15.6 except the crafting gate's worst half, plus:

1. `charcoal` still reads 2 at year 200 and `Smelt Iron` is still short of it —
   made and consumed in the same breath. That is a real economy rather than a
   dead chain now, but nobody has checked whether the iron half keeps up.
2. `woodCeiling` is 160 and a valley now sits *at* it for most of a run. Pinned
   at the ceiling is better than pinned at the floor, but it is still pinned —
   worth a look once something else competes for the ground.

## 18. 2026-08-26 (evening) — a quarter of the recipe book needed treasure

Found by reading `WoodProbe`'s own output rather than by looking for it:
`Weave Fiber Rope` sat on a standing order and had made **zero** in two
centuries, short of `strong_plant_fibers`.

### 18.1 — what it was

`SiteEngine.lootPool` hands back every material *no recipe makes and no ground
gives*. That is a nice piece of design and it hides a whole class of bug: an
item with no source is not unreachable, it is **treasure** — so the data looks
complete from every angle except the bench.

Counted: **104 of 411 recipes needed at least one input obtainable only as
loot.** `strong_plant_fibers` alone gated **fifty** of them — *"bundles of
tough, dried plant fibers… essential for many early crafts, like fishing nets
or baskets"* — so weaving a net waited on excavating a barrow.

| orphan | recipes blocked | what its own description says it is |
|---|---|---|
| `strong_plant_fibers` | 50 | dried plant fibre, retted |
| `ancient_alloy` | 20 | **treasure on purpose** |
| `bone_spearhead` | 10 | sharpened animal bone |
| `straight_timber_log` | 6 | a trunk, cut and debarked |
| `rendered_animal_fat` | 5 | clarified fat |
| `raw_beeswax_lump` | 4 | wax off the comb |
| `pack_of_river_clay` | 4 | clay off the bank |
| `cured_rabbit_pelt` | 4 | a scraped hide |
| `basic_machine_parts` | 4 | cast gears and levers |
| `crater_glass` | 3 | **treasure on purpose** |
| `spirit_essence` | 2 | **treasure on purpose** |
| `dried_wild_mushrooms` | 1 | picked and dried |

### 18.2 — the fix

Nine recipes, each derived from what its own item description already says it
is made of and who would make it — nothing invented. `greens → fibers` at the
hut, `wood → log` at the lumberyard, `meat → fat` at the cookhouse, and so on.
**104 → 24**, and the 24 that remain all want one of the three things whose
names say they are found rather than made.

### 18.3 — the guard, and what the guard found

`ContentTests` now asserts no material is loot-only outside a named list of
three. Writing it turned up a fourth source the analysis had missed:
`star_iron` comes from a **starfall POI cache** on the colony's own local map —
`LocalPOIKind.cacheItemID`, a real and quite reachable source that is neither a
recipe nor a `LocalResourceKind`. The test found it; the spreadsheet did not.

## 19. 2026-08-26/27 — played it again: pause, deaths, and people with names

Six complaints in one sitting. Every one named a thing the simulation was
already doing that the player had no way to reach, stop, or find out about.

### 19.1 — what was said, and what it was

| said | was |
|---|---|
| *"věci se dějí ale ty si řekneš: ok, stalo se, nijak neovlivním"* | **the game had no pause.** A card arrived and the colony carried on around it |
| *"souboje stále jdou přes běžící simulaci"* | same missing thing from the other end |
| *"raideři nejde je vybrat"* | `RaiderCard` was unreachable — an arm above it in the same chain caught every case it could match (rule 97) |
| *"raideři nemají žádné vlastní features"* | a `Combatant` had strength and intent and **no name** |
| *"lidé umřeli na zvěř ale nevím o tom"* | a raid removed the fallen and wrote **nothing**; a mauling was filed `.danger`; the diary had no filter |
| *"pawni jsou fakt větší než okolní budovy i stromy"* | a colonist stood 8.9pt against a 7.7pt build tile — taller than the hut they live in |
| *"mělo by to poslat notifikaci"* | `pendingDecisionLine` read one of the two decision queues (rule 98) |

### 19.2 — the pause, and the two traps in it

Ticks come from `lastRealTimestamp` against the wall clock, so a pause that
merely stops calling `advanceLive` hands the whole paused duration over on
resume — **a pause would cause the catch-up it exists to prevent.** Resuming
carries the stamp forward instead.

And the obvious trigger was wrong. Edge-detection across one live tick misses
the case that matters: most decisions arrive during a *catch-up*, which is
exactly the state a returning player finds. Keyed on the thing itself, so it
fires however the thing got here and cannot re-fire the moment you press Resume.

A siege keeps stepping on its own clock while the world is held — the fight is
the thing you stopped everything else to watch.

### 19.3 — measured, not guessed

`bodyScale` was 0.82 and the eye was right but kinder than the arithmetic: a
build tile is `baseSpan / baseGrid` = 0.46/24, about **7.7pt at zoom 1**, and a
grown colonist stood at `10.9 × 0.82 ≈ 8.9pt`. True scale would be near 0.3 and
would turn people into dots — they carry a face, a tunic in their trade's
colour and the tool of their work. 0.62 lands a person at seven eighths of a
tile and just under half a mature tree.

### 19.4 — still open

1. **`ColonyLogEntry.subject` is still mostly unset** — 6 of 75 appends before
   this, about 14 after. The per-colonist log is only as good as the subjects,
   and births, comings-of-age and most work lines still set none.
2. The header wraps on an iPhone once a year carries an annotation
   (*"a year to remember"*) — cosmetic, visible, unfixed.
3. Everything in §15.6, §16.3–16.4 and §17.4 still stands.

## 20. 2026-08-27 — the memory, and a recipe book that was already right

Two of the five jobs in `handoffs/HANDOFF-2026-08-27.md`. Both were written as small
sure things and both turned out to be aimed at the wrong half, which is now the
third time in a row a probe has moved the work before it started (rules 23, 90).

### 20.1 — the colonist's own history: subjects were never the shortage

The handoff: *"15 of 76 `journal.append` calls set a subject"*, so set the rest.
`MemoryProbe` (new, seed 4242, two centuries) says what that would have bought:

```
year   pop  held  spanY  subj  withHist  p50  p90  max
  10    15   140    8.5   113  15 (100%)    8   10   11
 100    69   140    2.0   111   59 (85%)    2    3    4
 200   195   140    1.0   124  101 (51%)    1    2    3
```

`subj` is how many of the 140 entries the journal holds already name a person:
**113–125 of 140**, at every reading. The share of living colonists with a
non-empty history never drops below half. The call-site count was a bad proxy,
because the sites that fire most already set a subject.

What is actually missing is *keeping*. `ColonyLog.capacity` is 140 entries for
the whole colony, so the ring spans **8.5 in-game years at year 10 and 1.0 at
year 200** — and by kind, 118 of those 140 are people chatting by the well. A
colonist's card was showing last spring's gossip, median one line, and could not
show their wedding because the wedding had scrolled off.

So a moment that belongs to a person is filed on the person. `Pawn.keepsakes`,
twelve of them, dies with them (no cleanup to forget — rule 33), decodes empty
out of an older save (rules 3, 37) and is in the coding keys with a round-trip
test that carries a value (rule 73). `Settlement.note` is the single door —
journal always, people when it is theirs — and `ColonyLog.append` is no longer
public, because two call sites filing one moment by hand is rule 92 waiting.

Kept: birth (the child and both parents), coming of age, the end of an
apprenticeship, a first friendship, a friendship curdling, a wedding, a
betrothal at the midsummer fire, the first case of a plague, being gored and
living, an event that fell on somebody by name, mourning, the day a captive
stopped being one. **Chatter is not kept** — that is the whole distinction, and
it is not derivable from `Kind`, which is why `keptBy:` is written at the call
site rather than inferred.

Two lines that named a person and set no subject now do: the mourner (they are
the one still standing somewhere) and the settlers who came up the road.

### 20.2 — the crafting gate: the book was already tiered

The handoff: 245 of 420 recipes carry no `requiresTech`, depth 1 is 73%
ungated, so *"the generation got lazier the earlier it went"* — derive a gate
from material chain depth. Measured before writing one, and the premise is
backwards. The ungated recipes are ungated because **they are first-age
content**: ungated arms run damage 1–14 with p75 = 4, and the tier bands read
off the recipes that *do* carry a tech (damage p50: 3 in the first age, 4
ancient, 14 medieval, 18 early industrial, 16 modern, 36 near future) put them
exactly where they already sit. Gating them by depth would have pushed stone
axes and grass hats into the medieval era and made them content nobody meets.

Against those bands the whole shipped book has **five** faults, now fixed:

| recipe | makes | was | is |
|---|---|---|---|
| `craft_chainmail` | mail | *no bench, no study, 2 iron ingots* | workshop + `masters_and_journeymen` |
| `craft_plate_armor` | plate | workshop, no study | + `machining` |
| `craft_warden_plate` | plate | workshop + `scholarship` | + `machining` |
| `craft_bronze_spear` | 6 damage | no bench, no study, **no materials** | bloomery + `bronze_tools` |
| `manufacture_service_rifle` | 24 damage | factory + `machining` | + `mass_production` |

Three guards, and the negative check was run on each: `ContentTests` now asserts
no weapon or armour arrives before the age its damage or its material belongs
to, and — the one worth keeping longest — **nothing is gated later than
something that needs it**, which is §18's fault (`strong_plant_fibers`) stated
as an invariant instead of as a list.

**What the wall actually is**, measured: 212 of the 420 recipes are makeable in
the first age, and 120 more arrive the day the workshop goes up — because
`workshop` is a **medieval** building and 98 of its 123 recipes are first-age
crafts (bone chisels, grass hats, hide caps, stone-tipped spears). There is no
general crafting bench before the medieval era at all; early crafting happens at
the `hut`. That is the avalanche, and it is a *building* problem, not a tech
one: gating a bone chisel on `basic_tools` changes nothing, because by the time
the workshop exists the early techs are two ages old. **Left for a session of
its own** (see §20.4).

### 20.3 — one row per thing

The other half of *"crafteni je moc velké"*, and the one that was cheap. 240 of
the 420 recipes make something another recipe already makes: 107 items have two
or more routes and 79 of those have them in the same age, so the panel showed
"Sew Hide Vest" directly above "Stitch Hide Vest". The list folds on the output
now — first age 212 rows → 151, whole book 420 → 287 — showing the route the
colony would actually take (what it can do now, then the cheaper), with a
`2 ways` note so the fold reads as tidying rather than as content gone missing.
A search is deliberately **not** folded: somebody typing a recipe's name is
asking for that recipe.

Also counted and left alone: **19 recipes are strictly dominated** — a cheaper
route to the same item arrives an age earlier — so they can never be chosen.
The fold makes them harmless; deleting them is a content decision.

### 20.4 — the renderer, in eight files

`SettlementRenderer.swift` was 2822 lines against a stated maximum of 800, and
the seams were the ones its own `// MARK:` lines already drew. Cut into
extensions on the same enum, so every call site is unchanged and a
member-by-member check says the same 64 members are there afterwards:

| file | lines | what |
|---|---|---|
| `SettlementRenderer.swift` | 402 | the camera, `draw`, fog, season |
| `SettlementRendererScenery.swift` | 599 | trees, rocks, reeds, the sea |
| `SettlementRendererLayout.swift` | 598 | glyphs, lots, where a roof stands |
| `SettlementRendererGround.swift` | 443 | cover, zones, roads, the river |
| `SettlementRendererLots.swift` | 305 | the buildings, drawn |
| `SettlementRendererNight.swift` | 228 | darkness and what is lit in it |
| `SettlementRendererDeposits.swift` | 182 | ore, clay, salt, stone |
| `SettlementRendererAgents.swift` | 135 | the people on the ground |

The one edit that is not a move: a member that leaves a file cannot stay
`private`, which in Swift is file scope for a type's members. `drawProp` is 444
lines on its own and is the next seam if Scenery grows.

**`GameViewModel.swift` (2415 lines) was looked at and deliberately left.**
Splitting a class across files means its methods live in extensions, and
`world` is `private(set)` — which in Swift is *file* scope for the setter. Every
mutating method that moved out would force the setter to become internal, and
that one modifier is what keeps a view from writing the simulation (rule 1).
A line count is not worth that. The way through, when it is worth doing, is to
lift genuinely separate *types* out of it — the recipe list is already a pure
derivation over `(registry, settlement)` and could be a `CraftingList` the way
`SettlementRenderer` is an enum of pure functions — rather than to scatter the
class over five files.

### 20.5 — the header, measured on the phone

Reported as the year's annotation breaking the season line. Screenshotting it
found two faults: the reported one (*"rok, na který se nezapomíná"* is 27
characters and shared the season's row), and one that is on screen far more
often — the clock line wraps at midday on its own account, because
"11:42 Midday · 107 at work · 83 resting" is wider than a 402pt phone. `at
work` broke onto a second line and left `· 83 resting` hanging beside it.

The annotation has its own line now, and the clock line is a `ViewThatFits`
offering itself with two entries, then one, then none — `doing` is ordered
worst-news-first, so what goes when the row is short is the least important
thing on it. Verified in the simulator at midday.

### 20.6 — the iron half, measured: the bench had been full since year 60

`WoodProbe` grew iron, steel and charcoal columns, and three columns that a
stock cannot give you — whether a foundry stands, whether the council *wants*
steel, and whether it *could* smelt it — because a flat zero cannot tell
"never wanted" from "wanted and unmakeable" from "makeable and no slot".

Seed 4242, before:

```
year   pop miners    ore charcoal   iron   steel  smeltFe   bench
  60    56      5    274        1      0       0        0   ——                           8/8
 130   100      7    238        2      1       0       27   ——    wantsSteel             8/8
 160   150     11    139        3      0       0       60   foundry wantsSteel canSmelt  8/8
 200   226     15      2       16      0       0      122   foundry wantsSteel canSmelt  8/8
```

Read the last two columns together and the fault is plain: from year 130 the
colony **wanted** steel, from year 160 it had the foundry and the study to
**make** it, and it made **none in two centuries**. The bench column says why —
`8/8` from year 60 to year 200, every one of them a standing order.

A standing order never finishes, so `StewardEngine.councilBenchShare` was not a
share, it was an allocation: eight slots claimed by what a village of fifty-six
wanted — bone spearheads, retted fibre — and held for the rest of the colony's
history. **Rule 83 one level up**: the endless thing outranks everything,
because it is never done.

So the council can now give up one of its own. `CraftOrder.byCouncil` says whose
an order is (hand-written decoder, rule 37; `SaveMigrator` 5→6 reads an old
save's standing orders as the council's, rule 79), and `orderToRetire` gives up
a **council, standing** order that is *below the thing waiting* on the shopping
list — never the player's, which is rule 77's other half. Where several
qualify, the one with most of its material already on the shelf goes.

After, same seed:

```
 130   108      8    262        3      1       1       31   foundry wantsSteel canSmelt  8/8
 200   241     17      1       23      0       1      143   foundry wantsSteel canSmelt  8/8
```

and the bench at year 200 holds three orders that could not have existed at all
before: **Smelt Steel Ingot (9 made), Cast machine parts (18), Process Resin
(18)** — with `basic_machine_parts` and `processed_resin_block` on the shelf for
the first time. Wood 882 → 1107, timber 275 → 410, charcoal burnt 382 → 452,
iron smelted 122 → 143. The industrial half of the item tree is reachable.

**Where the constraint went**, which is the honest next question: steel and
machine parts are both short of `iron_ingot`, iron is short of `iron_ore`, and
ore falls from 309 at year 90 to **1 at year 200** against seventeen miners. The
chain runs now and the shortage has moved to the ground — a thing to manage
rather than a wall. Nobody has measured whether the mine can be made to keep up.

### 20.7 — still open

1. ~~**The workshop avalanche** (§20.2).~~ **Done 2026-08-28 — see §21.4.** An
   early general bench (`work_shelter`), ninety-nine recipes moved to it, and
   the medieval step down from +119 recipes to +24.
2. `GameViewModel.swift` at 2415 lines, and the reason it was left (§20.4).
3. Everything in §15.6, §16.3–16.4 and §17.4 that is not listed above.

## 21. 2026-08-28 — three faults in raids, none of them in the fight

Keks, in one sentence: *"vyvolat nájezd ukáže gui co jsem nikdy neviděl,
přehrání pak přehrává jinde, boj se seká po několika vteřinách — to chci
plynule."* Three complaints, three different causes, and the fight itself was
right in all three.

### 21.1 — the raid landed on a colony nobody was looking at

`GameViewModel.stageRaid` opened the siege on `world.settlements.indices.first`.
`advanceSiegeStep`, `startSiegeLoop` and the screen's `.onChange` all worked on
the **selected** settlement. With one colony the two agree and nothing shows;
with two, a raid on an outpost pauses the world — `stopForAnythingImportant`
looks at every settlement — for a fight that nothing is stepping. A frozen game
with a banner saying the world is stopped for an attack.

Fixed at both ends: `stageRaid` opens it where the player is looking, and the
loop steps **every** besieged settlement, because the pause is world-wide and
the driver has to match it. The screen watches `runningSiege`, not `siege`; the
camera still only flies to a fight on ground it is showing.

### 21.2 — the fight was drawn on a clock that had stopped (rule 103)

`SettlementBattle.withinStep` worked out how far into the current simulation
step the drawing was by subtracting `siege.advancedTo / actionStepsPerTick` from
`continuousTick`. Both sides of that are wrong at once during a raid:

- the **world clock stops** — a raid pauses it, which is the point of it —
  so `TickClock.continuous` clamps at `tick + 1` and stays there;
- the **siege loop does not**, resolving a step every 1.4 real seconds, eight
  to a tick.

So `advancedTo` passes `continuousTick` after about eleven seconds, the
subtraction goes negative, `min(1, max(0, …))` pins it at zero, and it never
moves again. From then on every arrow is stamped at the instant its step began
(`arrowFlight` is 7% of a step, so it is drawn at flight 0 and gone), every
flinch is at full throw, and every stride is a teleport. *"Boj se seká po
několika vteřinách"* — after several seconds, exactly.

`SettlementBattle.Beat` is the fix: the loop stamps each step as it lands, in
seconds since `DayClock.epoch` — the timebase the renderer's `time` already
speaks — and the canvas divides. The world-clock reading is kept for the case it
was written for: a fight in a settlement nobody is watching.

And the drawing needed somewhere to walk **from**. `drawLive` said so in its own
comment — *"everybody is drawn where the simulation says they are, and nothing
is interpolated"* — which is a body appearing at eight positions a tick.
`Siege.Combatant.wasAt` is stamped once at the top of `fightOneStep`, before
anything moves; `spot(within:)` and `Siege.place(of:within:)` are the lerp.
Optional and hand-decoded, so an old save draws exactly as it used to (rule 3).

### 21.3 — the siege screen was reachable only by luck (rule 104)

The third complaint was not a bug report, it was the tell: a surface the player
had never seen. Not rarity — `DangerProbe` measures **127 fights in two
centuries**. A tick is two real minutes and a raid is under one, so the window
in which a raid can be *met* is the sliver of the day the app is in front.
Everything else opened and finished inside a catch-up, fought out by the world
clock, arriving as a line in the diary and a report card.

`TickEngine.advance(_:ticks:registry:stoppingWhen:)` asks a predicate between
two whole ticks and reports how far it got; `GameEngine.openSession` carries
that up and moves `lastRealTimestamp` by the ticks **actually run**, so the rest
of the absence is still owed. The determinism this rides on is stated as a test:
stopping halfway and finishing later must land on the world one straight run
would have.

**Once per return**, and that is the whole policy. A colony is raided several
times in a day of world time, so halting at every one turns a fortnight away
into a queue of fights before the player can look at their own town.
`GameViewModel.haltedForRaid` clears when the app goes to background.

### 21.4 — the workshop avalanche, measured and moved (§20.7.1, rule 105)

Measured across the whole book rather than one building: **101 recipes were
gated by nothing but a bench from a later age than everything else they
needed**, 91 of them at `workshop`, which is medieval.

The previous handoff called the choice between "an early general bench" and
"re-home them to the benches that exist" a design call. It is not, quite: the
second scatters ninety-nine recipes across four unrelated buildings and makes
*where do I make a bone chisel* harder than it was. `work_shelter` — a roof on
four posts, **"Kolna"** — is `early_settlement`, `work: crafting`, 12 materials
and a timber bundle, and it is now the cheapest bench a colony can raise. The
council reaches it through the clause that already exists for this
(`CouncilAppetite.hands` — a crafter with no bench).

**What moved and what stayed needed no taste.** A recipe stays at the workshop
if it eats something smelted or mined (`iron_ingot`, `ancient_alloy`, ore, coal,
crude oil) or if what it makes is outside its age's damage or armour band — and
both bands were **already** in `ContentTests` from §20.2. Ninety-nine moved;
the twenty-five that stayed read exactly right: chainmail, plate, iron sword,
crossbow, the three war bows, flintlock, blunderbuss, machine parts.

| | before | after |
|---|---|---|
| makeable in the first age | 210 | 298 |
| arriving at medieval | **+119** | +24 |
| stranded behind a later bench | 101 | 23 |
| strictly dominated recipes | 19 | 14 |

Two new guards, stated as invariants so a generator cannot walk it back: *no
bench is the only thing holding a book of recipes back* (cap 20) and *no single
age hands over a sixth of the book at once*.

### 21.5 — the fourteen routes nobody would choose

Counted while measuring the above: fourteen recipes are strictly dominated — an
earlier age reaches the same item for no more cost. All fourteen are one shape,
a generator writing a second and dearer route to something the book could
already make.

**Not deleted, deliberately.** The panel folds to one row per thing so the
player never meets them, and a recipe id can be sitting in a standing order in
somebody's save, where removing it stops a bench in silence (rule 3). Capped by
a test instead, so the number cannot grow while the decision is open. The
decision: cut them, or price each below its earlier rival so it becomes the good
route at its own age — and that wants a *rule*, not fourteen hand-set numbers.

### 21.6 — still open

1. **The iron half of the same avalanche.** Of the 23 recipes still stranded,
   almost all are iron at the medieval workshop while `iron_ingot` is reachable
   in the first age at the bloomery — §21.4 one age up. The bands say a `smithy`
   at `ancient` is the shape. Measure either side (rule 72).
2. **The fourteen** (§21.5) — a rule, not a list.
3. **The mine** (§20.7 carried forward): `iron_ore` 309 at year 90 to 1 at year
   200 against seventeen miners. Print the distribution first.
4. `GameViewModel.swift`, and the reason it was left (§20.4).
5. **A raid that ends while the world is paused for it clears its field at
   once** — the linger is measured off `continuousTick`, which is not moving.
   Rule 103's shape a third time, and the same cure.
6. Everything in §15.6, §16.3–16.4 and §17.4 not listed above.

## 22. 2026-08-28 — what the suite said about §21, and the 2.5D groundwork

### 22.1 — two things the move broke, both of them the move's fault

`0c2488f` shipped without a run — `TEST-BASELINE.md` said so in as many words,
which is the harness earning its keep. The run found five issues in two tests,
and both were §21.4's ninety-nine recipes landing somewhere they could not work.

**The cart chain.** `assemble_simple_cart`, `build_wooden_cart` and
`construct_simple_cart` moved to `work_shelter`, which is `early_settlement` —
and a cart is made of `rough_wooden_wheel` and `wooden_cart_axle`, both of which
are carved at the **wainwright**, which is `ancient`. So three recipes became
craftable an age before their own parts existed.

The split rule of §21.4 asked whether a recipe eats something *smelted or mined*
and that is a hand-written list of nine material ids. It is the right question
badly asked: the real one is whether every ingredient is **reachable at the
bench's own age**, which is a fixpoint over the whole recipe graph and which
`ProductionChainTests.ingredientsArriveInTime` has computed since long before
this. The check was already there and the move was measured against a weaker
one. Fixed where it belongs — a cart is a wainwright's work, and the three sit
at the wainwright now. Zero violations across the book.

**The council's bench.** `StewardTests.theBenchTurnsOver` stands a village out
of a hand-listed set of benches — `workshop`, `cookhouse`, `hunters_lodge` and
nine more — precisely so the council has something to work (rule 67). Ninety-six
recipes had just moved to a bench that list did not name, so the bench filled to
five of eight and the retirement the test is actually about never ran. One line
in the fixture.

Neither is a fault in the engines and neither would have shown in `ContentTests`
alone. **A content move wants the whole suite, not the suite that owns the
content** — the readers of a bank are spread across the tests of everything that
reads it.

### 22.2 — the 2.5D layer, specified and not built

Keks: *"chci, ay byly zpracované mapy, osady, budovy — a každá unikátní a
graficky rozeznatelná, až na nutné výjimky."* Measured before writing anything:
**62 buildings, 30 `look` values, 51 of them sharing theirs with another.** And
`StructureVariant`'s axes give **zero** collisions — the signature already
separates all sixty-two, so there is nothing to disambiguate and the drawing
simply does not spend the difference it is handed. Rule 92 left half-finished.

`docs/RENDER_25D.md` is the specification: a **lift, not a rotation** (the map
stays in plan, one `liftPerUnit` constant, and the quad between the footprint
and its lifted copy is the wall face nothing has ever had), one depth-sorted
pass across footings, bodies, attachments and agents, and a shadow whose length
comes off `SettlementLight.sun` rather than a constant of its own (rule 35).

The bank is `structures.json` — a recipe per building, not a picture: `standing`
in map units, a closed `roof` and `fabric`, and **`attachments`**, which is the
field that does the work. What stands *beside* a building is what tells you what
it is across a valley, and it is where the five `plant` buildings stop being one
building drawn five times. The schema is in `docs/data-schemas/structures.json`
and eighteen hand-written exemplars are §7 of the specification.

**Nothing is built.** §6 is the order, and the bank deliberately has no reader
yet: `texture` in `ground.json` was validated, generated and read by nothing for
weeks (rule 47), and a second one of those is not wanted.

### 22.3 — `Tools/revise.py`

`generate.py` adds entries; nothing could correct a bank **as a set**. Four of
twenty grounds share `stipple` and no per-entry review will ever see it, because
the fault is only visible with all twenty on the page at once.

Three things make it safe against a file the game loads: the **roster may not
change** (an id dropped would merge in silence, and it is the one failure a
draft cannot have), **`--fields` is a fence** — everything outside it is restored
from the original, so a run aimed at textures cannot quietly reword forty
descriptions in two languages — and it prints a field-by-field diff before the
same three checks anything else answers to. Temperature 0.55, not 0.95: a
revision is a correction, not an invention.

### 22.3b — `make test-app` said "none" while the run was failing

Worth its own note, because it is the harness lying rather than the code.
`test-app` greps `/tmp/endless-frontier-test.log` for `' failed (` — XCTest's
wording — and the App suite is **swift-testing**, which writes `✘ Test`. The
Core half of the app's tests reported one failure and the target printed
`none`, then `|| true` handed back exit 0. A run that fails and reports success
is the same silent-success shape as a decoder that swallows its error, this time
in the command built to catch those. The grep now matches all three wordings.

The failure it was hiding was mine and it was not a defect: `#expect(end == 1)`
on a share of a step, where `landed + 1.4` is not the number it looks like and
the division came out 0.9999999999997402. A share is a measurement and a
measurement is compared with a tolerance. In the running app the same
subtraction is over `DayClock.epoch`-sized numbers, where a double resolves to
about 10⁻⁷ s — still four orders of magnitude finer than anything a 1.4-second
step is drawn with.

### 22.4 — still open

Unchanged from §21.6, less the two the suite closed. Nearest first:

1. **The iron half** (§21.6.1), now measured: of the 25 recipes left at the
   workshop, **nine** are held there by nothing — `craft_iron_scythe`,
   `forge_miners_pick`, `craft_sturdy_axe`, `forge_grafting_knife`,
   `craft_watchmans_horn`, `consecrate_grave_torc`, `craft_crude_animal_bell`,
   `forge_sturdy_axe`, `craft_masterwork_pick` — while `iron_ingot` is reachable
   in the first age at the bloomery. The other four (`craft_iron_sword`,
   `craft_crossbow`, and the two war bows) are held by the **damage band**,
   which is correct gating rather than an accident. A `smithy` at `ancient` is
   the shape, and §22.1 is the warning: measure with the chain fixpoint, not a
   list of material names.
2. Steps 1–2 of `docs/RENDER_25D.md` §6 — the lift and the depth sort, no data.
   Cheap to abandon if it does not look right, which is why they are first.
3. The rest of §21.6.
