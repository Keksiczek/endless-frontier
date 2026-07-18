import SwiftUI
import EndlessFrontierCore

/// The line-art of the structures themselves — finished silhouettes and the
/// scaffolding of what's still being raised. Split from `SettlementRenderer`
/// so the world stays one readable file and the architecture another.
enum SettlementStructures {
    /// A construction site: staked ground, rising scaffold, a timber pile and
    /// a thin progress mark — the colony visibly *making* something.
    static func site(
        at c: CGPoint, s: CGFloat, progress: Double, time: Double,
        context: inout GraphicsContext
    ) {
        let ink = Theme.bone.opacity(0.55)
        let w = s * 1.8, h = s * 1.3
        let base = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
        // Staked-out ground.
        context.stroke(Path(base), with: .color(ink),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        // The frame rises with progress.
        let rise = CGFloat(0.3 + progress * 0.7)
        context.stroke(Path { p in
            p.move(to: CGPoint(x: base.minX, y: base.minY))
            p.addLine(to: CGPoint(x: base.minX, y: base.minY - h * 0.8 * rise))
            p.move(to: CGPoint(x: base.maxX, y: base.minY))
            p.addLine(to: CGPoint(x: base.maxX, y: base.minY - h * 0.8 * rise))
            if progress > 0.55 {
                p.move(to: CGPoint(x: base.minX, y: base.minY - h * 0.8 * rise))
                p.addLine(to: CGPoint(x: c.x, y: base.minY - h * (0.8 * rise + 0.35)))
                p.addLine(to: CGPoint(x: base.maxX, y: base.minY - h * 0.8 * rise))
            }
        }, with: .color(Theme.bone.opacity(0.75)), lineWidth: 1)
        // Cross-brace.
        context.stroke(Path { p in
            p.move(to: CGPoint(x: base.minX, y: base.minY - h * 0.8 * rise))
            p.addLine(to: CGPoint(x: base.maxX, y: base.minY))
            p.move(to: CGPoint(x: base.maxX, y: base.minY - h * 0.8 * rise))
            p.addLine(to: CGPoint(x: base.minX, y: base.minY))
        }, with: .color(ink.opacity(0.5)), lineWidth: 0.7)
        // Timber pile by the corner.
        for i in 0..<3 {
            let y = base.maxY - CGFloat(i) * 1.6
            context.stroke(Path { p in
                p.move(to: CGPoint(x: base.maxX + 2, y: y))
                p.addLine(to: CGPoint(x: base.maxX + 2 + s * 0.9, y: y))
            }, with: .color(Color(red: 0.52, green: 0.42, blue: 0.30)), lineWidth: 1.2)
        }
        // Progress underline in lantern amber.
        context.stroke(Path { p in
            p.move(to: CGPoint(x: base.minX, y: base.maxY + 3))
            p.addLine(to: CGPoint(x: base.minX + w * CGFloat(progress), y: base.maxY + 3))
        }, with: .color(Theme.accent.opacity(0.9)), lineWidth: 1.6)
    }

    /// A discovered point of interest, drawn as a small landmark. Undiscovered
    /// ones stay invisible — finding them is the scouts' job.
    static func poi(
        _ kind: LocalPOIKind, at c: CGPoint, s: CGFloat, time: Double,
        context: inout GraphicsContext
    ) {
        let stone = Theme.boneDim
        switch kind {
        case .ruins:
            // Two leaning pillars and a fallen lintel.
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.7, y: c.y + s * 0.6))
                p.addLine(to: CGPoint(x: c.x - s * 0.55, y: c.y - s * 0.9))
                p.move(to: CGPoint(x: c.x + s * 0.55, y: c.y + s * 0.6))
                p.addLine(to: CGPoint(x: c.x + s * 0.62, y: c.y - s * 0.5))
                p.move(to: CGPoint(x: c.x - s * 0.9, y: c.y + s * 0.75))
                p.addLine(to: CGPoint(x: c.x + s * 0.4, y: c.y + s * 0.9))
            }, with: .color(stone), lineWidth: 1.1)
        case .cave:
            // A dark mouth in the hillside.
            context.fill(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.8, y: c.y + s * 0.5))
                p.addQuadCurve(to: CGPoint(x: c.x + s * 0.8, y: c.y + s * 0.5),
                               control: CGPoint(x: c.x, y: c.y - s * 1.1))
                p.closeSubpath()
            }, with: .color(Theme.ink))
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.8, y: c.y + s * 0.5))
                p.addQuadCurve(to: CGPoint(x: c.x + s * 0.8, y: c.y + s * 0.5),
                               control: CGPoint(x: c.x, y: c.y - s * 1.1))
            }, with: .color(stone), lineWidth: 1)
        case .spring:
            // A pool with a glint that breathes.
            let water = Color(red: 0.45, green: 0.65, blue: 0.75)
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.8, y: c.y - s * 0.4,
                                                width: s * 1.6, height: s * 0.8)),
                         with: .color(water.opacity(0.4)))
            context.stroke(Path(ellipseIn: CGRect(x: c.x - s * 0.8, y: c.y - s * 0.4,
                                                  width: s * 1.6, height: s * 0.8)),
                           with: .color(water), lineWidth: 1)
            let glint = 0.4 + 0.4 * abs(sin(time * 1.4))
            context.fill(Path(ellipseIn: CGRect(x: c.x - 1, y: c.y - s * 0.9, width: 2, height: 2)),
                         with: .color(Color.white.opacity(glint)))
        case .treasure:
            // An opened chest with a faint glint.
            let wood = Color(red: 0.55, green: 0.42, blue: 0.28)
            context.stroke(Path(CGRect(x: c.x - s * 0.6, y: c.y - s * 0.25,
                                       width: s * 1.2, height: s * 0.7)),
                           with: .color(wood), lineWidth: 1)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.6, y: c.y - s * 0.25))
                p.addLine(to: CGPoint(x: c.x - s * 0.35, y: c.y - s * 0.75))
                p.addLine(to: CGPoint(x: c.x + s * 0.85, y: c.y - s * 0.75))
                p.addLine(to: CGPoint(x: c.x + s * 0.6, y: c.y - s * 0.25))
            }, with: .color(wood), lineWidth: 1)
            context.fill(Path(ellipseIn: CGRect(x: c.x - 1, y: c.y - 1, width: 2, height: 2)),
                         with: .color(Theme.accent.opacity(0.9)))
        case .shrine:
            // Two posts, a roof line, and a small living flame.
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.5, y: c.y + s * 0.6))
                p.addLine(to: CGPoint(x: c.x - s * 0.5, y: c.y - s * 0.5))
                p.move(to: CGPoint(x: c.x + s * 0.5, y: c.y + s * 0.6))
                p.addLine(to: CGPoint(x: c.x + s * 0.5, y: c.y - s * 0.5))
                p.move(to: CGPoint(x: c.x - s * 0.75, y: c.y - s * 0.5))
                p.addLine(to: CGPoint(x: c.x + s * 0.75, y: c.y - s * 0.5))
            }, with: .color(stone), lineWidth: 1.1)
            let flicker = 0.6 + 0.3 * sin(time * 5)
            context.fill(Path(ellipseIn: CGRect(x: c.x - 1.2, y: c.y + s * 0.05,
                                                width: 2.4, height: 2.4)),
                         with: .color(Theme.accent.opacity(flicker)))
        case .wreck:
            // A cart on its last wheel, bed tipped into the grass.
            let wood = Color(red: 0.5, green: 0.4, blue: 0.3)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.9, y: c.y + s * 0.3))
                p.addLine(to: CGPoint(x: c.x + s * 0.7, y: c.y - s * 0.35))
                p.addLine(to: CGPoint(x: c.x + s * 0.9, y: c.y - s * 0.1))
            }, with: .color(wood), lineWidth: 1.1)
            context.stroke(Path(ellipseIn: CGRect(x: c.x - s * 0.55, y: c.y + s * 0.1,
                                                  width: s * 0.75, height: s * 0.75)),
                           with: .color(wood), lineWidth: 1)
            context.stroke(Path { p in
                p.addArc(center: CGPoint(x: c.x + s * 0.75, y: c.y + s * 0.45),
                         radius: s * 0.35, startAngle: .degrees(200),
                         endAngle: .degrees(30), clockwise: false)
            }, with: .color(wood.opacity(0.7)), lineWidth: 0.9)
        }
    }

    static func building(
        _ glyph: SettlementRenderer.BuildingGlyph, at c: CGPoint, s: CGFloat,
        context: inout GraphicsContext
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
            // A warm window — someone lives here.
            context.fill(Path(CGRect(x: c.x - s * 0.18, y: c.y - s * 0.1,
                                     width: s * 0.36, height: s * 0.3)),
                         with: .color(Theme.accent.opacity(0.35)))
        case .granary:
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
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.6, y: c.y - s * 1.2))
                p.addLine(to: CGPoint(x: c.x + s * 0.6, y: c.y - s * 1.2))
            }, with: .color(bright), lineWidth: 1.4)
        case .temple:
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
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x + s * 0.15, y: c.y - s * 0.3))
                p.addLine(to: CGPoint(x: c.x - s * 0.2, y: c.y + s * 0.1))
                p.addLine(to: CGPoint(x: c.x + s * 0.1, y: c.y + s * 0.1))
                p.addLine(to: CGPoint(x: c.x - s * 0.15, y: c.y + s * 0.5))
            }, with: .color(Theme.accent.opacity(0.9)), lineWidth: 1)
        }
    }
}
