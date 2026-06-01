# Local Review: Phase 2 (scheduled effects, exploration, expansion)

**Reviewed**: 2026-06-01
**Scope**: 11 modified + 10 new files in `Core/`
**Decision**: APPROVE with comments (no CRITICAL/HIGH)

## Summary
Phase 2 adds scheduled/duration effects, exploration expeditions, and
multi-city expansion to the deterministic core. Logic is clean, pure, and
well-tested (45 tests pass). No security concerns (offline, no I/O beyond
local JSON persistence, no user-supplied input parsing beyond bundled data).
Two MEDIUM items worth tracking; no blockers.

## Findings

### CRITICAL
None.

### HIGH
None.

### MEDIUM
1. **WorldState save compatibility** — adding non-optional `scheduledEffects`
   and `tradeRoutes` to `WorldState` means old JSON saves fail synthesized
   decoding. The app's `try? store.load()` falls back to a new game, so it's a
   silent reset, not a crash. Acceptable pre-release, but **add a `schemaVersion`
   field + migration before any public release** so player saves survive
   updates. (`Models/WorldState.swift`)

2. **Isolation penalty over long offline periods** — `isolationStabilityPenalty`
   (0.5/tick) applies every tick to unconnected non-capital settlements. At the
   1-tick/minute rate, an unconnected outpost reaches 0 stability in ~3 hours of
   offline time. It's data-driven (tunable in `world-config.json`) and floored
   at 0 with no cascade, but consider a gentler curve or a grace period so a
   newly founded outpost isn't doomed if the player closes the app.
   (`Engine/MultiCityEngine.swift`)

### LOW
3. **Outpost founding cost is a hardcoded constant** (`ExpansionEngine.outpostFoundingCost`)
   rather than living in `WorldConfig`. Fine for now; move to config if it needs
   balance iteration. (`Engine/ExpansionEngine.swift`)

4. **Global stability lags one tick behind isolation** — `ResourceLoop`
   recomputes global stability from settlement stability *before*
   `MultiCityEngine` applies the isolation penalty, so the global figure trails
   by one tick. Cosmetic. (`Engine/TickEngine.swift` ordering)

## Validation Results

| Check | Result |
|---|---|
| Build (`swift build`) | Pass |
| Tests (`swift test`) | Pass — 45 tests, 11 suites |
| Lint | Skipped (no SwiftLint configured) |

## Files Reviewed
- Added: ExplorationEngine, ExpansionEngine, MultiCityEngine, ScheduledEffectEngine,
  Expedition, TradeRoute, ScheduledEffect (+ 3 test suites)
- Modified: WorldState, Settlement, WorldConfig, GameEngine, TickEngine,
  GameWorldFactory, EffectApplier, StatPath, StoryPlanner, world-config.json,
  PersistenceAndDataTests
