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
| **Buildings** | `BuildingInstance.count` | `BuildingPlacement` | ❌ **reads the count** | ✅ | ❌ |
| Events | — | `EventTemplate` | n/a | ❌ text only | ❌ |

**The three ❌ rows are the next phase.** See [../BACKLOG.md](../BACKLOG.md).

### Why the buildings row matters most

`Settlement.buildings` is `[BuildingInstance(definitionID:count:)]` — a tally.
`ColonyMap.placements` holds the real, sited, footprinted buildings, and the two
are kept in sync by hand in `ColonyBuilder.place`/`remove`. Consequences:

- A building has **no `condition` of its own**, so nothing can burn, wear out or
  be damaged individually. Two granaries are indistinguishable.
- It blocks §11.26 (durability) and §11.27 (buildings as cover / turrets)
  outright — you cannot damage or shoot at a row in a ledger.

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
