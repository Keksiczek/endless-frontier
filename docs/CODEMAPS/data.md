# Content — the data files

<!-- Generated 2026-08-13 | counts re-verified 2026-08-28 | 21 files | ~700 tokens -->

**All game content is data.** Adding content = adding JSON, not Swift. Everything
loads through `GameDataRegistry.bundled()`; views never read JSON directly.

`Core/Sources/EndlessFrontierCore/Resources/GameData/`

| File | Entries | What it defines |
|---|---|---|
| `buildings.json` | 63 | Cost, production, footprint, `storage` (typed per resource), `sleepers`/`floors`, `work`, `look`, adjacency |
| `techs.json` | 60 | The tech DAG. `knowledgeCost`, `requires`, `repeatable` |
| `eras.json` | 5 | Milestones gating each age (tech / stat / population / settlements) |
| `biomes.json` | 7 | plains, forest, desert, tundra, mountains, coast, wetlands |
| `events.json` | 182 | Storyteller templates — conditions, weights, effects, choices |
| `items.json` | 477 | Equipment, materials, artifacts. Rarity, slots, combat profile |
| `recipes.json` | 420 | `outputItemID` ← `materials` + `requiresBuilding` |
| `meals.json` | 47 | What a cook can make out of the harvest |
| `laws.json` | 30 | What the assembly votes on. `modifiers`, and `vote_bias`: the four genes, `poor_favour`, and `trade_favour` — what the law is worth to each trade's living |
| `cults.json` | 21 | Faiths a temple can seed |
| `plagues.json` | 17 | Illnesses |
| `quests.json` | 7 | Multi-stage chains |
| `motions.json` | 129 | **How a body moves.** Each part of the figure as a wave (`amplitude`/`frequency`/`phase`), plus `lean`, `bob`, `slouch`, `reach`. `serves_activities` + `serves_work` say which colonists it may be chosen for — without those a clip loads and is never seen |
| `animals.json` | 11 | The wild and the tamed as **kinds**: `build`, diet, size, `baseHealth`, comfort band, biomes, `tameability` |
| `flora.json` | 8 | Trees as data (rule 95): `crown`, `timber`, `maturityTicks`, `hardiness`, biomes |
| `conveyances.json` | 46 | Mounts and vehicles in one bank — `riders`, `cargo`, `pace`, `region_pace`, `terrain` |
| `fittings.json` | 245 | What stands **inside** a building: `shape`, `role`, `tint`, which `rooms` and which `eras` |
| `ground.json` | 20 | The ground's own colours and textures, read by the canvas (rule 9 — opaque) |
| `structures.json` | 63 | **How each building is put together** — `standing`, roof, fabric, what stands beside it. One per building: 51 of 63 share a `look` and the drawing never spent the difference (rule 107). See [RENDER_25D.md](../RENDER_25D.md) |
| `scenery.json` | 23 | The colours of everything scattered over the ground |
| `map-gen.json` | 11 keys | Hex world generation tuning |
| `world-config.json` | 8 groups | **Every tuning constant** — see below |

Schemas live in `docs/data-schemas/`. Validate before committing.

## Bilingual, always (rule 7)

Every player-facing string is `LocalizedText` with `en` + `cs`. Guarded two ways:

- `ContentTests` — "Every line of content reads in Czech as well as English"
  walks **all** of `GameData`, so a new entry cannot ship half-translated.
- `UIStringsTests` (App) — "No panel greets a Czech player in English" walks
  `App/Sources/**/*.swift` for `Text("…")` literals.

The app translates **four** ways: `AppStrings`, `LocalizedText` from the Core, an
inline `cs ? "…" : "…"`, and a local `s(_:_:)` some views declare. The test
accepts all four; consolidating them is open work.

## `world-config.json` — the constants that move the game

Grouped. The ones that have caused trouble, with the rule they taught:

| Key | Note |
|---|---|
| `realSecondsPerTick`, `ticksPerYear` | A tick is 2 real minutes; a year is 60 ticks, ~2 hours |
| `upkeepRateOfCost` | **Per tick.** × 60 = per year (rule 24) |
| `defaultStorageCapacity` | 500, applies to every resource before buildings |
| `energyPerPersonPerTick` × `eraEnergyDemand[era]` | Demand scales with **people**, supply with **buildings** |
| `influencePerPersonPerTick`, `influencePerSettlement` | Administration |
| `knowledgeReserve` | What research leaves banked so buildings priced in knowledge are buyable at all |
| `repeatableTechCostGrowth` | Keeps endless research a sink |
| `selfGoverningPopulation` | Below this, no administration cost |

## Two costs on a building, two stores

`cost` is paid from `Settlement.storage` (abstract `Resources`).
`material_cost` is paid from `Settlement.stockpile` (concrete items).
**Both must be met.** A colony with 5500 `materials` and no `timber_bundle` can
build nothing — see [models.md](models.md).
