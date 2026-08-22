# The Council

<!-- Written 2026-08-22, out of one screenshot: year 28, medieval, six hundred
     materials of six hundred, and an observatory. -->

`StewardEngine` is the autopilot. It runs in the gaps — the player's decisions
always win — and it exists because without it the world was frozen: research,
building and the bench were all UI-only, so a colony nobody was watching did
nothing at all for two hundred years.

This doc is about the ways it can *look* like it is working and not be.

## 1. What it does, in order

Once per `interval` ticks, per settlement:

| | |
|---|---|
| `keepMaterialsComing` | standing orders for the made things the buildings want |
| `raiseWhatIsShort` | one building, by the clause order below |
| `QuartermasterEngine` | arms, coats, tools, and the handing out of them |
| `keepTheYard` | carts and mounts, sized against the people who would push them |
| `sendSomebodyOut` / `foundIfItCan` | expeditions, and daughter towns |

`nextBuilding` argues in this order: **fields, roofs, stores, a kitchen, a
generator, then breadth.** Named needs rather than a score, so the reason a
colony built a granary is a sentence.

## 2. The three faults behind one screenshot

A player's colony, year 28, medieval, 53 souls in 152 beds: **materials 600 of
600, food 1148 of 1150**, an observatory standing, and no warehouse. The council
had stopped doing anything useful years earlier. Three separate faults, each of
which alone would have been enough.

### 2.1 The bench belonged entirely to the council

`CraftingEngine.maxOrders` is twelve, and `keepMaterialsComing` stood one
**standing** order per wanted material — where `wantedMaterials` unions the
material list of every building of every era the colony has reached, plus
everything the gear bench asks for. Past the first age that is comfortably a
dozen.

So the queue filled with council orders and stayed full, which does three things
at once and shows none of them:

- the player's own orders are **refused** — `CraftingEngine.place` returns the
  settlement unchanged when the queue is full, and the panel's button just does
  nothing;
- `QuartermasterEngine` runs *after* it and could never queue a spear or a coat;
- every material trickled, because the bench's effort is split twelve ways.

`councilBenchShare = 8` leaves four slots the council cannot take. If the player
fills them, the council waits — which is the right way round.

### 2.2 It shopped in alphabetical order

`wantedMaterials` returns `Set.sorted()`. Against a finite bench that made *the
first letter of an item id* the colony's industrial policy. `shoppingList` now
sorts by **how many buildings the material unblocks**, which is the difference
between four timber bundles arriving and a warehouse being unbuildable for ever.

`buildableHere` was split for this: `wantedHere` applies every guard *except*
"the made things are on the shelf", so the difference between the two lists is
the shopping list. Nothing had ever computed it.

### 2.3 The upkeep brake refused the answer to the problem

`canAffordToKeep` weighs a building's **materials production** against its
upkeep. It is sound and it is the reason a colony stopped building itself to
death (rule 25) — the measured run where 163 buildings took materials from 7886
to 9 and the population from 204 to 28.

But **a warehouse produces nothing.** So a colony at its materials cap was
refused, permanently, the one building that raises the cap: standing at the brim
does not change the ledger the brake reads, so the refusal is stable for ever
and the colony throws away its whole quarry output every tick. Shelter already
had an exemption for exactly this shape; stores have one now, and only for the
good that is actually spilling.

**Measured before the fix**, medieval, 600 of 600: the colony could build
**one** thing in the whole book — a well. Everything else in the book named a
made thing nobody had asked for.

## 2.4 What the three fixes are worth, measured

`ZZCouncilDiag`, seed 4242, the council left alone:

```
year pop | mats/cap      | able | clause -> pick
  10  22 |   479/500     |  3   | 4 breadth -> lumberyard
  40  60 |  2270/2300    | 29   | 2 roofs   -> courtyard_house
 110  95 |  3296/3600    | 10   | 3 stores  -> railyard
 200 257 | 20800/21300   | 27   | 3 stores  -> railyard
 250 402 | 44184/44300   |      |
```

The column that matters is `able`. It was **one** — a well — in the state the
screenshot caught: a medieval colony at six hundred materials of six hundred,
where every other definition in the book named a made thing nobody had asked
for. It now runs between nine and twenty-nine, the store cap climbs from five
hundred to forty-four thousand over two and a half centuries, and clause 3 gets
its turn regularly instead of never.

Two things this run also shows that are **not** fixed and are not this doc's
subject: knowledge sits at 120 of a cap that reaches ten thousand — research
income is close to zero — and the fields clause only takes its turn at year 240.

## 2.5 And a fourth thing, found while looking at the map

`Region.river` is written where every derived field is written — at generation,
in `MapGenerator.region(at:...)`. So a world that already existed had `nil` on
every hex and would have kept it: no rivers, no bridges, and no way to tell dry
country from a save made before there was any water.

`SaveMigrator` step **2 → 3** recomputes it for every region. Safe to recompute
rather than guess, because the course is a pure function of `(mapSeed, coord)` —
it gives exactly the map the generator would have drawn, which is also what a
newly explored hex on the frontier gets. Any derived field added to a generated
model wants this step in the same change.

## 3. What to check when the council looks stupid

In this order, because each one makes the next unreadable:

1. **How many things can it build at all?** `StewardEngine.buildableHere(...)`.
   If that is one or zero, nothing else about the clause order matters.
2. **Why not?** Diff it against `wantedHere` — the difference is materials the
   bench has not made.
3. **Is the bench free?** `settlement.craftOrders.count` against
   `CraftingEngine.maxOrders`.
4. **Is an earlier clause permanently true?** Rule 27. Fields and roofs both
   grow with the population, so both can become standing conditions in a colony
   that is genuinely growing.

`ZZCouncilDiag` (`EF_DIAG=1`) prints all four, per decade, with the clause that
answered and what it picked.
