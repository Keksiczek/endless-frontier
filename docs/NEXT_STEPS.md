# Endless Frontier — What to Build Next

Snapshot (2026-06-02): the Core simulation is deep and heavily tested
(**133 tests**). What exists now:

- **Colonists** with needs, skills (learning by doing), mood, mental breaks,
  health, starvation→death, equipment in 3 slots.
- **Endless hex world**: per-hex procedural generation, frontier that expands as
  you explore, distance-scaled difficulty, dynamic region events.
- **Special sites**: ruins / dungeons / anomalies with risk-reward and loot.
- **RPG layer**: items with rarity, equipment + colony artifacts, **materials +
  crafting (recipes)**, drops scaling with distance.
- **Quests**: multi-stage chains with rewards (items + effects).
- **Systems**: raids & defense, housing & population cap, pollution, tech/era
  progression, cross-era content (24 buildings, 14 techs, ~25 events),
  objectives, resilient saves.
- **App**: SwiftUI dashboard (objectives, quests, colonists, items, crafting,
  research/build) + interactive procedural hex **World map** (pan/zoom,
  expeditions, founding, site interactions), iPad-adaptive.

The systems are rich; the gap now is **presentation, balance, and the breadth of
the world the player acts on.** Priorities:

## Tier 1 — make it look and feel like a game

1. **Real art pass.** Biome tile sprites, rarity-framed item icons, colonist
   portraits, site/marker art. Assets/prompts already drafted
   (`docs/ASSET_SPECIFICATION.md`, `docs/AI_PROMPT_LIBRARY.md`,
   `docs/LEONARDO_EXPLORATION_PROMPTS.md`). Generate (Leonardo / Recraft /
   fal.ai), bundle in an asset catalog, swap the procedural Canvas for sprites
   (keep procedural fallback). Add subtle motion (water, fog, frontier pulse).
2. **Play on device + balance harness.** With this much interplay, balance is
   the main risk. Add a headless auto-play test that runs thousands of ticks and
   charts resources/morale/population/threat, then tune `world-config.json` /
   `map-gen.json`. Run on a real iPad/iPhone to feel pacing.

## Tier 2 — deepen what the player acts on  ✅ DONE

3. ✅ **Colonists in outposts.** Founded outposts arrive with real colonists; the
   app lets you switch settlements and manage each one's people/gear.
4. ✅ **Combat with teeth.** Raids defended by a colonist militia (armed colonists
   fight harder, real casualties).
5. ✅ **Inter-settlement economy.** Trade-route management UI (caravans + the
   isolation-connectivity that keeps outposts stable).
6. ✅ **Tech-tree screen.** Era-grouped tech tree with status/prereqs and research
   selection (its own tab).

Remaining within Tier 2 / next refinements: crafting & building are still
capital-scoped (make them per-selected-settlement); specialised settlements and
caravan-as-pawns; connector lines / graph layout for the tech tree.

## Tier 3 — breadth & long game

7. **Later eras (modern / near-future)** content — ✅ first pass done (2026-06-05):
   the tech tree now runs unbroken from early-industrial through modern into
   near-future (electricity → computing → robotics → fusion → AI → space →
   megastructures), with ~20 new buildings (clean power, automation, data
   centres, arcologies), late-era events (energy crisis, automation unrest, AI
   awakening, orbital signals, climate shift) and two endgame quest chains
   (*The Electric Age*, *Dawn of Tomorrow*) plus a population/expansion chain
   (*A Thriving World*). Era advancement into modern/near-future is now gated on
   the new techs. **Still open**: an end-game/legacy/prestige loop, and balance
   tuning of the new late-game numbers (knowledge costs, building yields).
8. **Repeatable site content**: dungeons you can re-delve at rising difficulty,
   ruins with lore unlocks, anomalies as ongoing event sources.
9. **More RPG**: set bonuses, item upgrading/enchanting — ✅ a modern/future
   crafting tier was added (steel → circuit board → fusion cell feeding
   exosuits, power armour, neural implants, colony artifacts). Still open: set
   bonuses, item upgrading/enchanting, traits that interact with gear.
10. **LLM narrator** (originally Phase 3): lots to narrate now — named
    colonists, their fates, quests, raids, golden ages. Optional, offline-first.

## Tier 4 — product polish

11. Onboarding/tutorial, settings (tick rate, reset, toggles).
12. Local notifications for the "while you were away" summary.
13. Accessibility (VoiceOver, Dynamic Type) and Czech/English localization.
14. Multiple saves + optional iCloud sync; audio & haptics.

## In-settlement colony layer (started 2026-06-05)

The RimWorld-style base layer has its **engine foundation** in place
(`ColonyMap` model + `ColonyBuilder` engine, with tests):

- Each settlement can hold an optional square build grid (`colony: ColonyMap?`,
  backward-compatible — `nil` on old saves and until build mode is opened).
- `ColonyBuilder.place` / `remove` place and demolish buildings on tiles and
  keep the count-based `buildings` economy ledger in sync (the resource loop is
  untouched).
- `ColonyBuilder.assign` / `unassign` put named colonists to work on a specific
  placed building (work kind derived from what the building produces), honouring
  the building's worker cap.

**Still open** (the visible/interactive half): a SwiftUI grid view to see and
edit the layout (tap a tile → build/demolish, tap a colonist → assign), then the
art pass renders sprites on those tiles. Also: connect `ColonyBuilder` through
`GameEngine` + `GameViewModel`, and have `GameWorldFactory` seed a starting
layout from the capital's initial buildings.

## Known debt

- `schemaVersion` exists; write migration steps when field *meaning* changes.
- Balance numbers (pollution, isolation, loot, quest rewards) are first-pass.
- A few costs are hardcoded constants (outpost founding, pawn tuning) that could
  move into config for easier balancing.
