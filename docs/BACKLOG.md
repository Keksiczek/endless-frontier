# Backlog — what Keks has asked for, in one place

Everything requested, kept here so nothing is lost between sessions. The
ordering inside each section is my recommendation, not a promise.

Last updated: 2026-07-28 (evening).

---

## 1. The RimWorld line — everything is a pawn, everything is a thing

| # | Thing | State |
|---|---|---|
| 1.1 | Colonists are pawns with genes, a body, a life | **done** |
| 1.2 | Animals are pawns: body parts, wounds, illness, cold | **done** |
| 1.3 | Animals have a **stored position** and a think-step | **done** |
| 1.4 | Hunters take **named animals**; `deerHerd` retired to a view | **done** |
| 1.5 | Buildings have an **inside** — floor, walls, fittings, stations | **done** |
| 1.6 | **Mineable rock**: a massif of stone blocks you dig into | **done** |
| 1.7 | Pawn **needs that bite**: hunger, rest, warmth | **done** |
| 1.8 | A house is a **household**; sleeping rough hurts | **done** |
| 1.9 | Buildings are the truth: condition, damage, repair | todo |
| 1.10 | **Haul jobs** — felled timber and cut stone carried to a store | todo |
| 1.11 | Animals you can **tame**, and beasts of burden | todo |
| 1.12 | Colonists carry **wounds by body part**, like animals already do | todo |

## 2. What it looks like

| # | Thing | State |
|---|---|---|
| 2.1 | The ground stops being a spreadsheet of vertical strips | **done** |
| 2.2 | Fog falls off in steps instead of a black staircase | **done** |
| 2.3 | Buildings drawn bigger, the town spread wider (span 0.42 → 0.52) | **done** |
| 2.4 | Roof lifts off as you zoom in | **done** |
| 2.5 | Animals sized against people instead of against the canvas | **done** |
| 2.6 | Colonists huddling in the middle of town | **done** (own beds) |
| 2.7 | Battle was three enormous red blobs | **done** |
| 2.8 | Weapons visible in the hand — bow drawn and loosed, blade swung | **done** |
| 2.9 | An app icon | todo |
| 2.10 | Ground still reads flat at a distance — wants light and shade | todo |
| 2.11 | Seasons should change the *land*, not just its tint (snow lying, mud) | todo |

## 3. The world beyond the valley

| # | Thing | State |
|---|---|---|
| 3.1 | **Supply** between your own settlements | todo |
| 3.2 | **Trade** you can watch — caravans as figures on the road | todo |
| 3.3 | **Diplomacy** arriving as envoys rather than as a panel | todo |
| 3.4 | More **events**, each happening *somewhere* to *someone* | todo |
| 3.5 | More **POIs** and more **items** | todo |

## 4. Scale — a colony of sixty-five must still be a place

1. **A house is a household.** — **done.** Four sleepers to a tile, never more
   than the ledger claims; the roofless sleep badly and say so.
2. **Home is a place, not a pool.** — **done.** `Pawn.homeID`, a bed apiece.
3. **Districts.** When the build grid fills, the colony spills into outlying
   clusters instead of packing tighter. — todo.
4. **Level of detail.** Past a threshold, distant figures draw as a group mark
   that resolves into people as you push in. — todo.
5. **Manage by policy, not by pawn.** Trades, rosters and rations as rules;
   the pawn screen is for *looking at someone*. — partly done (the screen is
   now worth looking at).

## 5. Housekeeping

- Notifications — **fixed**; still wants one real run on device to confirm the
  sheet appears and the digest does not fire while playing.
- The old English content (events, buildings, techs) is still untranslated;
  everything new ships CZ+EN in the same change.

---

## Rules any of this must not break

Every one of them has cost a session at least once:

1. **Presentation never writes the simulation.**
2. **Determinism** — seeds from stable ids; new RNG draws at the *end* of a
   generation pass, never inserted in the middle.
3. **Decode-if-present** — every new field optional with a sane default.
4. **The per-tick path is replayed tens of thousands of times.** Anything
   O(entities) goes on a cadence (`LaborEngine.staffingInterval`,
   `JobBoard.interval`, `AnimalEngine.thinkInterval`, all 10).
5. **`isEmpty` is not "has no layer"** — `usesEntityLand`, `usesEntities`,
   `StoneField.usesBlocks`.
6. **Check a threshold is reachable by the rate meant to cross it.** This has
   now bitten seven times; the newest was winter being unable to make anyone
   cold. Write a test named for the reachability, not for the behaviour.
7. **Content is data, CZ+EN, in the same change.**
8. **Two numbers that must agree live in one place** — `SettlementGeometry.span`
   and `SettlementRenderer.colonySpan` are one number in two files.
