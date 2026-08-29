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
│   ├── NEXT_STEPS.md         Prioritised backlog — what to build next
│   ├── RIMWORLD_LAYER.md     Building footprints + pawn-like animals
│   ├── architecture/         Architecture diagrams
│   ├── data-schemas/         JSON schemas for game data
│   └── events/               Authored event content (reference)
├── Core/                     Swift Package — EndlessFrontierCore
│   ├── Package.swift
│   ├── Sources/EndlessFrontierCore/
│   │   ├── Models/           WorldState, Settlement, Pawn (+Genes), Animal, Season,
│   │   │                     LocalMap/LocalTerrain, Crop, ColonyMap, Society, Diplomacy,
│   │   │                     Region, Era
│   │   ├── Engine/           SeededRNG, TickEngine, ResourceLoop, PawnEngine,
│   │                     FarmEngine, CookingEngine,
│   │   │                     PopulationEngine, LaborEngine, WildlifeEngine,
│   │   │                     SocietyEngine, FaithEngine, DiplomacyEngine,
│   │   │                     ChronicleEngine, LocalMapGenerator, MapGenerator,
│   │   │                     TechEngine, EraEngine, GameEngine, BalanceHarness
│   │   ├── Storyteller/      EventTemplate/Effect/Condition, WorldQuery,
│   │   │                     EffectApplier, TensionCalculator, StoryPlanner
│   │   ├── Data/             *Definition types, LocalizedText, GameDataRegistry,
│   │   │                     WorldConfig
│   │   ├── Persistence/      WorldStore (JSON on disk), SaveMigrator
│   │   └── Resources/GameData/  buildings/techs/eras/biomes/events/laws/cults/…
│   └── Tests/EndlessFrontierCoreTests/
└── App/                      iOS app (XcodeGen-generated project)
    ├── project.yml           Run `xcodegen generate` after adding a file
    └── Sources/              SwiftUI: EndlessFrontierApp, GameViewModel, Theme,
                              AppStrings (CZ/EN), Views/ (+ Views/Settlement/:
                              the living canvas, renderer, agent motion)
