# Handoff — 2026-08-01

Branch: **`main`**. PR #7 merged; `docs/rimworld-layer` is fully contained in
`origin/main` and can be deleted. Working tree clean.

Tests: **773 Core** and **83 app** — both green on `main` as of this handoff.
(`swift test --package-path Core` takes ~250 s; the app suite ~4 s once built.)

---

## 1. Read first

| For | Read |
|---|---|
| Everything asked for and its state | `docs/BACKLOG.md` |
| What the RimWorld-leaning layer *is* | `docs/RIMWORLD_LAYER.md` |
| Rules that must not break | `docs/BACKLOG.md` §"Rules" (ten of them), `CLAUDE.md` |

---

## 2. Where the game is

Every numbered item in `BACKLOG.md` §1 (the RimWorld line), §2 (what it looks
like), §4 (scale) and all of §3 except 3.6 is **done**. In one paragraph:

Every living thing is a pawn with a body, named parts, wounds and illness.
Work happens at a *place* — this tree, this block of hillside, this deer — and
what is cut lies on the ground until somebody hauls it in. Buildings are rooms
with floors, walls and posted workers; they weather, take damage by kind, and
masons repair them. A sun crosses the sky on the colonists' own clock and the
land is lit by it; snow lies in the hollows in winter and spring opens as mud.
Twelve kinds of place are worth walking to. The world beyond arrives as
traders, envoys and refugees you answer. And a town of sixty is run by
**standing orders** — trades, rations, roster — not by sixty taps.

---

## 3. Corrections to the previous handoff

The last handoff's "next" list was three items. **Two of them were already
done** and one was stale. Verified this session, so nobody re-does them:

| Previous claim | Actual state |
|---|---|
| "Old English content is untranslated — events, buildings, techs" | **False.** All 7 `GameData/*.json` files are fully bilingual: 0 missing `cs` across 461 localized strings, no `en == cs` duplicates, no Czech field without diacritics. |
| "Make the post pay — `ResourceLoop` produces from building *counts*, not from who is at the bench" | **Already done.** `ResourceLoop.staffingFactors` scales output by how well each building kind is manned, floored at `unstaffedFloor = 0.4`, and multiplies in building condition too. |
| `BACKLOG` 3.3: "refugees arrive; taking them in is still todo" | **Already done.** `VisitorEngine` queues the `visitors_refugees` template; its `take_them_in` choice costs 40 food and applies `add_pawn` twice plus a morale lift. Its `weight: 0` is deliberate — the visitor engine names the template directly instead of letting the storyteller draw it. |

Two things checked and found **healthy**, so they need no work:

- `EventTemplate.allows(era:)` is `era.isEmpty || era.contains(candidate)` —
  the 28 templates with `era: []` mean *all eras*, not *never*. Not an
  instance of the recurring unreachable-threshold bug.
- Event content is not thin: **71 templates**, 49 of them with player choices
  (26 opportunity, 25 disaster, 10 threat, 10 flavour).

---

## 4. What is actually left

Ordered by what I would do next.

### 4.1 The last untranslated surface is the **app UI**, not the content
~23 bare English string literals in SwiftUI views — the ones that never went
through `AppStrings` or `cs ? … : …`. Small, bounded, and it is the text a
Czech player reads most often. Find them with:

```bash
grep -rn 'Text("' App/Sources/Views --include=*.swift | grep -v 'cs ?' | grep -v AppStrings | grep -v 'resolve('
```

Known offenders: `ColonistsPanel` ("Mood", "Unequip"), `CouncilScreen`
("Gini"), `ItemsPanel` ("Material", the empty-state sentence).

### 4.2 `BACKLOG` 3.6 — events that happen *somewhere*, to *someone*
The only item in §3 still open, and the phrasing matters: there are plenty of
events, but 40 of 71 never name a building, a place or a colonist. An event
that says "a fire" is weaker than one that says *which* workshop burned and
*who* was inside it. Now that there are twelve POI kinds, named buildings with
condition, and pawns with bodies, the hooks all exist.

### 4.3 Standing orders should have consequences the player can see
`ColonyPolicy` is new and nothing reports on it. Candidates: a chronicle
insight when a policy visibly reshaped the colony ("the decade we became a
mining town"), and a warning when an order is doing harm — famine rations held
for years, or a trade set to `.off` that the colony needs.

### 4.4 Housekeeping
- Delete the merged `docs/rimworld-layer` branch (local and remote).
- Notifications may still not arrive on device; the permission state is
  visible in Settings and only the user can undo an iOS *Refused*.

---

## 5. Traps this codebase has already sprung

Full list in `BACKLOG.md` §"Rules". The three newest, all from the sun-and-
seasons work, because they are the least obvious:

1. **Rule 9 — never lay a translucent layer over the ground tiles.** Tiles are
   drawn a hair larger than their cell so no seam shows. Harmless under an
   opaque fill; under a see-through one the overlap blends twice and paints a
   bright line along every tile edge. Resolve cover, season skin and light band
   into one colour (`SettlementGround.Tone`) and fill it solid.
2. **Rule 10 — a one-tile-wide cell is against both side borders.** On a phone
   `subX` is 1, so a dither that only borrows from an edge it is strictly on
   borrows vertically alone. The land was drawn as vertical stripes for as long
   as there was land.
3. **Rule 9c — an order must reach a town that is already full.** The labour
   assigner only touches the idle, so a policy alone changes nothing in any
   colony past its first decade. `LaborEngine.rebalance` is the slow hand.

Plus: `GameDataRegistry.bundled()` loads items with `try?`, so **one**
malformed effect anywhere in `items.json` silently empties the whole table.
`colony_production` takes `perTick`, not `amount`. Guarded by a test.

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
