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

Each is specified in `docs/HANDOFF.md` §2 with the diagnosis rather than the
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
20. **A rate that is linear in population, against an opportunity space that is
   quadratic in it, shrinks as the world succeeds.** Rule 6's social form, and
   the one that hid longest: `SocialEngine` held one encounter per ten
   colonists per tick while the *pairs* who could meet grow as n². So a bond in
   a village of seventeen gained two points every two years against a decay
   that never slowed — forty-five years to a wedding, and every marriage in the
   colony's history made in its first fifteen years. Ask of any per-tick
   opportunity: how many *pairs*, *sites* or *combinations* is it being spread
   over, and does that grow faster than the rate does?
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
15. **An autonomous standing order must be priced as a standing order.** Every
   `dispatch` in the game is written for a player who tapped it once and knew
   what it cost. Handing the same call to the council turns "once, deliberately"
   into "four times a year, for ever" — so the council needs its own, stricter
   gates on top: a cadence, a surplus bar above the one building has to clear,
   and a cap on how much of the workforce may be abroad.
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
11. **Playback pace is not simulation pace.** A tick is a real minute and a
   battle is eight rounds; played at the tick's own speed that is one
   exchange every seven and a half seconds, which reads as nothing happening.
   A *record* may be replayed at whatever speed makes it legible —
   `SettlementBattle.playSeconds`. Do not confuse "how long it took" with
   "how long to show it for".
