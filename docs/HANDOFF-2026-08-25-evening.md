# Handoff — 2026-08-25, evening

<!-- For a chat starting cold. Read CLAUDE.md, then docs/RULES.md, then this.
     The previous one is docs/HANDOFF-2026-08-25.md. -->

| | |
|---|---|
| Last pushed | this batch |
| Core | 1541 tests, green (see §4 for the run) |
| App | 173 tests green, iOS build green |

## 1. What this batch was

Keks played it and listed what was wrong, in one message and four follow-ups.
Every item below is one of his sentences, and the fix under it is what the
sentence turned out to mean. Nothing here was on a roadmap — this is the game
answering back.

## 2. Shipped

| commit | what |
|---|---|
| `a567465` | a war with a beginning and an end, and peoples who live somewhere |
| `ecf0551` | a fight at the town's edge, ground under the houses, a square in the middle |
| `cd6bb6e` | a valley bigger than the town, land the world map promised, wounds you can see |
| `e086e9b` | a river with fords in it, and a party that walks to one |
| `785bc4f` | outlaws who notice how rich you have got |
| (this one) | research paced by the age you live in |

### "Války mi neprojdou propojené nikde, jen v diplomacii."

War was not a thing. `standing < −30` rolled a raid once a year, `Tribe.wars`
counted them, and a "fragile peace" clause quietly set the number back to −5 —
so nothing in the world could be **asked** whether there was a war on, and the
one surface that showed anything drew its WAR pill at −60 while the raid rolled
at −30. `WarState` is declared, fought, tallied and ended; it shows on the world
map (crossed swords, the people's own name), in the settlement's status strip
(the year and the butcher's bill), in the diplomacy card, and in its own journal
kind. Tribute finally has a war to end rather than a grievance to work off.

### "Na mapě nejsou všechny národy."

A seceding people was given `regionID` of the settlement it walked out of — the
colony's own hex, where the map draws a house and the house wins. Every people
the colony ever bred was invisible. They move out now, the map asks for *every*
tribe on a hex, and schema 5 re-homes the squatters in existing saves.

### "Všichni tam naběhnou v takovém umělém archu … kreslí se to přes aktuální mapu."

It was not drawn over the map — it was **fought on top of it**. `SiegeField`'s
reaches were written when a colony was a ring of huts (line at 0.30, wall at
0.26) and the build grid has since covered 0.70 of the valley, whose edge is at
0.35. `SettlementGeometry.builtReach` measures the furthest standing roof on the
bearing the attack comes in on; the muster, the wall and the warband's start all
hang off it, and the rank is scattered by a hash of its own place.

### "Ať je souboj dynamický dle prostředí — co je okolo, za co se skrýt."

`CoverField` has stamped every tree, rock, cliff and building into one grid
since §11.27 and the fight read it only to tax arrows in flight.
`SiegeEngine.groundStride` walks the ground: a step that would end inside a
building slides round the face, and while closing, a fighter takes the
best-covered place a stride can reach. Not in contact, and not in a press.

### "Budovy jen levitují nad zemí a pod nimi vše normálně roste."

The lot was there and stopped dead at the wall. Every building now wears a
ragged apron of scuffed ground and darkens the earth where its wall meets it.

### "Udělej náves rozlišitelnou … teď je to namačkáno mezi domy."

The green has been reserved in the Core since districts went in and **nothing
ever drew it** — which is exactly what "a gap between the houses" looks like.
`SettlementGreen` draws beaten earth, four tracks, and one thing in the middle
that says which century it is: a moot fire, then a well, then a market cross.

### "V pozdějších érách se to zaplní a okolo nic moc není."

The grid grows to ninety tiles a side and `SettlementGeometry.span` did not
follow it, so a grown town packed ninety tiles into the same 0.70 with the same
thin rim of country. The span follows the grid now, a founding town takes 0.46,
and `Camera.opening` is derived from the same number so buildings are the size
they were with more valley behind them.

### "Když je něco na mapě světa, není to na mapě osady."

`RegionFeature` reached the road cost and the region panel and never the ground.
It stands its country up in the valley now, and the two site kinds that put
nothing there (a ruins hex grew four decorative pillars; an anomaly grew
nothing) put a place you can walk to.

### "Zranění neodpovídají tomu, co vidíme na plátně."

True since the medical model went in. `PawnHarm` derives what a body shows and
the figure draws it: a stump above the elbow, a leg that ends at the knee with a
stick on the good side, a limp, linen where somebody was tended and blood where
nobody was.

### Expeditions walked over the water (open since 22 August)

Fixing it turned over the thing underneath: **a river had no crossings**, which
makes it a wall rather than a river. `RiverShape.fords` — three, placed from the
river's own phase — and `PathEngine.dryWay` charts the way through one. The
crossings are drawn, because a ford is a place.

### Outlaw raid cadence (open since 23 August)

Eight raids in two centuries. The probe named the cause: `temptation` read
3.000 at every percentile for two hundred years, because its haul term was
capped. Ceiling off the haul, kept on the fullness ratio: **31 raids**, and the
number now varies with what the colony has (rule 90).

### Research ran out at year 130, and the eras lagged

Gated on `requires` alone, so the council took the cheapest tech anywhere: a
medieval colony studied `computing` at year 110 and finished all sixty by 160.
`TechEngine.eraReach` allows one age of reach — the ladder `eras.json` needs —
and the last two era milestones asked for 260 and 600 souls against a measured
peak of 322. Re-measured: medieval studies stay medieval, early industrial at
140, modern at 170, **near future at 190** (never reached before).

## 3. Open

1. **`roofEnough` was guessed, not measured** (`StewardEngine`). Untouched.
2. **The camps are never cleared** — three of three still standing after two
   centuries in every probe run. The player can now be raided by them properly;
   burning one out is still a verb nobody uses.
3. **Knowledge income swings between −7 011 and +7 011 a year** in
   `ResearchProbe`. It is drawn in lumps by design, but nobody has checked
   whether the lumps are the reason a colony sometimes stalls mid-study.
4. **The melee still reads as "radoby se mydlí"** to some degree: the fight is
   in the right place and uses the ground now, but the exchange itself is a
   swing and a blood mark. Impacts, recoil and a weapon that meets a body are
   the next pass.

## 4. How to measure

```bash
swift test --package-path Core                       # ~16 min
EF_PROBE=1 swift test --package-path Core --filter "raidCadence"
EF_PROBE=1 swift test --package-path Core --filter "ResearchProbe"
xcodebuild -project App/EndlessFrontier.xcodeproj -scheme EndlessFrontier \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
