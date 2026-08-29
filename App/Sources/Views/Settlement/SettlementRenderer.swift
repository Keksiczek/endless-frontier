import SwiftUI
import EndlessFrontierCore

/// Draws a settlement's living world as line-art into a `Canvas`
/// `GraphicsContext`. Pure and layered — each concern is its own function, so
/// new scenery or building types slot in without disturbing the rest.
///
/// Coordinates arrive normalised (0…1) from the model and are mapped to pixels
/// here, so the same scene renders crisp at any size. The world is
/// season-aware: ground, trees, fields and the river all change with the
/// calendar instead of sitting in one eternal grey-green.
enum SettlementRenderer {
    /// Cap on drawn colonists — keeps a boom-town calm and the frame cheap.
    /// Everyone still exists in the sim; this only thins the *visible* crowd.
    static let maxVisibleAgents = 90
    /// Per-frame budget for **drawn** structures.
    ///
    /// This used to be `placements.prefix(30)` — the first thirty in *build
    /// order*, so a colony of seventy-nine drew the ones it raised in its first
    /// twenty years and silently dropped everything after. The building the
    /// player had just paid for and watched go up was always the one that
    /// vanished.
    ///
    /// Worse, `normalizedLayout` is not only the drawing's layout:
    /// `AgentMotion` reads it for homes, beds and work posts. Forty-nine
    /// buildings past the cap were not merely undrawn — nobody could live or
    /// work in them, so a boom-town's colonists drifted with no post to stand
    /// at. The §9.11 shape again: the entity layer invisible to the thing that
    /// draws it.
    ///
    /// So the layout is now **complete**, and the budget applies to one frame:
    /// cull to what is actually on screen, and if a town still overflows it,
    /// keep what is nearest the middle of the view. A building leaves the
    /// drawing because you panned away from it, never because of when it
    /// was built.
    static let maxDrawnBuildings = 120

    /// Where the viewer is standing: how far in, and how far they've dragged.
    ///
    /// Zoom is applied by *scaling the rect the world is mapped into*, not by
    /// a `scaleEffect` on the view — a layer transform would resample the
    /// finished bitmap and turn crisp hairlines into mush. Mapping into a
    /// larger rect re-strokes everything at the new size, so the line art stays
    /// sharp however far you push in.
    struct Camera: Equatable {
        var scale: CGFloat = Camera.opening
        var offset: CGSize = .zero

        /// Where the camera opens: framed on the **town**, not on the whole
        /// valley.
        ///
        /// The settlement screen used to open at 1 — the entire local map
        /// across the width of a phone. The built span is a little over half of
        /// that width and holds an 18×18 grid, so a one-tile house came out
        /// about eleven points across: a colony read as a scatter of marks and
        /// you had to pinch in before you could tell a granary from a hut.
        ///
        /// This puts the built ground across most of the screen the moment you
        /// arrive, which is also where `showLabels` (1.6) starts naming roofs.
        /// Pinching out to `minScale` still gives you the whole valley.
        ///
        /// Raised to 2 when the grid went to 24×24 and every footprint grew: a
        /// building is two to four tiles across now instead of one to three, so
        /// there is genuinely more to look *at*, and the point of the settlement
        /// screen is seeing what people are doing rather than counting roofs.
        ///
        /// **And to 2.8 on 2026-08-23**, because the grid did not stop at 24.
        /// `ColonyBuilder.grownOutward` takes in another ring of four tiles
        /// every time a building will not fit, up to 90 a side, and
        /// `SettlementGeometry.span` does *not* follow it — so the town keeps
        /// the same slice of the valley and its tiles get smaller every time it
        /// grows. Keks's save is at 36×36 after three of those rings: a 2×2 hut
        /// covers `2/36 × 0.70` = 0.039 of the map, which at a zoom of 2 is
        /// about **30 points on a phone**. A house the size of a thumbnail is
        /// what *"mapa je malá"* looks like from the inside.
        ///
        /// 2.8 puts that hut at about 42 points and a third of the map's width
        /// across the screen — the town, not the valley. The real fix is for
        /// the span to grow with the grid so a tile keeps its size, and that is
        /// a wider change: the charted ground (`LocalMapGenerator`) and the
        /// rock kept off the grid (`StoneEngine.colonyClearance`) are both
        /// derived from the span and would have to grow with it, or a colony
        /// would grow into its own fog.
        /// **How far in the camera opens.**
        ///
        /// Moves with `SettlementGeometry.baseSpan`, and has to: a town given a
        /// smaller share of the valley is drawn smaller by exactly that ratio,
        /// and the point of the change was more country around the town, not
        /// smaller houses. 2.8 was right when a founding town took 0.70 of the
        /// map; at 0.46 the same building wants 2.8 × 0.70 / 0.46.
        static let opening: CGFloat = 2.8 * 0.70 / CGFloat(SettlementGeometry.baseSpan)
        static let minScale: CGFloat = 1
        /// How far in the camera will go.
        ///
        /// Was 4, and 4 is the whole town from a rooftop. Everything the canvas
        /// draws for a close look tops out well below it — the roof is off by
        /// 2.5, people are individuals from 1.5, labels from 1.6 — so past 4
        /// there was nothing left to reach *for*, and Keks asked for the reach.
        /// Doubling it is the difference between looking at a street and
        /// standing in one: at 8 a one-tile house is most of a phone's width,
        /// its wall shows what it is built of, and the people at its door are
        /// the size of people.
        static let maxScale: CGFloat = 8

