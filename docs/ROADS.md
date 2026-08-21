# Roads — the world map gets a shape

**Written 2026-08-21, as the system was built.** Keks asked for roads, bridges
and rail links more than once; the notes lived in a session and the doc never
existed. This is it.

Read `docs/RULES.md` first. The three rules this design is shaped by are **6**
(a threshold beyond the reach of the rate meant to cross it), **16** (build off
a rate, never a share of the store) and **21** (a purse capped below the
cheapest thing can never buy the dearest).

---

## 1. What was wrong

The world map had no road concept at all, and **distance was a number nothing
the colony did could change**. Three systems were the poorer for it, each in the
same way:

| System | What it did | Why that was thin |
|---|---|---|
| `RegionExpeditionEngine.travelTicks` | `hexes × travelTicksPerHex` | a party crossing a fen and one crossing a plain took the same time |
| `TradeRoute` | names an origin and a destination | **and no path** — a route through a range cost what one next door cost |
| 46 conveyances | carry a `regionPace` of 0.7…50 | the world had nowhere for a lorry to be faster than a mule |

The third is the one that matters most, and it is the shape
`HANDOFF-GENERATION.md` names outright: *a bank whose reader you have not
checked*. Forty-six vehicles were generated, drawn parametrically, given fuel
chains and upkeep — and the number that says how fast they cross country had
nothing to divide into.

## 2. The shape

A road is **per hex-edge**, not per journey. You do not build "a road to the
mountains"; you build the piece between here and the next hex, and a route is a
chain of pieces. Three consequences, all wanted:

- a **half-finished road is a real state of the world**, and it shows on the map;
- a road can be **cut**, which is what makes a pass worth holding;
- the network **grows where the world actually goes** rather than where a
  designer drew a line.

```
RoadLink    a ── b, a grade, a condition        Models/Road.swift
RoadGrade   track → road → paved → rail
RoadNetwork every link, and the pathfinder      Models/RoadNetwork.swift
RoadEngine  who lays them, what takes them back Engine/RoadEngine.swift
```

`RoadLink.id` is **derived from the two coords**, never random, and the two ends
are stored in canonical order so `a→b` and `b→a` are one road. This is rule 3
in the place it has already cost a session once (`GameWorldFactory`'s founding
UUIDs).

## 3. Where roads come from

Three motions, and only the middle one costs the colony anything.

**1. Traffic beats a track.** Nobody decides to build one. At `trackThreshold`
crossings the ground *is* a track, worth 1.35× and free — which is how a world
earns its first roads without the player having to know roads exist.

Two things lay traffic, and the **second is the one that matters**:

- **Journeys**, recorded by whoever makes them (`RoadEngine.travelled`) —
  caravans, supply runs, expeditions. Real, and far too rare to build a system
  on: *thirteen* in two hundred measured years, because supply only moves when
  somebody is short and the council only explores out of overflow.
- **Neighbours** (`RoadEngine.neighbourlyTraffic`) — people going back and forth
  between towns that are near each other, to a market, a wedding, a brother's
  farm. Each settlement to its *nearest* neighbour, weighted by the smaller of
  the two populations, so a hamlet beside a city wears the road at a hamlet's
  rate. This is a rate that exists **as long as the towns do**, and it is what
  actually puts roads between neighbours, where roads belong.

Nearest-only keeps it O(settlements), and it runs on `visitInterval` rather than
every tick because it pathfinds (rule 4).

**2. The council makes a road.** `RoadEngine.wanted` scores every edge by
**traffic × how bad the country is** and hands the steward the single best one.
That product is the whole design: a made way across a plain saves a tenth of the
journey and one through a fen or over a pass saves half of it, so the council
ends up building the pass — the piece a player would have chosen, arrived at
from the numbers rather than from a list of special cases.

Paid for out of materials at `reserveMultiple` × the price (rule 16: a multiple
of the **cost**, never a share of the warehouse — a granary multiplies the cap,
and a reserve that grows with the cap is a colony that can suddenly never afford
anything again).

**3. Weather takes it back.** A way nobody mends returns to being country. And
traffic *keeps* a road as well as making one — a way in daily use is repaired by
the people using it — so the network thins back to what the world needs instead
of accumulating every road ever built. A failed track is simply gone; anything
dearer falls back one grade, because the levelled ground under a paved road does
not stop existing.

## 4. What the country charges

`TerrainCost.of(region)` — biome × the land's own `RegionFeature`, both already
derived from elevation, moisture and warmth, so this can never disagree with the
country the generator drew.

| | |
|---|---|
| plains 1.0 · coast 1.15 · forest 1.35 | ordinary going |
| desert 1.5 · tundra 1.6 | slow |
| **wetlands 2.1 · mountains 2.4** | the two the roads exist for |
| **pass ×0.55** | why a range is passable at all |
| gorge ×1.7 · fen ×1.8 · peak ×2.2 | chokepoints |

