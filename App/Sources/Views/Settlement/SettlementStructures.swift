import SwiftUI
import EndlessFrontierCore

/// The line-art of the structures themselves — finished silhouettes and the
/// scaffolding of what's still being raised. Split from `SettlementRenderer`
/// so the world stays one readable file and the architecture another.
enum SettlementStructures {
    /// What time and trouble have done to a building.
    ///
    /// Buildings used to be immortal, so nothing in the art ever had to say
    /// otherwise. Now a raid, a storm or a hard winter leaves a mark, and the
    /// mark has to be legible from across the valley or the whole layer is a
    /// number in an inspector: first cracks, then a hole in the roof and a
    /// prop holding what is left, then a ruin with the walls down.
    static func wear(
        _ context: inout GraphicsContext, at c: CGPoint, footprint: CGSize,
        condition: Double, seed: UInt64
    ) {
        guard condition < 0.92 else { return }
        let w = max(6, footprint.width), h = max(6, footprint.height)
        let ruin = condition < 0.25
        var roll = seed | 1
        func next() -> CGFloat {
            roll ^= roll >> 33; roll = roll &* 0xFF51_AFD7_ED55_8CCD; roll ^= roll >> 29
            return CGFloat(Double((roll >> 40) & 0xFFFF) / 65535)
        }

        // Cracks: more of them, and longer, the worse it is.
        let cracks = ruin ? 5 : Int((1 - condition) * 6)
        var lines = Path()
        for _ in 0..<max(1, cracks) {
            let x = c.x - w / 2 + next() * w
            let y = c.y - h / 2 + next() * h
            let run = (0.18 + next() * 0.3) * min(w, h)
            lines.move(to: CGPoint(x: x, y: y))
            lines.addLine(to: CGPoint(x: x + (next() - 0.5) * run, y: y + run * 0.6))
        }
        context.stroke(lines, with: .color(Theme.ink.opacity(ruin ? 0.75 : 0.45)),
                       lineWidth: ruin ? 1.1 : 0.7)

        guard condition < 0.6 else { return }
        // A hole where the roof gave: dark, and it does not move.
        let hole = min(w, h) * CGFloat(0.18 + (0.6 - condition) * 0.5)
        context.fill(Path(ellipseIn: CGRect(x: c.x - hole / 2 + (next() - 0.5) * w * 0.3,
                                            y: c.y - hole / 2 - h * 0.1,
                                            width: hole, height: hole * 0.7)),
                     with: .color(Theme.ink.opacity(0.7)))

        guard ruin else {
            // Not a ruin yet: a prop under the sagging side.
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x + w * 0.34, y: c.y + h * 0.42))
                p.addLine(to: CGPoint(x: c.x + w * 0.22, y: c.y - h * 0.18))
            }, with: .color(Color(red: 0.52, green: 0.42, blue: 0.30)), lineWidth: 1.2)
            return
        }
        // A ruin: the wall line broken, and rubble at its foot.
        for i in 0..<4 {
            let r = min(w, h) * (0.10 + next() * 0.08)
            let p = CGPoint(x: c.x - w * 0.4 + CGFloat(i) * w * 0.27 + (next() - 0.5) * w * 0.1,
                            y: c.y + h * (0.30 + next() * 0.2))
            context.fill(Path(roundedRect: CGRect(x: p.x - r / 2, y: p.y - r / 2,
                                                  width: r, height: r * 0.8),
                              cornerRadius: r * 0.2),
                         with: .color(Color(red: 0.36, green: 0.34, blue: 0.32)))
        }
    }

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

    /// A native people's camp: a loose ring of tents around a fire, and their
    /// folk moving between them. Drawn on a surveyed region's chunk — the
    /// world's other peoples visibly *live* somewhere, RimWorld-style, not
    /// just on a diplomacy panel. Purely presentational; positions come from
    /// the terrain seed and the frame clock.
    static func camp(
        _ context: inout GraphicsContext, rect: CGRect,
        population: Double, tint: Color, time: Double, seed: UInt64,
        night: Double = 0, zoom: CGFloat = 1
    ) {
        let unit = min(rect.width, rect.height)
        let heart = CGPoint(x: rect.midX, y: rect.midY)
        let phase = Double(seed % 613) / 613 * 2 * .pi

        // The fire, breathing — and at night, owning the dark.
        let flicker = 0.55 + 0.3 * sin(time * 6 + phase)
        if night > 0.05 {
            let glow = unit * 0.05 * (0.8 + 0.2 * sin(time * 4 + phase))
            context.fill(
                Path(ellipseIn: CGRect(x: heart.x - glow, y: heart.y - glow,
                                       width: glow * 2, height: glow * 2)),
                with: .radialGradient(
                    Gradient(colors: [Theme.accent.opacity(0.22 * night), .clear]),
                    center: heart, startRadius: 0, endRadius: glow))
        }
        context.fill(Path(ellipseIn: CGRect(x: heart.x - 2.2 * zoom, y: heart.y - 2.2 * zoom,
                                            width: 4.4 * zoom, height: 4.4 * zoom)),
                     with: .color(Theme.accent.opacity(flicker)))
        // Its smoke.
        for k in 0..<3 {
            let t = (time * 0.25 + Double(k) * 0.33 + phase).truncatingRemainder(dividingBy: 1)
            let y = heart.y - (4 + CGFloat(t) * 16) * zoom
            let x = heart.x + CGFloat(sin(t * 5 + Double(k))) * 3 * zoom
            let r = (1 + CGFloat(t) * 2.6) * zoom
            context.fill(Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)),
                         with: .color(Theme.boneDim.opacity((1 - t) * 0.3)))
        }

        // Tents, sized to the people: 3 for a band, up to 7 for a strong tribe.
        let tents = min(7, max(3, Int(population / 18) + 3))
        let s = unit * 0.020
        for i in 0..<tents {
            let angle = Double(i) / Double(tents) * 2 * .pi + phase
            let c = CGPoint(x: heart.x + cos(angle) * unit * 0.085,
                            y: heart.y + sin(angle) * unit * 0.062)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s, y: c.y + s * 0.7))
                p.addLine(to: CGPoint(x: c.x, y: c.y - s))
                p.addLine(to: CGPoint(x: c.x + s, y: c.y + s * 0.7))
                p.closeSubpath()
                // The door slit.
                p.move(to: CGPoint(x: c.x, y: c.y - s * 0.1))
                p.addLine(to: CGPoint(x: c.x, y: c.y + s * 0.7))
            }, with: .color(tint.opacity(0.75)), lineWidth: 1)
        }

        // Their people, about their day.
        let folk = min(10, max(2, Int(population / 8)))
        for i in 0..<folk {
            let fp = Double(i) * 1.7 + phase
            let wander = 0.10 + 0.05 * sin(time * 0.11 + fp * 2)
            let angle = time * (0.05 + Double(i % 3) * 0.02) + fp
            let p = CGPoint(x: heart.x + cos(angle) * unit * wander,
                            y: heart.y + sin(angle * 1.3) * unit * wander * 0.75)
            let gait = CGFloat(sin(time * 5 + fp)) * 1.2 * zoom
            let head = CGPoint(x: p.x, y: p.y - 3.6 * zoom)
            context.fill(Path(ellipseIn: CGRect(x: head.x - 1.3 * zoom, y: head.y - 1.3 * zoom,
                                                width: 2.6 * zoom, height: 2.6 * zoom)),
                         with: .color(tint.opacity(0.8)))
            var body = Path()
            body.move(to: CGPoint(x: p.x, y: head.y + 1.3 * zoom))
            body.addLine(to: CGPoint(x: p.x, y: p.y + 2 * zoom))
            body.move(to: CGPoint(x: p.x - 1.4 * zoom + gait, y: p.y + 4.6 * zoom))
            body.addLine(to: CGPoint(x: p.x, y: p.y + 2 * zoom))
            body.addLine(to: CGPoint(x: p.x + 1.4 * zoom - gait, y: p.y + 4.6 * zoom))
            context.stroke(body, with: .color(tint.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
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

        case .orchard:
            // Three trees in a row that used to be a row.
            let bark = Color(red: 0.44, green: 0.34, blue: 0.24)
            let leaf = Color(red: 0.32, green: 0.46, blue: 0.28)
            for k in 0..<3 {
                let x = c.x + CGFloat(k - 1) * s * 0.72
                let lift = s * (k == 1 ? 0.18 : 0)
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: c.y + s * 0.7))
                    p.addLine(to: CGPoint(x: x, y: c.y - s * 0.1 - lift))
                }, with: .color(bark), lineWidth: 1)
                context.fill(
                    Path(ellipseIn: CGRect(x: x - s * 0.34, y: c.y - s * 0.7 - lift,
                                           width: s * 0.68, height: s * 0.66)),
                    with: .color(leaf))
                // The fruit is the point.
                context.fill(
                    Path(ellipseIn: CGRect(x: x + s * 0.10, y: c.y - s * 0.34 - lift,
                                           width: 1.8, height: 1.8)),
                    with: .color(Theme.accent.opacity(0.85)))
            }

        case .hermit:
            // A lean-to against nothing, and a fire that is always lit.
            let wood = Color(red: 0.46, green: 0.36, blue: 0.26)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.85, y: c.y + s * 0.6))
                p.addLine(to: CGPoint(x: c.x + s * 0.15, y: c.y - s * 0.8))
                p.addLine(to: CGPoint(x: c.x + s * 0.85, y: c.y + s * 0.6))
                p.closeSubpath()
            }, with: .color(wood), lineWidth: 1.1)
            let fire = 0.55 + 0.35 * sin(time * 4.2)
            context.fill(
                Path(ellipseIn: CGRect(x: c.x - s * 0.14, y: c.y + s * 0.16,
                                       width: s * 0.28, height: s * 0.34)),
                with: .color(Theme.accent.opacity(fire)))

        case .watchtower:
            // A broken shaft with the top gone and a stair still showing.
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.42, y: c.y + s * 0.75))
                p.addLine(to: CGPoint(x: c.x - s * 0.30, y: c.y - s * 1.05))
                p.addLine(to: CGPoint(x: c.x + s * 0.34, y: c.y - s * 0.72))
                p.addLine(to: CGPoint(x: c.x + s * 0.46, y: c.y + s * 0.75))
            }, with: .color(stone), lineWidth: 1.1)
            for k in 0..<3 {
                let y = c.y + s * (0.42 - CGFloat(k) * 0.46)
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: c.x - s * 0.36, y: y))
                    p.addLine(to: CGPoint(x: c.x + s * 0.40, y: y))
                }, with: .color(stone.opacity(0.55)), lineWidth: 0.7)
            }

        case .saltPan:
            // Flat crusted plates with a rake's furrows across them.
            let crust = Color(red: 0.82, green: 0.84, blue: 0.86)
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.95, y: c.y - s * 0.42,
                                                width: s * 1.9, height: s * 0.84)),
                         with: .color(crust.opacity(0.42)))
            context.stroke(Path(ellipseIn: CGRect(x: c.x - s * 0.95, y: c.y - s * 0.42,
                                                  width: s * 1.9, height: s * 0.84)),
                           with: .color(crust.opacity(0.85)), lineWidth: 0.9)
            for k in 0..<3 {
                let y = c.y + s * (CGFloat(k) - 1) * 0.24
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: c.x - s * 0.62, y: y))
                    p.addLine(to: CGPoint(x: c.x + s * 0.62, y: y))
                }, with: .color(crust.opacity(0.55)), lineWidth: 0.6)
            }

        case .barrow:
            // A long low mound with a stone door let into its end.
            let earth = Color(red: 0.30, green: 0.30, blue: 0.26)
            context.fill(Path { p in
                p.move(to: CGPoint(x: c.x - s * 1.0, y: c.y + s * 0.6))
                p.addQuadCurve(to: CGPoint(x: c.x + s * 1.0, y: c.y + s * 0.6),
                               control: CGPoint(x: c.x, y: c.y - s * 0.95))
                p.closeSubpath()
            }, with: .color(earth))
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 1.0, y: c.y + s * 0.6))
                p.addQuadCurve(to: CGPoint(x: c.x + s * 1.0, y: c.y + s * 0.6),
                               control: CGPoint(x: c.x, y: c.y - s * 0.95))
            }, with: .color(stone), lineWidth: 1)
            context.fill(Path(CGRect(x: c.x - s * 0.20, y: c.y + s * 0.06,
                                     width: s * 0.40, height: s * 0.54)),
                         with: .color(Theme.ink))

        case .starfall:
            // A crater lip, and something in the bottom of it that still glows.
            context.stroke(Path(ellipseIn: CGRect(x: c.x - s * 1.0, y: c.y - s * 0.5,
                                                  width: s * 2.0, height: s * 1.0)),
                           with: .color(stone), lineWidth: 1)
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.5, y: c.y - s * 0.25,
                                                width: s * 1.0, height: s * 0.5)),
                         with: .color(Theme.ink))
            let heat = 0.45 + 0.4 * abs(sin(time * 1.1))
            context.fill(
                Path(ellipseIn: CGRect(x: c.x - s * 0.20, y: c.y - s * 0.11,
                                       width: s * 0.40, height: s * 0.22)),
                with: .color(Color(red: 1.0, green: 0.62, blue: 0.34).opacity(heat)))
        }
    }

    // A building's materials — a warm dark timber body under bright bone
    // linework, a solid mass on the ground rather than an outline. The base
    // tones below are nudged per building by `tone(...)`, so two of the same
    // kind read as neighbours, not clones.
    private static let baseWall = (0.20, 0.18, 0.16)
    private static let baseRoof = (0.12, 0.11, 0.11)
    private static let baseStone = (0.24, 0.24, 0.26)

    /// What an era builds *out of*. A colony that has reached fusion should not
    /// still be drawn in wattle and thatch: timber warms into brick, brick cools
    /// into concrete, and concrete pales into panel and glass. Read straight off
    /// the building's own era, so this ages with the content and not with a
    /// switch someone has to remember to update.
    static func materials(_ era: Era) -> (wall: (Double, Double, Double),
                                                  roof: (Double, Double, Double),
                                                  stone: (Double, Double, Double)) {
        switch era {
        case .earlySettlement, .ancient:
            return (baseWall, baseRoof, baseStone)               // timber, thatch
        case .medieval:
            return ((0.21, 0.19, 0.17), (0.13, 0.12, 0.12), (0.26, 0.26, 0.27))
        case .earlyIndustrial:
            return ((0.25, 0.17, 0.14), (0.13, 0.12, 0.13), (0.23, 0.22, 0.23))  // brick, soot
        case .modern:
            return ((0.22, 0.23, 0.24), (0.15, 0.16, 0.17), (0.26, 0.27, 0.29))  // concrete
        case .nearFuture:
            return ((0.20, 0.24, 0.27), (0.14, 0.18, 0.20), (0.24, 0.28, 0.31))  // panel, glass
        }
    }

    /// A base tone shifted a little — lighter/darker and warmer/cooler — from a
    /// per-building seed, so a row of houses isn't a row of identical stamps.
    static func tone(_ rgb: (Double, Double, Double), _ seed: UInt64,
                             spread: Double = 0.05) -> Color {
        let u: (UInt64) -> Double = { Double(($0 &* 0x2545_F491_4F6C_DD1D) >> 40 & 0xFFFF) / 65535 - 0.5 }
        let l = u(seed) * 2 * spread          // lighter or darker
        let warm = u(seed &* 7) * spread      // warmer or cooler: +red, −blue
        return Color(red: min(1, max(0, rgb.0 + l + warm)),
                     green: min(1, max(0, rgb.1 + l)),
                     blue: min(1, max(0, rgb.2 + l - warm)))
    }

    /// The soft pool of shade a structure casts on the ground — the cheapest,
    /// strongest cue that it *sits* somewhere rather than floating.
    static func groundShadow(at c: CGPoint, halfWidth w: CGFloat, footY: CGFloat,
                                     context: inout GraphicsContext) {
        let sw = w * 2.3, sh = w * 0.7
        context.fill(
            Path(ellipseIn: CGRect(x: c.x - sw / 2, y: footY - sh / 2, width: sw, height: sh)),
            with: .radialGradient(
                Gradient(colors: [Theme.ink.opacity(0.42), .clear]),
                center: CGPoint(x: c.x, y: footY), startRadius: 0, endRadius: sw / 2))
    }

    /// What a wall is built of, as something to draw.
    ///
    /// The era already decided the *palette* — timber and thatch give way to
    /// brick, then to panel and glass — and that was the whole of the story, so
    /// every building raised in the same century was the same drawing in
    /// different sizes. What a building is actually made of is in its own
    /// `materialCost`, and `Cover.substance` has been reading it since the
    /// cover model went in. This is the same fact, drawn: log courses on a
    /// timber house, coursed blocks on a stone one, a woven wall on a hut of
    /// sticks and turf.
    static func fabricLines(
        _ fabric: Cover.Substance, in body: CGRect, seed: UInt64,
        ink: Color, context: inout GraphicsContext
    ) {
        let faint = ink.opacity(0.30)
        switch fabric {
        case .wood:
            // Horizontal log courses, and the odd one out of true.
            let courses = max(2, Int(body.height / 5))
            for course in 1..<courses {
                let y = body.minY + body.height * CGFloat(course) / CGFloat(courses)
                let sag = CGFloat((seed >> UInt64(course % 40)) & 3) * 0.25
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: body.minX + 0.5, y: y))
                    p.addLine(to: CGPoint(x: body.maxX - 0.5, y: y + sag))
                }, with: .color(faint), lineWidth: 0.5)
            }
        case .stone:
            // Coursed blocks, offset every other row — the whole reason stone
            // reads as stone from any distance.
            let courses = max(2, Int(body.height / 4.5))
            for course in 1..<courses {
                let y = body.minY + body.height * CGFloat(course) / CGFloat(courses)
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: body.minX + 0.5, y: y))
                    p.addLine(to: CGPoint(x: body.maxX - 0.5, y: y))
                }, with: .color(faint), lineWidth: 0.5)
                let joints = 3
                for joint in 0..<joints {
                    let offset = course % 2 == 0 ? 0.5 : 0.0
                    let x = body.minX + body.width * (CGFloat(joint) + 0.5 + offset) / CGFloat(joints)
                    guard x > body.minX, x < body.maxX else { continue }
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: x, y: y))
                        p.addLine(to: CGPoint(x: x, y: y - body.height / CGFloat(courses)))
                    }, with: .color(faint), lineWidth: 0.4)
                }
            }
        case .foliage:
            // Wattle and turf: a woven wall, drawn as uprights and a weave.
            let uprights = max(3, Int(body.width / 5))
            for post in 1..<uprights {
                let x = body.minX + body.width * CGFloat(post) / CGFloat(uprights)
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: body.minY + 1))
                    p.addLine(to: CGPoint(x: x, y: body.maxY - 1))
                }, with: .color(faint), lineWidth: 0.4)
            }
        case .air:
            // Panel and glass: one long band, and nothing else.
            context.stroke(Path { p in
                p.move(to: CGPoint(x: body.minX + 1, y: body.midY))
                p.addLine(to: CGPoint(x: body.maxX - 1, y: body.midY))
            }, with: .color(faint), lineWidth: 0.6)
        }
    }

    /// **The walls, as actually drawn.** One rect, asked for by two callers.
    ///
    /// Keks, at zoom: *"vypadají uvnitř budovy skoro stejně, taky světlo z nich
    /// prosvítá přes stěny."* The second half was a real fault and this is it.
    /// `SettlementInterior` sized its room off the **lot** — the footprint,
    /// inset a tenth — while the structure draws its body off `s`, which is the
    /// lot over 2.2. On a 3×3 lot that is a room four fifths of the plot inside
    /// a house half of it: the floor, the lamplight and half the furniture were
    /// laid outside the walls that were supposed to contain them, and after
    /// dark the light came with them.
    ///
    /// So the room comes from the same rect the walls do. Rule 35 in the
    /// drawing: a number that must equal another number should *be* it.
    static func bodyRect(
        _ glyph: SettlementRenderer.BuildingGlyph, at c: CGPoint, s s0: CGFloat,
        seed: UInt64, footprint: CGSize
    ) -> CGRect {
        let aspect = footprint.height > 0
            ? Double(footprint.width / footprint.height) : 1
        let size = bodySize(glyph, s: Double(s0), seed: seed, aspect: aspect)
        return CGRect(x: c.x - CGFloat(size.width) / 2, y: c.y - CGFloat(size.height) / 2,
                      width: CGFloat(size.width), height: CGFloat(size.height))
    }

    /// The same walls in whatever units the caller measures in.
    ///
    /// Three callers, one formula: the structure draws it, the interior
    /// furnishes inside it, and `AgentMotion` stands people at the fittings —
    /// in normalised map units rather than pixels. When these disagreed, the
    /// smith was drawn hammering an anvil that was somewhere else.
    static func bodySize(
        _ glyph: SettlementRenderer.BuildingGlyph, s s0: Double,
        seed: UInt64, aspect rawAspect: Double
    ) -> (width: Double, height: Double) {
        let sizeJ = Double((seed &* 0x9E37_79B9_7F4A_7C15) >> 40 & 0xFFFF) / 65535
        let s = s0 * (0.9 + sizeJ * 0.2)
        let aspect = min(1.7, max(0.6, rawAspect))
        let shape = bodyShape(glyph)
        var width = s * Double(shape.width) * aspect
        var height = s * Double(shape.height)

        // **Fill the other axis too.**
        //
        // `lotSize` solves for the size that just fits, on *whichever* axis
        // binds first — and then the other one is left short by exactly the
        // ratio between them. For the ordinary house shape (1.6 wide by 1.1
        // tall) on a square lot that is 85% of the plot across and **58% of it
        // down**: a wide, squat model of a house with a band of bare ground
        // above and below it. Keks, at zoom: *"budovy mají malý interiér"* —
        // and the room is drawn inside these walls, so everything in it was
        // shrunk by the same amount before a single fitting was placed.
        //
        // The slack is computable from what is already here: the axis that did
        // not bind is short by `(lotH/lotW) · shapeW·aspect / shapeH`, and every
        // caller passes `rawAspect` as the lot's own width over its height.
        // Stretching by exactly that reaches the same fill the bound axis has
        // and — by construction — never passes it.
        //
        // Capped, because a hall that fills a square plot perfectly is a
        // square, and the silhouettes are how you tell a hall from a hut across
        // the valley. `maxStretch` is the most identity this will trade for
        // ground.
        let slack = rawAspect > 0
            ? (Double(shape.width) * aspect) / (Double(shape.height) * rawAspect)
            : 1
        if slack > 1 {
            height *= min(maxStretch, slack)
        } else if slack > 0 {
            width *= min(maxStretch, 1 / slack)
        }
        return (width, height)
    }

    /// How far a body may be stretched toward its lot before it stops looking
    /// like the kind of building it is. See `bodySize`.
    static let maxStretch: Double = 1.35

    /// How wide and tall each kind of building's walls run, in multiples of
    /// `s`. Most are the house's proportions; the ones that are not are the
    /// ones you can tell apart from across the valley.
    static func bodyShape(_ glyph: SettlementRenderer.BuildingGlyph) -> (width: CGFloat, height: CGFloat) {
        switch glyph {
        case .tower, .well: return (0.9, 1.5)
        case .hall, .temple, .market, .barracks: return (1.9, 1.2)
        case .tenement: return (1.5, 1.6)
        case .farm: return (1.8, 0.9)
        default: return (1.6, 1.1)
        }
    }

    // MARK: - Where the door is

    /// How many bays wide a building of this size is drawn — the count the door
    /// and the windows are both spaced against.
    static func bays(width: CGFloat, s: CGFloat) -> Int {
        max(1, min(4, Int((width / (s * 0.72)).rounded(.down))))
    }

    /// **Where the way in is**, as a fraction of the building's width from its
    /// middle: −0.5 is the left corner, 0 the centre, +0.5 the right.
    ///
    /// The door has always been drawn — for a house, in a bay picked off the
    /// seed — and nothing else in the game knew where it was. Colonists were
    /// placed at their station inside the room and walked to it in a straight
    /// line from wherever they had come from, which meant they came in through
    /// whichever wall happened to be in the way. This is that number, published
    /// once, so the drawing and the walking agree about where the door is.
    ///
    /// Only a dwelling has a bay-picked door; everything else is entered at the
    /// middle of its front, which is where the drawings put their openings.
    static func doorOffset(_ glyph: SettlementRenderer.BuildingGlyph,
                           seed: UInt64, width: CGFloat, s: CGFloat) -> Double {
        guard glyph == .house else { return 0 }
        let count = bays(width: width, s: s)
        let door = Int((seed >> 3) % UInt64(count))
        return (Double(door) + 0.5) / Double(count) - 0.5
    }

    // MARK: - Where the light comes out

    /// One opening in a wall, and whether anything is burning behind it.
    struct Pane {
        let rect: CGRect
        let lit: Bool
    }

    /// A dwelling's walls, its door and every window in them.
    ///
    /// Extracted so that **one** piece of arithmetic decides where a window is.
    /// It was written twice before — once here, drawing the panes, and once in
    /// `SettlementRenderer.nightLamps`, which did not know about bays at all
    /// and hung a single lamp at the middle of the roof. So after dark every
    /// house in the colony glowed from one point in its centre while its lit
    /// windows sat dark and unlit a bay to either side: the glow was not coming
    /// out of the openings it was supposed to be coming out of, which is
    /// exactly what it looked like.
    ///
    /// Pure, and a function of the same `(seed, footprint, floors)` the walls
    /// are drawn from, so a lamp cannot land where its window is not.
    static func dwelling(
        at c: CGPoint, s s0: CGFloat, seed: UInt64, footprint: CGSize, floors: Int,
        glyph: SettlementRenderer.BuildingGlyph = .house
    ) -> (body: CGRect, door: CGRect, panes: [Pane]) {
        // A block of flats is not a cottage with more storeys — it has its own
        // walls and its own grid of windows, drawn in `SettlementTrades`. Ask
        // the drawing that owns it rather than guessing at a gable.
        if glyph == .tenement {
            let sizeJ = Double((seed &* 0x9E37_79B9_7F4A_7C15) >> 40 & 0xFFFF) / 65535
            let s = s0 * CGFloat(0.9 + sizeJ * 0.2)
            let aspect: CGFloat = footprint.height > 0
                ? min(1.7, max(0.6, footprint.width / footprint.height)) : 1
            return (SettlementTrades.tenementBody(c, s, aspect), .zero,
                    SettlementTrades.tenementPanes(c, s, aspect, seed))
        }
        let sizeJ = Double((seed &* 0x9E37_79B9_7F4A_7C15) >> 40 & 0xFFFF) / 65535
        let s = s0 * CGFloat(0.9 + sizeJ * 0.2)
        let storeys = max(1, min(3, floors))
        let shell = bodyRect(.house, at: c, s: s0, seed: seed, footprint: footprint)
        let h = shell.height * (1 + CGFloat(storeys - 1) * 0.62)
        let body = CGRect(x: shell.minX, y: shell.maxY - h, width: shell.width, height: h)

        // A long house is a house with more *bays*, not a stretched hut: one
        // door and as many windows as it has rooms behind them.
        let bays = bays(width: body.width, s: s)
        let doorBay = Int((seed >> 3) % UInt64(bays))
        let storeyHeight = body.height / CGFloat(storeys)
        var door = CGRect.zero
        var panes: [Pane] = []
        for storey in 0..<storeys {
            // Counted from the ground up, so the door is always on the storey
            // somebody can walk into.
            let floorTop = body.maxY - storeyHeight * CGFloat(storey + 1)
            for bay in 0..<bays {
                let mid = body.minX + body.width * (CGFloat(bay) + 0.5) / CGFloat(bays)
                if storey == 0, bay == doorBay {
                    let dw = min(s * 0.32, body.width / CGFloat(bays) * 0.5)
                    let doorTop = max(floorTop + storeyHeight * 0.35,
                                      body.maxY - storeyHeight * 0.75)
                    door = CGRect(x: mid - dw / 2, y: doorTop,
                                  width: dw, height: body.maxY - doorTop)
                    continue
                }
                // Whether this window has a light behind it is fixed per house,
                // storey and bay — a home does not blink at you, and the upper
                // floor of a tenement is not lit in lockstep with the shop
                // under it.
                let lamp = UInt64(20 + bay + storey * 5) % 60
                let paneH = min(s * 0.3, storeyHeight * 0.45)
                panes.append(Pane(
                    rect: CGRect(x: mid - s * 0.17, y: floorTop + storeyHeight * 0.28,
                                 width: s * 0.34, height: paneH),
                    lit: ((seed >> lamp) & 3) != 0))
            }
        }
        return (body, door, panes)
    }


    // MARK: - Composition, so a shared archetype is not a shared drawing

    /// **How a block-shaped building is closed off at the top.**
    ///
    /// Five buildings were the `plant` archetype and four were `lab`, so a town
    /// of the late eras was one smoking block and one glass block repeated. The
    /// shape is right for all of them — what was missing is that a vehicle
    /// works, an assembly plant and an automated factory *close their roofs
    /// differently*, and always have.
    ///
    /// Drawn over `body`, so a case only has to say where its walls are.
    static func roofCap(
        _ line: StructureVariant.Roofline, over body: CGRect, s: CGFloat,
        roof: Color, ink: Color, bright: Color, context: inout GraphicsContext
    ) {
        switch line {
        case .flat:
            // A parapet: a lip standing a little proud of the wall.
            let lip = CGRect(x: body.minX - s * 0.04, y: body.minY - s * 0.09,
                             width: body.width + s * 0.08, height: s * 0.11)
            context.fill(Path(lip), with: .color(roof))
            context.stroke(Path(lip), with: .color(ink), lineWidth: 0.9)
        case .gable:
            let peak = Path { p in
                p.move(to: CGPoint(x: body.minX - s * 0.08, y: body.minY))
                p.addLine(to: CGPoint(x: body.midX, y: body.minY - s * 0.42))
                p.addLine(to: CGPoint(x: body.maxX + s * 0.08, y: body.minY))
                p.closeSubpath()
            }
            context.fill(peak, with: .color(roof))
            context.stroke(peak, with: .color(ink), lineWidth: 1)
        case .sawtooth:
            // North light: the working roof, glazed on the shaded side. The one
            // roofline that says "there are benches under here".
            let teeth = max(2, Int(body.width / (s * 0.62)))
            for k in 0..<teeth {
                let x0 = body.minX + body.width * CGFloat(k) / CGFloat(teeth)
                let x1 = body.minX + body.width * CGFloat(k + 1) / CGFloat(teeth)
                let tooth = Path { p in
                    p.move(to: CGPoint(x: x0, y: body.minY))
                    p.addLine(to: CGPoint(x: x0, y: body.minY - s * 0.3))
                    p.addLine(to: CGPoint(x: x1, y: body.minY))
                    p.closeSubpath()
                }
                context.fill(tooth, with: .color(roof))
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: x0, y: body.minY - s * 0.3))
                    p.addLine(to: CGPoint(x: x0, y: body.minY))
                }, with: .color(bright), lineWidth: 0.8)
            }
        case .barrel:
            let shell = Path { p in
                p.move(to: CGPoint(x: body.minX, y: body.minY))
                p.addQuadCurve(to: CGPoint(x: body.maxX, y: body.minY),
                               control: CGPoint(x: body.midX, y: body.minY - s * 0.68))
                p.closeSubpath()
            }
            context.fill(shell, with: .color(roof))
            context.stroke(shell, with: .color(ink), lineWidth: 1)
        case .stepped:
            // Storeys that set back as they rise — what a tall building does.
            var step = body
            for k in 0..<3 {
                let inset = s * 0.16 * CGFloat(k + 1)
                step = CGRect(x: body.minX + inset, y: body.minY - s * 0.26 * CGFloat(k + 1),
                              width: max(s * 0.2, body.width - inset * 2), height: s * 0.28)
                context.fill(Path(step), with: .color(roof))
                context.stroke(Path(step), with: .color(ink), lineWidth: 0.8)
            }
        }
    }

    /// **What stands on the roof** — the second half of the same idea. A place
    /// that makes power carries collectors; a place that teaches carries an
    /// aerial; a place that cooks or burns carries vents.
    static func roofFurniture(
        _ top: StructureVariant.Rooftop, over body: CGRect, s: CGFloat,
        stone: Color, ink: Color, bright: Color, lit: Color,
        context: inout GraphicsContext
    ) {
        let y = body.minY
        switch top {
        case .none:
            break
        case .vents:
            for k in 0..<3 {
                let x = body.minX + body.width * (CGFloat(k) + 0.5) / 3
                let vent = CGRect(x: x - s * 0.07, y: y - s * 0.2, width: s * 0.14, height: s * 0.2)
                context.fill(Path(vent), with: .color(stone))
                context.stroke(Path(vent), with: .color(ink), lineWidth: 0.7)
            }
        case .array:
            // Collectors lying back toward the light.
            let panels = max(2, Int(body.width / (s * 0.5)))
            for k in 0..<panels {
                let x = body.minX + body.width * (CGFloat(k) + 0.5) / CGFloat(panels)
                let panel = Path { p in
                    p.move(to: CGPoint(x: x - s * 0.2, y: y - s * 0.04))
                    p.addLine(to: CGPoint(x: x + s * 0.06, y: y - s * 0.26))
                    p.addLine(to: CGPoint(x: x + s * 0.2, y: y - s * 0.18))
                    p.addLine(to: CGPoint(x: x - s * 0.06, y: y + s * 0.04))
                    p.closeSubpath()
                }
                context.fill(panel, with: .color(lit.opacity(0.5)))
                context.stroke(panel, with: .color(bright), lineWidth: 0.6)
            }
        case .aerial:
            let mast = CGPoint(x: body.midX + body.width * 0.28, y: y)
            context.stroke(Path { p in
                p.move(to: mast)
                p.addLine(to: CGPoint(x: mast.x, y: y - s * 0.62))
            }, with: .color(ink), lineWidth: 1)
            for k in 1...3 {
                let ry = y - s * 0.62 + s * 0.14 * CGFloat(k)
                let w = s * 0.07 * CGFloat(k)
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: mast.x - w, y: ry))
                    p.addLine(to: CGPoint(x: mast.x + w, y: ry))
                }, with: .color(bright.opacity(0.8)), lineWidth: 0.7)
            }
        case .tank:
            let r = s * 0.24
            let tank = CGRect(x: body.midX - r, y: y - r * 1.5, width: r * 2, height: r * 1.5)
            context.fill(Path(roundedRect: tank, cornerRadius: r * 0.45), with: .color(stone))
            context.stroke(Path(roundedRect: tank, cornerRadius: r * 0.45),
                           with: .color(ink), lineWidth: 0.8)
            // Legs, so it reads as standing on the roof rather than sunk in it.
            context.stroke(Path { p in
                p.move(to: CGPoint(x: tank.minX + r * 0.3, y: tank.maxY))
                p.addLine(to: CGPoint(x: tank.minX + r * 0.3, y: y))
                p.move(to: CGPoint(x: tank.maxX - r * 0.3, y: tank.maxY))
                p.addLine(to: CGPoint(x: tank.maxX - r * 0.3, y: y))
            }, with: .color(ink), lineWidth: 0.7)
        }
    }

    /// A door wide enough for what lives inside. A stable, a wainwright's and a
    /// garage all need one; a library does not.
    static func frontDoor(
        wide: Bool, on body: CGRect, s: CGFloat, at x: CGFloat,
        ink: Color, dark: Color, context: inout GraphicsContext
    ) {
        let w = wide ? s * 0.62 : s * 0.24
        let h = wide ? s * 0.52 : s * 0.42
        let door = CGRect(x: x - w / 2, y: body.maxY - h, width: w, height: h)
        context.fill(Path(door), with: .color(dark))
        context.stroke(Path(door), with: .color(ink), lineWidth: 0.8)
        guard wide else { return }
        // A roller shutter reads as a vehicle door and not as a big front door.
        for k in 1..<4 {
            let y = door.minY + door.height * CGFloat(k) / 4
            context.stroke(Path { p in
                p.move(to: CGPoint(x: door.minX, y: y))
                p.addLine(to: CGPoint(x: door.maxX, y: y))
            }, with: .color(ink.opacity(0.5)), lineWidth: 0.5)
        }
    }

    static func building(
        _ glyph: SettlementRenderer.BuildingGlyph, at c: CGPoint, s s0: CGFloat,
        time: Double = 0, night: Double = 0, seed: UInt64 = 0,
        era: Era = .earlySettlement, footprint: CGSize = .zero,
        fabric: Cover.Substance = .wood, floors: Int = 1,
        variant: StructureVariant = .plain,
        context: inout GraphicsContext
    ) {
        // Per-building variation so same-type structures aren't clones: a nudge
        // to overall size, and to each material's tone.
        let sizeJ = Double((seed &* 0x9E37_79B9_7F4A_7C15) >> 40 & 0xFFFF) / 65535
        let s = s0 * CGFloat(0.9 + sizeJ * 0.2)
        // How the ground it owns is shaped: a 3×2 lot wants a long building, a
        // 2×2 a square one. Clamped so nothing becomes a ribbon.
        let aspect: CGFloat = footprint.height > 0
            ? min(1.7, max(0.6, footprint.width / footprint.height)) : 1
        let base = materials(era)
        let wall = tone(base.wall, seed)
        let roof = tone(base.roof, seed &* 3, spread: 0.035)
        let stone = tone(base.stone, seed &* 5)
        let ink = Theme.bone.opacity(0.85)
        let bright = Theme.bone.opacity(0.96)
        let lit = Theme.accent.opacity(0.32 + night * 0.55)   // a lamp lit after dark
        switch glyph {
        case .house:
            // A home, and not the same home twice.
            //
            // One drawing served every dwelling in the colony: a hut and a
            // longhouse were the same gable at two sizes, with one window in
            // the same place. A street of them read as a stamp repeated. What a
            // house actually varies by is what it is *made* of, how long it is,
            // and what its household has left lying in the yard.
            // **How tall it stands.** `floors` has been in `buildings.json`
            // since the beginning and was read by one thing — `HouseholdEngine`,
            // counting beds — so a tenement was a tenement because its `look`
            // said so and not because it had three storeys. A second storey is
            // a taller wall and another row of windows, which is what makes a
            // street of houses and a street of tenements different streets.
            // The ground floor is the room the interior furnishes; anything
            // above it is storeys, rising off the same footings. `floors` has
            // been in the data since the beginning and read by one thing —
            // `HouseholdEngine`, counting beds — so a building that stacks
            // people has never *looked* like one.
            // The walls, the door and the windows — all of it from `dwelling`,
            // which is now the one place that decides where a house's openings
            // are. The lamps that burn behind them after dark read the same
            // function, which is the whole point of it being one.
            let openings = dwelling(at: c, s: s0, seed: seed,
                                    footprint: footprint, floors: floors)
            let body = openings.body
            let w = body.width
            let h = body.height
            groundShadow(at: c, halfWidth: w / 2, footY: body.maxY + s * 0.08, context: &context)
            context.fill(Path(body), with: .color(wall))
            // What the wall is made of, before anything is drawn on it.
            fabricLines(fabric, in: body, seed: seed, ink: ink, context: &context)

            // How steeply it is roofed, and whether the ridge is thatched or
            // shingled. Fixed per house, so a street has variety and a house
            // does not change its own roof between frames — and **weighted by
            // what the house is built of**: nobody thatches a stone house they
            // could tile, and a hut of sticks and turf is never shingled.
            let pitch = 0.58 + Double((seed >> 18) & 7) / 20      // 0.58…0.93
            let thatched: Bool
            switch fabric {
            case .stone, .air: thatched = (seed >> 9) & 7 == 0    // rarely
            case .foliage: thatched = true
            case .wood: thatched = (seed >> 9) & 1 == 0
            }
            let ridgeY = body.minY - h * CGFloat(pitch)
            let eaves = s * 0.16
            let roofShape = Path { p in
                p.move(to: CGPoint(x: body.minX - eaves, y: body.minY))
                if thatched {
                    // Thatch sags: a soft ridge rather than a folded one.
                    p.addQuadCurve(to: CGPoint(x: body.maxX + eaves, y: body.minY),
                                   control: CGPoint(x: c.x, y: ridgeY - h * 0.18))
                } else {
                    p.addLine(to: CGPoint(x: c.x, y: ridgeY))
                    p.addLine(to: CGPoint(x: body.maxX + eaves, y: body.minY))
                }
                p.closeSubpath()
            }
            context.fill(roofShape, with: .color(roof))
            context.stroke(Path(body), with: .color(ink), lineWidth: 1)
            context.stroke(roofShape, with: .color(bright), lineWidth: 1.1)
            if !thatched {
                for k in 1...2 {
                    let t = CGFloat(k) / 3
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: body.minX - eaves + (c.x - body.minX + eaves) * t,
                                           y: body.minY - (body.minY - ridgeY) * (1 - t)))
                        p.addLine(to: CGPoint(x: body.maxX + eaves - (body.maxX + eaves - c.x) * t,
                                              y: body.minY - (body.minY - ridgeY) * (1 - t)))
                    }, with: .color(Theme.boneDim.opacity(0.5)), lineWidth: 0.5)
                }
            }

            if openings.door.height > 0 {
                context.fill(Path(openings.door), with: .color(roof))
                context.stroke(Path(openings.door), with: .color(ink), lineWidth: 0.8)
            }
            for pane in openings.panes {
                context.fill(Path(pane.rect),
                             with: .color(pane.lit ? lit : stone.opacity(0.75)))
                context.stroke(Path(pane.rect), with: .color(ink), lineWidth: 0.6)
            }

            // A chimney, on the gable end, with smoke on it after dark.
            let stackX = body.minX + body.width * ((seed >> 5) & 1 == 0 ? 0.18 : 0.82)
            let stack = CGRect(x: stackX - s * 0.09, y: ridgeY + h * 0.06,
                               width: s * 0.18, height: body.minY - ridgeY + s * 0.1)
            if stack.height > 0 {
                context.fill(Path(stack), with: .color(stone))
                context.stroke(Path(stack), with: .color(ink), lineWidth: 0.6)
                if night > 0.15 {
                    for puff in 0..<3 {
                        let t = Double(puff) / 3
                        let drift = CGFloat(sin(time * 0.7 + Double(puff) * 1.3)) * s * 0.08
                        let r = s * CGFloat(0.07 + t * 0.09)
                        context.fill(Path(ellipseIn: CGRect(
                            x: stack.midX - r + drift,
                            y: stack.minY - s * CGFloat(0.16 + t * 0.5),
                            width: r * 2, height: r * 1.5)),
                            with: .color(Theme.boneDim.opacity(0.14 * night * (1 - t))))
                    }
                }
            }

            // And what a household leaves in its own yard. One of these, never
            // all of them: a colony of woodpiles is as much of a stamp as a
            // colony of bare walls.
            switch (seed >> 13) % 7 {
            case 4:
                // A water butt under the eaves, which is where one goes.
                let r = s * 0.16
                let butt = CGRect(x: body.maxX + s * 0.1, y: body.maxY - r * 2,
                                  width: r * 1.6, height: r * 2)
                context.fill(Path(butt), with: .color(stone.opacity(0.8)))
                context.stroke(Path(butt), with: .color(ink), lineWidth: 0.6)
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: butt.minX, y: butt.midY))
                    p.addLine(to: CGPoint(x: butt.maxX, y: butt.midY))
                }, with: .color(Theme.boneDim.opacity(0.5)), lineWidth: 0.4)
            case 5:
                // A handcart tipped on its shafts against the gable.
                let cart = CGRect(x: body.minX - s * 0.5, y: body.maxY - s * 0.22,
                                  width: s * 0.42, height: s * 0.18)
                context.stroke(Path(cart), with: .color(Theme.boneDim.opacity(0.55)),
                               lineWidth: 0.7)
                let wheel = s * 0.09
                context.stroke(Path(ellipseIn: CGRect(
                    x: cart.midX - wheel, y: cart.maxY - wheel * 0.6,
                    width: wheel * 2, height: wheel * 2)),
                    with: .color(Theme.boneDim.opacity(0.5)), lineWidth: 0.6)
            case 6:
                // A kitchen patch: three rows of something coming up.
                for row in 0..<3 {
                    let ry = body.maxY + s * (0.06 + CGFloat(row) * 0.07)
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: body.minX + s * 0.1, y: ry))
                        p.addLine(to: CGPoint(x: body.minX + s * 0.7, y: ry))
                    }, with: .color(Theme.good.opacity(0.28)), lineWidth: 0.6)
                }
            case 0:
                // A stack of firewood against the wall.
                for log in 0..<3 {
                    let ly = body.maxY - s * (0.06 + CGFloat(log) * 0.09)
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: body.maxX + s * 0.08, y: ly))
                        p.addLine(to: CGPoint(x: body.maxX + s * 0.42, y: ly))
                    }, with: .color(Theme.boneDim.opacity(0.55)), lineWidth: max(0.8, s * 0.07))
                }
            case 1:
                // A washing line between the eaves and a post.
                let postX = body.minX - s * 0.4
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: postX, y: body.maxY))
                    p.addLine(to: CGPoint(x: postX, y: body.midY - s * 0.1))
                }, with: .color(ink), lineWidth: 0.8)
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: postX, y: body.midY - s * 0.08))
                    p.addQuadCurve(to: CGPoint(x: body.minX, y: body.midY - s * 0.16),
                                   control: CGPoint(x: (postX + body.minX) / 2,
                                                    y: body.midY + s * 0.02))
                }, with: .color(Theme.boneDim.opacity(0.5)), lineWidth: 0.5)
            case 2:
                // A low fence around a scrap of garden.
                for post in 0..<4 {
                    let px = body.maxX + s * (0.12 + CGFloat(post) * 0.11)
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: px, y: body.maxY + s * 0.04))
                        p.addLine(to: CGPoint(x: px, y: body.maxY - s * 0.16))
                    }, with: .color(Theme.boneDim.opacity(0.45)), lineWidth: 0.6)
                }
            default:
                // A lean-to off the gable end — the commonest thing anyone
                // adds to a house they have outgrown.
                let lean = Path { p in
                    p.move(to: CGPoint(x: body.minX, y: body.maxY))
                    p.addLine(to: CGPoint(x: body.minX - s * 0.36, y: body.maxY))
                    p.addLine(to: CGPoint(x: body.minX - s * 0.3, y: body.midY + s * 0.04))
                    p.addLine(to: CGPoint(x: body.minX, y: body.midY - s * 0.06))
                    p.closeSubpath()
                }
                context.fill(lean, with: .color(wall.opacity(0.9)))
                context.stroke(lean, with: .color(ink), lineWidth: 0.7)
            }
        case .granary:
            let silo = CGRect(x: c.x - s * 0.7, y: c.y - s * 0.5, width: s * 1.4, height: s * 1.4)
            groundShadow(at: c, halfWidth: s * 0.7, footY: silo.maxY + s * 0.05, context: &context)
            context.fill(Path(ellipseIn: silo), with: .color(wall))
            context.stroke(Path(ellipseIn: silo), with: .color(ink), lineWidth: 1)
            // The hoops that hold a full silo together — narrower toward the
            // curved top and bottom, so the barrel reads as round.
            for band in 0..<3 {
                let dy = CGFloat(band) * 0.32 - 0.1
                let y = c.y + s * dy
                let half = s * (0.62 - abs(dy) * 0.4)
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: c.x - half, y: y))
                    p.addLine(to: CGPoint(x: c.x + half, y: y))
                }, with: .color(Theme.boneDim.opacity(0.6)), lineWidth: 0.6)
            }
            let cap = Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.82, y: c.y - s * 0.4))
                p.addLine(to: CGPoint(x: c.x, y: c.y - s * 1.32))
                p.addLine(to: CGPoint(x: c.x + s * 0.82, y: c.y - s * 0.4))
                p.closeSubpath()
            }
            context.fill(cap, with: .color(roof))
            context.stroke(cap, with: .color(bright), lineWidth: 1)
        case .cookhouse:
            // A low hall with its long side to the street, a broad oven stack
            // at one end and a shuttered serving hatch. It reads against the
            // granary next door: that one is a barrel you put things into,
            // this one is a roof things come out from under.
            let hw = s * 0.95 * aspect
            let body = CGRect(x: c.x - hw, y: c.y - s * 0.42, width: hw * 2, height: s * 0.92)
            groundShadow(at: c, halfWidth: s * 0.95, footY: body.maxY + s * 0.06, context: &context)
            context.fill(Path(body), with: .color(wall))
            context.stroke(Path(body), with: .color(ink), lineWidth: 0.9)
            // A shallow hipped roof — a kitchen is not a house.
            let lid = Path { p in
                p.move(to: CGPoint(x: body.minX - s * 0.12, y: body.minY))
                p.addLine(to: CGPoint(x: body.minX + s * 0.3, y: body.minY - s * 0.42))
                p.addLine(to: CGPoint(x: body.maxX - s * 0.3, y: body.minY - s * 0.42))
                p.addLine(to: CGPoint(x: body.maxX + s * 0.12, y: body.minY))
                p.closeSubpath()
            }
            context.fill(lid, with: .color(roof))
            context.stroke(lid, with: .color(bright), lineWidth: 1)
            // The oven stack, squat and wide, with the fire showing at its foot.
            let stack = CGRect(x: body.maxX - s * 0.62, y: body.minY - s * 0.92,
                               width: s * 0.44, height: s * 0.62)
            context.fill(Path(stack), with: .color(wall.opacity(0.95)))
            context.stroke(Path(stack), with: .color(ink), lineWidth: 0.7)
            let mouth = CGRect(x: body.maxX - s * 0.58, y: body.midY - s * 0.02,
                               width: s * 0.36, height: s * 0.3)
            context.fill(Path(roundedRect: mouth, cornerRadius: s * 0.14),
                         with: .color(Theme.accent.opacity(0.55)))
            // …and the hatch the food goes out of.
            let hatch = CGRect(x: body.minX + s * 0.24, y: body.midY - s * 0.06,
                               width: s * 0.5, height: s * 0.34)
            context.stroke(Path(hatch), with: .color(ink.opacity(0.7)), lineWidth: 0.7)
        case .workshop:
            let hw = s * 0.9 * aspect
            let body = CGRect(x: c.x - hw, y: c.y - s * 0.5, width: hw * 2, height: s)
            groundShadow(at: c, halfWidth: s * 0.9, footY: body.maxY + s * 0.06, context: &context)
            context.fill(Path(body), with: .color(wall))
            // A sawtooth roof — the workshop skylight, one tooth per quarter so
            // a wider shed grows more of them rather than stretching four.
            let teeth = max(2, Int((body.width / (s * 0.9)).rounded()))
            let saw = Path { p in
                p.move(to: CGPoint(x: body.minX, y: body.minY))
                for k in 0..<teeth {
                    let x0 = body.minX + body.width * CGFloat(k) / CGFloat(teeth)
                    let x1 = body.minX + body.width * CGFloat(k + 1) / CGFloat(teeth)
                    p.addLine(to: CGPoint(x: (x0 + x1) / 2, y: body.minY - s * 0.5))
                    p.addLine(to: CGPoint(x: x1, y: body.minY))
                }
            }
            context.stroke(Path(body), with: .color(ink), lineWidth: 1)
            context.stroke(saw, with: .color(bright), lineWidth: 1)
            // A lit forge-mouth and a working chimney.
            context.fill(Path(CGRect(x: c.x - s * 0.2, y: c.y - s * 0.05,
                                     width: s * 0.4, height: s * 0.4)),
                         with: .color(Theme.accent.opacity(0.45 + 0.2 * sin(time * 4))))
            context.fill(Path(CGRect(x: body.maxX - s * 0.35, y: body.minY - s * 0.75,
                                     width: s * 0.2, height: s * 0.5)), with: .color(roof))
            context.stroke(Path(CGRect(x: body.maxX - s * 0.35, y: body.minY - s * 0.75,
                                       width: s * 0.2, height: s * 0.5)),
                           with: .color(ink), lineWidth: 0.8)
        case .tower:
            let shaft = CGRect(x: c.x - s * 0.45, y: c.y - s * 1.2, width: s * 0.9, height: s * 1.9)
            groundShadow(at: c, halfWidth: s * 0.5, footY: shaft.maxY + s * 0.04, context: &context)
            context.fill(Path(shaft), with: .color(stone))
            context.stroke(Path(shaft), with: .color(ink), lineWidth: 1)
            // Crenellations along the top.
            let bat = Path { p in
                for i in 0..<3 {
                    let x = shaft.minX + CGFloat(i) * s * 0.36
                    p.addRect(CGRect(x: x, y: shaft.minY - s * 0.22, width: s * 0.18, height: s * 0.22))
                }
            }
            context.fill(bat, with: .color(stone))
            context.stroke(bat, with: .color(bright), lineWidth: 0.9)
            // Stone courses, an arrow slit, and a banner that answers the wind.
            for course in 1...3 {
                let y = shaft.minY + CGFloat(course) * s * 0.45
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: shaft.minX, y: y)); p.addLine(to: CGPoint(x: shaft.maxX, y: y))
                }, with: .color(Theme.boneDim.opacity(0.4)), lineWidth: 0.4)
            }
            context.fill(Path(CGRect(x: c.x - s * 0.08, y: c.y - s * 0.7,
                                     width: s * 0.16, height: s * 0.45)), with: .color(Theme.ink))
            let wave = CGFloat(sin(time * 2.4)) * s * 0.18
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x, y: c.y - s * 1.42)); p.addLine(to: CGPoint(x: c.x, y: c.y - s * 2.0))
            }, with: .color(ink), lineWidth: 0.8)
            context.fill(Path { p in
                p.move(to: CGPoint(x: c.x, y: c.y - s * 2.0))
                p.addLine(to: CGPoint(x: c.x + s * 0.55 + wave, y: c.y - s * 1.85))
                p.addLine(to: CGPoint(x: c.x, y: c.y - s * 1.7))
                p.closeSubpath()
            }, with: .color(Theme.accent.opacity(0.75)))
        case .temple:
            let base = CGRect(x: c.x - s * 0.95, y: c.y - s * 0.35, width: s * 1.9, height: s * 0.9)
            groundShadow(at: c, halfWidth: s * 1.05, footY: base.maxY + s * 0.35, context: &context)
            context.fill(Path(base), with: .color(stone))
            let pediment = Path { p in
                p.move(to: CGPoint(x: c.x - s * 1.08, y: c.y - s * 0.35))
                p.addLine(to: CGPoint(x: c.x, y: c.y - s * 1.18))
                p.addLine(to: CGPoint(x: c.x + s * 1.08, y: c.y - s * 0.35))
                p.closeSubpath()
            }
            context.fill(pediment, with: .color(roof))
            context.stroke(pediment, with: .color(bright), lineWidth: 1)
            context.stroke(Path(base), with: .color(ink), lineWidth: 1)
            // Fluted columns with dark gaps between them.
            for i in 0..<4 {
                let x = c.x - s * 0.72 + CGFloat(i) * s * 0.48
                context.fill(Path(CGRect(x: x - s * 0.09, y: c.y - s * 0.25,
                                         width: s * 0.18, height: s * 0.72)),
                             with: .color(Theme.bone.opacity(0.5)))
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: c.y - s * 0.25)); p.addLine(to: CGPoint(x: x, y: c.y + s * 0.47))
                }, with: .color(ink), lineWidth: 0.6)
            }
            for step in 0..<2 {
                let inset = s * (0.85 - CGFloat(step) * 0.16)
                let y = base.maxY + CGFloat(step + 1) * 1.7
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: c.x - inset, y: y)); p.addLine(to: CGPoint(x: c.x + inset, y: y))
                }, with: .color(Theme.boneDim.opacity(0.55)), lineWidth: 0.7)
            }
        case .mine:
            groundShadow(at: c, halfWidth: s * 0.8, footY: c.y + s * 0.62, context: &context)
            // The spoil-heap the shaft is cut into.
            context.fill(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.95, y: c.y + s * 0.6))
                p.addLine(to: CGPoint(x: c.x, y: c.y - s * 1.05))
                p.addLine(to: CGPoint(x: c.x + s * 0.95, y: c.y + s * 0.6))
                p.closeSubpath()
            }, with: .color(stone))
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.42, y: c.y - s * 0.1,
                                                width: s * 0.84, height: s * 0.5)),
                         with: .color(Theme.ink))   // the dark adit
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.95, y: c.y + s * 0.6))
                p.addLine(to: CGPoint(x: c.x, y: c.y - s * 1.05))
                p.addLine(to: CGPoint(x: c.x + s * 0.95, y: c.y + s * 0.6))
            }, with: .color(bright), lineWidth: 1)
            // A-frame headgear over the mouth.
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.3, y: c.y + s * 0.3))
                p.addLine(to: CGPoint(x: c.x, y: c.y - s * 0.5))
                p.addLine(to: CGPoint(x: c.x + s * 0.3, y: c.y + s * 0.3))
            }, with: .color(ink), lineWidth: 0.8)
            let shuttle = CGFloat(0.5 + 0.5 * sin(time * 1.1))
            let cart = CGPoint(x: c.x + s * 0.2 + s * 1.25 * shuttle, y: c.y + s * (0.5 + 0.1 * shuttle))
            context.fill(Path(CGRect(x: cart.x - s * 0.18, y: cart.y - s * 0.16,
                                     width: s * 0.36, height: s * 0.2)), with: .color(roof))
            context.stroke(Path(CGRect(x: cart.x - s * 0.18, y: cart.y - s * 0.16,
                                       width: s * 0.36, height: s * 0.2)), with: .color(ink), lineWidth: 0.6)
        case .mill:
            let body = CGRect(x: c.x - s * 0.9, y: c.y - s * 0.4, width: s * 1.5, height: s * 0.9)
            groundShadow(at: c, halfWidth: s * 0.9, footY: body.maxY + s * 0.06, context: &context)
            context.fill(Path(body), with: .color(wall))
            context.stroke(Path(body), with: .color(ink), lineWidth: 1)
            let wheel = CGRect(x: c.x + s * 0.35, y: c.y - s * 0.75, width: s * 0.9, height: s * 0.9)
            context.fill(Path(ellipseIn: wheel), with: .color(roof))
            context.stroke(Path(ellipseIn: wheel), with: .color(bright), lineWidth: 1)
            // The wheel actually turns — a working mill is the town's clock.
            let hub = CGPoint(x: wheel.midX, y: wheel.midY)
            let radius = wheel.width / 2
            let spin = time * 0.9
            context.stroke(Path { p in
                for spoke in 0..<6 {
                    let a = spin + Double(spoke) * .pi / 3
                    p.move(to: hub)
                    p.addLine(to: CGPoint(x: hub.x + CGFloat(cos(a)) * radius,
                                          y: hub.y + CGFloat(sin(a)) * radius))
                }
            }, with: .color(bright), lineWidth: 0.7)
        case .generator:
            let body = CGRect(x: c.x - s * 0.75, y: c.y - s * 0.4, width: s * 1.5, height: s * 1.0)
            groundShadow(at: c, halfWidth: s * 0.75, footY: body.maxY + s * 0.06, context: &context)
            context.fill(Path(body), with: .color(stone))
            context.stroke(Path(body), with: .color(ink), lineWidth: 1)
            // Cooling ribs, and a bolt that hums on a fast flicker.
            for i in 1...3 {
                let x = body.minX + CGFloat(i) * body.width / 4
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: body.minY + s * 0.12))
                    p.addLine(to: CGPoint(x: x, y: body.maxY - s * 0.12))
                }, with: .color(Theme.boneDim.opacity(0.4)), lineWidth: 0.5)
            }
            let hum = 0.65 + 0.3 * sin(time * 9)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x + s * 0.15, y: c.y - s * 0.3))
                p.addLine(to: CGPoint(x: c.x - s * 0.2, y: c.y + s * 0.1))
                p.addLine(to: CGPoint(x: c.x + s * 0.1, y: c.y + s * 0.1))
                p.addLine(to: CGPoint(x: c.x - s * 0.15, y: c.y + s * 0.5))
            }, with: .color(Theme.accent.opacity(hum)), lineWidth: 1.2)

        case .hall:
            // Learning: a long hall with a clerestory over a colonnade. Reads as
            // civic without borrowing the monument's pediment.
            let hw = s * 1.05 * aspect
            let body = CGRect(x: c.x - hw, y: c.y - s * 0.45, width: hw * 2, height: s * 1.0)
            groundShadow(at: c, halfWidth: hw, footY: body.maxY + s * 0.06, context: &context)
            context.fill(Path(body), with: .color(wall))
            context.stroke(Path(body), with: .color(ink), lineWidth: 1)
            // A raised clerestory — the reading light.
            let clere = CGRect(x: body.minX + hw * 0.25, y: body.minY - s * 0.42,
                               width: hw * 1.5, height: s * 0.42)
            context.fill(Path(clere), with: .color(roof))
            context.stroke(Path(clere), with: .color(bright), lineWidth: 1)
            // A library, a school and a university are all this hall. What
            // separates them is how much of it there is: the panes across the
            // clerestory, the aerial a university carries and a village school
            // does not.
            let panes = max(3, variant.bays)
            for k in 0..<panes {
                let x = clere.minX + clere.width * (CGFloat(k) + 0.5) / CGFloat(panes)
                context.fill(Path(CGRect(x: x - s * 0.07, y: clere.minY + s * 0.09,
                                         width: s * 0.14, height: s * 0.24)),
                             with: .color(variant.nightShift ? lit : lit.opacity(0.3)))
            }
            roofFurniture(variant.rooftop, over: clere, s: s,
                          stone: stone, ink: ink, bright: bright, lit: lit, context: &context)
            // The colonnade along the front — a grander hall has more of it.
            let posts = max(3, variant.bays + variant.tier)
            for k in 0..<posts {
                let x = body.minX + body.width * (CGFloat(k) + 0.5) / CGFloat(posts)
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: body.minY + s * 0.14))
                    p.addLine(to: CGPoint(x: x, y: body.maxY - s * 0.06))
                }, with: .color(Theme.boneDim.opacity(0.55)), lineWidth: 0.7)
            }

        case .market:
            // Exchange: open stalls under awnings, with goods stacked beneath.
            let hw = s * 1.0 * aspect
            groundShadow(at: c, halfWidth: hw, footY: c.y + s * 0.55, context: &context)
            let stalls = max(2, Int(hw / (s * 0.55)))
            for k in 0..<stalls {
                let x = c.x - hw + (hw * 2) * (CGFloat(k) + 0.5) / CGFloat(stalls)
                let top = c.y - s * 0.45
                // A striped awning, sagging a little between its poles.
                let awning = Path { p in
                    p.move(to: CGPoint(x: x - s * 0.42, y: top))
                    p.addQuadCurve(to: CGPoint(x: x + s * 0.42, y: top),
                                   control: CGPoint(x: x, y: top + s * 0.18))
                    p.addLine(to: CGPoint(x: x + s * 0.34, y: top - s * 0.2))
                    p.addLine(to: CGPoint(x: x - s * 0.34, y: top - s * 0.2))
                    p.closeSubpath()
                }
                context.fill(awning, with: .color(k % 2 == 0 ? roof : Theme.accent.opacity(0.34)))
                context.stroke(awning, with: .color(bright), lineWidth: 0.8)
                // Poles down to the ground, and a crate of goods between them.
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: x - s * 0.38, y: top))
                    p.addLine(to: CGPoint(x: x - s * 0.38, y: c.y + s * 0.5))
                    p.move(to: CGPoint(x: x + s * 0.38, y: top))
                    p.addLine(to: CGPoint(x: x + s * 0.38, y: c.y + s * 0.5))
                }, with: .color(ink), lineWidth: 0.8)
                context.fill(Path(CGRect(x: x - s * 0.24, y: c.y + s * 0.12,
                                         width: s * 0.48, height: s * 0.34)),
                             with: .color(wall))
            }

        case .plant:
            // Heavy industry — and five different industries, not one.
            //
            // `factory`, `vehicle_works`, `assembly_plant`, `automated_factory`
            // and `garage` all draw here, so everything that tells them apart
            // comes out of `variant`: how many chimneys the work needs (a
            // garage has none), whether the front has a door a lorry fits
            // through, whether anyone is here after dark, and how the roof is
            // closed. See `StructureVariant`.
            let hw = s * (0.9 + CGFloat(variant.tier) * 0.06) * aspect
            let body = CGRect(x: c.x - hw, y: c.y - s * 0.55, width: hw * 2, height: s * 1.2)
            groundShadow(at: c, halfWidth: hw, footY: body.maxY + s * 0.05, context: &context)
            context.fill(Path(body), with: .color(stone))
            context.stroke(Path(body), with: .color(ink), lineWidth: 1)
            roofCap(variant.roofline, over: body, s: s,
                    roof: roof, ink: ink, bright: bright, context: &context)
            roofFurniture(variant.rooftop, over: body, s: s,
                          stone: stone, ink: ink, bright: bright, lit: lit, context: &context)
            // A band of windows. Lit only if somebody is posted here — an
            // automated works runs in the dark, which is what it is *for*.
            let bays = max(3, variant.bays)
            for k in 0..<bays {
                let x = body.minX + body.width * (CGFloat(k) + 0.5) / CGFloat(bays)
                context.fill(Path(CGRect(x: x - s * 0.08, y: c.y - s * 0.18,
                                         width: s * 0.16, height: s * 0.3)),
                             with: .color(variant.nightShift
                                          ? lit.opacity(0.7)
                                          : Theme.boneDim.opacity(0.18)))
            }
            frontDoor(wide: variant.wideDoor, on: body, s: s, at: body.midX,
                      ink: ink, dark: Theme.boneDim.opacity(0.3), context: &context)
            // Chimneys: as many as the work actually sends up, tallest first.
            for i in 0..<variant.stacks {
                let dx = -0.55 + CGFloat(i) * 0.42
                let h = s * (1.5 - CGFloat(i) * 0.22)
                let stack = CGRect(x: c.x + hw * dx, y: body.minY - h, width: s * 0.26, height: h)
                context.fill(Path(stack), with: .color(roof))
                context.stroke(Path(stack), with: .color(ink), lineWidth: 0.8)
                for k in 0..<3 {
                    let t = (time * 0.22 + Double(k) * 0.33 + Double(i) * 0.17)
                        .truncatingRemainder(dividingBy: 1)
                    let r = s * (0.16 + CGFloat(t) * 0.4)
                    let y = stack.minY - CGFloat(t) * s * 1.5
                    let x = stack.midX + CGFloat(sin(t * 4 + Double(i))) * s * 0.24
                    context.fill(Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2,
                                                        width: r, height: r)),
                                 with: .color(Theme.boneDim.opacity((1 - t) * 0.26)))
                }
            }

        case .array:
            // A field of collectors: rows of tilted panels lying over the ground,
            // low and wide — nothing like a building, which is the point.
            let hw = s * 1.15 * aspect
            groundShadow(at: c, halfWidth: hw, footY: c.y + s * 0.5, context: &context)
            let rows = 2, perRow = max(3, Int(hw / (s * 0.42)))
            for r in 0..<rows {
                let y = c.y - s * 0.1 + CGFloat(r) * s * 0.46
                for k in 0..<perRow {
                    let x = c.x - hw + (hw * 2) * (CGFloat(k) + 0.5) / CGFloat(perRow)
                    // A parallelogram reads as a panel tilted to the sun.
                    let panel = Path { p in
                        p.move(to: CGPoint(x: x - s * 0.3, y: y + s * 0.16))
                        p.addLine(to: CGPoint(x: x - s * 0.14, y: y - s * 0.16))
                        p.addLine(to: CGPoint(x: x + s * 0.32, y: y - s * 0.16))
                        p.addLine(to: CGPoint(x: x + s * 0.16, y: y + s * 0.16))
                        p.closeSubpath()
                    }
                    context.fill(panel, with: .color(stone))
                    context.stroke(panel, with: .color(bright.opacity(0.75)), lineWidth: 0.6)
                    // A slow glint travelling along the rows.
                    let glint = sin(time * 0.8 + Double(k) * 0.7 + Double(r))
                    if glint > 0.86 {
                        context.fill(panel, with: .color(Theme.accent.opacity(0.28)))
                    }
                }
            }

        case .pad:
            // A launch complex: an apron, a gantry, and a vehicle standing on it.
            let hw = s * 1.0 * aspect
            let apron = CGRect(x: c.x - hw, y: c.y + s * 0.15, width: hw * 2, height: s * 0.5)
            groundShadow(at: c, halfWidth: hw, footY: apron.maxY + s * 0.04, context: &context)
            context.fill(Path(ellipseIn: apron), with: .color(stone))
            context.stroke(Path(ellipseIn: apron), with: .color(ink), lineWidth: 1)
            // The vehicle: a slim body under a nose cone, on fins.
            let bodyW = s * 0.42, bodyH = s * 1.5
            let rocket = CGRect(x: c.x - bodyW / 2, y: c.y - s * 1.15, width: bodyW, height: bodyH)
            context.fill(Path(rocket), with: .color(wall))
            context.stroke(Path(rocket), with: .color(bright), lineWidth: 1)
            let nose = Path { p in
                p.move(to: CGPoint(x: rocket.minX, y: rocket.minY))
                p.addLine(to: CGPoint(x: c.x, y: rocket.minY - s * 0.62))
                p.addLine(to: CGPoint(x: rocket.maxX, y: rocket.minY))
                p.closeSubpath()
            }
            context.fill(nose, with: .color(roof))
            context.stroke(nose, with: .color(bright), lineWidth: 1)
            context.fill(Path { p in
                p.move(to: CGPoint(x: rocket.minX, y: rocket.maxY))
                p.addLine(to: CGPoint(x: rocket.minX - s * 0.26, y: rocket.maxY + s * 0.3))
                p.addLine(to: CGPoint(x: rocket.minX, y: rocket.maxY - s * 0.3))
                p.closeSubpath()
                p.move(to: CGPoint(x: rocket.maxX, y: rocket.maxY))
                p.addLine(to: CGPoint(x: rocket.maxX + s * 0.26, y: rocket.maxY + s * 0.3))
                p.addLine(to: CGPoint(x: rocket.maxX, y: rocket.maxY - s * 0.3))
                p.closeSubpath()
            }, with: .color(roof))
            // The gantry alongside, and a beacon that keeps its own time.
            let mast = CGRect(x: c.x + hw * 0.5, y: c.y - s * 1.0, width: s * 0.12, height: s * 1.5)
            context.fill(Path(mast), with: .color(stone))
            for k in 0..<4 {
                let y = mast.minY + mast.height * CGFloat(k) / 4
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: mast.minX, y: y))
                    p.addLine(to: CGPoint(x: rocket.maxX, y: y + s * 0.08))
                }, with: .color(Theme.boneDim.opacity(0.5)), lineWidth: 0.6)
            }
            let beacon = 0.35 + 0.5 * max(0, sin(time * 2.2))
            context.fill(Path(ellipseIn: CGRect(x: mast.midX - s * 0.1, y: mast.minY - s * 0.2,
                                                width: s * 0.2, height: s * 0.2)),
                         with: .color(Theme.accent.opacity(beacon)))

        // The trades: the seventeen archetypes added when forty-seven buildings
        // turned out to be sharing eleven shapes. In `SettlementTrades`, purely
        // because this file was already at the size limit.
        case .tenement, .farm, .lodge, .sawmill, .well, .forge, .tanks, .rail,
             .lab, .dish, .vault, .clinic, .aqueduct, .wall, .barracks,
             .turbine, .dam:
            SettlementTrades.draw(
                glyph, at: c, s: s, aspect: aspect, time: time, night: night,
                seed: seed, era: era, variant: variant,
                surfaces: SettlementTrades.Surfaces(
                    wall: wall, roof: roof, stone: stone,
                    ink: ink, bright: bright, lit: lit),
                context: &context)
        }
    }
}
