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
        time: Double = 0, night: Double = 0, seed: UInt64 = 0, context: inout GraphicsContext
    ) {
        // Per-building variation so same-type structures aren't clones: a nudge
        // to overall size, and to each material's tone.
        let sizeJ = Double((seed &* 0x9E37_79B9_7F4A_7C15) >> 40 & 0xFFFF) / 65535
        let s = s0 * CGFloat(0.9 + sizeJ * 0.2)
        let wall = tone(baseWall, seed)
        let roof = tone(baseRoof, seed &* 3, spread: 0.035)
        let stone = tone(baseStone, seed &* 5)
        let ink = Theme.bone.opacity(0.85)
        let bright = Theme.bone.opacity(0.96)
        let lit = Theme.accent.opacity(0.32 + night * 0.55)   // a lamp lit after dark
        switch glyph {
        case .house:
            let w = s * 1.6, h = s * 1.1
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
            let body = CGRect(x: c.x - s * 0.9, y: c.y - s * 0.5, width: s * 1.8, height: s)
            groundShadow(at: c, halfWidth: s * 0.9, footY: body.maxY + s * 0.06, context: &context)
            context.fill(Path(body), with: .color(wall))
            // A sawtooth roof — the workshop skylight.
            let saw = Path { p in
                p.move(to: CGPoint(x: body.minX, y: body.minY))
                p.addLine(to: CGPoint(x: body.minX + s * 0.45, y: body.minY - s * 0.5))
                p.addLine(to: CGPoint(x: body.minX + s * 0.9, y: body.minY))
                p.addLine(to: CGPoint(x: body.minX + s * 1.35, y: body.minY - s * 0.5))
                p.addLine(to: CGPoint(x: body.maxX, y: body.minY))
            }
            context.stroke(Path(body), with: .color(ink), lineWidth: 1)
            context.stroke(saw, with: .color(bright), lineWidth: 1)
            // A lit forge-mouth and a working chimney with a wisp of smoke.
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
        }
    }
}
