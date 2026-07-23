import SwiftUI
import EndlessFrontierCore

/// The wild, drawn: the deer herd the hunters live off grazes its way around
/// the valley, and when predator pressure climbs, something grey prowls the
/// tree line. Purely presentational — herd size and pressure are read from
/// `WildlifeState`; where the animals *stand* is a deterministic function of
/// the map seed and the frame clock, so the sim stays untouched.
enum SettlementWildlife {
    /// Predator pressure above which a prowler appears at the fringe…
    static let prowlerPressure: Double = 15
    /// …and above which a second joins it.
    static let packPressure: Double = 30
    /// The most deer ever drawn — a full herd, thinned as hunters cull it.
    static let maxVisibleDeer = 5

    /// Where the herd is grazing right now: a slow figure-eight around the
    /// valley's middle distance, well clear of the built heart. Hunters anchor
    /// to this too, so the figures chase the same deer you see.
    static func herdCenter(map: LocalMap, time: Double) -> LocalPoint {
        let seed = Double(map.terrainSeed % 977) / 977 * 2 * .pi
        let t = time / 90 + seed          // one slow lap ≈ a minute and a half
        return LocalPoint(
            x: 0.5 + cos(t) * 0.30,
            y: 0.52 + sin(t * 2) * 0.20)  // lissajous keeps it off the houses
    }

    /// Draws the herd and any prowler. Everything is skipped under fog.
    static func draw(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap, time: Double
    ) {
        let unit = min(rect.width, rect.height)
        let herd = herdCenter(map: map, time: time)
        let count = min(maxVisibleDeer,
                        Int((map.wildlife.herdFraction * Double(maxVisibleDeer)).rounded(.up)))
        for i in 0..<max(0, count) {
            let phase = Double(i) * 2.1
            let p = LocalPoint(
                x: herd.x + cos(time * 0.18 + phase) * 0.035,
                y: herd.y + sin(time * 0.14 + phase * 1.7) * 0.028)
            guard map.isExplored(p) else { continue }
            deer(&context, at: SettlementRenderer.point(p, in: rect),
                 s: unit * 0.010, time: time, phase: phase)
        }

        let pressure = map.wildlife.predatorPressure
        guard pressure > prowlerPressure else { return }
        let prowlers = pressure > packPressure ? 2 : 1
        for i in 0..<prowlers {
            let angle = time * 0.05 + Double(i) * .pi + Double(map.terrainSeed % 7)
            let p = LocalPoint(x: 0.5 + cos(angle) * 0.42,
                               y: 0.52 + sin(angle) * 0.36)
            guard map.isExplored(p) else { continue }
            prowler(&context, at: SettlementRenderer.point(p, in: rect),
                    s: unit * 0.011, time: time, hungry: pressure > packPressure)
        }
    }

