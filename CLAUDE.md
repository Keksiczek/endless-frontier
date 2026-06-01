# CLAUDE.md — Endless Frontier

## Project overview

Endless Frontier is a persistent civilization / colony simulation for iOS (Swift / SwiftUI). It is a solo-developer project built incrementally in phases. Read `docs/DESIGN.md` and `docs/ROADMAP.md` before touching any code.

## Repository layout

The simulation is a **platform-agnostic Swift Package** (`Core/`), so the
deterministic engine builds and tests with `swift test` on macOS — no iOS
simulator needed. The iOS app (`App/`) is a thin SwiftUI shell that depends on
the package. This is the physical realisation of the "three layers strictly
separated" rule: Layers 1 & 2 live in the package, the UI lives in the app.

```
endless-frontier/
├── CLAUDE.md                 This file
├── docs/
│   ├── DESIGN.md             Full game design document
│   ├── ROADMAP.md            Phased implementation plan
│   ├── architecture/         Architecture diagrams
│   ├── data-schemas/         JSON schemas for game data
│   └── events/               Authored event content (reference)
├── Core/                     Swift Package — EndlessFrontierCore
│   ├── Package.swift
│   ├── Sources/EndlessFrontierCore/
│   │   ├── Models/           WorldState, Settlement, Region, Resources, Era
│   │   ├── Engine/           SeededRNG, ResourceLoop, TickEngine, TechEngine,
│   │   │                     EraEngine, GameEngine, GameWorldFactory
│   │   ├── Storyteller/      StatPath, EventEffect/Condition/Template,
│   │   │                     WorldQuery, EffectApplier, TensionCalculator,
│   │   │                     StoryPlanner
│   │   ├── Data/             *Definition types + GameDataRegistry, WorldConfig
│   │   ├── Persistence/      WorldStore (JSON on disk)
│   │   └── Resources/GameData/  buildings/techs/eras/biomes/events/world-config
│   └── Tests/EndlessFrontierCoreTests/
└── App/                      iOS app (XcodeGen-generated project)
    ├── project.yml           Run `xcodegen generate` to (re)create the project
    └── Sources/              SwiftUI: EndlessFrontierApp, GameViewModel, Views/
```

> **Layer 3 (LLM narrator)** is not built yet (Phase 3). It will be a separate
> module/protocol the app talks to; the Core stays narrator-agnostic.

## Key design rules

1. **Three layers are strictly separated.** The Narrator never writes WorldState. The Storyteller only mutates state through typed effect structs. The Core has no dependency on Layer 2 or 3. See `docs/architecture/LAYERS.md`.

2. **All game content is data-driven.** Buildings, techs, eras, biomes and events live in `GameData/*.json`. Adding content = adding JSON, not Swift code.

3. **Deterministic simulation.** The seeded RNG state is stored in `WorldState`. Given the same seed and inputs, the world evolves identically. This makes testing straightforward.

4. **Offline-first.** No URLSession in the simulation path. LLM narrator is an optional enhancement, never a requirement.

5. **Codable persistence.** `WorldState` is encoded to JSON and saved to the app's Documents directory on every meaningful state change.

## Current phase

**Phase 0 ✅ and Phase 1 ✅ complete.** The deterministic core, data-driven
content (buildings/techs/eras/biomes/events), tech & era progression, and the
full storyteller engine (tension + planner) are implemented and tested (29
tests). A SwiftUI dashboard app reads the live world. Next: Phase 2
(exploration, multi-city, scheduled/duration effects) — see `docs/ROADMAP.md`.

## Running tests

The core is tested without a simulator:

```bash
cd Core && swift test
```

Build the iOS app (regenerate the project first if `project.yml` changed):

```bash
cd App && xcodegen generate
xcodebuild -project App/EndlessFrontier.xcodeproj -scheme EndlessFrontier \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Coding conventions (Swift)

- Use `struct` for all model types; `class` only where reference semantics are required (e.g. `@Observable` view models).
- Engine functions are pure: `func advance(state: WorldState, ticks: Int) -> WorldState`.
- Avoid `@State` in engine or model layers — only in SwiftUI views.
- Target Swift 6 concurrency (sendable, actor isolation).
- No force-unwrap (`!`) in engine code. Use `guard let` or `if let`.
- All JSON loading goes through `GameDataRegistry`. Views never read JSON directly.

## Data file locations

All under `Core/Sources/EndlessFrontierCore/Resources/GameData/`, loaded at
startup by `GameDataRegistry.bundled()`:

| File | Purpose |
|---|---|
| `buildings.json` | Building definitions |
| `techs.json` | Tech tree DAG |
| `eras.json` | Era milestones |
| `biomes.json` | Biome definitions |
| `events.json` | Event templates (storyteller) |
| `world-config.json` | Tuning constants (tick rate, tension formula, etc.) |

The JSON schemas live in `docs/data-schemas/`. Validate new data files against the schema before committing.

## Where to look for context

- Game systems and formulas → `docs/DESIGN.md`
- What to build next → `docs/ROADMAP.md`
- Architecture rules → `docs/architecture/LAYERS.md`
- Event template schema → `docs/data-schemas/events.json`
- Tech tree schema → `docs/data-schemas/techs.json`
- Starter event examples → `docs/events/starter-events.json`
