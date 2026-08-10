# Handoff — 2026-08-10 (second pass)

> **The camera now goes to what happened, and the game really was running
> twice.**

Branch **`main`**. Core green, iOS build green, run on the iPhone 17 simulator.

## What changed

| | |
|---|---|
| **Something happened *to* something** | `ColonyLogEntry.Subject` — `.pawn` / `.building(placementID)` / `.place`, optional and defaulted, set where the engine already had the thing: the colonist a disaster picked out, the lot a fire took hold on (`BuildingEngine.damage` returns its `seat` now), the ground a raid was fought over, a finished roof, a newborn. The Core says *who*; it still holds no screen position. |
| **The camera goes there** | `CanvasFocus` resolves a subject to a `LocalPoint` (`AgentMotion` for people, `normalizedLayout` for lots), `SettlementRenderer.Camera.framing` centres it under the pan gesture's own clamp, `SettlementCanvasView.fly` flies **once** and then lets go. Fires for a live siege, the battle report, a replay, and any `danger` line with a place. |
| **Every toast with a subject is tappable** | A `scope` glyph marks it; the tap takes you there. The quiet lines — a birth, a roof — are reachable without being intrusive. |
| **It was running twice** | `EndlessFrontierApp` opens the session from `.task` *and* from `scenePhase == .active`; a cold launch fires both, `isCatchingUp` covered only the long path, and two short opens advanced the world twice for one absence. `isOpeningSession`. Rule 29. |
| **The valley gets a turn** | `chartTheFog` returns and was tried first, and once the ledger stopped bleeding it could afford to every sitting: forty years, thirteen regions charted, four workable landmarks at home, zero parties. Alternating sittings. Rule 27. |
| **"Can it build" measures pay, not appetite** | `buildableHere` empty at year 100 was the colony *full*, not frozen — store at the cap, seventy-nine buildings, repeat cap `1 + population/15`. Rule 28. |

## Next

1. **The fertility clock** — unchanged and now measured twice: 79 buildings by
   year eighty, then population 69 → 29 with the store at its cap. `wed`/`fert`
   in `GrowthProbe.theCurve` are the instrument;
   `SocialEngine.weddingMinStrength` and how fast `Relationship.strength`
   climbs are the suspects.
2. **The repeat cap is tied to a falling population**, so a colony that shrinks
   can never rebuild. Look at it after the clock, not before.
3. **Give the rest of the journal a subject.** Nineteen engines write to it and
   six now say what they happened to. Weddings, plagues, the taming of a beast
   and a caravan's arrival are all one argument away.
4. Everything on the previous handoff's list below still stands, with one
   correction: a full `swift test` is **~46 minutes** on this machine now
   (1022 tests, measured 2767 s), not the 5–10 the older list says. Run it
   once, at the end, and use `--filter <TypeName>` — note the *type*, not the
   `@Suite` display name — while you are working.

---

# Handoff — 2026-08-10

> **Everything on the last list is done, and the thing the last list was about
> was not the thing that was wrong.**
>
> The colony was capped at ~55 and the diagnosis was housing: births die at 65%
> occupancy, the council does not act until 95%, the two thresholds never meet.
> That was true and it is fixed — and it moved the beds from 82 to 100 and no
> further, because **the colony had not been able to afford anything since year
> thirty**. `upkeepRateOfCost` is charged *per tick* at 0.03 against a year of
> sixty ticks: **180% of the price of everything you own, every year**.
> `buildableHere` came back empty for a hundred and seventy years while food,
> energy and influence sat pinned at the cap. See `docs/BACKLOG.md` §11.17 and
> rules **24**, **25**, **26**.

Branch **`main`**. Tests: **Core green**. Nothing under `App/Sources` changed —
the canvas already reads fighter positions off the Core (rule 18), so the scrum
shows without a line of view code.

## What changed

