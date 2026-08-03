# Handoff — 2026-08-02

Branch **`main`**, working tree clean, everything pushed.

Tests: **836 Core**, **93 app**, both green.
`swift test --package-path Core` takes ~250 s cold, ~50 s warm. App suite ~3 s once built.

---

## 0. Read this first — the next chat's actual job

Keks played it and gave three pieces of feedback. They are the brief:

1. **It is too easy. There is almost no challenge.**
2. **Combat does not aim/handle well, and the rounds feel strange.**
3. **Real-time walking would be better** — and it would fit the rest of the
   game: *I go somewhere and do something. The enemy comes, we go and get
   ready, and then we kill him if we can.*

Point 3 is a **design pivot on the combat layer that was built this session**.
§4 says what that costs honestly, and what of the current work survives it.
Do not treat the round-based siege as settled — it is one iteration old and
the player has already said the shape is wrong.

---

## 1. Where to look

| For | Read |
|---|---|
| Everything ever asked for, and its state | `docs/BACKLOG.md` |
| The rules that keep getting broken | `docs/BACKLOG.md` §"Rules" (now 11) |
| The RimWorld-leaning layer | `docs/RIMWORLD_LAYER.md` |
| Layer separation | `docs/architecture/LAYERS.md`, `CLAUDE.md` |

---

## 2. What shipped this session

Eight commits, `44063fb` … `2a6b7db`.

**The valley stopped being wrong to look at.** Rule 10 was fixed for the ground
*cover* and never for the **relief the light reads**, so the noise stayed round
in `(u, v)`, came out four times stretched in pixels, and the whole map was lit
in vertical stripes — for as long as it had been lit at all. Also: the day was
2.5 real minutes so shadows swung while you watched them; a hut threw a shadow
three times its height; building lots were 0.6-alpha slabs that read as holes
punched in the map *and* ruled a grid inside every yard (rule 9); and the night
wash was the most saturated layer in the stack, which turned autumn purple
every single dusk.

**A raid became a fight you stand in.** `Siege` + `SiegeEngine`: live state on
the settlement, the player's posture and withdrawals recorded *on it* so they
are inputs rather than a hole in determinism, and a step fought once by whoever
reaches it first — so the app can drive it fast while somebody watches, and
`ActionLoop` finishes it identically if nobody does. Wolves open one too.

**Making things became work.** `WorkKind.crafting` did not exist: a recipe named
a workshop, the colony had to *have* a workshop, and no colonist could ever be a
person who worked in one. Now `CraftOrder` is a queue, crafters are a staffed
trade, one bench per kind of shop, and `ItemQuality` means a master's sword is
not an apprentice's.

**The world started advancing on its own** — see §3, it is the big one.

**Czech.** 196 strings: 48 events with their choices, every tech description,
seven quests with stages, six biomes, and the five resource words that were
`rawValue.capitalized` (so a Czech game said "Food" and "Materials" mid-sentence
in every panel).

Real bugs found in passing, each of them the project's recurring shape — *a
mechanic nothing can reach*:

- **Quarried rock produced nothing.** Wood falls at the stump and hewn stone at
  the face, but a pick into an *outcrop* took only `.map` back from
  `FloraEngine.quarry` and dropped the yield. On any valley with no massif —
  every coast, most plains — four miners ground nine clay banks to nothing over
  four hundred ticks and banked not one unit. Clay is the only route to the
  kiln, so that whole branch was unreachable by working for it.
- **Predators were never seeded.** `isPredator` is honoured everywhere and not
  one wolf, fox or bear had ever been put on a map.
- **Trees only grew inside forest *deposits*** — so plains, coast and tundra had
  literally no trees.
- **Founding buildings had random UUIDs**, so two worlds from one seed differed.

---

## 3. The frozen world — what was found, and what fixed it

Measured, fresh world, twelve thousand ticks (200 in-game years), untouched:

```
t=1000    pop=27  beds=30  cap=500  buildings=3  building=0  techs=0  era=earlySettlement
t=12000   pop=26  beds=30  cap=500  buildings=3  building=0  techs=0  era=earlySettlement
```

