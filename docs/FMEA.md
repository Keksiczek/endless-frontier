# FMEA — symptom → cause → where

Organised by **what you are staring at**, so it is reachable *before* the theory
rather than quoted after it. [`RULES.md`](RULES.md) is the same knowledge
organised by lesson, and the [codemaps](CODEMAPS/) by place; this is the index
into both by symptom.

**Read the section that matches the symptom before forming a theory.** Nearly
every row here cost a session at least once.

Every `Where` cell names a real file and a real symbol. `make verify-docs`
fails when one stops resolving — a stale `Where` cell is a broken document,
not an out-of-date one.

---

## §A — a build, a test or the toolchain

| Symptom | Cause | Where |
|---|---|---|
| A file you added is not in the app target | `EndlessFrontier.xcodeproj` is generated — run `xcodegen generate` in `App/` | `App/project.yml` · `sources` |
| `xcodebuild` fails naming a destination that does not exist | **only `iPhone 17` is installed on this host**; the name goes stale with Xcode | `Makefile` · `SIM` |
| The Core suite takes ~18 minutes and you only changed one engine | that is the whole suite; filter with `swift test --filter` | `Makefile` · `test-filter` |
| `make verify-docs` fails on a document you did not edit | a count in a living document is now false because the *tree* changed — fix the doc, that is the check working | `scripts/verify-docs.py` · `LIVING_DOCS` |
| A new document fails the class check | every doc is a living document or a record; say which | `scripts/verify-docs.py` · `RECORD_FILES` |
| A test build fails on a file you did not touch | you edited a source file *while* its build was running (rule 70) | `docs/RULES.md` · `Editing a source file while its test build is running` |
| A new content file loads in tests and not in the app | resources are declared per target in the package manifest | `Core/Package.swift` · `resources` |
| Two measurements and you cannot tell which change moved the number | you changed two things between probe runs (rule 72) | `docs/RULES.md` · `Two changes, one measurement` |

## §B — a mechanic exists and never fires

The commonest failure in this project: **a threshold beyond the reach of the
rate meant to cross it** (rule 6). Do the arithmetic before rewriting the
mechanic.

| Symptom | Cause | Where |
|---|---|---|
| A mechanic has never fired in a 200-year run | threshold unreachable by its own rate — say the rate out loud times `ticksPerYear` first (rules 6, 24) | `Core/Sources/EndlessFrontierCore/Data/WorldConfig.swift` · `upkeepRateOfCost` |
| A per-tick rate that "reads small" is ruinous per year | a per-tick rate is a per-year rate × 60 (rule 24) | `Core/Sources/EndlessFrontierCore/Data/WorldConfig.swift` · `ticksPerYear` |
| A threat came at a colony of 5 exactly as at a colony of 400 | the danger does not scale with what it threatens (rule 12) — measure with `DangerProbe` | `Core/Tests/EndlessFrontierCoreTests/DangerProbe.swift` · `DangerProbe` |
| A build-up (grudge, tension, war) never starts | every term of the loop is inside the loop; it needs an input from outside (rule 13) | `Core/Sources/EndlessFrontierCore/Engine/DiplomacyEngine.swift` · `grudge` |
| A policy or standing order changes nothing in an established colony | the assigner only touches the idle, and nobody is idle past decade one (rules 9c, 17) | `Core/Sources/EndlessFrontierCore/Engine/LaborEngine.swift` · `assignIdleAdults` |
| A trade has zero members and never gains one | zero × anything is zero — `rebalance` is the hand that has to reach it (rule 17) | `Core/Sources/EndlessFrontierCore/Engine/LaborEngine.swift` · `rebalance` |
| Bonds, marriages, meetings all stop as the colony grows | a linear rate spread over a quadratic opportunity space (rule 20) | `Core/Sources/EndlessFrontierCore/Engine/SocialEngine.swift` · `SocialEngine` |
| A bank saves for ever and never buys | the bank is capped at the cheapest batch while the selector reaches for the dearest (rule 21) | `Core/Sources/EndlessFrontierCore/Engine/CookingEngine.swift` · `CookingEngine` |
| An event's effect is felt for exactly one tick | it was written into a field the engine recomputes; land it in a term the derivation reads (rule 26) | `Core/Sources/EndlessFrontierCore/Models/Pawn.swift` · `moodShift` |
| An option list comes back empty and the obvious reading is wrong | ask *why* it is empty before believing it (rule 28) | `Core/Sources/EndlessFrontierCore/Engine/StewardEngine.swift` · `buildableHere` |
| Research finishes the tree decades early | a DAG orders things, it does not pace them (rule 88) | `Core/Sources/EndlessFrontierCore/Engine/TechEngine.swift` · `TechEngine` |
| A standing order in a queue never gets its turn again | a queue sorted by age holds a place for ever; shares allocated once are held for ever (rules 83, 102) | `Core/Sources/EndlessFrontierCore/Engine/CraftingEngine.swift` · `CraftingEngine` |

