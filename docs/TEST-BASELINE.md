# Test baseline — one row per measurement

**Append, never rewrite.** A test count is a claim with a date on it, and this
file is the only place a live document may take one from: `make verify-docs`
fails when `CLAUDE.md`, `docs/README.md` or a codemap quotes a number that is
not the newest row here.

**Diff against the newest row only.** Diffing an older one invents regressions —
suites are split and merged all the time, so "220 suites then, 224 now" says
nothing on its own.

| Date | Commit | Core tests | Core suites | Wall clock | App tests | App suites | Note |
|---|---|---|---|---|---|---|---|
| 2026-08-29 | `16ae1cb` | 1620 | 227 | ~18 min | 225 | 35 | The catch-up bar sized by the clock, a feast on the green, the readouts lifted out, and the research ladder measured (`BACKLOG.md` §31) |
| 2026-08-29 | `3b83128` | 1617 | 226 | ~19 min | 221 | 34 | The field that cleared too soon, the fourteen, the mine, the crafting ladder, nine fabrics, the view model split and the worn things (`BACKLOG.md` §29–30) |
| 2026-08-28 | `cbd6505` | 1614 | 224 | ~19 min | 220 | 34 | A storyteller raid opens a siege you can answer, and a store holds what it is a store for (`BACKLOG.md` §28) |
| 2026-08-28 | `d39e845` | 1614 | 224 | ~22 min | 220 | 34 | The height was being counted twice, so a warehouse hung over the town (`BACKLOG.md` §27.4) |
| 2026-08-28 | `532baf1` | 1614 | 224 | ~22 min | 220 | 34 | The corner in the wall, the flicker that was reading screen coordinates, and the smithy the iron half was waiting for (`BACKLOG.md` §27) |
| 2026-08-28 | `7f582ce` | 1614 | 224 | ~18 min | 219 | 34 | Every beast in the valley had been walking backwards half the time — the animals had no facing at all (`BACKLOG.md` §26.4) |
| 2026-08-28 | `faac494` | 1614 | 224 | ~18 min | 216 | 33 | The lift and the wall face it uncovers, five bank fields that were carried and never read, and the placement that was throwing the yards away (`BACKLOG.md` §26) |
| 2026-08-28 | `853fe1a` | 1614 | 224 | ~18 min | 213 | 33 | The yard drawn at last (54 attachments), the foot on the plot, and everybody in the one sorted pass (`BACKLOG.md` §25) |
| 2026-08-28 | `3378499` | 1614 | 224 | ~18 min | 210 | 33 | The wood drawn in the town's own sorted pass, seven structures that are not rooms, and the first sixty per-building fittings (`BACKLOG.md` §24) |
| 2026-08-27 | `b6fea2e` | 1614 | 224 | ~25 min | 207 | 33 | The 2.5D assets: `structures.json` and its reader, the battle caption that was off the edge of the world, interiors that can name a building (`BACKLOG.md` §23) |
| 2026-08-27 | `9319742` | 1611 | 224 | ~16 min | 207 | 33 | The raid commit measured at last, and the workshop move with it — two failures found and fixed (`BACKLOG.md` §22.1) |
| 2026-08-27 | `29892c1` | 1604 | 224 | ~18 min | 202 | 32 | Re-counted rather than copied; `CLAUDE.md` had claimed 1233 tests in 42 minutes |
| 2026-08-26 | — | 1581 | 220 | ~13 min | 182 | — | The suite had come down from ~32 min — an allocation per sapling, `BACKLOG.md` §18 |
| 2026-08-25 | — | 1548 | 218 | — | 173 | — | |
| 2026-08-21 | — | 1344 | 186 | — | 161 | 25 | |

## Unmeasured since the newest row

- Nothing. `0c2488f` is measured in the newest row above, along with the fixes
  the measurement produced.

## How to count

XCTest's trailing tally counts *assertions*, not tests, and reading it has
invented a regression before — and `Executed 0 tests` is what it prints for a
suite written in **swift-testing**, which is all of them now. The line to read
is swift-testing's own, and the failures are `✘`:

```bash
grep -E "Test run with|✘ Test " /tmp/endless-frontier-test.log
```

`make test-app` greps for all three wordings. It did not always: it looked for
XCTest's `' failed (` alone, so an App run with a swift-testing failure in it
printed `none` and exited 0 (`BACKLOG.md` §22.3b).

`make test-app` writes that log. For the Core suite, `swift test` prints the
suite and test totals directly.