        /// How close the camera goes when it is *taken* somewhere — a fight, a
        /// roof that just went on, the colonist a disaster picked out.
        ///
        /// Nearer than `opening`, because being shown a thing and being shown
        /// the town it is in are different favours, and past `showsIndividuals`
        /// so the people at the other end of it are people.
        static let closeUp: CGFloat = 3.0

        /// The camera that puts a point on the local map in the middle of the
        /// screen, without letting the world's edge come inside it.
        ///
        /// A world point is a fraction of the map, so it lands at
        /// `rect.origin + p × rect.size`; putting that at the view's centre is
        /// one line of algebra, and the clamp is the same one the pan gesture
        /// uses — otherwise being taken to a raid on the southern edge would
        /// show you half a screen of nothing.
        /// **Where in the view the thing being looked at should sit**, as a
        /// fraction down the screen.
        ///
        /// Half is the middle, which is right for almost everything and wrong
        /// for a fight: the card carrying the orders covers the bottom two
        /// thirds of the screen, so a raid framed in the centre is a raid drawn
        /// behind its own controls. Keks, watching one: *"chci vidět bitvu na
        /// plátně."*
        static let heldHigh: CGFloat = 0.30

        static func framing(_ point: LocalPoint, in size: CGSize,
                            scale: CGFloat = closeUp,
                            at height: CGFloat = 0.5) -> Camera {
            let s = min(maxScale, max(minScale, scale))
            // The world is the view scaled about its centre and then dragged,
            // so putting `point` at `height` down the screen is the centring
            // offset plus however far `height` is from the middle.
            var camera = Camera(scale: s, offset: CGSize(
                width: size.width * s * (0.5 - point.x),
                height: size.height * s * (0.5 - point.y)
                    + size.height * (height - 0.5)))
            let slackX = max(0, size.width * (s - 1) / 2)
            let slackY = max(0, size.height * (s - 1) / 2)
            camera.offset.width = min(slackX, max(-slackX, camera.offset.width))
            camera.offset.height = min(slackY, max(-slackY, camera.offset.height))
            return camera
        }
    }

    /// The rect the world is mapped into for a given camera — the view's rect
    /// scaled about its centre and dragged by the camera's offset.
    static func worldRect(viewRect: CGRect, camera: Camera) -> CGRect {
        let w = viewRect.width * camera.scale
        let h = viewRect.height * camera.scale
        return CGRect(
            x: viewRect.midX - w / 2 + camera.offset.width,
            y: viewRect.midY - h / 2 + camera.offset.height,
            width: w, height: h)
    }

