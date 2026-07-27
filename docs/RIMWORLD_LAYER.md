# The RimWorld Layer — embodied buildings, embodied wildlife

How Endless Frontier stopped being a spreadsheet with glyphs on top and started
being a *place*. This document covers the direction, what has actually landed,
and what the next slices are.

Reference for the engine ideas being borrowed: see the RimWorld/Verse notes in
`docs/DESIGN.md` and the north star in `docs/ROADMAP.md`. This is a reference
for *direction*, not a porting spec — the useful borrowings are conceptual.

**Landed as of `7782249` (PR #6, 2026-07-22).** 536 Core tests green.

---

## 1. The two guiding ideas

| Idea | Meaning here |
|---|---|
| **A building is ground it owns, not a glyph** | A structure covers real tiles. It has a lot, it blocks that lot, people work *inside* it. |
| **An animal is a pawn with a lighter mind** | Wildlife is not a `Double`. It's an entity with a body, a sex, an age, wounds and illnesses — the same *kind* of thing a colonist is. |

Both replace an abstraction with an entity. That's the whole thrust of the
layer: things the player can look at and point to, instead of numbers the
simulation privately reasons about.

---

## 2. Buildings own ground

### 2.1 The footprint pipeline

Footprint flows from JSON to pixels through five stages. Each stage is worth
knowing because a change at any one of them is silently a change to all of them.

```
buildings.json           "footprint": { "w": 3, "h": 2 }
      │
      ▼
BuildingDefinition       let footprint: TileSize        (decodeIfPresent → 1×1)
      │                  TileSize maps w/h → width/height, clamped to ≥ 1
      ▼
ColonyBuilder            fits() / place() / remove() / centerFit()
      │                  every tile of the footprint must be in bounds & free
      ▼
BuildingPlacement        coord (TOP-LEFT origin) + width + height
      │                  .footprint → [TileCoord], every tile it covers
      ▼
SettlementRenderer       gridLayout() → NormalizedBuilding
      │                  footprintW/H in canvas fractions; centre nudged from
      │                  the top-left origin to the middle of what it covers
      ▼
floorPlot()              draws the lot — before any structure
```

Two details that are easy to get wrong:

- **`coord` is the top-left origin, not the centre.** `gridLayout` nudges the
  draw point by `(width-1)/2` and `(height-1)/2` tiles to centre the glyph on
  the ground it covers. Treating `coord` as a centre puts every multi-tile
  building half a lot off.
- **Lots are drawn in a separate pass, before any structure.** Otherwise a
  later building's lot paints over an earlier building's roof. See
  `SettlementRenderer.buildings(...)` — the `floorPlot` loop runs to completion
  first, then the structure loop.

### 2.2 The footprint table

43 of 47 buildings occupy multi-tile ground, sized to what they are. Capped at
3×3 — the goal is *bigger area*, not "large buildings win". The grid stays
12×12, so placement, seeding and balance all still hold.

| Size | Count | Buildings |
|---|---|---|
| **1×1** | 4 | hut, well, palisade, watchtower |
| **2×1** | 6 | hunters_lodge, windmill, observatory, stone_walls, aqueduct, bloomery |
| **2×2** | 17 | longhouse, lumberyard, quarry, library, trade_post, school, barracks, granary, bank, workshop, foundry, chemical_plant, clinic, electronics_lab, data_center, ai_core, orbital_array |
| **3×2** | 12 | farm_basic, farm_advanced, market, power_plant, railyard, hydro_dam, oil_refinery, vehicle_works, assembly_plant, apartment_block, solar_array, wind_farm |
| **3×3** | 8 | university, factory, hospital, research_campus, automated_factory, fusion_reactor, spaceport, arcology |

Point structures (a well, a fence post, a watchtower) stay 1×1 deliberately —
they are *points*, and inflating them would read as wrong.

### 2.3 The lot on screen

`SettlementRenderer.floorPlot` draws packed, cleared earth the size of the
footprint:

- Filled dark warm brown (`0.20, 0.18, 0.15` at 60%) — warmer and darker than
  wild grass, so built ground reads as *ground people made*.
- Inset to 92% of the footprint, so neighbouring lots still read as separate
  parcels while an adjacent row knits into built-up land.
- A construction site reserves its ground with a **dashed** outline and a much
  fainter fill — the ground is claimed before the roof exists.
- Skipped entirely below 2px, so a zoomed-out town doesn't turn to mud.

### 2.4 Colonists work across the lot

Before: every worker whose job was "at a building" walked to its exact centre
and drifted there. A staffed workshop was five figures stacked on a pin.

Now `AgentMotion.WorkSite` carries the building's centre **and** its half-width
and half-height. A worker's stable position is derived from their `pawn.id`
within that rectangle — so a staffed building reads as people working across
its floor.

```
struct WorkSite {
    let center: LocalPoint
    let halfW: Double        // from NormalizedBuilding.footprintW / 2
    let halfH: Double
}
```

Scene slots that became `WorkSite`: `civic` (temple/library — scholars and
priests), `workshop` (workshop/mill/generator), `granary` (traders), and every
active construction `site` (builders).

Unchanged by design: deposit work (fields, forest, quarry) already spread
across nodes, and the midday gathering on the green is *supposed* to be a
crowd in one place.

### 2.5 Buildings look like what they are

Forty-seven buildings used to be drawn as **eight** silhouettes, and the mapping
was blunt enough to be actively wrong:

- The Greek temple carried 12 of 47 — library, school, university, observatory,
  market, bank, trade post, all the same monument.
- Worse, every materials producer answered `ColonyBuilder.workKind` identically.
  Both `.logging` and `.mining` map to `materials`, and the scan takes the first
  maximum, so lumberyard, quarry, workshop, foundry and factory *all* resolved
  to `.logging` — every one of them drawn as the same waterwheel mill.

Now there are **13** archetypes (`house, hall, market, granary, workshop, plant,
tower, temple, mine, mill, generator, array, pad`), and a building's shape comes
from two places:

1. **What the numbers imply**, asked strongest-first: housing → house, defense →
   tower, `pollution >= 10` → plant, near-future influence → pad, energy → array
   in the near future else generator, knowledge → hall, influence → market, food
   or storage → granary, otherwise workshop.
2. **What the content says**, via an optional `look` on the building definition,
   which wins outright.

`look` exists because some shapes genuinely are *not* derivable — a lumberyard,
a quarry and a workshop all just "produce materials". It is an **opaque string**
in Core, which never interprets it; `SettlementRenderer.glyph(named:)` maps it,
and a test asserts every `look` in the content resolves, so a typo can't quietly
pick a shape. Eleven buildings state one: lumberyard/windmill → mill, quarry →
mine, hunters_lodge → workshop, aqueduct/hospital/clinic → hall, railyard →
plant, fusion_reactor → generator, arcology → pad, well → granary.

The result: the biggest silhouette now carries 11 of 47 (23%) instead of a
quarter of the town being one temple and most of the rest a waterwheel.

Two more things drive the look:

- **Era materials** (`SettlementStructures.materials`): timber and thatch warm
  into brick and soot, cool into concrete, then pale into panel and glass. A
  fusion-era colony is no longer drawn in wattle.
- **Footprint aspect**: box-bodied archetypes stretch to the lot they own
  (clamped to 0.6…1.7), so a 3×2 farm is long and a 2×2 workshop is square. The
  workshop's sawtooth roof grows a tooth per bay rather than stretching four.

### 2.6 Buildings vary

Every building of a kind used to draw identically — a row of houses was one
stencil repeated. Each placement now carries a stable `seed`:

- From the placement's `UUID` where there is one (`buildingSeed(_ uuid:)` packs
  the first 8 bytes), else from `(definitionID, ring index)` via FNV-1a for the
  fallback ring layout.
