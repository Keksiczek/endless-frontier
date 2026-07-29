# Handoff — 2026-07-29

Branch: `docs/rimworld-layer`, all pushed, **not merged to `main`**.
Tests: **741 Core**, **61 app** — green. Build green.

---

## 1. Read first

| For | Read |
|---|---|
| Everything asked for and its state | `docs/BACKLOG.md` |
| What the RimWorld-leaning layer *is* | `docs/RIMWORLD_LAYER.md` |
| Rules that must not break | `docs/BACKLOG.md` §"Rules", `CLAUDE.md` |

---

## 2. Where the game is now

Every complaint from the last two play sessions is closed. The shape of the
game today:

- **Everything alive is a pawn with a body.** Colonists and animals both carry
  named parts, wounds on those parts, illness and cold. A wound bleeds until
  somebody tends it; a ruined arm costs the colony work; a lost part never
  grows back.
- **Work happens at a place.** A logger fells *this* tree, a miner cuts *this*
  block of hillside, a hunter stalks *this* deer, and the timber and stone lie
  on the ground until somebody carries them in.
- **Buildings are rooms.** Floor, walls, a door, fittings, and the colonists
  the engine posted standing at them. Push the camera in, the roof lifts off.
  They weather, take damage by kind (raid, storm, fire, beast, quake), stop
  working when derelict, and masons repair them at a cost.
- **The colony is a place.** A house is a household with beds; the roofless
  sleep badly and say so. The town opens districts as it grows. Pulled back,
  people gather into group marks with headcounts.
- **The world beyond arrives.** Traders with mules, envoys with a standard,
  refugees — each puts a decision to you. Your own towns ship carts to each
  other and you can watch them leave.
- **Beasts can be tamed** and then haul, guard or keep company — and eat.

---

## 3. Fixed this session (from screenshots)

- **Animal animation stutter.** Was `time * urgency`; changing activity jumped
  the phase by (urgency − 1) × time. Clock is one rate now; urgency changes
  amplitude.
- **Animals stacking into one smeared beast.** Grazing targeted the herd
  centroid, so the herd converged. Each beast keeps its own `herdStation`
  offset, stable per id.
- **Animals were not tappable.** `CanvasSelection.animal(UUID)` +
  `AnimalInspectorCard` — species, health, what it is doing, its body part by
  part, and taming progress.
- **Pawn card too thin.** Now shows all six body parts always, top three
  trades, bed, carried load, equipment count.
- **Notifications invisible.** Settings shows the real
  `UNAuthorizationStatus` with a button that asks (not-determined) or opens iOS
  Settings (denied).

---

## 4. Known open — read before touching

1. **Notifications may still not arrive on device.** The code path is correct
   and the status is now visible. If Settings says *Refused*, that is an iOS
   record from an earlier build and only the user can undo it. Verify by
   checking the card before assuming a code bug.
2. **Old English content is untranslated** — events, buildings, techs from
   before `LocalizedText`. Everything new ships CZ+EN.
3. **`deerHerd` is a view now**, recomputed from live animals. Do not write to
   it; write animals.
4. **`SupplyEngine` sends one cart per resource per check** on purpose — the
   first version was O(settlements²) per check and broke
   `catchUpScalesLinearly`.

---

## 5. Next, in the order I would take it

1. **Ground light and shade** (`BACKLOG` 2.10). It still reads flat from a
   distance — the one remaining "it looks boring" complaint. Wants a low sun,
   long shadows off buildings and trees, and seasons that change the *land*
   (snow lying, spring mud) rather than only tinting it (2.11).
2. **More POIs and items** (3.7). Six place kinds is thin after a few hours.
3. **Manage by policy, not by pawn** (§4.5). At sixty souls nobody wants to
   click each colonist — trades, rosters and rations as standing rules.
4. **Merge to `main`.** This branch is a long way ahead and nothing here is
   experimental any more.

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
