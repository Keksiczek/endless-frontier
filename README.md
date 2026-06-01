# Endless Frontier

A persistent civilization / colony simulation for iOS, built in Swift / SwiftUI.

## Concept

Endless Frontier blends three familiar genres into one slow-burn, long-term mobile game:

- **RimWorld-style storyteller** — an event planner that creates incidents, crises and opportunities based on world state and a tension curve.
- **Surviving Mars-style resource management** — a small set of critical indicators the player must keep in safe ranges to avoid collapse.
- **4X-style progression** — technologies, eras and expansion across a growing map.

The game is fully **offline-first**. There is no always-running background process; instead the world advances in deterministic ticks whenever the app is opened, based on real time elapsed.

## Documentation

| Document | Description |
|---|---|
| [docs/DESIGN.md](docs/DESIGN.md) | Full game design document — systems, loops, schemas |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Phased implementation plan (Phase 0 → 4) |
| [docs/architecture/LAYERS.md](docs/architecture/LAYERS.md) | Three-layer architecture overview |
| [docs/data-schemas/](docs/data-schemas/) | JSON schemas for events, tech tree, world config |

## Quick start (future)

```bash
open EndlessFrontier.xcodeproj
```

## Project status

Phase 0 — not yet started. See [ROADMAP.md](docs/ROADMAP.md).