## §C — the colony died, or stopped growing

| Symptom | Cause | Where |
|---|---|---|
| Colonists starved beside a full granary | a "not worth the walk" rule applied to a survival need (rule 22) | `Core/Sources/EndlessFrontierCore/Engine/ErrandEngine.swift` · `furthestWorthGoing` |
| The colony peaks small and dies with an empty store | births are not the size knob — housing is (rule 19) | `Core/Sources/EndlessFrontierCore/Engine/PopulationEngine.swift` · `headroomFactor` |
| Every material is at 1 and the council builds nothing | upkeep scaling with everything you own against an income that does not (rules 24, 25) | `Core/Sources/EndlessFrontierCore/Engine/ResourceLoop.swift` · `upkeepRateOfCost` |
| No wood, therefore no crafting, no power, nothing modern | the felling rate is pinned by a conserving rule; loggers must replant (rule 95) | `Core/Sources/EndlessFrontierCore/Engine/FloraEngine.swift` · `seedStand` |
| The colony bleeds people as the map is explored | a per-entity roll with no ceiling on the entity count (rule 14) | `Core/Sources/EndlessFrontierCore/Engine/DiplomacyEngine.swift` · `defect` |
| The council explores for ever and builds nothing | an `if canAfford` above the fix became a new bug once the store filled (rule 27) | `Core/Sources/EndlessFrontierCore/Engine/StewardEngine.swift` · `sendSomebodyOut` |
| Storage or beds are always just behind demand | capacity built off a stock level instead of a rate against a need (rule 16) | `Core/Sources/EndlessFrontierCore/Engine/StewardEngine.swift` · `plotsWanted` |
| Growth is measured and looks wrong | run the probe rather than reading a number in prose | `Core/Tests/EndlessFrontierCoreTests/GrowthProbe.swift` · `GrowthProbe` |

## §D — content is loaded, and silently not there

| Symptom | Cause | Where |
|---|---|---|
| Loot, equipment or a whole table is empty with no error | `try?` on a whole-file decode — one bad line empties the table (rules 9b, 42) | `Core/Sources/EndlessFrontierCore/Data/GameDataRegistry.swift` · `bundled` |
| An item exists and can never be equipped | an optional field nothing reads — `equipSlot` was `nil` on 73 items (rule 94) | `Core/Sources/EndlessFrontierCore/Models/Item.swift` · `equipSlot` |
| A generated effect is accepted and does nothing | the vocabulary check knows the words, not their fields (rules 41, 61, 62) | `Core/Tests/EndlessFrontierCoreTests/ContentTests.swift` · `ContentIntegrityTests` |
| A recipe can never be made | it needs a bench the colony has no trade for, or a material that lands in a catch-all (rules 58, 96) | `Core/Sources/EndlessFrontierCore/Engine/QuartermasterEngine.swift` · `lootPool` |
| A motion clip loads and is never seen | `serves_activities` / `serves_work` missing, so no colonist may be given it (rule 47) | `Core/Sources/EndlessFrontierCore/Resources/GameData/motions.json` · `serves_activities` |
| New text ships English-only | engine-written sentences are outside the content guard (rule 91) | `Core/Tests/EndlessFrontierCoreTests/ContentTests.swift` · `Czech` |
| "It builds and ContentTests pass" and the registry still did not load it | the build proves nothing about the decoder (rule 43) | `Core/Sources/EndlessFrontierCore/Data/GameDataRegistry.swift` · `decode` |
| A field survives a round-trip test and is empty in the save | the test round-tripped an empty field (rules 37, 73) | `Core/Sources/EndlessFrontierCore/Models/Settlement.swift` · `CodingKeys` |

## §E — the canvas shows the wrong thing