Three buildings, no construction ever started, no tech ever researched, still in
the first era, all four stores pinned at the cap the entire time. The colony was
not dying — it was **frozen**, and every link of the chain was reachable only
from the UI:

- `activeResearch` is set nowhere but the tech screen → no tech → no era → no
  building unlocked.
- `GameEngine.build` is called nowhere but the build bar → not even the
  *unlocked* buildings were raised, including the hut that lifts the housing
  ceiling and the granary that lifts the storage cap.
- `CraftingEngine.place` is called nowhere but the crafting panel → the
  `timber_bundle` that half the early buildings ask for was never made.

`StewardEngine` closes it. The council studies the cheapest reachable tech,
keeps a standing order for building materials, and raises what the colony is
short of — beds, then store, then food, then breadth out of real surplus. It
acts **only in the gaps**, so an explicit player choice is never touched, and
`WorldState.stewardEnabled` switches it off entirely.

After: pop 5 → 80, two eras, 31 techs, ~48 buildings by t=5000, then a plateau
where materials become the binding constraint.

**Answered while doing it:** a granary raises the cap for **every** resource,
not just food (`storage: 250`, summed by `ResourceLoop.storageCapacity`, which
rewrites `settlement.storageCapacity` every tick). The mechanism was always
correct — a granary just never got built.

---

## 4. The brief: challenge, and real-time combat

### 4.1 Why there is no challenge — measured, not guessed

Same 12,000-tick run, counting everything dangerous:

```
battles = 26        live-siege ticks = 26        tribes = 6
deaths  = { old_age: 106 }          ← every single one
population 42 · food 2500/2500 · morale 74
colonists hurt at the end = 0 · broken = 0
```

Twenty-six fights across two centuries and **not one person died of anything but
old age**, with nobody even carrying a wound at the end. Food sat at the cap the
whole time. That is the whole of "no challenge", and it is four separate things:

1. **Nothing kills.** No battle deaths, no starvation, no cold, no beast.
   Wounds heal faster than they land.
2. **Fights are over instantly.** 26 battles produced 26 tick-samples with a
   siege live — each fight ends inside roughly *one world tick*, because a
   forty-person militia vastly outmatches a wolf pack of strength ~10. Even at
   1.4 s a step you will miss it unless you happen to be looking.
3. **Food is never scarce.** It is pinned at the cap for two hundred years, so
   the one resource that has ever been a real sink in this game is not one.
4. **The wall is nearly free.** `SiegeEngine.wallShare` caps at 0.85 and a
   modest palisade already turns most of a raid aside.

Levers, all in one place each: `SiegeEngine` (`linePerStep`,
`attackerDamagePerStrength`, `fortificationHalfPoint`, `fortificationCeiling`),
`WildlifeEngine.attackChancePerPressure`, `DiplomacyEngine.warChance` /
`warStanding` (a yearly roll needing standing < −30), and
`MedicineEngine` for how fast wounds close.

**Do not just multiply the numbers.** The honest fix is that a fight has to be
*survivable but expensive* — people should come out of it hurt, and being hurt
should cost the colony work. The wound and body-part system already exists and
currently has nothing to do.

### 4.2 What "real-time walking" costs, honestly

The current fight is **round-based on the action-step grid**: `Siege.stepsTotal`
= 24 steps, four named phases, each raider abstractly paired with the colonist
opposite. `SettlementBattle` draws that pairing; the figures do not really walk
to each other, which is exactly why "the rounds feel strange".

The pivot is smaller than it sounds, but it crosses one hard line:

- **Keep:** the siege as live saved state; orders as recorded inputs; a step
  fought once by whoever reaches it first; offline resolution identical to
  watched resolution. All four of those are what make a live battle safe in a
  deterministic offline-first game, and they survive the pivot unchanged.
- **Change:** the *unit*. Instead of 24 exchanges, every combatant needs a
  **position that advances per step**, and contact becomes proximity rather than
  a round index. Steps get finer and faster (the app already drives them).
