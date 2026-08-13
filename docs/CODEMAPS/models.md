# Models — what is an entity, and what is still a number

<!-- Generated 2026-08-13 | 46 models | ~800 tokens -->

The project has been converting *abstractions* into *entities* one layer at a
time. Every conversion follows one shape, and the remaining work is more
instances of it:

> A number that describes a thing → the thing itself → the number **derived**
> from the things → the number deleted.

## Conversion status

| Layer | Old number | Entity | Economy reads | Drawn | Done |
|---|---|---|---|---|---|
| Colonists | `population` | `Pawn` | ✅ entity | ✅ | ✅ |
| Wood | `forest` node | `Tree` (`Flora`) | ✅ entity | ✅ | ⚠️ node still a view |
| Stone | `stone` node | `Rock` / `StoneField` | ✅ entity | ✅ | ⚠️ node still a view |
| Goods on the ground | — | `HaulPile` | ✅ | ✅ | ✅ |
| Crops | `field` node | `Crop` (plots) | ✅ | ✅ | ✅ |
| Wild animals | `deerHerd` | `Animal` | ⚠️ **herd still drives yield** | ✅ | ❌ |
| **Buildings** | `BuildingInstance.count` | `BuildingPlacement` | ⚠️ count for output, **condition per placement** | ✅ | ⚠️ partly |
| Events | — | `EventTemplate` | n/a | ❌ text only | ❌ |

**The ❌ rows are the next phase**, and the buildings row is less of a
blocker than `NEXT_PHASE.md` claims — see below. See [../BACKLOG.md](../BACKLOG.md).

### What the buildings row actually is — narrower than it looks

`Settlement.buildings` is `[BuildingInstance(definitionID:count:)]` — a tally.
`ColonyMap.placements` holds the real, sited, footprinted buildings, and the two
are kept in sync by hand in `ColonyBuilder.place`/`remove`.

**Correction (2026-08-13).** `NEXT_PHASE.md` says "a building has no condition,
nothing can be damaged", and the first draft of this file repeated it without
checking. It is **out of date**. `BuildingPlacement.condition` exists and is
live: `BuildingEngine` has `derelictBelow` and `repairBelow`,
`ColonyBuilder.clearedOfDerelicts` pulls wrecks down for their ground, and
`ResourceLoop.staffingFactors` folds soundness into output — a workshop with the
roof off produces less, a derelict one nothing.

What is *actually* still missing:

- Production is averaged **per definition id**, not per building, so two
  granaries are one entry with a mean condition. One cannot be the old one that
  leaks.
- The ledger and the placements are kept in step by hand, which is a
  correctness burden with no upside.

Consequently this row is a **tidy-up with modest payoff**, not the unlock it was
billed as. It does *not* block:

- **§11.26 durability** — that needs `ItemInstance.quality` to be mutable in
  practice (it is written in `init` and never again anywhere in the codebase),
  not building conversion.
- **§11.27 cover / turrets** — that needs a **height** and a solidity on
  `Landform`, `Flora` and the rocks, none of which have either.
  `BuildingDefinition.floors` is not it: it is read only by `HouseholdEngine`,
  is never drawn, and measures *upward*, while cover is decided at the height of
  a person standing on the ground.

## Derived, not stored

These are computed and must never be set directly:

| Value | Derived from |
|---|---|
| `Settlement.population` | `pawns.count` |
| housing capacity | placements' footprint × `floors` (`HouseholdEngine`) |
| `Settlement.storageCapacity` | standing buildings' typed `storage` (`ResourceLoop`) |
| `Tree.growth`, `timberYield` | `age` / `species.maturityTicks` |
| a colonist's appearance | `PawnLook.of(pawn, ageYears:)` — pure, stored nowhere |
| positions on the canvas | `(id, frame clock)` via `AgentMotion` |

## The world's shape

```
WorldState
 ├ settlements: [Settlement]
 │   ├ pawns: [Pawn]          (+Genes, Body, Relationship, Job)
 │   ├ buildings: [BuildingInstance]     ← the tally
 │   ├ colony: ColonyMap                 ← the build grid + placements
 │   ├ localMap: LocalMap                ← the valley: trees, rocks, crops,
 │   │                                      piles, landforms, wildlife, fog
 │   ├ storage: Resources                 (food/materials/energy/knowledge/influence)
 │   ├ storageCapacity: Resources         ← typed per resource, 2026-08-13
 │   ├ stockpile: [String: Int]           ← concrete items (wood, timber_bundle…)
 │   ├ society, faith, laws, policy, journal, constructions, craftOrders
 │   └ captives, expeditions, tamed
 ├ regions: [Region]          the hex world
 ├ tribes: [Tribe]            emergent neighbours
 ├ era, tick, mapSeed, researchedTechs, unlockedBuildings
 └ chronicle: [WorldRecord]   one per in-game year
```

## Two resource spaces, deliberately

| | `Resources` (abstract) | `stockpile` (concrete) |
|---|---|---|
| Holds | food, materials, energy, knowledge, influence | `wood`, `timber_bundle`, `rough_stone`, `leather`… |
| Capped by | `storageCapacity` per resource | `CookingEngine` roof for foodstuffs only |
| Feeds | the ledger, building `cost` | recipes, building `material_cost` |

**A building needs both.** `material_cost` in `buildings.json` is paid from the
*stockpile*, and that is a separate gate from `cost`. A colony rich in
`materials` and out of `timber_bundle` can build nothing — this froze the game
for 120 years until `FloraEngine.reseeded` landed.

## Codable and saves (rule 3)

Every new field decodes with `decodeIfPresent` and a sane default. Two live
migrations worth knowing: `Pawn.haulPosition` → `haulWalk` (a point becomes a
`WalkPath` that stands still), and `Settlement.storageCapacity` `Double` →
`Resources` (one number reads as every store that deep).
