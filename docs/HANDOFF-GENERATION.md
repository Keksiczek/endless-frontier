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
