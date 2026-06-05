# Endless Frontier — What to Build Next

Snapshot (2026-06-02): Core sim is deep and well-tested (112 tests). The game
has colonists, an endless hex world, special sites, raids/defense, housing,
pollution, cross-era content, objectives, and resilient saves. A SwiftUI app
drives it with procedural map terrain. Below is the prioritised backlog.

## Tier 1 — highest value next

1. **Play it on a real device.** Build & run on an iPad/iPhone to actually feel
   the loop and the map (the local simulator has been slow). This will surface
   the most important balance/UX issues fast.
2. **Real graphics pass.** The asset specs and AI prompts already exist
   (`docs/ASSET_SPECIFICATION.md`, `docs/AI_PROMPT_LIBRARY.md`,
   `docs/LEONARDO_EXPLORATION_PROMPTS.md`). Generate biome tiles, region-site
   icons and colonist art (Leonardo / Recraft / fal.ai), drop them into an asset
   catalog, and swap the procedural Canvas terrain for sprites (keep procedural
   as fallback). Add light motion (water shimmer, frontier pulse, drifting fog).
3. **Balance pass via a sim harness.** Add a headless "auto-play" test that runs
   thousands of ticks and reports resource/morale/population/threat curves, then
   tune `world-config.json` / `map-gen.json` so a long game neither stalls nor
   runs away. Cheap to add given determinism.

## Tier 2 — deepen the loop

4. **Colonists in outposts.** Pawns currently live only in the capital; effects,
   raids and sites target the capital. Give every settlement real colonists and
   let the player manage them per-settlement.
5. **Quests / story chains.** The `quest` event type exists but is unused. Add
   multi-step directed quests (trigger → objective → reward) for long-term goals
   beyond the live Objectives list.
6. **Local region resources.** `Region.resourceDeposits` is modelled but unused.
   Tie a settlement's production bonuses to the deposits of the region it sits
   in, so *where* you settle matters.
7. **Tech-tree screen.** Visualise the DAG (it's a flat list today) so players
   can plan a research path.

## Tier 3 — breadth & later eras

8. **Modern / near-future content.** Buildings, techs and events for eras 5–6,
   plus an end-game/legacy or prestige loop for the truly long game.
9. **Put special sites to fuller use.** Dungeons as repeatable risk/reward
   delves, ruins as lore unlocks, anomalies as ongoing dynamic-event sources.
10. **LLM narrator (originally Phase 3).** Now there's a lot to narrate (named
    colonists, their fates, raids, golden ages). `LLMNarratorProtocol` +
    `StubNarrator` + a local model; turns event data into a rich chronicle. Ties
    into the personal Home Hub later.

## Tier 4 — product polish

11. **Onboarding / tutorial** and a settings screen (tick rate, new game/reset,
    enable narrator).
12. **Local notifications** for the "while you were away" summary on reopen.
13. **Accessibility & i18n**: finish VoiceOver labels, Dynamic Type, and
    consider Czech/English localization.
14. **Save management**: multiple saves and optional iCloud sync.
15. **Audio & haptics** for key actions and events.

## Known follow-ups / debt

- `schemaVersion` is in place; write actual migration steps when field meaning
  (not just presence) changes.
- Isolation-penalty and pollution curves are first-pass numbers — revisit in the
  balance pass.
- Outpost founding cost is a hardcoded constant; move to `world-config.json` if
  it needs tuning.
