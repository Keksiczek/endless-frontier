# CLAUDE.md — Endless Frontier

## Project overview

Endless Frontier is a persistent civilization / colony simulation for iOS (Swift / SwiftUI). It is a solo-developer project built incrementally in phases. Read `docs/DESIGN.md` and `docs/ROADMAP.md` before touching any code.

## Repository layout (target — not all directories exist yet)

```
EndlessFrontier/              Xcode project root
├── CLAUDE.md                 This file
├── docs/
│   ├── DESIGN.md             Full game design document
│   ├── ROADMAP.md            Phased implementation plan
│   ├── architecture/         Architecture diagrams
│   └── data-schemas/         JSON schemas for game data
├── EndlessFrontier/          Swift source
│   ├── App/                  App entry point, DI container
│   ├── Models/               WorldState, Settlement, Resource, etc.
│   ├── Engine/               TickEngine, TechEngine, ExplorationEngine
│   ├── Storyteller/          TensionCalc, EventRegistry, StoryPlanner
│   ├── Narrator/             LLMNarratorProtocol, StubNarrator, LocalLLMNarrator
│   ├── GameData/             JSON files: buildings, techs, eras, biomes, events
│   └── UI/                   SwiftUI views
└── EndlessFrontierTests/     Unit + integration tests
```

## Key design rules

1. **Three layers are strictly separated.** The Narrator never writes WorldState. The Storyteller only mutates state through typed effect structs. The Core has no dependency on Layer 2 or 3. See `docs/architecture/LAYERS.md`.

2. **All game content is data-driven.** Buildings, techs, eras, biomes and events live in `GameData/*.json`. Adding content = adding JSON, not Swift code.

3. **Deterministic simulation.** The seeded RNG state is stored in `WorldState`. Given the same seed and inputs, the world evolves identically. This makes testing straightforward.

4. **Offline-first.** No URLSession in the simulation path. LLM narrator is an optional enhancement, never a requirement.

5. **Codable persistence.** `WorldState` is encoded to JSON and saved to the app's Documents directory on every meaningful state change.

## Current phase

**Phase 0 — not started.** See `docs/ROADMAP.md` for deliverables.

## Running tests

```bash
xcodebuild test -scheme EndlessFrontier -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Coding conventions (Swift)

- Use `struct` for all model types; `class` only where reference semantics are required (e.g. `@Observable` view models).
- Engine functions are pure: `func advance(state: WorldState, ticks: Int) -> WorldState`.
- Avoid `@State` in engine or model layers — only in SwiftUI views.
- Target Swift 6 concurrency (sendable, actor isolation).
- No force-unwrap (`!`) in engine code. Use `guard let` or `if let`.
- All JSON loading goes through `GameDataRegistry`. Views never read JSON directly.

## Data file locations

| File | Purpose |
|---|---|
| `GameData/buildings.json` | Building definitions |
| `GameData/techs.json` | Tech tree DAG |
| `GameData/eras.json` | Era milestones |
| `GameData/biomes.json` | Biome definitions |
| `GameData/events.json` | Event templates (storyteller) |
| `GameData/world-config.json` | Tuning constants (tick rate, tension formula, etc.) |

The JSON schemas live in `docs/data-schemas/`. Validate new data files against the schema before committing.

## Where to look for context

- Game systems and formulas → `docs/DESIGN.md`
- What to build next → `docs/ROADMAP.md`
- Architecture rules → `docs/architecture/LAYERS.md`
- Event template schema → `docs/data-schemas/events.json`
- Tech tree schema → `docs/data-schemas/techs.json`
- Starter event examples → `docs/events/starter-events.json`
