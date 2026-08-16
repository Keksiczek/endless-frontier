# Handoff — 2026-08-16

> **"Mělo by to být krytí footprinty budov."** Cover itself was built last
> session and every part of it was right. What was still a *number* was
> everything the cover was supposed to be about: all forty-nine buildings
> covered identically, a palisade was placed wherever there happened to be room
> (which is the middle of town), `fortification` was one scalar that did not
> care which side the attack came from, and nothing a fight did to the town was
> ever recorded on the town.

Branch `main`. The plan is [BACKLOG.md](BACKLOG.md) §11.34; the rule this day
earned is **37** in [RULES.md](RULES.md).

---

## What changed

**A building covers according to what it is.** `Cover.body(of:registry:)`: a
wall is chest-high and roofless, everything else is total, and the substance is
whatever the thing was actually built out of — read off `materialCost` through
the new `ItemDefinition.substance`, which the twenty-four material items now
carry. A palisade of six timber bundles is 0.56; mortared ramparts are 0.75; a
brick building is 1.

**A wall stands on the ring.** `ColonyBuilder.perimeterFit` puts ramparts at
`SiegeField.wallReach` from the heart — derived from the reach the fighting
actually happens at (rule 35), not a tile count somebody wrote down — and each
new one goes round to the side nothing guards.

**A wall counts where it stands.** `SiegeEngine.facingShare` weights every
rampart by its bearing against the approach and by its condition, down to
`strayRampartShare` (0.30) for one behind you. Garrison buildings are people and
have no side, so a colony with no walls is untouched by this.

**Cover is a place people go.** `CoverField.shelter` answers what is at a
defender's shoulder — the trace `struck` uses cannot, because two people in
contact are inside one cell of each other — and `SiegeEngine.sheltering` steps a
colonist behind the wall, boulder or old walls within a stride of their post.
The canvas needed nothing: it draws what the Core says (rule 5).

**A shot that is stopped marks what stopped it.** `CoverField.struck` names the
placement, `BuildingEngine.chip` wears it, and a battered wall then turns aside
less — so the damage a raid does is a cost the *next* raid collects.

**A building that fights.** `Siege.Combatant.Kind.emplacement`: a watchtower
stands where it was built, shoots half again as far as a bow in a hand, stops
when it becomes a wreck, and can be pulled down by raiders who would rather be
in the stores. It is not on the roster, does not march and is not shoved.

**Nothing lies in the mud for free.** `HaulEngine.weathered` rots the heaps
nobody has carried in, at a rate read off the same `substance`: the harvest
quickly, timber slowly, **stone not at all**. On the tick, never the step. This
is what makes a store worth building — the buildings existed the whole time and
were a pure upgrade with no force pushing the other way.

**And the store can be found.** `BuildingDefinition.purpose` (derived, not a
list) and a filter row on the build bar: *Bydlení · Jídlo · Sklady · Obrana ·
Práce · Věda*. The warehouse has been an early-settlement building for months;
the fault was one alphabetical strip of everything the colony can raise.

## Three things this turned over

1. **The cover grid is 40 × 25, not square.** A step of one column (0.025) never
   leaves the row a person stands in (0.04), so cover to the north or south was
   unreachable however close it stood. Both the shelter sample and `coverSearch`
   are floored at the larger cell dimension.
2. **Seeking cover against a distant origin moves nobody.** Every candidate
   within a stride looks at the same two cells as the post it came from, so the
   search always returned the post. It is measured against the *bearing* of the
   attack instead.
3. **A default value does not make a `Codable` field optional** — rule 37. The
   synthesised decoder calls `decode`, not `decodeIfPresent`, so `kind` would
   have cost every in-progress raid its save.

## What to pick up next

- **Look at a fight.** The whole point of this batch is that people now stand
  behind things. Watch one raid before tuning anything.
- **Not built, and named in §11.27:** a shot stopped by a *tree* damages
  nothing, because only buildings are named on the field. That is deliberate for
  now; wear on flora would want §11.26 C first.
- **§11.26 C — durability.** Still true that `ItemInstance.quality` is written
  in `init` and never again. Buildings wear now; gear does not.
- **§11.30 — audio.** Still nothing at all.
- **A `LivelinessProbe`** — what fraction of colonists are visibly moving — is
  still the cheapest way to settle "does the town read as alive", and still
  unbuilt.
