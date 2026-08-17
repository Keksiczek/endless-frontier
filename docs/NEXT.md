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
96 view files, 1145 Core tests.** Content: 49 buildings, 31 techs, 72 events, 76
items, 29 recipes, 7 quests — all bilingual CZ/EN, guarded by a test.

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

### 2.1 A town past thirty buildings is half-drawn — `maxVisibleBuildings = 30`

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

### 2.2 Opening after a long absence looks like a hang

Catch-up simulates up to 30 days off the main actor and shows a spinner with no
progress, no estimate, and no way out. In a debug build a multi-day absence is
**minutes**. The player cannot tell it from a freeze — and until §11.36 it
partly *was* one. Wants: a progress figure (ticks done / total), the years
counting up as they pass, and a cap the player can understand ("a month is as
far as the world runs without you").

### 2.3 Storeys exist in the drawing and not in the data

`floors` is drawn now, but only `apartment_block` (5) and `arcology` (12) carry
it, so every building a player sees for the first two hundred years is one
storey. Raising it on a hut is **not** a drawing change: `sleepers = footprint ×
2 × floors`, so a longhouse with a loft sleeps twice as many and the growth
curve moves. Decide deliberately: either give `floors` to the buildings that
plainly have them and re-run `GrowthProbe`, or split "drawn storeys" from
"storeys that hold beds" and accept two numbers for two different things.

### 2.4 The era ladder is probably unreachable, and nobody has measured it

`eras.json` asks for population **18 → 45 → 110 → 260 → 600**. The colony sits
at 67 in year 40 of a real save. 260 and 600 are the shape rule 6 keeps
catching: a threshold nobody checked against the rate meant to cross it. Measure
with `GrowthProbe` over 200 years *before* writing any content for the late
eras. If they are out of reach, that is the whole late game sitting behind a
door that does not open.

### 2.5 The world is silent

No `AVFoundation` anywhere. Wind, rain, a hammer, a bell at midday, a horn when
a raid comes. This is the cheapest large gain in perceived quality in the
project, and it is the oldest open ask (§11.30).

---

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
| Onboarding | none — a new player is dropped into a village with a build bar | high |
| Accessibility | 21 files carry labels; the canvas itself is unlabelled to VoiceOver | medium |
| Saves | one file, no slots, no backup, no export; a bad write is unrecoverable | medium |
| Haptics | none | low |
| App icon | one 1024 png, present | done |
| Release profiling | never done; all timings so far are debug builds | high before ship |

A save backup is cheap and worth doing before anything that touches
`WorldState`: write to a temp file, keep the previous as `.bak`, fall back on a
decode failure.

---

## 5. Measurement, before more content

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
2. **Batch two — sound.** Ambience per season and time of day, a handful of
   event stings, a volume control in Settings. Offline assets only.
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
