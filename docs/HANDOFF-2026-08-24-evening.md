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
