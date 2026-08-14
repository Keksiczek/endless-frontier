# Handoff — 2026-08-14

> **"Přijde mi že se postavičky nehýbou."** They were moving. They were moving
> thirty times slower than the colonist standing next to them, which the eye
> reads as not moving at all. The canvas was never at fault: 30 fps,
> a fractional tick, `WalkPath.position(at:)` interpolating correctly. The fault
> was a rate written in the wrong unit, and it had been there since hauling was
> built.

Branch `main`. Start at [README.md](README.md); the plan is
[BACKLOG.md](BACKLOG.md) §11.32, and the rule this earned is **34** in
[RULES.md](RULES.md).

---

## What was actually wrong

Four movement rates shared one screen, in three different units. Nobody had
ever converted them into the same one.

| who | as written | crossing the whole map |
|---|---|---|
| a colonist living the drawn day | `AgentMotion.walkSpeed` 4.5 per 300 s day | **67 s** |
| a hauler | `HaulEngine.carrySpeed` 0.06 **per tick** | **33 min** |
| somebody on an errand | `ErrandEngine.pace` 0.09 **per tick** | **22 min** |
| a fighter closing on a raider | `SiegeEngine.pace` 0.030 **per action step** | **47 s** |

A world tick is two real minutes and about six in-game days, so a colonist
fetching a sack from the far side of the village was spending three in-game
months on the walk. In map widths per real second — the only unit the player's
eye works in — that is `0.0008` against the day walker's `0.015`.

**The regression Keks remembered is real and has a shape.** `AgentMotion.pose`
gives `haulWalk` and `errand` *priority* over the day clock. So every system
that put a colonist on a simulated walk — the food chain, `HaulEngine`,
`ErrandEngine` — moved that colonist off the fast clock and onto the slow one.
The town became more alive in the simulation and more frozen on the screen, at
the same time, for the same reason.

**The answer was already in the codebase, used by exactly one system.**
`SiegeEngine` was the only movement measured per *action step*, and combat was
the only movement that looked alive.

## What changed

- **`WalkPace`** (new, `Models/`) — one place that says how fast a person walks,
  per action step. `0.08` empty-handed, `0.06` with a load. Crossing the valley
  is twelve and a half steps; an ordinary trip across town is two or three.
- **`WalkPath` and `Errand` count absolute action steps**, not ticks. Same
  fields, same saves, one clock eight times finer. Crossing the map goes from
  22 minutes (errand) and 33 minutes (hauler) to about 3 and 4 — roughly
  sevenfold, because the pace itself moved as well as the unit.
- **`HaulEngine.advanceStep` and `ErrandEngine.advanceStep` run from
  `ActionLoop`** — eight times inside the tick — instead of once from
  `ResourceLoop`.
- **A hauler who puts a load down looks for the next heap on the spot.** A walk
  is a few steps now, so the ten-tick job board would have left them standing in
  the doorway nine tenths of the colony's day.
- **`SiegeEngine.pace` keeps its own, slower number** and now says why: a line
  closing on an enemy advances warily. Deliberately different, deliberately on
  the same clock.

Guarded by `WalkPaceTests` (Core) and `WalkPaceAgreementTests` (App). The second
one is the test that would have caught this in the first place: it converts both
clocks into map widths per real second and asserts they are within 5× of each
other. They were 20× apart. It is a *cross-layer* assertion, which is why nobody
had made it — the two numbers live on opposite sides of the package boundary.

## The regression I made, and caught

Moving the errand engine onto the finer grid ran it eight times a tick, and two
things in it are **rates**, not one-shots: `eat` is capped at a head's share of
the store and `gnaw` takes one unit off the shelf at a time. Both are
deliberately small enough to be repeated — that is what makes a famine a famine
for everybody. Run eight times a tick, a starving colony eats its granary eight
times as fast.

So the engine is split: **arrivals every step, setting off once a tick.**
Arriving is the half that has to be fine-grained — it is what puts a colonist at
the granary door at the moment the canvas draws them reaching it. Setting off,
and eating where you stand because you are away with a party, stay on the tick.

The same split pays for itself twice: `places(in:)` walks every placement in the
colony and is now built on the tick's own step and not on the seven that follow
(rule 4). `ColonyRoute.Occupancy` is built lazily, the pile sweep stays on the
tick, and `ErrandEngine` returns immediately for a colony where nobody is
hungry, cold or on the road.

## Combat needed nothing

Worth writing down because it was half the question. A live raid steps at 1.4 s
(`GameViewModel.siegeLoop`, ten times ahead of the world clock) and a finished
skirmish replays over `SettlementBattle.playSeconds = 20`. Both were already
independent of the tick. **Combat was the one thing built right, and it was the
model for the fix.**

---

## What to pick up next

**1. Look at it before building anything else.** This whole change is visual and
nobody has watched it yet — open a colony and give it two minutes. If the town
now reads as busy, the "watch loop" idea (driving action steps ahead of the
world clock the way `siegeLoop` does, so a walk plays in 10 s instead of 40)
is **not needed** and should not be built. Decide by looking, not by arithmetic;
the arithmetic is what got us here.

A `LivelinessProbe` would settle it properly and is cheap: sample a settled
colony at a hundred random instants and print **what fraction of colonists are
visibly moving**, by activity. That is the number this whole session was about
and there is no measurement of it anywhere. It belongs next to `GrowthProbe`.

**2. The same mistake, twice more — both on screen, neither fixed.** Found while
looking, written up in §11.32:

- **Visitors crawl.** `VisitorEngine.pace` is `0.03` *per tick*: a trader with
  mules covers `0.00025` map widths a second, sixty times slower than a
  colonist. This one wants a **decision, not a constant**. The approach is
  supposed to take several minutes so the player sees a party coming, and over
  that distance it cannot also move visibly — so either the beat becomes
  "waiting at the edge" rather than "walking slowly", or visitors go on the step
  grid. `VisitorEngine.walk` mixes the walking with the `ticksRemaining` phase
  logic and wants splitting first.
- **The wild is a still life.** `AnimalEngine.stride` is `0.012` over a
  `thinkInterval` of 10 ticks — `0.00001` map widths a second. Grazing should be
  slow; two in-game months to cross one per cent of the valley is stopped.
  Changing it moves hunting yields and predator contact, so put `DangerProbe` on
  it rather than guessing.

**3. Then the backlog as it stood.** §11.26 wear (`ItemInstance.quality` is
written in `init` and never again anywhere), §11.27 cover and turrets (needs a
height and a solidity on `Landform`, `Flora` and the rocks), §11.29 fuel and
vehicles, §11.30 audio.

---

## Habits this day earned

- **Convert the rate into the player's unit before deciding it is wrong.** Rule
  34. "The figures don't move" was a report about map widths per real second,
  and every number in the argument was written per tick. Nothing in the
  simulation ever complained: the food arrived, the store filled, the tests were
  green. *The only symptom was on the screen.*
- **When one system does the thing right, that is the design.** `SiegeEngine`
  had been on the action grid the whole time and combat was the one thing that
  looked alive. Look for the working instance before inventing an approach.
- **Making a clock finer turns every one-shot into a repeat.** Anything moved
  onto a finer grid has to be sorted into "happens once" and "happens per unit
  time", and the second kind multiplies. Arrivals moved; eating did not.
- **A slow test run is usually the build.** Thirteen minutes of apparent
  test-suite pain was `swift build`; the suites themselves took 3.2 seconds.
  Check `ps` before optimising the thing you just changed.
