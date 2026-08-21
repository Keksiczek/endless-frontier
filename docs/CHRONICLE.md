# The Chronicle

<!-- Live design doc. Written 2026-08-21, alongside the work. -->

The chronicle is the only place the game says **what happened to you** rather
than what is happening now. Everything else on screen is a present tense: the
valley, the council, the stores, the neighbours. The annals are the past tense,
and a colony sim without one is a screensaver with numbers on it.

Until now it was four charts and six canned observations. This doc is what it
is becoming and — more usefully — the seams it may not cross.

## 1. What the chronicle is allowed to be

`WorldRecord` is **one row per in-game year**, written at the year boundary by
`ChronicleEngine.record`, capped at `maxRecords = 200`. It is part of
`WorldState`, so it is persisted, and every field in it costs save size forever.
That cap is why the chronicle is a *sampling* of history and not a log: two
hundred rows is two hundred years, and a colony that lives longer forgets its
beginning. This is deliberate and should stay.

Everything else the annals say is **derived on read** — computed from the rows,
never stored. `ChronicleEngine.insights` already works this way and the annals
follow it. The test of whether something belongs in `WorldRecord` is simple:

> Could it be recomputed from the rows later? Then it is not a field.

## 2. Chapters, not years

Two hundred rows is a spreadsheet, not a history. The annals cut the rows into
**chapters** — a chapter per era, and long eras subdivided so no chapter spans
more than `Annals.maxChapterYears`. Each chapter carries a `ChapterSnapshot`:
the span, the population at both ends and at its peak, what the people died of
*in that span* (the cumulative tallies differenced, not the running totals),
the drift of each disposition, the wars, the disasters, the faith.

The snapshot is the **whole** contract with Layer 3. It is `Codable`, it is
small on purpose (the LAYERS.md budget is ~500 tokens of JSON), and it contains
no `WorldState`, no ids a narrator could act on, and nothing mutable.

## 3. The narrator seam (Layer 3)

```
ChapterSnapshot ──▶ NarratorProtocol.narrate(_:language:) ──▶ String?
```

Rules, all of them from `docs/architecture/LAYERS.md` and none of them
negotiable:

- **Text only.** A narrator returns a string. It cannot write `WorldState`,
  cannot be handed one, and nothing downstream of it may feed back into the
  simulation.
- **Offline-first.** `StubNarrator` is *always available* and is what ships. It
  writes the annals out of the snapshot with no model, no network and no
  `Date()`. A colony on a plane reads the same annals as a colony at home.
- **Deterministic.** Same snapshot, same language, same prose. Where the stub
  wants variety it draws from a seed derived from `(mapSeed, chapter span)`,
  which is stable across replays — never from an unseeded RNG.
- **Optional means optional.** `LocalLLMNarrator` is a seat, not a dependency.
  If it is absent, slow, or returns nothing, the stub's text is what the player
  reads, and they are not told they are missing anything.

`isAvailable` exists so the UI can *offer* a richer narrator, never so it can
require one.

## 4. Why the gene chart was empty

The chronicle carries "natural selection" as a generated insight and a four-line
chart, and for two centuries both said the same thing: nothing moved. That is
not a chronicle problem. `Genes.blended` is the midpoint of both parents, which
halves the variance every generation; `Genes.mutated` is mean-zero, which adds
spread and no direction. The fixed point of the two is a standing deviation of
about 0.073 and a mean that never leaves 0.5.

A mean only moves if a gene decides **who survives and who has children**.
Widening the mutation does not do that — it makes noise. `GeneProbe` prints the
standing deviation and the **selection differential** — the mean of everyone
under ten, less the mean of the adults — so the question is answered with a
number instead of an argument.

### What it measured, before anything was changed

Seed 4242, two hundred years:

```
year   pop  gen |  industry            |  fertility           | …
                    mean    sd   kid−ad    mean    sd   kid−ad
  10    21  0.4 |  0.593 0.095 -0.0055 |  0.541 0.099 -0.0125 | …
  50    57  2.0 |  0.567 0.109 -0.0078 |  0.521 0.101 +0.0451 | …
 100    88  4.0 |  0.564 0.110 -0.0283 |  0.518 0.082 -0.0194 | …
 170   217  6.8 |  0.541 0.100 +0.0038 |  0.516 0.090 +0.0180 | …
```

Three things, all of them decisive:

1. **`sd` is 0.09–0.11.** There is plenty of variation. Spread was never the
   problem, which is why widening the mutation would have been the wrong fix.
2. **`kid−ad` has no sign.** It wanders either side of zero for all four genes,
   generation after generation. That is the definition of no selection.
3. **142 of 143 deaths in 180 years were old age.** One was sickness; nothing
   else killed anybody at all. So `lifespanYears` — courage's ten years and
   industry's eight — acts entirely *after* the fertile window shuts at forty
   to fifty-two. Those two coefficients are invisible to selection by
   construction, however large they look.

### What was changed, and where each shows up

One coupling per gene, each in a different column of the probe, so the next
measurement can tell them apart (rule 72):

