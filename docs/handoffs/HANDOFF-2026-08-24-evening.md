# Handoff — 2026-08-24, evening

<!-- For a chat starting cold. Read CLAUDE.md, then docs/RULES.md, then this.
     The morning's is docs/HANDOFF-2026-08-24.md and its open list still
     stands except where §3 says otherwise. -->

| | |
|---|---|
| Last pushed | `fec46b1` (+ the animals commit this doc ships with) |
| Core | full sweep, 1500 tests in 211 suites |
| App | iOS build green |

## 1. What shipped

| commit | what |
|---|---|
| `5d93361` | timber a valley can spare (mills, carts that carry goods, a shopping list closed over recipe inputs); water with a depth |
| `fec46b1` | a tree is content (`flora.json`); the wild moves while you are looking at it |
| this one | a beast is content (`animals.json`) |

## 2. The pattern, now used three times

`ArmourProfile`, then `FloraDefinition`, then `AnimalDefinition`. It is worth
naming because the next one should follow it without rediscovering it:

1. **Derive what can be derived, declare only what cannot.** A tree's winter
   bareness and its cover both fall out of `crown`; a beast's meat, its
   retaliation and whether it is dangerous all fall out of `size` and `diet`.
   Eleven hand-written tables became two declared fields.
2. **The declared field is a closed set, and it is a piece of drawing that
   exists.** `Crown` has five cases and `Build` has eight because the canvas
   draws exactly that many silhouettes. A species names one and is a real thing
   on the day it ships; there is no fallback that quietly draws a bush.
3. **The entity carries its own numbers.** `Tree` holds `maturityTicks`,
   `timber`, `crown`; `Animal` holds `baseHealth`, `size`, `build`,
   `isPredator` and its comfort band. Copied from the definition when the thing
   is made, so `growth`, `meatYield` and `isPredator` stay pure functions read
   thousands of times a frame — no registry threaded through twenty signatures.
4. **The old enum is frozen, not deleted and not a second authority.**
   `LegacyTreeSpecies` and `LegacyAnimalSpecies` exist because saves carry
   `"species": "oak"` and no numbers, and `init(from:)` has no registry.
   Nothing is ever added to them: no save can hold a species that did not exist
   when it was written. A content test holds each against its JSON.
5. **Gate the content, in the same change.** Every species is checked for a
   drawable crown/build, a biome that will have it, a colour, and agreement
   with the frozen table. `Tools/generate.py` learned both kinds, and
   `NEEDS_SWIFT_FIRST` lost two of its four entries.

## 3. Open

1. **Interiors are still `switch glyph`** with 21 hard-coded `Fitting` cases,
   so a medieval workshop and a far-future assembly plant share crates. This is
   the next one in the same shape: `fittings.json` with an era range and a
   shape spec, then generate. Keks has asked for it twice.
2. **Nothing is selectable but pawns, buildings, animals and POIs.** Keks:
   *"ideálně jde vybrat na mapě a něco s tím dělat."* A tree can be tapped and
   named; flora otherwise cannot be marked, and there is nothing to *do* with a
   plant. Designations exist (`DesignationEngine`) and are the obvious hook.
3. **Water is honoured by the router and by nothing else.** Building placement,
   expeditions and the beasts still walk into the sea. `PathEngine.waterDepth`
   is the one function to call.
4. **`charcoal` and `iron_ingot` are a trickle, not a flow.** The chain is
   reachable — it was dead — but `saw_timber` and `burn_charcoal` compete for
   the same wood. Measure the sustainable yield before tuning either.
5. Everything from `docs/HANDOFF-2026-08-24.md` §"Open" that this did not
   touch: the settlement span not following the grid, `WalkRoutes` unprofiled
   against the 150 ms budget, herbs out-pulled ~8×, research running out at
   year 130.

## 4. How to measure

```bash
EF_SAVE=~/…/Documents/endless-frontier-world.json EF_YEARS=60 \
  swift test --package-path Core --filter ZZSaveDiag
swift test --package-path Core --filter "FloraContent|AnimalContent|WildMotion|DryLand"
python3 Tools/generate.py kinds
```

---

## 5. Added later the same evening: the rooms

`fittings.json` + `FittingDefinition` — the pattern in §2 for the **fourth**
time, and the one Keks had asked for twice.

Which fittings a building got was a `switch` over building shapes with **no
notion of when**, so a medieval workshop and a near-future assembly plant were
furnished from the same two lines and shared their crates. It is a query now:
*what belongs in this room, in this age.*

- **`shape`** is the drawable declaration — the 21 drawings that exist.
- **`eras` is the point.** A dated fitting **replaces** the timeless one of its
  shape, so a far-future workshop is not a museum of its own history.
- **`tint` and `scale`** keep two entries of one drawing from being the same
  object: a plank cot and a sprung bed are both `bed`.
- The age that furnishes a room is the **town's**, not the building's. A
  windmill raised in the age of bronze is still a windmill; the bench inside it
  belongs to the century the colony is living in.

90 fittings generated, 27 → 117. Measured: `workshop`, `granary`, `temple` and
`house` are all furnished differently in the medieval age and the near future.

Also: a tapped tree, seam or heap now says **what it is** — a line out of
`flora.json` / `animals.json` on the work-order card. Those descriptions were
content nothing read (rule 47).

### Three faults this turned up

1. **A generator kind needs a `wants` line as well as a `brief`.** Without it
   every batch dies on `KeyError: 'wants'` — so `flora` and `animals` were
   listed as generatable for a whole session and could not be generated.
   `kinds` hid the hole cheerfully.
2. **A free list of strings is not a vocabulary.** `eras` is `[String]`, so the
   model wrote `industrial` fourteen times: decodes, loads, belongs to an age
   no colony reaches. Closed via `SUPPLEMENTS_BY_KIND`.
3. **A derived query inside a per-frame loop is a rate that scales with
   content.** `fittings(inRoom:era:)` filtered and sorted the whole book per
   building per frame and cost `TribeCampTests` its 150 ms budget five times
   over. Worked out once at load instead (rule 38).

And one older latent flaw the new content exposed: `WearTests` picked its
sample with `items.values.first { … }` — an arbitrary entry out of a
dictionary — and eventually landed on a leather halter, worth zero fresh *and*
worn. Sorted, and picking something that can actually lose value.