    static func draw(
        _ context: inout GraphicsContext,
        size: CGSize,
        settlement: Settlement,
        map: LocalMap,
        registry: GameDataRegistry,
        time: Double,
        season: Season,
        /// The age the **town** is in, which is what furnishes its rooms.
        ///
        /// Not the building's own era: a windmill raised in the age of bronze
        /// is still a windmill, but the bench inside it belongs to the century
        /// the colony is living in. That difference is the whole of *"vesnice
        /// je moderní až v budoucnosti, canvas vypadá stejně"*
        /// (`FittingDefinition`).
        era: Era = .earlySettlement,
        camera: Camera,
        continuousTick: Double = 0,
        caravans: [Caravan] = [],
        /// The made ways arriving from the world map, drawn into the ground
        /// they cross so a highway does not stop at the valley's edge.
        approaches: [RoadApproach] = [],
        /// How far through its season the year has got, 0…1. Snow lies deeper
        /// at midwinter than on its first day, and spring's mud dries.
        seasonProgress: Double = 0.5,
        /// What the sky is doing, from `Climate.weather(_:)`. Cloud is what
        /// decides whether the moon is lighting anything.
        weather: Double = 0,
        /// A fight the player asked to see again. Overrides the live one while
        /// it runs, so "watch it again" is the same choreography on its own
        /// clock rather than a second, separate picture of a battle.
        battleReplay: SettlementBattle.Replay? = nil,
        /// **The clock a live raid's steps are actually landing on.** The world
        /// clock stops for a raid and the siege loop does not, so this is what
        /// carries a body between two steps of a fight — see
        /// `SettlementBattle.Beat`.
        battleBeat: SettlementBattle.Beat? = nil,
        /// When the last raid stopped, so the field can linger on real seconds
        /// rather than on a world clock a raid has paused (`BACKLOG.md` §21.6).
        battleEnded: (id: UUID, at: Date)? = nil,
        selectedPawnID: UUID?,
        selectedBuildingID: Int?
    ) {
        let viewRect = CGRect(origin: .zero, size: size)
        let rect = worldRect(viewRect: viewRect, camera: camera)
        let night = nightness(time: time)
        // Where the sun is standing. Everything that casts, shades or warms
        // reads this one value, so the whole valley is lit from one place.
        let sun = SettlementLight.sun(time: time)
        // One world scale for everything drawn in absolute pixels. Geometry
        // derived from `rect` grows with the camera by construction; the
        // fixed-pixel art (figures, river body, deposit furniture, smoke) has
        // to be told — or zooming in grows the town and leaves its people
        // doll-sized.
        let zoom = camera.scale
        let showLabels = zoom >= 1.6
        SettlementGround.draw(&context, rect: rect, map: map, season: season, zoom: zoom,
                              sun: sun, seasonProgress: seasonProgress,
                              tracks: SettlementTracks(settlement: settlement,
                                                       approaches: approaches),
                              registry: registry)
        zones(&context, rect: rect, settlement: settlement, season: season)
        // The square in the middle of it all. Reserved in the Core since
        // districts went in and never drawn, so a town's one open place read as
        // the gap the houses had not filled yet (`SettlementGreen`).
        SettlementGreen.draw(&context, rect: rect, settlement: settlement,
                             season: season, era: era, time: time, zoom: zoom)
        // Stone and iron. Earth roads are already in the ground's own colour
        // (`SettlementTracks`); what is left is the ways that are *made* of
        // something, which no amount of packed earth can say.
        highways(&context, rect: rect, approaches: approaches, zoom: zoom)
        // The trails out to the wood and the quarry — the one journey nobody
        // makes from a doorway, so it is not on the build grid and cannot be
        // worn into it.
        trails(&context, rect: rect, settlement: settlement, registry: registry,
               map: map, zoom: zoom)
        heartGlow(&context, rect: rect)
        // The sea, before the river and the landscape: everything else stands
        // on the land it leaves.
        sea(&context, rect: rect, shore: map.shore, season: season, time: time)
        river(&context, rect: rect, river: map.river, season: season, zoom: zoom)
        scenery(&context, rect: rect, map: map, season: season)
        // The real wood and rock, over the decorative landscape but under
        // anything built — a tree stands in front of the grass and behind the
        // roof it shades.
        // The mountain, before the wood: a tree at the foot of a cliff stands in
        // front of it, and nothing stands on top of solid rock.
        // The country's own shapes first of all: a ravine is *ground*, so the
        // rock, the wood and everything standing on it belongs in front.
        SettlementLandforms.draw(&context, rect: rect, map: map, season: season,
                                 zoom: zoom, showLabels: showLabels)
        SettlementStone.draw(&context, rect: rect, map: map, season: season, zoom: zoom,
                             registry: registry)
        // The wood's shadows and its rock, on the ground where they belong. The
        // **trunks** are held back and drawn with the town below, in one pass
        // sorted on the foot — otherwise every tree in the settlement stands
        // behind every roof in it, which is the "levitating trees" Keks named.
        SettlementFlora.draw(&context, rect: rect, map: map, season: season, time: time,
                             sun: sun, viewport: viewRect, standingTrees: false,
                             registry: registry)
        // The fields, over the ground and under everything standing on it —
        // a plot is worked earth, so a figure reaping it stands in front.
        SettlementCrops.draw(&context, rect: rect, map: map, season: season, zoom: zoom,
                             registry: registry)
        // What has been cut and not yet carried in.
        SettlementPiles.draw(&context, rect: rect, map: map, zoom: zoom)
        // And whoever has come in over the edge to trade or to talk.
        SettlementVisitors.draw(
            &context, rect: rect, map: map, time: time,
            continuousStep: continuousTick * Double(WorldClock.actionStepsPerTick),
            zoom: zoom, showLabels: showLabels)
        // Your own carts, on the leg of the road that crosses this valley.
        SettlementConvoys.draw(&context, rect: rect, settlement: settlement,
                               caravans: caravans, map: map, time: time, zoom: zoom)
        // And the beasts that stopped running and stayed.
        SettlementWildlife.drawTamed(&context, rect: rect, settlement: settlement,
                                     map: map, time: time, zoom: zoom)
        // What the player has asked for, over the things it points at: a mark
        // you cannot see is a mark you do not believe in.
        SettlementMarks.draw(&context, rect: rect, settlement: settlement,
                             map: map, time: time, zoom: zoom)
        // …and the people the colony is holding. They have been in the save
        // since `CaptiveEngine` was written and on the screen never.
        SettlementCaptives.draw(&context, rect: rect, settlement: settlement,
                                map: map, registry: registry, time: time, zoom: zoom,
                                ticksPerYear: registry.config.ticksPerYear,
                                selected: selectedPawnID)
        deposits(&context, rect: rect, map: map, season: season, zoom: zoom,
                 showLabels: showLabels)
        pois(&context, rect: rect, map: map, time: time, showLabels: showLabels,
             expeditions: settlement.expeditions)
        SettlementWildlife.draw(
            &context, rect: rect, map: map, time: time,
            continuousStep: continuousTick * Double(WorldClock.actionStepsPerTick),
            zoom: zoom)

        // Culled to the screen, not to build order: the newest roof in a town
        // of eighty is drawn, and what drops out is whatever you panned away
        // from. `size` is the view, `rect` is the world the camera maps into.
        let placed = layout(settlement: settlement, registry: registry, rect: rect,
                            viewport: CGRect(origin: .zero, size: size))
        // Pushed in close, every structure says what it is — the answer to
        // "which roof is the library?" without a single tap.
        // Blood is on the ground, so it goes under everything standing on it —
        // under the town as much as under the people, which is why it is drawn
        // before the sorted pass rather than between two halves of it.
        SettlementBattle.drawGround(&context, rect: rect, settlement: settlement,
                                    continuousTick: continuousTick, zoom: zoom,
                                    secondsPerTick: registry.config.realSecondsPerTick,
                                    replay: battleReplay, beat: battleBeat, time: time,
                                    ended: battleEnded)
        buildings(&context, placed: placed, time: time, night: night,
                  showLabels: showLabels, zoom: zoom, sun: sun,
                  selectedBuildingID: selectedBuildingID,
                  trees: SettlementFlora.standing(map: map, rect: rect, viewport: viewRect),
                  rect: rect, season: season,
                  people: standingAgents(
                      rect: rect, settlement: settlement, map: map,
                      continuousTick: continuousTick, registry: registry, time: time,
                      zoom: zoom, selectedPawnID: selectedPawnID,
                      battleReplay: battleReplay, battleBeat: battleBeat),
                  registry: registry, era: era)
        SettlementFigures.smoke(
            &context,
            houses: placed.filter { $0.glyph == .house && !$0.underConstruction },
            time: time, zoom: zoom)

        SettlementFigures.birds(&context, rect: rect, season: season, time: time, zoom: zoom)
        // A raid plays out over the scene it happens to — above the people,
        // under the fog, so the dark still hides what the colony cannot see.
        SettlementBattle.draw(&context, rect: rect, settlement: settlement,
                              continuousTick: continuousTick, time: time, zoom: zoom,
                              secondsPerTick: registry.config.realSecondsPerTick,
                              replay: battleReplay, selectedPawnID: selectedPawnID,
                              beat: battleBeat, viewport: viewRect, ended: battleEnded)
        fog(&context, rect: rect, map: map, time: time)
        // The seasonal wash is atmosphere over the lens, not part of the world,
        // so it stays in view space and doesn't slide when you pan.
        seasonWash(&context, rect: viewRect, size: size, season: season, time: time)
        SettlementLight.wash(&context, rect: viewRect, sun: sun)
        let moonlight = MoonPhase.moonlight(at: time, weather: weather)
        nightWash(&context, rect: viewRect, night: night, moonlight: moonlight)
        // And then the lamps, **over** the wash — the one layer night is not
        // allowed to grey out, because at night the lights are the picture.
        // …and whatever a fight is carrying, so a raid at midnight is something
        // you can see rather than a rumour in the dark.
        SettlementLight.lamps(
            &context,
            nightLamps(placed: placed) + SettlementBattle.torchlight(
                settlement, rect: rect, continuousTick: continuousTick,
                secondsPerTick: registry.config.realSecondsPerTick,
                replay: battleReplay, zoom: zoom, beat: battleBeat, time: time,
                ended: battleEnded),
            night: night, moonlight: moonlight, time: time)
    }

