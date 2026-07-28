# Handoff — 2026-07-28 (evening)

Branch: `docs/rimworld-layer`, everything pushed, **not yet merged to `main`**.
Tests: **654 Core**, **52 app** — all green.

---

## 1. Read this first

| For | Read |
|---|---|
| Everything asked for and its state | `docs/BACKLOG.md` |
| What the RimWorld-leaning layer *is* | `docs/RIMWORLD_LAYER.md` |
| Rules that must not be broken | `docs/BACKLOG.md` §"Rules", `CLAUDE.md` |

---

## 2. What changed this session

Seven blocks, each committed on its own.

### The roof comes off
`SettlementInterior` — a building is a room: floor, walls with a door, and
fittings that say what it is for. Every fitting somebody uses is a **station**,
and the engine's own roster decides who stands at which. Push the camera in and
the roof fades off; pull back and it is a town of roofs again. The build grid
widened to 0.52 (in the Core too — `SettlementGeometry.span` and
`SettlementRenderer.colonySpan` are one number in two files).

### The earth stops being a bar chart
`SettlementGround` — the ground was the fog grid painted in, and on a phone
that grid is three times taller than wide, so every meadow was a green column.
It now has its own square grain, dovetailing edges, per-tile shade and surface
texture. Fog falls off in three bands instead of one flat black.

### A raid you watch people go to
`BattleLog` carries the staging: how many came, from which bearing, and **who
turned out**. The mustered pawns stop living their day and run to their post
from wherever they were. Raiders form up opposite; arrows go out on a volley;
whoever falls falls at their own place in the line.

### The wild walks its own valley
`Animal.position` + `AnimalEngine.roam` (cadence 10). `HuntEngine` makes the
hunt an encounter: a bow kills from cover, a spear means closing with it and a
boar that survives will gore you. A kill is a carcass — meat and a hide.
`deerHerd` is now a *view* recomputed from the beasts standing on the map.

### A mountain you dig into
`StoneField` + `StoneEngine` — solid rock in blocks, worked at the **face**,
never grows back, blocks building until it is mined. Raised clear of the
colony's founding ground. Drawn as blocks with a lit top and a cliff outline.

### Everyone gets a bed
`HouseholdEngine` + `Pawn.homeID` — a colonist holds one dwelling; a house
sleeps four to a tile. The roofless get half a night's rest and −8 mood until
somebody builds another house. Colonists shrunk to 0.82 so a household fits in
its own room.

### Winter bites, and people can say why
`ComfortEngine` — a warmth need, fed by season, roof, clothes and the colony's
fires. Exposure costs health. `MoodLedger` recomputes mood as a list of reasons,
and the colonist screen leads with four need bars and **why** they feel that
way.

### Notifications that can arrive
The permission sheet was asked for while backgrounding, where iOS will not show
it, so nothing was ever queued. Both the ask and the arming happen in the
foreground now.

---

## 3. Done vs. built-but-not-verified

| Thing | State |
|---|---|
| Interiors, stations, roof fade | **done and seen running** |
| Ground grain, fog bands | **done and seen running** |
| Households, beds, rough sleeping | **done, wants a play at 60+ souls** |
| Warmth and exposure | **done, wants a winter watched** |
| Mineable stone | **wired, never seen on screen** — needs a mountain map |
| Live combat | **wired, never seen fire** — needs a raid |
| Hunt as an encounter | **wired**, but no *visual* of the kill yet |
| Notifications | **fixed, never verified on device** |

---

## 4. Where I would go next

1. **Haul jobs.** Felled timber and cut stone are goods that appear in a ledger;
   they should be piles somebody carries. It is the last big hole in "work is a
   thing done at a place".
2. **Supply, trade, diplomacy you can watch** — caravans as figures, envoys
   arriving. The whole world map is still a panel.
3. **Districts + crowd LOD** — the remaining half of scale (`BACKLOG` §4.3–4.4).
4. **Buildings as the truth** — condition, damage, repair.
5. **An app icon.**

---

## 5. Commands

```bash
swift test --package-path Core
```

```bash
cd App && xcodegen generate
```

```bash
xcodebuild -project App/EndlessFrontier.xcodeproj -scheme EndlessFrontier -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Installed simulators are iPhone 17 / 17 Pro / 17 Pro Max / Air / 16e — not
iPhone 16.
