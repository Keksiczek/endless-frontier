# Handoff — 2026-08-23, evening

<!-- For a chat starting cold. Read CLAUDE.md, then docs/RULES.md (87 rules),
     then this. The earlier ones today are docs/HANDOFF-2026-08-23.md and
     docs/HANDOFF-2026-08-22-evening.md; their open sections still stand
     except where §3 below says otherwise. §4 is the brief for the next run. -->

Everything here is measured. Every number comes from a probe or diag in the
tree, named where it appears.

| | |
|---|---|
| Last pushed | `515d600` |
| Core | steward, appetite, building, research, content, map and name suites green |
| App | **168 tests in 26 suites**, green |

---

## 1. What shipped today

| commit | what |
|---|---|
| `79f33fc` | four name shapes and a scattered index; captives drawn and tappable; five new research levers, 23 techs, costs against the measured curve |
| `c72481b` | a store's floor shows the goods it actually holds |
| `a8b08bc` | **`CouncilAppetite`** — the council builds what the town is short of, tilted by who is on it |

### The council, measured

Keks's own save was the evidence: **98 buildings for 90 souls — 7 wells, 7
banks, 6 observatories, 6 universities, no windmill and no workshop at all.**

One line did it. `StewardEngine.nextBuilding`'s last clause was "the cheapest
thing we do not have yet, and once we have one of everything, the cheapest
thing at all". `CouncilAppetite` scores instead: what the colony does not make
enough of *per soul*, a trade with people and nowhere to work, walls only
against something real, a fifth of a thing worth a fifth of the first, and —
the part asked for by name — **the council's own people** (genes read as
distance from the middle, leader counts double, capped at a third either way).

Two hundred years, seed 4242 (`EF_DIAG=1 swift test --package-path Core
--filter ZZCouncilDiag/theTown`, new diag):

```
before the fix   124 buildings / 158 souls   observatory 5+, no assembly plant, defends 4
after            127 buildings / 191 souls   observatory 3, assembly_plant 2, quarry 4,
                                             bloomery 2, stone_walls 5, defends 5
```

---

## 2. Open, and honest about it

1. **`roofEnough` was guessed, not measured.** It is the new bar that stops the
   store runaway (`StewardEngine.roofEnough`, 60 per soul for food and
   materials, 20–25 for the rest). The tally still shows **75 stores of 127**,
   though most of those are dual-purpose (a railyard both makes and stores).
   Before touching it, measure roof against *consumption*: a colony of 191 eats
   about 19 a tick, so a granary cap of 2 600 is two and a bit years of food —
   which may well be right, and the 13 granaries may be honest. Rule 23: print
   the distribution before moving the number.
2. **Research still runs out at year 130** of a 200-year game, and late income
   (16 000/yr) outruns any fixed price. See `docs/HANDOFF-2026-08-23.md` §1.
3. **Eras lag the tree** — medieval at year 80 with 32 of 60 studied.
4. Outlaw raid cadence (7 in two centuries against 63 from peoples and 57 from
   the wild), camp loot never engaging for a strong colony, tribes stage two —
   all still as written in `docs/HANDOFF-2026-08-22-evening.md` §3.
5. Still undrawn on the settlement canvas: **craft orders** and **inventory**.

---

## 3. What Keks asked for while this was being written

Four things, in his words, none of them started:

1. **"Chybí továrny, ale hlavně elektrika."** His medieval town has no windmill
   and no workshop — the store runaway ate every surplus, so the energy clause
   (`draw > 0 && generation < draw`) and the appetite clause below it never got
   a turn. `a8b08bc` should fix it going forward; **it has not been verified on
   his save**, and the honest check is to load that save, run a decade and look
   at the tally. Note the era gate too: `power_plant` is `early_industrial`, so
   a medieval colony's only generator is the windmill.
2. **"Mapa je malá, chtělo by to větší, možná o půlku nebo dvakrát."** The
   *settlement* map. `SettlementGeometry.span` and `ColonyMap` width/height are
   the two numbers; the grid is 24×24 (see `docs/RULES.md` on scale) and the
   canvas span was last moved 0.52 → 0.58. Growing the ground is not just a
   constant: `ColonyBuilder` places on the grid, `FarmEngine` lays plots per
   lot, fog and `AgentMotion` walk in map units, and `SettlementRenderer`'s
   camera opens at a fixed zoom. Expect to touch all four and to re-measure the
   layout cost (`TribeCampTests` has the 150 ms budget).
3. **"Cesty to křižují přes všechno doprostřed, tak není ideální."** The worn
   paths (`SettlementPaths`, `PathEngine`) run point to point, so they cross
   lots, buildings and fields rather than following the edges of them. Wants a
   router that prefers open ground and the edges of lots — the same problem the
   world map solved with `RoadEngine.cut`, one scale down.
