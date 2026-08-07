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
    /// Cap on drawn structures, so a large town stays legible.
    static let maxVisibleBuildings = 30

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
        static let opening: CGFloat = 2.0
        static let minScale: CGFloat = 1
        static let maxScale: CGFloat = 4
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
        camera: Camera,
        continuousTick: Double = 0,
        caravans: [Caravan] = [],
        /// How far through its season the year has got, 0…1. Snow lies deeper
        /// at midwinter than on its first day, and spring's mud dries.
        seasonProgress: Double = 0.5,
        /// A fight the player asked to see again. Overrides the live one while
        /// it runs, so "watch it again" is the same choreography on its own
        /// clock rather than a second, separate picture of a battle.
        battleReplay: SettlementBattle.Replay? = nil,
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
                              sun: sun, seasonProgress: seasonProgress)
        zones(&context, rect: rect, settlement: settlement, season: season)
        paths(&context, rect: rect, settlement: settlement, registry: registry,
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
        SettlementStone.draw(&context, rect: rect, map: map, season: season, zoom: zoom)
        SettlementFlora.draw(&context, rect: rect, map: map, season: season, time: time, sun: sun)
        // The fields, over the ground and under everything standing on it —
        // a plot is worked earth, so a figure reaping it stands in front.
        SettlementCrops.draw(&context, rect: rect, map: map, season: season, zoom: zoom)
        // What has been cut and not yet carried in.
        SettlementPiles.draw(&context, rect: rect, map: map, zoom: zoom)
        // And whoever has come in over the edge to trade or to talk.
        SettlementVisitors.draw(&context, rect: rect, map: map, time: time,
                                zoom: zoom, showLabels: showLabels)
        // Your own carts, on the leg of the road that crosses this valley.
        SettlementConvoys.draw(&context, rect: rect, settlement: settlement,
                               caravans: caravans, map: map, time: time, zoom: zoom)
        // And the beasts that stopped running and stayed.
        SettlementWildlife.drawTamed(&context, rect: rect, settlement: settlement,
                                     map: map, time: time, zoom: zoom)
        deposits(&context, rect: rect, map: map, season: season, zoom: zoom,
                 showLabels: showLabels)
        pois(&context, rect: rect, map: map, time: time, showLabels: showLabels,
             expeditions: settlement.expeditions)
        SettlementWildlife.draw(&context, rect: rect, map: map, time: time, zoom: zoom)

        let placed = layout(settlement: settlement, registry: registry, rect: rect)
        // Pushed in close, every structure says what it is — the answer to
        // "which roof is the library?" without a single tap.
        buildings(&context, placed: placed, time: time, night: night,
                  showLabels: showLabels, zoom: zoom, sun: sun,
                  selectedBuildingID: selectedBuildingID)
        SettlementFigures.smoke(
            &context,
            houses: placed.filter { $0.glyph == .house && !$0.underConstruction },
            time: time, zoom: zoom)

        // Blood is on the ground, so it goes under the people standing on it —
        // the only part of a battle that is drawn before the figures.
        SettlementBattle.drawGround(&context, rect: rect, settlement: settlement,
                                    continuousTick: continuousTick, zoom: zoom,
                                    secondsPerTick: registry.config.realSecondsPerTick,
                                    replay: battleReplay)

        agents(&context, rect: rect, settlement: settlement, map: map, continuousTick: continuousTick,
               registry: registry, time: time, zoom: zoom, selectedPawnID: selectedPawnID,
               battleReplay: battleReplay)
        SettlementFigures.birds(&context, rect: rect, season: season, time: time, zoom: zoom)
        // A raid plays out over the scene it happens to — above the people,
        // under the fog, so the dark still hides what the colony cannot see.
        SettlementBattle.draw(&context, rect: rect, settlement: settlement,
                              continuousTick: continuousTick, time: time, zoom: zoom,
                              secondsPerTick: registry.config.realSecondsPerTick,
                              replay: battleReplay, selectedPawnID: selectedPawnID)
        fog(&context, rect: rect, map: map, time: time)
        // The seasonal wash is atmosphere over the lens, not part of the world,
        // so it stays in view space and doesn't slide when you pan.
        seasonWash(&context, rect: viewRect, size: size, season: season, time: time)
        SettlementLight.wash(&context, rect: viewRect, sun: sun)
        nightWash(&context, rect: viewRect, night: night)
    }

    // MARK: - Day & night

    /// How deep into night the settlement's shared day is (0 = broad day,
    /// 1 = the dead of night). Synced to `AgentMotion.dayLength`, so the world
    /// darkens exactly while the figures are in their beds — the day cycle the
    /// motion always had, finally *visible*.
    static func nightness(time: Double) -> Double {
        let t = (time / AgentMotion.dayLength).truncatingRemainder(dividingBy: 1)
        let phase = t < 0.5 ? t : t - 1          // −0.5…0.5, midnight at 0
        let fromMidnight = abs(phase)
        return max(0, min(1, (0.16 - fromMidnight) / 0.10))
    }

    /// A cool veil over the lens at night. The fog stays darker still, and
    /// warm windows and fires read brighter against it.
    private static func nightWash(
        _ context: inout GraphicsContext, rect: CGRect, night: Double
    ) {
        guard night > 0.01 else { return }
        // Night **darkens**; it does not paint the valley blue.
        //
        // At 0.30 alpha of (0.03, 0.05, 0.12) this was the strongest single
        // wash in the whole stack and by far the most saturated, so every dusk
        // dragged the ground toward its own colour. Over autumn — which is the
        // one season whose earth is genuinely brown — brown plus that much blue
        // is *purple*, and the whole valley went violet every evening.
        //
        // A near-neutral slate at two thirds the strength reads as the light
        // going out, which is what it is.
        context.fill(Path(rect),
                     with: .color(Color(red: 0.06, green: 0.07, blue: 0.10).opacity(night * 0.20)))
    }

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

    /// Draws an explored region's *chunk* — the same terrain, deposits,
    /// landmarks and wildlife a settlement map gets, minus the town. This is
    /// what opens when you survey a region from the world map: the land as
    /// your expedition recorded it, alive. A native people's camp (and its
    /// people, walking) is drawn when one lives here.
    static func drawWilderness(
        _ context: inout GraphicsContext,
        size: CGSize,
        map: LocalMap,
        season: Season,
        time: Double,
        camera: Camera,
        regionKind: RegionKind,
        tribe: Tribe?,
        seasonProgress: Double = 0.5
    ) {
        let viewRect = CGRect(origin: .zero, size: size)
        let rect = worldRect(viewRect: viewRect, camera: camera)
        let night = nightness(time: time)
        let sun = SettlementLight.sun(time: time)
        let zoom = camera.scale
        let showLabels = zoom >= 1.6
        SettlementGround.draw(&context, rect: rect, map: map, season: season, zoom: zoom,
                              sun: sun, seasonProgress: seasonProgress)
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
        SettlementStone.draw(&context, rect: rect, map: map, season: season, zoom: zoom)
        SettlementFlora.draw(&context, rect: rect, map: map, season: season, time: time, sun: sun)
        // The fields, over the ground and under everything standing on it —
        // a plot is worked earth, so a figure reaping it stands in front.
        SettlementCrops.draw(&context, rect: rect, map: map, season: season, zoom: zoom)
        // What has been cut and not yet carried in.
        SettlementPiles.draw(&context, rect: rect, map: map, zoom: zoom)
        // And whoever has come in over the edge to trade or to talk.
        SettlementVisitors.draw(&context, rect: rect, map: map, time: time,
                                zoom: zoom, showLabels: showLabels)
        deposits(&context, rect: rect, map: map, season: season, zoom: zoom,
                 showLabels: showLabels)
        pois(&context, rect: rect, map: map, time: time, showLabels: showLabels)
        SettlementWildlife.draw(&context, rect: rect, map: map, time: time, zoom: zoom)
        if regionKind == .anomaly {
            anomalyGlow(&context, rect: rect, time: time)
        }
        if let tribe {
            SettlementStructures.camp(
                &context, rect: rect, population: tribe.population,
                tint: campTint(tribe.status), time: time,
                seed: map.terrainSeed, night: night, zoom: zoom)
        }
        seasonWash(&context, rect: viewRect, size: size, season: season, time: time)
        SettlementLight.wash(&context, rect: viewRect, sun: sun)
        nightWash(&context, rect: viewRect, night: night)
    }

    private static func campTint(_ status: DiplomaticStanding) -> Color {
        switch status {
        case .allied, .friendly: return Theme.good
        case .neutral: return Theme.bone
        case .tense: return Theme.accent
        case .war: return Theme.danger
        }
    }

    /// The anomaly's unquiet light: a breathing glow and slow-orbiting motes.
    private static func anomalyGlow(
        _ context: inout GraphicsContext, rect: CGRect, time: Double
    ) {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let breath = 0.5 + 0.5 * sin(time * 0.8)
        let radius = rect.width * (0.16 + 0.03 * breath)
        context.fill(
            Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius,
                                   width: radius * 2, height: radius * 2)),
            with: .radialGradient(
                Gradient(colors: [Color(red: 0.55, green: 0.45, blue: 0.85).opacity(0.20 + 0.10 * breath), .clear]),
                center: c, startRadius: 0, endRadius: radius))
        for i in 0..<5 {
            let angle = time * 0.3 + Double(i) * 1.26
            let r = radius * (0.5 + 0.35 * sin(time * 0.5 + Double(i)))
            let p = CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r * 0.7)
            context.fill(Path(ellipseIn: CGRect(x: p.x - 1.2, y: p.y - 1.2, width: 2.4, height: 2.4)),
                         with: .color(Color(red: 0.7, green: 0.6, blue: 0.95).opacity(0.7)))
        }
    }

    // MARK: - Ground tiles

    /// The earth, drawn by `SettlementGround` — a square grain over the fog
    /// grid rather than the fog grid itself, which on a phone is three times
    /// taller than it is wide and made every meadow a green column.
    static func coverColor(_ cover: GroundCover, season: Season) -> Color {
        SettlementGround.coverColor(cover, season: season)
    }

    // MARK: - Zones

    /// The amenity zones the player painted on the build grid, visible on the
    /// living canvas at last: a park's green, a plaza's paving, a garden's
    /// blooms. The plaza is also where the midday crowd gathers (see
    /// `AgentMotion.Scene`).
    private static func zones(
        _ context: inout GraphicsContext, rect: CGRect, settlement: Settlement, season: Season
    ) {
        guard let colony = settlement.colony, !colony.zones.isEmpty else { return }
        let unit = min(rect.width, rect.height)
        let tile = unit * 0.038
        for zone in colony.zones {
            let center = point(canvasPoint(for: zone.coord, in: colony), in: rect)
            let patch = CGRect(x: center.x - tile / 2, y: center.y - tile / 2,
                               width: tile, height: tile)
            switch zone.kind {
            case .park:
                context.fill(Path(roundedRect: patch, cornerRadius: tile * 0.3),
                             with: .color(canopyColor(season).opacity(0.16)))
                for i in 0..<2 {
                    let x = patch.minX + tile * (0.3 + Double(i) * 0.4)
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: x, y: patch.maxY - 2))
                        p.addLine(to: CGPoint(x: x, y: patch.midY))
                    }, with: .color(canopyColor(season).opacity(0.7)), lineWidth: 0.8)
                    context.stroke(
                        Path(ellipseIn: CGRect(x: x - 2.4, y: patch.midY - 4.5, width: 4.8, height: 4.5)),
                        with: .color(canopyColor(season).opacity(0.7)), lineWidth: 0.8)
                }
            case .plaza:
                context.fill(Path(roundedRect: patch, cornerRadius: tile * 0.15),
                             with: .color(Theme.bone.opacity(0.08)))
                for i in 0..<4 {
                    let x = patch.minX + tile * (0.2 + Double(i % 2) * 0.5)
                    let y = patch.minY + tile * (0.25 + Double(i / 2) * 0.45)
                    context.stroke(Path(CGRect(x: x, y: y, width: 2.6, height: 1.8)),
                                   with: .color(Theme.boneFaint), lineWidth: 0.5)
                }
            case .garden:
                context.fill(Path(roundedRect: patch, cornerRadius: tile * 0.3),
                             with: .color(Color(red: 0.35, green: 0.5, blue: 0.32).opacity(0.18)))
                for i in 0..<3 {
                    let x = patch.minX + tile * (0.25 + Double(i) * 0.25)
                    let y = patch.midY + (i % 2 == 0 ? -2.0 : 2.0)
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.8, height: 1.8)),
                                 with: .color(Color(red: 0.85, green: 0.72, blue: 0.6).opacity(0.8)))
                }
            }
        }
    }

    // MARK: - Points of interest

    /// Discovered landmarks — what the scouts' walking actually found.
    private static func pois(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap, time: Double,
        showLabels: Bool = false, expeditions: [POIExpedition] = []
    ) {
        let unit = min(rect.width, rect.height)
        for poi in map.pois where poi.discovered && map.isExplored(poi.position) {
            let c = point(poi.position, in: rect)
            // A faint halo separates a landmark from mere scenery — and says
            // at a glance whether the place still has anything to give. A
            // picked-clean ruin should not keep inviting you over.
            let spent = poi.isExhausted
            let halo = unit * 0.024
            context.fill(Path(ellipseIn: CGRect(x: c.x - halo, y: c.y - halo,
                                                width: halo * 2, height: halo * 2)),
                         with: .color(Theme.accent.opacity(spent ? 0.02 : 0.06)))
            context.stroke(Path(ellipseIn: CGRect(x: c.x - halo, y: c.y - halo,
                                                  width: halo * 2, height: halo * 2)),
                           with: .color(spent ? Theme.textDim.opacity(0.18)
                                              : Theme.accent.opacity(0.22)),
                           lineWidth: 0.7)
            SettlementStructures.poi(poi.kind, at: c,
                                     s: unit * 0.014, time: time, context: &context)
            // If a party is in there right now, draw what they are dealing
            // with. A visit used to be a party standing on a dot for six ticks.
            if let site = expeditions.first(where: { $0.poiID == poi.id })?.site {
                SettlementSites.draw(site, in: rect, time: time, context: &context)
            }
            if showLabels {
                let caption = Text(poi.kind.displayLabel)
                    .font(.system(size: 5.5))
                    .foregroundStyle(Theme.accent.opacity(0.8))
                context.draw(context.resolve(caption),
                             at: CGPoint(x: c.x, y: c.y + halo + 5))
            }
        }
    }

    // MARK: - Paths

    /// Worn trails printed into the grass: from the heart out to every working
    /// structure and to the deposits the colony is actually harvesting — the
    /// routes the colonists genuinely walk. The town stops floating on lawn
    /// and starts being *connected*.
    private static func paths(
        _ context: inout GraphicsContext, rect: CGRect,
        settlement: Settlement, registry: GameDataRegistry, map: LocalMap, zoom: CGFloat
    ) {
        let heart = point(colonyHeart, in: rect)
        var targets: [CGPoint] = []
        for building in layout(settlement: settlement, registry: registry, rect: rect)
        where !building.underConstruction && building.glyph != .house {
            targets.append(building.center)
        }
        // Only deposits someone is assigned to work — an untouched wood has
        // no trail beaten to it.
        let worked = Set(settlement.pawns.map(\.assignedWork))
        for node in map.nodes
        where map.isExplored(node.position) && worked.contains(node.kind.work) {
            targets.append(point(node.position, in: rect))
        }

        let dirt = Color(red: 0.36, green: 0.31, blue: 0.23)
        for (i, target) in targets.prefix(14).enumerated() {
            let dx = target.x - heart.x, dy = target.y - heart.y
            let length = max(1, sqrt(dx * dx + dy * dy))
            let side: CGFloat = i.isMultiple(of: 2) ? 1 : -1
            let bow = min(14 * zoom, length * 0.12) * side
            var trail = Path()
            trail.move(to: heart)
            trail.addQuadCurve(
                to: target,
                control: CGPoint(x: (heart.x + target.x) / 2 - dy / length * bow,
                                 y: (heart.y + target.y) / 2 + dx / length * bow))
            context.stroke(trail, with: .color(dirt.opacity(0.32)),
                           style: StrokeStyle(lineWidth: 2.6 * zoom, lineCap: .round))
        }
    }

    private static func heartGlow(_ context: inout GraphicsContext, rect: CGRect) {
        let heart = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.52)
        context.fill(
            Path(ellipseIn: CGRect(x: heart.x - rect.width * 0.4, y: heart.y - rect.height * 0.4,
                                   width: rect.width * 0.8, height: rect.height * 0.8)),
            with: .radialGradient(
                Gradient(colors: [Theme.bone.opacity(0.05), .clear]),
                center: heart, startRadius: 0, endRadius: rect.width * 0.42)
        )
    }

    // MARK: - River

    private static func river(
        _ context: inout GraphicsContext, rect: CGRect, river: RiverShape,
        season: Season, zoom: CGFloat = 1
    ) {
        // A dry valley has no river to draw. Six kinds of country that all came
        // with the same blue ribbon across them read as one kind of country in
        // six tints — which is why the biome now decides whether water runs.
        guard river.flows else { return }
        var path = Path()
        let steps = 48
        for i in 0...steps {
            let nx = Double(i) / Double(steps)
            let p = point(LocalPoint(x: nx, y: river.y(atX: nx)), in: rect)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        // The band is *geometry* (a river has a width in the world), so it
        // grows with the camera; the highlight stays a near-hairline.
        let body = 14 * zoom
        let sheen = max(1.4, 2 * sqrt(zoom))
        if season == .winter {
            context.stroke(path, with: .color(Color(red: 0.42, green: 0.50, blue: 0.60)),
                           style: StrokeStyle(lineWidth: body, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(Color(red: 0.72, green: 0.80, blue: 0.90).opacity(0.8)),
                           style: StrokeStyle(lineWidth: sheen, lineCap: .round,
                                              dash: [6 * zoom, 5 * zoom]))
        } else {
            context.stroke(path, with: .color(Color(red: 0.15, green: 0.22, blue: 0.30)),
                           style: StrokeStyle(lineWidth: body, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(Color(red: 0.38, green: 0.52, blue: 0.64).opacity(0.75)),
                           style: StrokeStyle(lineWidth: sheen, lineCap: .round))
        }
    }

    // MARK: - Scenery

    private static func scenery(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap, season: Season
    ) {
        for prop in map.scenery where map.isExplored(prop.position) {
            let c = point(prop.position, in: rect)
            let s = CGFloat(prop.scale) * min(rect.width, rect.height) * 0.012
            // The land is stock, not wallpaper: trees standing near a forest
            // deposit are *that forest* — as the loggers eat it, they come
            // down (stump first, then bare ground). Rocks near a quarry
            // shrink the same way. Which prop falls first is stable per prop,
            // so the clearing spreads instead of flickering.
            var kind = prop.kind
            var size = s
            if kind == .tree || kind == .pine {
                if let fraction = nearestNodeFraction(map: map, kind: .forest, to: prop.position) {
                    // A wood that has real trees in it draws those instead —
                    // otherwise the same copse is drawn twice, once as standing
                    // stock and once as furniture that only pretends to be cut.
                    if !map.trees.isEmpty { continue }
                    let threshold = propRoll(prop.id)
                    if fraction < threshold * 0.5 { continue }        // felled and hauled
                    if fraction < threshold * 0.9 { kind = .stump }   // fresh-cut
                }
            } else if kind == .rock || kind == .boulder {
                if let fraction = nearestNodeFraction(map: map, kind: .stone, to: prop.position) {
                    if !map.rocks.isEmpty { continue }
                    let threshold = propRoll(prop.id)
                    if fraction < threshold * 0.4 { continue }        // quarried away
                    size *= CGFloat(0.6 + fraction * 0.4)             // being cut down
                }
            }
            drawProp(kind, at: c, s: size, season: season, context: &context)
        }
    }

    /// How full the nearest deposit of a kind is around a point (within a
    /// working radius), or nil if none is close enough to claim the prop.
    private static func nearestNodeFraction(
        map: LocalMap, kind: LocalResourceKind, to position: LocalPoint
    ) -> Double? {
        var best: (d2: Double, fraction: Double)?
        for node in map.nodes where node.kind == kind {
            let dx = node.position.x - position.x
            let dy = node.position.y - position.y
            let d2 = dx * dx + dy * dy
            if d2 < 0.045 * 0.045 * 16, d2 < (best?.d2 ?? .infinity) {   // ~0.18 reach
                best = (d2, node.capacity > 0 ? node.amount / node.capacity : 1)
            }
        }
        return best?.fraction
    }

    /// A stable 0.35…0.95 roll per prop — the order the clearing takes them.
    private static func propRoll(_ id: Int) -> Double {
        var h = UInt64(bitPattern: Int64(id)) &* 0x9E37_79B9_7F4A_7C15
        h ^= h >> 29
        return 0.35 + Double(h % 1000) / 1000 * 0.6
    }

    /// The deciduous canopy through the year.
    private static func canopyColor(_ season: Season) -> Color {
        switch season {
        case .spring: return Color(red: 0.44, green: 0.62, blue: 0.42)
        case .summer: return Color(red: 0.38, green: 0.55, blue: 0.40)
        case .autumn: return Color(red: 0.72, green: 0.50, blue: 0.28)
        case .winter: return Color(red: 0.50, green: 0.52, blue: 0.56)
        }
    }

    private static func drawProp(
        _ kind: SceneryKind, at c: CGPoint, s: CGFloat, season: Season,
        context: inout GraphicsContext
    ) {
        switch kind {
        case .tree:
            // A shadow, a filled trunk, and a lobed canopy with real mass —
            // not an outline the terrain shows straight through.
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.85, y: c.y + s * 0.72,
                                                width: s * 1.7, height: s * 0.5)),
                         with: .color(Theme.ink.opacity(0.20)))
            context.fill(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.15, y: c.y + s * 0.9))
                p.addLine(to: CGPoint(x: c.x - s * 0.06, y: c.y - s * 0.1))
                p.addLine(to: CGPoint(x: c.x + s * 0.06, y: c.y - s * 0.1))
                p.addLine(to: CGPoint(x: c.x + s * 0.15, y: c.y + s * 0.9))
                p.closeSubpath()
            }, with: .color(Color(red: 0.34, green: 0.27, blue: 0.20)))
            if season == .winter {
                // Bare branches instead of a canopy.
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: c.x, y: c.y + s * 0.2))
                    p.addLine(to: CGPoint(x: c.x - s * 0.7, y: c.y - s * 1.0))
                    p.move(to: CGPoint(x: c.x, y: c.y - s * 0.1))
                    p.addLine(to: CGPoint(x: c.x + s * 0.65, y: c.y - s * 1.15))
                    p.move(to: CGPoint(x: c.x, y: c.y - s * 0.4))
                    p.addLine(to: CGPoint(x: c.x - s * 0.3, y: c.y - s * 1.4))
                }, with: .color(Color(red: 0.34, green: 0.27, blue: 0.20)), lineWidth: 0.9)
            } else {
                let canopy = canopyColor(season)
                let lobes: [(CGFloat, CGFloat, CGFloat)] =
                    [(-0.5, -0.75, 0.8), (0.5, -0.8, 0.78), (0, -1.25, 0.92)]
                for (dx, dy, r) in lobes {
                    context.fill(Path(ellipseIn: CGRect(x: c.x + dx * s - r * s, y: c.y + dy * s - r * s,
                                                        width: r * s * 2, height: r * s * 2)),
                                 with: .color(canopy))
                }
                // A sunlit highlight on the crown gives the foliage form.
                context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.55, y: c.y - s * 1.55,
                                                    width: s * 0.7, height: s * 0.7)),
                             with: .color(.white.opacity(0.12)))
                if season == .autumn {
                    for i in 0..<3 {
                        let lx = c.x + CGFloat(i - 1) * s * 0.5
                        context.fill(Path(ellipseIn: CGRect(x: lx, y: c.y + s * 0.8,
                                                            width: 1.6, height: 1.1)),
                                     with: .color(canopy.opacity(0.8)))
                    }
                }
            }
        case .pine:
            let pine = season == .winter
                ? Color(red: 0.36, green: 0.46, blue: 0.44)
                : Color(red: 0.28, green: 0.44, blue: 0.33)
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.7, y: c.y + s * 0.78,
                                                width: s * 1.4, height: s * 0.42)),
                         with: .color(Theme.ink.opacity(0.20)))
            context.fill(Path(CGRect(x: c.x - s * 0.09, y: c.y + s * 0.45,
                                     width: s * 0.18, height: s * 0.65)),
                         with: .color(Color(red: 0.32, green: 0.25, blue: 0.19)))
            for tier in 0..<3 {
                let t = CGFloat(tier)
                let top = c.y - s * 1.4 + t * s * 0.55
                let w = s * (0.42 + t * 0.3)
                context.fill(Path { p in
                    p.move(to: CGPoint(x: c.x - w, y: top + s * 0.58))
                    p.addLine(to: CGPoint(x: c.x, y: top))
                    p.addLine(to: CGPoint(x: c.x + w, y: top + s * 0.58))
                    p.closeSubpath()
                }, with: .color(pine.opacity(1 - t * 0.08)))
            }
            if season == .winter {
                // Snow settled on the crown.
                context.fill(Path { p in
                    p.move(to: CGPoint(x: c.x - s * 0.32, y: c.y - s * 0.95))
                    p.addLine(to: CGPoint(x: c.x, y: c.y - s * 1.4))
                    p.addLine(to: CGPoint(x: c.x + s * 0.32, y: c.y - s * 0.95))
                    p.closeSubpath()
                }, with: .color(.white.opacity(0.5)))
            }
        case .bush:
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.7, y: c.y + s * 0.32,
                                                width: s * 1.4, height: s * 0.34)),
                         with: .color(Theme.ink.opacity(0.16)))
            let bushC = canopyColor(season)
            let lobes: [(CGFloat, CGFloat, CGFloat)] = [(-0.4, 0, 0.55), (0.4, 0, 0.55), (0, -0.2, 0.66)]
            for (dx, dy, r) in lobes {
                context.fill(Path(ellipseIn: CGRect(x: c.x + dx * s - r * s, y: c.y + dy * s - r * s,
                                                    width: r * s * 2, height: r * s * 2)),
                             with: .color(bushC.opacity(0.92)))
            }
        case .rock:
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.6, y: c.y + s * 0.3,
                                                width: s * 1.2, height: s * 0.3)),
                         with: .color(Theme.ink.opacity(0.18)))
            let face = Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.5, y: c.y + s * 0.4))
                p.addLine(to: CGPoint(x: c.x - s * 0.2, y: c.y - s * 0.4))
                p.addLine(to: CGPoint(x: c.x + s * 0.4, y: c.y - s * 0.25))
                p.addLine(to: CGPoint(x: c.x + s * 0.55, y: c.y + s * 0.4))
                p.closeSubpath()
            }
            context.fill(face, with: .color(Color(red: 0.55, green: 0.57, blue: 0.61)))
            // A shaded facet turns the flat stone into a solid.
            context.fill(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.2, y: c.y - s * 0.4))
                p.addLine(to: CGPoint(x: c.x + s * 0.4, y: c.y - s * 0.25))
                p.addLine(to: CGPoint(x: c.x + s * 0.55, y: c.y + s * 0.4))
                p.closeSubpath()
            }, with: .color(Color(red: 0.42, green: 0.44, blue: 0.48)))
            context.stroke(face, with: .color(Color(red: 0.70, green: 0.72, blue: 0.76).opacity(0.5)), lineWidth: 0.6)
        case .boulder:
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.95, y: c.y + s * 0.5,
                                                width: s * 1.9, height: s * 0.4)),
                         with: .color(Theme.ink.opacity(0.2)))
            let boulder = Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.9, y: c.y + s * 0.7))
                p.addLine(to: CGPoint(x: c.x - s * 0.5, y: c.y - s * 0.6))
                p.addLine(to: CGPoint(x: c.x + s * 0.3, y: c.y - s * 0.85))
                p.addLine(to: CGPoint(x: c.x + s * 0.95, y: c.y + s * 0.2))
                p.addLine(to: CGPoint(x: c.x + s * 0.6, y: c.y + s * 0.7))
                p.closeSubpath()
            }
            context.fill(boulder, with: .color(Color(red: 0.50, green: 0.52, blue: 0.57)))
            context.fill(Path { p in
                p.move(to: CGPoint(x: c.x + s * 0.3, y: c.y - s * 0.85))
                p.addLine(to: CGPoint(x: c.x + s * 0.95, y: c.y + s * 0.2))
                p.addLine(to: CGPoint(x: c.x + s * 0.6, y: c.y + s * 0.7))
                p.closeSubpath()
            }, with: .color(Color(red: 0.38, green: 0.40, blue: 0.45)))
            context.stroke(boulder, with: .color(Color(red: 0.66, green: 0.68, blue: 0.72).opacity(0.45)), lineWidth: 0.7)
        case .flowers:
            // Blooms in spring and summer; bare stems otherwise.
            let blooming = season == .spring || season == .summer
            let bloom = season == .spring
                ? Color(red: 0.85, green: 0.70, blue: 0.75)
                : Color(red: 0.84, green: 0.76, blue: 0.52)
            for i in 0..<4 {
                let a = Double(i) * 1.9
                let px = c.x + CGFloat(cos(a)) * s * 0.6
                let py = c.y + CGFloat(sin(a)) * s * 0.4
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: px, y: py + s * 0.4))
                    p.addLine(to: CGPoint(x: px, y: py))
                }, with: .color(Color(red: 0.42, green: 0.54, blue: 0.42)), lineWidth: 0.8)
                if blooming {
                    context.fill(Path(ellipseIn: CGRect(x: px - 1, y: py - 1.6, width: 2, height: 2)),
                                 with: .color(bloom))
                }
            }
        case .reeds:
            let reed = Color(red: 0.54, green: 0.62, blue: 0.48)
            for i in 0..<5 {
                let px = c.x + CGFloat(i - 2) * s * 0.28
                let lean = CGFloat(i - 2) * 0.6
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: px, y: c.y + s * 0.6))
                    p.addLine(to: CGPoint(x: px + lean, y: c.y - s * 0.9))
                }, with: .color(reed), lineWidth: 1)
            }
        case .stump:
            context.stroke(Path(CGRect(x: c.x - s * 0.4, y: c.y - s * 0.2,
                                       width: s * 0.8, height: s * 0.5)),
                           with: .color(Color(red: 0.44, green: 0.36, blue: 0.28)), lineWidth: 1)
        case .pond:
            let water = season == .winter
                ? Color(red: 0.60, green: 0.70, blue: 0.80)
                : Color(red: 0.32, green: 0.46, blue: 0.56)
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 1.3, y: c.y - s * 0.7,
                                                width: s * 2.6, height: s * 1.4)),
                         with: .color(water.opacity(0.35)))
            context.stroke(Path(ellipseIn: CGRect(x: c.x - s * 1.3, y: c.y - s * 0.7,
                                                  width: s * 2.6, height: s * 1.4)),
                           with: .color(water), lineWidth: 1)
        case .cactus:
            let green = Color(red: 0.46, green: 0.60, blue: 0.46)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x, y: c.y + s * 0.9))
                p.addLine(to: CGPoint(x: c.x, y: c.y - s * 1.1))
                p.move(to: CGPoint(x: c.x, y: c.y - s * 0.2))
                p.addLine(to: CGPoint(x: c.x - s * 0.6, y: c.y - s * 0.2))
                p.addLine(to: CGPoint(x: c.x - s * 0.6, y: c.y - s * 0.7))
                p.move(to: CGPoint(x: c.x, y: c.y - s * 0.5))
                p.addLine(to: CGPoint(x: c.x + s * 0.55, y: c.y - s * 0.5))
                p.addLine(to: CGPoint(x: c.x + s * 0.55, y: c.y - s * 0.95))
            }, with: .color(green), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        case .snowdrift:
            context.fill(Path { p in
                p.move(to: CGPoint(x: c.x - s, y: c.y + s * 0.35))
                p.addQuadCurve(to: CGPoint(x: c.x + s, y: c.y + s * 0.35),
                               control: CGPoint(x: c.x, y: c.y - s * 0.6))
                p.closeSubpath()
            }, with: .color(Color(red: 0.74, green: 0.80, blue: 0.88).opacity(0.32)))
        case .ruinPillar:
            context.stroke(Path(CGRect(x: c.x - s * 0.25, y: c.y - s * 1.1,
                                       width: s * 0.5, height: s * 1.5)),
                           with: .color(Theme.boneDim), lineWidth: 1)

        case .cliff:
            // A face with a lit top edge and a deep shadow at its foot, so it
            // reads as ground you could not walk up.
            let face = Path { p in
                p.move(to: CGPoint(x: c.x - s * 1.3, y: c.y + s * 0.7))
                p.addLine(to: CGPoint(x: c.x - s * 0.9, y: c.y - s * 0.9))
                p.addLine(to: CGPoint(x: c.x + s * 0.3, y: c.y - s * 1.1))
                p.addLine(to: CGPoint(x: c.x + s * 1.3, y: c.y - s * 0.3))
                p.addLine(to: CGPoint(x: c.x + s * 1.1, y: c.y + s * 0.7))
                p.closeSubpath()
            }
            context.fill(face, with: .color(Color(red: 0.30, green: 0.29, blue: 0.31)))
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.9, y: c.y - s * 0.9))
                p.addLine(to: CGPoint(x: c.x + s * 0.3, y: c.y - s * 1.1))
                p.addLine(to: CGPoint(x: c.x + s * 1.3, y: c.y - s * 0.3))
            }, with: .color(Theme.bone.opacity(0.5)), lineWidth: 1)
            // Strata, and the dark at the base.
            for band in 1...2 {
                let y = c.y - s * 0.6 + CGFloat(band) * s * 0.45
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: c.x - s * 1.1, y: y))
                    p.addLine(to: CGPoint(x: c.x + s * 1.1, y: y))
                }, with: .color(.black.opacity(0.22)), lineWidth: 0.7)
            }
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 1.2, y: c.y + s * 0.5,
                                                width: s * 2.4, height: s * 0.45)),
                         with: .color(.black.opacity(0.25)))

        case .crag:
            // A spire — two jagged teeth, the taller one lit down one side.
            let spire = Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.8, y: c.y + s * 0.7))
                p.addLine(to: CGPoint(x: c.x - s * 0.2, y: c.y - s * 1.4))
                p.addLine(to: CGPoint(x: c.x + s * 0.25, y: c.y - s * 0.2))
                p.addLine(to: CGPoint(x: c.x + s * 0.6, y: c.y - s * 0.95))
                p.addLine(to: CGPoint(x: c.x + s * 0.95, y: c.y + s * 0.7))
                p.closeSubpath()
            }
            context.fill(spire, with: .color(Color(red: 0.33, green: 0.32, blue: 0.35)))
            context.stroke(spire, with: .color(Theme.bone.opacity(0.42)), lineWidth: 0.8)

        case .dune:
            // A long low ridge with a bright windward face.
            let ridge = Path { p in
                p.move(to: CGPoint(x: c.x - s * 1.5, y: c.y + s * 0.45))
                p.addQuadCurve(to: CGPoint(x: c.x + s * 1.5, y: c.y + s * 0.45),
                               control: CGPoint(x: c.x + s * 0.3, y: c.y - s * 0.85))
                p.closeSubpath()
            }
            context.fill(ridge, with: .color(Color(red: 0.66, green: 0.57, blue: 0.38).opacity(0.5)))
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 1.5, y: c.y + s * 0.45))
                p.addQuadCurve(to: CGPoint(x: c.x + s * 1.5, y: c.y + s * 0.45),
                               control: CGPoint(x: c.x + s * 0.3, y: c.y - s * 0.85))
            }, with: .color(Theme.bone.opacity(0.3)), lineWidth: 0.7)

        case .deadTree:
            // A bare snag: a pale forked trunk, no crown at all.
            let bone = Color(red: 0.62, green: 0.58, blue: 0.50)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x, y: c.y + s * 0.7))
                p.addLine(to: CGPoint(x: c.x - s * 0.1, y: c.y - s * 1.2))
                p.move(to: CGPoint(x: c.x - s * 0.08, y: c.y - s * 0.5))
                p.addLine(to: CGPoint(x: c.x + s * 0.7, y: c.y - s * 1.0))
                p.move(to: CGPoint(x: c.x - s * 0.09, y: c.y - s * 0.85))
                p.addLine(to: CGPoint(x: c.x - s * 0.75, y: c.y - s * 1.25))
            }, with: .color(bone), lineWidth: max(0.7, s * 0.16))

        case .tallGrass:
            // Tufts leaning one way, so a meadow has a wind in it.
            for blade in 0..<5 {
                let dx = (CGFloat(blade) - 2) * s * 0.32
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: c.x + dx, y: c.y + s * 0.5))
                    p.addQuadCurve(to: CGPoint(x: c.x + dx + s * 0.42, y: c.y - s * 0.75),
                                   control: CGPoint(x: c.x + dx, y: c.y - s * 0.2))
                }, with: .color(Color(red: 0.44, green: 0.52, blue: 0.30).opacity(0.75)),
                   lineWidth: 0.8)
            }

        case .mushroom:
            // A little cluster in the leaf litter.
            for (dx, scale) in [(-0.45, 0.8), (0.0, 1.0), (0.4, 0.65)] {
                let m = CGPoint(x: c.x + CGFloat(dx) * s, y: c.y + s * 0.35)
                let r = s * 0.42 * CGFloat(scale)
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: m.x, y: m.y))
                    p.addLine(to: CGPoint(x: m.x, y: m.y - r * 0.9))
                }, with: .color(Theme.bone.opacity(0.55)), lineWidth: 0.7)
                context.fill(Path { p in
                    p.move(to: CGPoint(x: m.x - r, y: m.y - r * 0.85))
                    p.addQuadCurve(to: CGPoint(x: m.x + r, y: m.y - r * 0.85),
                                   control: CGPoint(x: m.x, y: m.y - r * 2.1))
                    p.closeSubpath()
                }, with: .color(Color(red: 0.60, green: 0.34, blue: 0.28)))
            }

        case .driftwood:
            // Bleached wood above the tideline, lying down.
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 1.1, y: c.y + s * 0.3))
                p.addQuadCurve(to: CGPoint(x: c.x + s * 1.1, y: c.y + s * 0.05),
                               control: CGPoint(x: c.x, y: c.y - s * 0.3))
            }, with: .color(Color(red: 0.68, green: 0.64, blue: 0.57)),
               style: StrokeStyle(lineWidth: max(1, s * 0.28), lineCap: .round))
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x + s * 0.3, y: c.y + s * 0.1))
                p.addLine(to: CGPoint(x: c.x + s * 0.8, y: c.y - s * 0.5))
            }, with: .color(Color(red: 0.68, green: 0.64, blue: 0.57)), lineWidth: max(0.7, s * 0.16))

        case .hotSpring:
            // Steaming water in a rim of mineral stone.
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.9, y: c.y - s * 0.4,
                                                width: s * 1.8, height: s * 0.9)),
                         with: .color(Color(red: 0.76, green: 0.72, blue: 0.60).opacity(0.5)))
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.62, y: c.y - s * 0.26,
                                                width: s * 1.24, height: s * 0.6)),
                         with: .color(Color(red: 0.34, green: 0.62, blue: 0.66).opacity(0.8)))
            for wisp in 0..<2 {
                let dx = CGFloat(wisp) * s * 0.4 - s * 0.2
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: c.x + dx, y: c.y - s * 0.35))
                    p.addQuadCurve(to: CGPoint(x: c.x + dx + s * 0.2, y: c.y - s * 1.2),
                                   control: CGPoint(x: c.x + dx - s * 0.3, y: c.y - s * 0.8))
                }, with: .color(Theme.bone.opacity(0.22)), lineWidth: 0.8)
            }
        }
    }

    /// Open water along one edge of a coastal map, with a beach fading into it
    /// and a surf line that breathes.
    ///
    /// A coast used to be a field with a stream through it, exactly like the
    /// plains — the one country whose whole character is the water had none.
    private static func sea(
        _ context: inout GraphicsContext, rect: CGRect, shore: ShoreShape?,
        season: Season, time: Double
    ) {
        guard let shore else { return }
        // Walk the coast in steps, so the waterline wanders rather than ruling
        // a straight edge across the map.
        let steps = 64
        func waterPoint(_ t: Double, reach: Double) -> CGPoint {
            let p: LocalPoint
            switch shore.side {
            case .north: p = LocalPoint(x: t, y: reach)
            case .south: p = LocalPoint(x: t, y: 1 - reach)
            case .west:  p = LocalPoint(x: reach, y: t)
            case .east:  p = LocalPoint(x: 1 - reach, y: t)
            }
            return point(p, in: rect)
        }
        func edgePoint(_ t: Double) -> CGPoint { waterPoint(t, reach: 0) }

        // The tide breathes: the whole waterline creeps in and out a little.
        let tide = sin(time * 0.09) * 0.006

        var water = Path()
        water.move(to: edgePoint(0))
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            water.addLine(to: waterPoint(t, reach: shore.reach(at: t) + tide))
        }
        water.addLine(to: edgePoint(1))
        water.closeSubpath()

        let deep = season == .winter
            ? Color(red: 0.13, green: 0.22, blue: 0.30)
            : Color(red: 0.12, green: 0.26, blue: 0.36)
        context.fill(water, with: .color(deep))

        // The shallows: a paler band just inside the waterline.
        var shallow = Path()
        shallow.move(to: waterPoint(0, reach: shore.reach(at: 0) + tide))
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            shallow.addLine(to: waterPoint(t, reach: shore.reach(at: t) + tide))
        }
        for step in stride(from: steps, through: 0, by: -1) {
            let t = Double(step) / Double(steps)
            shallow.addLine(to: waterPoint(t, reach: shore.reach(at: t) + tide - 0.035))
        }
        shallow.closeSubpath()
        context.fill(shallow, with: .color(Color(red: 0.22, green: 0.44, blue: 0.52).opacity(0.55)))

        // Surf, running along the coast rather than sitting still.
        var surf = Path()
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let foam = shore.reach(at: t) + tide + sin(t * 26 + time * 0.9) * 0.004
            let p = waterPoint(t, reach: foam)
            step == 0 ? surf.move(to: p) : surf.addLine(to: p)
        }
        context.stroke(surf, with: .color(Theme.bone.opacity(0.42)), lineWidth: 1.1)

        if season == .winter {
            // Ice hugging the shore.
            context.stroke(surf, with: .color(Color(red: 0.80, green: 0.86, blue: 0.92).opacity(0.3)),
                           lineWidth: 3)
        }
    }

    // MARK: - Resource deposits

    private static func deposits(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap,
        season: Season, zoom: CGFloat = 1, showLabels: Bool = false
    ) {
        // Only the deposits that are genuinely a *patch of worked ground*.
        //
        // A wood is drawn as trees and a massif as blocks, and the node behind
        // them is a ledger, not a place: drawing it too put a "Forest · 87 %"
        // glyph in the middle of an actual wood, which is the duplication the
        // whole entity layer exists to remove. Fields and herb beds keep
        // theirs, because a tilled plot really is one thing.
        for node in map.nodes
        where map.isExplored(node.position) && !FloraEngine.isEntityBacked(node.kind, in: map) {
            let center = point(node.position, in: rect)
            let fraction = node.capacity > 0 ? node.amount / node.capacity : 1
            drawDeposit(node.kind, at: center, fraction: fraction,
                        shade: Theme.depositShade(node.kind), season: season,
                        zoom: zoom, context: &context)
            if showLabels {
                let caption = Text("\(node.kind.displayLabel) · \(Int(fraction * 100)) %")
                    .font(.system(size: 5.5))
                    .foregroundStyle(Theme.boneDim)
                context.draw(context.resolve(caption),
                             at: CGPoint(x: center.x, y: center.y + 16 * zoom))
            }
        }
    }

    private static func drawDeposit(
        _ kind: LocalResourceKind, at c: CGPoint, fraction: Double,
        shade: Color, season: Season, zoom: CGFloat = 1, context: inout GraphicsContext
    ) {
        let count = max(2, Int(3 + fraction * 5))
        let z = zoom
        switch kind {
        case .field:
            // A tilled plot. The rows follow the calendar: green shoots in
            // spring, gold in summer, stubble in autumn, snow-dusted in winter.
            let plot = CGRect(x: c.x - 12 * z, y: c.y - 8 * z, width: 24 * z, height: 16 * z)
            context.stroke(Path(plot), with: .color(shade.opacity(0.5)), lineWidth: 1)
            let rowColor: Color
            switch season {
            case .spring: rowColor = Color(red: 0.55, green: 0.68, blue: 0.42)
            case .summer: rowColor = Color(red: 0.80, green: 0.72, blue: 0.40)
            case .autumn: rowColor = Color(red: 0.72, green: 0.58, blue: 0.34)
            case .winter: rowColor = Color(red: 0.62, green: 0.66, blue: 0.74)
            }
            for i in 0..<4 {
                let y = plot.minY + (CGFloat(i) * 4 + 2) * z
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: plot.minX + 2 * z, y: y))
                    p.addLine(to: CGPoint(x: plot.maxX - 2 * z, y: y))
                }, with: .color(rowColor.opacity(season == .winter ? 0.35 : 0.35 + fraction * 0.5)),
                style: StrokeStyle(lineWidth: 1, dash: season == .winter ? [2, 3] : []))
            }
        case .forest:
            let leaf = season == .autumn
                ? Color(red: 0.70, green: 0.50, blue: 0.30)
                : (season == .winter ? Color(red: 0.48, green: 0.54, blue: 0.54) : shade)
            for i in 0..<count {
                let a = Double(i) * 2.399
                let d = Double(i % 3) * 5 * z
                let p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
                context.stroke(Path { path in
                    path.move(to: CGPoint(x: p.x, y: p.y - 6 * z))
                    path.addLine(to: CGPoint(x: p.x - 3.4 * z, y: p.y + 2 * z))
                    path.addLine(to: CGPoint(x: p.x + 3.4 * z, y: p.y + 2 * z))
                    path.closeSubpath()
                }, with: .color(leaf.opacity(0.85)), lineWidth: 1)
            }
        case .stone:
            for i in 0..<max(2, count / 2) {
                let ox = c.x + (CGFloat((i * 13) % 17) - 8) * z
                let oy = c.y + (CGFloat((i * 7) % 11) - 5) * z
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: ox - 4 * z, y: oy + 3 * z))
                    p.addLine(to: CGPoint(x: ox - 2 * z, y: oy - 3 * z))
                    p.addLine(to: CGPoint(x: ox + 3 * z, y: oy - 2 * z))
                    p.addLine(to: CGPoint(x: ox + 4 * z, y: oy + 3 * z))
                    p.closeSubpath()
                }, with: .color(shade.opacity(0.85)), lineWidth: 1)
            }
        case .herbs:
            let herb = season == .winter ? shade.opacity(0.4) : shade.opacity(0.85)
            for i in 0..<count {
                let ox = c.x + (CGFloat((i * 11) % 19) - 9) * z
                let oy = c.y + (CGFloat((i * 5) % 13) - 6) * z
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: ox, y: oy + 2.5 * z))
                    p.addLine(to: CGPoint(x: ox, y: oy - 2 * z))
                    p.move(to: CGPoint(x: ox - 1.6 * z, y: oy))
                    p.addLine(to: CGPoint(x: ox, y: oy - 1.4 * z))
                    p.addLine(to: CGPoint(x: ox + 1.6 * z, y: oy))
                }, with: .color(herb), lineWidth: 1)
            }
        case .ironOre:
            // A cut face with the seam running through it — rock, but rock
            // that's worth something to a forge.
            let face = CGRect(x: c.x - 9 * z, y: c.y - 6 * z, width: 18 * z, height: 12 * z)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: face.minX, y: face.maxY))
                p.addLine(to: CGPoint(x: face.minX + 3 * z, y: face.minY))
                p.addLine(to: CGPoint(x: face.maxX - 3 * z, y: face.minY))
                p.addLine(to: CGPoint(x: face.maxX, y: face.maxY))
                p.closeSubpath()
            }, with: .color(shade.opacity(0.55)), lineWidth: 1)
            for i in 0..<max(2, count / 2) {
                let t = Double(i) / Double(max(1, count / 2))
                let y = face.minY + CGFloat(t) * face.height
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: face.minX + 3 * z, y: y))
                    p.addLine(to: CGPoint(x: face.maxX - 4 * z, y: y + 1.5 * z))
                }, with: .color(shade.opacity(0.35 + fraction * 0.5)),
                style: StrokeStyle(lineWidth: 1.4, dash: [3, 2]))
            }
        case .clay:
            // A dug pit: an open bowl with spoil heaped beside it.
            context.stroke(Path { p in
                p.addArc(center: CGPoint(x: c.x, y: c.y - 1 * z), radius: 8 * z,
                         startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            }, with: .color(shade.opacity(0.7)), lineWidth: 1)
            for i in 0..<max(2, count / 2) {
                let ox = c.x + (CGFloat((i * 9) % 15) - 7) * z
                let oy = c.y + 4 * z + CGFloat(i % 2) * 2 * z
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: ox - 3 * z, y: oy))
                    p.addLine(to: CGPoint(x: ox, y: oy - 2.4 * z))
                    p.addLine(to: CGPoint(x: ox + 3 * z, y: oy))
                }, with: .color(shade.opacity(0.3 + fraction * 0.5)), lineWidth: 1)
            }
        }
    }

    // MARK: - Buildings

    /// What a structure looks like on the map. Derived from what the building
    /// actually *does*, so new content picks up a sensible silhouette for free.
    /// The silhouettes a structure can be drawn as.
    ///
    /// Eight of these used to carry all forty-seven buildings, which is why a
    /// spaceport and a workshop were the same shed and every library, school,
    /// bank and market was the same Greek temple. A colony reads as a place
    /// when its skyline has more than one idea in it.
    /// What a building looks like.
    ///
    /// Twenty-nine of these for forty-seven buildings, because thirteen was not
    /// enough to tell them apart: thirty-six of the forty-seven stated no
    /// `look` at all and had their shape *derived* from their numbers, which
    /// put thirteen of them on `hall` and nine on `plant`. A farm, a granary
    /// and a well were the same barrel. Every building names its own archetype
    /// now, and no archetype carries more than four.
    enum BuildingGlyph {
        // Where people live
        case house      // hut, longhouse
        case tenement   // apartment block, arcology — stacked storeys
        // Ground and wood
        case farm       // furrows and a low barn
        case lodge      // the hunters', with the racks outside
        case sawmill    // a timber stack and a saw frame
        case mine       // a cut into the rock
        case well       // a ring of stones and a windlass
        // Fire and craft
        case workshop   // light craft
        case forge      // bloomery, foundry — the hearth that glows
        case cookhouse  // ovens and a standing fire — where the harvest is eaten
        case plant      // heavy industry, the smoking block
        case tanks      // refinery, chemical works
        case rail       // a shed, a water tower and track
        // Knowing
        case hall       // library, school, university
        case lab        // the clean block, glass and rooftop plant
        case dish       // observatory, orbital array
        // Trade and rule
        case market     // stalls under awnings
        case vault      // the bank: a squat stone strongbox
        case temple     // civic monument
        case clinic     // hospital, clinic
        case granary    // food and stores
        case aqueduct   // a run of arches
        // Holding the line
        case wall       // a run of palisade or masonry
        case tower      // the watchtower
        case barracks   // a long low block under a banner
        // Power
        case mill       // the wheel and the sails
        case generator  // a machine that makes power
        case turbine    // the tall three-bladed kind
        case array      // fields of panels
        case dam        // a curved wall holding water
        case pad        // spaceport
    }

    /// The archetype names `buildings.json` may state outright via `look`.
    static func glyph(named name: String) -> BuildingGlyph? {
        switch name {
        case "house": return .house
        case "tenement": return .tenement
        case "farm": return .farm
        case "lodge": return .lodge
        case "sawmill": return .sawmill
        case "mine": return .mine
        case "well": return .well
        case "workshop": return .workshop
        case "forge": return .forge
        case "plant": return .plant
        case "tanks": return .tanks
        case "rail": return .rail
        case "hall": return .hall
        case "lab": return .lab
        case "dish": return .dish
        case "market": return .market
        case "vault": return .vault
        case "temple": return .temple
        case "clinic": return .clinic
        case "granary": return .granary
        case "cookhouse": return .cookhouse
        case "aqueduct": return .aqueduct
        case "wall": return .wall
        case "tower": return .tower
        case "barracks": return .barracks
        case "mill": return .mill
        case "generator": return .generator
        case "turbine": return .turbine
        case "array": return .array
        case "dam": return .dam
        case "pad": return .pad
        default: return nil
        }
    }

    /// What a building looks like: what the content says, else what the numbers
    /// imply. Order matters — the strongest signal is asked first.
    ///
    /// Deriving alone was never enough. Every materials producer answers
    /// `workKind` the same way, so lumberyard, quarry, workshop, foundry and
    /// factory were all drawn as one waterwheel; `look` is how the handful the
    /// numbers cannot separate say what they are.
    static func glyph(for def: BuildingDefinition) -> BuildingGlyph {
        if let stated = def.look, let g = glyph(named: stated) { return g }
        if def.housing > 0 { return .house }
        if def.defense > 0 { return .tower }
        // Anything that smokes is heavy industry, whatever else it does.
        if def.pollution >= 10 { return .plant }
        // The furthest-out civic works read as nothing else.
        if def.era == .nearFuture, def.production[.influence] > 0 { return .pad }
        if def.production[.energy] > 0 {
            // Panels and turbines lie flat over the ground; everything earlier
            // that makes power is a machine in a shed.
            return def.era == .nearFuture ? .array : .generator
        }
        if def.production[.knowledge] > 0 { return .hall }
        if def.production[.influence] > 0 { return .market }
        if def.production[.food] > 0 || def.storage > 0 { return .granary }
        return .workshop
    }

    /// One structure in the settlement, in normalised (0…1) space — the shared
    /// truth for the renderer, the tap targets *and* the colonists' motion, so
    /// a builder walks to the same scaffolding you see.
    struct NormalizedBuilding: Identifiable {
        let id: Int              // stable within a layout pass
        let definitionID: String
        let name: String
        let glyph: BuildingGlyph
        let center: LocalPoint
        /// Glyph size as a fraction of the canvas's short side.
        let size: Double
        /// The ground the building actually covers, as fractions of the short
        /// side — width×height of its footprint, so a 2×2 stands on a 2×2 plot
        /// instead of hovering as a single glyph.
        let footprintW: Double
        let footprintH: Double
        let underConstruction: Bool
        /// Construction completion 0…1 (1 when built).
        let progress: Double
        /// A stable per-building seed for cosmetic variation (tone, size).
        let seed: UInt64
        /// The era that raised it — timber and thatch give way to brick, then
        /// to panel and glass, so a data centre is not a wattle hut in a hat.
        let era: Era
        /// The colonists the *simulation* has posted here
        /// (`BuildingPlacement.assignedPawnIDs`). The canvas stands them on
        /// this lot rather than guessing a workplace from their trade, so what
        /// the player watches is the roster the engine actually keeps.
        let assignedPawnIDs: [UUID]
        /// The placement this came from, where there is one. How a colonist's
        /// `homeID` finds the house it names.
        let placementID: UUID?
        /// How sound the building is, 0…1.
        let condition: Double
    }

    /// The same structure mapped to pixels for one frame.
    struct PlacedBuilding: Identifiable {
        let id: Int
        let definitionID: String
        let name: String
        let glyph: BuildingGlyph
        let center: CGPoint
        let size: CGFloat
        /// The building's footprint on the ground, in pixels.
        let footprint: CGSize
        let underConstruction: Bool
        let progress: Double
        let seed: UInt64
        let era: Era
        /// How many colonists the engine posted here — the room is furnished
        /// with a station apiece, and they are drawn standing at them.
        let workers: Int
        /// …and how many live here, for a dwelling: a bed apiece.
        let residents: Int
        /// How sound it is, 0…1 — cracks, then a hole in the roof, then a ruin.
        let condition: Double
    }

    /// A stable per-building seed for cosmetic variation — from a placement's
    /// id where there is one, else its kind and ring slot.
    static func buildingSeed(_ uuid: UUID) -> UInt64 {
        let u = uuid.uuid
        return UInt64(u.0) << 56 | UInt64(u.1) << 48 | UInt64(u.2) << 40 | UInt64(u.3) << 32
             | UInt64(u.4) << 24 | UInt64(u.5) << 16 | UInt64(u.6) << 8 | UInt64(u.7)
    }
    static func buildingSeed(_ id: String, _ index: Int) -> UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in id.utf8 { h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3 }
        return h ^ UInt64(bitPattern: Int64(index))
    }

    /// Where the settlement's heart sits on the canvas — the fog is cleared
    /// around here, so this is the only part of the world anyone has actually
    /// seen.
    static let colonyHeart = LocalPoint(x: 0.5, y: 0.52)
    /// How wide a slice of the canvas the whole build grid covers.
    ///
    /// Widened from 0.42 once buildings gained insides: an 18×18 grid squeezed
    /// into 0.42 gave each tile about nine pixels at rest, which is a room you
    /// cannot see into and a town whose people are drawn on top of one another.
    /// Widened again to 0.58 when the complaint was that the town was not
    /// legible at a glance. Two things move together for that: this, and
    /// `Camera.opening` — a wider span gives each building more ground and the
    /// opening zoom puts that ground across the screen.
    ///
    /// Mirrored by `SettlementGeometry.span` in the Core — a colonist must be
    /// sent to the building that is *drawn*, so the two must agree. Guarded by
    /// "The Core and the canvas agree about how wide the town is".
    static let colonySpan: Double = 0.58

    /// Maps a grid tile to the point on the canvas it sits at, centred on the
    /// heart so the built colony always lands inside the cleared ground.
    static func canvasPoint(for coord: TileCoord, in colony: ColonyMap) -> LocalPoint {
        let fx = (Double(coord.x) + 0.5) / Double(max(1, colony.width)) - 0.5
        let fy = (Double(coord.y) + 0.5) / Double(max(1, colony.height)) - 0.5
        return LocalPoint(
            x: colonyHeart.x + fx * colonySpan,
            y: colonyHeart.y + fy * colonySpan)
    }

    /// The inverse of `canvasPoint`: which build tile a point on the canvas
    /// falls on, or nil when it lies off the colony's ground. This is what lets
    /// the player place a building by pointing at the settlement itself rather
    /// than at an abstract grid on another screen.
    static func tile(at p: LocalPoint, in colony: ColonyMap) -> TileCoord? {
        guard colony.width > 0, colony.height > 0, colonySpan > 0 else { return nil }
        let fx = (p.x - colonyHeart.x) / colonySpan + 0.5
        let fy = (p.y - colonyHeart.y) / colonySpan + 0.5
        guard fx >= 0, fx < 1, fy >= 0, fy < 1 else { return nil }
        return TileCoord(min(colony.width - 1, Int(fx * Double(colony.width))),
                         min(colony.height - 1, Int(fy * Double(colony.height))))
    }

    /// Where the settlement's structures stand, in normalised space. The grid
    /// is the truth wherever one exists; the rings are only the fallback for a
    /// colony that hasn't been laid out yet.
    static func normalizedLayout(
        settlement: Settlement, registry: GameDataRegistry
    ) -> [NormalizedBuilding] {
        if let colony = settlement.colony, !colony.placements.isEmpty {
            return gridLayout(settlement: settlement, colony: colony, registry: registry)
        }
        return ringLayout(settlement: settlement, registry: registry)
    }

    /// The pixel-space layout for one frame — what drawing and hit-testing use.
    static func layout(
        settlement: Settlement, registry: GameDataRegistry, rect: CGRect
    ) -> [PlacedBuilding] {
        let unit = min(rect.width, rect.height)
        // Who sleeps where, counted once for the whole frame.
        var household: [UUID: Int] = [:]
        for pawn in settlement.pawns {
            guard let home = pawn.homeID else { continue }
            household[home, default: 0] += 1
        }
        return normalizedLayout(settlement: settlement, registry: registry).map { b in
            PlacedBuilding(id: b.id, definitionID: b.definitionID, name: b.name, glyph: b.glyph,
                           center: point(b.center, in: rect), size: unit * b.size,
                           footprint: CGSize(width: b.footprintW * unit, height: b.footprintH * unit),
                           underConstruction: b.underConstruction, progress: b.progress,
                           seed: b.seed, era: b.era, workers: b.assignedPawnIDs.count,
                           residents: b.placementID.map { household[$0] ?? 0 } ?? 0,
                           condition: b.condition)
        }
    }

    /// The structures as actually placed on the build grid.
    private static func gridLayout(
        settlement: Settlement, colony: ColonyMap, registry: GameDataRegistry
    ) -> [NormalizedBuilding] {
        colony.placements.prefix(maxVisibleBuildings).enumerated().map { index, placement in
            // `coord` is the footprint's top-left origin, so a multi-tile
            // building is nudged to the middle of what it covers — and drawn
            // larger for covering it.
            let origin = canvasPoint(for: placement.coord, in: colony)
            let p = LocalPoint(
                x: origin.x + Double(placement.width - 1) * 0.5 / Double(max(1, colony.width)) * colonySpan,
                y: origin.y + Double(placement.height - 1) * 0.5 / Double(max(1, colony.height)) * colonySpan)
            let def = registry.building(placement.definitionID)
            let glyph = def.map(glyph(for:)) ?? .house
            let progress = settlement.constructions
                .first { $0.placementID == placement.id }?.fraction
            let label = def?.name.resolve(AppStrings.language) ?? placement.definitionID
            // The footprint in canvas fractions: one tile is this slice of the
            // built span, and the plot is as many tiles wide and tall as the
            // building covers.
            let tileW = colonySpan / Double(max(1, colony.width))
            let tileH = colonySpan / Double(max(1, colony.height))
            return NormalizedBuilding(
                id: index,
                definitionID: placement.definitionID,
                name: label,
                glyph: glyph,
                center: p,
                // Sized to the ground it owns, not to a bare tile count. The
                // old `0.021 × max(w, h)` was unrelated to the lot: a 3×2 came
                // out twice as wide as its own plot, so neighbouring buildings
                // grew into each other and the colony read as a heap of glyphs.
                // A body runs about 2.2 × `size` across, so this keeps it
                // inside the parcel while roofs still rise above it.
                size: min(Double(max(1, placement.width)) * tileW,
                          Double(max(1, placement.height)) * tileH) / 2.2,
                footprintW: Double(max(1, placement.width)) * tileW,
                footprintH: Double(max(1, placement.height)) * tileH,
                underConstruction: placement.underConstruction,
                progress: placement.underConstruction ? (progress ?? 0) : 1,
                seed: buildingSeed(placement.id),
                era: def?.era ?? .earlySettlement,
                assignedPawnIDs: placement.assignedPawnIDs,
                placementID: placement.id,
                condition: placement.condition)
        }
    }

    /// Calm rings around the heart, for a colony with no layout of its own yet.
    /// Civic buildings hold the centre; housing drifts to the outer rings.
    /// Pure and deterministic — the same settlement always lays out the same.
    private static func ringLayout(
        settlement: Settlement, registry: GameDataRegistry
    ) -> [NormalizedBuilding] {
        var expanded: [(id: String, name: String, glyph: BuildingGlyph, era: Era)] = []
        for instance in settlement.buildings {
            let def = registry.building(instance.definitionID)
            let g = def.map(glyph(for:)) ?? .house
            for _ in 0..<instance.count where expanded.count < maxVisibleBuildings {
                expanded.append((instance.definitionID,
                                 def?.name.resolve(AppStrings.language) ?? instance.definitionID,
                                 g, def?.era ?? .earlySettlement))
            }
        }
        guard !expanded.isEmpty else { return [] }
        expanded.sort { rank($0.glyph) < rank($1.glyph) }

        var placed: [NormalizedBuilding] = []
        var drawn = 0, ringIndex = 0
        while drawn < expanded.count {
            let perRing = ringIndex == 0 ? 1 : ringIndex * 6
            let radius = Double(ringIndex) * 0.052
            for slot in 0..<perRing where drawn < expanded.count {
                let angle = Double(slot) / Double(perRing) * 2 * .pi + Double(ringIndex) * 0.6
                // The y-step is damped: normalised y maps to the (taller)
                // screen height, and an uncorrected circle stretches into an
                // egg on a portrait phone.
                let c = LocalPoint(x: colonyHeart.x + cos(angle) * radius,
                                   y: colonyHeart.y + sin(angle) * radius * 0.72)
                placed.append(NormalizedBuilding(
                    id: drawn, definitionID: expanded[drawn].id,
                    name: expanded[drawn].name, glyph: expanded[drawn].glyph,
                    center: c, size: 0.021, footprintW: 0.05, footprintH: 0.05,
                    underConstruction: false, progress: 1,
                    seed: buildingSeed(expanded[drawn].id, drawn),
                    era: expanded[drawn].era,
                    assignedPawnIDs: [], placementID: nil, condition: 1))
                drawn += 1
            }
            ringIndex += 1
        }
        return placed
    }

    /// Civic buildings rank low (centre), housing high (outskirts).
    private static func rank(_ g: BuildingGlyph) -> Int {
        switch g {
        case .temple: return 0
        case .hall: return 1
        case .market: return 2
        case .granary: return 3
        case .cookhouse: return 3
        case .workshop: return 4
        case .mill: return 5
        case .plant: return 6
        case .generator: return 7
        case .array: return 8
        case .pad: return 9
        case .mine: return 10
        case .sawmill: return 10
        case .forge: return 6
        case .tanks: return 7
        case .rail: return 7
        case .lab: return 2
        case .dish: return 8
        case .vault: return 2
        case .clinic: return 3
        case .aqueduct: return 3
        case .turbine: return 8
        case .dam: return 9
        case .wall: return 13
        case .barracks: return 11
        case .well: return 3
        case .lodge: return 11
        case .farm: return 14
        case .tower: return 11
        case .house: return 12
        case .tenement: return 12
        }
    }

    private static func buildings(
        _ context: inout GraphicsContext, placed: [PlacedBuilding],
        time: Double, night: Double = 0, showLabels: Bool = false,
        zoom: CGFloat = 1, sun: SettlementLight.Sun = SettlementLight.sun(time: 0),
        selectedBuildingID: Int?
    ) {
        // Foundations first — every building's plot, drawn before any structure,
        // so a later lot never paints over an earlier roof and adjacent lots
        // knit into one cleared, built-up ground the town sits on.
        for building in placed {
            floorPlot(&context, at: building.center, footprint: building.footprint,
                      underConstruction: building.underConstruction)
        }
        // Then what the town throws across its own ground. Every shadow in one
        // path, filled once: a shadow must never fall on the *building* next
        // door, only on the earth between them.
        castShadows(&context, placed: placed, sun: sun)
        // Then the insides: floor, fittings, walls. Drawn under the roofs, so
        // pushing the camera in lifts the roof off a room that is already there
        // rather than swapping one drawing for another.
        let roof = SettlementInterior.roofFade(zoom: zoom)
        if roof < 0.999 {
            for building in placed where !building.underConstruction {
                SettlementInterior.draw(
                    &context, glyph: building.glyph, at: building.center,
                    footprint: building.footprint, seed: building.seed, era: building.era,
                    workers: building.workers, residents: building.residents,
                    night: night, time: time)
            }
        }
        for building in placed {
            if building.underConstruction {
                SettlementStructures.site(at: building.center, s: building.size,
                                          progress: building.progress, time: time, context: &context)
            } else if roof > 0.001 {
                // The roof, as solid as the distance warrants.
                var roofContext = context
                roofContext.opacity = roof
                SettlementStructures.building(building.glyph, at: building.center,
                                              s: building.size, time: time, night: night,
                                              seed: building.seed, era: building.era,
                                              footprint: building.footprint, context: &roofContext)
            }
            // What time and trouble have done to it, over whatever is drawn —
            // a ruin has to read as one whether its roof is on or off.
            if !building.underConstruction, building.condition < 0.92 {
                SettlementStructures.wear(&context, at: building.center,
                                          footprint: building.footprint,
                                          condition: building.condition, seed: building.seed)
            }
            if building.id == selectedBuildingID {
                let r = building.size * 2.6
                context.stroke(
                    Path(ellipseIn: CGRect(x: building.center.x - r, y: building.center.y - r,
                                           width: r * 2, height: r * 2)),
                    with: .color(Theme.accent), lineWidth: 1.5)
            }
            if showLabels {
                let caption = building.underConstruction
                    ? "\(Int(building.progress * 100)) %"
                    : building.name
                let label = Text(caption)
                    .font(.system(size: 5.5, weight: .medium))
                    .foregroundStyle(Theme.bone.opacity(0.75))
                context.draw(context.resolve(label),
                             at: CGPoint(x: building.center.x,
                                         y: building.center.y + building.size * 2.5))
            }
        }
    }

    /// How tall a structure stands, as a multiple of its glyph size — what
    /// decides how far it throws a shadow. A tower reaches across the square at
    /// evening; a field of panels barely lifts off the ground.
    static func height(of glyph: BuildingGlyph) -> CGFloat {
        switch glyph {
        case .tower:     return 3.4
        case .temple:    return 2.8
        case .plant:     return 2.6
        case .hall:      return 2.2
        case .mill:      return 2.2
        case .pad:       return 2.4
        case .granary:   return 1.9
        case .cookhouse: return 1.6
        case .house:     return 1.7
        case .market:    return 1.6
        case .workshop:  return 1.5
        case .generator: return 1.4
        case .mine:      return 1.2
        case .array:     return 0.6
        // The trades.
        case .tenement:  return 3.6
        case .turbine:   return 3.4
        case .dish:      return 2.6
        case .tanks:     return 2.4
        case .forge:     return 2.2
        case .vault:     return 2.0
        case .rail:      return 1.9
        case .dam:       return 1.8
        case .aqueduct:  return 1.8
        case .lab:       return 1.7
        case .clinic:    return 1.6
        case .barracks:  return 1.5
        case .lodge:     return 1.6
        case .sawmill:   return 1.3
        case .wall:      return 1.2
        case .well:      return 0.9
        case .farm:      return 1.1
        }
    }

    /// Everything the town throws on the ground, as one silhouette.
    private static func castShadows(
        _ context: inout GraphicsContext, placed: [PlacedBuilding],
        sun: SettlementLight.Sun
    ) {
        guard sun.strength > 0.01 else { return }
        var shadows = Path()
        for building in placed where !building.underConstruction {
            let tall = building.size * height(of: building.glyph)
            // A shadow starts at the foot of the wall, not at the roof line.
            let foot = CGPoint(x: building.center.x, y: building.center.y + building.size * 0.3)
            let base = CGSize(width: max(4, building.footprint.width * 0.78),
                              height: max(3, building.footprint.height * 0.52))
            shadows.addPath(SettlementLight.boxShadow(
                at: foot, footprint: base, height: tall, sun: sun))
        }
        guard !shadows.isEmpty else { return }
        context.fill(shadows, with: .color(SettlementLight.shadowColour(sun)))
    }

    /// The plot a structure stands on — cleared, framed ground the size of the
    /// building's footprint. This is the foundation of the multi-tile world:
    /// a 2×2 building owns a 2×2 lot, adjacent lots merge into built-up land,
    /// and a construction site reserves its ground with a dashed outline. Read
    /// only from the layout; nothing here touches the simulation.
    private static func floorPlot(
        _ context: inout GraphicsContext, at c: CGPoint, footprint: CGSize,
        underConstruction: Bool
    ) {
        guard footprint.width > 2, footprint.height > 2 else { return }
        // A hair of margin so neighbouring lots still read as separate parcels.
        let w = footprint.width * 0.92, h = footprint.height * 0.92
        let rect = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
        let radius = min(w, h) * 0.16
        let shape = Path(roundedRect: rect, cornerRadius: radius)
        if underConstruction {
            context.fill(shape, with: .color(Theme.bone.opacity(0.05)))
            context.stroke(shape, with: .color(Theme.boneFaint.opacity(0.65)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        } else {
            // Packed, cleared earth — warmer and a touch darker than the wild
            // grass, so the built ground reads as a place people made.
            //
            // Opaque, and rule 9 is why: ground tiles overlap by a hair so no
            // seam shows, and a *translucent* lot laid over them blends that
            // overlap twice and rules a bright grid inside every yard in the
            // town. At 0.6 alpha over dark grass it also came out as a near
            // black slab — the thing that read as a hole in the map.
            context.fill(shape, with: .color(Color(red: 0.27, green: 0.23, blue: 0.18)))
            context.stroke(shape, with: .color(Theme.boneFaint.opacity(0.4)), lineWidth: 0.8)
        }
    }

    // MARK: - Colonists

    /// Who gets drawn when the crowd is capped.
    ///
    /// The cap keeps a boom-town cheap, but taking a plain `prefix` means that
    /// in a colony past ninety souls the party out at the ruins — the one thing
    /// the player is deliberately watching — could fall off the end of the array
    /// and simply not be drawn. Anyone away goes in first; the rest fill the
    /// remaining seats.
    static func visibleAgents(_ settlement: Settlement) -> [Pawn] {
        guard settlement.pawns.count > maxVisibleAgents else { return settlement.pawns }
        let away = settlement.pawns.filter(\.isAway)
        guard !away.isEmpty else { return Array(settlement.pawns.prefix(maxVisibleAgents)) }
        let home = settlement.pawns.filter { !$0.isAway }
        return away + home.prefix(max(0, maxVisibleAgents - away.count))
    }

    private static func agents(
        _ context: inout GraphicsContext, rect: CGRect, settlement: Settlement,
        map: LocalMap, continuousTick: Double, registry: GameDataRegistry,
        time: Double, zoom: CGFloat, selectedPawnID: UUID?,
        battleReplay: SettlementBattle.Replay? = nil
    ) {
        let scene = AgentMotion.Scene(settlement: settlement, registry: registry,
                                      continuousTick: continuousTick, replay: battleReplay)
        let ticksPerYear = registry.config.ticksPerYear
        let close = SettlementCrowd.showsIndividuals(zoom: zoom)

        // Pushed in, people are people. Pulled back, a town of sixty drawn as
        // sixty eleven-pixel figures is a smear — so they gather into group
        // marks that say how many and at what, and resolve back into people as
        // the camera comes in.
        guard close else {
            let standing = visibleAgents(settlement).compactMap {
                pawn -> (id: UUID, position: LocalPoint, trade: WorkKind, hurt: Bool)? in
                let pose = AgentMotion.pose(for: pawn, map: map, scene: scene,
                                            time: time, ticksPerYear: ticksPerYear)
                guard map.isExplored(pose.position) else { return nil }
                return (pawn.id, pose.position, pawn.assignedWork,
                        pawn.body.needsTending || pawn.isBroken)
            }
            for cluster in SettlementCrowd.cluster(standing) {
                guard cluster.count >= SettlementCrowd.minimumGroup else {
                    // Two people read better as two people than as a mark
                    // saying "2".
                    for id in cluster.members {
                        guard let pawn = settlement.pawns.first(where: { $0.id == id }) else { continue }
                        let pose = AgentMotion.pose(for: pawn, map: map, scene: scene,
                                                    time: time, ticksPerYear: ticksPerYear)
                        SettlementFigures.draw(
                            pawn: pawn, pose: pose, at: point(pose.position, in: rect),
                            time: time, ticksPerYear: ticksPerYear,
                            selected: pawn.id == selectedPawnID, zoom: zoom,
                            context: &context)
                    }
                    continue
                }
                SettlementCrowd.draw(&context, cluster: cluster,
                                     at: point(cluster.position, in: rect),
                                     time: time, zoom: zoom)
            }
            return
        }

        for pawn in visibleAgents(settlement) {
            let pose = AgentMotion.pose(for: pawn, map: map, scene: scene,
                                        time: time, ticksPerYear: ticksPerYear)
            guard map.isExplored(pose.position) else { continue }
            // What they would do with what they are carrying — the same split
            // the simulation fights on, so a bow is drawn being drawn.
            // What is actually in their hands. A colony's militia is its
            // farmers: somebody who owns nothing swings the tool of their
            // trade, and somebody whose trade has no edge on it swings fists.
            let armed: SettlementFigures.Armament
            switch CombatEngine.weaponProfile(pawn, registry: registry)?.kind {
            case .ranged: armed = .bow
            case .melee:  armed = .blade
            case nil:     armed = .none
            }
            SettlementFigures.draw(
                pawn: pawn, pose: pose, at: point(pose.position, in: rect),
                time: time, ticksPerYear: ticksPerYear,
                selected: pawn.id == selectedPawnID, zoom: zoom, armed: armed,
                context: &context)
        }
    }

    // MARK: - Fog of war

    private static func fog(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap, time: Double
    ) {
        SettlementGround.fog(&context, rect: rect, map: map)
        scoutOrder(&context, rect: rect, map: map, time: time)
    }

    /// Where the player has sent the scouts, marked in the dark they were sent
    /// into. Without this an order lands silently and the tap reads as a
    /// no-op — the ground it points at is, by definition, not yet drawn.
    private static func scoutOrder(
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

    private static func seasonWash(
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
