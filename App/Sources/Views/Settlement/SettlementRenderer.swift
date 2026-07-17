import SwiftUI
import EndlessFrontierCore

/// Draws a settlement's living world as monochrome line-art into a `Canvas`
/// `GraphicsContext`. Pure and layered — each concern is its own function, so
/// new scenery or building types slot in without disturbing the rest.
///
/// Coordinates arrive normalised (0…1) from the model and are mapped to pixels
/// here, so the same scene renders crisp at any size.
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
        ground(&context, rect: rect, map: map)
        heartGlow(&context, rect: rect)
        river(&context, rect: rect, river: map.river)
        scenery(&context, rect: rect, map: map)
        deposits(&context, rect: rect, map: map)
        buildings(&context, rect: rect, settlement: settlement, registry: registry,
                  selectedBuildingID: selectedBuildingID)
        agents(&context, rect: rect, settlement: settlement, map: map,
               time: time, selectedPawnID: selectedPawnID)
        fog(&context, rect: rect, map: map)
        // The seasonal wash is atmosphere over the lens, not part of the world,
        // so it stays in view space and doesn't slide when you pan.
        seasonWash(&context, rect: viewRect, size: size, season: season, time: time)
    }

    /// Maps a normalised model point to a pixel point in `rect`.
    static func point(_ p: LocalPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
    }

    // MARK: - Ground tiles

    /// The tiled earth: every revealed cell painted with its seeded ground
    /// cover. Batched into one path per cover so a full map is a handful of
    /// fills, not a thousand.
    private static func ground(_ context: inout GraphicsContext, rect: CGRect, map: LocalMap) {
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
            context.fill(path, with: .color(coverColor(cover)))
        }
    }

    /// Muted earth tones — dark enough that line-art still reads on top.
    static func coverColor(_ cover: GroundCover) -> Color {
        switch cover {
        case .grass:  return Color(red: 0.11, green: 0.15, blue: 0.12)
        case .meadow: return Color(red: 0.14, green: 0.18, blue: 0.13)
        case .dirt:   return Color(red: 0.16, green: 0.14, blue: 0.11)
        case .sand:   return Color(red: 0.20, green: 0.18, blue: 0.13)
        case .rock:   return Color(red: 0.13, green: 0.14, blue: 0.16)
        case .snow:   return Color(red: 0.19, green: 0.21, blue: 0.25)
        case .marsh:  return Color(red: 0.11, green: 0.16, blue: 0.15)
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

    private static func river(_ context: inout GraphicsContext, rect: CGRect, river: RiverShape) {
        var path = Path()
        let steps = 48
        for i in 0...steps {
            let nx = Double(i) / Double(steps)
            let p = point(LocalPoint(x: nx, y: river.y(atX: nx)), in: rect)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        context.stroke(path, with: .color(Color(red: 0.13, green: 0.17, blue: 0.22)),
                       style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(Color(red: 0.34, green: 0.44, blue: 0.54).opacity(0.7)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    // MARK: - Scenery

    private static func scenery(_ context: inout GraphicsContext, rect: CGRect, map: LocalMap) {
        for prop in map.scenery where map.isExplored(prop.position) {
            let c = point(prop.position, in: rect)
            let s = CGFloat(prop.scale) * min(rect.width, rect.height) * 0.012
            drawProp(prop.kind, at: c, s: s, context: &context)
        }
    }

    private static func drawProp(
        _ kind: SceneryKind, at c: CGPoint, s: CGFloat, context: inout GraphicsContext
    ) {
        switch kind {
        case .tree:
            let canopy = Color(red: 0.40, green: 0.52, blue: 0.42)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x, y: c.y + s * 0.9))
                p.addLine(to: CGPoint(x: c.x, y: c.y))
            }, with: .color(Color(red: 0.36, green: 0.30, blue: 0.24)), lineWidth: 1)
            context.stroke(Path(ellipseIn: CGRect(x: c.x - s * 0.8, y: c.y - s * 1.5,
                                                  width: s * 1.6, height: s * 1.5)),
                           with: .color(canopy), lineWidth: 1)
        case .pine:
            let pine = Color(red: 0.34, green: 0.48, blue: 0.38)
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
                           with: .color(Color(red: 0.42, green: 0.52, blue: 0.42)), lineWidth: 1)
        case .rock:
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.5, y: c.y + s * 0.4))
                p.addLine(to: CGPoint(x: c.x - s * 0.2, y: c.y - s * 0.4))
                p.addLine(to: CGPoint(x: c.x + s * 0.4, y: c.y - s * 0.25))
                p.addLine(to: CGPoint(x: c.x + s * 0.55, y: c.y + s * 0.4))
                p.closeSubpath()
            }, with: .color(Color(red: 0.52, green: 0.54, blue: 0.58)), lineWidth: 1)
        case .boulder:
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.9, y: c.y + s * 0.7))
                p.addLine(to: CGPoint(x: c.x - s * 0.5, y: c.y - s * 0.6))
                p.addLine(to: CGPoint(x: c.x + s * 0.3, y: c.y - s * 0.85))
                p.addLine(to: CGPoint(x: c.x + s * 0.95, y: c.y + s * 0.2))
                p.addLine(to: CGPoint(x: c.x + s * 0.6, y: c.y + s * 0.7))
                p.closeSubpath()
            }, with: .color(Color(red: 0.46, green: 0.48, blue: 0.53)), lineWidth: 1.2)
        case .flowers:
            let bloom = Color(red: 0.80, green: 0.72, blue: 0.52)
            for i in 0..<4 {
                let a = Double(i) * 1.9
                let px = c.x + CGFloat(cos(a)) * s * 0.6
                let py = c.y + CGFloat(sin(a)) * s * 0.4
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: px, y: py + s * 0.4))
                    p.addLine(to: CGPoint(x: px, y: py))
                }, with: .color(Color(red: 0.40, green: 0.50, blue: 0.40)), lineWidth: 0.8)
                context.fill(Path(ellipseIn: CGRect(x: px - 1, y: py - 1.6, width: 2, height: 2)),
                             with: .color(bloom))
            }
        case .reeds:
            let reed = Color(red: 0.52, green: 0.60, blue: 0.48)
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
                           with: .color(Color(red: 0.40, green: 0.33, blue: 0.26)), lineWidth: 1)
        case .pond:
            let water = Color(red: 0.30, green: 0.42, blue: 0.52)
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 1.3, y: c.y - s * 0.7,
                                                width: s * 2.6, height: s * 1.4)),
                         with: .color(water.opacity(0.35)))
            context.stroke(Path(ellipseIn: CGRect(x: c.x - s * 1.3, y: c.y - s * 0.7,
                                                  width: s * 2.6, height: s * 1.4)),
                           with: .color(water), lineWidth: 1)
        case .cactus:
            let green = Color(red: 0.44, green: 0.58, blue: 0.44)
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
            }, with: .color(Color(red: 0.72, green: 0.78, blue: 0.86).opacity(0.30)))
        case .ruinPillar:
            context.stroke(Path(CGRect(x: c.x - s * 0.25, y: c.y - s * 1.1,
                                       width: s * 0.5, height: s * 1.5)),
                           with: .color(Theme.boneDim), lineWidth: 1)
        }
    }

    // MARK: - Resource deposits

    private static func deposits(_ context: inout GraphicsContext, rect: CGRect, map: LocalMap) {
        for node in map.nodes where map.isExplored(node.position) {
            let center = point(node.position, in: rect)
            let fraction = node.capacity > 0 ? node.amount / node.capacity : 1
            drawDeposit(node.kind, at: center, fraction: fraction,
                        shade: Theme.depositShade(node.kind), context: &context)
        }
    }

    private static func drawDeposit(
        _ kind: LocalResourceKind, at c: CGPoint, fraction: Double,
        shade: Color, context: inout GraphicsContext
    ) {
        let count = max(2, Int(3 + fraction * 5))
        switch kind {
        case .field:
            // A tilled plot with rows of grain — reads as worked land.
            let plot = CGRect(x: c.x - 12, y: c.y - 8, width: 24, height: 16)
            context.stroke(Path(plot), with: .color(shade.opacity(0.45)), lineWidth: 1)
            for i in 0..<4 {
                let y = plot.minY + CGFloat(i) * 4 + 2
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: plot.minX + 2, y: y))
                    p.addLine(to: CGPoint(x: plot.maxX - 2, y: y))
                }, with: .color(shade.opacity(0.35 + fraction * 0.5)), lineWidth: 1)
            }
        case .forest:
            for i in 0..<count {
                let a = Double(i) * 2.399
                let d = Double(i % 3) * 5
                let p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
                context.stroke(Path { path in
                    path.move(to: CGPoint(x: p.x, y: p.y - 6))
                    path.addLine(to: CGPoint(x: p.x - 3.4, y: p.y + 2))
                    path.addLine(to: CGPoint(x: p.x + 3.4, y: p.y + 2))
                    path.closeSubpath()
                }, with: .color(shade.opacity(0.85)), lineWidth: 1)
            }
        case .stone:
            // A quarry face with cut blocks.
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
            for i in 0..<count {
                let ox = c.x + CGFloat((i * 11) % 19) - 9
                let oy = c.y + CGFloat((i * 5) % 13) - 6
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: ox, y: oy + 2.5))
                    p.addLine(to: CGPoint(x: ox, y: oy - 2))
                    p.move(to: CGPoint(x: ox - 1.6, y: oy))
                    p.addLine(to: CGPoint(x: ox, y: oy - 1.4))
                    p.addLine(to: CGPoint(x: ox + 1.6, y: oy))
                }, with: .color(shade.opacity(0.85)), lineWidth: 1)
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

    /// One structure standing in the settlement, at the spot it is drawn.
    ///
    /// The ring layout used to live inside the draw call, which meant a
    /// building on screen had no identity — there was nothing for a tap to
    /// land on. Layout is now computed once, here, and both the renderer and
    /// the canvas's hit-testing read from it, so what you tap is exactly what
    /// you see.
    struct PlacedBuilding: Identifiable {
        let id: Int              // stable within a layout pass
        let definitionID: String
        let glyph: BuildingGlyph
        let center: CGPoint
        let size: CGFloat
    }

    /// Where the settlement's structures stand.
    ///
    /// The colony had two truths: the build grid the player lays out on
    /// `ColonyMapScreen`, and a decorative ring of glyphs here — two unrelated
    /// pictures of the same town. Now the grid is the truth wherever one
    /// exists, so a building you place is the building you see, and the rings
    /// are only the fallback for a colony that hasn't been laid out yet.
    static func layout(
        settlement: Settlement, registry: GameDataRegistry, rect: CGRect
    ) -> [PlacedBuilding] {
        if let colony = settlement.colony, !colony.placements.isEmpty {
            return gridLayout(colony: colony, registry: registry, rect: rect)
        }
        return ringLayout(settlement: settlement, registry: registry, rect: rect)
    }

    /// Where the settlement's heart sits on the canvas — the fog is cleared
    /// around here, so this is the only part of the world anyone has actually
    /// seen.
    static let colonyHeart = LocalPoint(x: 0.5, y: 0.52)
    /// How wide a slice of the canvas the whole build grid covers.
    ///
    /// The grid used to be stretched across most of the canvas, which put a
    /// building on tile (0,0) up in the unexplored dark, nowhere near the
    /// settlement it belongs to — structures standing out in the fog. The grid
    /// is a compact cluster *at the heart*, not a sprawl over the whole map.
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

    /// The structures as actually placed on the build grid.
    private static func gridLayout(
        colony: ColonyMap, registry: GameDataRegistry, rect: CGRect
    ) -> [PlacedBuilding] {
        let unit = min(rect.width, rect.height)
        return colony.placements.prefix(maxVisibleBuildings).enumerated().map { index, placement in
            // `coord` is the footprint's top-left origin, so a multi-tile
            // building is nudged to the middle of what it covers — and drawn
            // larger for covering it.
            let origin = canvasPoint(for: placement.coord, in: colony)
            let p = LocalPoint(
                x: origin.x + Double(placement.width - 1) * 0.5 / Double(max(1, colony.width)) * colonySpan,
                y: origin.y + Double(placement.height - 1) * 0.5 / Double(max(1, colony.height)) * colonySpan)
            let glyph = registry.building(placement.definitionID).map(glyph(for:)) ?? .house
            return PlacedBuilding(
                id: index,
                definitionID: placement.definitionID,
                glyph: glyph,
                center: point(p, in: rect),
                size: unit * 0.021 * Double(max(placement.width, placement.height)))
        }
    }

    /// Calm rings around the heart, for a colony with no layout of its own yet.
    /// Civic buildings hold the centre; housing drifts to the outer rings.
    /// Pure and deterministic — the same settlement always lays out the same.
    private static func ringLayout(
        settlement: Settlement, registry: GameDataRegistry, rect: CGRect
    ) -> [PlacedBuilding] {
        var expanded: [(id: String, glyph: BuildingGlyph)] = []
        for instance in settlement.buildings {
            let g = registry.building(instance.definitionID).map(glyph(for:)) ?? .house
            for _ in 0..<instance.count where expanded.count < maxVisibleBuildings {
                expanded.append((instance.definitionID, g))
            }
        }
        guard !expanded.isEmpty else { return [] }
        expanded.sort { rank($0.glyph) < rank($1.glyph) }

        let heart = point(LocalPoint(x: 0.5, y: 0.52), in: rect)
        let unit = min(rect.width, rect.height)
        var placed: [PlacedBuilding] = []
        var drawn = 0, ringIndex = 0
        while drawn < expanded.count {
            let perRing = ringIndex == 0 ? 1 : ringIndex * 6
            let radius = Double(ringIndex) * unit * 0.058
            for slot in 0..<perRing where drawn < expanded.count {
                let angle = Double(slot) / Double(perRing) * 2 * .pi + Double(ringIndex) * 0.6
                let c = CGPoint(x: heart.x + cos(angle) * radius, y: heart.y + sin(angle) * radius)
                placed.append(PlacedBuilding(id: drawn, definitionID: expanded[drawn].id,
                                             glyph: expanded[drawn].glyph, center: c,
                                             size: unit * 0.021))
                drawn += 1
            }
            ringIndex += 1
        }
        return placed
    }

    private static func buildings(
        _ context: inout GraphicsContext, rect: CGRect,
        settlement: Settlement, registry: GameDataRegistry,
        selectedBuildingID: Int?
    ) {
        for building in layout(settlement: settlement, registry: registry, rect: rect) {
            drawBuilding(building.glyph, at: building.center, s: building.size, context: &context)
            if building.id == selectedBuildingID {
                let r = building.size * 2.6
                context.stroke(
                    Path(ellipseIn: CGRect(x: building.center.x - r, y: building.center.y - r,
                                           width: r * 2, height: r * 2)),
                    with: .color(Theme.accent), lineWidth: 1.5)
            }
        }
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

    private static func drawBuilding(
        _ glyph: BuildingGlyph, at c: CGPoint, s: CGFloat, context: inout GraphicsContext
    ) {
        let ink = Theme.bone.opacity(0.62)
        let bright = Theme.bone.opacity(0.8)
        switch glyph {
        case .house:
            let w = s * 1.6, h = s * 1.1
            let body = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
            context.stroke(Path(body), with: .color(ink), lineWidth: 1)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: body.minX, y: body.minY))
                p.addLine(to: CGPoint(x: c.x, y: body.minY - h * 0.7))
                p.addLine(to: CGPoint(x: body.maxX, y: body.minY))
            }, with: .color(bright), lineWidth: 1)
        case .granary:
            // Round silo with a conical cap.
            context.stroke(Path(ellipseIn: CGRect(x: c.x - s * 0.7, y: c.y - s * 0.5,
                                                  width: s * 1.4, height: s * 1.4)),
                           with: .color(ink), lineWidth: 1)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.8, y: c.y - s * 0.4))
                p.addLine(to: CGPoint(x: c.x, y: c.y - s * 1.3))
                p.addLine(to: CGPoint(x: c.x + s * 0.8, y: c.y - s * 0.4))
            }, with: .color(bright), lineWidth: 1)
        case .workshop:
            let body = CGRect(x: c.x - s * 0.9, y: c.y - s * 0.5, width: s * 1.8, height: s)
            context.stroke(Path(body), with: .color(ink), lineWidth: 1)
            // Saw-tooth roof.
            context.stroke(Path { p in
                p.move(to: CGPoint(x: body.minX, y: body.minY))
                p.addLine(to: CGPoint(x: body.minX + s * 0.45, y: body.minY - s * 0.5))
                p.addLine(to: CGPoint(x: body.minX + s * 0.9, y: body.minY))
                p.addLine(to: CGPoint(x: body.minX + s * 1.35, y: body.minY - s * 0.5))
                p.addLine(to: CGPoint(x: body.maxX, y: body.minY))
            }, with: .color(bright), lineWidth: 1)
        case .tower:
            context.stroke(Path(CGRect(x: c.x - s * 0.45, y: c.y - s * 1.2,
                                       width: s * 0.9, height: s * 1.9)),
                           with: .color(ink), lineWidth: 1)
            // Crenellations.
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.6, y: c.y - s * 1.2))
                p.addLine(to: CGPoint(x: c.x + s * 0.6, y: c.y - s * 1.2))
            }, with: .color(bright), lineWidth: 1.4)
        case .temple:
            // Columned front with a pediment.
            let base = CGRect(x: c.x - s * 0.95, y: c.y - s * 0.35, width: s * 1.9, height: s * 0.9)
            context.stroke(Path(base), with: .color(ink), lineWidth: 1)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 1.05, y: c.y - s * 0.35))
                p.addLine(to: CGPoint(x: c.x, y: c.y - s * 1.15))
                p.addLine(to: CGPoint(x: c.x + s * 1.05, y: c.y - s * 0.35))
            }, with: .color(bright), lineWidth: 1)
            for i in 0..<3 {
                let x = c.x - s * 0.55 + CGFloat(i) * s * 0.55
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: c.y - s * 0.25))
                    p.addLine(to: CGPoint(x: x, y: c.y + s * 0.5))
                }, with: .color(ink), lineWidth: 0.9)
            }
        case .mine:
            // A pit-head: an A-frame over a dark mouth.
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.5, y: c.y + s * 0.1,
                                                width: s, height: s * 0.5)),
                         with: .color(Theme.ink))
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.8, y: c.y + s * 0.6))
                p.addLine(to: CGPoint(x: c.x, y: c.y - s * 1.0))
                p.addLine(to: CGPoint(x: c.x + s * 0.8, y: c.y + s * 0.6))
                p.move(to: CGPoint(x: c.x - s * 0.45, y: c.y - s * 0.1))
                p.addLine(to: CGPoint(x: c.x + s * 0.45, y: c.y - s * 0.1))
            }, with: .color(bright), lineWidth: 1)
        case .mill:
            // A lumber mill: shed plus a blade wheel.
            context.stroke(Path(CGRect(x: c.x - s * 0.9, y: c.y - s * 0.4,
                                       width: s * 1.5, height: s * 0.9)),
                           with: .color(ink), lineWidth: 1)
            let wheel = CGRect(x: c.x + s * 0.35, y: c.y - s * 0.75, width: s * 0.9, height: s * 0.9)
            context.stroke(Path(ellipseIn: wheel), with: .color(bright), lineWidth: 1)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: wheel.minX, y: wheel.midY))
                p.addLine(to: CGPoint(x: wheel.maxX, y: wheel.midY))
                p.move(to: CGPoint(x: wheel.midX, y: wheel.minY))
                p.addLine(to: CGPoint(x: wheel.midX, y: wheel.maxY))
            }, with: .color(bright), lineWidth: 0.8)
        case .generator:
            context.stroke(Path(CGRect(x: c.x - s * 0.75, y: c.y - s * 0.4,
                                       width: s * 1.5, height: s * 1.0)),
                           with: .color(ink), lineWidth: 1)
            // A bolt on the face.
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x + s * 0.15, y: c.y - s * 0.3))
                p.addLine(to: CGPoint(x: c.x - s * 0.2, y: c.y + s * 0.1))
                p.addLine(to: CGPoint(x: c.x + s * 0.1, y: c.y + s * 0.1))
                p.addLine(to: CGPoint(x: c.x - s * 0.15, y: c.y + s * 0.5))
            }, with: .color(Theme.accent.opacity(0.9)), lineWidth: 1)
        }
    }

    // MARK: - Colonists

    private static func agents(
        _ context: inout GraphicsContext, rect: CGRect, settlement: Settlement,
        map: LocalMap, time: Double, selectedPawnID: UUID?
    ) {
        for pawn in settlement.pawns.prefix(maxVisibleAgents) {
            let pos = AgentMotion.position(for: pawn, map: map, time: time)
            guard map.isExplored(pos) else { continue }
            figure(pawn, at: point(pos, in: rect), time: time,
                   selected: pawn.id == selectedPawnID, context: &context)
        }
    }

    private static func figure(
        _ pawn: Pawn, at p: CGPoint, time: Double, selected: Bool, context: inout GraphicsContext
    ) {
        let child = pawn.age < 14 * 60
        let scale: CGFloat = child ? 0.72 : 1.0
        let shade = Theme.roleShade(pawn.assignedWork)
        let alpha = max(0.4, pawn.health / 100)

        let gait = AgentMotion.gaitPhase(for: pawn, time: time)
        let swing = CGFloat(sin(gait)) * 1.4 * scale
        let headY = p.y - 4 * scale

        context.fill(
            Path(ellipseIn: CGRect(x: p.x - 1.7 * scale, y: headY - 1.7 * scale,
                                   width: 3.4 * scale, height: 3.4 * scale)),
            with: .color(shade.opacity(alpha)))

        var body = Path()
        body.move(to: CGPoint(x: p.x, y: headY + 1.7 * scale))
        body.addLine(to: CGPoint(x: p.x, y: p.y + 2.6 * scale))
        body.move(to: CGPoint(x: p.x - 2 * scale + swing, y: p.y + 6 * scale))
        body.addLine(to: CGPoint(x: p.x, y: p.y + 2.6 * scale))
        body.addLine(to: CGPoint(x: p.x + 2 * scale - swing, y: p.y + 6 * scale))
        context.stroke(body, with: .color(shade.opacity(alpha)),
                       style: StrokeStyle(lineWidth: 1.2 * scale, lineCap: .round, lineJoin: .round))

        if selected {
            context.stroke(
                Path(ellipseIn: CGRect(x: p.x - 8, y: p.y - 9, width: 16, height: 16)),
                with: .color(Theme.bone), lineWidth: 1.2)
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
