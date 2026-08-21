# Handoff — the generation and wiring session

<!-- Written 2026-08-19, at the end of the session that closed steps 1–5 of
     MOUNTS_AND_VEHICLES.md. Pick this up cold. -->

Read `CLAUDE.md`, then `docs/RULES.md` (56 rules), then this. Everything below
is measured, not remembered — re-measure before trusting a number.

## The one lesson this whole session was about

**Content that loads perfectly and that nothing ever reaches.** It happened
seven times in two days, in seven different systems, and it is the thing to
watch for in every task below:

- 17 of 48 motion clips had never been drawn (the selector stopped at `.first`)
- `texture` in `ground.json` was validated, generated, and read by nothing
- 23 materials nothing made and nothing spent
- 135 pieces of gear obtainable only from a ruin
- research moved two numbers, both of them "more research"
- arrivals rolled a die while the world map knew exactly where everyone was
- every fight ran the same 24 steps whatever its size

Rules 47–56 are these. **Before adding content to a bank, ask what reads that
bank, and whether the reader can reach past the first row.**

## Where things stand

| | |
|---|---|
| Core tests | 1211+ in 159+ suites, green |
| App tests | 146 in 22 suites, green |
| Last commit | `e85e513`, pushed |
| Uncommitted | conveyance steps 3–5, volley fix, variable siege length |

Content: 306 recipes, 306 items, 83 motions, 20 grounds, 152 events, 49
buildings, 37 techs, 3 conveyances.

## What can be generated right now

Run `Tools/generate.py` — see `Tools/README.md`. Vertex, no API key,
`gcloud auth login` is the whole setup. Flash for volume, Pro where the *shape*
is harder than the prose. **Three checks stand between a model and `GameData`**
and all three have caught something real; do not bypass them.

The loop that works, and that closed the last two gaps, is in
`/private/tmp/.../scratchpad/wire.py` and `gear.py`: recompute what is *still*
missing each round, counting drafts already collected, so the model is never
asked twice and a run that dies halfway keeps its work. Copy that shape.

### 1. Motions for the twelve staffed buildings that have none

`farm_basic`, `farm_advanced`, `hunters_lodge`, `cookhouse`, `palisade`,
`stone_walls`, `watchtower`, `barracks`, `aqueduct`, `hospital`, `clinic`,
`arcology`.

`serves_buildings` outranks the trade, so this is what stops a farmer at a farm
and a farmer at a lodge being the same person twice. Pure content; the selector
is built and tested (`everyClipIsSelectable`).

### 2. Events for the late eras

`modern` 71, `near_future` 61, against `ancient` 123. `EraProbe` proved the
ladder is fully reachable — last era in year 225 of 250, nothing behind glass —
so late content is worth writing. Re-run it with
`EF_PROBE=1 swift test --package-path Core --filter EraProbe` (~30 min, prints
as it goes).

### 3. Biomes

Six today. `MapGenerator` reads them from the file, so a seventh is pure
content. Each new one needs a row in `LocalTerrain.weights(for:)` and
`sceneryMix(for:)` — Swift, but two lines.

## What must NOT be generated yet

**Conveyances.** Three in the bank and four eras empty, but step 6 — the
parametric drawing — has to exist first. Generating sixty now produces sixty
things that look like four. That is the motion bank again, one layer up.

**Horse tack.** Seventeen pieces already sit in `items.json` with no recipe,
waiting on mounts. Giving them recipes today makes things nobody can use.

**Anything into a bank whose reader you have not checked.**

## What needs Swift, not JSON

**19 buildings share a drawing.** `factory`, `vehicle_works`, `assembly_plant`
and `automated_factory` are one picture; so are `library`, `school`,
`university`. `look` maps to a `case` in `SettlementRenderer.BuildingGlyph`, so
a new drawing is Swift. Keks's standing rule is that every thing must be unique
and do something — this is that rule already broken 19 times, and new content
will only widen it.

The fix that scales is **parametric, not sprites**: `SettlementStructures`
already composes buildings from a shape table + era materials + a seed. Do the
same for conveyances (wheels / what draws it / what it carries / how it is
covered) so uniqueness comes from composition. Sixty hand-drawn vehicles is not
a plan.

## The design already written down

- `docs/MOUNTS_AND_VEHICLES.md` — steps 1–5 done, 6 (drawing) and 7
  (generation) open. The four seams and their conversions are in there.
- `docs/NEXT.md` §5 — the `EraProbe` numbers and the two findings from them.
- **Not yet written**: roads, bridges, rail links, infrastructure ruins, and
  what they do to war. Keks asked for it; the notes are in the session, the
  doc is not. `RegionFeature` already has `.pass`, `.gorge`, `.fen` — the
  chokepoints a road is an answer to and a war is fought over. `TradeRoute`
  exists and has no path on the map. There is no road concept anywhere in
  Core.
