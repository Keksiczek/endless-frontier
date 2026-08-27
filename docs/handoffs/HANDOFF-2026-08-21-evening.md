# Handoff — 2026-08-21, evening

<!-- The second half of 2026-08-21. Read CLAUDE.md, then docs/RULES.md, then
     HANDOFF-2026-08-21.md (the morning), then this. -->

Everything below is **measured, not remembered**.

| | |
|---|---|
| Core tests | **1344 in 186 suites**, green |
| App tests | **161 in 25 suites**, green |

---

## 1. Read this first: what `f3197e9` actually contains

`f3197e9` ("somebody of ours who lives among them") was written by a second chat
running in the same working tree, and it **swept up in-flight work from this
one**: the narrator, the annals, `GeneProbe`, `Era.displayName`, the chronicle
screen's chapter cards. Its message says "Core 1300 tests in 178 suites, green".
That was true of the embassy work it set out to commit and **not true of the
tree it committed** — the road ruins were half-landed at that moment and three
`RoadTests` cases were red.

Nothing needs undoing. It is written down because the commit message is a
record, and this one records a test run that did not cover what it shipped.

**One working tree, one chat.** Two agents committing from the same directory
cannot both know what is in the index.

---

## 2. What this session did

### 2.1 The chronicle is a chronicle now (§5.1 of the morning handoff)

- **Layer 3 exists.** `Core/…/Narrator/`: `NarratorProtocol`, `StubNarrator`,
  `ChapterSnapshot`, `Annals`. The stub needs no model, no network and no
  `Date()`, and `docs/architecture/LAYERS.md`'s rules hold — text only, never
  writes `WorldState`, never required.
- **`Annals.chapters`** cuts two hundred yearly rows into chapters (per era, at
  most `maxChapterYears`, stubs folded back), and `StubNarrator` writes each one
  as prose in Czech and English.
- **`ChronicleFigure`** — the annals have **names** in them. Founders are
  enrolled on day one; anybody who reaches `rememberedAge` is noticed; the year
  boundary writes down when they die. Derived at `ChronicleEngine.record`, so
  `PopulationEngine` did not have to learn about `WorldState`.
- App: chapter cards, a **Lives** roll, and a **Stores** chart — `food` and
  `materials` have been in every `WorldRecord` since the chronicle existed and
  nothing had ever drawn them.

### 2.2 Genes — measured, then fixed twice

`GeneProbe` (new) prints the standing deviation and the **selection
differential**: the mean of everyone under ten less the mean of the adults.

**First measurement.** `sd` is 0.09–0.11, so variation was never the problem.
`kid−ad` had no sign at all for any of the four genes — that is no selection, by
definition. And **142 of 143 deaths in 180 years were old age**, so courage's
ten lifespan years and industry's eight act entirely after the fertile window
shuts. Invisible by construction.

Three couplings, one per gene, each in a different probe column so the next run
can tell them apart (rule 72): `PopulationEngine.fertilityGenePull`,
`SocialEngine.sociabilityBondPull`, and `DiplomacyEngine.boldestFirst` (the bold
walk out first — the only place courage can decide anything while nothing kills
anybody). **Each is exactly 1 at the middle of the distribution**, so the average
colony's growth curve is untouched and every number measured against it stands.

**Second measurement found the real cause.** Fertility turned from falling to
rising (0.501 at year 90 → 0.528 at 170) — and all four means *still* converged
on 0.5. Because every newcomer was built by `PawnFactory.generate` rolling
`Genes.founder`, whose mean is exactly 0.5. **Immigration was resetting the gene
pool toward the middle**, and it is a far stronger force than two centuries of
selection.

`Genes.drawn(from:using:)` fixes it: a settler party takes after the people they
walked from (`Tribe.genes`), an outpost's founders after the realm that sent
them, an event's arrival after the colony it arrives at.

**Third measurement: the fix had not fired.** The re-run came back identical to
the one before it, digit for digit — which is decisive rather than weak, because
a simulation that produces exactly the same two centuries did not execute the
change. `VisitorEngine.settlerParty` is the volume path and it carries
`tribeID: nil` with an invented origin, so the tribe lookup found nothing and
fell back to `Genes.founder`. The fallback now goes to the **colony they are
joining**, and `Settlement.birthTally` / `arrivalTally` count arrivals directly
so "nobody came" stops looking like "the change did nothing".

