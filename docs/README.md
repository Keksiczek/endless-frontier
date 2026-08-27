# Docs — what is where

> **Start here if you are picking this up cold:**
> [`HANDOFF-2026-08-28.md`](handoffs/HANDOFF-2026-08-28.md) — the newest plan: three
> faults in raids that were none of them in the fight (the wrong colony, a
> stopped clock, and a surface only reachable while the app was in front), and
> the workshop avalanche measured and moved.
> Before it: [`HANDOFF-2026-08-27-evening.md`](handoffs/HANDOFF-2026-08-27-evening.md) —
> what the last five jobs turned into.
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
> Before it: [`HANDOFF-2026-08-22.md`](handoffs/HANDOFF-2026-08-22.md) — combat measured
> apart into three faults, the council that could build one building, and the
> six things Keks asked for next in his own order.
> Before it: [`HANDOFF-2026-08-21-evening.md`](handoffs/HANDOFF-2026-08-21-evening.md) — the
> narrator, the chronicle's names, what `GeneProbe` measured twice, roads over
> water, and a save bug that had been throwing away every road since it shipped.
> [`HANDOFF-2026-08-21.md`](handoffs/HANDOFF-2026-08-21.md) is the morning before it, and
> its §4.2 and §4.4 are still open.

<!-- Consolidated 2026-08-13 -->

Read in this order when picking work up cold:

| # | Doc | What it is |
|---|---|---|
| 1 | [NEXT.md](NEXT.md) | **Start here.** Where the game stands and what to work on next, with the evidence for each |
| 2 | [CODEMAPS/architecture.md](CODEMAPS/architecture.md) | The three layers, the tick order, where a decision flows |
| 3 | [RULES.md](RULES.md) | **105 rules, each of which cost a session.** Read before writing a threshold |
| 4 | [BACKLOG.md](BACKLOG.md) | **The living record.** What was measured, what was built, what Keks asked for |

## Routing table — by what you are about to do

Not "what is in this directory". **What you are doing → the one file to open.**

| I am about to… | Open | Then |
|---|---|---|
| **start cold** | [`../CLAUDE.md`](../CLAUDE.md) | then the newest handoff in [`handoffs/`](handoffs/README.md), and stop — that is enough to talk |
| **stare at a failure** | [`FMEA.md`](FMEA.md), by symptom | build → §A · a mechanic that never fires → §B · the colony died → §C · content silently missing → §D · the canvas is wrong → §E |
| **write a threshold** | [`RULES.md`](RULES.md) rules 6, 23, 24, 30 | then §F of `FMEA.md` — the situations, not the symptoms |
| **add a mechanic and expect it to fire** | [`RULES.md`](RULES.md) rule 6 | write the test named for its *reachability* |
| **add content** | [`CODEMAPS/data.md`](CODEMAPS/data.md) | CZ + EN in the same change (rule 7); `make verify-docs` checks it without building |
| **change what the canvas draws** | [`CODEMAPS/app.md`](CODEMAPS/app.md) | rule 18 — ask what in the Core it is a picture *of* |
| **know a number** | nothing — **run a probe** | [`CODEMAPS/probes.md`](CODEMAPS/probes.md) |
| **quote a test count** | [`TEST-BASELINE.md`](TEST-BASELINE.md), newest row | append a row after a run; never edit a count in prose |
| **read what a past session did** | [`handoffs/README.md`](handoffs/README.md) | newest for the state, older ones only for *why* a constant has its value |
| **decide what to work on** | [`BACKLOG.md`](BACKLOG.md), newest section | the open list at the end of it |
| **trust a document** | [`FMEA.md`](FMEA.md) §G | what each doc is good for, and what it is not |

### The command that keeps this honest

```bash
make verify-docs
```

Ten mechanical checks, no Xcode and no network, about two seconds:
`FMEA.md`'s `path` · `symbol` cells resolve · every relative link resolves ·
`RULES.md` is numbered contiguously and its header count is true · every engine
is named in `CODEMAPS/engines.md` · every `GameData/*.json` parses, is listed in
`CODEMAPS/data.md` and its entry count there is true · every line of content
carries `cs` beside `en` · every document is declared a **living document** or a
**record** · no living document quotes a content or rule count the tree
disagrees with · no living document quotes a test count that is not the newest
row of [TEST-BASELINE.md](TEST-BASELINE.md) · every handoff is in the log and
this file points at the newest. Run it before every commit — it is part of
`make check`.

**Living document or record.** The two are trusted differently and the checks
treat them differently: a living document's numbers are claims about today and
are enforced; a record's numbers were true when it was written and are left
alone. `CLAUDE.md`, this file, `NEXT.md`, `TEST-BASELINE.md` and the codemaps
are living. `BACKLOG.md`, `RULES.md`, `FMEA.md` and everything in `handoffs/`
are records — `RULES.md` and `FMEA.md` because a rule quotes the measurement
that produced it. A new document has to be declared one or the other in
`scripts/verify-docs.py`, which is the point: nobody can add an unowned doc.

## Reference, by question

| Question | Doc |
|---|---|
| The chronicle, the annals, and the narrator seam | [CHRONICLE.md](CHRONICLE.md) |
| Why the council built *that* | [COUNCIL.md](COUNCIL.md) |
| Weapons, volleys, and what a fight is made of | [ARMS_AND_PROJECTILES.md](ARMS_AND_PROJECTILES.md) |
| Roads, water, bridges, ruins and what rail costs | [ROADS.md](ROADS.md) |
| A symptom, and where its cause has been before | [FMEA.md](FMEA.md) |
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
| [handoffs/](handoffs/README.md) | — | **The session log.** One file per session, newest first, with what each is safe for |
| [NEXT.md](NEXT.md) | plan 2026-08-17, counts 2026-08-28 | Still the best short answer to "what next". Its counts are checked by `make verify-docs` now; **its plan is not** — read `BACKLOG.md` and the newest handoff beside it |

Reality as of the newest row of [TEST-BASELINE.md](TEST-BASELINE.md)
(**2026-08-27**): **1604 Core tests** in 224 suites in ~18 minutes, and
**202 App tests** in 32 suites, all green; iOS build green. The raid commit
after it is unmeasured — see the note in that file, and append a row rather than
editing this line.
Content: **62 buildings**, **60 techs**, 182 events, 7 biomes, **477 items**,
**420 recipes** — checked against the tree by `make verify-docs`. History lives
in `BACKLOG.md`; the newest sections are §17 and §18. The open list is §15.6,
§16.3–16.4 and §17.4.

## The one rule about these docs

A status line in a doc is a claim with a date on it. If you are about to trust
one — "buildings and techs are still English-only", "next up is Phase 3" —
**check the code first.** Both of those examples were false for weeks before
anyone noticed.
