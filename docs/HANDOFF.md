# Handoff — 2026-08-07 (second pass)

Branch **`main`**, clean and pushed.

Tests: **942 Core**, app build green.

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

Three measuring instruments, all off unless asked:

```bash
EF_PROBE=1 swift test --package-path Core --filter DangerProbe
```

```bash
EF_PROBE=1 swift test --package-path Core --filter GrowthProbe
```

`GrowthProbe` runs two tables now: `theCurve` (the population and the couples
behind it) and **`theChain`** (the food chain link by link — farmers, cooks,
plots, shelf, larder, beds, headroom). Run both before touching anything that
touches food, because `food = 0` is four different colonies in trouble and they
want opposite fixes.

---

## Read this first

**The colony no longer starves.** Seed 4242, 200 years: `starvation: 0` against
`old_age: 46`, and the granary holds between 1134 and 1150 every decade of the
two centuries. It was 18 starved and the larder empty for ten of twenty decades
this morning.

The two things that were wrong are written up in `docs/BACKLOG.md` §11.9, and
neither of them was the labour quota table the last handoff pointed at:

1. **`ErrandEngine.furthestWorthGoing`** — a comfort cap ("not worth the walk")
   applied to hunger. Anybody working further than half the valley from the
   granary was refused the eat errand every tick from `hungryBelow` down to
   zero. They starved beside a full store.
2. **`CookingEngine`'s banked effort** was capped at one batch of the *cheapest*
   meal while `best(for:)` reached for the *dearest*. A kitchen with one
   unskilled cook cooked **nothing at all**, for ever. It needed a cookhouse to
   bite, so: the colony died because it built a kitchen.

Both are new faces of rule 6, and they are now rules **21** and **22** in
`docs/BACKLOG.md`. Read them before writing another accumulate-then-spend loop
or another "not worth it" threshold.

The quota floors the last handoff asked for are in as well — `LaborEngine.floors`,
one farmer and one cook before any share applies — because at seven adults half a
person is 0.071 and cooking's whole share is 0.07, so `rebalance` could never
make the move.

---

## 1. Next: decide what growth *is*, then build it

**A design question, not a bug, and it wants Keks before it wants code.**

With the food chain honest, the colony peaks at **30 around year forty** and
declines to three by year two hundred, entirely of old age. `docs/BACKLOG.md`
§11.10 has the measurement that rules out the usual suspects:

- **Not food** — granary full the whole way, shelf at its ceiling.
- **Not the roofs** — 82 beds against 23 people, `headroomFactor` 0.40–0.55.
  Rule 19 says check this first; it is not this.
- **Not the social layer** — 7–10 couples, 3–6 of them fertile.

It is the ratio: about **0.2 births a year against 0.24 deaths**. A closed
founding party is a positive-feedback loop and this one runs a hair under unity,
so it decays on a two-century timescale however well every part works.

Keks has said a colony being able to fail is wanted (*"líbí se mi, že to může
failnout na základě nějakého RNG"*). Right now **every** village fails, which is
the other half of that. The two answers are different games:

- raise `PopulationEngine.conceive`'s odds → a colony that grows because the
  dice were retuned;
- **newcomers** — `visitors_refugees`, the tribes, `add_pawn`, all of which
  exist and are event-rare → a colony that grows because people came.

Ask which. Do not pick one quietly.

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

The best-value item on this list. The crops, the comfort bands, the animals and
the status strip **all already read `Climate`**, so there is one place to change
and five things that come alive from it. `FarmEngine.growthStep` reads both ends
of the range now, so a bad year would immediately mean a bad harvest — which
also means it is the first change that could make the food chain bite again.
Re-run `GrowthProbe.theChain` after it.

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
- `GameDataRegistry.cookableMeals` re-sorts the whole meal table on every
  access, and it sits inside the per-tick cooking loop (rule 4). Small, real.

## 4. Things that will bite you

1. **Never seed an RNG from `hashValue`**, and never let an entity take the
   default `UUID()`. Per-entity randomness comes from `(mapSeed, id, tick)`, so
   a hashed or random id is a different world every launch. **And never iterate
   a `Dictionary` where the result decides anything** — Swift does not keep that
   order stable between runs. Found this session in `LaborEngine.rebalance`'s
   eviction loop, where two trades tied on surplus handed the colonist to
   whichever came out first.
2. **Every new field on a saved type is `decodeIfPresent` with a default.**
   Recent ones: `crops`, `usesEntityFields`, `harvestCredit`, `kitchenProgress`,
   `Job.cropID`, `Crop.halfWidth`/`halfHeight`, `Relationship.lastChildTick`.
3. **`isEmpty` is not "has no layer"** — `usesEntityLand`, `usesEntityFields`,
   `StoneField.usesBlocks`.
4. **A cap in ticks is a cap in wall-clock time only until a tick changes.**
   `WorldConfig.default` mirrors `world-config.json`; edit them together.
5. **A birth rate is not a population knob** (rule 19). Size comes from the
   roofs — but check that it *is* the roofs before you reach for them. It was
   not, this time: 82 beds and 23 people.
6. **A rate linear in population against an opportunity space quadratic in it
   shrinks as the world succeeds** (rule 20).
7. **A bank capped at the cheapest batch can never buy the dearest** (rule 21,
   new). Ask what the thing being saved for costs, and whether *one* worker's
   rate plus the carry-over reaches it. Aggregate throughput tests go straight
   past this: `cooksKeepUpWithFarmers` divides a thousand cooks' hands by the
   dearest meal and was green all along.
8. **A "not worth it" threshold on a survival path is a death sentence**
   (rule 22, new). It hides perfectly, because every metric upstream reads fine
   — the granary was at 1148 of 1150 while people starved next to it.
9. **What is in the simulation is on the canvas** (rule 18).
10. **Check the drawing before rebuilding the system** — a thing that renders
   and is *covered* looks exactly like a thing that does not render.
11. Keks's Mac is an **8 GB Intel** machine; a full `swift test` is 5–10 minutes
   and two concurrent runs make both crawl. Simulator is **iPhone 17**.

## 5. Where to look

| For | Read |
|---|---|
| Everything ever asked for | `docs/BACKLOG.md` |
| The two that starved the colony | `docs/BACKLOG.md` §11.9 |
| Why it still shrinks, and what is ruled out | `docs/BACKLOG.md` §11.10 |
| The colony's scale, and the seven edges | `docs/BACKLOG.md` §11.4, §11.7 |
| The food chain | `docs/BACKLOG.md` §10.8–10.10 |
| The 22 rules a change must not break | `docs/BACKLOG.md` § "Rules" |
| Systems and formulas | `docs/DESIGN.md` |
| Footprints, lots, pawn-like animals | `docs/RIMWORLD_LAYER.md` |
| Layer separation | `docs/architecture/LAYERS.md` |
| Whether the world is dangerous | `DangerProbe`, `EF_PROBE=1` |
| What shape a colony's life has | `GrowthProbe.theCurve`, `EF_PROBE=1` |
| Where the food chain breaks | `GrowthProbe.theChain`, `EF_PROBE=1` |
