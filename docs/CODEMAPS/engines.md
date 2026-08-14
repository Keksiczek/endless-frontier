# Engines — who owns what

<!-- Generated 2026-08-13 | 65 engines | ~950 tokens -->

All engines are `enum` namespaces of pure static functions:
`(state, registry) -> state`. None hold state. Ordered by the tick, not
alphabetically — see [architecture.md](architecture.md) for the running order.

## The spine

| Engine | Owns |
|---|---|
| `TickEngine` | The tick. Calls everything below in a fixed order. |
| `ActionLoop` | Sub-tick steps (`WorldClock`) — marches, shifts, blows landing, **and everybody walking** (`ErrandEngine`, `HaulEngine`). |
| `ResourceLoop` | Production, consumption, storage caps, morale/stability/defense/pollution drift. The biggest file; read its numbered steps. |
| `GameEngine` | The player's verbs: build, demand, gift. `build` sites *before* it pays. |
| `StewardEngine` | **The council** — what runs the colony when nobody taps. Research, materials, buildings, expeditions, founding. Acts only in the gaps. |

## People

| Engine | Owns |
|---|---|
| `PawnEngine` | Needs, mood, skilled work, starvation, death. Food is eaten here, not in `ResourceLoop`. |
| `PawnFactory` | Making a colonist — genes, name, look inputs. |
| `PopulationEngine` | Births. `headroomFactor` is the growth throttle (rule 19). |
| `GenerationEngine` | Coming of age, the old at the elbow of the young. |
| `LaborEngine` | Who does what. `staffingInterval` = 10 (rule 4). Quotas per trade. |
| `HouseholdEngine` | Homes, families, who sleeps where. Derives housing from footprint + `floors`. |
| `SocialEngine` | Bonds, quarrels, marriages. Was the quadratic (rule 20). |
| `ComfortEngine`, `MedicineEngine`, `PlagueEngine` | Warmth, wounds, illness. |
| `ErrandEngine` | A colonist's own business — eat, warm up, rest. `WalkPath` per leg, on the **action step** (`WalkPace`). |

## The food chain (a chain, not a number)

```
FarmEngine   plots ripen with season+weather
   ↓         a farmer reaps → raw crop lies at the plot
HaulEngine   somebody carries it in → Settlement.stockpile
   ↓
CookingEngine  a cook turns raw → storage[.food]  ( = MEALS, nothing else)
   ↓
PawnEngine   colonists eat
```
`HuntEngine` yields meat, foraging yields berries — both enter the same chain.
Two valves: no cookhouse = cooking over the fire at half rate; no cook = eating
raw off the shelf badly.

## The land

| Engine | Owns |
|---|---|
| `LocalMapGenerator` | The valley: terrain, landforms, trees, rocks, deposits. |
| `MapGenerator` | The hex world beyond it. |
| `FloraEngine` | Trees as entities — growth, felling, **reseeding**. |
| `StoneEngine` | Rock as blocks. |
| `ColonyBuilder` | Siting a building: fit, `grownOutward`, `clearedOfDerelicts`. |
| `ColonyRoute` | Pathing. `Occupancy` answers tile → placement from a flat array. |
| `HaulEngine` | Carrying goods in, per **action step**. Routes once per walk, not per step (rule 4). |
| `ConstructionEngine`, `BuildingEngine` | Raising and repairing. `condition`, `derelictBelow`. |

## The wild

`WildlifeEngine` (herds, ageing the wood), `AnimalEngine` (per-animal think),
`HuntEngine`, `TamingEngine`, `BanditEngine` (temptation ∝ full stores).

## Society, faith, neighbours

`SocietyEngine` (wages → classes → gini → unrest, elections, the assembly),
`FaithEngine`, `DiplomacyEngine`, `MultiCityEngine`, `SupplyEngine`,
`CaravanEngine`, `VisitorEngine`, `CaptiveEngine`, `ExpansionEngine`,
`ExplorationEngine`, `RegionExpeditionEngine`, `SiteEngine`, `SiteVisitEngine`,
`LocalPOIEngine`.

## Making and fighting

`CraftingEngine` (the bench; recipes), `QuartermasterEngine` (arms and coats —
publishes its own material wants, rule 32), `ItemEngine`, `CombatEngine`,
`BattleResolver`, `SiegeEngine`.

## Progression and record

`TechEngine` (research draws banked knowledge, leaving `knowledgeReserve`),
`EraEngine`, `QuestEngine`, `ObjectivesEngine`, `ChronicleEngine`,
`FestivalEngine`, `ScheduledEffectEngine`.

## Support

`SeededRNG` (the only randomness), `NameForge`, `GameWorldFactory`,
`GameDataRegistry` (all JSON loading), `BalanceHarness`, `WorldReport`.

## Cadences (rule 4)

Anything O(entities) runs on an interval, never every tick:

| Constant | Value | Used by |
|---|---|---|
| `LaborEngine.staffingInterval` | 10 | staffing, flora ageing |
| `FloraEngine.reseeded` | ×10 of the above (100) | tree regrowth |
| `StewardEngine.interval` | 60 (~a season) | the council sitting |
| `AnimalEngine.thinkInterval` | 10 | per-animal decisions |
