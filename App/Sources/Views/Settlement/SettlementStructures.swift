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
    private static func tone(_ rgb: (Double, Double, Double), _ seed: UInt64,
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
    private static func groundShadow(at c: CGPoint, halfWidth w: CGFloat, footY: CGFloat,
                                     context: inout GraphicsContext) {
        let sw = w * 2.3, sh = w * 0.7
        context.fill(
            Path(ellipseIn: CGRect(x: c.x - sw / 2, y: footY - sh / 2, width: sw, height: sh)),
            with: .radialGradient(
                Gradient(colors: [Theme.ink.opacity(0.42), .clear]),
                center: CGPoint(x: c.x, y: footY), startRadius: 0, endRadius: sw / 2))
    }

    static func building(
        _ glyph: SettlementRenderer.BuildingGlyph, at c: CGPoint, s s0: CGFloat,
        time: Double = 0, night: Double = 0, seed: UInt64 = 0,
        era: Era = .earlySettlement, footprint: CGSize = .zero,
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
            let w = s * 1.6 * aspect, h = s * 1.1
            let body = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
            groundShadow(at: c, halfWidth: w / 2, footY: body.maxY + s * 0.08, context: &context)
            // Walls, then a filled roof over them — a solid gabled house.
            context.fill(Path(body), with: .color(wall))
            let roofShape = Path { p in
                p.move(to: CGPoint(x: body.minX - s * 0.14, y: body.minY))
                p.addLine(to: CGPoint(x: c.x, y: body.minY - h * 0.72))
                p.addLine(to: CGPoint(x: body.maxX + s * 0.14, y: body.minY))
                p.closeSubpath()
            }
            context.fill(roofShape, with: .color(roof))
            context.stroke(Path(body), with: .color(ink), lineWidth: 1)
            context.stroke(roofShape, with: .color(bright), lineWidth: 1.1)
            // Two courses of shingles down the roof.
            for k in 1...2 {
                let t = CGFloat(k) / 3
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: body.minX - s * 0.14 + (c.x - body.minX + s * 0.14) * t,
                                       y: body.minY - h * 0.72 * (1 - t)))
                    p.addLine(to: CGPoint(x: body.maxX + s * 0.14 - (body.maxX + s * 0.14 - c.x) * t,
                                          y: body.minY - h * 0.72 * (1 - t)))
                }, with: .color(Theme.boneDim.opacity(0.5)), lineWidth: 0.5)
            }
            // A warm window — someone lives here — and a plank door.
            context.fill(Path(CGRect(x: c.x - s * 0.5, y: c.y - s * 0.08,
                                     width: s * 0.34, height: s * 0.32)), with: .color(lit))
            context.stroke(Path(CGRect(x: c.x - s * 0.5, y: c.y - s * 0.08,
                                       width: s * 0.34, height: s * 0.32)),
                           with: .color(ink), lineWidth: 0.6)
            let door = Path { p in
                p.move(to: CGPoint(x: c.x + s * 0.28, y: body.maxY))
                p.addLine(to: CGPoint(x: c.x + s * 0.28, y: c.y + s * 0.02))
                p.addLine(to: CGPoint(x: c.x + s * 0.6, y: c.y + s * 0.02))
                p.addLine(to: CGPoint(x: c.x + s * 0.6, y: body.maxY))
            }
            context.fill(door, with: .color(roof))
            context.stroke(door, with: .color(ink), lineWidth: 0.8)
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
            let panes = max(3, Int(hw / (s * 0.42)))
            for k in 0..<panes {
                let x = clere.minX + clere.width * (CGFloat(k) + 0.5) / CGFloat(panes)
                context.fill(Path(CGRect(x: x - s * 0.07, y: clere.minY + s * 0.09,
                                         width: s * 0.14, height: s * 0.24)),
                             with: .color(lit))
            }
            // The colonnade along the front.
            let posts = max(3, Int(hw / (s * 0.34)))
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
            // Heavy industry: a blunt block, stacks, and smoke that keeps coming.
            let hw = s * 1.0 * aspect
            let body = CGRect(x: c.x - hw, y: c.y - s * 0.55, width: hw * 2, height: s * 1.2)
            groundShadow(at: c, halfWidth: hw, footY: body.maxY + s * 0.05, context: &context)
            context.fill(Path(body), with: .color(stone))
            context.stroke(Path(body), with: .color(ink), lineWidth: 1)
            // A band of lit windows — the night shift.
            let bays = max(3, Int(hw / (s * 0.3)))
            for k in 0..<bays {
                let x = body.minX + body.width * (CGFloat(k) + 0.5) / CGFloat(bays)
                context.fill(Path(CGRect(x: x - s * 0.08, y: c.y - s * 0.18,
                                         width: s * 0.16, height: s * 0.3)),
                             with: .color(lit.opacity(0.7)))
            }
            // Two stacks, the taller one drawing.
            for (i, dx) in [(-0.55 as CGFloat), (0.3 as CGFloat)].enumerated() {
                let h = s * (i == 0 ? 1.5 : 1.05)
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
        }
    }
}
