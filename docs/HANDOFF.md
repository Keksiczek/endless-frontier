# Handoff — 2026-08-06 (second pass)

Branch **`main`**, clean and pushed.

Tests: **932 Core**, app build and tests green.

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

**Food is a chain now** — farms own plots, plots ripen and are reaped, the
harvest is carried in like timber, and a cook turns it into what the colony
eats. The write-up, including the arithmetic that caused the old famine and the
five things the change turned over, is `docs/BACKLOG.md` §10.8–10.9.

**And the two measurements disagree. Read §3 before believing either.**

- Unattended (`TickEngine.advance`, 12 000 ticks, seed 4242): starvation
  **182 → 5**, the colony lives, food stays near the cap. This is what
  `FoodChainTests` pins.
- `DangerProbe`, same seed and length: starvation **182 → 451**, population 108,
  food 0 of 1850. **Worse than before the change.**

The difference is the harness, and the cause is understood: `DangerProbe` drives
the world through `BalanceHarness.autoPlay`, which calls `GameEngine.build`
directly and picks "the building the capital has fewest of". It therefore never
sees `StewardEngine`'s new plot-capacity clause, and never keeps fields in step
with a population its own greedy research is growing. So the colony it plays out
is a colony that builds a second observatory instead of a third farm.

**Keks's call, 2026-08-06: a colony nobody manages is allowed to starve.** So
the probe's 451 is not a bug to be tuned away — it is a badly-run colony getting
what a badly-run colony gets, and the chain is doing its job by making bad
management fatal. What the numbers say together is the thing worth keeping:
manage your fields and the famine is over (5 dead in two centuries); don't, and
the valley buries you. That is a game, where before it was arithmetic nobody
could influence.

Do not quote "182 → 5" without saying which path it was measured on.

---

## 1. What shipped

### The chain

```
plot ripens (season + weather)  →  farmer reaps it  →  grain/roots/greens on the ground
      →  hauler carries it in   →  cook makes a meal  →  storage[.food]  →  somebody eats
```

- **`Crop` + `FarmEngine`.** A farm building owns `plots` derived from its
  footprint, exactly as `sleepers` is (rule 8). A plot carries a crop that grows
  with the season and the temperature — **winter grows nothing**, which is the
  first time the granary has had a reason to exist — and gives up raw
  ingredients when somebody walks out and cuts it.
- **`CookingEngine` + `meals.json`.** Eight meals, CZ+EN. Cooks pick by food per
  batch *weighted by the pressure it puts on the shelf*, so the kitchens use up
  what there is most of. That weighting is not a nicety: without it the colony
  buried itself under 2 852 greens and 17 grain and went extinct.
- **`WorkKind.cooking`**, a `cookhouse` (starter building, new renderer
  archetype), a `.cooking` share in `LaborEngine.quotas`, and a founder who can
  cook.
- **Hunting yields `meat`**, foraging yields `berries`. The hide is what is left
  over now rather than the point of the hunt.
- **The shelf has a ceiling.** Foodstuffs share the granary's capacity; what
  there is no roof for goes over. Ore and clay are left uncapped — that is a
  separate argument and this change should not smuggle it in.

### What `.food` means now

**Cooked meals in the larder**, and nothing else. Every existing reader —
`ErrandEngine`, morale, famine, trade, caravans, expedition provisions, events,
laws, quests, `DangerProbe` — is untouched and still correct. The chain was
built *in front of* the pool rather than replacing it, which is why no authored
content had to change.

---

## 2. Still open, from Keks

### 2.1 The pace (§10.6)

> *"možná snížit tempo hry potom"*

Still not done, and still wants a phone in hand rather than a probe.
`realSecondsPerTick` is the knob, `DangerProbe` is the check afterwards.

### 2.2 ~~The plots are not on the canvas~~ — done 2026-08-06

`JobBoard` posts `workPlot` and `cookMeal`; `Job.cropID` names the furrow; the
farmer sent to a plot is the one who reaps it; `SettlementCrops` draws the beds,
the shoots and a half-cut harvest; and the inspector reads the job rather than
the trade, so the card says "Tending the grain — 6 % ripe" over a figure
standing on that plot. See `docs/BACKLOG.md` §10.10.

Verified in the simulator, not only in tests — which is how the first cut was
caught: the plots were laid out over the farm's whole footprint and every one
of them was **drawn underneath the building**. They existed, ripened and were
reaped, invisibly, for a whole build.

### 2.3 Weather, checked — done 2026-08-06

`Climate` was sound; two things read only half of it. Crops had a cold floor and
no ceiling (a 42° desert summer did nothing), and a farm sowed the same rotation
on the tundra as on the plains. Both closed — `docs/BACKLOG.md` §10.11 has the
temperature table.