- **fertility → `PopulationEngine.fertilityGenePull`.** `fertilityAt` returns a
  flat 1 through the middle of a life, so the gene only ever moved the *edges*
  of a window most children are born well inside. Now it scales a couple's
  chance directly. **At 0.5 the factor is exactly 1**, so the average colony's
  growth curve — and every number measured against it — is unchanged; what
  changes is the spread.
- **sociability → `SocialEngine.sociabilityBondPull`.** Children come out of
  bonds now, so how fast a bond grows *is* how many children a colonist has.
  Again 1 at the middle of the distribution.
- **courage → who walks out.** `DiplomacyEngine` seeds a seceding band with the
  poorest or the unhappiest; of those, the boldest go first. It is the only
  place courage can decide anything while nothing in the world kills anybody
  (see `DangerProbe`), and it makes the colony steadier as its boldest keep
  leaving — which is a story worth being able to read in the chart.
- **industry** was left alone on purpose. It is already selected *indirectly*:
  industry buys wealth (`SocietyEngine`), and wealth decides who stays when a
  people secedes. A second, direct coupling would be a thumb on the scale.

### And then the second measurement found the real cause

With those three couplings in, fertility turned from falling to rising — 0.501
at year 90 to 0.528 at year 170, and a selection differential that finally had a
sign. But **all four means still converged on 0.5**, including the two that
selection was now pushing on.

The cause was not selection at all. Every newcomer — a settler party up the
road, a colonist an event brings in, the six who found an outpost — was built by
`PawnFactory.generate`, which rolled `Genes.founder`: uniform 0.3…0.7, **mean
exactly 0.5**. So immigration was quietly resetting the colony's gene pool
toward the middle every time somebody arrived, and it is a far stronger force
than anything two centuries of selection produces. A colony could not drift
because it was being topped up from an urn that always held the average.

The fix is `Genes.drawn(from:using:)`: **a newcomer comes from somewhere**, and
that somewhere has a character of its own.

| Who arrives | What they take after |
|---|---|
| a settler party | the people they walked from (`Tribe.genes`) |
| the founders of an outpost | the realm that sent them |
| somebody an event brings in | the colony they arrive at — the game knows no better |
| a prisoner taken in a raid | *still a stranger* — see below |

`Tribe.genes` has existed since a seceding band first carried out the average of
those who left, so this closes the loop: the world's gene pool becomes a system
with structure in it rather than a leak into a fixed average.

### …and the first cut of that fix did nothing, which the numbers proved

The re-run came back **identical to the previous one, digit for digit**. That is
not a weak result, it is a decisive one: a simulation that produces exactly the
same two hundred years did not execute a single line of the change.

The reason is `VisitorEngine.settlerParty`, which is the *volume* path — a
household on the road to a colony that is feeding itself, has spare beds and is
not visibly wretched. It sets **`tribeID: nil`** and invents an origin with
`wandererOrigin` that is not a place on the map. So the fix, which looked up a
tribe, found nothing and fell straight back to `Genes.founder`.

The fallback is the fix: where no people can be named, a newcomer takes after
**the colony they are joining**. A household off an unnamed road is people of
this country; they are not a draw from a fixed distribution centred on 0.5.

And because "nobody arrived" and "arrivals that changed nothing" had looked
identical for two measurements, `Settlement.birthTally` and `arrivalTally` now
count both directly. Not off `ColonyLog` — that is a 140-entry ring, so counting
`.birth` entries in it silently undercounts the moment a colony outlives its own
diary, which is rule 67 in its plainest form.

### What it reads now

Seed 4242, the same two hundred years, with the leak closed:

```
year   pop   born  came  died |  industry     |  fertility    |  sociability  |  courage
  10    22      8     2     0 |  0.595 0.092  |  0.547 0.102  |  0.466 0.101  |  0.497 0.096
  50    68     45    24     4 |  0.601 0.088  |  0.540 0.083  |  0.485 0.082  |  0.487 0.075
 100    85     96    58    48 |  0.632 0.079  |  0.547 0.064  |  0.493 0.083  |  0.489 0.068
 170   216    274   110   110 |  0.634 0.081  |  0.552 0.074  |  0.494 0.075  |  0.496 0.075
```

| | founders | year 170 | before the fix |
|---|---|---|---|
| industry | 0.584 | **0.634** | 0.551, and falling |
| fertility | 0.545 | **0.552** | 0.527, and falling |
| sociability | 0.456 | **0.494** | 0.487 |
| courage | 0.498 | 0.496 | 0.509 |

The `came` column is the whole argument: **110 arrivals against 274 births**, so
better than a quarter of everybody who ever joined this colony walked in from
outside. A path carrying that much of the population and drawing every one of
them from a fixed distribution was never going to let anything drift.

Two of the three couplings can now be seen doing something. Sociability climbs
0.456 → 0.494 against a blending process that has no direction of its own, which
is `sociabilityBondPull` selecting. Fertility stops falling. **Courage is flat**,
and correctly so: about seventy people left this colony over the two centuries,
which takes the boldest out at roughly the rate the rest of the world produces
them.

**Still open:** a prisoner ought to carry their own people's character in with
them. `Siege` knows `attackerTribeID` but not their genes, and the tribes are
not in scope anywhere on the path from `SiegeEngine.begin` to
`CaptiveEngine.take` — four signatures for the rarest way anybody arrives, so it
was left alone and written down instead.