    // MARK: - Day & night

    /// Maps a normalised model point to a pixel point in `rect`.
    static func point(_ p: LocalPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
    }

    /// The inverse of `point`: where on the map a tap landed, clamped to it.
    /// Lets a tap on the fog name the ground the scouts should walk to.
    static func normalised(_ p: CGPoint, in rect: CGRect) -> LocalPoint {
        guard rect.width > 0, rect.height > 0 else { return LocalPoint(x: 0.5, y: 0.5) }
        return LocalPoint(
            x: min(1, max(0, (p.x - rect.minX) / rect.width)),
            y: min(1, max(0, (p.y - rect.minY) / rect.height)))
    }

    // MARK: - Wilderness (surveying a region without a settlement)

    static func fog(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap, time: Double
    ) {
        SettlementGround.fog(&context, rect: rect, map: map)
        scoutOrder(&context, rect: rect, map: map, time: time)
    }

    /// Where the player has sent the scouts, marked in the dark they were sent
    /// into. Without this an order lands silently and the tap reads as a
    /// no-op — the ground it points at is, by definition, not yet drawn.
    static func scoutOrder(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap, time: Double
    ) {
        guard let focus = map.scoutFocus else { return }
        let c = point(focus, in: rect)
        let unit = min(rect.width, rect.height)
        // A slow beacon: two rings breathing out of phase, so it reads as
        // "on its way" rather than as something already found.
        for i in 0..<2 {
            let phase = (time * 0.5 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
            let r = unit * (0.012 + 0.028 * phase)
            context.stroke(
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                with: .color(Theme.accent.opacity(0.5 * (1 - phase))), lineWidth: 1.2)
        }
        let dot = unit * 0.006
        context.fill(Path(ellipseIn: CGRect(x: c.x - dot, y: c.y - dot,
                                            width: dot * 2, height: dot * 2)),
                     with: .color(Theme.accent.opacity(0.85)))
    }

    // MARK: - Season

    static func seasonWash(
        _ context: inout GraphicsContext, rect: CGRect, size: CGSize,
        season: Season, time: Double
    ) {
        context.fill(Path(rect), with: .color(Theme.seasonTint(season)))
        guard season == .winter else { return }
        for i in 0..<40 {
            let sx = (Double(i) * 173 + time * (12 + Double(i % 3) * 6))
                .truncatingRemainder(dividingBy: size.width)
            let sy = (Double(i) * 97 + time * (18 + Double(i % 4) * 5))
                .truncatingRemainder(dividingBy: size.height)
            context.fill(Path(ellipseIn: CGRect(x: sx, y: sy, width: 1.6, height: 1.6)),
                         with: .color(Color.white.opacity(0.5)))
        }
    }
}
