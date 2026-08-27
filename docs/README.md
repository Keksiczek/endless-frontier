# Docs — what is where

> **Start here if you are picking this up cold:**
> [`HANDOFF-2026-08-27-evening.md`](HANDOFF-2026-08-27-evening.md) — the newest
> plan, and what the last five jobs turned into.
> Then [`BACKLOG.md` §20](BACKLOG.md) (2026-08-27) — a colonist's memory (the
> subjects were never the shortage, the 140-entry ring was), a recipe book that
> turned out to be correctly tiered, the renderer in eight files, and **a
> council bench that had been full since year 60**, so a colony that wanted
> steel from year 130 made none in two centuries. Open list: §20.7.
> Before it: [`BACKLOG.md` §17–18](BACKLOG.md) (2026-08-26 evening) — why a long
> game ran out of wood, and why **a quarter of the recipe book needed
> treasure**. Both were found by measuring; the first disproved the hypothesis
> that started it.
> Before them, [`§15–16`](BACKLOG.md) — the app audit: diplomacy's verbs were
> off the edge of an iPhone, there were two build flows and one of them omitted
> every early building, the objectives panel was in English, marching on a
> neighbour did not exist, and **73 items could never be equipped while 89
> recipes went on making them**.
> Before it: [`HANDOFF-2026-08-22.md`](HANDOFF-2026-08-22.md) — combat measured
> apart into three faults, the council that could build one building, and the
> six things Keks asked for next in his own order.
> Before it: [`HANDOFF-2026-08-21-evening.md`](HANDOFF-2026-08-21-evening.md) — the
> narrator, the chronicle's names, what `GeneProbe` measured twice, roads over
> water, and a save bug that had been throwing away every road since it shipped.
> [`HANDOFF-2026-08-21.md`](HANDOFF-2026-08-21.md) is the morning before it, and
> its §4.2 and §4.4 are still open.

<!-- Consolidated 2026-08-13 -->

Read in this order when picking work up cold:

| # | Doc | What it is |
|---|---|---|
| 1 | [NEXT.md](NEXT.md) | **Start here.** Where the game stands and what to work on next, with the evidence for each |
| 2 | [CODEMAPS/architecture.md](CODEMAPS/architecture.md) | The three layers, the tick order, where a decision flows |
| 3 | [RULES.md](RULES.md) | **102 rules, each of which cost a session.** Read before writing a threshold |
| 4 | [BACKLOG.md](BACKLOG.md) | **The living record.** What was measured, what was built, what Keks asked for |

## Reference, by question

| Question | Doc |
|---|---|
| The chronicle, the annals, and the narrator seam | [CHRONICLE.md](CHRONICLE.md) |
| Why the council built *that* | [COUNCIL.md](COUNCIL.md) |
| Weapons, volleys, and what a fight is made of | [ARMS_AND_PROJECTILES.md](ARMS_AND_PROJECTILES.md) |
| Roads, water, bridges, ruins and what rail costs | [ROADS.md](ROADS.md) |
| What does this engine own? | [CODEMAPS/engines.md](CODEMAPS/engines.md) |
| Is this an entity or still a number? | [CODEMAPS/models.md](CODEMAPS/models.md) |
| Where does content live? | [CODEMAPS/data.md](CODEMAPS/data.md) |
| How does the canvas work? | [CODEMAPS/app.md](CODEMAPS/app.md) |
| How do I measure the world? | [CODEMAPS/probes.md](CODEMAPS/probes.md) |
| What are the game's systems and formulas? | [DESIGN.md](DESIGN.md) |
| Building footprints, lots, pawn-like animals | [RIMWORLD_LAYER.md](RIMWORLD_LAYER.md) |
| Art direction, why it is line art | [ASSET_SPECIFICATION.md](ASSET_SPECIFICATION.md) |
| Mounts, carts, and everything later that moves | [MOUNTS_AND_VEHICLES.md](MOUNTS_AND_VEHICLES.md) |
| Event / tech JSON schemas | `data-schemas/` |

## Historical — do not plan from these

They are kept for the reasoning in them, not for their status lines. Both were
overtaken without being updated, which is exactly how a stale doc does damage.

| Doc | Frozen at | Says |
|---|---|---|
| [ROADMAP.md](ROADMAP.md) | 2026-06-01 | "45 tests, phases 0–2 done, next is Phase 3" |
| [NEXT_STEPS.md](NEXT_STEPS.md) | 2026-06-06 | "179 tests" |
| [NEXT_PHASE.md](NEXT_PHASE.md) | ~2026-07-28 | The entity-conversion brief. Two of its three unconverted rows still stand; **the buildings row is out of date** — see [CODEMAPS/models.md](CODEMAPS/models.md) |
| [HANDOFF.md](HANDOFF.md) | 2026-08-13 | A state report, not a plan — but the newest one, and worth reading |
| [NEXT.md](NEXT.md) | 2026-08-17 | Still the best short answer to "what next", but **its counts are stale**: it says 37 techs / 306 recipes / 38 rules against 60 / 420 / 96 today |

Reality as of **2026-08-26 (evening)**: **1581 Core tests in 220 suites** and
182 App tests, all green; iOS build green. The Core suite runs in ~13 minutes,
down from ~32 — an allocation per sapling, see §18.
Content: 56 buildings, **60 techs**, 182 events, 7 biomes, **477 items**,
**420 recipes**. History lives in `BACKLOG.md`; the newest sections are §17 and
§18. The open list is §15.6, §16.3–16.4 and §17.4.

## The one rule about these docs

A status line in a doc is a claim with a date on it. If you are about to trust
one — "buildings and techs are still English-only", "next up is Phase 3" —
**check the code first.** Both of those examples were false for weeks before
anyone noticed.