- **The line it crosses:** colonists' positions today live in `AgentMotion`,
  which is **presentation only** — CLAUDE.md rule 5, and it is load-bearing.
  Real-time combat means fighters' positions must move **into the Core**. That
  is a real architectural change and it should be made deliberately, not by
  letting the renderer start writing state.

  The precedent already exists and should be followed: `Pawn.currentJob` carries
  a `position`, and `HaulEngine` gives a hauler a real `haulPosition` the Core
  owns. A `Siege` fighter with a Core-owned position is the same shape.

- **What that buys, in the player's words:** the enemy appears at the edge of
  the map and *walks in*, so there is time to prepare. You can send people to
  meet them or pull them back behind the wall. Positions make aiming mean
  something, which is the other half of the complaint.

Suggested order for the next chat:

1. Move fighter positions into the Core (`Siege.Combatant` with a `LocalPoint`
   advanced per action step). Keep the existing phases as *emergent* — approach
   is "not in contact yet" rather than "step < 4".
2. Let a tap during a siege give a colonist a **move order** and a **target**.
   Recorded on the siege, exactly as posture is, so determinism holds.
3. Only then retune difficulty (§4.1). Balancing the old shape would be work
   thrown away.

---

## 5. Rules this codebase has sprung, newest first

Full list in `BACKLOG.md` §"Rules". The ones added this session:

11. **Playback pace is not simulation pace.** A tick is a real minute and a
    battle was eight rounds; played at the tick's own speed that is one exchange
    every 7.5 s, which reads as nothing happening. A *record* may be replayed at
    whatever speed makes it legible (`SettlementBattle.playSeconds`).
10b. **The map is not square, and every field drawn over it has to know.** Rule
    10 was fixed for ground cover and not for the relief, so the valley went
    back to stripes the moment it was lit.

And two traps found while balancing the steward, both now guarded by tests:

- **A reserve as a share of capacity is a trap.** Keeping 35 % of the warehouse
  back looks reasonable — but granaries multiply the cap, the reserve grows with
  it, and a colony whose income never changed can suddenly never afford anything
  again. Measured: capacity 500 → 2750 and the town stopped building for ten
  thousand ticks. Tie a reserve to the **cost**, never to the warehouse.
- **Overlapping tiles make draw *order* load-bearing.** Once ground tiles grow
  into each other by a third rather than a hair, whichever tone is filled last
  decides what the ground looks like — and Swift dictionary iteration order is
  not stable, so the map would reshuffle its own edges every frame. Sorted by
  `SettlementGround.Tone.order`.

---

## 6. Still open, beyond the brief

- **Births do not keep pace with old age.** With beds and food no longer
  binding, population peaks near 80 and drifts back to 40 while the only deaths
  are old age. Always true; simply unreachable behind the frozen ceiling.
- **Era stops at `ancient`** with the whole tech tree researched — the later era
  milestones want population or settlement counts the colony never reaches.
- **`BACKLOG` 3.6** — 40 of 71 events never name a building, a place or a
  colonist. All the hooks exist now.
- **Quests read as empty** to the player. They are long arcs buried in a detail
  sheet; the new *Where things stand* card on the Council screen is the
  short-horizon answer, and quests probably want the same treatment.
- Battle has no sound and no haptics.

---

## 7. Commands

```bash
swift test --package-path Core
```

```bash
xcodebuild -project App/EndlessFrontier.xcodeproj -scheme EndlessFrontier -destination 'platform=iOS Simulator,name=iPhone 17' test
```

```bash
cd App && xcodegen generate
```

Regenerate the Xcode project after adding any file under `App/Sources` —
a new file that is not in the target fails as `cannot find type … in scope`.

Simulator installed: **iPhone 17** (not 16). Keks's Mac is an 8 GB Intel
machine: `actool`, `ibtool` and `momc` were SIGKILLed for about an hour under
memory pressure mid-session and then recovered on their own. If a build fails
with `terminated with uncaught signal 9` in the asset-catalog step, that is the
host, not the repo — free memory or reboot.