    /// A grazing deer — a stag lifts an antlered head now and then, a doe just
    /// grazes. Filled hide, four legs, a soft shadow, a white scut: an animal,
    /// not a mark on the grass.
    private static func deer(
        _ context: inout GraphicsContext, at p: CGPoint, s: CGFloat,
        time: Double, phase: Double
    ) {
        let hide = Color(red: 0.72, green: 0.62, blue: 0.46)
        let dark = Color(red: 0.53, green: 0.44, blue: 0.32)
        let grazing = sin(time * 0.6 + phase) > 0.3
        let stag = Int(phase.rounded()) % 2 == 0
        let headY = grazing ? p.y + s * 0.55 : p.y - s * 0.95
        let headX = p.x + s * 1.35

        // Shadow.
        context.fill(Path(ellipseIn: CGRect(x: p.x - s * 1.1, y: p.y + s * 1.05,
                                            width: s * 2.4, height: s * 0.5)),
                     with: .color(Theme.ink.opacity(0.18)))
        // Four legs.
        for dx in [-0.65, -0.45, 0.45, 0.65] as [CGFloat] {
            context.fill(Path(CGRect(x: p.x + dx * s - s * 0.09, y: p.y + s * 0.2,
                                     width: s * 0.18, height: s * 1.15)),
                         with: .color(dark))
        }
        // Body.
        context.fill(Path(ellipseIn: CGRect(x: p.x - s, y: p.y - s * 0.55,
                                            width: s * 2, height: s * 1.1)),
                     with: .color(hide))
        // A white scut at the tail.
        context.fill(Path(ellipseIn: CGRect(x: p.x - s * 1.12, y: p.y - s * 0.3,
                                            width: s * 0.4, height: s * 0.4)),
                     with: .color(.white.opacity(0.5)))
        // Neck + head.
        context.fill(Path { n in
            n.move(to: CGPoint(x: p.x + s * 0.55, y: p.y - s * 0.35))
            n.addLine(to: CGPoint(x: p.x + s * 1.0, y: p.y - s * 0.1))
            n.addLine(to: CGPoint(x: headX, y: headY))
            n.addLine(to: CGPoint(x: headX - s * 0.3, y: headY + s * 0.25))
            n.closeSubpath()
        }, with: .color(hide))
        context.fill(Path(ellipseIn: CGRect(x: headX - s * 0.32, y: headY - s * 0.28,
                                            width: s * 0.62, height: s * 0.52)),
                     with: .color(hide))
        if !grazing {
            context.stroke(Path { e in
                e.move(to: CGPoint(x: headX, y: headY - s * 0.2))
                e.addLine(to: CGPoint(x: headX + s * 0.32, y: headY - s * 0.55))
            }, with: .color(dark), lineWidth: 0.7)
            if stag {
                // Branching antlers.
                context.stroke(Path { a in
                    a.move(to: CGPoint(x: headX - s * 0.05, y: headY - s * 0.25))
                    a.addLine(to: CGPoint(x: headX + s * 0.05, y: headY - s * 0.98))
                    a.move(to: CGPoint(x: headX, y: headY - s * 0.6))
                    a.addLine(to: CGPoint(x: headX - s * 0.35, y: headY - s * 0.82))
                    a.move(to: CGPoint(x: headX + s * 0.02, y: headY - s * 0.8))
                    a.addLine(to: CGPoint(x: headX + s * 0.42, y: headY - s * 1.02))
                }, with: .color(dark), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
            }
        }
    }

    /// Something grey at the tree line — a filled wolf, head low, loping. At
    /// pack pressure the eye catches red and the colony should be worried.
    private static func prowler(
        _ context: inout GraphicsContext, at p: CGPoint, s: CGFloat,
        time: Double, hungry: Bool
    ) {
        let coat = Color(red: 0.50, green: 0.51, blue: 0.55)
        let dark = Color(red: 0.36, green: 0.37, blue: 0.41)
        let lope = CGFloat(sin(time * 2.2)) * s * 0.15
        let sw = CGFloat(sin(time * 2.2)) * s * 0.22

        // Shadow.
        context.fill(Path(ellipseIn: CGRect(x: p.x - s * 1.4, y: p.y + s * 0.9,
                                            width: s * 3.1, height: s * 0.5)),
                     with: .color(Theme.ink.opacity(0.16)))
        // Legs — the far pair darker, the near pair in coat.
        context.fill(Path(CGRect(x: p.x - s * 0.85 - sw, y: p.y + s * 0.1, width: s * 0.2, height: s * 0.95)), with: .color(dark))
        context.fill(Path(CGRect(x: p.x + s * 0.55 + sw, y: p.y + s * 0.1, width: s * 0.2, height: s * 0.95)), with: .color(dark))
        context.fill(Path(CGRect(x: p.x - s * 0.55 + sw, y: p.y + s * 0.1, width: s * 0.18, height: s * 0.9)), with: .color(coat))
        context.fill(Path(CGRect(x: p.x + s * 0.85 - sw, y: p.y + s * 0.1, width: s * 0.18, height: s * 0.9)), with: .color(coat))
        // Tail sweeping off the rump.
        context.fill(Path { t in
            t.move(to: CGPoint(x: p.x - s * 1.05, y: p.y - s * 0.05))
            t.addLine(to: CGPoint(x: p.x - s * 1.75, y: p.y - s * 0.5 + lope))
            t.addLine(to: CGPoint(x: p.x - s * 1.5, y: p.y - s * 0.15 + lope))
            t.addLine(to: CGPoint(x: p.x - s * 1.0, y: p.y + s * 0.15))
            t.closeSubpath()
        }, with: .color(coat))
        // Body: rump, spine, low head, snout, jaw, belly.
        context.fill(Path { b in
            b.move(to: CGPoint(x: p.x - s * 1.1, y: p.y - s * 0.1))
            b.addLine(to: CGPoint(x: p.x + s * 0.9, y: p.y - s * 0.28))
            b.addLine(to: CGPoint(x: p.x + s * 1.5, y: p.y + s * 0.15))
            b.addLine(to: CGPoint(x: p.x + s * 1.7, y: p.y + s * 0.35))
            b.addLine(to: CGPoint(x: p.x + s * 1.2, y: p.y + s * 0.5))
            b.addLine(to: CGPoint(x: p.x + s * 0.7, y: p.y + s * 0.42))
            b.addLine(to: CGPoint(x: p.x - s * 1.0, y: p.y + s * 0.45))
            b.closeSubpath()
        }, with: .color(coat))
        // Ear.
        context.fill(Path { e in
            e.move(to: CGPoint(x: p.x + s * 0.98, y: p.y - s * 0.28))
            e.addLine(to: CGPoint(x: p.x + s * 1.1, y: p.y - s * 0.62))
            e.addLine(to: CGPoint(x: p.x + s * 1.24, y: p.y - s * 0.22))
            e.closeSubpath()
        }, with: .color(dark))
        // Eye — red and larger when the pack is hungry.
        context.fill(Path(ellipseIn: CGRect(x: p.x + s * 1.4, y: p.y + s * 0.14,
                                            width: hungry ? 2.0 : 1.4, height: hungry ? 2.0 : 1.4)),
                     with: .color(hungry ? Theme.danger.opacity(0.95) : Theme.ink.opacity(0.85)))
    }
}
