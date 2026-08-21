# Where the game stands, and what to do next

**Written 2026-08-17, for a chat starting cold.** Read this, then
[`CODEMAPS/architecture.md`](CODEMAPS/architecture.md) and **[`RULES.md`](RULES.md)**
(38 rules, each of which cost a session). [`BACKLOG.md`](BACKLOG.md) is the long
history; this file is the short answer to *"what should I work on?"*.

```bash
cd Core && swift test          # 1145 tests, 146 suites, ~27 min
```

```bash
cd App && xcodegen generate && cd .. && xcodebuild -project App/EndlessFrontier.xcodeproj -scheme EndlessFrontier -destination 'platform=iOS Simulator,name=iPhone 17' test
```

---

## 1. What it is now

A deterministic colony simulation with a living top-down canvas. Seven founders,
a two-minute tick, a five-real-minute drawn day. **67 engines, 50 model types,
97 view files.** Content: 56 buildings, 37 techs, 182 events, 7 biomes, 46
conveyances, 306 items, 306 recipes — all bilingual CZ/EN, guarded by a test.

What works and is worth protecting:

- **Everything on the canvas is the simulation.** Colonists walk their day,
  haul, take cover behind walls, sleep at night; the renderer never invents a
  position it could ask for. This is the game's whole identity (rule 5).
- **The chain is real, not a number.** Plots ripen → a farmer reaps → a hauler
  carries → a cook makes meals → people eat. Heaps left out now rot.
- **Things wear.** Buildings weather by what they are made of, where they stand
  and what the sky is doing; gear wears by swinging, being swung at, and work.
- **A raid is a fight you stand in**, with cover derived from height ×
  substance, ramparts that count where they stand, and a watchtower that shoots.
- Society, faith, neighbours, chronicle — all present and all reachable.

---

## 2. What is broken or invisible right now

Ordered by *how likely a player is to hit it*. These are the first batch.

### 2.1 ~~A town past thirty buildings is half-drawn~~ — **done 2026-08-20**

Fixed, and it was worse than the heading said. The cut lived inside
`normalizedLayout`, which `AgentMotion` also reads for homes, beds and work
posts — so the forty-nine buildings past the cap were not merely undrawn:
**nobody could live or work in them.** The layout is complete now and the budget
(`maxDrawnBuildings`, 120) applies to one frame: cull to the camera's rect, and
when a town still overflows, keep what is nearest the middle of the view. Ids
come from the complete layout, so culling never renumbers a selection.
`RenderBudgetTests` pins all five claims. Rule **63**.

<details><summary>What it used to say</summary>

`SettlementRenderer.maxVisibleBuildings = 30`, applied as
`colony.placements.prefix(30)`. Placements are in build order, so the buildings
that vanish are **the newest ones** — the one the player just paid for and
watched go up. A colony at year 40 has well over thirty. `maxVisibleAgents` is
90 and much safer, but has the same shape.