| | |
|---|---|
| **The roofs** | `StewardEngine.bedsWanted` — build against the ratio the births feel (`crowdedAbove`, 0.55), not against the last free bed. Dwellings are exempt from the repeat cap while the colony is short of them, because `1 + population/15` grows with a population that is bounded by the beds. |
| **The ledger** | `upkeepRateOfCost` 0.03 → **0.005** (`WorldConfig` *and* `world-config.json`). Physical wear was always separate (`BuildingEngine.weather`/`repair`). |
| **The battle** | No ring. `closingPoint` clamps to `posture.reach + SiegeField.scrumDepth`, and `SiegeEngine.shoulder` parts anybody standing inside anybody else (`bodySpace`, three passes a step, off a snapshot). The depth is emergent: whoever reached the fighting first is in the way. §11.15b. |
| **Events land** | The 34 that touched neither a person nor a place now break buildings, hurt the colonist least able to take it, or lift the colony — and a disaster that picks somebody out **names them in the chronicle**. |
| **Events are felt** | `pawn_mood` wrote into `mood`, which `PawnEngine` recomputes from needs every tick, so every authored mood effect in the game lasted one tick. It lands on `Pawn.moodShift` now and fades over a season. |
| **Events speak Czech** | 48 plain-string `narrative_hint`s are `{en, cs}`. Guarded, with the above, by two tests in `ContentTests`. |

Measured, seed 4242, two hundred years, before → after:

```
buildings   23 → 79      beds  82 → 160
peak pop    55 → 69      best chance at a child  0.0007 → 0.0031
```

## Next — the ceiling that is left, and where it is

The curve now **peaks at 69 around year eighty and decays to 29 by year two
hundred**, all of old age. Housing is not it (headroom 0.32–0.35 through the
growth years), food is not it (granary at the cap the whole way), the ledger is
not it (materials at the cap from year sixty).

It is `fert` in `GrowthProbe.theCurve` — couples with **both** partners inside
the fertile window. It runs 9–12 while the colony grows and **1–4 for the whole
second century**. The founders age out together and the bonds that would replace
them form too slowly to catch it: a colonist has to make a friend, the friendship
has to reach `SocialEngine.weddingMinStrength`, and by the time it does the
couple is past its best years.

So the next question is the **social clock**, not the roofs and not the ledger:
how fast `Relationship.strength` climbs, and whether a widow or widower ever
finds anybody again. Measure first — `wed` and `fert` are already the instrument
— and beware the shape this project keeps producing: a threshold beyond the reach
of the rate meant to cross it (rule 6, now nine times).

After that, in order:

1. **`GrowthProbe.theChain` has new columns** (`want`, `mats`, `built`, `site`).
   Use them: `beds < want` with `mats` at 1 is a colony that wanted a roof and
   could not have one, and it looks identical to a contented one in the `beds`
   column alone.
2. **The battle has no sound and no haptics**, and `BattleMoment` still does not
   carry the wound kind, so the report says "wounded" where it could say "a stab
   to the shoulder".
3. **Buildings that cannot be sited are still built.** `GameEngine.build` enqueues
   with `placementID: nil` when `ColonyBuilder.placeSiteAtFirstFit` finds no room,
   so a full 24×24 colony grows a ledger the canvas cannot show (rule 18). It has
   not bitten yet at 79 buildings; it will.
4. **Old English content** — buildings and techs are still English-only. Events
   are done.

## Things that will bite you

Everything in the previous handoff's list still holds. Add:

1. **Say a per-tick rate out loud times `ticksPerYear` before believing it**
   (rule 24). 0.03 a tick is 180% a year.
2. **A store that clamps at zero turns a sink into a trap** (rule 25). Ask what
   income scales with the cost, and whether the colony can still reach it from
   the floor.
3. **An effect written into a derived field does nothing** (rule 26). `mood` is
   recomputed every tick; so is `Settlement.population`.
4. **Do not compare two probe runs across an edit.** Both probes take two and a
   half minutes; a background run started before an edit finishes against the old
   code, and combat changes move the growth curve. Determinism is intact —
   checked directly, two processes, identical fingerprints for 800 ticks.

---

# Handoff — 2026-08-07 (third pass)

> **Everything on the previous handoff's list is done.** Newcomers (§11.11),
> the weather (§11.12), the world map (§11.13), a bigger frontier and places
> that are landmarks in themselves (§11.14).
>
> **Battle finally has a specification** (§11.15) — *"bitva nevypadá jako bitva
> ale jako dvě řady lidí co mávají mečem"* — and it is **half done**. The
> formation has depth on the approach; the defence still flattens into one row
> on contact, because `SiegeEngine.closingPoint` puts the whole line on one
> ring. Fixing that properly is a *combat* change, not a presentation one: the
> obvious version was written and reverted after it dropped "a fight leaves the
> line hurt" from eight defenders marked to two. **Start here, and run
> `DangerProbe` beside it.** The next move is probably a scrum rather than a
> ring — on contact the ranks stop existing and the bodies knot around the
> fighting.

---

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