**Fourth measurement, and the means finally move.** Over 170 years: **110
arrivals against 274 births**, so more than a quarter of everybody who joined
this colony walked in from outside — which is why the leak dominated everything.
Industry 0.584 → **0.634** where it used to fall to 0.551; fertility holds at
0.552 where it fell to 0.527; sociability climbs 0.456 → 0.494 against a
blending process with no direction of its own, which is the coupling selecting.
Courage stays flat at 0.496, correctly: roughly seventy people left over the two
centuries, which takes the boldest out about as fast as the rest are born. Full
tables in `docs/CHRONICLE.md` §4.

### 2.3 Roads — the three open items from `docs/ROADS.md` §7

- **Ruins.** `RoadEngine.seedRuins` lays ancient paved way at world generation.
  `RoadLink.origin` decides three things: weather cannot take it below
  `ancientFloor`, building on it costs `ancientDiscount`, and a raid leaves it
  alone. Drawn as broken stone, and only where the player has walked.
- **A road the player lays.** `GameEngine.layRoad` / `roadCost`, offered as
  **Ways from here** in the region panel. Same ladder, same price as the council
  pays. Nothing shows in the first age because nothing can be laid in it.
- **Bridges, and the water to put them over.** `Region.river` is a
  `RiverCourse`, derived per hex from the same fields as the biomes — **local
  by necessity**, because the map grows outward for ever and a globally traced
  river would change shape depending on which hexes existed when it was asked
  for. `RoadEngine.bridgePremium` prices a crossing; a way along the bank pays
  nothing extra. The moisture threshold was **swept**, not guessed.

### 2.4 A real bug, found by accident

**`roads` and `roadTraffic` were never saved.** Neither had a `CodingKeys` case,
so the encoder skipped them and the decoder never looked: every way the colony
built was dropped on the next write and came back an empty network. Shipped in
`b21182f` and invisible for the whole day, because the only test that could have
caught it — "Full round-trip is lossless" — compared a field that happened to be
empty on both sides. It only went red once the map began *generating* with
ancient stone on it.

**Rule to write down: a round-trip test proves nothing about a field that is
empty in the fixture.** `SavePersistenceTests` now puts a road and a traffic
figure in before encoding.

---

## 3. How to measure any of it

```bash
EF_PROBE=1 swift test --package-path Core --filter GeneProbe    # ~25 min
EF_PROBE=1 swift test --package-path Core --filter MapProbe     # fast; sweeps the water
EF_PROBE=1 swift test --package-path Core --filter RoadProbe    # ~20 min
```

**Disk is still the recurring hazard**, and it bit twice today. Each
`--scratch-path` is ~370 MB and a full test run needs room on top; the machine
hit 0 bytes free mid-build and Swift failed with `No space left on device`
inside the index store, which reads like a compiler bug and is not one.
`~/Library/Developer/Xcode/iOS DeviceSupport` had grown to **11 GB** on one
half-finished copy from `iPhone17,1 26.6`; it was deleted with Keks's say-so and
regenerates when a device is next attached. Delete finished scratch paths as you
go.

---

## 4. Still open

- **A prisoner is still a stranger.** `Siege` knows `attackerTribeID` but not
  their genes, and the tribes are not in scope anywhere between
  `SiegeEngine.begin` and `CaptiveEngine.take`. Four signatures for the rarest
  arrival — written down rather than threaded.
- **A river should slow a crossing, not only price one.** `TerrainCost.of` does
  not read the water. Left out deliberately (rule 72).
- **Sociability's coupling did not show up in the measurement.** Bond growth is
  faster for sociable pairs, but `slots` saturates at 90–100% from year ten
  (morning handoff §4.3) and a bond reaches the wedding threshold in about nine
  years either way, so a ±40% swing barely moves the age at marriage. The
  courtship ceiling is the thing to fix; the coupling is waiting on it.
- **Courage never fired**, because no colony in the measured runs seceded. It is
  correct and dormant.
- **The morning handoff's §4.2 and §4.4 are untouched**: the grudge saturates at
  the ceiling for every people, and the council deepens one trunk route rather
  than widening a web.