- The seed nudges **overall size** (±10%) and the **tone** of wall, roof and
  stone — lighter/darker and warmer/cooler, roughly ±5% (roof ±3.5%, it reads
  louder).

Same seed, same building, every frame and every launch. A row of houses reads
as a neighbourhood.

---

## 3. Wildlife as entities

`Core/Sources/EndlessFrontierCore/Models/Animal.swift` — the foundation slice.

### 3.1 The model

| Type | What it is |
|---|---|
| `AnimalSpecies` | deer, boar, hare, fox, wolf, bear. A **Flyweight** (the role `ThingDef` plays in RimWorld): `baseHealth`, `comfortLow`/`comfortHigh` in °C, `isPredator`, `displayName` (CZ+EN), `bodyPlan`. Traits live here so an instance stays light. |
| `AnimalBodyPartKind` | head, torso, and four legs. `isVital` (head/torso), `isLeg`. |
| `AnimalBodyPart` | `condition` 0…1 plus `missing`. |
| `AnimalConditionKind` | injury, disease, frostbite, heatstroke. |
| `AnimalCondition` | a lasting mark: kind, the part it sits on, `severity` 0…1, a localized label. |
| `Animal` | id, species, sex, `age` (in world ticks), `health`, `body`, `conditions`. |
| `AnimalFactory` | `herd(_:count:rng:)` and `wildPopulation(rng:)` — deterministic from a `SeededRNG`. |

Behaviour worth knowing:

- `isAlive` — health above zero **and** neither head nor torso missing.
- `canWalk` — a quadruped needs at least two legs; losing legs cripples rather
  than kills.
- `injure(_:by:)` — drains health, degrades the part (`amount / 40`), and when a
  part's condition hits zero it is **lost**; losing a vital part kills. Returns
  whether the animal survived.

Health is *stored*, not purely derived from body parts, so illness and
starvation can drain it independently of trauma.

### 3.2 How it's wired

