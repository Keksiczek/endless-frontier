# Backlog — what Keks has asked for, in one place

Everything requested, kept here so nothing is lost between sessions. The
ordering inside each section is my recommendation, not a promise.

Last updated: 2026-07-29.

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
| 1.9 | **Haul jobs** — felled timber and cut stone carried to a store | **done** |
| 1.10 | Buildings are the truth: condition, damage, repair | **done** |
| 1.11 | Animals you can **tame**, and beasts of burden | **done** |
| 1.12 | Colonists carry **wounds by body part**, like animals already do | **done** |

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
| 2.9 | An app icon | **done** |
| 2.10 | Ground still reads flat at a distance — wants light and shade | **done** |
| 2.11 | Seasons should change the *land*, not just its tint (snow lying, mud) | **done** |

## 3. The world beyond the valley

| # | Thing | State |
|---|---|---|
| 3.1 | **Trade** you can watch — traders with mules walking in | **done** |
| 3.2 | **Diplomacy** arriving as envoys rather than as a panel | **done** |
| 3.3 | Refugees from a neighbour's bad winter | **done** (they arrive; taking them in is still todo) |
| 3.4 | **Supply** between your own settlements — a caravan you can see leave | **done** |
| 3.5 | A visit the player can **answer** — accept the refugees, refuse the envoy | **done** |
| 3.6 | More **events**, each happening *somewhere* to *someone* | part done (3 disasters, 3 visits) |
| 3.7 | More **POIs** and more **items** | **done** (6 kinds → 12, 57 items → 71) |

## 4. Scale — a colony of sixty-five must still be a place

1. **A house is a household.** — **done.** Four sleepers to a tile, never more
   than the ledger claims; the roofless sleep badly and say so.
2. **Home is a place, not a pool.** — **done.** `Pawn.homeID`, a bed apiece.
3. **Districts.** — **done.** The colony fills its heart, opens a second
   quarter, fills that; a building whose quarter is full goes to the next one.
4. **Level of detail.** — **done.** Below zoom 1.5, people standing together
   draw as one group mark with a headcount and the commonest trade's colour.
5. **Manage by policy, not by pawn.** — **done.** `ColonyPolicy` on the
   settlement, set from *Standing orders* on the Council screen: a weight per
   trade (`.off` … `.priority`), the ration on the table, and whether an
   expedition may take hands off the trades you said matter. `LaborEngine`
   scales its own quotas by the weights and **renormalises** them — an
   unnormalised `.priority` means "only", and swallows the whole town.
   `LaborEngine.rebalance` moves one colonist per staffing pass, so a policy
   set on a town of sixty actually reaches it instead of waiting for sixty
   people to fall idle.

## 5. Housekeeping

- Notifications — permission state is now **visible and settable** in Settings.
  If it says *Refused*, that is an iOS record only the user can undo.
- Animals: stutter, stacking and un-tappability all fixed 2026-07-29.
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
9. **Ground tiles overlap by a hair, so every layer over them must be opaque.**
   The overlap hides seams under an opaque fill and *doubles* under a
   translucent one, so a see-through snow or light sheet paints a bright line
   along every tile edge and the whole valley turns into brickwork. Resolve
   cover, season skin and light band into one colour and fill it solid —
   `SettlementGround.Tone`.
9b. **`GameDataRegistry.bundled()` loads items with `try?`.** One malformed
   effect anywhere in `items.json` silently empties the *entire* table — no
   loot, no equipment, no error. `colony_production` takes `perTick`, not
   `amount`. Guarded by "A single bad item cannot silently empty the whole
   table".
9c. **A standing order has to *reach* a town that is already full.** The
   assigner only ever touches the idle — rightly, or it would undo the
   player's own choices — so a policy alone changes nothing in a colony where
   nobody is idle, which is every colony past its first decade. `rebalance`
   is the slow hand that makes the rule bite. Same shape as rule 6: a lever
   whose effect cannot reach the thing it is aimed at.
10. **A cell one tile wide is against both its side borders.** With the fog grid
   three times taller than it is wide, `subX` comes out as 1 and a dither that
   only borrows from an edge it is strictly on borrows vertically alone — which
   drew the valley as vertical stripes for as long as the ground has existed.
