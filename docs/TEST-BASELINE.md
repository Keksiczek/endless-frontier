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
| 2026-08-27 | `29892c1` | 1604 | 224 | ~18 min | 202 | 32 | Re-counted rather than copied; `CLAUDE.md` had claimed 1233 tests in 42 minutes |
| 2026-08-26 | — | 1581 | 220 | ~13 min | 182 | — | The suite had come down from ~32 min — an allocation per sapling, `BACKLOG.md` §18 |
| 2026-08-25 | — | 1548 | 218 | — | 173 | — | |
| 2026-08-21 | — | 1344 | 186 | — | 161 | 25 | |

## Unmeasured since the newest row

- `0c2488f` *fix: three faults in a raid* — adds `BattleBeatTests` (App) and
  extends `SiegeTests` and `ContentTests` (Core). **Not measured.** The next
  session to run `make test` should append the row rather than trusting the one
  above.

## How to count

XCTest's trailing tally counts *assertions*, not tests, and reading it has
invented a regression before. Count failures with:

```bash
grep "' failed (" /tmp/endless-frontier-test.log
```

`make test-app` writes that log. For the Core suite, `swift test` prints the
suite and test totals directly.