4. **"Souboje začínají salvami, co nesedí — mělo by se střílet na dostřel
   luku, podle skillu lovce atd."** Partly answered and mostly not:

   - *Fixed* (`515d600`): the live fight was drawn in **jumps**, because
     `Siege.progress` is `step / steps` and a step only moves when the
     simulation resolves one. Arrows never flew; impacts arrived in a lump.
     `SettlementBattle.liveProgress` interpolates between steps now.
   - *Open, and this is the part he means*: **when a volley happens has nothing
     to do with range.** `SiegeEngine.loose` fires on the step, not on whether
     anybody is inside a bow's reach, and what a shot is worth does not read
     the shooter's skill. It should: `raiderArms`/`weaponProfile` already carry
     `range`, `SiegeField.distance` already measures it, and `Pawn.skills`
     already holds what a hunter is worth with a bow. Until then a fight opens
     with a salvo at whatever distance the line happens to be standing at,
     which is what "nesedí" is.
   - Also open: **the arms in a raider's hands and the effect drawn for them
     can disagree.** `RaiderCard` reads the age; the projectile drawn reads
     `moment.projectile`; a camp of deserters carries the arms of a *later*
     age (`OutlawCamp.armsEra`). Those three have never been checked against
     each other.

5. **"Zoom kamery na eventy nebo směr raidu je taky takový divný."** The camera
   flies to what the Core says happened (`ef-camera-follows-events`), and the
   raid's own bearing (`Siege.approach`) decides where the warband walks in
   from. One of the two is wrong on screen and nobody has measured which:
   start by printing the approach bearing beside where the camera actually
   settles.

6. A **handoff and a brief for a clean run** — §4.

---

## 4. Brief for a clean run

Paste this into a fresh chat.

> Read `CLAUDE.md`, then `docs/RULES.md` (87 rules), then
> `docs/HANDOFF-2026-08-23-evening.md`. Work down §3, in order, and measure
> before tuning anything.
>
> **1. Verify the council fix on the real save.** The container is under
> `~/Library/Developer/CoreSimulator/Devices/94498DA6-…/data/Containers/Data/
> Application/*/Documents/endless-frontier-world.json` (find it; the app id is
> `com.keks.endlessfrontier`). Before: 98 buildings for 90 souls, 7 banks, 6
> observatories, 6 universities, no windmill, no workshop. Load it, advance a
> decade, and print the same tally. If the mix has not moved, the fault is that
> the earlier clauses (stores, roofs) still eat every surplus — measure which
> clause answers, `ZZCouncilDiag` already prints that column.
>
> **2. Electricity and factories.** A medieval colony's only generator is the
> windmill (`power_plant` is early industrial). Check `ResourceLoop
> .domesticEnergyDemand` against what a medieval town of ninety actually draws,
> and whether the energy clause can ever fire before the appetite clause does.
> Content may be the answer — the ancient/medieval eras have one generator
> between them — but measure first.
>
> **3. The settlement map is too small.** Keks wants it half again to twice as
> big. Touching `SettlementGeometry.span` alone will not do it: `ColonyMap` is
> a 24×24 grid, `ColonyBuilder` places on it, `FarmEngine` lays plots per lot,
> and the camera opens at a fixed zoom. Grow the grid *and* the span together,
> keep `TribeCampTests`' 150 ms layout budget, and re-run
> `ZZCouncilDiag/theTown` — a bigger grid means more lots, which means the
> council builds more.
>
> **4. The paths cut through everything.** `PathEngine` wears a track between
> the two points somebody walks between, straight through lots, fields and
> buildings. It wants routing that prefers open ground and lot edges. The world
> map's `RoadEngine.cut` is the same problem one scale up and is worth reading
> first. `AgentMotion` must keep walking the same lines the renderer draws, or
> people will cut corners their own paths do not.
>
> **5. Volleys should be about range, not about the step.** `SiegeEngine.loose`
> fires because a step happened; it should fire because somebody is inside a
> bow's reach, and be worth what the shooter's skill with that bow is worth.
> `weaponProfile` carries `range`, `SiegeField.distance` measures it, and
> `Pawn.skills[.hunting]` is the number Keks named. Check what the raider is
> *drawn* holding against what the record says was fired while you are in there.
>
> **6. The camera on events and on the raid's direction reads wrong.** Print
> `Siege.approach` beside where the camera settles before changing either.
>
> **Rules that will bite:** one SwiftPM run at a time (two starve each other
> and the perf guards fail on a loaded machine); `swift test --package-path
> Core` is ~40 min for everything, so filter; every string ships CZ+EN in the
> same change; the canvas never writes `WorldState`.

---

## 5. How to measure what is above

```bash
EF_DIAG=1  swift test --package-path Core --filter ZZCouncilDiag/theTown  # ~13 min
EF_DIAG=1  swift test --package-path Core --filter ZZCouncilDiag          # ~20 min
EF_PROBE=1 swift test --package-path Core --filter ResearchProbe          # ~27 min
EF_DIAG=1  swift test --package-path Core --filter ZZOutlawDiag           # ~30 min
EF_DIAG=1  swift test --package-path Core --filter ZZNameSample           # instant
```
