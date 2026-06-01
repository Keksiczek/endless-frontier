# Architecture: Three Layers

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer 3 — LLM Narrator (OPTIONAL)                              │
│                                                                 │
│  Input:  compact WorldSnapshot JSON (~500 tokens)               │
│  Output: narrative text, advisor comments, flavor details       │
│                                                                 │
│  ┌──────────────────────┐   ┌───────────────────────────────┐  │
│  │   StubNarrator       │   │   LocalLLMNarrator            │  │
│  │  (always available)  │   │  (on-device / localhost LLM)  │  │
│  └──────────────────────┘   └───────────────────────────────┘  │
│                  implements LLMNarratorProtocol                 │
└────────────────────────────┬────────────────────────────────────┘
                             │ text only — never writes WorldState
┌────────────────────────────▼────────────────────────────────────┐
│  Layer 2 — Storyteller Engine                                   │
│                                                                 │
│  ┌────────────────┐  ┌──────────────────┐  ┌────────────────┐  │
│  │ TensionCalc    │  │ EventRegistry    │  │ StoryPlanner   │  │
│  │                │  │ (from JSON)      │  │                │  │
│  │ f(WorldState)  │  │ conditions       │  │ filter         │  │
│  │ → Float 0–100  │  │ weights          │  │ weight         │  │
│  │                │  │ effects          │  │ roll           │  │
│  │                │  │ choices          │  │ apply          │  │
│  └────────────────┘  └──────────────────┘  └────────────────┘  │
│                                                                 │
│  Runs every PLANNER_INTERVAL ticks.                             │
│  Fully deterministic (seeded RNG).                              │
└────────────────────────────┬────────────────────────────────────┘
                             │ reads / writes WorldState
┌────────────────────────────▼────────────────────────────────────┐
│  Layer 1 — World & Simulation Core                              │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ WorldState (Codable, persisted to disk)                  │  │
│  │  tick, era, techs, settlements[], regions[], eventHist[] │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ TickEngine   │  │ TechEngine   │  │ ExplorationEngine    │  │
│  │              │  │              │  │                      │  │
│  │ advance(N)   │  │ research()   │  │ sendExpedition()     │  │
│  │ per building │  │ unlock()     │  │ revealRegion()       │  │
│  │ produce/     │  │ era check    │  │ foundOutpost()       │  │
│  │ consume      │  │              │  │                      │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ GameDataRegistry (reads JSON at startup)                 │  │
│  │  BuildingDefs, TechDefs, EraDefs, BiomeDefs, EventDefs   │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Dependency rule

Each layer may only depend on layers **below** it. The LLM narrator may never write directly to WorldState. The Storyteller reads WorldState but only mutates it through event effects (typed structs, not free-form). The Core has no dependency on Layers 2 or 3.

## Data flow on app open

```
AppDelegate.applicationDidBecomeActive
  └─ TimeElapsedCalculator.elapsed(since: lastTimestamp)
  └─ TickEngine.advance(ticks: elapsed / tickDuration)
        ├─ (per tick) ResourceLoop.update(state)
        ├─ (per PLANNER_INTERVAL ticks) StoryPlanner.run(state)
        │      └─ collect selectedEvents
        │      └─ apply effects → state
        │      └─ (async, optional) LLMNarrator.narrate(snapshot, events)
        └─ persist(state)
  └─ UI re-renders from updated state
```

## Key invariants

1. `WorldState` is the single source of truth.
2. All mutations happen inside engine functions — never directly from UI.
3. The RNG seed is stored in `WorldState` and advanced deterministically — given the same seed and inputs, the world evolves identically.
4. JSON game data is read-only at runtime. Never modified by the simulation.