`buildingCost` is deliberately **sub-linear** in the crossing cost: a fen is
twice as slow to walk and about half again as dear to bridge, not twice.
Otherwise the one road worth having is the one nobody can ever afford — rule 21,
which killed a colony once already.

## 5. What rail actually is

Not "a faster road". `RoadNetwork.Mover.onRails` **may not leave the rails** —
`stepCost` returns `nil` for any edge that is not `.rail`. That is the trade a
railway asks you to make, and it is why rail is a decision rather than an
upgrade.

The other half is what stops "buy a lorry" substituting for building anything:

- **off the road**, a wheeled thing is capped at 1.25× a walking party however
  fast it is;
- **on a track** it gets a quarter of its own speed, on a road half, and on
  **stone all of it**.

Paving is what a fast machine is waiting for.

## 6. What the finished system actually does, measured

Two hundred years, seed 4242, `RoadProbe`:

```
year │ towns │ traffic │ busiest │ track road paved rail │ worst │ saved
 100 │     2 │     6.9 │     6.9 │     0    0     0    1 │  0.98 │  13%
 140 │     4 │   153.2 │   132.5 │     0    0     0    3 │  0.83 │   7%
 200 │     5 │   831.1 │   560.6 │     0    0     0    6 │  0.34 │   7%
```

Traffic is real, the ladder climbs the whole way, and six edges end at rail.
**Two things in that table are worth knowing before anybody tunes it again.**

**The council deepens rather than widens.** It lays one edge per pass and always
the best-scoring one, so it keeps upgrading the same few links — track to road
to paved to rail — while a second-best edge never gets a first road. That is why
`road` and `paved` read zero at year 200: not because they are unreachable
(`RoadLadderTests` proves a bare edge gets a road first) but because every edge
the council has touched has already been carried past them. Whether that is
right is a design question, not a bug: a realm with one superb trunk route and
nothing else is a defensible answer, and so is a realm with a web of ordinary
roads. Nobody has decided which this game wants.

**The saving is 7% because the network is a forest, not a web.** Traffic is laid
from each settlement to its *nearest* neighbour, so what grows is a set of short
links between close pairs — and the number above measures the journey between
the two towns **farthest apart**, which mostly crosses ground nobody has any
reason to road. The roads that exist do their job; the metric is measuring
around them. Widening `neighbourlyTraffic` past the nearest neighbour would
close it, at O(settlements²) pathfinding, which is a cost that wants measuring
before it is paid.

## 7. Still open

- **Bridges.** A river crossing is currently just terrain. `RiverShape` exists
  per local map; the world map has no river edges to bridge yet, so this wants
  the world map to know where water runs before it can mean anything.
- **Cutting a road.** The model supports it (`RoadNetwork.remove`) and nothing
  does it. A raid that cuts the pass behind you is the war-fought-over-terrain
  the chokepoints are for.
- **Infrastructure ruins.** A stretch of paved road with no colony at either end
  is a strong piece of world-telling and `SiteEncounter` already knows how to
  make a place out of things.
- **A player-built road.** Today only the council lays them. A tap on a hex edge
  with a price on it is the obvious affordance, and it wants the drawing first.

## 8. What four measurements cost, and what they taught

Worth writing down, because the system was **correct after the first pass** and
three of the four rounds of "tuning" that followed were chasing a broken metric.

| Round | What it showed | What was actually wrong |
|---|---|---|
| 1 | traffic 4, threshold 60 | real: no track could ever be worn (rule 65) |
| 2 | rail 4, road 0 | real: `nextGrade` returned the top rung (rule 66) |
| 3 | *identical to round 2* | `.road` was gated on `the_wheel`, a **leaf tech** nothing else requires, so a colony heading for steam never picks it up |
| 4 | traffic 900, busiest 604 | the fix that mattered: roads are worn by **neighbours**, not freight (rule 69) |
| all four | "saved 5%" | **the metric was wrong** — it measured the longest journey to any explored *region*, a wilderness hex nothing would ever build toward, while the roads between the towns were climbing the whole ladder (rule 68) |

The columns that told the truth — `busiest` and `routes` — were the ones added
last. A total says nothing about how it is spread, and a track is worn by
traffic on **one edge**. `routes` was what proved the `TradeRoute` clause dead:
zero in every world the harness plays.

## 9. How to measure it

`RoadProbe` walks two hundred years of a real world and prints what the map
ended up with: traffic, tracks worn, what the council paid for, worst-kept
condition, and **how much of the longest journey the network saves**.

```bash
EF_PROBE=1 swift test --package-path Core --filter RoadProbe
```

`RoadTests` proves the system is reachable *in the API*. Rule 59 is the reminder
that this is not the same question — a sweep that sets the era, grants the tech
and fills the warehouse says the code works and says nothing about whether a
colony left alone ever gets there. **Read the probe before tuning anything.**
