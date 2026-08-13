# Probes — measuring the world instead of guessing at it

<!-- Generated 2026-08-13 | 6 probes | ~500 tokens -->

Probes are `@Suite`s gated on `EF_DIAG`, so they never run in the normal suite.
They **print tables, they do not assert.** Their job is to answer "what is the
colony actually doing over two centuries", which no unit test can.

```bash
cd Core && EF_DIAG=1 swift test --filter ZZStewardProbe
```

Filter by the **type name** (`ZZStewardProbe`), not the suite name — `--filter
steward` matches `StewardEngineTests` too and silently runs the wrong thing.

A 12 000-tick run is ~15 minutes. Two seeds is ~25.

| Probe | Suite | Answers |
|---|---|---|
| `ZZStewardProbe` | `steward` | **What the council does with two centuries to itself.** Population, food, energy demand vs made, plots vs wanted, materials, timber on the shelf, how many buildings are *buildable*, and what it picks |
| `ZZDiagProbe` | `diag` | How far the world gets: towns, foundable regions, peoples met, wars, unlocked vs buildable |
| `ZZCoverProbe` | `coverprobe` | Ground-cover distribution and elevation percentiles per biome — for tuning `LocalTerrain` |
| `GrowthProbe` | `Growth, measured` | The population curve: beds, headroom, plots against `plotsWanted` |
| `DangerProbe` | `Danger, measured` | Whether anything can threaten a mature colony |
| `MapProbe` | `The map, drawn` | Relief percentiles — set thresholds from the field's own distribution (rule 23) |

## Why `ZZStewardProbe` exists separately from `BalanceHarness`

`BalanceHarnessTests` layers a **hand-rolled policy** on top of the world
(cheapest tech, most productive affordable building, hut when crowded). But
`TickEngine` already calls `StewardEngine` every tick, and the council acts only
*in the gaps* — so that policy **preempts and silences the shipped autopilot**.
Its trace measures a player nobody is.

`ZZStewardProbe` drives nothing. An untouched world *is* the shipped game left
alone. **Treat pre-2026-08-13 balance traces accordingly.**

## What probes have caught that tests did not

- The council builds **one windmill and never a second** while demand triples.
- `plots` at 126 against 54 wanted — and the colony starving anyway, which
  proved the famine is downstream of the fields.
- `timber_bundle` at **zero from year 80 for the remaining 120 years**, with
  `buildableHere` returning an empty list and 5500 materials in the store.
  That one bug froze the whole building economy and made every clause in
  `nextBuilding` unreachable — including one added the same day.
- `materials` and `influence` pinned at the **identical** number, which is how
  one storage cap wearing five hats was found.

## The habit

Print the column that would falsify the guess, not the one that confirms it. The
timber lock was diagnosed twice from the outside and wrong both times; it took
adding `timbr` and `able` columns to see that `nextBuilding` was returning at its
first `guard` and no clause was running at all.