---

## 3. How the world measures now

`DangerProbe`, off unless asked:

```bash
EF_PROBE=1 swift test --package-path Core --filter DangerProbe
```

Two hundred years, seed 4242, nobody playing — **and the harness matters**.

`DangerProbe` (world driven by `BalanceHarness.autoPlay`):

```
                        before (6134290)      after (this commit)
deaths   old_age            134                 119
         starvation         182                 451     ← worse
         sickness             3                  23
population                  295                 108
food                       7/2000              0/1850
fights                      88                  75
```

Plain unattended `TickEngine.advance(world, ticks: 12_000)`, same seed:

```
                        before                after
deaths   old_age            —                  132
         starvation         —                    5
population                  —                   81
food                        —              2740/2750
```

### 3.1 Reading the two numbers

They are not in conflict; they are the two ends of the same lever, and both are
wanted.

`BalanceHarness.autoPlay` builds the thing the capital has *fewest* of and
researches the cheapest study going — so it grows the population hard and lets
the fields fall behind, and it never consults `StewardEngine.nextBuilding`,
where the plot-capacity clause lives. It is a colony that builds a second
observatory instead of a third farm, and it starves. **That is allowed** (Keks,
2026-08-06): a colony nobody manages may die of hunger.

So neither number should be tuned toward the other. What must stay true is the
gap between them: the managed path (`StewardEngine`, `FoodChainTests`) has to
stay survivable, and the reachability test is what pins that honest. If a future
change closes the gap from either side — the unmanaged colony stops dying, or
the managed one starts — that is the regression, not the absolute figure.

Run both, every time.

---

## 4. Things that will bite you

1. **Never seed an RNG from `hashValue`**, and never let an entity take the
   default `UUID()`. `FarmEngine.plotID` derives a plot's id from the farm
   placement's own bytes for this reason.
2. **Every new field on a saved type is `decodeIfPresent` with a default.**
   `crops`, `usesEntityFields`, `harvestCredit`, `kitchenProgress`. Guarded by
   "A save written before there were plots still loads" — and that test also
   pins that such a save keeps the **old** food arithmetic, because a save with
   no plots *and* no per-skill trickle simply starves.
3. **`isEmpty` is not "has no layer"** — `usesEntityFields` is the third of
   these (`usesEntityLand`, `StoneField.usesBlocks`). A colony between harvests
   has no crops either.
4. **An income is not a store** (new rule 16). A council that builds farms when
   the larder is thin builds them a year too late; it has to compare the fields
   against the mouths. This is what killed two separate attempts at the balance.
5. **A trade with no members cannot acquire any** (new rule 17). `rebalance`
   now runs without a policy, which is the only reason cooking ever reaches a
   town where nobody is idle.
6. **Check the drawing before rebuilding the system** — and this time it bit in
   a new way: the plots were not merely undrawn, they were drawn *underneath*
   the building that owns them. A thing that renders and is covered looks
   exactly like a thing that does not render. Screenshot it.
7. **A `Job` is what somebody is doing; a `WorkKind` is only what they are.**
   `workplace` reads the job, so anything else that describes a colonist has to
   read it too or the two will disagree about the same person. That is what
   "je uvnitř, píše to venku" was.
8. Keks's Mac is an **8 GB Intel** machine; `signal 9` in the asset-catalog step
   is memory pressure, not the repo. Simulator is **iPhone 17**.

---

## 5. Also still open, from before

- **Events happen nowhere, to nobody.** 40 of 71 never name a building, a place
  or a colonist, and every hook exists (`WorldQuery`, `EffectApplier`). Cheapest
  large win left.
- **Old English content** — events, buildings, techs are English-only.
  `LocalizedText` is in place; this is a translation pass.
- **Herb beds are still places, not things.** Fields are plots now; `herbs` is
  still a `ResourceNode` blob.
- **Births do not keep pace; the era stalls.** No longer entangled with the
  famine — worth measuring on its own now that food is not the binding
  constraint.
- Battle has **no sound and no haptics**.
- The world-map `SiteOutcome.narrative` is a plain `String`, not
  `LocalizedText` — the one journal line that cannot be Czech.

---

## 6. Where to look

| For | Read |
|---|---|
| Everything ever asked for | `docs/BACKLOG.md` |
| The famine and the food chain | `docs/BACKLOG.md` §10.8–10.9 |
| The 17 rules a change must not break | `docs/BACKLOG.md` § "Rules" |
| Systems and formulas | `docs/DESIGN.md` |
| Footprints, lots, pawn-like animals | `docs/RIMWORLD_LAYER.md` |
| Layer separation | `docs/architecture/LAYERS.md` |
| Whether the world is dangerous | `DangerProbe`, `EF_PROBE=1` |