Not a constant to simply raise: it exists because the frame cost is real. Do it
properly — cull by what is **on screen** (the camera's world rect) rather than
by array order, and keep a cap on what a single frame draws. The fix and the
measurement belong together: after §11.36's sort bug, the ground is no longer
the bottleneck, so the budget is worth re-measuring before choosing a number.
</details>

### 2.2 ~~Opening after a long absence looks like a hang~~ — **done 2026-08-20**

`GameEngine.openSession(_:now:registry:sliceTicks:onProgress:)` runs the
catch-up in slices and reports `(done, total)`; `CatchUpOverlay` shows a
determinate bar and **the years counting up**, which is the unit a player thinks
in. Slicing a deterministic simulation is the dangerous part, so it is guarded
rather than argued: `CatchUpSliceTests` runs the same absence whole and in
slices of 1, 13, 240 and 10,000 and requires the identical `WorldState`. It is
safe because `TickEngine.advance` is a plain loop over a pure step and `ticks`
is nothing but its bound.

<details><summary>What it used to say</summary>

Catch-up simulates up to 30 days off the main actor and shows a spinner with no
progress, no estimate, and no way out. In a debug build a multi-day absence is
**minutes**. The player cannot tell it from a freeze — and until §11.36 it
partly *was* one. Wants: a progress figure (ticks done / total), the years
counting up as they pass, and a cap the player can understand ("a month is as
far as the world runs without you").

</details>

### 2.3 Storeys exist in the drawing and not in the data — **half done 2026-08-20**

Measuring it found a bigger hole than the one described. Only five buildings in
the game have `housing` at all, and between the longhouse (early settlement) and
the apartment block (modern) there was **no new dwelling for three entire
eras** — a player's housing did not change for most of the game. Three added,
priced off the beds-per-material curve the shipped dwellings already describe
(2.00 → 1.29 → 1.04 → 0.80) rather than off a guess: `courtyard_house`
(ancient, 3×3×2, opened by masonry), `townhouse_row` (medieval, 4×2×2, guilds)
and `brick_tenement` (early industrial, 3×3×3, sanitation — more people for
less, at −1 morale, and it knows it).

Still open, and still a deliberate decision rather than a fix: whether the
**hut and the longhouse** should carry a loft. That one moves the growth curve
(`sleepers = footprint × 2 × floors`), so it wants `GrowthProbe` re-run either
side of it.

<details><summary>What it used to say</summary>

`floors` is drawn now, but only `apartment_block` (5) and `arcology` (12) carry
it, so every building a player sees for the first two hundred years is one
storey. Raising it on a hut is **not** a drawing change: `sleepers = footprint ×
2 × floors`, so a longhouse with a loft sleeps twice as many and the growth
curve moves. Decide deliberately: either give `floors` to the buildings that
plainly have them and re-run `GrowthProbe`, or split "drawn storeys" from
"storeys that hold beds" and accept two numbers for two different things.

</details>

### 2.4 The era ladder is probably unreachable, and nobody has measured it

`eras.json` asks for population **18 → 45 → 110 → 260 → 600**. The colony sits
at 67 in year 40 of a real save. 260 and 600 are the shape rule 6 keeps
catching: a threshold nobody checked against the rate meant to cross it. Measure
with `GrowthProbe` over 200 years *before* writing any content for the late
eras. If they are out of reach, that is the whole late game sitting behind a
door that does not open.

### 2.5 ~~The world is silent~~ — **done 2026-08-17**

Built, generated rather than recorded: `Soundscape` (pure mapping, tested) plus
`AudioEngine` (an `AVAudioSourceNode` doing the DSP). Wind, rain, crickets, the
village, fire; five stings; a volume in Settings. No assets, no licences.

What is left of it: **music.** A theme wants a real track from a clean source —
a generator does texture well and melody badly. See §11.30.

---

### 2.6 ~~The world map has no roads~~ — **done 2026-08-21**

`RoadLink` / `RoadNetwork` / `RoadEngine`, and `docs/ROADS.md` for the whole
design. What it closed: travel time was `hexes × 26` and nothing the colony did
could change it; `TradeRoute` named two ends and no path; and forty-six
conveyances carried a `regionPace` of 0.7…50 that the world had nowhere to
spend. Roads appear where the world actually goes — caravans and expeditions
record their route, traffic wears a track, and the council pays to make a road
out of whichever edge carries the most traffic through the worst country.

Still open there: bridges, cutting a road in war, infrastructure ruins, and a
road the *player* lays rather than the council. Measure with `RoadProbe` before
touching a number.

## 3. What the design promises and has not delivered

### 3.1 Layer 3 — the narrator

`docs/architecture/LAYERS.md` describes three layers; the third is not built.
The Core is narrator-agnostic and stays that way, so this is additive: a
protocol the app talks to, an offline fallback that is what the game does today,
and an optional LLM that turns a year's `WorldRecord` into a paragraph somebody
would read. **Offline-first is a hard rule** — the narrator can never be
required for play.

### 3.2 A reason to keep playing past the first hundred hours

There are objectives, quests (7) and eras, but no long arc a player can name.
The chronicle is the most distinctive thing the game has and it is a chart —
this is where a "history of my colony" that reads like a book would land, and
where the narrator earns its place.

### 3.3 Neighbours are emergent but thin

Tribes appear from secession and first contact, trade, marry, defect and raid.
What is missing is anything the player *does* about them between raids: an
embassy, a tribute, a joint venture, a border they can see on the map.

---

## 4. Craft and polish

| Thing | State | Worth |
|---|---|---|
| Onboarding | **done 2026-08-21** — `FirstRunView`: four cards, the four things that are not guessable | done |
| Accessibility | 21 files carry labels; the canvas itself is unlabelled to VoiceOver | medium |
| Saves | **backup done 2026-08-21** — `.bak` rotation and a fallback when the save will not decode. Slots and export still missing | partly |
| Haptics | none | low |
| App icon | one 1024 png, present | done |
| Release profiling | never done; all timings so far are debug builds | high before ship |

A save backup is cheap and worth doing before anything that touches
`WorldState`: write to a temp file, keep the previous as `.bak`, fall back on a
decode failure.

---

## 5. Measurement, before more content

### `EraProbe`, run 2026-08-19 — the ladder is reachable, and two other things

Built to answer "is the late game behind glass, and should we stop generating
content for it?" The answer is **no, generate freely**: a colony left entirely
alone reaches the last era in year 225 of 250, and *nothing* is unreachable —
0 of 152 events, 0 of 31 techs, 0 of 49 buildings.

```
year   era                 pop   prosp  techs  repeats  towns
  10   ancient              21     90      5        0      1
  40   medieval             48     98     19        0      1
  60   medieval             43     95     31        2      1   ← tree finished
 120   early_industrial    115     85     31       15      2
 170   modern              262     88     31       21      3
 225   near_future           —      —     31        —      —
 250   near_future         906     87     31       29      7
```

**A correction worth keeping**, because the first read of this probe got it
wrong and the wrong version is the more quotable one: *"research dies at year
60"* is **false**. `researchedTechs.count` saturates at the size of the tree —
a repeatable study stays in the set — so the count alone says "stopped" for a
colony still studying every tick. The `repeats` column is the honest one, and
it keeps climbing: twenty-nine completions over the 190 years after the tree
runs out, roughly one every six or seven years, slowing as the price grows at
1.35× a time. That cadence is *fine*. Do not flatten the curve.

What is worth fixing is what those studies **buy**, and one thing about the
ladder:

- **Research changed menus, never the valley.** Counted across `techs.json`
  before 2026-08-19: thirty-nine effects unlocked a building, five opened an
  event category, and every one of the ten `modifier` effects moved
  `knowledgeOutput` or `influenceOutput` — nine of the ten the former. So the
  reward for finishing a study was a new row in the build menu, or research
  that produces more research. Fixed by `ResearchStat`: four world-facing
  stats — crop yield, build speed, building wear, recovery — wired at the
  seams that decide them, and four endless studies that pay out in the valley.
- **The era ladder is a population ladder wearing three hats.** Every milestone
  has three parts — a tech, prosperity, a population. The techs are all done by
  year 60 and prosperity never drops below 81 against thresholds of 35…75, so
  **neither is ever the binding constraint**. Only population gates anything,
  and a three-part gate where two parts are always open is a one-part gate.

Re-run with `EF_PROBE=1 swift test --package-path Core --filter EraProbe`. It
takes about half an hour; the table prints as it goes.

- **`LivelinessProbe`** — still not built, and it is the probe that matches what
  the player actually complains about: what share of colonists are visibly doing
  something, per part of the day.
- **Re-run `DangerProbe` and `GrowthProbe`.** This session changed the line size
  (12 → 55% of the able-bodied), added building wear from weather and raids, and
  added gear wear. All three move balance and none has been measured since.
- **Release-build frame time** on a large colony at zoom 8.

---

## 6. Suggested order

1. **Batch one — what a player hits today**: on-screen culling instead of
   `prefix(30)`; catch-up progress; `GrowthProbe` + `DangerProbe` re-run to see
   what the last three sessions did; decide `floors`.
2. ~~**Batch two — sound.**~~ Done. What remains is a music track, which needs
   a licence rather than code.
3. **Batch three — the era ladder and the late game**, informed by (1)'s
   numbers: either bring the thresholds into reach or move what is behind them.
4. **Batch four — onboarding and saves.** First-run guidance that teaches by
   pointing at the world rather than by modal text; save slots and a backup.
5. **Batch five — Layer 3.** The narrator, with the offline path unchanged.

---

## 7. Traps this codebase has already paid for

Read [`RULES.md`](RULES.md) in full before writing a threshold. The four that
have bitten most often:

- **Rule 6** — check a threshold is reachable by the rate meant to cross it.
- **Rule 34** — a rate in the wrong unit is an arithmetic mistake, not a balance
  choice. Convert to what the player experiences before tuning.
- **Rule 35** — a number that must equal another number should *be* that number.
- **Rule 38** — a derived property used by a comparator is on the hottest path
  in the program; and a frozen UI is not always a stuck simulation. Sample the
  process before believing the symptom.

Two more that are cheap to forget: entities need **stable ids** or determinism
breaks silently (CLAUDE.md rule 3), and every line of content ships **CZ and EN
in the same change** — there is a test that walks all of `GameData` and fails
otherwise.
