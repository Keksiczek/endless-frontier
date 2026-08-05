# Handoff — 2026-08-05 (second session)

Branch **`main`**, clean and pushed. Last commit `3cb1473`.

Tests: **914 Core**, app build and tests green.

```bash
swift test --package-path Core
```

```bash
xcodebuild -project App/EndlessFrontier.xcodeproj -scheme EndlessFrontier -destination 'platform=iOS Simulator,name=iPhone 17' test
```

```bash
cd App && xcodegen generate
```

Regenerate the Xcode project after adding any file under `App/Sources`.

---

## Read this first

**The probe numbers in the previous handoff were never reproducible, and neither
was anything else.** `Pawn.init` defaults `id` to a fresh `UUID()` and the four
founders were taking it, so every launch of the same seed began with four
different people — and since per-entity randomness comes from
`(mapSeed, entity.id, tick)`, the whole world diverged from tick zero. That is
fixed (`3cb1473`), and the figures in §3 below are the first the project can
actually compare against.

Four of Keks's six are done. The fifth (pace) is deliberately not, and the sixth
was done last session.

---

## 1. What shipped

### `ff06bf4` — a blow is a moment on two bodies, and the blood stays

The simulation was already right; the *drawing* still spoke in aggregate — a
bright seam across the whole line, sparks at a computed "front", a harm bar
floating over every defender's head.

A beat was a time and a name, so there was nowhere to put a blow.
`BattleMoment.spot` is the point of impact, stamped by `SiegeEngine.answer`
between the two people who were touching. On that one fact: `SettlementBlood`
draws the impact once and short with the spray thrown the way the blow
travelled, stains the ground permanently in a pass drawn *before* the figures,
and puts harm on the body that took it — colonists and raiders both. The seam,
the sparks, the hit ring and eleven of the twelve floating bars are gone; the
bar survives only for the selected pawn.

### `2f82c9d` — needs send people places, and the council leaves the valley

**Needs cause decisions.** `Errand` + `ErrandEngine`: a need past its threshold
posts a walk to the nearest larder or hearth, and the need is answered **on
arrival**. Built as a field of its own rather than a `JobKind` — an errand is a
person's own business and has to *interrupt* work, not compete for the same
slot. `AgentMotion` reads the Core's own positions for the walk.

Balance held flat on purpose: a meal at the granary fills you and costs food in
proportion, so steady-state upkeep is unchanged (pinned by a test). One thing a
per-tick top-up got right for free: in a famine nobody may eat the granary, so a
sitting is capped at a head's worth of the store — that alone took starvation
over two hundred years from 340 to 182.

`JobBoard` also hands out the **nearest** piece of a trade's work now, anchored
on the worker's own door.

**The council leaves the valley.** A fourth `StewardEngine` clause charts the
nearest unknown region, works a landmark in its own valley, then goes over the
hill. Tuned twice by measurement — see §4.

### `3cb1473` — the land has weather, and the same seed founds the same colony

`Climate` is one thermometer read by both people and beasts;
`temperature_shift` on the biome makes where you settle a decision (tundra −13,
mountains −8, forest −2, coast +4, desert +11). A tundra winter reaches past a
roof and a coat.

And it is on screen: the status strip says what it is outside next to the season
that causes it, coloured when the day can hurt somebody, and the colonist card
itemises the sum out of `ComfortEngine.reckon` — the day is −35, your roof is
worth 26, your coat 11.

Plus the founder-id fix described above.

---

## 2. Still open, from Keks

### 2.1 The pace (§10.6)

> *"možná snížit tempo hry potom"*

Deliberately not done. `WorldConfig` carries the tick rate and slowing it is a
one-line change and a large balance change — and the thing that made it feel
fast was that events resolved without a middle, which is exactly what the three
commits above put back. **This one wants a phone in hand, not a probe.** Play it
first; if it still runs away, `realSecondsPerTick` is the knob and `DangerProbe`
is the check afterwards.

---

## 3. How the world measures now

`DangerProbe`, off unless asked:

```bash
EF_PROBE=1 swift test --package-path Core --filter DangerProbe
```

Two hundred years, seed 4242, nobody playing — **and reproducible for the first
time**:

```
deaths      old_age 190 · starvation 310 · sickness 4
population  266        morale 65        food 6/1950
fights      91  (41 turned back)        sicknesses 4
tribes      6   standings [−78, −56, −25, 0, 0, 74]
threat      22  predators 12
```

Do not compare these against any earlier handoff. Every previous run measured a
different colony.

**The one number that is shouting: 310 starved against 190 of old age, with the
granary at 6 of 1950 for most of the run.** This predates everything in §1 —
food income stops scaling with mouths somewhere past a few dozen souls and never
recovers. It is the largest measured failure in the game and it is the obvious
next session. Start from *what rate is food supposed to grow at, and can it
reach the population the housing allows?*

---

## 4. What the new work turned over, and how it was tuned

Worth reading before touching `StewardEngine` or `DiplomacyEngine`.

- **The council's outward push had to be tuned twice.** Unguarded it charted
  twenty-six regions in fifty years and spent every material the town would have
  built with: 44 buildings and 62 people became 33 and 32, and the colony never
  left the first era. It now looks over the hill only out of *overflow* (a bar
  above the one building has to clear), considers it once every three sittings,
  and keeps under an eighth of its adults abroad.
- **Every `dispatch` in the game was written for a player who tapped it once.**
  `chooseParty` refuses to strip a settlement "bare", meaning two people left
  standing — fine as a deliberate act, ruinous as a standing order. New rule 15
  in `BACKLOG.md`.
- **Defection was rolled per neighbour.** `0.30 × tribes met`, with nothing
  capping the count, so the colony began bleeding the moment it started
  exploring. It is one question asked once a year of the colony now. New rule 14.
- **People out at the ruins eat their provisions where they are.** Without that
  exception, four colonists on an expedition starved in a town with a full
  granary.
- **`theWorldAdvancesUnattended` now runs 4000 ticks, not 3000.** The colony
  reaches the second era about a decade later because it also charts a map and
  works ruins. The canary is *frozen*, not *slow* — but if that horizon has to
  move again, something is wrong.

---

## 5. Also still open, from before

- **Events happen nowhere, to nobody.** 40 of 71 never name a building, a place
  or a colonist, and every hook exists (`WorldQuery`, `EffectApplier`). Cheapest
  large win left.
- **Old English content** — events, buildings, techs are English-only.
  `LocalizedText` is in place; this is a translation pass.
- **Fields and herb beds are still places, not things.** The wood, the rock and
  the beasts are entities; `field` and `herbs` are still `ResourceNode` blobs.
- **Births do not keep pace; the era stalls.** Related to the famine above —
  measure the food first.
- Battle has **no sound and no haptics**.
- The world-map `SiteOutcome.narrative` is a plain `String`, not
  `LocalizedText` — the one journal line that cannot be Czech.

---

## 6. Things that will bite you

1. **Never seed an RNG from `hashValue`**, and never let an entity take the
   default `UUID()`. Swift seeds its hasher per process; a random id breaks
   determinism from the moment the entity exists. This has now cost two
   sessions, the second one at world creation itself.
2. **Every new field on a saved type is `decodeIfPresent` with a default**, with
   a "a save written before this existed still loads" test.
3. **Two numbers for one thing is the recurring design bug.** Derive the second.
4. **The recurring bug shape, now both ways round:** a rate that cannot reach
   its threshold (rule 6), *and* a rate multiplied by an entity count nobody
   bounded (rule 14).
5. **Check the drawing before rebuilding the system.** §1's first commit is
   presentation-only and fixed what read as a simulation problem.
6. Keks's Mac is an **8 GB Intel** machine; `signal 9` in the asset-catalog step
   is memory pressure, not the repo. Simulator is **iPhone 17**.

---

## 7. Where to look

| For | Read |
|---|---|
| Everything ever asked for | `docs/BACKLOG.md` |
| The 15 rules a change must not break | `docs/BACKLOG.md` § "Rules" |
| Systems and formulas | `docs/DESIGN.md` |
| Footprints, lots, pawn-like animals | `docs/RIMWORLD_LAYER.md` |
| Layer separation | `docs/architecture/LAYERS.md` |
| Whether the world is dangerous | `DangerProbe`, `EF_PROBE=1` |
