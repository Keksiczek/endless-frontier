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

    /// Draws the wild. Where there are real `Animal`s on the map each one is
    /// drawn as itself — its own species, its own wander, and visibly the worse
    /// for a hard winter — and the abstract herd is only the fallback for saves
    /// that predate them. Everything is skipped under fog.
    static func draw(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap, time: Double
    ) {
        guard map.wildlife.animals.isEmpty else {
            entities(&context, rect: rect, map: map, time: time)
            return
        }
        abstractHerd(&context, rect: rect, map: map, time: time)
    }

    /// Every beast the simulation is actually running.
    ///
    /// Position is presentation, exactly as it is for colonists: derived from
    /// `(animal.id, frame clock)` and never stored, so the deterministic Core
    /// stays untouched. Prey graze around the herd's slow lap of the valley;
    /// predators keep to the tree line.
    private static func entities(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap, time: Double
    ) {
        let unit = min(rect.width, rect.height)
        let herd = herdCenter(map: map, time: time)
        for animal in map.wildlife.animals {
            let phase = Double(hash(animal.id) % 6199) / 6199 * 2 * .pi
            // A limping beast covers less ground; a sick one drifts.
            let vigour = animal.canWalk ? 1.0 : 0.35
            let position: LocalPoint
            if animal.species.isPredator {
                let angle = time * 0.05 * vigour + phase
                position = LocalPoint(x: 0.5 + cos(angle) * 0.42,
                                      y: 0.52 + sin(angle) * 0.36)
            } else {
                position = LocalPoint(
                    x: herd.x + cos(time * 0.18 * vigour + phase) * 0.035,
                    y: herd.y + sin(time * 0.14 * vigour + phase * 1.7) * 0.028)
            }
            guard map.isExplored(position) else { continue }
            let at = SettlementRenderer.point(position, in: rect)
            let ailing = !animal.conditions.isEmpty
                || animal.health < animal.species.baseHealth * 0.55

            switch animal.species {
            case .deer:
                deer(&context, at: at, s: unit * 0.010, time: time, phase: phase)
            case .boar:
                boar(&context, at: at, s: unit * 0.009, time: time, phase: phase)
            case .hare:
                hare(&context, at: at, s: unit * 0.006, time: time, phase: phase)
            case .fox:
                prowler(&context, at: at, s: unit * 0.007, time: time, hungry: false)
            case .wolf:
                prowler(&context, at: at, s: unit * 0.011, time: time, hungry: ailing)
            case .bear:
                prowler(&context, at: at, s: unit * 0.015, time: time, hungry: ailing)
            }

            // A beast that is hurt, ill or frozen says so, so a hard winter is
            // something you can see happening rather than read about later.
            if ailing {
                context.fill(
                    Path(ellipseIn: CGRect(x: at.x - unit * 0.0022,
                                           y: at.y - unit * 0.018,
                                           width: unit * 0.0044, height: unit * 0.0044)),
                    with: .color(Theme.danger.opacity(0.75)))
            }
        }
    }

    /// The old behaviour, for maps generated before the wild had bodies.
    private static func abstractHerd(
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

    /// A stable number per beast, so its wander is its own and never jitters.
    private static func hash(_ id: UUID) -> UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        let b = id.uuid
        for byte in [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7] {
            h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3
        }
        return h
    }

    /// A boar: low, heavy, snout down, with a bristled back.
    private static func boar(
        _ context: inout GraphicsContext, at p: CGPoint, s: CGFloat,
        time: Double, phase: Double
    ) {
        let hide = Color(red: 0.33, green: 0.27, blue: 0.23)
        let body = CGRect(x: p.x - s * 1.0, y: p.y - s * 0.5, width: s * 2.0, height: s * 0.95)
        context.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.9, y: p.y + s * 0.4,
                                            width: s * 1.8, height: s * 0.4)),
                     with: .color(.black.opacity(0.2)))
        context.fill(Path(ellipseIn: body), with: .color(hide))
        // A wedge of a head, always rooting at the ground.
        context.fill(Path { q in
            q.move(to: CGPoint(x: body.minX + s * 0.1, y: p.y - s * 0.3))
            q.addLine(to: CGPoint(x: body.minX - s * 0.75, y: p.y + s * 0.42))
            q.addLine(to: CGPoint(x: body.minX + s * 0.2, y: p.y + s * 0.4))
            q.closeSubpath()
        }, with: .color(hide))
        // Bristles.
        for i in 0..<4 {
            let x = body.minX + body.width * (CGFloat(i) + 0.8) / 5
            context.stroke(Path { q in
                q.move(to: CGPoint(x: x, y: body.minY + s * 0.06))
                q.addLine(to: CGPoint(x: x + s * 0.06, y: body.minY - s * 0.24))
            }, with: .color(Theme.bone.opacity(0.4)), lineWidth: 0.6)
        }
        // Four short legs, working.
        let gait = CGFloat(sin(time * 3 + phase)) * s * 0.16
        for i in 0..<4 {
            let x = body.minX + body.width * (CGFloat(i) + 0.5) / 4
            context.stroke(Path { q in
                q.move(to: CGPoint(x: x, y: body.maxY - s * 0.1))
                q.addLine(to: CGPoint(x: x + (i % 2 == 0 ? gait : -gait), y: body.maxY + s * 0.42))
            }, with: .color(hide), lineWidth: max(0.7, s * 0.2))
        }
    }

    /// A hare: small, still, then suddenly not.
    private static func hare(
        _ context: inout GraphicsContext, at p: CGPoint, s: CGFloat,
        time: Double, phase: Double
    ) {
        let fur = Color(red: 0.62, green: 0.55, blue: 0.44)
        // It sits, then bolts a short way and sits again.
        let bolt = max(0, sin(time * 0.9 + phase) - 0.86) * 7
        let hop = CGFloat(abs(sin(time * 9 + phase))) * s * CGFloat(bolt)
        let c = CGPoint(x: p.x + CGFloat(bolt) * s * 0.8, y: p.y - hop)
        context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.8, y: c.y - s * 0.5,
                                            width: s * 1.6, height: s * 1.0)),
                     with: .color(fur))
        // Two long ears, laid back when it runs.
        for side in [-1.0, 1.0] {
            let lean = CGFloat(side) * s * (0.18 + CGFloat(bolt) * 0.5)
            context.stroke(Path { q in
                q.move(to: CGPoint(x: c.x + s * 0.4, y: c.y - s * 0.35))
                q.addLine(to: CGPoint(x: c.x + s * 0.4 + lean, y: c.y - s * 1.15))
            }, with: .color(fur), lineWidth: max(0.6, s * 0.2))
        }
        context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.95, y: c.y - s * 0.3,
                                            width: s * 0.4, height: s * 0.4)),
                     with: .color(Theme.bone.opacity(0.75)))   // the scut
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