- **Also not written**: the world-map polish pass, including climate rules
  ("it does not snow in the desert"). Check `Climate.of(_:in:registry:)`
  before assuming it is missing — it knows the biome, so this may be another
  case of the information existing and nothing reading it.

## Open, not started

- **Crafting panel.** 306 recipes in one flat alphabetical list. Group by what
  comes out, put the affordable first, add a search field, hide what is
  strictly worse (`QuartermasterEngine.worth(of:)` already computes that), and
  offer the missing ingredient's own recipe. Half a day.
- **Households fill one house at a time.** A village of 76 has ~10 full houses
  and 20 empty, and an empty house is dark at night. Deliberate
  (`HouseholdEngine.assignHomes`), and the reason the town looks dead. Keks's
  call, not a bug.


---

# What the next session inherits — 2026-08-20

The three open steps above are closed, and closing them turned over the usual
thing: **content that loads and that nothing reaches.**

| | |
|---|---|
| Step 1, motions | already done — 129 clips, none of the twelve buildings missing |
| Step 2, late-era events | **done** — modern 30 → 45, near_future 20 → 45 |
| Step 3, a seventh biome | **done** — `wetlands` / Mokřiny, and it was fourteen touchpoints, not two |
| Steps 6–7, conveyances | already done — 46 in the bank, parametric drawing |

## Generating the late-era events took four rounds, and that is the lesson

The draft passed `check` and then failed to *decode*, three times running:
`unlock_tech` with no `techId`, a `region_hazard` written in `region_kind`'s
shape, a `remove_pawn` carrying a `count`. `SUPPLEMENTS["type"]` had taught the
generator every word `EventEffect` accepts and nothing about what each one
reads.

`EFFECT_SHAPES` in `content_kinds.py` is the grammar, taken from the decoder,
and `check` runs it for events now. **Run it before believing a draft is
clean.** Rule 61.

Pointing it at the shipped file found **forty-one of the same fault already in
the game**, none of them new: `damage_buildings` takes `strength`, and eleven
effects said `delta`, `damage` or `amount` instead — every one ignored, every
one falling back to a severity of 0.5, so an authored landslide and an authored
dam breach had always been exactly as bad as each other. Seven carried a `count`
for an effect that already damages many buildings; three `add_pawn`s asked for
people they never got. All repaired, and `EffectShapeTests` guards it in Swift
by round-tripping every effect through the decoder and its own encoder — no
second list to keep in step. Rule 62.

## Where the drawing stands

**`19 buildings share a drawing` is closed** — by composition, not by seventeen
new shapes. `StructureVariant` derives how a building is put together from its
own definition (chimneys from what it burns, a wide door from whether
`conveyances.json` keeps a vehicle there, a dark building from having no
workers, `tier` from what it cost, `heft` from `defense`), and
`SettlementStructures.roofCap` / `roofFurniture` / `frontDoor` compose it.
`StructureVariantTests` asserts no two of the fifty-six buildings share both an
archetype and a composition.

Two things worth keeping from it:

- **A random tie-breaker is worse than none.** A coin toss on `bays` was itself
  making a 2-wide palisade and a 3-wide stone wall come out identical. Every
  axis says something true now, and the ties break on `tier`, `heft` and what
  the building stores.
- The signature is what makes the standing rule testable. If you add an axis to
  the drawing, add it to `signature` or the guard stops guarding.

## Still not generated, still for the same reasons

**Horse tack** — seventeen pieces in `items.json` with no recipe, waiting on
mounts. **Anything into a bank whose reader you have not checked.**

## The seventh biome cost fourteen edits, not two

The handoff above said "a row in `LocalTerrain.weights(for:)` and
`sceneryMix(for:)` — Swift, but two lines". It is **fourteen** `switch`es:
terrain shape, ground weights, scenery, tree count, tree species, massif
weight, seam mix, river chance, river anchor, landform chance, animal mix, POI
mix, deposit mix and forage base — plus two in the app for the world-map
colour and its detail marks.

Every one of them has a `default:` arm, so a biome added to the JSON alone
generates cleanly, crashes nothing, and is **the plains under a different
name**. `BiomeCoverageTests` is the guard: it fingerprints each biome across
nine axes against what the unknown-biome path answers and requires at least six
to be its own. `plains` is exempt by name because it genuinely *is* the
fallback — every `default:` in the Core reads `// plains & homeland`.

What the fen is *for*, so the next country is designed and not just tuned: it
eats easily (fowl, fish, reed — forage 85, food affinity 1.15) and it has no
stone at all (massif weight 0.06, no iron in any seam). A colony founded on one
must trade or move for the whole industrial chain, and it has peat to trade
with. Its water lies through the middle of the map rather than along an edge,
which is the only biome that does.

## Open, unchanged
- The crafting panel: 306 recipes in one flat alphabetical list.
- Roads, bridges, rail links — asked for, never written down.
- Households fill one house at a time, so a village of 76 has ~10 full houses
  and 20 dark ones. Deliberate; Keks's call.
