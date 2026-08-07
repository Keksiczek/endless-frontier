# Handoff — 2026-08-07

Branch **`main`**, clean and pushed.

Tests: **933 Core**, app build and tests green.

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

Two measuring instruments, both off unless asked:

```bash
EF_PROBE=1 swift test --package-path Core --filter DangerProbe
```

```bash
EF_PROBE=1 swift test --package-path Core --filter GrowthProbe
```

---

## Read this first

The colony's whole **scale** changed on 2026-08-07, and everything balanced
against the old scale is now suspect. A settlement is founded with twelve
people, not nineteen; a hut is a household of eight, not twelve; a tick is two
real minutes, so a year is two hours; and **children come out of marriages
rather than out of a birth rate**.

The full account — seven hard edges found on the way, each of which showed up
only as "the colony is gone by year 130" — is `docs/BACKLOG.md` §11.4 and §11.7.
Read them before touching `PopulationEngine`, `SocialEngine` or
`LaborEngine.quotas`.

**Where it actually stands, measured, seed 4242, 200 years: founded 12, 31 by
year fifty, then a long decline to six. The social layer is no longer the
limiter. Food is.** 17 dead of starvation against 37 of old age, granary at zero
for eight of the twenty decades. That is the first thing to fix, and §1 below
says why it is not the famine that was already fixed.

---

## 1. Next: the labour quotas are shares of a workforce that no longer exists

**The one to do first.** `LaborEngine.quotas` are fractions of the adult
workforce, written when a colony was eighty people. A village of twenty adults
gets:

| trade | share | people in a village of 20 adults |
|---|---|---|
| farming | 0.20 | 4 |
| logging | 0.12 | 2.4 |
| **cooking** | **0.07** | **1.4** |
| research | 0.10 | 2 |
| hunting | 0.07 | 1.4 |
| foraging | 0.06 | 1.2 |
| scouting | 0.05 | 1 |
| trade | 0.05 | 1 |
| healing | 0.05 | 1 (and gated at 16 population) |

A colony that loses its one cook eats raw off the shelf
(`ErrandEngine.rawFoodValue` — deliberately poor) until it starves. That is the
measured 17 starvation deaths: **not** the §10.8 famine, which was three hundred
people outgrowing their fields. This is twenty people who cannot keep a kitchen
staffed.

Every trade in the table wants re-checking against the number of people who
actually exist, and the honest shape of the fix is probably *floors* rather than
shares for the trades a colony cannot do without — one cook and one farmer
before any share applies. `rebalance` already moves one person per cadence and
now runs without a policy, so the mechanism to reach a full town exists; what is
missing is the rule that says "a colony always has a cook".

Guard it with a reachability test (rule 6), not a behaviour test: *can a colony
of N adults staff the trades it cannot live without, for every N the game
allows?*

## 2. Also open, from Keks

### 2.1 The map does not look like a map (§11.5)

> *"tiles na mapě nevypadají vůbec jako mapa"*

Written down, **not diagnosed**. Two candidate tilings with two different
problems — the hex world map (`WorldMapScreen`, `Region`) and the settlement
ground (`SettlementGround`, `LocalTerrain`) — and the complaint does not say
which. Screenshot both at three zooms before touching either.

The shape to look for is the one this project keeps producing: a field drawn
from noise that reads as *pattern* rather than as *country*, because the noise
is isotropic and the map is not. Rules 10 and 10b are both this, both found in
the ground layer.

### 2.2 Battle and attacks, again (§11.6)

Flagged, **not specified**. The mechanism is sound — `SiegeEngine` moves real
fighters at real positions and `SettlementBattle` draws blows between the two
bodies that are touching. What is wanted is a different *feel*, and Keks has to
say what is wrong with this one before anything is rebuilt. §8.1 is two sessions
of evidence that tuning a shape nobody wants is work thrown away.

### 2.3 The weather has to be alive (§11.8)

> *"stejně tak počasí atd, vše bude proměnlivé, ne pevně dané, dynamické dle
> simulace"*

`Climate.base(season)` is four constants plus a per-biome shift, so every spring
in a colony's life is exactly 11 °C. Consistent, and not weather.

What it wants: a temperature that wanders around the season's mean, years that
are harder or milder than usual, and the odd winter people still talk about —
all derived from `(mapSeed, tick)` so it stays deterministic and replayable.

