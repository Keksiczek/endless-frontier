# Handoff — 2026-08-05

Branch **`main`**, clean and pushed. Last commit `9f8cc01`.

Tests: **889 Core**, **94 app**.

```bash
swift test --package-path Core
```

```bash
xcodebuild -project App/EndlessFrontier.xcodeproj -scheme EndlessFrontier -destination 'platform=iOS Simulator,name=iPhone 17' test
```

```bash
cd App && xcodegen generate
```

Regenerate the Xcode project after adding any file under `App/Sources`.

---

## Read this first

**This session was cut short deliberately.** Keks gave six pieces of feedback,
one of them was fixed, and he asked for the rest to be written down rather than
half-built. Everything below §2 is *specified, not started*. Nothing is in
flight; the tree is clean.

---

## 1. What shipped today

**`9f8cc01` — a militia of farmers stops looking like a company of swordsmen.**

`SettlementFigures.fightingArms` took a `Bool` (bow or blade), so everybody
without a bow was drawn swinging a bar of iron — including the sixty colonists
who own no weapon at all. `CombatEngine` has always priced them as unarmed
(`baseUnarmedPower`); only the drawing disagreed.

`SettlementFigures.Armament` (`.bow` / `.blade` / `.none`) is now what is
actually in their hands, resolved from `CombatEngine.weaponProfile`. Unarmed
colonists swing the tool of their trade — axe, pick, scythe, hammer — and a
trade with no edge on it fights with fists.

---

## 2. Keks's feedback, still open

In the order I would do it. Each has a diagnosis, not just a wish.

### 2.1 Combat should read as real time, and a hit should be a hit

> *"ať je to prostě real time mapa — bouchne ho a je vidět že ho zasáh a z toho
> krev, ne kaňky barvy všude jako teď"*

The simulation is already right: `SiegeEngine` moves real fighters over real
ground, contact is proximity, and a blow lands on a named person. **The drawing
is what is wrong.** `SettlementBattle` still paints the *aggregate*: a bright
`contact` seam across the whole line, `sparks` at a computed "front", a `hit`
ring, and a `wounded` bar floating over each defender. That is the "kaňky barvy
všude" — colour standing in for events.

What it should be instead, and all of it is available already:

- A blow is a **moment on two specific bodies**. `Siege.fighters` has both
  positions and `SiegeEngine` already writes a `.wound` / `.death` beat with a
  `pawnID`. Draw the impact *between the two figures that are touching*, once,
  and short.
- **Blood belongs on the person and on the ground**, and it should persist.
  `Siege.damage[pawnID]` is the accumulated harm and `Pawn.body.ailments` names
  the part. A splash at the moment of the hit, then a mark that stays on them
  and a stain where they stood. That is what turns a number into an injury.
- **Delete the seam and the floating bars.** The contact band and the
  over-the-head harm bars are both aggregate readouts of a thing that now has
  individuals in it. The bar can stay for the *selected* fighter only.
- Files: `App/Sources/Views/Settlement/SettlementBattle.swift` (`drawLive`,
  `contact`, `sparks`, `hit`, `wounded`). Everything needed is already on
  `Siege`; this is presentation-only, so rule 5 is not at risk.

### 2.2 Nobody does anything because of what they need

> *"stále to nemá tu dynamičnost, že by lidé něco logicky dělali dle potřeb a
> okolí a svého zaměření"*

This is the biggest one and it has a precise cause: **needs are satisfied by
teleportation.** In `PawnEngine.advanceOneTick`, a hungry colonist eats out of
the settlement's store wherever they happen to be standing
(`s.pawns[i].needs.hunger += hungerPerMeal`). Nobody walks to a granary. Warmth
is a passive comfort number — nobody walks to a fire. Rest is handled by
`AgentMotion`'s day cycle, which is *presentation*, so it is a picture of
sleeping rather than sleeping.

So needs exist, and they bite (mood, health, frostbite), but they never *cause a
decision*. That is exactly what "no dynamism" means.

The shape of the fix, reusing what exists:

- `JobKind` already drives movement through `Pawn.currentJob.position`, and
  `AgentMotion` already puts a colonist wherever their job is (fixed yesterday
  — the job now outranks the deposit blob).
- Add `JobKind.eat` and `.warmUp`. A needs pass posts one when a need crosses a
  threshold, targeting the **nearest** food store / hearth-bearing building.
- The need is satisfied **on arrival**, not on the tick. A colony whose granary
  is on the far side of town, or burned, genuinely fails to feed people.
- "Podle svého zaměření" falls out of the same pass: when nothing is biting,
  pick the *nearest* instance of your trade's work rather than a random one.
- Watch: this changes food timing, so measure with `DangerProbe` before and
  after. It is the sort of change that can quietly start a famine.

### 2.3 The steward never sends anybody out

> *"automat neposílá výpravy na prozkoumání mapy"*

