# The next phase — one world of entities, and it moves

Brief for the next working session. The goal in one line:

> **Everything in the world is the same kind of thing — a body with a life —
> and everything that happens to it is something you can watch happen.**

Half of that is built. This document says which half, what is left, and the
order I would build it in.

---

## 1. Where the line currently is

The project has been converting *abstractions* into *entities* one layer at a
time. Each conversion follows the same shape, and it is worth naming because
every remaining item is another instance of it:

> A number that describes a thing → the thing itself → the number derived from
> the things → the number deleted.

| Layer | Number | Entity | Economy reads | Drawn | Fully converted |
|---|---|---|---|---|---|
| Colonists | `population` | `Pawn` | ✅ | ✅ | ✅ **done** |
| Wood | `forest` node | `Tree` | ✅ | ✅ | ⚠️ node still exists as a view |
| Stone | `stone` node | `Rock` | ✅ | ✅ | ⚠️ node still exists as a view |
| Wild animals | `deerHerd` | `Animal` | ✅ (head count) | ✅ | ⚠️ `deerHerd` still drives yield |
| Buildings | `BuildingInstance.count` | `BuildingPlacement` | ❌ **counts** | ✅ | ❌ **not converted** |
| Events | — | `EventTemplate` | n/a | ❌ text only | ❌ **not embodied** |

**The three unconverted rows are this phase.**

---

## 2. What "not converted" means, concretely

### 2.1 Buildings are still a tally

`Settlement.buildings` is `[BuildingInstance(definitionID:count:)]` — a *count*.
`ColonyMap.placements` holds the real, placed, footprinted, staffed buildings,
and `ResourceLoop` reads **the count**, not the placements. The two are kept in
sync by hand in `ColonyBuilder.place` / `remove`.

Consequences that are visible in play:

- A building has no **condition**: nothing can be damaged, burn down, wear out
  or be repaired, because there is nothing per-building to damage. A raid that
  "loots the granary" changes a number somewhere else.
- Adjacency, staffing and upkeep all have to reach *around* the ledger.
- Two granaries are indistinguishable; one cannot be the old one that leaks.

**The conversion:** make `BuildingPlacement` the truth — give it `condition`,
`age`, its own stores — and derive `buildings` from `placements` the way
`Settlement.population` is derived from `pawns`. Then delete the ledger.

**Watch out:** `ResourceLoop`, `ColonyBonus`, `TechEngine`, `ConstructionEngine`,
`ExpansionEngine` and the balance harness all read `buildings`. Outposts founded
without a grid must keep working — derive a placement-less fallback, or lay a
grid out for every settlement at founding.

### 2.2 Not every animal is a pawn yet

`Animal` has a body, wounds, illness and a life. What it does **not** have:

- **A position of its own.** Positions are presentation-derived from `(id, clock)`,
  so animals cannot actually *be* anywhere — they cannot be found, tracked,
  cornered, or flee toward cover.
- **Behaviour.** No hunger, no grazing that depletes anything, no predation
  (wolves never eat deer), no fleeing.
- **Being hunted individually.** `deerHerd` still produces the food; the entities
  are culled to match it afterwards.
- **Domestication.** Nothing can be tamed, herded, or kept.

**The conversion:** give `Animal` a stored `position` and a tiny think-step
(graze → flee → hunt → rest), let hunters take *named* animals with `hunt`, and
retire `deerHerd` to a derived read-out.

**Watch out:** this puts an O(animals) movement step in the per-tick path. It
must go on a cadence like `JobBoard` (see §4).

### 2.3 Events are text, not things that happen

`StoryPlanner` picks an `EventTemplate`, `EffectApplier` mutates state, a line
lands in the journal. The player reads that something happened. Nothing is ever
*seen* happening except a raid (`SettlementBattle`) and, since this session, a
site find.

**The conversion:** an event gains an optional **staging** — where it happens on
the map, who is involved, and over how many ticks — so a fire is a fire *at the
mill*, a quarrel is two named colonists in the square, a caravan arrival is
figures on the road. `WorldClock`/`BattleLog` already prove the pattern for
raids; generalise it.

**Watch out:** the storyteller must stay narrator-agnostic and deterministic.
Staging is *data on the effect*, not a callback into the view.

---

## 3. What "alive and action-y" needs beyond the conversions

From playing it (2026-07-28) — the things that read as dead even where the
simulation is fine:

1. **The colony is a huddle.** Everyone converges on the centre; the town looks
   like a crowd around a well. Wants: work sites spread out, homes assigned per
   family, and colonists pathing *around* buildings instead of through them.
2. **Nothing has weight.** People arrive and things change; nothing is carried,
   dropped, stacked or hauled. A **haul job** (timber from the felled tree to the
   store) would do more for aliveness than any other single addition — it makes
   the map show its own logistics.
3. **Defence is invisible.** A beast attack picks the least-healthy colonist and
   wounds them. Nobody runs to the walls, nobody forms up, the garrison that now
   exists does nothing visible. Wants: defenders converge, a real clash at a
   place, casualties where they fell.
4. **Weather and time of day are cosmetic.** Night darkens the canvas but changes
   nothing; the seasonal day shape is presentation-only. Wants: night actually
   stops outdoor work, a storm actually interrupts.
5. **Battle visuals are placeholder.** Red blobs. Wants: figures, a line, a
   result you can read without the card.

---

## 4. Rules any of this must not break

These have all been violated at least once and cost a session each:

1. **Presentation never writes the simulation.** If the canvas needs to know
   something, the engine stores it and the canvas reads it.
2. **Determinism.** Seeds from stable ids. New RNG draws go at the *end* of a
   generation pass.
3. **Decode-if-present.** Every new field optional with a sane default.
4. **The per-tick path is replayed tens of thousands of times.** `OfflineCatchUpTests`
   asserts linearity and *will* fail. Anything O(entities) goes on a cadence —
   `LaborEngine.staffingInterval` and `JobBoard.interval` are both 10.
5. **`isEmpty` is not "has no layer".** See `usesEntityLand` / `usesEntities`.
   Every new entity layer needs the same flag or "all gone" reads as "never had".
6. **Check that a threshold is reachable by the rate meant to cross it.** Five
   bugs of this exact shape so far. Test reachability, not just behaviour.
7. **Content is data, CZ+EN, in the same change.**

---

## 5. Suggested order

Each step is shippable on its own and leaves the game better than it found it.

| # | Step | Why first | Size |
|---|---|---|---|
| 1 | **Haul jobs** — felled timber and quarried stone must be carried to a store | Biggest aliveness-per-line in the project; uses the job layer that already exists | S |
| 2 | **Animals get positions + a think-step** | Unblocks hunting-by-entity, predation and fleeing; makes the wild move on its own | M |
| 3 | **Retire `deerHerd`** — hunters take named animals | Completes the wildlife conversion | S |
| 4 | **Buildings become the truth** — condition, damage, repair; derive the ledger | Unlocks fire, decay, sabotage, "the old granary leaks" | L |
| 5 | **Staged events** — an event happens *somewhere*, to *someone*, over *ticks* | Turns the storyteller from text into theatre | M |
| 6 | **Defence you can watch** — garrison converges, real clash, casualties in place | The single loudest complaint from play | M |
| 7 | **Night and weather bite** — outdoor work stops, storms interrupt | Makes the day shape and the seasons mean something | S |

Elevation (`docs/NEXT_STEPS.md`) is deliberately *not* in this list — it is a
separate phase and would collide with steps 1–2 over pathing.

---

## 6. Starting points in the code

| Concern | File |
|---|---|
| Job posting and assignment | `Core/…/Models/Job.swift` |
| Tree/rock behaviour | `Core/…/Engine/FloraEngine.swift` |
| Animal life | `Core/…/Engine/AnimalEngine.swift` |
| Wildlife tick + herd bridge | `Core/…/Engine/WildlifeEngine.swift` |
| The building ledger to be replaced | `Core/…/Models/Settlement.swift` (`buildings`) |
| Placements — the intended truth | `Core/…/Models/ColonyMap.swift` |
| Per-tick economy | `Core/…/Engine/ResourceLoop.swift` |
| Storyteller | `Core/…/Storyteller/` |
| Sub-tick staging (the pattern to copy) | `Core/…/Models/WorldClock.swift`, `BattleLog` |
| Colonist motion | `App/…/Views/Settlement/AgentMotion.swift` |
| Battle drawing | `App/…/Views/Settlement/SettlementBattle.swift` |

Run tests: `cd Core && swift test` (no simulator needed).
Build the app: `xcodebuild -project App/EndlessFrontier.xcodeproj -scheme EndlessFrontier -destination 'platform=iOS Simulator,name=iPhone 17' test`
