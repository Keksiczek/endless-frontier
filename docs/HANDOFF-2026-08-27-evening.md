# Handoff — 2026-08-27, evening

The five jobs in `HANDOFF-2026-08-27.md` are done. Two of them were not the jobs
they looked like, and that is the useful part of this note: **the last three
sessions in a row have started with a plan a probe then disproved.** Budget for
the measurement before the fix.

**Read first:** `CLAUDE.md`, then `docs/RULES.md` (102 rules — 99 to 102 are
this session's), then `docs/BACKLOG.md` §20.

**Test commands.** Core: `cd Core && swift test` — **1604 tests in 224 suites,
~18 min**. App: `cd App && xcodegen generate` after adding a file, then
`xcodebuild -project App/EndlessFrontier.xcodeproj -scheme EndlessFrontier -destination 'platform=iOS Simulator,name=iPhone 17' test`
— **202 tests in 32 suites**. Both green on `main`.

---

## What this session did, in one line each

1. **A colonist's own history.** The plan (set `subject` on sixty more journal
   calls) was aimed at the wrong half: 113–125 of the 140 entries a journal
   holds already name somebody. The ring is what fails — it spans **1.0 in-game
   years at year 200**, four fifths of it chatter. `Pawn.keepsakes` carries the
   dozen moments a life is made of; `Settlement.note` is the one door.
2. **The recipe book was already tiered.** Ungated arms run damage 1–14 with a
   p75 of 4; the bands read off the gated half put them where they sit. Five
   recipes were genuinely wrong (chainmail from two ingots with no bench and no
   study). Three `ContentTests` guards. The list folds to **one row per thing**
   — 240 of 420 recipes make something another already makes.
3. **The renderer, in eight files** (2822 → 402 + seven), same 64 members.
4. **The iron half.** Wanted from year 130, makeable from 160, **never made** —
   the council's eight bench slots were full of standing orders from year 60 and
   a standing order never finishes. It can retire its own now, never the
   player's. Steel, machine parts and resin exist for the first time.
5. **The header.** The year's annotation has its own line, and the clock line is
   a `ViewThatFits` — at midday it was wrapping and orphaning "83 resting".

---

## Five jobs, in the order I would do them

### 1. The workshop avalanche — the real "crafting is too big"

**Measured, not guessed.** 212 of the 420 recipes are makeable in the first age,
and 120 more arrive **the day the workshop goes up** — because `workshop` is a
*medieval* building and **98 of its 123 recipes are first-age crafts**: bone
chisels, grass hats, hide caps, stone-tipped spears. There is no general
crafting bench before the medieval era at all; early crafting happens at the
`hut`.

Gating cannot fix this and §20.2 says why: by the time the workshop exists the
early techs are two ages old, so gating a bone chisel on `basic_tools` changes
nothing. The fix is that a recipe sits at the bench **its own age has**. Two
shapes, and the choice is a design call:

- an early general bench (a lean-to, a work yard) at `early_settlement`, and the
  98 move to it; or
- the 98 re-homed to the benches that already exist — hut, hunters_lodge,
  cookhouse, lumberyard — by what they are made of.

Either moves a third of the book, so **measure either side of it** (rule 72):
count recipes-available-per-age before and after, and check nothing that was
craftable becomes unreachable (`ContentTests` has the invariant for that now).

### 2. The mine — where the shortage went

The iron chain runs now and the constraint moved down to the ground:
`iron_ore` falls from **309 at year 90 to 1 at year 200** against seventeen
miners, and both `Smelt Steel Ingot` and `Cast machine parts` end the run short
of `iron_ingot`. That may be right — a resource to manage — or the mine may
simply not scale. `WoodProbe` has the columns; nobody has read them against what
a mine *can* yield. Print the distribution first (rules 23, 90).

### 3. `GameViewModel.swift`, 2415 lines — and why it was left

Splitting a class across files puts its methods in extensions, and `world` is
`private(set)` — which in Swift is **file** scope for the setter. Every mutating
method that moved out would force that setter to internal, and that one modifier
is what keeps a view from writing the simulation (rule 1). A line count is not
worth it.

The way through is to lift genuinely separate *types* out: the recipe list is
already a pure derivation over `(registry, settlement)` and could be a
`CraftingList` the way `SettlementRenderer` is an enum of pure functions.
`SettlementRendererScenery.drawProp` (444 lines) is the same kind of job.

### 4. Nineteen recipes that can never be chosen

Counted while measuring §20.3: 19 recipes are **strictly dominated** — a cheaper
route to the same item arrives an age earlier. The fold makes them harmless in
the panel; whether to delete them, or to make them the *good* route at their own
age, is a content decision nobody has made.

### 5. Accessibility, still untouched

From §16.5: the canvas is unlabelled to VoiceOver, Dynamic Type is ignored by 33
fixed `.font(.system(size:))` calls, and `preferredColorScheme(.dark)` is
hard-wired in `EndlessFrontierApp`.

---

## Things that are done — do not rebuild them

Everything in the previous handoff's list, plus:

- **A colonist's keepsakes.** `Pawn.keepsakes` (12, dies with them),
  `Settlement.note` as the single door, `ColonyLog.append` no longer public,
  `GameViewModel.history(of:)` unions the ring and the keepsakes.
- **The recipe guards.** `ContentTests` now holds "nothing is gated later than
  something that needs it", plus damage and armour-material bands.
- **One row per thing** in the crafting panel, with a `2 ways` note. A search is
  deliberately not folded.
- **The renderer split** — eight files, extensions on the same enum.
- **`CraftOrder.byCouncil`** and `StewardEngine.orderToRetire`, with the
  `SaveMigrator` 5→6 step that goes with them.
- **`MemoryProbe`**, and `WoodProbe`'s iron half.

Two greps that find this project's most repeated bug — a system the simulation
has and the player cannot see — are in `docs/RULES.md` rule 93.