`StewardEngine.advanceOneTick` does exactly three things: `chooseResearch`,
`keepMaterialsComing`, `raiseWhatIsShort`. It never explores, never works a POI,
and never sends a `RegionExpedition` — all three of which now exist and work
(`LocalPOIEngine.dispatch`, `RegionExpeditionEngine.dispatch`,
`GameEngine.explore`).

So a player who does not personally tap the world map never sees any of the
expedition content, which is most of what was built this week.

Add a fourth clause to the council: when there are spare hands and no party out,
send one — to the nearest unexplored region first, then to an unworked POI, then
to a site. Same "acts only in the gaps" rule as the rest of `StewardEngine`, so
an explicit choice by the player is never overridden.

### 2.4 Temperature is cosmetic, and it does not match

> *"je tam stav teploty ale ten vůbec nesedí a je spíš kosmetický, stejně tak
> pro lidi"*

Two separate faults:

1. **Temperature is season-only and biome-blind.** `AnimalEngine.temperature`
   is a four-case switch on `Season`, and `biomes.json` has no temperature field
   at all. A tundra valley in January is exactly as cold as a coastal one. The
   world says "tundra" and the body does not agree — that is the "nesedí".
2. **It is nowhere on screen.** The only reading is a "Warmth" need bar on the
   colonist card. There is no temperature anywhere, so the player cannot connect
   the season, the biome, the roof and the coat to the number. `ComfortEngine`
   computes all four terms and shows none of them.

Fix: a `temperature_shift` on the biome, one shared
`temperature(season:biome:)` used by **both** people and animals (rule 8 — it is
one number), a reading in the status strip, and a line on the colonist card that
says *why*: the day is −22, your roof is worth 26, your coat 11.

It already bites for the roofless (`freezingBelow` 18 against a housed warmth of
~40), so this is about making it honest and legible, not about making it hurt
more. A tundra shift would make a hard winter dangerous even indoors, which is
the point of choosing a tundra.

### 2.5 The pace

> *"možná snížit tempo hry potom"*

Deliberately last: pace should be judged once the above are in, because most of
what makes it feel fast is that events resolve without a middle. `WorldConfig`
carries the tick rate; slowing it is a one-line change and a large balance
change, so measure with `DangerProbe` after, not before.

---

## 3. How the world measures right now

`DangerProbe` is the instrument, off unless asked:

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

Run it before and after anything that touches a combat, wildlife, diplomacy,
food or needs number. It has caught three regressions no unit test would have.

---

## 4. Also still open, from before

- **Events happen nowhere, to nobody.** 40 of 71 never name a building, a place
  or a colonist, and every hook exists (`WorldQuery`, `EffectApplier`). Cheapest
  large win left.
- **Old English content** — events, buildings, techs are English-only.
  `LocalizedText` is in place; this is a translation pass.
- **Fields and herb beds are still places, not things.** The wood, the rock and
  the beasts are entities; `field` and `herbs` are still `ResourceNode` blobs.
  Last of "everything is blocks or pawns".
- **Births do not keep pace; the era stops at `ancient`.** Two thirds of the
  tech tree is unreachable in practice. Measure before tuning.
- Battle has **no sound and no haptics**.
- The world-map `SiteOutcome.narrative` is a plain `String`, not
  `LocalizedText` — the one journal line that cannot be Czech.

---

## 5. Things that will bite you

1. **Never seed an RNG from `hashValue`** — Swift seeds its hasher per process,
   so it replays differently every launch and silently breaks determinism.
   Derive from the UUID's bytes (`PlagueEngine.seed`, `BanditEngine.seed`).
2. **Every new field on a saved type is `decodeIfPresent` with a default**, with
   a "a save written before this existed still loads" test.
3. **Two numbers for one thing is the recurring design bug** — `housing` vs
   beds, `span` vs `colonySpan`, the muster line in two files. Derive the second
   one instead of writing it.
4. **The recurring bug shape, six times running:** a system whose effect cannot
   reach the thing it is aimed at. When something feels flat, ask *what rate is
   supposed to move this, and can it get there?* Rules 6, 12 and 13 in
   `BACKLOG.md`.
5. **Check the drawing before rebuilding the system.** Yesterday's "the entity
   layer feels fake" was three lines of ordering in `AgentMotion`, not a design
   problem. §2.1 above is the same shape.
6. Keks's Mac is an **8 GB Intel** machine; `signal 9` in the asset-catalog step
   is memory pressure, not the repo. Simulator is **iPhone 17**.

---

## 6. Where to look

| For | Read |
|---|---|
| Everything ever asked for | `docs/BACKLOG.md` |
| The 13 rules a change must not break | `docs/BACKLOG.md` § "Rules" |
| Systems and formulas | `docs/DESIGN.md` |
| Footprints, lots, pawn-like animals | `docs/RIMWORLD_LAYER.md` |
| Layer separation | `docs/architecture/LAYERS.md` |
| Whether the world is dangerous | `DangerProbe`, `EF_PROBE=1` |