`WildlifeState` now carries `animals: [Animal]` alongside the abstract
`deerHerd`/`deerCapacity`/`predatorPressure`.

`LocalMapGenerator` seeds a mixed wild population — 6 deer, 2 hares, 1 boar.
Predators are **not** seeded as residents; they arrive with pressure.

> **Determinism note.** `AnimalFactory.wildPopulation(rng:)` is called **last**
> in map generation, after deposits, scenery and POIs. Adding RNG draws
> anywhere earlier would shift every subsequent roll and change existing
> worlds. If you add wildlife generation, add it at the end.

### 3.3 What still drives the economy

The abstract `deerHerd` **still drives hunting**. The entities are the layer
that grows to take it over — they are not yet the source of truth for the food
loop. Don't wire hunting to `animals` until per-tick animal life exists.

---

## 4. Invariants this layer must not break

1. **Presentation never writes the simulation.** Footprint lots, per-building
   variation and lot-spread worker positions are *all* renderer-side. They read
   `ColonyMap` placements and `pawn.id`; nothing feeds back into `WorldState`.
   (`SettlementRenderer`, `SettlementStructures`, `AgentMotion`.)
2. **Determinism.** Every seed is derived from stable ids — a placement `UUID`,
   a `pawn.id`, the map seed. Never `Date()`, never an unseeded RNG. New RNG
   draws go at the *end* of a generation pass.
3. **Saves stay loadable.** `footprint` and `animals` both decode-if-present:
   an old save gets 1×1 buildings and no animals, and keeps playing.
4. **Content is data.** Footprints live in `buildings.json`, not in Swift. New
   building variety comes from data and composition, never from new glyph
   subclasses.
5. **Bilingual content.** Anything player-visible ships CZ+EN in the same
   change — `AnimalSpecies.displayName` is the pattern.

---

## 5. What's next

Roughly in dependency order.

### 5.1 Wildlife — finish what the foundation started

- **Per-tick animal life**: ageing, hunger, movement, death. An `AnimalEngine`
  alongside the other engines.
- **Hunting the entities**, so `deerHerd` can finally retire as the food source.
- **Temperature and disease** consuming `comfortLow`/`comfortHigh` and the
  condition kinds that already exist but nothing yet applies.
- **Per-species rendering** — a wolf should not be a recoloured deer.
- **Predators arriving with pressure**, rather than being map furniture.

### 5.2 Buildings — from lot to interior

- **Interiors**: a lot with a door, walls and a floor, not a decorated rectangle.
- **Pathing and LOS**: a footprint should *block*. Rock impassable until mined
  (`Building_Mineable`'s trick — mined to 0 hp, destroyed, spawns resources).
- **Room detection**: enclosed areas for further bonuses (already flagged as
  open in `NEXT_STEPS.md`).

### 5.3 The big lift — a real job layer

RimWorld's `JobTracker` + `ThinkTree`: a pawn scores available work by
priority, walks to it, does it, with opportunistic pickups en route. Endless
Frontier's equivalent is currently spread across `PawnEngine` / `LaborEngine` /
`SocialEngine` plus presentation-only `AgentMotion`.

A real job/think layer is what turns "colonists are drawn near the workshop"
into "colonists actually do things". It's the largest remaining item toward the
vision and should be planned as its own phase.

### 5.4 Not needed yet

Deliberately skipped — these are RimWorld's scaling machinery and Endless
Frontier is far smaller:

- **Region system** (spatial hash for ~O(1) nearest-lookups over 50k things) —
  we have tens of pawns.
- **Tick buckets** (Normal/Rare/Long) — the single tick plus `WorldClock`
  action-steps is fine.
- **Two-pass load with deferred cross-reference resolution** — Swift `Codable`
  plus resilient decoding already covers us. Revisit only if entity
  cross-references become cyclic.

---

## 6. File map

| Concern | File |
|---|---|
| Footprint data | `Core/…/Resources/GameData/buildings.json` |
| `TileSize`, definition decoding | `Core/…/Data/BuildingDefinition.swift` |
| `BuildingPlacement`, `ColonyMap` | `Core/…/Models/ColonyMap.swift` |
| Placement, collision, seeding | `Core/…/Engine/ColonyBuilder.swift` |
| Animal model + factory | `Core/…/Models/Animal.swift` |
| `WildlifeState.animals` | `Core/…/Models/LocalMap.swift` |
| Wild population seeding | `Core/…/Engine/LocalMapGenerator.swift` |
| Layout, lots, per-building seed | `App/…/Views/Settlement/SettlementRenderer.swift` |
| Structure drawing + tone variation | `App/…/Views/Settlement/SettlementStructures.swift` |
| `WorkSite`, lot-spread positions | `App/…/Views/Settlement/AgentMotion.swift` |
| Tests | `Core/Tests/…/AnimalTests.swift`, `ColonyBuilderTests.swift`; `App/Tests/SettlementRendererTests.swift` |
