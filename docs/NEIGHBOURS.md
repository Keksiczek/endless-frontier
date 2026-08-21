# Neighbours — verbs that stand on the map

**Written 2026-08-21, before the code.** `docs/ROADS.md` is the sibling: roads
are what makes half of this affordable, because a road to somebody else's
capital is a thing you can see, pay for, and lose.

Read `docs/RULES.md` first. The ones this design is shaped by are **16** (build
off a rate, never a share of the store), **21** (a purse capped below the
cheapest thing buys nothing) and **69** (a rate that only fires on an event is
not a rate).

---

## 1. What is actually missing

Not verbs. The game has three and they are correctly layered —
`GameEngine.sendGift`, `demandTribute`, `proposePact`, called from
`GameViewModel`, applied in the Core. An earlier read of this file said the
player had no verb at all; that was wrong, and it is worth saying so here
because the wrong diagnosis leads to building a fourth button.

What is missing is that **all three are a one-off spend of influence that moves
a number.** A gift raises `standing` and lowers `grudge`, and that is the whole
of it. None of them:

- **stands on the map**, where it can be seen;
- **holds in time**, so it can be tended or neglected;
- can be **lost** — and a relationship you cannot lose is not a relationship.

That is the gap. Three verbs that persist, each costing something real and each
reading state that already exists.

## 2. The three

| Verb | What it costs | What holds | How it is lost |
|---|---|---|---|
| **An embassy** | influence, and a colonist who is *there* and not at home | `standing` climbs slowly while they sit | war, or you call them home |
| **A road to them** | materials, edge by edge | caravans both ways, `standing` for the commitment | **cut in war** |
| **Tribute you pay** | food or materials, every year | holds `grudge` down while you pay | stop paying and it returns with interest |

### 2.1 An embassy

A named colonist leaves and does not come back until you send for them.
`Pawn.isAway` and `expeditionID` already model somebody who is elsewhere;
`RegionExpedition` is the precedent for hands that are not at home and that the
labour engine notices.

What makes it a *decision* rather than a purchase: the colonist is gone. A
colony of thirty feels one fewer pair of hands. And the standing they earn is a
**rate** — a little every year — so an embassy that has stood for fifty years is
worth something no gift can buy, and one you set up last spring is not.

### 2.2 A road to them

The one roads unlocked, and the reason to do this batch now. `RoadEngine`
already lays edges, prices them by terrain, and draws them. A road to a
neighbour's capital is:

- **visible** — it is on the world map, in the grade you paid for;
- **mutual** — it shortens the journey *both ways*, which is what makes it a
  commitment rather than a gift. A road to somebody who later hates you is a
  road their warband walks in on;
- **losable** — `RoadNetwork.remove` exists and nothing calls it. A raid that
  cuts the pass behind you is the payoff `RegionFeature.pass` has been waiting
  for since it was written.

### 2.3 Tribute you pay

`demandTribute` is the verb pointing outward. The one pointing in has no
counterpart: a colony that cannot fight has no way to buy peace except a gift,
which is a single payment against a grudge that keeps growing.

Paying tribute is a **standing charge** — every year, out of stores — that holds
`grudge` down while it is paid. Stop, and it comes back with what it would have
been. This is the verb a losing player needs and the one that makes losing
interesting rather than terminal.

## 3. What must not happen

- **A verb that is strictly better than the others.** If the road is always
  right, the embassy is decoration. They cost different things — hands, matter,
  a yearly bill — so a colony short of people, short of stone, or short of food
  should each reach for a different one.
- **A rate keyed to an event.** Rule 69, learned the expensive way in
  `RoadEngine`: standing earned by an embassy has to accrue *because the
  embassy stands*, not when something happens to fire.
- **A cost as a share of the store.** Rule 16: the yearly tribute is a multiple
  of what it buys, never a fraction of the warehouse, or a colony that builds a
  granary suddenly cannot afford peace.
- **A threshold nobody reaches.** Rule 6. Measure with `DiplomacyProbe` before
  choosing a single number — §4 is what it currently reads.

## 4. What the neighbours actually do, measured

`DiplomacyProbe`, two hundred years, seed 4242 — the numbers every new verb has
to be sized against:

```
year  met │ standing: worst  best  mean │ grudge: worst mean │ wars  fights
 100    4 │            -25    71     5 │           110   68 │   13     41
 200    5 │            -61    -4   -31 │           110   97 │   67     92

  Askarel          -74 … 81   (155)     Ranaův lid      -100 … 14  (114)
  Thalen           -83 … 23   (107)     Vemlarunův lid   -99 …  8  (107)
  Oldaslavův lid   -53 …  4   ( 58)
```

**This is the opposite of §8.5.** Then, two hundred years produced six peoples
who could not be angered and twenty-six fights that were all wolves. Now the
world turns hostile on its own: sixty-seven wars, ninety-two fights, and every
people in the negative by year 170.

Two readings that matter for the verbs:

- **Standings swing over bands of 58 to 155 points.** A gift's twelve is noise
  against that. A verb is felt when it is a *rate* — an embassy that adds a
  little every year is worth something at fifty years that no single payment
  buys — which is why §2 is written in terms of what **holds** rather than what
  it costs.
- **Grudge saturates at the ceiling for every people.** That is a fault: a
  number every neighbour shares stops telling a people you have wronged from
  one you have not. The **relief** is where to attack it — trade and marriage
  take three off a grudge that grows by eight a year, and §8.5 claimed they
  "work it off". Measured, they do not. Do **not** attack the source: capping
  crowding's contribution was tried, and took the war count from 67 to 2
  (rule 71).

One real bug came out of the first run and is fixed: `grudgeCeiling` was
honoured at one of the three places anger is added, so every people overshot to
exactly 119. `DiplomacyEngine.resent` is the one door now.

## 5. Order of work

1. ~~**`DiplomacyProbe`**~~ — **done**, and §4 is what it says.
2. ~~**Cutting a road**~~ — **done**. `RoadEngine.cut`, called from
   `DiplomacyEngine.raid`: raiders take the dearest stretch on their own line of
   march, one grade down rather than gone, because an embankment does not stop
   existing when somebody tears up the rails.
3. ~~**A road to a neighbour**~~ — **done**. `GameEngine.buildRoadToward`, one
   stretch per call, growing outward from home so a half-built road goes *part*
   of the way. Buys standing and eases the grudge, and can be cut by the people
   it was built for.
4. **The embassy**, because it wants a colonist to be genuinely absent.
5. **Tribute you pay**, last, because it is the one that most wants the probe's
   numbers to be trustworthy.

## 6. Open questions nobody has decided

- Does an embassy make a raid on you *less likely*, or only cheaper to end?
- Can a neighbour ask **you** for tribute, as an event with a real choice?
- Is a border a thing on the map, or is `DiplomacyEngine.crowding` enough? The
  crowding pressure already models "your colony is taking somebody's share of
  finite land" without any hex being owned, and adding ownership may be two
  numbers for one thing (rule 8).
