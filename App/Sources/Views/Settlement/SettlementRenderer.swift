import SwiftUI
import EndlessFrontierCore

/// Draws a settlement's living world as monochrome line-art into a `Canvas`
/// `GraphicsContext`. Pure and layered — each concern is its own function, so
/// new scenery (walls, temples, banners…) slots in without disturbing the rest.
///
/// Coordinates arrive normalised (0…1) from the model and are mapped to pixels
/// here, so the same scene renders crisp at any size.
enum SettlementRenderer {
    /// Cap on drawn colonists — keeps a boom-town calm and the frame cheap.
    /// Everyone still exists in the sim; this only thins the *visible* crowd.
    static let maxVisibleAgents = 90

    static func draw(
        _ context: inout GraphicsContext,
        size: CGSize,
        settlement: Settlement,
        map: LocalMap,
        time: Double,
        season: Season,
        selectedPawnID: UUID?
    ) {
        let rect = CGRect(origin: .zero, size: size)
        ground(&context, rect: rect)
        river(&context, rect: rect, river: map.river)
        deposits(&context, rect: rect, map: map)
        buildings(&context, rect: rect, settlement: settlement)
        agents(&context, rect: rect, settlement: settlement, map: map,
               time: time, selectedPawnID: selectedPawnID)
        fog(&context, rect: rect, map: map)
        seasonWash(&context, rect: rect, size: size, season: season, time: time)
    }

    /// Maps a normalised model point to a pixel point in `rect`.
    static func point(_ p: LocalPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
    }

    // MARK: - Ground

    private static func ground(_ context: inout GraphicsContext, rect: CGRect) {
        // A faint radial glow at the settlement heart lifts it off the ink.
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
        // Broad soft water, then a bright thread for the current.
        context.stroke(path, with: .color(Color(red: 0.13, green: 0.17, blue: 0.22)),
                       style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(Color(red: 0.34, green: 0.44, blue: 0.54).opacity(0.7)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    // MARK: - Resource deposits

    private static func deposits(_ context: inout GraphicsContext, rect: CGRect, map: LocalMap) {
        for node in map.nodes where map.isExplored(node.position) {
            let center = point(node.position, in: rect)
            let fraction = node.capacity > 0 ? node.amount / node.capacity : 1
            let shade = Theme.depositShade(node.kind)
            drawDeposit(node.kind, at: center, fraction: fraction, shade: shade, context: &context)
        }
    }

    private static func drawDeposit(
        _ kind: LocalResourceKind, at c: CGPoint, fraction: Double,
        shade: Color, context: inout GraphicsContext
    ) {
        let count = max(2, Int(3 + fraction * 5))
        switch kind {
        case .field:
            // A tidy huddle of grain dots.
            for i in 0..<count {
                let a = Double(i) * 2.399
                let d = Double(i % 4) * 3 + 2
                let p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2)),
                             with: .color(shade.opacity(0.9)))
            }
        case .forest:
            for i in 0..<count {
                let a = Double(i) * 2.399
                let d = Double(i % 3) * 5
                let p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
                var tri = Path()
                tri.move(to: CGPoint(x: p.x, y: p.y - 6))
                tri.addLine(to: CGPoint(x: p.x - 3.4, y: p.y + 2))
                tri.addLine(to: CGPoint(x: p.x + 3.4, y: p.y + 2))
                tri.closeSubpath()
                context.stroke(tri, with: .color(shade.opacity(0.85)), lineWidth: 1)
            }
        case .stone:
            for i in 0..<max(1, count / 2) {
                let ox = c.x + Double((i * 13) % 17) - 8
                let oy = c.y + Double((i * 7) % 11) - 5
                var rock = Path()
                rock.move(to: CGPoint(x: ox - 4, y: oy + 3))
                rock.addLine(to: CGPoint(x: ox - 2, y: oy - 3))
                rock.addLine(to: CGPoint(x: ox + 3, y: oy - 2))
                rock.addLine(to: CGPoint(x: ox + 4, y: oy + 3))
                rock.closeSubpath()
                context.stroke(rock, with: .color(shade.opacity(0.85)), lineWidth: 1)
            }
        case .herbs:
            for i in 0..<count {
                let ox = c.x + Double((i * 11) % 19) - 9
                let oy = c.y + Double((i * 5) % 13) - 6
                var sprig = Path()
                sprig.move(to: CGPoint(x: ox, y: oy + 2.5))
                sprig.addLine(to: CGPoint(x: ox, y: oy - 2))
                sprig.move(to: CGPoint(x: ox - 1.6, y: oy))
                sprig.addLine(to: CGPoint(x: ox, y: oy - 1.4))
                sprig.addLine(to: CGPoint(x: ox + 1.6, y: oy))
                context.stroke(sprig, with: .color(shade.opacity(0.85)), lineWidth: 1)
            }
        }
    }