```

> **Layer 3 (LLM narrator)** is not built yet (Phase 3). It will be a separate
> module/protocol the app talks to; the Core stays narrator-agnostic.

## Key design rules

1. **Three layers are strictly separated.** The Narrator never writes WorldState. The Storyteller only mutates state through typed effect structs. The Core has no dependency on Layer 2 or 3. See `docs/architecture/LAYERS.md`.

2. **All game content is data-driven.** Buildings, techs, eras, biomes and events live in `GameData/*.json`. Adding content = adding JSON, not Swift code.

3. **Deterministic simulation.** Given the same seed and inputs, the world evolves identically — this is a hard invariant, and the tests lean on it heavily. Never call `Date()` or an unseeded RNG in the engine path. Per-entity randomness comes from a seed derived from `(mapSeed, entity.id, tick-or-year)`, so **entities need stable ids**: a settlement created with a random `UUID()` will draw different society/wildlife rolls on every run and silently break determinism (this has bitten us — see the fixed ids in the tests).

4. **Offline-first.** No URLSession in the simulation path. LLM narrator is an optional enhancement, never a requirement. Catch-up after a long absence (up to 30 days of ticks) runs **off the main actor** — see `GameViewModel.openSession`.

5. **Presentation never writes the simulation.** The living settlement canvas derives colonist positions from `(pawn.id, frame clock)`. Nothing the renderer does may feed back into `WorldState`.

5. **Codable persistence.** `WorldState` is encoded to JSON and saved to the app's Documents directory on every meaningful state change.

## Current state — V2

Endless Frontier **V2** merges the original deterministic colony sim with the
living-world and social systems of a Czech HTML civilisation sim. All V2 phases
(A–F) are complete. Current: **1622 Core tests in 227 suites green**
(`cd Core && swift test`, ~18 min) and **225 App tests in 35 suites**, iOS
build green.

Content, counted 2026-08-28: **63 buildings, 60 techs**, 182 events, **7
biomes**, 46 conveyances, **477 items, 420 recipes**, 129 motion clips,
47 meals, 30 laws, 21 cults, 7 quests. All bilingual CZ/EN, guarded by a test.

What the game is now:

- **A colony starts at seven and grows into a village.** Five named founders
  and two who came with them; a tick is two real minutes, so a year is two
  hours and the first fifty years — the ones where you know everybody — are
  a hundred hours of play. Size comes from the roofs (`headroomFactor` against
  housing), pace comes from `realSecondsPerTick`, and the birth rate only
  decides whether the place has a future. Measured by `GrowthProbe`.
- **Every inhabitant is a pawn** with genes (industry/fertility/sociability/
  courage), age, wealth and a life cycle — births mutate genes, so natural
  selection is visible in the chronicle. `Settlement.population` is *derived*
  from `pawns.count`; there is no macro headcount.
- **Food is a chain, not a number.** Farms own **plots** of tilled ground
  (`Crop`, `FarmEngine`); a plot ripens with the season and the weather and is
  *reaped* by a farmer. What comes off is grain/roots/greens lying at the plot,
  carried in by `HaulEngine` like timber, and a **cook** turns it into
  `storage[.food]` — which means *meals ready to eat* and nothing else
  (`CookingEngine`, `meals.json`). Hunting yields `meat`, foraging `berries`.
  Two valves keep a broken link from being fatal: no cookhouse means cooking
  over the fire at half rate, no cook means eating raw off the shelf badly.
- **A living settlement view** (`App/Sources/Views/Settlement/`): a
  `TimelineView`+`Canvas` line-art world with seeded ground tiles, biome-driven
  scenery and deposits, fog of war, seasons, and colonists who walk their day.
  Movement is *presentation-only* (`AgentMotion`) and never touches the sim.
- **Buildings own ground, wildlife are entities** — multi-tile footprint lots,
  per-building visual variation, workers spread across their building's floor,
  and pawn-like `Animal`s with bodies, wounds and illnesses. See
  `docs/RIMWORLD_LAYER.md`.
- **Society**: yearly wages → wealth classes (40th/85th percentiles) → Gini →
  uprisings and strikes; elections every 12 years; an assembly every 6 that
  votes on a data-driven law and puts it before **the player** to ratify or
  veto (overruling it costs morale).
- **Faith**: a temple raised by law seeds a cult; priests sustain devotion,
  prophets convert or sow doubt; belief lifts morale and softens disaster.
- **Neighbours**: tribes are *emergent* — colonists who walked out. Trade,
  scholars' exchange, marriage alliances, border disputes, war and defectors.
- **Chronicle**: one `WorldRecord` per in-game year, charted in-app, with
  generated insights (gene drift, inequality, the commonest death).

**Content is fully bilingual as of 2026-08-11.** Audited across every data file
— buildings, techs, eras, biomes, laws, cults, meals, items,
recipes, quests — and there are no English-only strings left. `events.json`
is guarded by "Every event narrates in Czech as well as English" in
`ContentTests`; the rest is guarded by "Every line of content reads in Czech as
well as English", which walks all of `GameData` rather than one file, so a new
entry cannot ship half-translated.

(This section used to say buildings and techs were still English-only. They were
translated at some point without the note being updated — do not trust a
"remaining work" line here without checking the files.)

## Running tests

There is a `Makefile` at the root — `make help` lists everything. Two commands
carry most of the work:

```bash
make verify-docs
```

Ten mechanical documentation checks (~2 s, no Xcode, no network): FMEA targets,
links, rule numbering, the engine index, the content tables, CZ beside EN in
every line of content, every document declared living-or-record, every count in
a living document against the tree, every test count against the newest row of
`docs/TEST-BASELINE.md`, and the handoff log. **Run it before every commit** — a
stale `Where` cell or a content count that has drifted is a failure, not a
cosmetic issue.

Two consequences worth knowing before writing a doc: a **count in a living
document is enforced**, so quote one only where it is worth keeping true (a
record — a handoff, the backlog, a rule — may say what it measured on the day),
and a **test count comes from `docs/TEST-BASELINE.md`**, where you append a row
after a run rather than editing a number in prose.

```bash
make test          # = cd Core && swift test  (~18 min)
make test-filter F=Siege
```

The core is tested without a simulator:

```bash
cd Core && swift test
```

Build the iOS app (regenerate the project first if `project.yml` changed):

```bash
cd App && xcodegen generate
xcodebuild -project App/EndlessFrontier.xcodeproj -scheme EndlessFrontier \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

The device name goes stale with Xcode. On Xcode 26.2 the only installed iPhone
runtime is **iPhone 17**, and asking for a device that is not there fails with
`Unable to find a device matching the provided destination specifier` — which
reads like a broken project and is not one. Check what exists first:

```bash
xcrun simctl list devices available | grep iPhone
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
| `laws.json` | Laws the assembly votes on (V2) |
| `cults.json` | Faiths a temple can seed (V2) |
| `meals.json` | What a cook can make out of the harvest |
| `items.json`, `recipes.json`, `quests.json` | RPG layer |
| `conveyances.json` | Mounts and vehicles — one bank for both (data layer only so far) |
| `map-gen.json` | Hex world generation tuning |
| `world-config.json` | Tuning constants (tick rate, calendar, tension formula, etc.) |

The JSON schemas live in `docs/data-schemas/`. Validate new data files against the schema before committing.

## Where to look for context

**Start at `docs/README.md`** — it says which doc is live and which is
historical. Consolidated 2026-08-13, because `ROADMAP.md` and `NEXT_STEPS.md`
had been stale for two months while this section still pointed at them as "what
to build next".

Read these three, in order, when picking work up cold:

1. `docs/CODEMAPS/architecture.md` — three layers, tick order, how a decision flows
2. **`docs/RULES.md`** — 110 rules, each of which cost a session. Read *before*
   writing a threshold, not after
3. `docs/BACKLOG.md` — the living plan

**When something is broken, start at `docs/FMEA.md` instead** — the same
knowledge as `RULES.md`, indexed by the symptom you are staring at rather than
by the lesson. Its `Where` cells are checked by `make verify-docs`, so they
point at code that still exists.

| Question | Where |
|---|---|
| Something is broken — where has it been before? | **`docs/FMEA.md`** |
| What did the last sessions do? | `docs/handoffs/README.md` |
| How many tests are there? | `docs/TEST-BASELINE.md`, newest row |
| What does this engine own? | `docs/CODEMAPS/engines.md` |
| Entity or still a number? | `docs/CODEMAPS/models.md` |
| Content files and tuning constants | `docs/CODEMAPS/data.md` |
| The canvas | `docs/CODEMAPS/app.md` |
| How to measure the world | `docs/CODEMAPS/probes.md` |
| Game systems and formulas | `docs/DESIGN.md` |
| Architecture rules | `docs/architecture/LAYERS.md` |
| Footprints, lots, pawn-like animals | `docs/RIMWORLD_LAYER.md` |
| Mounts, carts and later transport | `docs/MOUNTS_AND_VEHICLES.md` |
| Roads, chokepoints and what rail costs | `docs/ROADS.md` |
| Event / tech schemas | `docs/data-schemas/` |

**Historical, do not plan from:** `ROADMAP.md`, `NEXT_STEPS.md`, and every
file in `docs/handoffs/` except the newest — `docs/handoffs/README.md` says
what each is safe for.
`NEXT_PHASE.md` is partly live — its three unconverted rows still stand.
