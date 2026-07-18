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
        selectedPawnID: UUID?,
        selectedBuildingID: Int?
    ) {
        let viewRect = CGRect(origin: .zero, size: size)
        let rect = worldRect(viewRect: viewRect, camera: camera)
        ground(&context, rect: rect, map: map, season: season)
        zones(&context, rect: rect, settlement: settlement, season: season)
        heartGlow(&context, rect: rect)
        river(&context, rect: rect, river: map.river, season: season)
        scenery(&context, rect: rect, map: map, season: season)
        deposits(&context, rect: rect, map: map, season: season)
        pois(&context, rect: rect, map: map, time: time)
        SettlementWildlife.draw(&context, rect: rect, map: map, time: time)

        let placed = layout(settlement: settlement, registry: registry, rect: rect)
        buildings(&context, placed: placed, time: time, selectedBuildingID: selectedBuildingID)
        SettlementFigures.smoke(
            &context,
            houses: placed.filter { $0.glyph == .house && !$0.underConstruction },
            time: time)

        agents(&context, rect: rect, settlement: settlement, map: map,
               registry: registry, time: time, selectedPawnID: selectedPawnID)
        SettlementFigures.birds(&context, rect: rect, season: season, time: time)
        fog(&context, rect: rect, map: map)
        // The seasonal wash is atmosphere over the lens, not part of the world,
        // so it stays in view space and doesn't slide when you pan.
        seasonWash(&context, rect: viewRect, size: size, season: season, time: time)
    }

    /// Maps a normalised model point to a pixel point in `rect`.
    static func point(_ p: LocalPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
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
        ground(&context, rect: rect, map: map, season: season)
        river(&context, rect: rect, river: map.river, season: season)
        scenery(&context, rect: rect, map: map, season: season)
        deposits(&context, rect: rect, map: map, season: season)
        pois(&context, rect: rect, map: map, time: time)
        SettlementWildlife.draw(&context, rect: rect, map: map, time: time)
        if regionKind == .anomaly {
            anomalyGlow(&context, rect: rect, time: time)
        }
        if let tribe {
            SettlementStructures.camp(
                &context, rect: rect, population: tribe.population,
                tint: campTint(tribe.status), time: time,
                seed: map.terrainSeed)
        }
        seasonWash(&context, rect: viewRect, size: size, season: season, time: time)
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
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap, time: Double
    ) {
        let unit = min(rect.width, rect.height)
        for poi in map.pois where poi.discovered && map.isExplored(poi.position) {
            SettlementStructures.poi(poi.kind, at: point(poi.position, in: rect),
                                     s: unit * 0.014, time: time, context: &context)
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
        _ context: inout GraphicsContext, rect: CGRect, river: RiverShape, season: Season
    ) {
        var path = Path()
        let steps = 48
        for i in 0...steps {
            let nx = Double(i) / Double(steps)
            let p = point(LocalPoint(x: nx, y: river.y(atX: nx)), in: rect)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        if season == .winter {
            // Frozen over: a pale band with a hairline of open water.
            context.stroke(path, with: .color(Color(red: 0.42, green: 0.50, blue: 0.60)),
                           style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(Color(red: 0.72, green: 0.80, blue: 0.90).opacity(0.8)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5]))
        } else {
            context.stroke(path, with: .color(Color(red: 0.15, green: 0.22, blue: 0.30)),
                           style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(Color(red: 0.38, green: 0.52, blue: 0.64).opacity(0.75)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    // MARK: - Scenery

    private static func scenery(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap, season: Season
    ) {
        for prop in map.scenery where map.isExplored(prop.position) {
            let c = point(prop.position, in: rect)
            let s = CGFloat(prop.scale) * min(rect.width, rect.height) * 0.012
            drawProp(prop.kind, at: c, s: s, season: season, context: &context)
        }
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
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x, y: c.y + s * 0.9))
                p.addLine(to: CGPoint(x: c.x, y: c.y))
            }, with: .color(Color(red: 0.40, green: 0.33, blue: 0.26)), lineWidth: 1)
            if season == .winter {
                // Bare branches instead of a canopy.
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: c.x, y: c.y))
                    p.addLine(to: CGPoint(x: c.x - s * 0.7, y: c.y - s * 1.0))
                    p.move(to: CGPoint(x: c.x, y: c.y - s * 0.3))
                    p.addLine(to: CGPoint(x: c.x + s * 0.65, y: c.y - s * 1.15))
                    p.move(to: CGPoint(x: c.x, y: c.y - s * 0.6))
                    p.addLine(to: CGPoint(x: c.x - s * 0.3, y: c.y - s * 1.4))
                }, with: .color(canopyColor(season)), lineWidth: 0.9)
            } else {
                context.stroke(Path(ellipseIn: CGRect(x: c.x - s * 0.8, y: c.y - s * 1.5,
                                                      width: s * 1.6, height: s * 1.5)),
                               with: .color(canopyColor(season)), lineWidth: 1)
                if season == .autumn {
                    // A few fallen leaves at the foot.
                    for i in 0..<3 {
                        let lx = c.x + CGFloat(i - 1) * s * 0.5
                        context.fill(Path(ellipseIn: CGRect(x: lx, y: c.y + s * 0.85,
                                                            width: 1.4, height: 1.0)),
                                     with: .color(canopyColor(season).opacity(0.7)))
                    }
                }
            }
        case .pine:
            let pine = season == .winter
                ? Color(red: 0.42, green: 0.52, blue: 0.50)
                : Color(red: 0.32, green: 0.50, blue: 0.38)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x, y: c.y + s))
                p.addLine(to: CGPoint(x: c.x, y: c.y + s * 0.5))
            }, with: .color(Color(red: 0.34, green: 0.28, blue: 0.22)), lineWidth: 1)
            for tier in 0..<3 {
                let t = CGFloat(tier)
                context.stroke(Path { p in
                    let top = c.y - s * 1.4 + t * s * 0.55
                    let w = s * (0.4 + t * 0.28)
                    p.move(to: CGPoint(x: c.x - w, y: top + s * 0.5))
                    p.addLine(to: CGPoint(x: c.x, y: top))
                    p.addLine(to: CGPoint(x: c.x + w, y: top + s * 0.5))
                }, with: .color(pine), lineWidth: 1)
            }
        case .bush:
            context.stroke(Path(ellipseIn: CGRect(x: c.x - s * 0.6, y: c.y - s * 0.45,
                                                  width: s * 1.2, height: s * 0.9)),
                           with: .color(canopyColor(season).opacity(0.9)), lineWidth: 1)
        case .rock:
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.5, y: c.y + s * 0.4))
                p.addLine(to: CGPoint(x: c.x - s * 0.2, y: c.y - s * 0.4))
                p.addLine(to: CGPoint(x: c.x + s * 0.4, y: c.y - s * 0.25))
                p.addLine(to: CGPoint(x: c.x + s * 0.55, y: c.y + s * 0.4))
                p.closeSubpath()
            }, with: .color(Color(red: 0.55, green: 0.57, blue: 0.61)), lineWidth: 1)
        case .boulder:
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.9, y: c.y + s * 0.7))
                p.addLine(to: CGPoint(x: c.x - s * 0.5, y: c.y - s * 0.6))
                p.addLine(to: CGPoint(x: c.x + s * 0.3, y: c.y - s * 0.85))
                p.addLine(to: CGPoint(x: c.x + s * 0.95, y: c.y + s * 0.2))
                p.addLine(to: CGPoint(x: c.x + s * 0.6, y: c.y + s * 0.7))
                p.closeSubpath()
            }, with: .color(Color(red: 0.50, green: 0.52, blue: 0.57)), lineWidth: 1.2)
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
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap, season: Season
    ) {
        for node in map.nodes where map.isExplored(node.position) {
            let center = point(node.position, in: rect)
            let fraction = node.capacity > 0 ? node.amount / node.capacity : 1
            drawDeposit(node.kind, at: center, fraction: fraction,
                        shade: Theme.depositShade(node.kind), season: season, context: &context)
        }
    }

    private static func drawDeposit(
        _ kind: LocalResourceKind, at c: CGPoint, fraction: Double,
        shade: Color, season: Season, context: inout GraphicsContext
    ) {
        let count = max(2, Int(3 + fraction * 5))
        switch kind {
        case .field:
            // A tilled plot. The rows follow the calendar: green shoots in
            // spring, gold in summer, stubble in autumn, snow-dusted in winter.
            let plot = CGRect(x: c.x - 12, y: c.y - 8, width: 24, height: 16)
            context.stroke(Path(plot), with: .color(shade.opacity(0.5)), lineWidth: 1)
            let rowColor: Color
            switch season {
            case .spring: rowColor = Color(red: 0.55, green: 0.68, blue: 0.42)
            case .summer: rowColor = Color(red: 0.80, green: 0.72, blue: 0.40)
            case .autumn: rowColor = Color(red: 0.72, green: 0.58, blue: 0.34)
            case .winter: rowColor = Color(red: 0.62, green: 0.66, blue: 0.74)
            }
            for i in 0..<4 {
                let y = plot.minY + CGFloat(i) * 4 + 2
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: plot.minX + 2, y: y))
                    p.addLine(to: CGPoint(x: plot.maxX - 2, y: y))
                }, with: .color(rowColor.opacity(season == .winter ? 0.35 : 0.35 + fraction * 0.5)),
                style: StrokeStyle(lineWidth: 1, dash: season == .winter ? [2, 3] : []))
            }
        case .forest:
            let leaf = season == .autumn
                ? Color(red: 0.70, green: 0.50, blue: 0.30)
                : (season == .winter ? Color(red: 0.48, green: 0.54, blue: 0.54) : shade)
            for i in 0..<count {
                let a = Double(i) * 2.399
                let d = Double(i % 3) * 5
                let p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
                context.stroke(Path { path in
                    path.move(to: CGPoint(x: p.x, y: p.y - 6))
                    path.addLine(to: CGPoint(x: p.x - 3.4, y: p.y + 2))
                    path.addLine(to: CGPoint(x: p.x + 3.4, y: p.y + 2))
                    path.closeSubpath()
                }, with: .color(leaf.opacity(0.85)), lineWidth: 1)
            }
        case .stone:
            for i in 0..<max(2, count / 2) {
                let ox = c.x + CGFloat((i * 13) % 17) - 8
                let oy = c.y + CGFloat((i * 7) % 11) - 5
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: ox - 4, y: oy + 3))
                    p.addLine(to: CGPoint(x: ox - 2, y: oy - 3))
                    p.addLine(to: CGPoint(x: ox + 3, y: oy - 2))
                    p.addLine(to: CGPoint(x: ox + 4, y: oy + 3))
                    p.closeSubpath()
                }, with: .color(shade.opacity(0.85)), lineWidth: 1)
            }
        case .herbs:
            let herb = season == .winter ? shade.opacity(0.4) : shade.opacity(0.85)
            for i in 0..<count {
                let ox = c.x + CGFloat((i * 11) % 19) - 9
                let oy = c.y + CGFloat((i * 5) % 13) - 6
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: ox, y: oy + 2.5))
                    p.addLine(to: CGPoint(x: ox, y: oy - 2))
                    p.move(to: CGPoint(x: ox - 1.6, y: oy))
                    p.addLine(to: CGPoint(x: ox, y: oy - 1.4))
                    p.addLine(to: CGPoint(x: ox + 1.6, y: oy))
                }, with: .color(herb), lineWidth: 1)
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
        let glyph: BuildingGlyph
        let center: LocalPoint
        /// Footprint size as a fraction of the canvas's short side.
        let size: Double
        let underConstruction: Bool
        /// Construction completion 0…1 (1 when built).
        let progress: Double
    }

    /// The same structure mapped to pixels for one frame.
    struct PlacedBuilding: Identifiable {
        let id: Int
        let definitionID: String
        let glyph: BuildingGlyph
        let center: CGPoint
        let size: CGFloat
        let underConstruction: Bool
        let progress: Double
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
            PlacedBuilding(id: b.id, definitionID: b.definitionID, glyph: b.glyph,
                           center: point(b.center, in: rect), size: unit * b.size,
                           underConstruction: b.underConstruction, progress: b.progress)
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
            let glyph = registry.building(placement.definitionID).map(glyph(for:)) ?? .house
            let progress = settlement.constructions
                .first { $0.placementID == placement.id }?.fraction
            return NormalizedBuilding(
                id: index,
                definitionID: placement.definitionID,
                glyph: glyph,
                center: p,
                size: 0.021 * Double(max(placement.width, placement.height)),
                underConstruction: placement.underConstruction,
                progress: placement.underConstruction ? (progress ?? 0) : 1)
        }
    }

    /// Calm rings around the heart, for a colony with no layout of its own yet.
    /// Civic buildings hold the centre; housing drifts to the outer rings.
    /// Pure and deterministic — the same settlement always lays out the same.
    private static func ringLayout(
        settlement: Settlement, registry: GameDataRegistry
    ) -> [NormalizedBuilding] {
        var expanded: [(id: String, glyph: BuildingGlyph)] = []
        for instance in settlement.buildings {
            let g = registry.building(instance.definitionID).map(glyph(for:)) ?? .house
            for _ in 0..<instance.count where expanded.count < maxVisibleBuildings {
                expanded.append((instance.definitionID, g))
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
                    id: drawn, definitionID: expanded[drawn].id, glyph: expanded[drawn].glyph,
                    center: c, size: 0.021, underConstruction: false, progress: 1))
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
        time: Double, selectedBuildingID: Int?
    ) {
        for building in placed {
            if building.underConstruction {
                SettlementStructures.site(at: building.center, s: building.size,
                                          progress: building.progress, time: time, context: &context)
            } else {
                SettlementStructures.building(building.glyph, at: building.center,
                                              s: building.size, time: time, context: &context)
            }
            if building.id == selectedBuildingID {
                let r = building.size * 2.6
                context.stroke(
                    Path(ellipseIn: CGRect(x: building.center.x - r, y: building.center.y - r,
                                           width: r * 2, height: r * 2)),
                    with: .color(Theme.accent), lineWidth: 1.5)
            }
        }
    }

    // MARK: - Colonists

    private static func agents(
        _ context: inout GraphicsContext, rect: CGRect, settlement: Settlement,
        map: LocalMap, registry: GameDataRegistry, time: Double, selectedPawnID: UUID?
    ) {
        let scene = AgentMotion.Scene(settlement: settlement, registry: registry)
        let ticksPerYear = registry.config.ticksPerYear
        for pawn in settlement.pawns.prefix(maxVisibleAgents) {
            let pose = AgentMotion.pose(for: pawn, map: map, scene: scene,
                                        time: time, ticksPerYear: ticksPerYear)
            guard map.isExplored(pose.position) else { continue }
            SettlementFigures.draw(
                pawn: pawn, pose: pose, at: point(pose.position, in: rect),
                time: time, ticksPerYear: ticksPerYear,
                selected: pawn.id == selectedPawnID, context: &context)
        }
    }

    // MARK: - Fog of war

    private static func fog(_ context: inout GraphicsContext, rect: CGRect, map: LocalMap) {
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