Worth doing straight after the map: the crops, the comfort bands, the animals and
the status strip **all already read `Climate`**, so there is one place to change
and five things that come alive from it. Note that `FarmEngine.growthStep` reads
both ends of the range now (cold floor and heat ceiling), so a bad year would
immediately mean a bad harvest.

### 2.4 Growth past a village — newcomers, not a bigger number

The colony does not become a civilisation, and it is not yet decided whether it
should. The cause is structural, not tuning: a closed founding party is a
positive-feedback loop (people → couples → children → people) running barely
above unity. Real colonies grow by **immigration**, and the pieces exist —
`visitors_refugees`, the tribes, `add_pawn` — and are event-rare.

If this gets picked up, answer it with newcomers arriving rather than with a
higher birth chance. Keks has said plainly that a colony being *able* to fail is
wanted (*"líbí se mi, že to může failnout na základě nějakého RNG"*), so the
target is a world where a village can die and a well-run one can grow, not one
where growth is guaranteed.

## 3. Older, still open

- **Events happen nowhere, to nobody.** 40 of 71 never name a building, a place
  or a colonist, and every hook exists (`WorldQuery`, `EffectApplier`). Cheapest
  large win left.
- **Old English content** — events, buildings and techs are English-only.
  `LocalizedText` is in place; this is a translation pass.
- **Herb beds are still places, not things.** Fields became plots; `herbs` is
  still a `ResourceNode` blob.
- Battle has **no sound and no haptics**.
- The world-map `SiteOutcome.narrative` is a plain `String`, not
  `LocalizedText` — the one journal line that cannot be Czech.

## 4. Things that will bite you

1. **Never seed an RNG from `hashValue`**, and never let an entity take the
   default `UUID()`. Per-entity randomness comes from `(mapSeed, id, tick)`, so
   a hashed or random id is a different world every launch.
2. **Every new field on a saved type is `decodeIfPresent` with a default.**
   Recent ones: `crops`, `usesEntityFields`, `harvestCredit`, `kitchenProgress`,
   `Job.cropID`, `Crop.halfWidth`/`halfHeight`, `Relationship.lastChildTick`.
3. **`isEmpty` is not "has no layer"** — `usesEntityLand`, `usesEntityFields`,
   `StoneField.usesBlocks`.
4. **A cap in ticks is a cap in wall-clock time only until a tick changes.**
   `realSecondsPerTick` doubled this session and `maxOfflineTicks` had to halve
   with it. `WorldConfig.default` mirrors `world-config.json` and they must be
   edited together.
5. **A birth rate is not a population knob** (rule 19). Births and deaths are
   both per-capita, so there is no equilibrium population — only growth or
   collapse. Size comes from the roofs.
6. **A rate linear in population against an opportunity space quadratic in it
   shrinks as the world succeeds** (rule 20). This is what made friendships
   unable to reach a wedding in any colony bigger than a dozen.
7. **What is in the simulation is on the canvas** (rule 18). Anything that
   describes a colonist reads the same source the drawing does.
8. **Check the drawing before rebuilding the system** — and remember a thing
   that renders and is *covered* looks exactly like a thing that does not
   render. The crop plots were drawn underneath their own farm for a whole
   build. Screenshot it.
9. Keks's Mac is an **8 GB Intel** machine; a full `swift test` is 6–12 minutes
   and two concurrent runs make both crawl. Simulator is **iPhone 17**.

## 5. Where to look

| For | Read |
|---|---|
| Everything ever asked for | `docs/BACKLOG.md` |
| The colony's new scale, and the seven edges | `docs/BACKLOG.md` §11.4, §11.7 |
| The food chain | `docs/BACKLOG.md` §10.8–10.10 |
| The 20 rules a change must not break | `docs/BACKLOG.md` § "Rules" |
| Systems and formulas | `docs/DESIGN.md` |
| Footprints, lots, pawn-like animals | `docs/RIMWORLD_LAYER.md` |
| Layer separation | `docs/architecture/LAYERS.md` |
| Whether the world is dangerous | `DangerProbe`, `EF_PROBE=1` |
| What shape a colony's life has | `GrowthProbe`, `EF_PROBE=1` |
