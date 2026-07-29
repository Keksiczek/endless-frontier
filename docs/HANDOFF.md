# Handoff — 2026-07-29 (evening)

Branch: `docs/rimworld-layer`, all pushed, **not merged to `main`**.
Tests: **773 Core**, **83 app** — green. Build green.

---

## 1. Read first

| For | Read |
|---|---|
| Everything asked for and its state | `docs/BACKLOG.md` |
| What the RimWorld-leaning layer *is* | `docs/RIMWORLD_LAYER.md` |
| Rules that must not break | `docs/BACKLOG.md` §"Rules" (now ten), `CLAUDE.md` |

---

## 2. Done this session — the whole of the previous handoff's list

**§2.10 Light and shade.** There is a sun now. It rises, crosses and sets on
the same clock the colonists keep, and one value — `SettlementLight.sun(time:)`
— is read by everything that casts, shades or warms, so the valley is lit from
one place. A slow relief field the simulation knows nothing about gives the
land shape; buildings, trees and rock throw shadows along the sun's line, long
at dawn, tucked under at noon.

**§2.11 Seasons on the land.** Snow *lies* rather than tinting: hollows fill
first, ridges stay scoured, deep by midwinter and still deep at its end. Spring
opens as mud and standing meltwater and dries out of it. Autumn drops leaves
under the woods that dropped them. High summer burns the ridges off.

**§3.7 More places, more things.** Six POI kinds → twelve. A wild orchard, a
hermit who teaches the party rather than paying the colony, a watchtower that
pays in *map*, a salt pan, a burial mound that costs morale to open, and a
fallen star. Fourteen new items, CZ+EN. A map draws 4–7 of 12 rather than
3–5 of 6.

**§4.5 Manage by policy.** `ColonyPolicy` on the settlement, set from *Standing
orders* on the Council screen: a weight per trade, the ration on the table, and
whether an expedition may take hands off the trades you said matter.

---

## 3. Three traps this session walked into — all now backlog rules

1. **Rule 9 — translucent layers over overlapping tiles.** Ground tiles are
   drawn a hair larger than their cell so no seam shows. Harmless under an
   opaque fill; under a *see-through* one the overlap blends twice and paints a
   bright line along every tile edge. The first light-and-snow build turned the
   whole valley into brickwork. Cover, season skin and light band resolve into
   one colour now (`SettlementGround.Tone`) and every fill is solid.
2. **Rule 10 — a one-tile-wide cell is against both side borders.** On a phone
   the fog grid is three times taller than wide, `subX` is 1, and the cover
   dither borrowed vertically only. The land has been drawn as vertical stripes
   for as long as there has been land.
3. **Rule 9c — an order must reach a town that is already full.** The labour
   assigner only touches the idle, so a policy alone changed nothing in any
   colony past its first decade. `LaborEngine.rebalance` is the slow hand.

Also: `GameDataRegistry.bundled()` loads items with `try?`, so **one** bad
effect anywhere in `items.json` silently empties the entire table. There is a
tripwire test for it now. (`colony_production` takes `perTick`, not `amount`.)

---

## 4. Known open

1. **Notifications may still not arrive on device.** The code path is correct
   and the status is visible in Settings. If it says *Refused*, that is an iOS
   record only the user can undo.
2. **Old English content is untranslated** — events, buildings, techs from
   before `LocalizedText`. Everything new ships CZ+EN.
3. **`deerHerd` is a view**, recomputed from live animals. Write animals.
4. **`SupplyEngine` sends one cart per resource per check** on purpose.

---

## 5. Next, in the order I would take it

1. **Merge to `main`.** This branch is a long way ahead and nothing on it is
   experimental any more. This is the top item now that the backlog's visual
   and scale sections are closed.
2. **Translate the old content.** Events, buildings and techs are the last
   English-only surface, and it is the one the player reads most.
3. **Make the post pay.** `ResourceLoop` still produces from building *counts*,
   not from who is stood at the bench (`LaborEngine.staffBuildings` note). The
   standing orders make this matter: telling a colony to prioritise mining
   should change what comes out of the ground, and right now it changes who is
   standing where.
4. **More events** (`BACKLOG` 3.6) — three disasters and three visits is thin
   against twelve kinds of place.

---

## 6. Commands

```bash
swift test --package-path Core
```

```bash
cd App && xcodegen generate
```

```bash
xcodebuild -project App/EndlessFrontier.xcodeproj -scheme EndlessFrontier -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Installed simulators: iPhone 17 / 17 Pro / 17 Pro Max / Air / 16e. Not iPhone 16.

Regenerate the Xcode project after adding any file under `App/Sources`.
