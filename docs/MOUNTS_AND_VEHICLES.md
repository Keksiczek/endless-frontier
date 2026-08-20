# Mounts and vehicles

<!-- Written 2026-08-19. Steps 1 and 2 are built; 3 onward are design. -->

The colony walks everywhere. It will walk everywhere in the fusion age too,
because nothing in the game can move a body or a load any way but on foot. This
is the design for the thing that changes that, written **before** the content,
because a horse is not a JSON file — see [[ef-content-generation]]'s lesson and
`RULES.md` 47: *a bank is only as big as the selector that reaches into it*, and
a conveyance nothing reads is a bank with no selector at all.

## The one idea

**A mount and a cart are the same thing.** Both are something that

1. moves a body faster than its legs,
2. carries more than a back can,
3. has to be kept — fed, fuelled, repaired,
4. can be lost.

They differ only in what supplies them: a mount is a `TamedAnimal`, a vehicle is
something the colony built. Everything downstream — pace, cargo, upkeep,
terrain, combat, how it is drawn — is one model. Writing "horses" and then
"carts" and then "trucks" as three systems is how a game ends up with three
half-working ones.

So: **`Conveyance`**, and `ConveyanceDefinition` in `conveyances.json`.

## Where it has to bite

A conveyance that does not change one of these numbers is a picture of a horse.
There are exactly four places speed and load are decided today, and the design
is finished when each of them reads the conveyance:

| Seam | Today | With a conveyance |
|---|---|---|
| `WalkPace.perStep` / `carryingPerStep` | 0.08 / 0.06 of the local map per action step | × the conveyance's `pace` |
| `HaulEngine` — how much `HaulLoad.amount` a colonist takes per trip | one back | × `cargo` |
| `LocalPOIEngine.travelTicksPerDistance` (4) | the walk to a cave | ÷ `regionPace` |
| `CaravanEngine.ticksPerHex` | the road between settlements | ÷ `regionPace` |

Two more that make it felt rather than merely faster:

| Seam | What changes |
|---|---|
| `CombatEngine` | a rider charges; a wagon is a wall to fight behind |
| `AgentMotion` + `motions.json` | a rider is drawn on the animal, a driver in front of the cart |

### And one the map owed the world

Not a conveyance seam, but found next to them and the same fault: **arrivals
had no direction.** A raid picked its line with `rng.nextUnit() * 2 * .pi` and
a visitor picked one of four edges at random, so the tribe you can see to the
north on the world map came over your southern fence. Every region has a
`HexCoord`; none of it reached the valley. `Bearing` is the conversion, read by
the raid and the visit alike so they cannot disagree about where north is — and
it falls back to the old roll for anybody with no place on the map, which is
the right answer for a wanderer.

**Rule 34 applies twice here.** `WalkPace` counts in *local-map units per action
step*; the two travel functions count in *ticks per unit of distance*. One
`pace` number applied to both without conversion is the same class of bug as
walking being tuned per tick and judged per second. The multiplier is stated
once in the definition and converted at each seam — never copied.

## The data

```jsonc
{
  "id": "riding_horse",
  "name": { "en": "Riding horse", "cs": "Jezdecký kůň" },
  "description": { "en": "…", "cs": "…" },
  "era": "ancient",
  "class": "mount",                      // mount | cart | rail | motor | air
  "requires_animal": "horse",            // mounts only: which species it is
  "requires_building": "stable",
  "requires_tech": "husbandry",
  "materials": { "leather": 2, "wood": 4 },
  "riders": 1,
  "cargo": 3,                            // multiples of a colonist's back
  "pace": 2.2,                           // × WalkPace, on the local map
  "region_pace": 1.8,                    // × the road, between places
  "upkeep": { "food": 0.4 },             // per tick, per conveyance
  "terrain": ["grass", "meadow", "dirt", "sand", "heath"],
  "combat": { "charge": 1.4 }
}
```

Every later age uses this same schema and nothing else. That is the test of
whether the abstraction is right:

| Era | Examples | What is interesting about them |
|---|---|---|
| Early settlement | travois, hand sledge | `pace` **below 1** — slower than walking, and carries. The first real trade-off |
| Ancient | riding horse, ox cart, pack mule | the split between fast-and-light and slow-and-heavy |
| Medieval | wagon, warhorse, river barge | barge: `terrain` is the *river*, so the map decides the route |
| Early industrial | steam locomotive, canal boat, stagecoach | rail needs a **link** between two settlements, not just a building |
| Modern | truck, tractor, cargo ship, airship | fuel upkeep, so a conveyance can be grounded by a shortage |
| Near future | hover sled, cargo drone, orbital lifter | `terrain: []` meaning *anything*, at a price nothing else charges |

