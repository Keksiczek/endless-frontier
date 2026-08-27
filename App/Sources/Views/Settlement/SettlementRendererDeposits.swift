import SwiftUI
import EndlessFrontierCore

/// **What the ground has in it** — the ore, clay, salt and stone a colonist
/// can be sent to dig, drawn as the seams they are rather than as a marker.
extension SettlementRenderer {
    static func deposits(
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

    static func drawDeposit(
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
        case .coal:
            // A seam, not a pit: a band of black lying *through* the rock, so
            // it reads as something followed rather than something dug out.
            let face = CGRect(x: c.x - 9 * z, y: c.y - 5 * z, width: 18 * z, height: 10 * z)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: face.minX, y: face.maxY))
                p.addLine(to: CGPoint(x: face.minX + 2 * z, y: face.minY))
                p.addLine(to: CGPoint(x: face.maxX - 2 * z, y: face.minY))
                p.addLine(to: CGPoint(x: face.maxX, y: face.maxY))
                p.closeSubpath()
            }, with: .color(shade.opacity(0.5)), lineWidth: 1)
            // The band itself, thick and unbroken — the one solid mark on a
            // canvas made of hairlines, because coal is the darkest thing here.
            let band = CGRect(x: face.minX + 2 * z, y: c.y - 1.4 * z,
                              width: face.width - 4 * z, height: 2.8 * z)
            context.fill(Path(band), with: .color(Theme.ink.opacity(0.55 + fraction * 0.35)))
            for i in 0..<max(2, count / 3) {
                let ox = face.minX + CGFloat((i * 7) % 14 + 2) * z
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: ox, y: band.minY - 1.5 * z))
                    p.addLine(to: CGPoint(x: ox + 1.2 * z, y: band.maxY + 1.5 * z))
                }, with: .color(shade.opacity(0.35)), lineWidth: 0.8)
            }
        case .oilSeep:
            // Nothing is broken open here — it comes up on its own. A dark pool
            // with rings going out from it, and the ground stained around it.
            for i in 0..<max(2, count / 2) {
                let r = CGFloat(3 + i * 3) * z
                context.stroke(
                    Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.55,
                                           width: r * 2, height: r * 1.1)),
                    with: .color(shade.opacity(0.45 - Double(i) * 0.08)), lineWidth: 1)
            }
            let pool = CGRect(x: c.x - 4.5 * z, y: c.y - 2.4 * z,
                              width: 9 * z, height: 4.8 * z)
            context.fill(Path(ellipseIn: pool),
                         with: .color(Theme.ink.opacity(0.5 + fraction * 0.35)))
            // A sheen on it, so it reads as wet rather than as a hole.
            context.stroke(Path(ellipseIn: pool.insetBy(dx: 2 * z, dy: 1 * z)),
                           with: .color(shade.opacity(0.5)), lineWidth: 0.8)
        }
    }

    // MARK: - Buildings

}