| Symptom | Cause | Where |
|---|---|---|
| The valley is drawn as vertical stripes or brickwork | the map is not square; a normalised field needs the `aspect` (rules 10, 10b) | `App/Sources/Views/Settlement/SettlementLight.swift` · `slopeLight` |
| A bright line along every tile edge in snow or light | ground tiles overlap by a hair, so every layer over them must be opaque (rule 9) | `App/Sources/Views/Settlement/SettlementGround.swift` · `Tone` |
| The newest buildings are the ones missing from the map | a cull by array order drops the newest (rule 63) | `App/Sources/Views/Settlement/SettlementRendererLayout.swift` · `colonySpan` |
| Two buildings of different kinds share one drawing | the difference has to be derived from the definition, not from a shape list (rule 64) | `App/Sources/Views/Settlement/StructureVariant.swift` · `StructureVariant` |
| A colonist "is inside" in one panel and outside in another | two readers of the same colonist answering from different fields (rule 18) | `App/Sources/Views/Settlement/AgentMotion.swift` · `AgentMotion` |
| A battle reads as nothing happening | playback pace is not simulation pace (rule 11) | `App/Sources/Views/Settlement/SettlementBattle.swift` · `playSeconds` |
| Walking looks wrong after a "correct" tuning | the rate was per tick and the eye judges per real second (rule 34) | `Core/Sources/EndlessFrontierCore/Data/WorldConfig.swift` · `realSecondsPerTick` |
| A system exists in the sim and the player can never see it | the recurring shape — grep for it before rebuilding anything | `docs/RULES.md` · `A surface only reachable while the app is in the foreground` |

## §F — you are about to write code

| Situation | Do this instead | Where |
|---|---|---|
| Adding anything O(entities) to the tick | put it on a cadence of 10 like everything else (rule 4) | `Core/Sources/EndlessFrontierCore/Engine/LaborEngine.swift` · `staffingInterval` |
| Creating an entity | give it a **stable id** — a random `UUID()` breaks determinism silently (rule 2) | `Core/Sources/EndlessFrontierCore/Engine/SeededRNG.swift` · `SeededRNG` |
| Adding a field to a saved model | make it optional with a sane default, decode-if-present (rule 3) | `Core/Sources/EndlessFrontierCore/Persistence/SaveMigrator.swift` · `SaveMigrator` |
| Writing a threshold | set it from the field's own distribution, and prefer a definition needing no magnitude (rule 23) | `Core/Tests/EndlessFrontierCoreTests/MapProbe.swift` · `MapProbe` |
| Adding content | CZ + EN in the same change, never deferred (rule 7) | `Core/Sources/EndlessFrontierCore/Data/LocalizedText.swift` · `LocalizedText` |
| Adding a drawing | ask what in the Core it is a picture *of*; if nothing, that is the bug (rule 18) | `docs/RULES.md` · `What is in the simulation is on the canvas` |
| Two numbers that must agree | make them one number in one place (rules 8, 35) | `Core/Sources/EndlessFrontierCore/Models/Job.swift` · `colonySpan` |
| Handing a player verb to the council | price it as a standing order — cadence, surplus bar, workforce cap (rule 15) | `Core/Sources/EndlessFrontierCore/Engine/StewardEngine.swift` · `StewardEngine` |
| Fixing an affordability bug | re-read every `if canAfford` above it — they have all changed meaning (rules 27, 31) | `Core/Sources/EndlessFrontierCore/Engine/StewardEngine.swift` · `sendSomebodyOut` |
| Adding a mechanic you expect to fire | write the test named for its **reachability**, not its behaviour (rule 6) | `Core/Tests/EndlessFrontierCoreTests/BalanceTests.swift` · `BalanceTests` |

## §G — you are about to trust a document

| Document | Trust it for | Not for |
|---|---|---|
| `CLAUDE.md` | the rules and the layout | current counts |
| `docs/RULES.md` | every lesson that cost a session | what is built today |
| `docs/CODEMAPS/` | where a thing lives, and what owns it | counts, timings, state |
| `docs/DESIGN.md` | what the systems are *for* | whether they exist |
| `docs/BACKLOG.md` | what was measured, and when | anything above its newest section |
| the newest handoff in `docs/handoffs/` | what the last session measured and left open | earlier sessions' numbers |
| `docs/handoffs/README.md` | what each past session is safe for | the state — only the newest handoff has that |
| `docs/TEST-BASELINE.md`, newest row | the test counts | rows below it — suites split and merge |
| `docs/ROADMAP.md`, `NEXT_STEPS.md` | **history only** — do not plan from them | the plan |
| any number in prose | the day it was written | today — run a probe |
| any commit message | intent | the diff — check it |
