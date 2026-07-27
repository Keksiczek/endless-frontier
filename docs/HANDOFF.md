# Handoff — 2026-07-27

Where the project stands after a long working session, what changed, what is
*genuinely* done versus merely built, and what to pick up next.

Branch: `docs/rimworld-layer` (all work pushed; **not yet merged to `main`**).
Tests: **608 Core**, **41 app** — all green.

---

## 1. Read this first

Three documents carry the context:

| For | Read |
|---|---|
| What the RimWorld-leaning layer *is* | `docs/RIMWORLD_LAYER.md` |
| The backlog, with everything below scoped out | `docs/NEXT_STEPS.md` |
| Rules that must not be broken | `CLAUDE.md` §"Key design rules" |

The invariants that actually bite, in the order they have bitten:

1. **Presentation never writes the simulation.** The canvas derives positions
   from ids and a frame clock. If a renderer change needs new state, the state
   goes in the engine and the renderer reads it.
2. **Determinism.** Every roll comes from a seed derived from stable ids. New
   RNG draws go at the **end** of a generation pass or every existing world
   changes.
3. **Saves decode-if-present.** Every field added this session
   (`work`, `look`, `trees`, `rocks`, `shore`, `usesEntityLand`, `usesEntities`,
   `currentJob`) is optional with a sane default.
4. **Offline catch-up is linear.** Anything added to the per-tick path is
   replayed tens of thousands of times. Two things this session had to move to a
   cadence (see §4).
5. **Content is data, and bilingual.** CZ+EN in the same change.

---

## 2. What changed this session

### The land became things
- `Tree` / `Rock` (`Models/Flora.swift`) with `FloraEngine`: trees grow from age,
  bank their own axe-work, and are gone when felled; rock is spent and does not
  return.
- `Animal` gained a life (`AnimalEngine`): ageing, exposure, illness, death,
  spring breeding, and a hunt that takes the weakest prey first.
- **The economy now runs on them.** `FloraEngine.syncDeposits` rewrites each
  forest/stone/iron/clay deposit's `amount` from what is standing on it, and
  `ResourceLoop.evolveDeposits` routes logger and miner work through
  `fell`/`quarry` instead of subtracting from a number. Fields and herb patches
  keep the old arithmetic.
- **Hunting reads the animals**: `WildlifeState.herdFraction` is a head count
  where there are heads to count, so a valley whose deer froze stops feeding its
  hunters.

### Work became concrete
- `LaborEngine.staffBuildings` keeps colonists' *posts* in step with their
  trades every ten ticks (before, `autoAssign` ran once at founding and never
  again).
- `ResourceLoop.staffingFactors` makes the post **pay**: output scales with who
  is at the bench, floored at `unstaffedFloor` (0.4).
- `JobBoard` (`Models/Job.swift`) gives every worker a **named piece of work at a
  named place** — this tree, this outcrop, this scaffold — and the canvas draws
  them there.
- `WorkKind.garrison` so walls and barracks can finally be manned.

### The world got wider and more varied
- Build grid **12×12 → 18×18**.
- `depositMix` jittered per map, so two forest valleys differ in composition.
- `ShoreShape`: coastal maps get a real **sea** along one edge.
- Eight new scenery kinds and rebuilt per-biome palettes.

### The screen caught up
- `SettlementFlora` draws trees and rock; `SettlementWildlife` draws animals as
  individuals.
- Building moved **onto the settlement canvas** (`SettlementBuildOverlay`,
  `BuildBar`): grid, taken ground, a full-size ghost you aim then commit.
- `SiteOutcomeCard` replaced a hardcoded-English `.alert`.
- `NotificationScheduler`: local notifications, app-side only, rate-limited,
  permission asked on *leaving* a session that lasted long enough.

---

## 3. Done vs. built-but-not-wired

Be careful with this distinction — it is where the last three sessions found
their worst bugs.

| Thing | State |
|---|---|
| Trees/rock drive the deposit economy | **Done and wired** |
| Hunting reads live animals | **Done and wired** |
| Staffing affects production | **Done and wired** |
| Jobs assigned + drawn | **Done and wired** |
| `FloraEngine.plant` | **Built, never called.** Nothing replants; a cleared wood only regrows from surviving saplings |
| `AnimalEngine.hunt` yield | Culls animals, but the *food* still comes from the abstract `deerHerd` path |
| Notifications | **Built and wired, never verified on device.** Needs a real run: permission prompt, delivery, and that the digest doesn't fire while playing |
| Build-on-canvas | **Built and wired, never played.** Unverified: whether 18×18 tiles are tappable at default zoom |
| Elevation | **Not started** — scoped in `NEXT_STEPS.md` as its own phase |

---

## 4. Traps a newcomer will hit

**The recurring bug shape** — a mechanic that cannot fire because a threshold is
out of reach of the rate meant to cross it. It has appeared five times now:
storyteller disasters, animal comfort bands, the condition keep-threshold,
`autoAssign` running once, and the entity-layer flags below. *When you add a
threshold, write down the rate that must cross it and check the arithmetic. Then
test that the mechanic is reachable, not just that it behaves once triggered.*

**`isEmpty` is not "has no layer".** `map.trees.isEmpty` is true both for a map
that predates trees *and* for a wood logged flat — and treating them alike made a
cleared forest keep its last value. Hence `LocalMap.usesEntityLand` and
`WildlifeState.usesEntities`. Any future entity layer needs the same flag.

**Per-tick cost is not free.** Widening the grid made `staffBuildings` superlinear
over a catch-up and tripped `OfflineCatchUpTests`. Both it and `JobBoard` now run
every `10` ticks. If you add per-tick work touching placements or pawns, check
that test.

**Waypoint semantics.** `AgentMotion` waypoints mean "from this hour, do this
here". They previously read the *next* waypoint's activity, which is why the
village appeared to socialise all afternoon.

**`ColonyBuilder.workKind` is data-first.** It returns `def.work` if set. Adding a
`WorkKind` case breaks exhaustive switches in `SocietyEngine.wage`,
`ColonistsPanel`, `ColonyMapScreen`, `AgentMotion.activityLabel` and
`SettlementFigures` — the compiler will find all five.

---

## 5. Next steps, in the order I would take them

1. **Play it.** Two sessions of changes have not been seen running. Specifically:
   is 18×18 legible and tappable; do the ghost + build bar make sense; do trees
   and animals read at default zoom; does the sea look like a sea.
2. **Replanting** (`FloraEngine.plant` has no caller). Without it a colony can
   permanently deforest its valley, which may be the right game — but it should
   be a decision, not an oversight.
3. **Hunting yield from the kill**, so `deerHerd` can finally retire rather than
   being shadowed.
4. **Verify notifications on device**, then decide whether the digest wants real
   numbers (currently deliberately vague, because a prediction made on leaving
   can be wrong by morning).
5. **Elevation** as its own phase — see `NEXT_STEPS.md`. Biggest remaining change
   to how the maps feel.
6. **The rest of the job layer**: jobs are assigned and drawn but not *worked* —
   progress still comes from the aggregate harvest, not from the specific tree a
   specific colonist is standing at. Closing that loop is what makes the day
   schedule mean something.

---

## 6. Commands

```bash
cd Core && swift test
```

```bash
cd App && xcodegen generate
```

```bash
xcodebuild -project App/EndlessFrontier.xcodeproj -scheme EndlessFrontier -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Note: `iPhone 16` (still named in `CLAUDE.md`) does not exist on this machine —
the installed simulators are iPhone 17 / 17 Pro / 17 Pro Max / Air / 16e.
