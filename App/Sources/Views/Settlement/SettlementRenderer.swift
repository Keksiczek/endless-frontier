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
        var scale: CGFloat = 1
        var offset: CGSize = .zero

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
        selectedPawnID: UUID?,
        selectedBuildingID: Int?
    ) {
        let viewRect = CGRect(origin: .zero, size: size)
        let rect = worldRect(viewRect: viewRect, camera: camera)
        let night = nightness(time: time)
        // One world scale for everything drawn in absolute pixels. Geometry
        // derived from `rect` grows with the camera by construction; the
        // fixed-pixel art (figures, river body, deposit furniture, smoke) has
        // to be told — or zooming in grows the town and leaves its people
        // doll-sized.
        let zoom = camera.scale
        let showLabels = zoom >= 1.6
        ground(&context, rect: rect, map: map, season: season)
        zones(&context, rect: rect, settlement: settlement, season: season)
        paths(&context, rect: rect, settlement: settlement, registry: registry,
              map: map, zoom: zoom)
        heartGlow(&context, rect: rect)
        river(&context, rect: rect, river: map.river, season: season, zoom: zoom)
        scenery(&context, rect: rect, map: map, season: season)
        deposits(&context, rect: rect, map: map, season: season, zoom: zoom,
                 showLabels: showLabels)
        pois(&context, rect: rect, map: map, time: time, showLabels: showLabels)
        SettlementWildlife.draw(&context, rect: rect, map: map, time: time)

        let placed = layout(settlement: settlement, registry: registry, rect: rect)
        // Pushed in close, every structure says what it is — the answer to
        // "which roof is the library?" without a single tap.
        buildings(&context, placed: placed, time: time, night: night,
                  showLabels: showLabels, selectedBuildingID: selectedBuildingID)
        SettlementFigures.smoke(
            &context,
            houses: placed.filter { $0.glyph == .house && !$0.underConstruction },
            time: time, zoom: zoom)

        agents(&context, rect: rect, settlement: settlement, map: map, continuousTick: continuousTick,
               registry: registry, time: time, zoom: zoom, selectedPawnID: selectedPawnID)
        SettlementFigures.birds(&context, rect: rect, season: season, time: time, zoom: zoom)
        // A raid plays out over the scene it happens to — above the people,
        // under the fog, so the dark still hides what the colony cannot see.
        SettlementBattle.draw(&context, rect: rect, settlement: settlement,
                              continuousTick: continuousTick, time: time, zoom: zoom)
        fog(&context, rect: rect, map: map, time: time)
        // The seasonal wash is atmosphere over the lens, not part of the world,
        // so it stays in view space and doesn't slide when you pan.
        seasonWash(&context, rect: viewRect, size: size, season: season, time: time)
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
        context.fill(Path(rect),
                     with: .color(Color(red: 0.03, green: 0.05, blue: 0.12).opacity(night * 0.30)))
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
        tribe: Tribe?
    ) {
        let viewRect = CGRect(origin: .zero, size: size)
        let rect = worldRect(viewRect: viewRect, camera: camera)
        let night = nightness(time: time)
        let zoom = camera.scale
        let showLabels = zoom >= 1.6
        ground(&context, rect: rect, map: map, season: season)
        river(&context, rect: rect, river: map.river, season: season, zoom: zoom)
        scenery(&context, rect: rect, map: map, season: season)
        deposits(&context, rect: rect, map: map, season: season, zoom: zoom,
                 showLabels: showLabels)
        pois(&context, rect: rect, map: map, time: time, showLabels: showLabels)
        SettlementWildlife.draw(&context, rect: rect, map: map, time: time)
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

    /// The tiled earth: every revealed cell painted with its seeded ground
    /// cover in the current season's colours. Batched into one path per cover
    /// so a full map is a handful of fills, not a thousand.
    private static func ground(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap, season: Season
    ) {
        let cols = LocalMap.gridColumns, rows = LocalMap.gridRows
        let cw = rect.width / CGFloat(cols), ch = rect.height / CGFloat(rows)
        var batches: [GroundCover: Path] = [:]
        for index in map.exploredCells {
            let col = index % cols, row = index / cols
            guard row < rows else { continue }
            let cover = map.cover(column: col, row: row)
            batches[cover, default: Path()].addRect(
                CGRect(x: rect.minX + CGFloat(col) * cw, y: rect.minY + CGFloat(row) * ch,
                       width: cw + 0.6, height: ch + 0.6))
        }
        for (cover, path) in batches {
            context.fill(path, with: .color(coverColor(cover, season: season)))
        }
    }

    /// The raw earth tones, before the season passes over them. Lifted from
    /// the original near-black palette — the map read as permanently dusk.
    private static func baseCover(_ cover: GroundCover) -> (r: Double, g: Double, b: Double) {
        switch cover {
        case .grass:  return (0.15, 0.22, 0.15)
        case .meadow: return (0.19, 0.26, 0.16)
        case .dirt:   return (0.23, 0.19, 0.14)
        case .sand:   return (0.29, 0.26, 0.17)
        case .rock:   return (0.19, 0.20, 0.23)
        case .snow:   return (0.30, 0.33, 0.39)
        case .marsh:  return (0.15, 0.23, 0.20)
        }
    }

    /// The ground as the season paints it: fresh in spring, warm in summer,
    /// rusted in autumn, and pale under winter snow.
    static func coverColor(_ cover: GroundCover, season: Season) -> Color {
        var (r, g, b) = baseCover(cover)
        switch season {
        case .spring:
            g *= 1.22; r *= 0.96
        case .summer:
            r *= 1.12; g *= 1.10; b *= 0.94
        case .autumn:
            r *= 1.38; g *= 1.02; b *= 0.82
        case .winter:
            // Everything cools and lightens toward snow, but keeps a trace of
            // what lies underneath.
            r = r * 0.45 + 0.26; g = g * 0.45 + 0.28; b = b * 0.45 + 0.34
        }
        return Color(red: min(1, r), green: min(1, g), blue: min(1, b))
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
        showLabels: Bool = false
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
                    let threshold = propRoll(prop.id)
                    if fraction < threshold * 0.5 { continue }        // felled and hauled
                    if fraction < threshold * 0.9 { kind = .stump }   // fresh-cut
                }
            } else if kind == .rock || kind == .boulder {
                if let fraction = nearestNodeFraction(map: map, kind: .stone, to: prop.position) {
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
        }
    }

    // MARK: - Resource deposits

    private static func deposits(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap,
        season: Season, zoom: CGFloat = 1, showLabels: Bool = false
    ) {
        for node in map.nodes where map.isExplored(node.position) {
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
    enum BuildingGlyph {
        case house, granary, workshop, tower, temple, mine, mill, generator
    }

    static func glyph(for def: BuildingDefinition) -> BuildingGlyph {
        if def.housing > 0 { return .house }
        if def.defense > 0 { return .tower }
        if def.production[.knowledge] > 0 || def.production[.influence] > 0 { return .temple }
        if def.production[.energy] > 0 { return .generator }
        if def.production[.food] > 0 { return .granary }
        switch ColonyBuilder.workKind(for: def) {
        case .mining: return .mine
        case .logging: return .mill
        default: return .workshop
        }
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
    static let colonySpan: Double = 0.42

    /// Maps a grid tile to the point on the canvas it sits at, centred on the
    /// heart so the built colony always lands inside the cleared ground.
    static func canvasPoint(for coord: TileCoord, in colony: ColonyMap) -> LocalPoint {
        let fx = (Double(coord.x) + 0.5) / Double(max(1, colony.width)) - 0.5
        let fy = (Double(coord.y) + 0.5) / Double(max(1, colony.height)) - 0.5
        return LocalPoint(
            x: colonyHeart.x + fx * colonySpan,
            y: colonyHeart.y + fy * colonySpan)
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
        return normalizedLayout(settlement: settlement, registry: registry).map { b in
            PlacedBuilding(id: b.id, definitionID: b.definitionID, name: b.name, glyph: b.glyph,
                           center: point(b.center, in: rect), size: unit * b.size,
                           footprint: CGSize(width: b.footprintW * unit, height: b.footprintH * unit),
                           underConstruction: b.underConstruction, progress: b.progress, seed: b.seed)
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
                size: 0.021 * Double(max(placement.width, placement.height)),
                footprintW: Double(max(1, placement.width)) * tileW,
                footprintH: Double(max(1, placement.height)) * tileH,
                underConstruction: placement.underConstruction,
                progress: placement.underConstruction ? (progress ?? 0) : 1,
                seed: buildingSeed(placement.id))
        }
    }

    /// Calm rings around the heart, for a colony with no layout of its own yet.
    /// Civic buildings hold the centre; housing drifts to the outer rings.
    /// Pure and deterministic — the same settlement always lays out the same.
    private static func ringLayout(
        settlement: Settlement, registry: GameDataRegistry
    ) -> [NormalizedBuilding] {
        var expanded: [(id: String, name: String, glyph: BuildingGlyph)] = []
        for instance in settlement.buildings {
            let def = registry.building(instance.definitionID)
            let g = def.map(glyph(for:)) ?? .house
            for _ in 0..<instance.count where expanded.count < maxVisibleBuildings {
                expanded.append((instance.definitionID,
                                 def?.name.resolve(AppStrings.language) ?? instance.definitionID, g))
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
                    seed: buildingSeed(expanded[drawn].id, drawn)))
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
        case .granary: return 1
        case .workshop: return 2
        case .mill: return 3
        case .generator: return 4
        case .mine: return 5
        case .tower: return 6
        case .house: return 7
        }
    }

    private static func buildings(
        _ context: inout GraphicsContext, placed: [PlacedBuilding],
        time: Double, night: Double = 0, showLabels: Bool = false,
        selectedBuildingID: Int?
    ) {
        // Foundations first — every building's plot, drawn before any structure,
        // so a later lot never paints over an earlier roof and adjacent lots
        // knit into one cleared, built-up ground the town sits on.
        for building in placed {
            floorPlot(&context, at: building.center, footprint: building.footprint,
                      underConstruction: building.underConstruction)
        }
        for building in placed {
            if building.underConstruction {
                SettlementStructures.site(at: building.center, s: building.size,
                                          progress: building.progress, time: time, context: &context)
            } else {
                SettlementStructures.building(building.glyph, at: building.center,
                                              s: building.size, time: time, night: night,
                                              seed: building.seed, context: &context)
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
            // Packed, cleared earth — warmer and darker than the wild grass, so
            // the built ground reads as a place people made.
            context.fill(shape, with: .color(Color(red: 0.20, green: 0.18, blue: 0.15).opacity(0.6)))
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
        time: Double, zoom: CGFloat, selectedPawnID: UUID?
    ) {
        let scene = AgentMotion.Scene(settlement: settlement, registry: registry,
                                      continuousTick: continuousTick)
        let ticksPerYear = registry.config.ticksPerYear
        for pawn in visibleAgents(settlement) {
            let pose = AgentMotion.pose(for: pawn, map: map, scene: scene,
                                        time: time, ticksPerYear: ticksPerYear)
            guard map.isExplored(pose.position) else { continue }
            SettlementFigures.draw(
                pawn: pawn, pose: pose, at: point(pose.position, in: rect),
                time: time, ticksPerYear: ticksPerYear,
                selected: pawn.id == selectedPawnID, zoom: zoom, context: &context)
        }
    }

    // MARK: - Fog of war

    private static func fog(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap, time: Double
    ) {
        let cols = LocalMap.gridColumns, rows = LocalMap.gridRows
        let cw = rect.width / CGFloat(cols), ch = rect.height / CGFloat(rows)
        var covered = Path()
        for row in 0..<rows {
            for col in 0..<cols where !map.exploredCells.contains(row * cols + col) {
                covered.addRect(CGRect(x: rect.minX + CGFloat(col) * cw,
                                       y: rect.minY + CGFloat(row) * ch,
                                       width: cw + 0.5, height: ch + 0.5))
            }
        }
        context.fill(covered, with: .color(Theme.ink.opacity(0.86)))
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
