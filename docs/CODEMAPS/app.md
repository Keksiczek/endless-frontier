# App — the SwiftUI shell

<!-- Generated 2026-08-13 | 72 sources | ~700 tokens -->

A thin shell over `EndlessFrontierCore`. **It never writes the simulation**
(rule 1).

```
App/Sources/
  EndlessFrontierApp.swift   entry. Opens the session from BOTH .task and
                             scenePhase — guard the operation, not the symptom (rule 29)
  GameViewModel.swift        1415 lines. THE bridge. Owns catch-up (up to 30 days
                             of ticks, off the main actor), selection, journal→toasts
  Theme.swift                15 tokens, fixed dark palette
  AppStrings.swift           bilingual UI chrome
  NotificationScheduler.swift, Diagnostics.swift
  Views/                     ~28 screens and panels, flat
  Views/Settlement/          38 files — the living canvas
```

## The living canvas

`SettlementScreen` → `SettlementCanvasView` (`TimelineView` + `Canvas`) →
`SettlementRenderer.draw`, which layers back to front:

```
ground tiles (SettlementGround)      seeded per (terrainSeed, biome, cell)
landforms    (SettlementLandforms)   ravines, mesas, oases — ground with extent
stone        (SettlementStone)       massifs and blocks
flora shadow (SettlementFlora)       the wood's shadows and its outcrops
crops/piles/sites                    plots, HaulPiles, build sites
── one depth-sorted pass, on the foot each thing stands on ──
  footings   (SettlementRendererLots)      plots and cast shadows, first
  buildings  (SettlementStructures)        walls, roof, wear
  interiors  (SettlementInterior)          under the roof, as it fades
  attachments(SettlementAttachments)       what stands beside and names it
  trees      (SettlementFlora)             one trunk at a time
  people     (SettlementRendererAgents)    figures and crowd marks
light+season (SettlementLight, SettlementSeasons)   day/night, snow
fog of war
```

**One pass, or the illusion does not hold** (`RENDER_25D.md` §3). Drawn as
blocks, a tree in the village was behind every roof and a colonist in front of
every one — whatever the ground said. The sort compares the *foot*: the bottom
of a lot, the point a tree grows at, the ground a person stands on (a rider's
horse, not the saddle). The drawing of a building sits on the bottom edge of its
plot and rises out of it — `SettlementStructures.bodyLift`, the one number the
walls, the room, the furniture and the people at it all read.

**Motion is presentation-only.** `AgentMotion` derives a colonist's position from
`(pawn.id, frame clock)` and the `WalkPath` the engine wrote. Nothing feeds back.

`PawnLook.of(pawn, ageYears:)` — 6 hair × 5 colours × 4 beards × 3 builds ×
3 heights × 5 skin tones, a pure function of `(id, age, genes)`, stored nowhere.
Age shows: hair greys from 42, thins from 58, shoulders come forward from 54.

## Known problems (audit 2026-08-13, §11.25)

| | |
|---|---|
| `SettlementRenderer.swift` | **1969 lines** against a stated max of 800. Seams already marked: scenery (~520), deposits, buildings/glyphs |
| `GameViewModel.swift` 1415, `SettlementStructures.swift` 1003 | also over |
| Light/dark | `colorScheme` appears **zero times**. Fixed dark palette only |
| Reduce motion | `reduceMotion` appears **zero times**, in a continuously animating canvas |
| Dynamic Type | 33 × `.font(.system(size:))` at fixed sizes |
| Colour tokens | 204 hardcoded `Color(red:…)` against 15 `Theme` tokens |
| Layout | 40 files flat in `Views/`; only `Settlement/` is grouped |
| Tests | 6 files for 72 sources |

Accessibility work is deliberately **last** in the current plan.

## App tests

`App/Tests/` — run in the iOS simulator:

```bash
cd App && xcodegen generate     # after adding a file
xcodebuild -project App/EndlessFrontier.xcodeproj -scheme EndlessFrontier \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

The device name goes stale with Xcode; check `xcrun simctl list devices available`.

| Suite | Guards |
|---|---|
| `AgentMotionTests` | a colonist's day is one a person could live |
| `BuildingLookTests` | 62 buildings are not drawn as 8 shapes |
| `SettlementRendererTests` | the canvas shows the colony actually built |
| `SettlementLightTests` | hills come out round on a phone, not vertical stripes (rule 10b) |
| `CrowdTests`, `BattleStagingTests` | crowds at distance, raids play and clear |
| `UIStringsTests` | no panel greets a Czech player in English |