### Terrain is what stops this being a straight upgrade

A cart cannot cross marsh or scree. A horse cannot take a mountain pass a mule
walks. An airship does not care and eats fuel the whole time. Without this, every
conveyance is strictly better than the last and the choice is "have you unlocked
it yet" — which is not a choice. `GroundCover` has twenty kinds and
`LocalMap` already knows which is where; `terrain` is the list a conveyance may
cross, and a route that needs a cover outside it either takes the long way or
goes on foot.

This is also what makes the **biomes** worth generating: a marsh colony wants
barges and a mountain colony wants mules, and that is a different game rather
than a different palette.

## The model

```swift
public struct Conveyance: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID                 // stable — rule 3, or every roll drifts
    public let definitionID: String
    /// A mount is backed by a beast the colony tamed; a cart is not.
    public var animalID: UUID?
    /// Who is on it, or driving it. Nil when it is standing in the yard.
    public var riderID: UUID?
    /// Wear, on the same 0…1 scale buildings use.
    public var condition: Double
    public var cargo: [HaulLoad]
}
```

Held on `Settlement.conveyances`, beside `tamed`. A mount's `animalID` points
into `Settlement.tamed`, so a horse is still an `Animal` with a body, wounds and
illnesses — a mount that can be hurt, and that dies when the wolf gets it.
`TamedRole` gains `.mount`; `beastOfBurden` stays what it is, because a pack
animal that nobody rides is a different thing from a saddle horse.

## What it burns

**A machine burns a thing, not a number.** The five `ResourceType`s are
abstractions — `energy` means "the colony has power", not a barrel of anything —
so a locomotive charged `upkeep: {energy: 2}` was a locomotive running on the
ledger. It burns **coal**: somebody mined it out of a seam, somebody hauled it
home, and somebody has to keep doing both. That is a supply line, and a supply
line is a thing the player can lose.

```jsonc
"upkeep": { "food": 0.35 },          // the ledger: what it costs to keep
"material_upkeep": { "coal": 3 }     // the shelf: what it actually drinks
```

The same split buildings already make between `cost` and `material_cost`, for
the same reason. `StableEngine.advanceOneTick` takes the fuel out of
`Settlement.stockpile` — **all of it or none of it**, because half a tank does
not half-run a locomotive, and taking the coal without moving the train is the
worst of both. A machine that cannot be fuelled does not run, and because it
does not run it does not wear either.

### The chain, end to end

| | |
|---|---|
| the ground | `LocalMapGenerator.depositMix` puts coal seams in the mountains and the tundra, oil seeps in the desert, the tundra and the coast — and **neither in a forest valley**, which is what makes the industrial ages a reason to settle somewhere else |
| the deposit | `RockKind.coalSeam` / `.oilSeep` → `LocalResourceKind.coal` / `.oilSeep`, mined by a miner like any other seam |
| the raw thing | `rawMaterialID` → the items `coal` and `crude_oil` |
| the refinery | `refine_petrol`, `refine_diesel`, `refine_jet_fuel`, `refine_kerosene` — all out of `crude_oil` at the `oil_refinery`, behind `combustion` and `chemistry` |
| the machine | `material_upkeep` on every `rail`, `motor` and `air` conveyance |

`ZZ` guards, in `StableEngineTests`: every machine burns something real, every
fuel is either dug or cooked, some country holds coal and some holds oil, and a
locomotive spends its coal and stands still without it.

**The council knows too.** `StewardEngine.canFeedIt` asks for `fuelRunway`
ticks' worth on the shelf before it builds another thing that drinks — otherwise
it would build the lorry and the lorry would stand in the yard for ever, which
is `upkeep` and `material_upkeep` being two different questions and only the
first one being asked.

## The rules this must not break

Each of these is a session someone already paid for.

- **Rule 14 — rate × entity count.** `upkeep` is per conveyance per tick. Forty
  horses eat forty times. The colony that buys a stable full of them must feel
  it, and `GrowthProbe` must be re-run after, not before.
- **Rules 16 and 17 — build off a rate, and reach the threshold.** The cheapest
  conveyance has to be affordable out of what a colony of twelve actually banks
  in its first years, or the whole system is late-game content that the early
  game never sees.
- **Rule 21 — a bank capped at the cheapest batch never pays for the dearest.**
  Whatever bank pays for conveyances must have a ceiling that reaches the
  costliest one in the file.
