# Handoff — 2026-08-13 (fifth pass)

> **The colony stopped dying.** Left alone for two hundred years it now ends with
> **298 people and still growing**, in the **modern era**, where this morning it
> ended with 44 in `early_industrial`. Three of the five fixes were code that
> already existed and was never reached.

Branch `main`, everything pushed. **1078 Core tests in 139 suites green, 95 App
tests green, iOS `BUILD SUCCEEDED`.**

Start at [README.md](README.md) — the docs were consolidated today, and
`ROADMAP.md` / `NEXT_STEPS.md` are now marked historical.

---

## What changed, and why each one hid

Measured with `ZZStewardProbe` (`EF_DIAG=1 swift test --filter ZZStewardProbe`),
which drives nothing — an untouched world *is* the shipped game left alone.

| seed 4242 @ year 200 | before | after |
|---|---|---|
| population | 44 | **298**, climbing |
| era | `early_industrial` | **`modern`** |
| buildings | 110 | 164 |
| food / raw shelf | 0 / 0 | 4486 / 4403 |
| goods left lying | 354 | **0** |

**1. The harvest was owned by the dead** — `HaulEngine.releasingDeadClaims`.
`HaulPile.claimedBy` was set when a colonist reserved a heap and cleared in
exactly one place: arrival. Anyone who claimed a heap and then died, sickened or
walked out took it with them for ever. Two centuries of ordinary deaths leak
claims steadily. This was the famine §11.28 could not name, and it hid perfectly
— plots stood at 140 against 79 wanted, cooks and farmers both scaled correctly,
production was healthy throughout. **Nothing that was being watched was short.**
Rule **33**.

**2. The wood never grew back** — `FloraEngine.reseeded`. `FloraEngine.plant` had
**no callers**; its own doc comment called it "the only way a wood that has been
cleared ever comes back". A felled valley stayed bare, `wood` ran out,
`saw_timber` could not run, and every building with a `material_cost` became
permanently unbuildable: timber on the shelf hit zero at year eighty and stayed
there for the remaining hundred and twenty, with `buildableHere` returning an
**empty list** and 5500 materials in the store.

**3. Knowledge was emptied every tick** — `WorldConfig.knowledgeReserve`.
`drawKnowledge` took every banked point and the council always has a study
running, so `storage[.knowledge]` was permanently zero. `buildableHere` wants the
cost *and as much again*, so every knowledge-priced building was unreachable for
ever: power plant, bank, university, hydro dam, refinery.

**4. The council could not see a brownout** — `StewardEngine` clause 3c. The word
`energy` appeared once in that file, in a comment about an old bug.

**5. The council built itself bankrupt** — `canAffordToKeep`, rule 25.
`upkeepRateOfCost` is 0.005 *a tick*, thirty per cent of a building's price every
year, and nothing weighed it; once building was unlocked materials went
7886 → 3084 → 9. **Roofs are exempt** — the brake refused huts the moment the
ledger tightened, which is a colony forbidden to grow. The tests caught that.

Also landed: typed storage (a granary no longer deepens the archive; `warehouse`
is new), the granite that had two greys, 17 English-only UI strings plus a test
that walks the source for more, and §11.24 in full.

---

## §11.24 — a number can be followed to where it stops

The resource pills are buttons. Tapping one opens the chain in the order goods
actually move, marks **the first empty stage after a full one**, and names the
**kinds** held at each stage:

```
Roste na poli        1240   8 z 20 záhonů zralých
   │
Sklizeno, nedoneseno  260   Leží na poli, dokud pro to někdo nedojde.
   │                        [obilí 180] [řepa 80]
Na polici               0
   │
Hotová jídla            0   2 u ohně
```

`StoreBreakdown` is Core-side and derived, so the card and the simulation cannot
disagree (rule 18). The kinds were the point of the ask: the crafting bench was
the only screen in the game that named a good, and that is where you go when you
already know what you want.

`GameViewModel.focusRequest` is the shared affordance behind the click-throughs.
`SettlementScreen.selection` is local `@State`, so no other screen could reach it
— colonist rows and journal lines now post a *request* and the screen that owns
the canvas adopts it, moves the camera, and clears it. One place still decides
what is on screen.

---

## What to pick up next

The plan is [BACKLOG.md](BACKLOG.md) §11. Accessibility is deliberately **last**
(Keks, today).

1. **§11.26 wear.** `ItemInstance.quality` is written in `init` and never again
   anywhere in the codebase — a sword carried through forty battles is the sword
   it was forged as. Wear from use, from combat, and from lying in the open;
   stone exempt. Settle first whether wear lowers `quality` or is a second axis
   beside it.
2. **§11.27 cover and turrets.** Needs a **height** and a solidity on `Landform`,
   `Flora` and the rocks — none have either. Passability and cover are two
   different axes: a ravine is impassable and gives no cover, a low wall is
   passable and gives plenty.
3. **§11.29 fuel and vehicles.** The generator ladder already exists in
   `buildings.json`; opening the knowledge gate (done today) may be most of what
   was wanted. `Caravan.totalTicks` is fixed at creation, so there is nowhere to
   hang a horse until travel time is *derived*.
4. **§11.30 audio.** Sources checked and written up, nothing downloaded,
   deferred to its own round.

### Two corrections to carry forward

- `NEXT_PHASE.md` says "a building has no condition, nothing can be damaged".
  **Out of date** — and I repeated it in `CODEMAPS/models.md` before checking.
  `BuildingPlacement.condition` is live and `ResourceLoop.staffingFactors` folds
  it into output. The real gap is narrower: production is averaged *per
  definition id*, so two granaries are one entry with a mean condition. A
  tidy-up, not the unlock it was billed as — and **it does not block §11.26 or
  §11.27**.
- Daughter towns **are** founded (seed 4242 reaches four). They did not help,
  because every one of them had the same claim leak. Twenty-five charted empty
  regions sit unused because `soulsPerSettlement × (settlements + 1)` wants 225
  people for a fifth town.

---

## Habits this day earned

- **Probes beat tests for anything that takes a century.** All five bugs were
  found by `ZZStewardProbe`; not one by the suite. Print the column that would
  *falsify* the guess, not the one that confirms it.
- **Two columns, not one.** The famine was invisible in `shelf` alone and in
  `lying` alone. Side by side it was obvious in a second.
- **A fix that changes the trace by not one digit means the diagnosis was
  wrong**, not that the fix was incomplete. I read this famine wrong twice from
  the outside — once as clause ordering, once as cooking throughput — and both
  were correct arithmetic on the wrong question.
- **A status line in a doc is a claim with a date on it.** Check the code.
