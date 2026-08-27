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
