# Handoff — 2026-08-04

Branch **`main`**, clean and pushed.

Tests: **889 Core**, **94 app**. `swift test --package-path Core` takes ~4–9 min
on Keks's machine depending on load.

```bash
swift test --package-path Core
```

```bash
xcodebuild -project App/EndlessFrontier.xcodeproj -scheme EndlessFrontier -destination 'platform=iOS Simulator,name=iPhone 17' test
```

```bash
cd App && xcodegen generate
```

Regenerate the Xcode project after adding any file under `App/Sources` — a new
file that is not in the target fails as `cannot find type … in scope`.

---

## The batches, newest first

| | What |
|---|---|
| `a11de53` | Nobody teleports to a ruin; nothing works an abstraction; no two houses alike |
| `45e5efe` | Three kinds of danger, and the one that gets worse the better you do |
| `7432272` | Find one colonist in a town of a hundred; arm them from their own card |
| `ea45437` | The town has room to be a town; every building has its own face; a place has something in it |
| `1c8de0d` | The fight has a ground to stand on, and the neighbours can come to hate you |

`docs/BACKLOG.md` §8 and §9 carry the full write-up of each. What follows is
what a next session needs to know and what is left.

---

## 1. The through-line, stated once

Every one of these batches turned out to be the same bug wearing different
clothes: **a system whose effect could not reach the thing it was aimed at.**

- A raid could not be *fought* because it resolved between two frames.
- A people could not come to hate you, because the only thing that made them
  angry required them to be angry already.
- The wild could not threaten a big colony, because its strength was capped by
  the era and not by the colony.
- A hut could not house the people its ledger counted, because the ledger and
  the building were two numbers.
- A logger could not be seen working a tree, because the drawing checked the
  abstract deposit first and won.
- A ruin could not be a journey, because it was a button.

When something in this project "feels flat", the question that has found the
cause **six times running** is: *what rate is supposed to move this, and can it
actually get there?* Write the test for the reachability, not for the behaviour.

Rules 6, 12 and 13 in `BACKLOG.md` are three faces of it.

---

## 2. What the world does now, measured

`DangerProbe` is the instrument. It is off unless you ask for it:

```bash
EF_PROBE=1 swift test --package-path Core --filter DangerProbe
```

Two hundred years, seed 4242, nobody playing:

```
deaths      old_age 219 · starvation 132 · sickness 10 · battle 1
population  476        morale 73        food 13/2850
fights      91  (37 turned back)        sicknesses 4
tribes      6   standings [−80, −51, −9, 0, 0, 0]
```

For most of this project's life that tally was one line long (`old_age`). It is
now four, and each line comes from a different system:

- **Battle** — `SiegeEngine`, real positions, contact by proximity.
- **Sickness** — `PlagueEngine`, the threat that scales *with* your success.
- **Starvation** — food finally binds, once wolves stopped looting like a
  warband (`Siege.carriesOff`).
- **Old age** — still the commonest, which is right.

Anything that changes a combat, wildlife, diplomacy or food number should be
measured against this before and after. It takes ~7 minutes and it has caught
three regressions that no unit test would have.

---

## 3. Still open — in the order I would do them

### 3.1 Events happen nowhere, to nobody

`BACKLOG` 3.6. **40 of 71 events never name a building, a place or a colonist**,
and every hook to do it already exists (`WorldQuery` can pick a pawn, a
building, a POI; `EffectApplier` can act on one). This is the cheapest large win
left: it is content work against a working machine, and it turns the storyteller
from a ticker into something that happens *to* people you know by name.

### 3.2 The old English content

Events, buildings and techs still ship English-only. `LocalizedText` is in place
and everything new is bilingual, so this is a translation pass, not a
refactor — but it is the last thing standing between the game and being fully
Czech, and Keks plays in Czech.

### 3.3 Fields and herb beds are still places, not things

`SiteVisitEngine` and the entity layer took the wood, the rock and the beasts.
`LocalResourceKind.field` and `.herbs` are still `ResourceNode` blobs harvested
by proportional arithmetic (`FloraEngine.isEntityBacked` returns false for both).
A field of individual crops that ripen and are cut is the same move again, and
it is the last of "everything is blocks or pawns".

### 3.4 Births do not keep pace, and the era stops at `ancient`

Population peaks and drifts back. The later era milestones ask for settlement
counts and populations the colony never reaches, so two thirds of the tech tree
and the whole late game are unreachable in practice. This wants measuring before
it wants tuning — the probe will show where the ceiling actually is.

### 3.5 Smaller, and real

- Battle has **no sound and no haptics**. The one place a phone game should
  reach out of the screen, and it is silent.
- `Diagnostics` / `WorldReport` have grown organically and nobody reads half of
  it; a pass to make it say the four or five things that actually matter would
  pay for itself the next time something is "flat".
- The **world-map site outcome** narrative is a plain `String`, not
  `LocalizedText` — it predates the localisation and is the one journal line
  that cannot be Czech.

---

## 4. Things that will bite you, from experience

1. **`swift test` on the whole Core is slow.** Filter while working
   (`--filter SiegeTests`) and run the whole thing once before committing.
2. **Never seed an RNG from `hashValue`.** Swift seeds its hasher per process,
   so a hash-derived seed replays differently on every launch and silently
   breaks determinism. Derive from the UUID's *bytes* — see
   `PlagueEngine.seed`, `BanditEngine.seed`, `RegionExpeditionEngine.seed`.
3. **Every new field on a saved type is `decodeIfPresent` with a default.**
   Every batch this week added one and every one of them has a "a save written
   before this existed still loads" test.
4. **Two numbers for one thing is the recurring design bug.** `housing` vs beds,
   `SettlementGeometry.span` vs `colonySpan`, the muster line in two files.
   When you find yourself writing the second one, derive it instead.
5. **Keks's Mac is an 8 GB Intel machine.** If a build dies with `terminated
   with uncaught signal 9` in the asset-catalog step, that is the host under
   memory pressure, not the repo.
6. The simulator installed is **iPhone 17**.

---

## 5. Where to look

| For | Read |
|---|---|
| What has been asked for, ever | `docs/BACKLOG.md` |
| The rules a change must not break | `docs/BACKLOG.md` § "Rules" (13 of them) |
| Systems and formulas | `docs/DESIGN.md` |
| Footprints, lots, pawn-like animals | `docs/RIMWORLD_LAYER.md` |
| Layer separation | `docs/architecture/LAYERS.md` |
| Whether the world is actually dangerous | `DangerProbe`, `EF_PROBE=1` |
