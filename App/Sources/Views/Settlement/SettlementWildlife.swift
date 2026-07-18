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

    /// A grazing deer: body, neck, and now and then the head goes down to the
    /// grass — enough motion to read as an animal, not a rock.
    private static func deer(
        _ context: inout GraphicsContext, at p: CGPoint, s: CGFloat,
        time: Double, phase: Double
    ) {
        let hide = Color(red: 0.72, green: 0.62, blue: 0.46).opacity(0.9)
        let grazing = sin(time * 0.6 + phase) > 0.3
        let headY = grazing ? p.y + s * 0.55 : p.y - s * 0.9
        let headX = p.x + s * 1.35

        // Body and legs.
        context.stroke(Path(ellipseIn: CGRect(x: p.x - s, y: p.y - s * 0.5,
                                              width: s * 2, height: s)),
                       with: .color(hide), lineWidth: 1)
        var legs = Path()
        legs.move(to: CGPoint(x: p.x - s * 0.6, y: p.y + s * 0.4))
        legs.addLine(to: CGPoint(x: p.x - s * 0.6, y: p.y + s * 1.3))
        legs.move(to: CGPoint(x: p.x + s * 0.6, y: p.y + s * 0.4))
        legs.addLine(to: CGPoint(x: p.x + s * 0.6, y: p.y + s * 1.3))
        context.stroke(legs, with: .color(hide), lineWidth: 0.9)
        // Neck and head.
        var head = Path()
        head.move(to: CGPoint(x: p.x + s * 0.9, y: p.y - s * 0.2))
        head.addLine(to: CGPoint(x: headX, y: headY))
        context.stroke(head, with: .color(hide), lineWidth: 0.9)
        context.fill(Path(ellipseIn: CGRect(x: headX - s * 0.25, y: headY - s * 0.25,
                                            width: s * 0.5, height: s * 0.5)),
                     with: .color(hide))
        // Ears when the head is up.
        if !grazing {
            context.stroke(Path { path in
                path.move(to: CGPoint(x: headX, y: headY - s * 0.2))
                path.addLine(to: CGPoint(x: headX + s * 0.3, y: headY - s * 0.6))
            }, with: .color(hide), lineWidth: 0.7)
        }
    }

    /// Something grey at the tree line, head low, moving. At pack pressure the
    /// eye catches red — the colony should be worried.
    private static func prowler(
        _ context: inout GraphicsContext, at p: CGPoint, s: CGFloat,
        time: Double, hungry: Bool
    ) {
        let coat = Color(red: 0.55, green: 0.56, blue: 0.60).opacity(0.85)
        let lope = CGFloat(sin(time * 2.2)) * s * 0.15

        var body = Path()
        body.move(to: CGPoint(x: p.x - s * 1.2, y: p.y + lope * 0.4))         // tail root
        body.addLine(to: CGPoint(x: p.x - s * 1.7, y: p.y - s * 0.4 + lope)) // tail
        body.move(to: CGPoint(x: p.x - s * 1.2, y: p.y))
        body.addLine(to: CGPoint(x: p.x + s * 0.9, y: p.y - s * 0.15))       // spine
        body.addLine(to: CGPoint(x: p.x + s * 1.5, y: p.y + s * 0.25))       // head, low
        body.move(to: CGPoint(x: p.x - s * 0.8, y: p.y))
        body.addLine(to: CGPoint(x: p.x - s * 0.8 - lope, y: p.y + s * 0.9))
        body.move(to: CGPoint(x: p.x + s * 0.5, y: p.y))
        body.addLine(to: CGPoint(x: p.x + s * 0.5 + lope, y: p.y + s * 0.9))
        context.stroke(body, with: .color(coat),
                       style: StrokeStyle(lineWidth: 1, lineCap: .round))
        if hungry {
            context.fill(Path(ellipseIn: CGRect(x: p.x + s * 1.3, y: p.y + s * 0.05,
                                                width: 1.6, height: 1.6)),
                         with: .color(Theme.danger.opacity(0.9)))
        }
    }
}
