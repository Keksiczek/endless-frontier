# Handoff — 2026-08-03

Branch **`main`**.

Tests: **860 Core**, **94 app**. `swift test --package-path Core` takes ~270 s.

Three batches this day, newest first:

| | What |
|---|---|
| `7432272` | Find one colonist in a town of a hundred; arm them from their own card |
| `ea45437` | The town has room to be a town; every building has its own face; a place has something in it |
| `1c8de0d` | The fight has a ground to stand on, and the neighbours can come to hate you |

§6 and §7 below cover the two later batches; §1–§4 are the combat pivot.

---

## 0. What this session was for

The previous handoff put Keks's three pieces of feedback at the top as the
brief: *no challenge*, *combat does not aim well and the rounds feel strange*,
and *real-time walking would be better*. It also gave an order to do them in —
positions into the Core, then orders on tap, then difficulty — because
balancing the round-based shape first would be work thrown away.

All three are done, in that order. §1 is the pivot, §2 is what measuring the
difficulty actually turned up, and it was not what the numbers suggested.

---

## 1. The pivot: a fight with a ground to stand on

Fighters have positions the **Core** owns.

- `Siege.Combatant` — side, `at`, strength, target, down. Staged by
  `SiegeEngine.stageIfNeeded`: the watch among the houses, the warband at the
  edge of the map, abreast and facing each other down the line of the attack.
- `SiegeField` — the battlefield geometry, moved out of the app. Rule 8: the
  line the raiders break on and the line the colonists run to are one number
  now, not two.
- `AgentMotion` **reads** a colonist's position instead of interpolating one.
  Rule 5 is untouched and load-bearing; the precedent followed is
  `Pawn.currentJob.position` and `HaulEngine.haulPosition`.

Everything that was a step index is a distance:

| Was | Is |
|---|---|
| `step >= approachSteps` | nobody within `SiegeEngine.reach` yet |
| raider *i* fights colonist *i* | each picks the nearest enemy and walks to them |
| `Posture.cover` = 0.35 / 1 / 1.2 | `SiegeField.cover(at:)` — cover is a place you stand |
| `posture == .giveGround` spends grain | a raider inside `wallReach` is in the stores |
| all damage on the single weakest | every raider hits the person in front of them |

`Posture` no longer says how much of the wall counts. It says **how far out the
line will go** (`Posture.reach`), and the wall is read off the ground people are
standing on — so pressing them costs the wall because it walks out from behind
it, and giving ground keeps it because it puts you back inside.

**Orders.** Tap a colonist, then tap the ground or an enemy:
`Siege.Order.moveTo` / `.engage`, recorded on the siege exactly as the posture
is. Same seed plus same orders still replays to the same dead, and the order
survives the disk. `SiegeCommandCard` says so in one line, CZ+EN, because
nothing else on screen would.

Everything that made a live battle safe survives unchanged: a step is fought
once by whoever reaches it first, the app may run ahead of the world clock, and
`ActionLoop` finishes a raid nobody watched identically.

---

## 2. Difficulty — the numbers were the smaller half

`DangerProbe` (Core tests, off unless `EF_PROBE=1`) is the instrument. Run it:

```bash
EF_PROBE=1 swift test --package-path Core --filter DangerProbe
```

### 2.1 What one raid costs, after the retune

Twelve bare-handed colonists, whole fight, measured end to end:

```
str  30  wall  0  →  hurt 2  worst −33     str  30  wall 50  →  hurt 2  worst −13
str  60  wall  0  →  hurt 4  worst −93     str  60  wall 50  →  hurt 4  worst −37
str 120  wall  0  →  2 dead, hurt 8        str 120  wall 50  →  hurt 8  worst −43
```

Four changes got there, none of them a blanket multiplier:

- `attackerDamagePerStrength` 0.14 → 0.24. Spreading blows across a line made
  them slacker than the old single-target arithmetic; this puts the cost back.
- Raiders **work on whoever is already hurt**, mildly
  (`nearest(preferringWeak:)`). This is the mechanism that produces a casualty
  instead of twelve people evenly and harmlessly bruised.
- A held line **closes the last two steps** (`closingPoint`). Before it, a
  raider fighting your neighbour was a hand's breadth away and a third of the
  line never swung, because the enemy was "outside the muster ring".
- **Nothing knits while a wound is open** (`PawnEngine`). The flat 0.3-a-tick
  recovery ran unconditionally on top of the bleeding, so an untreated wound
  closed as fast as a tended one and the whole healer's trade bought nothing.

### 2.2 …and then the two that actually mattered

Measuring the *rate* rather than the fight found two things worse than any
combat number, both the project's recurring shape:

**No tribe had ever raided anybody.** Two hundred measured years, six peoples,
final standings `0 / 0 / 0 / +75 / +80 / +82`. Every one of the 26 fights in the
run was wolves. Grudge had exactly one source — a quarrel over hunting grounds —
gated on standing already being below −15, while standing drifts toward a
compatibility of 62 or better at 12 % a year. **Every term of the loop was
inside the loop**, so it never started. `DiplomacyEngine.crowding` feeds it from
outside: a colony that outgrows its neighbours is taking somebody's share of
finite land, game and water. Trade and marriage work it off.

**The wild never answered the colony.** Predator pressure is capped by the era,
so a pack was ten strong whether the settlement was five people or four hundred.
The first thirty years of a real world: four fights, worst wound *nothing at
all*. The pack's weight now scales with how much there is to come for
(`WildlifeEngine.packPerColonist`), the watch scales with the colony, and
`attackChancePerPressure` went 0.00025 → 0.0004.

Same seed, 200 years, after:

```
before   fights 26   standings [0, 0, 0, 75, 80, 82]    ever hurt 6
after    fights 58   standings [−51, −6, −1, 0, 0, 0]   ever hurt 13
```

Both are guarded by tests named for the reachability, not the behaviour:
*"A people can come to hate you without hating you first"* and *"The wild
answers a colony that has grown"*.

---

## 3. Still open

- **Nothing has yet killed anybody but old age** in a long run. A colony of four
  hundred shrugging off a warband of a hundred and forty is *correct*, so the
  honest next step is what threatens a **late** colony — not another multiplier
  on the early game. A raid you cannot simply out-number is the missing kind.
- **Food is not scarce.** It is no longer pinned at the cap in every run, but it
  is not a constraint either. §8.1 cause 3, untouched.
- **Births do not keep pace with old age** past the peak.
- **Era stops at `ancient`** with the whole tech tree researched.
- **The world map's own sites are still instant.** `SiteEngine.interact` —
  ruins, dungeons, anomalies, lost cities on the hex map — resolves in one call
  with no party and no journey. `SiteVisitEngine` fixed the *valley's* places;
  this needs travel between regions, which does not exist yet.
- **`BACKLOG` 3.6** — 40 of 71 events never name a building, a place or a
  colonist. All the hooks exist.
- Battle has no sound and no haptics.
- Old English content (events, buildings, techs) is still untranslated.

### Notifications

Keks reported getting one notification and then nothing. There was a real bug:
`minimumGap` was measured from the moment the player left rather than from the
previous message, so the one that is actually urgent — the council waiting on a
decision, due at two hours — was silently pushed out to six, every time. Fixed.

What is still true **by design**: the earliest message is two hours out, so a
short absence is meant to be silent, and a day with no pending decision and no
trouble produces only the 22-hour digest. If that reads as "nothing", the fix is
*more to say* — the world is deterministic, so a notification could genuinely
predict what will have happened by then — not a shorter timer.

---

## 4. Rules the codebase has sprung, newest first

Full list in `BACKLOG.md` §"Rules". Added this session:

13. **A feedback loop needs an input from outside itself.** Grudge could only be
    made by a quarrel, a quarrel needed hostility, and hostility only came from
    grudge. Anything that is supposed to build up has to be fed by something
    true whether or not it has already started.
12. **A threat that does not scale with what it threatens is scenery.** Rule 6
    in the danger direction, hiding behind numbers that looked fine.

---

## 6. Scale and charm (`ea45437`)

**The hut that held thirty people** was rule 8 again — two numbers for one
thing. `housing` said thirty and fed the population cap; the RimWorld layer gave
that hut one tile and four beds, so the ledger counted twenty-six people the
building had nowhere to put and all of them slept rough for ever. `housing` is a
*flag* now; `BuildingDefinition.sleepers` is the number, derived from the ground
covered times `floors`, read by both the ledger and the beds.

Scale with it: grid 18×18 → **24×24**, every footprint up a tile each way, the
span on screen unchanged so a *building* comes out larger, camera opens at 2×.
Dwelling costs fell with their capacity — beds per material are what they were,
because the fix was geometry and not difficulty. Miss that and the colony misses
its first era milestone; `StewardTests` caught it.

**Forty-seven buildings shared eleven shapes** because thirty-six stated no
`look` and the numbers cannot tell a farm from a granary from a well. Now 29
archetypes, none carrying more than four, seventeen of them new in
`SettlementTrades`, interiors furnished to match.

**A visit with a middle.** `SiteEncounter` + `SiteVisitEngine`: a place holds
caches, traps and something living in it, and the party walks between them on
the action clock exactly as a raid is fought. What comes home is what they got
the lid off.

## 7. Finding and arming one person (`7432272`)

A name field and five lenses on the colonists panel; `EquipmentStrip` on both
the colonist row and the canvas inspector, so equipping is person-first instead
of a menu of every colonist in the town.

## 5. Commands

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

Simulator installed: **iPhone 17**. Keks's Mac is an 8 GB Intel machine;
`actool`, `ibtool` and `momc` have been SIGKILLed under memory pressure before.
If a build fails with `terminated with uncaught signal 9` in the asset-catalog
step, that is the host, not the repo.