    // MARK: - Buildings

    private static func buildings(_ context: inout GraphicsContext, rect: CGRect, settlement: Settlement) {
        // Lay structures in a calm cluster of rings around the heart. We cap the
        // drawn count so a large town stays legible.
        let total = min(28, settlement.buildings.reduce(0) { $0 + $1.count })
        guard total > 0 else { return }
        let heart = point(LocalPoint(x: 0.5, y: 0.52), in: rect)
        let unit = min(rect.width, rect.height)

        var drawn = 0
        var ringIndex = 0
        while drawn < total {
            let perRing = ringIndex == 0 ? 1 : ringIndex * 6
            let radius = Double(ringIndex) * unit * 0.055
            for slot in 0..<perRing where drawn < total {
                let angle = Double(slot) / Double(perRing) * 2 * .pi + Double(ringIndex) * 0.6
                let cx = heart.x + cos(angle) * radius
                let cy = heart.y + sin(angle) * radius
                house(at: CGPoint(x: cx, y: cy), scale: unit * 0.02, context: &context)
                drawn += 1
            }
            ringIndex += 1
        }
    }

    private static func house(at c: CGPoint, scale: CGFloat, context: inout GraphicsContext) {
        let w = scale * 1.6, h = scale * 1.1
        let body = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
        context.stroke(Path(body), with: .color(Theme.bone.opacity(0.55)), lineWidth: 1)
        var roof = Path()
        roof.move(to: CGPoint(x: body.minX, y: body.minY))
        roof.addLine(to: CGPoint(x: c.x, y: body.minY - h * 0.7))
        roof.addLine(to: CGPoint(x: body.maxX, y: body.minY))
        context.stroke(roof, with: .color(Theme.bone.opacity(0.7)), lineWidth: 1)
    }

    // MARK: - Colonists

    private static func agents(
        _ context: inout GraphicsContext, rect: CGRect, settlement: Settlement,
        map: LocalMap, time: Double, selectedPawnID: UUID?
    ) {
        let pawns = settlement.pawns.prefix(maxVisibleAgents)
        for pawn in pawns {
            let pos = AgentMotion.position(for: pawn, map: map, time: time)
            // Hidden by fog unless it's near the revealed heart.
            guard map.isExplored(pos) else { continue }
            let p = point(pos, in: rect)
            let selected = pawn.id == selectedPawnID
            figure(pawn, at: p, time: time, selected: selected, context: &context)
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

        var body = Path()
        let headY = p.y - 4 * scale
        // Head
        context.fill(
            Path(ellipseIn: CGRect(x: p.x - 1.7 * scale, y: headY - 1.7 * scale,
                                   width: 3.4 * scale, height: 3.4 * scale)),
            with: .color(shade.opacity(alpha)))
        // Torso
        body.move(to: CGPoint(x: p.x, y: headY + 1.7 * scale))
        body.addLine(to: CGPoint(x: p.x, y: p.y + 2.6 * scale))
        // Legs (walking)
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
        context.fill(covered, with: .color(Theme.ink.opacity(0.82)))
    }

    // MARK: - Season

    private static func seasonWash(
        _ context: inout GraphicsContext, rect: CGRect, size: CGSize,
        season: Season, time: Double
    ) {
        context.fill(Path(rect), with: .color(Theme.seasonTint(season)))
        guard season == .winter else { return }
        // Drifting snow — sparse, so it reads as atmosphere, not noise.
        for i in 0..<40 {
            let sx = (Double(i) * 173 + time * (12 + Double(i % 3) * 6)).truncatingRemainder(dividingBy: size.width)
            let sy = (Double(i) * 97 + time * (18 + Double(i % 4) * 5)).truncatingRemainder(dividingBy: size.height)
            context.fill(Path(ellipseIn: CGRect(x: sx, y: sy, width: 1.6, height: 1.6)),
                         with: .color(Color.white.opacity(0.5)))
        }
    }
}