- **Rule 15 — autonomous dispatch is priced differently from a tap.** If the
  steward buys conveyances on its own, it will buy them constantly.
- **Rule 3 — stable ids.** A `Conveyance` created with a fresh `UUID()` each
  run breaks determinism exactly the way the founders did.
- **Rule 5 — presentation never writes the simulation.** A rider's position on
  the canvas is derived; the *fact* that they are mounted is the Core's.

## Order of work

Swift first, then generate — the whole point of writing this down.

1. ~~`ConveyanceDefinition`, `conveyances.json` with **three** hand-written
   entries, `GameDataRegistry` loading, and a test that counts what the
   *registry* holds (rule 43).~~ **Done 2026-08-19** — `ConveyanceBankTests`.
2. ~~`Settlement.conveyances`, `TamedRole.mount`, and `StableEngine`: build one,
   keep it fed, lose it when it starves or is killed.~~ **Done 2026-08-19** —
   `StableEngineTests`. `bestPace`, `bestRegionPace`, `cargoCapacity` and
   `canCross` are written and tested; **nothing reads them yet**, which is
   step 3.
3. ~~Pace at the four seams above, each with its own conversion and its own
   test.~~ **Done 2026-08-19** — `ConveyanceSeamTests`. `regionPace` *divides*
   at both travel seams, because those count ticks per distance and the
   definition states a speed; the haul seam multiplies. One number, converted
   at each seam rather than copied.
4. ~~`HaulEngine` cargo capacity — the seam that changes how the colony
   *feels*, because hauling is most of what it does.~~ **Done 2026-08-19**, and
   it needed a mechanic first: **a load had no size.** A hauler picked up the
   whole heap however big it was, so twelve logs and one log were the same
   walk and `cargo` had nothing to multiply. `HaulEngine.armfuls` is that size
   now, and the yard adds to it — what will not fit stays on the ground for
   the next trip, which is the pressure a cart is an answer to.
5. ~~Terrain routing: a conveyance refuses ground outside its `terrain`.~~
   **Done 2026-08-19** — `ConveyanceTerrainTests`. Two questions, not one:
   `bestPace(_:from:to:)` samples the cells a walk across the valley actually
   crosses, and `bestRegionPace(_:crossing:)` reads the dominant cover of every
   biome a road runs through (`CaravanEngine.countryBetween`). A journey a
   conveyance cannot make is one it does not join, and the answer falls back
   to walking — never slower than feet, which are always available.
6. ~~Presentation: a `riding` activity in `AgentMotion`, `serves_conveyance` in
   the motion bank, and a figure drawn on the beast.~~ **Done 2026-08-19**, and
   it needed a mechanic first, again: **nothing in a running game had ever
   built one.** `StableEngine.advanceOneTick` had no caller outside its own
   tests, so in play no cart wore out, no fuel was burned, no beast was lost
   and every one of the four seams read an empty yard — the whole system was a
   picture of a horse. Wired into `TickEngine` now, with
   `StewardEngine.keepTheYard` deciding to build one (capped at a conveyance
   per six colonists — rule 14) and `StableEngine.assignRiders` putting the
   people who are actually carrying something on them. Only then the drawing:
   `SettlementConveyances` composes a vehicle out of what its definition
   already says — undercarriage, cover, draught, bed — so sixty entries are
   sixty pictures rather than sixty copies of four. A mount's beast is drawn
   under its rider by `SettlementWildlife.body`, and is no longer also drawn
   circling the pen.
7. **Then** generate forty to sixty conveyances across all six eras, plus the
   buildings (stable, wainwright, garage, airfield — **written 2026-08-19**),
   the techs (husbandry, the wheel, rail, combustion — all already in the DAG)
   and the events that come with them — a horse thrown, a wagon lost at a ford,
   the first train.

   **There are no horses.** `AnimalSpecies` is deer, boar, hare, fox, wolf,
   bear, elk, goat, lynx, badger, grouse, so a mount names one of those or it
   is a conveyance the colony can never build. This is a better constraint than
   it looks: an elk train and a goat cart are this world's, and a generated
   "riding horse" is the same dead entry as a tech that does not exist.

Steps 1–6 are perhaps a day. Step 7 is an afternoon and can produce hundreds of
entries, which is the correct ratio and the reason for doing them in this order.

## What generating first would produce

A `conveyances.json` with sixty beautiful bilingual entries, a green build, a
green `ContentTests`, and a colony that walks everywhere. That is not a
hypothetical: it is what happened to the motion bank, where a third of the
clips loaded perfectly and had never been drawn.
