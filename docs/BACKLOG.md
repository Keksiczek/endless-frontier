# Backlog — what Keks has asked for, in one place

Everything requested that is not yet built, kept here so nothing is lost between
sessions. Ticked items link to the commit that closed them. The ordering inside
each section is my recommendation, not a promise.

Last updated: 2026-07-28.

---

## 1. The RimWorld line — everything is a pawn, everything is a thing

| # | Thing | State |
|---|---|---|
| 1.1 | Colonists are pawns with genes, a body, a life | **done** |
| 1.2 | Animals are pawns: body parts, wounds, illness, cold | **done** (model) |
| 1.3 | Animals have a **stored position** and a think-step (graze → flee → hunt) | todo |
| 1.4 | Hunters take **named animals**; retire `deerHerd` | todo |
| 1.5 | Buildings have an **inside** — floor, walls, fittings, workers at stations | **done** |
| 1.6 | Buildings are the truth: condition, damage, repair; derive the ledger | todo |
| 1.7 | **Mineable rock**: a massif of stone blocks you dig into, RimWorld-style | todo |
| 1.8 | Haul jobs — felled timber and cut stone carried to a store | todo |
| 1.9 | Pawn **needs that bite**: hunger, rest, warmth; visible and consequential | todo |

## 2. What it looks like

| # | Thing | State |
|---|---|---|
| 2.1 | The ground stops being a spreadsheet of vertical strips | **done** |
| 2.2 | Fog falls off in steps instead of standing as a black staircase | **done** |
| 2.3 | Buildings drawn **bigger**, the town spread wider (span 0.42 → 0.52) | **done** |
| 2.4 | Roof lifts off as you zoom in | **done** |
| 2.5 | Animals are drawn far too large next to people | todo |
| 2.6 | Colonists huddle in the middle of town | part done (wider span) |
| 2.7 | Battle is three enormous red blobs | todo |
| 2.8 | Buildings read as abstract icons rather than places | part done (interiors) |
| 2.9 | An app icon | todo |

## 3. Live combat

Asked for explicitly. Wanted:

- Raiders **advance as figures**, not a scatter of dots.
- The garrison **converges** — the walls and barracks that exist do something
  you can watch.
- A **clash at a place**, with a line that holds or breaks.
- **Casualties where they fell**, and a body that stays a moment.
- `"A beast"` in the battle card is untranslated English in a Czech UI.

## 4. The world beyond the valley

| # | Thing | State |
|---|---|---|
| 4.1 | **Supply** between your own settlements | todo |
| 4.2 | **Trade** you can watch — caravans as figures on the road | todo |
| 4.3 | **Diplomacy** arriving as envoys rather than as a panel | todo |
| 4.4 | More **events**, each happening *somewhere* to *someone* | todo |
| 4.5 | More **POIs** and more **items** | todo |

## 5. Scale — a colony of sixty-five must still be a place

The complaint, from play: at sixty-five souls the town is a *crowd*. Houses take
many colonists each, so the settlement stops growing outward as it grows in
population; everyone ends up stacked on the same few lots and nothing can be
told apart or managed. But the colony must still be able to expand and keep
itself running — thinning the crowd must not mean capping the game.

The shape of the fix, in the order I would take it:

1. **A house is a household.** Cap what one dwelling holds at something human
   (4–6), so doubling the population *doubles the roofs*. The town then spreads
   as a real town does, and the crowd thins because it has somewhere to go.
2. **Home is a place, not a pool.** Each colonist belongs to one dwelling —
   drawn there at night, hungry at its hearth — rather than picking any house
   from a list each frame.
3. **Districts.** When the build grid fills, the colony spills into outlying
   clusters with their own little squares, instead of packing tighter.
4. **Level of detail.** Past a threshold, distant figures draw as a group mark
   rather than as individuals; push the camera in and the group resolves into
   the people it is made of.
5. **Manage by policy, not by pawn.** At sixty-five nobody wants to click each
   colonist. Trades, rosters and rations are set as rules; the pawn screen is
   for *looking at someone*, not for running them.

## 6. Housekeeping

- Notifications have never fired once on device — permission is asked while the
  app is backgrounding, where the prompt cannot be shown, and scheduling is
  gated on an authorization that is therefore still `notDetermined`.
- The old English content (events, buildings, techs) is still untranslated;
  everything new ships CZ+EN in the same change.

---

## Rules any of this must not break

Repeated from `docs/NEXT_PHASE.md` §4 because every one of them has cost a
session at least once:

1. **Presentation never writes the simulation.**
2. **Determinism** — seeds from stable ids; new RNG draws at the *end* of a
   generation pass.
3. **Decode-if-present** — every new field optional with a sane default.
4. **The per-tick path is replayed tens of thousands of times.** Anything
   O(entities) goes on a cadence (`LaborEngine.staffingInterval`,
   `JobBoard.interval`, both 10).
5. **`isEmpty` is not "has no layer"** — see `usesEntityLand` / `usesEntities`.
6. **Check a threshold is reachable by the rate meant to cross it.**
7. **Content is data, CZ+EN, in the same change.**
