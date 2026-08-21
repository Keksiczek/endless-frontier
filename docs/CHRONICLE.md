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
Widening the mutation does not do that — it makes noise. See `GeneProbe`, which
prints the standing deviation and the selection differential (the mean of the
children less the mean of the adults) so the question can be answered with a
number instead of an argument.
