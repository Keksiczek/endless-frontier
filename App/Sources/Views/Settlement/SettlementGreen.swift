import SwiftUI
import EndlessFrontierCore

/// **The green — the one piece of a colony that is a place rather than a
/// building.**
///
/// `SettlementGeometry.greenTiles` has kept the middle four tiles of the build
/// grid clear since districts went in, and `ColonyBuilder.fits` refuses to
/// build on them, so the ground has always been reserved. Nothing ever drew it.
/// Keks: *"udělej prosím rovnou náves nějak rozlišitelnou, třeba aspoň prázdné
/// místo, pak můžou mít náměstí; teď je to vždy uprostřed namačkáno mezi
/// domy."* Reserved and undrawn is exactly "crammed between the houses": the
/// gap was there and read as a gap.
///
/// Drawn as ground the town has worn: beaten earth, tracks coming in from the
/// four ways, and one thing standing in the middle that says which century the
/// colony is living in — a moot fire, then a well, then a market cross on
/// flagstones. Strictly presentational (rule 5): the square is derived from the
/// grid, and nothing here writes anything.
enum SettlementGreen {

    /// What stands in the middle of it, by the age the town is in.
    ///
    /// Not a separate list of eras to keep in step with `Era` — the three
    /// stages are the three things a square has ever been, and the ladder is
    /// read off the era's own order.
    enum Centrepiece {
        /// A ring of stones and a fire: where a village that has no hall meets.
        case mootFire
        /// A well, and the town's day arranged round it.
        case well
        /// Flagstones and a market cross: a square rather than a green.
        case cross

        static func of(_ era: Era) -> Centrepiece {
            switch era {
            case .earlySettlement: return .mootFire
            case .ancient, .medieval: return .well
            case .earlyIndustrial, .modern, .nearFuture: return .cross
            }
        }
    }

    /// Draws the square, under everything the colony has built on the ground
    /// around it.
    static func draw(
        _ context: inout GraphicsContext, rect: CGRect, settlement: Settlement,
        season: Season, era: Era, time: Double, zoom: CGFloat
    ) {
        guard let colony = settlement.colony else { return }
        let tiles = SettlementGeometry.greenTiles
        let x0 = SettlementGeometry.greenOrigin(colony.width)
        let y0 = SettlementGeometry.greenOrigin(colony.height)
        // The square's own corners, in map units, from the grid it is cut out
        // of — so widening the green is one constant in the Core and never a
        // number copied into the drawing (rule 8).
        let topLeft = SettlementGeometry.canvasPoint(tileX: Double(x0), tileY: Double(y0),
                                                     in: colony)
        let bottomRight = SettlementGeometry.canvasPoint(
            tileX: Double(x0 + tiles), tileY: Double(y0 + tiles), in: colony)
        let a = SettlementRenderer.point(topLeft, in: rect)
        let b = SettlementRenderer.point(bottomRight, in: rect)
        let square = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                            width: abs(b.x - a.x), height: abs(b.y - a.y))
        guard square.width > 6, square.height > 6 else { return }
        let centre = CGPoint(x: square.midX, y: square.midY)
        let unit = min(square.width, square.height)

