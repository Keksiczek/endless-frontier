# Handoff — 2026-08-22, evening

<!-- For a chat starting cold. Read CLAUDE.md, then docs/RULES.md (87 rules),
     then this. The morning's handoff is docs/HANDOFF-2026-08-22.md; its §4
     list is now finished, and §5 (bandits) is built. -->

Everything below is **measured, not remembered**. Every number comes from a
probe or a diag still in the tree.

| | |
|---|---|
| Last pushed | `5e0c7c6` |
| Core tests | green on every suite touched, including the two perf guards re-run alone |
| App tests | **165 in 26 suites**, green |
| iOS build | green |

---

## 1. What shipped, in three commits

### `434d781` — an assembly of people who have lived somewhere

*"Sněm by mohl být dynamický, že by lidé volili dle svých vlastností,
zkušeností, názorů."*

`AssemblyEngine` weighs six terms per adult: **nature** (the law's `vote_bias`
against genes, read against the colony's own spread), **standing**, **trade**
(`trade_favour`, new in all 30 laws), **experience**, **hardship**,
**household**. Experience is not a seventh opinion — it is how firmly the
others are held, so a colony's politics change as it ages.

The motion carries its ten loudest voices into the save with the term that
moved each of them, and `CouncilScreen` prints them.

Measured (`EF_DIAG=1 … ZZAssemblyDiag`, colony of 69 at year 50): **no law
unanimous**, rooms run 20 %–69 % in favour, and the reasons differ by law —
`tithe` is ten voices of standing, `forest_protection` five of experience and
one of trade.

Three faults found on the way, now rules 85–87:

- reading nature absolutely made a settled colony vote as one body;
- `terms.values.reduce(0, +)` sums a **dictionary**, whose order comes from a
  per-process hash seed — one ulp of rounding flipped votes on a replay;
- `PawnNeeds.hunger` is **satiety**, and the assembly counted full bellies as
  suffering (the test agreed with it, and passed for the wrong reason).

### `6d6f680` — outlaws who live somewhere, and a store you can see into

*"K banditům napiš, aby byli víc různorodí — třeba chodili ze základen na
mapě, co nejsou žádná frakce."*

`OutlawCamp` + `OutlawCampEngine`: three camps on the map from tick 0, each of
a **kind** (`deserters` / `starving` / `hold`) that decides their arms era,
how many bodies the same weight is drawn as, whether there is a fence, and how
fast they fatten. A camp grows while nobody troubles it, sends warbands on the
bearing of its own hex, keeps what it carries off, and can be walked into and
burned out — the party fights it through `SiteEncounter`, and sacking it
returns the plunder. Broken for a season, never abolished. Not a faction.

`WorldState.camps` is encoded explicitly; migration **3 → 4** founds camps in
a world that already existed (verified on the live save: `schemaVersion 4`,
three camps, three hexes flipped to `outlaw_camp`).

Two measurement faults, both worth remembering:

- the diag counted `settlement.siege`, which exists only while a fight runs —
  it reported **14 raids in two centuries** for a colony that had **127**.
  `BattleLog.attackerCampID` now carries who attacked into the record.
- `temptation` read the stores as a **share of capacity**, which measures the
  colony's *buildings*: 6 280 food behind granaries for 44 300 read as 14 %
  full, so building a warehouse made the same grain invisible to outlaws.

Measured after (`ZZOutlawDiag`, 200 years): **127 raids — camps 7, peoples 63,
the wild 57**; strongest camp 178 (was 104 before the ceiling grew with the
country). **Outlaws are still the rarest of the three threats by a factor of
nine** — see §3.

Also in this commit: a store's floor shows what is in it
(`SettlementRenderer.stock`), and a farm's lot is field rather than swept yard.

### `5e0c7c6` — a valley you can point at

*"Vše drawn je there, ale pak na věci nejde klikat, vybírat je k akci."*

`Designation`: marking a **thing**, never ordering a person. A marked tree is
felled before the biggest one (and before the workable-size filter), a marked
seam broken before the softest, a marked heap fetched however far, a marked
beast taken before any other **in reach**. `DesignationEngine.prune` runs every
tick so a mark never outlives its thing.

App: `WorkOrderCard` on a tapped tree/rock/heap — what it is, what will be
done, and how many hands hold that trade; the same button on a beast's card;
every standing mark drawn on the ground (`SettlementMarks`) from the list the
engines read.

---

## 2. Verified, and how

- `swift test --package-path Core --filter "DesignationTests|HaulTests|JobTests|LivingLandTests|HuntTests|WildlifeTests"` — 88 in 9 suites.
- `--filter "OutlawTests|BanditTests|SaveMigrationTests|SaveCompatTests"` — 47 in 5.
- `--filter "FarmTests|OutlawTests|BattleTests|SiegeTests|BanditTests"` — 62 in 4.
- App: 165 in 26 suites (`xcodebuild … test`).
- **The two perf tests are load-sensitive, not broken.** Running the full Core
  suite beside a two-hundred-year diag put the machine at a load average of
  22, and `TribeCampTests` ("deriving is cheap", 150 ms budget) and
  `OfflineCatchUpTests` ("no O(n²) regression", 4.5× budget) both failed. With
  the simulators shut down and nothing else running, **both pass**:
  `TribeCampTests` 11/11, `OfflineCatchUpTests` 3/3 in 889 s.
  **Do not run a probe and the suite at once on this machine** — you will
  measure the load, not the code.

---

## 3. What is open, in the order I would take it

1. **Research income.** `ZZCouncilDiag` measured knowledge at 120 against a cap
   that reaches ten thousand. Scholars *do* produce (`WorkKind.research →
   .knowledge` in `PawnEngine`), so the question is not "is it zero" but "is a
   tech ever payable" — that wants a probe printing knowledge banked per year
   against the cheapest unresearched tech before anybody tunes a number
   (rule 23).
2. **Outlaws are the rarest threat by nine to one** (7 camp raids against 63
   from peoples and 57 from the wild, in two centuries). The rate is
   `BanditEngine.baseChance × temptation × (1 − watchfulness)`, and
   `watchfulness` caps at 0.85 — a walled, garrisoned colony is nearly immune.
   Decide the cadence you want *first* (one raid a decade? a generation?), then
   set the number against the distribution.
3. **A camp's loot stayed at zero for two centuries** in the diag, because a
   colony of 232 with a wall repels everything — so `strengthPerLoot`, the term
   that was meant to make a colony that keeps paying feed the people robbing
   it, never engaged. It is right that a strong colony is not robbed; it means
   the loop is only visible to a *weak* one, and nobody has measured that case.
4. **Tribes, stage two** — the same engines running on a tribe's settlement.
   Stage one deliberately adds nothing to the tick; stage two is a second
   simulation per people and wants measuring first (`ZZStewardProbe` shape).
5. The rest of `docs/BACKLOG.md` — §3.6, more events that happen *somewhere* to
   *someone*, is the one with content left in it.

---

## 4. How to measure anything here

```bash
EF_DIAG=1  swift test --package-path Core --filter ZZAssemblyDiag   # ~4 min
EF_DIAG=1  swift test --package-path Core --filter ZZOutlawDiag     # ~30 min
EF_DIAG=1  swift test --package-path Core --filter ZZBattleDiag     # ~1 min
EF_DIAG=1  swift test --package-path Core --filter ZZCouncilDiag    # ~20 min
EF_PROBE=1 swift test --package-path Core --filter DangerProbe
```

**One run at a time.** Two SwiftPM runs on one scratch path queue silently, and
two runs on *different* paths starve each other — §2's perf failures were
exactly that.

**Disk**: each `--scratch-path` is ~370 MB. Delete it when the run is done.
