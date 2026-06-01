# Endless Frontier — Implementation Roadmap

This is a solo-developer project. Each phase is independently shippable and testable. Later phases build on earlier ones without breaking them.

> **Status (2026-06-01):** Phases 0, 1, and 2 are implemented and tested (45
> tests, `swift test`). The deterministic core lives in the `Core/` Swift
> Package; a SwiftUI app (`App/`) drives it. Next up: Phase 3 (LLM narrator).
> Open follow-ups from the Phase 2 review (`.claude/reviews/phase2-local-review.md`):
> add a `schemaVersion` + save migration before public release, and revisit the
> isolation-penalty curve for balance.

---

## Phase 0 — Bare-bones simulation sandbox

**Goal**: a running Swift app that ticks the world and keeps state across sessions. No events, no LLM, no UI polish.

**Deliverables**:

- [ ] Xcode project, SwiftUI scaffold, CLAUDE.md
- [ ] `WorldState` model (Codable, persisted to JSON on disk)
- [ ] Tick engine: on app open, compute elapsed time → advance N ticks
- [ ] Single settlement with hard-coded building slots
- [ ] Resource tick loop (produce/consume/clamp)
- [ ] Basic SwiftUI dashboard: tick count, resource bars, settlement stats
- [ ] Unit tests for tick loop and resource math

**Success criteria**: open the app, see resources change based on time elapsed; close and reopen, numbers are preserved.

**Estimated scope**: ~500–800 lines of Swift (models + engine + minimal UI).

---

## Phase 1 — Data-driven content + simple rule-based events

**Goal**: buildings, tech tree, eras, and a simple event system all driven from JSON data files.

**Deliverables**:

- [ ] `GameData/` directory with JSON loaders:
  - `buildings.json` (building definitions)
  - `techs.json` (tech DAG)
  - `eras.json` (era milestones)
  - `biomes.json` (biome definitions)
- [ ] `GameDataRegistry` — loads JSON at startup, provides typed access
- [ ] Tech queue: player picks next research, knowledge accumulates, tech unlocks
- [ ] Era milestone checker: on each tick, check if era advancement is triggered
- [ ] Rule-based events: 3–5 hard-coded event types (drought, good harvest, bandit raid)
  - No storyteller yet — events fire on fixed conditions (e.g. food < 50 → drought)
- [ ] Event UI: modal card showing event name, description, choices
- [ ] Player choice applies effect to WorldState
- [ ] Map screen: placeholder hex grid, 1 region visible, adjacent regions unknown
- [ ] Unit tests for data loading, tech unlock, era progression

**Success criteria**: player can research techs, survive first era, see and respond to basic events.

---

## Phase 2 — Full storyteller engine + exploration

**Goal**: the game feels alive. Events are dynamic, tension drives drama, exploration expands the world.

**Deliverables**:

- [ ] `events.json` data file (10–20 event templates covering all types)
- [ ] Tension formula implementation (see DESIGN.md §6.1)
- [ ] Storyteller planner: filter → weight → roll → apply (see DESIGN.md §6.3)
- [ ] Event cooldown tracking in WorldState
- [ ] "While you were away" summary screen (events that fired during offline time)
- [ ] Exploration system:
  - [ ] Expedition action: target adjacent region, cost resources, takes N ticks
  - [ ] On completion: reveal region, fire discovery event
  - [ ] Outpost founding, city upgrade
- [ ] Multi-city support:
  - [ ] Each city has independent resource tick
  - [ ] Global stats aggregated from all cities
  - [ ] Supply-line vulnerability (distant cities lose stability without trade routes)
- [ ] Trade routes between cities (simple: resource transfer per tick)
- [ ] Era 2 content (Ancient/Classical): new buildings, event types
- [ ] Unit + integration tests for storyteller (deterministic seeding for reproducibility)

**Success criteria**: the game generates surprising, meaningful events over multiple sessions; player can expand to 2–3 cities.

---

## Phase 3 — Optional LLM narrator

**Goal**: if a local LLM is available, events are narrated in rich text. Game works identically without it.

**Deliverables**:

- [ ] `LLMNarratorProtocol`: abstract interface the simulation uses
- [ ] `StubNarrator`: returns `event.narrative_hint` as plain text (always available)
- [ ] `LocalLLMNarrator`: sends compact JSON snapshot to a local model (on-device or localhost)
- [ ] Chronicle view: scrollable "in-world newspaper" of narrated events
- [ ] Advisor comment system: LLM suggests action commentary alongside events
- [ ] Settings toggle: enable / disable narrator
- [ ] Input/output JSON schema enforced via Codable structs (see DESIGN.md §7)

**Success criteria**: with narrator off, game is identical to Phase 2; with narrator on, events read as rich prose.

---

## Phase 4 — External integration (Home Hub / AI agent bridge)

**Goal**: connect the game to the user's existing iOS Home Hub project as an optional data source.

**Deliverables**:

- [ ] Identify integration points: real-world data that can map to game parameters
  - e.g. weather API → in-game drought probability modifier
  - e.g. home energy usage → energy resource modifier
  - e.g. LLM from Home Hub narrates instead of local model
- [ ] `ExternalDataBridgeProtocol`: clean boundary so the game never directly depends on Home Hub internals
- [ ] Stub implementation for development without the hub
- [ ] Optional: export game state as structured data for Hub to query

**Note**: this phase is deliberately underspecified. Design it after Phase 2 is stable and the integration surface is clearer.

---

## Cross-cutting concerns (all phases)

| Concern | Approach |
|---|---|
| Persistence | `Codable` + JSON file on disk in app's Documents directory |
| Determinism | Seeded RNG (seed stored in WorldState), no random calls outside engine |
| Testability | Pure functions for simulation math; dependency injection for time + RNG |
| Data-driven | All game content in `GameData/*.json`; zero game logic in JSON loaders |
| Accessibility | VoiceOver labels on all interactive elements from day one |
| Offline-first | No URLSession calls in simulation path; narrator is an optional enhancement |

---

## Milestone summary

| Phase | Key feature | Testable? | Status |
|---|---|---|---|
| 0 | Ticking world, persisted state | Unit tests | ✅ Done |
| 1 | Tech tree, basic events, eras | Unit + data tests | ✅ Done |
| 2 | Storyteller, exploration, multi-city | Integration tests | ✅ Done |
| 3 | LLM narrator | Protocol stub tests | ⏳ Next |
| 4 | Home Hub bridge | Stub tests | ⬜ Planned |
