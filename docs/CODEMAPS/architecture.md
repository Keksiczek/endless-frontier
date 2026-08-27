# Architecture

<!-- Generated 2026-08-13 | Core: 65 engines, 46 models | App: 72 sources | ~900 tokens -->

## The three layers, and the one rule between them

```
┌── Layer 3  Narrator (LLM)  — NOT BUILT (Phase 3)
│              reads WorldState, writes prose. Never writes state.
├── Layer 2  Storyteller/    — picks EventTemplates, mutates ONLY via typed effects
│              StoryPlanner → EventTemplate → EffectApplier → WorldState
└── Layer 1  Core/           — deterministic simulation. Knows nothing of 2 or 3.
```

`App/` is a thin SwiftUI shell over Layer 1. **Presentation never writes the
simulation** (rule 1): the canvas derives positions from `(pawn.id, frame clock)`
and nothing it does feeds back.

## Package layout

```
Core/Sources/EndlessFrontierCore/
  Models/       46 types — the world's nouns (Pawn, Settlement, Animal, LocalMap…)
  Engine/       65 enums — the world's verbs. All pure: (state, registry) -> state
  Storyteller/  Layer 2 — EventTemplate/Effect/Condition, StoryPlanner, TensionCalculator
  Data/         *Definition types + GameDataRegistry + WorldConfig (JSON-backed)
  Persistence/  WorldStore (JSON on disk), SaveMigrator
  Resources/GameData/  the content itself — see data.md
App/Sources/
  GameViewModel.swift   the only bridge; owns catch-up, runs off the main actor
  Views/Settlement/     the living canvas — see app.md
```

## One tick, in order

`TickEngine.advance(state:ticks:registry:)` — this order is load-bearing.

```
per tick:
  ActionLoop × actionStepsPerTick   ← sub-tick: marches, shifts, fights
  ResourceLoop                      ← the big one, see below
  MultiCityEngine → SupplyEngine → CaravanEngine
  VisitorEngine → CaptiveEngine     ← the world arriving on foot
  tick += 1
  ScheduledEffectEngine → ExplorationEngine
  CraftingEngine                    ← after gathering, so the shelf is stocked
  StewardEngine                     ← the council: study, stock, raise, send out
  TechEngine → EraEngine → QuestEngine
  SocietyEngine        (every ticksPerYear)
  FestivalEngine       (midsummer — half a year off the above, deliberately)
  GenerationEngine     ← coming of age
  StoryPlanner         (every plannerInterval)
```

`ResourceLoop.advanceOneTick` inside that: production → artifacts → adjacency →
laws → **domestic draw** (energy + administration, scaled by *people* not
buildings) → storage clamp → morale/stability/defense/pollution drift →
`LaborEngine` → construction → `PawnEngine` (needs, mood, skilled work) →
medicine → taming → deposits & regrowth → **haul** → scouts.

## Data flow for one decision

```
player taps           →  GameViewModel  →  GameEngine.build(...)
nobody taps           →  StewardEngine.nextBuilding(...)  ← same GameEngine call
                            ↓
                     ColonyBuilder.place → ColonyMap.placements
                            ↓
                     Settlement.buildings (a COUNT — see models.md, still unconverted)
```

## Determinism (rule 2)

Never `Date()` or an unseeded RNG in the engine path. Per-entity randomness comes
from `SeededRNG(seed:)` derived from `(mapSeed, entity.id, tick-or-year)` — so
**entities need stable ids**. A settlement created with a random `UUID()` draws
different rolls every run and silently breaks determinism.

## Where to look

| Question | File |
|---|---|
| What must not break | [../RULES.md](../RULES.md) — 107 rules, each cost a session |
| What to build next | [../BACKLOG.md](../BACKLOG.md) — the living plan |
| Engine responsibilities | [engines.md](engines.md) |
| What is an entity vs a number | [models.md](models.md) |
| Content files | [data.md](data.md) |
| The canvas | [app.md](app.md) |
| Diagnostic probes | [probes.md](probes.md) |