        ground(&context, square: square, season: season)
        tracks(&context, square: square, centre: centre)
        switch Centrepiece.of(era) {
        case .mootFire: mootFire(&context, at: centre, unit: unit, time: time)
        case .well:     well(&context, at: centre, unit: unit)
        case .cross:    cross(&context, at: centre, unit: unit, square: square)
        }
        edging(&context, square: square, unit: unit, season: season)
    }

    // MARK: - The ground

    /// Beaten earth with a ragged edge. Opaque: a translucent patch laid over
    /// the ground tiles blends their overlap twice and rules a grid across the
    /// middle of the town (rule 9).
    private static func ground(
        _ context: inout GraphicsContext, square: CGRect, season: Season
    ) {
        var path = Path()
        let steps = 16
        for i in 0..<steps {
            let angle = Double(i) / Double(steps) * 2 * .pi
            // A worn hollow rather than a drawn rectangle: the corners of a
            // square nobody walks into stay green.
            let wobble = 0.92 + 0.16 * abs(sin(angle * 2.5))
            let p = CGPoint(x: square.midX + CGFloat(cos(angle) * wobble) * square.width / 2,
                            y: square.midY + CGFloat(sin(angle) * wobble) * square.height / 2)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        context.fill(path, with: .color(earth(season)))
        context.stroke(path, with: .color(Theme.boneFaint.opacity(0.30)), lineWidth: 0.8)
    }

    /// Winter freezes the mud; summer bakes it pale.
    private static func earth(_ season: Season) -> Color {
        switch season {
        case .winter: return Color(red: 0.40, green: 0.40, blue: 0.40)
        case .spring: return Color(red: 0.36, green: 0.31, blue: 0.22)
        case .summer: return Color(red: 0.44, green: 0.39, blue: 0.27)
        case .autumn: return Color(red: 0.38, green: 0.33, blue: 0.23)
        }
    }

    /// The four ways in, worn darker than the rest.
    private static func tracks(
        _ context: inout GraphicsContext, square: CGRect, centre: CGPoint
    ) {
        let ends = [CGPoint(x: square.midX, y: square.minY),
                    CGPoint(x: square.midX, y: square.maxY),
                    CGPoint(x: square.minX, y: square.midY),
                    CGPoint(x: square.maxX, y: square.midY)]
        for end in ends {
            var way = Path()
            way.move(to: centre)
            way.addLine(to: end)
            context.stroke(way, with: .color(Color(red: 0.27, green: 0.23, blue: 0.17)),
                           style: StrokeStyle(lineWidth: max(1.5, square.width * 0.055),
                                              lineCap: .round))
        }
    }

    // MARK: - What stands in the middle

    private static func mootFire(
        _ context: inout GraphicsContext, at c: CGPoint, unit: CGFloat, time: Double
    ) {
        let r = unit * 0.10
        context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.7,
                                            width: r * 2, height: r * 1.4)),
                     with: .color(Color(red: 0.16, green: 0.13, blue: 0.10)))
        // The ring of stones.
        for i in 0..<8 {
            let angle = Double(i) / 8 * 2 * .pi
            let p = CGPoint(x: c.x + CGFloat(cos(angle)) * r,
                            y: c.y + CGFloat(sin(angle)) * r * 0.7)
            context.fill(Path(ellipseIn: CGRect(x: p.x - 1.2, y: p.y - 1, width: 2.4, height: 2)),
                         with: .color(Theme.boneDim.opacity(0.8)))
        }
        // …and the fire in it, breathing.
        let flare = 0.7 + 0.3 * sin(time * 1.7)
        context.fill(
            Path(ellipseIn: CGRect(x: c.x - r * 0.4, y: c.y - r * 0.55,
                                   width: r * 0.8, height: r * 0.9)),
            with: .color(Theme.accent.opacity(0.55 * flare)))
    }

    private static func well(
        _ context: inout GraphicsContext, at c: CGPoint, unit: CGFloat
    ) {
        let r = unit * 0.085
        let mouth = CGRect(x: c.x - r, y: c.y - r * 0.72, width: r * 2, height: r * 1.44)
        context.fill(Path(ellipseIn: mouth), with: .color(Theme.boneDim.opacity(0.85)))
        context.fill(Path(ellipseIn: mouth.insetBy(dx: r * 0.34, dy: r * 0.24)),
                     with: .color(Theme.ink.opacity(0.9)))
        // Two posts and a beam over it — the shape that says "well" at any size.
        let top = c.y - r * 1.9
        for side in [-1.0, 1.0] {
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x + CGFloat(side) * r * 0.9, y: c.y))
                p.addLine(to: CGPoint(x: c.x + CGFloat(side) * r * 0.9, y: top))
            }, with: .color(Theme.bone.opacity(0.75)), lineWidth: 1)
        }
        context.stroke(Path { p in
            p.move(to: CGPoint(x: c.x - r * 1.1, y: top))
            p.addLine(to: CGPoint(x: c.x + r * 1.1, y: top))
        }, with: .color(Theme.bone.opacity(0.75)), lineWidth: 1)
    }

    private static func cross(
        _ context: inout GraphicsContext, at c: CGPoint, unit: CGFloat, square: CGRect
    ) {
        // Flagstones: the square is paved by now, so the ground under it reads
        // as laid rather than worn.
        let step = max(3.0, square.width / 7)
        var stones = Path()
        var y = square.minY + step * 0.5
        while y < square.maxY - step * 0.4 {
            var x = square.minX + step * 0.5
            while x < square.maxX - step * 0.4 {
                stones.addRect(CGRect(x: x, y: y, width: step * 0.82, height: step * 0.62))
                x += step
            }
            y += step * 0.8
        }
        context.fill(stones, with: .color(Color(red: 0.34, green: 0.34, blue: 0.35)))
        context.stroke(stones, with: .color(Theme.ink.opacity(0.35)), lineWidth: 0.4)
        // The cross itself, on three steps.
        let base = unit * 0.16
        for i in 0..<3 {
            let w = base * (1 - CGFloat(i) * 0.22)
            context.fill(Path(CGRect(x: c.x - w / 2, y: c.y + base * 0.36 - CGFloat(i) * 2.2,
                                     width: w, height: 2.2)),
                         with: .color(Theme.boneDim.opacity(0.85)))
        }
        context.stroke(Path { p in
            p.move(to: CGPoint(x: c.x, y: c.y + base * 0.3))
            p.addLine(to: CGPoint(x: c.x, y: c.y - base * 0.9))
            p.move(to: CGPoint(x: c.x - base * 0.28, y: c.y - base * 0.62))
            p.addLine(to: CGPoint(x: c.x + base * 0.28, y: c.y - base * 0.62))
        }, with: .color(Theme.bone.opacity(0.85)), lineWidth: 1.2)
    }

    // MARK: - The edge of it

    /// A tree at one corner and a bench at another: the difference between an
    /// empty patch and somewhere people sit.
    private static func edging(
        _ context: inout GraphicsContext, square: CGRect, unit: CGFloat, season: Season
    ) {
        let trunk = CGPoint(x: square.minX + square.width * 0.16,
                            y: square.minY + square.height * 0.18)
        context.stroke(Path { p in
            p.move(to: CGPoint(x: trunk.x, y: trunk.y + unit * 0.10))
            p.addLine(to: CGPoint(x: trunk.x, y: trunk.y - unit * 0.04))
        }, with: .color(Color(red: 0.32, green: 0.25, blue: 0.18)), lineWidth: 1.4)
        let crown = CGRect(x: trunk.x - unit * 0.09, y: trunk.y - unit * 0.16,
                           width: unit * 0.18, height: unit * 0.16)
        context.fill(Path(ellipseIn: crown), with: .color(canopy(season)))

        let bench = CGRect(x: square.maxX - square.width * 0.32,
                           y: square.maxY - square.height * 0.22,
                           width: max(4, square.width * 0.18), height: max(1.4, unit * 0.022))
        context.fill(Path(bench), with: .color(Color(red: 0.38, green: 0.30, blue: 0.21)))
    }

    private static func canopy(_ season: Season) -> Color {
        switch season {
        case .spring: return Color(red: 0.42, green: 0.60, blue: 0.34)
        case .summer: return Color(red: 0.30, green: 0.50, blue: 0.28)
        case .autumn: return Color(red: 0.62, green: 0.45, blue: 0.22)
        case .winter: return Color(red: 0.44, green: 0.44, blue: 0.44)
        }
    }
}
