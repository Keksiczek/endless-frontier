import SwiftUI
import EndlessFrontierCore

/// The seventeen archetypes added when forty-seven buildings turned out to be
/// sharing eleven shapes.
///
/// Thirty-six of the forty-seven stated no `look` at all, so the renderer
/// *derived* their shape from their numbers — and the numbers cannot tell a
/// farm from a granary from a well, because all three are "food or storage".
/// Thirteen buildings came out as the same lecture hall and nine as the same
/// smoking block. A colony you had built over two hundred years read as four
/// kinds of thing.
///
/// Split out of `SettlementStructures` purely for size: that file was already
/// at the eight-hundred-line mark. The shared surfaces (era materials, the
/// per-building tone jitter, the ground shadow) still live there and are passed
/// in, so a farm and a foundry raised in the same decade are made of the same
/// brick.
enum SettlementTrades {

    /// The colours a building is made of this era, already jittered per
    /// building. Passed as a bundle so a draw call is a draw call and not a
    /// fourteen-argument ritual.
    struct Surfaces {
        let wall: Color
        let roof: Color
        let stone: Color
        let ink: Color
        let bright: Color
        /// A window with somebody behind it, brighter after dark.
        let lit: Color
    }

    static func draw(
        _ glyph: SettlementRenderer.BuildingGlyph, at c: CGPoint, s: CGFloat,
        aspect: CGFloat, time: Double, night: Double, seed: UInt64, era: Era,
        variant: StructureVariant = .plain,
        surfaces f: Surfaces, context: inout GraphicsContext
    ) {
        switch glyph {
        case .tenement: tenement(c, s, aspect, night, seed, f, &context)
        case .farm:     farm(c, s, aspect, time, seed, variant, f, &context)
        case .lodge:    lodge(c, s, aspect, seed, variant, f, &context)
        case .sawmill:  sawmill(c, s, aspect, time, f, &context)
        case .well:     well(c, s, f, &context)
        case .forge:    forge(c, s, aspect, time, night, variant, f, &context)
        case .tanks:    tanks(c, s, aspect, time, variant, f, &context)
        case .rail:     rail(c, s, aspect, f, &context)
        case .lab:      lab(c, s, aspect, night, variant, f, &context)
        case .dish:     dish(c, s, time, f, &context)
        case .vault:    vault(c, s, aspect, f, &context)
        case .clinic:   clinic(c, s, aspect, night, variant, f, &context)
        case .aqueduct: aqueduct(c, s, aspect, f, &context)
        case .wall:     palisade(c, s, aspect, era, seed, variant, f, &context)
        case .barracks: barracks(c, s, aspect, time, f, &context)
        case .turbine:  turbine(c, s, time, f, &context)
        case .dam:      dam(c, s, aspect, time, f, &context)
        default: break
        }
    }

    // MARK: - Where people live

    /// Stacked storeys, a grid of windows and a tank on the roof. The one
    /// building that is allowed to be taller than it is wide.
    /// The walls of a block of flats. Its own proportions, and taller than it
    /// is wide — the one building allowed to be.
    static func tenementBody(_ c: CGPoint, _ s: CGFloat, _ aspect: CGFloat) -> CGRect {
        let w = s * 1.5 * aspect, h = s * 2.1
        return CGRect(x: c.x - w / 2, y: c.y - h * 0.72, width: w, height: h)
    }

    /// Every window in a block of flats, and which of them have somebody up.
    ///
    /// Pure, and the only arithmetic that says where a pane is. It used to be
    /// inline in the drawing, which is why the lamps knew nothing about it:
    /// after dark a six-storey block glowed from one dot at its centre while
    /// twenty-four drawn windows sat there lit and throwing nothing.
    ///
    /// Which are awake is fixed per building — a block does not blink its whole
    /// face every frame.
    static func tenementPanes(
        _ c: CGPoint, _ s: CGFloat, _ aspect: CGFloat, _ seed: UInt64
    ) -> [SettlementStructures.Pane] {
        let body = tenementBody(c, s, aspect)
        let cols = 4, rows = 6
        var h2 = seed | 1
        let cellW = body.width / CGFloat(cols + 1)
        let cellH = body.height / CGFloat(rows + 1)
        var panes: [SettlementStructures.Pane] = []
        for row in 0..<rows {
            for col in 0..<cols {
                h2 ^= h2 >> 33; h2 = h2 &* 0xFF51_AFD7_ED55_8CCD
                panes.append(SettlementStructures.Pane(
                    rect: CGRect(x: body.minX + cellW * (CGFloat(col) + 0.75),
                                 y: body.minY + cellH * (CGFloat(row) + 0.7),
                                 width: cellW * 0.5, height: cellH * 0.44),
                    lit: (h2 >> 30) & 7 > 3))
            }
        }
        return panes
    }

    private static func tenement(
        _ c: CGPoint, _ s: CGFloat, _ aspect: CGFloat, _ night: Double,
        _ seed: UInt64, _ f: Surfaces, _ ctx: inout GraphicsContext
    ) {
        let body = tenementBody(c, s, aspect)
        let w = body.width
        SettlementStructures.groundShadow(at: c, halfWidth: w / 2,
                                          footY: body.maxY + s * 0.06, context: &ctx)
        ctx.fill(Path(body), with: .color(f.wall))
        ctx.stroke(Path(body), with: .color(f.ink), lineWidth: 1)

        // Six floors of windows, from the one place that decides where they
        // are — so the lamps that burn behind them after dark land on the
        // openings rather than at the middle of the block.
        for pane in tenementPanes(c, s, aspect, seed) {
            ctx.fill(Path(pane.rect), with: .color(pane.lit
                ? f.lit.opacity(0.35 + night * 0.5)
                : f.stone.opacity(0.8)))
        }
        // The parapet, and the water tank everybody's plumbing hangs off.
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: body.minX - s * 0.08, y: body.minY))
            p.addLine(to: CGPoint(x: body.maxX + s * 0.08, y: body.minY))
        }, with: .color(f.bright), lineWidth: 1.2)
        let tank = CGRect(x: c.x + w * 0.12, y: body.minY - s * 0.42,
                          width: s * 0.36, height: s * 0.42)
        ctx.fill(Path(tank), with: .color(f.stone))
        ctx.stroke(Path(tank), with: .color(f.ink), lineWidth: 0.7)
    }

    // MARK: - Ground and wood

    /// Furrows, and the barn at the head of them. A farm is mostly *field*,
    /// which is why drawing it as a barrel never read as one.
    /// `farm_basic` and `farm_advanced` share this barn. An advanced farm is
    /// a bigger building with more doors down its side, which is what paying
    /// four times as much for it bought.
    private static func farm(
        _ c: CGPoint, _ s: CGFloat, _ aspect: CGFloat, _ time: Double,
        _ seed: UInt64, _ v: StructureVariant, _ f: Surfaces, _ ctx: inout GraphicsContext
    ) {
        let w = s * (1.8 + CGFloat(v.tier) * 0.12) * aspect
        // **No field is drawn here.** There used to be one: five ruled rows of
        // decorative furrow, identical on every farm, that knew nothing about
        // what was growing. The plots are real now (`Crop`, `FarmEngine`) and
        // `SettlementCrops` draws them where the simulation put them, so a
        // painted field beside them would be the same building's ground stated
        // twice — and the fake one always looked ripe.
        //
        // The barn keeps the top of the lot; `FarmEngine.reconcile` lays the
        // plots out over the rows below it, which is why they are visible at
        // all: laid over the whole footprint they sat under this glyph.
        let barn = CGRect(x: c.x - w * 0.30, y: c.y - s * 0.85, width: w * 0.60, height: s * 0.9)
        SettlementStructures.groundShadow(at: c, halfWidth: barn.width / 2,
                                          footY: barn.maxY + s * 0.05, context: &ctx)
        ctx.fill(Path(barn), with: .color(f.wall))
        let gable = Path { p in
            p.move(to: CGPoint(x: barn.minX - s * 0.1, y: barn.minY))
            p.addLine(to: CGPoint(x: c.x, y: barn.minY - s * 0.55))
            p.addLine(to: CGPoint(x: barn.maxX + s * 0.1, y: barn.minY))
            p.closeSubpath()
        }
        ctx.fill(gable, with: .color(f.roof))
        ctx.stroke(gable, with: .color(f.bright), lineWidth: 1)
        ctx.stroke(Path(barn), with: .color(f.ink), lineWidth: 1)
        let doors = CGRect(x: c.x - barn.width * 0.22, y: barn.midY,
                           width: barn.width * 0.44, height: barn.height * 0.5)
        ctx.fill(Path(doors), with: .color(Theme.ink.opacity(0.55)))
        ctx.stroke(Path(doors), with: .color(f.ink), lineWidth: 0.7)
        // A sheaf or two leaning by the door — different every farm.
        let lean = CGFloat((seed >> 12) % 5) * 0.04 - 0.08
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: barn.maxX + s * 0.16, y: barn.maxY))
            p.addLine(to: CGPoint(x: barn.maxX + s * (0.16 + lean), y: barn.maxY - s * 0.42))
        }, with: .color(Theme.accent.opacity(0.5)), lineWidth: 2)
    }

    /// The hunters': a steep roof to shed snow, racks of hides drying outside,
    /// and antlers over the door.
    /// The hunters' lodge and the stable are one drawing. A stable keeps
    /// animals, so it gets the wide door — `conveyances.json` says which
    /// buildings do, and nothing here has to be listed by hand.
    private static func lodge(
        _ c: CGPoint, _ s: CGFloat, _ aspect: CGFloat, _ seed: UInt64,
        _ v: StructureVariant, _ f: Surfaces, _ ctx: inout GraphicsContext
    ) {
        let w = s * 1.4 * aspect, h = s * 0.85
        let body = CGRect(x: c.x - w / 2, y: c.y - h * 0.3, width: w, height: h)
        defer {
            // Drawn last so it sits on the front wall rather than under it.
            SettlementStructures.frontDoor(
                wide: v.wideDoor, on: body, s: s, at: body.midX,
                ink: f.ink, dark: Theme.boneDim.opacity(0.32), context: &ctx)
        }
        SettlementStructures.groundShadow(at: c, halfWidth: w / 2,
                                          footY: body.maxY + s * 0.06, context: &ctx)
        ctx.fill(Path(body), with: .color(f.wall))
        let roof = Path { p in
            p.move(to: CGPoint(x: body.minX - s * 0.2, y: body.minY + s * 0.06))
            p.addLine(to: CGPoint(x: c.x, y: body.minY - s * 1.05))
            p.addLine(to: CGPoint(x: body.maxX + s * 0.2, y: body.minY + s * 0.06))
            p.closeSubpath()
        }
        ctx.fill(roof, with: .color(f.roof))
        ctx.stroke(roof, with: .color(f.bright), lineWidth: 1.1)
        ctx.stroke(Path(body), with: .color(f.ink), lineWidth: 1)
        // Antlers over the door.
        for side in [-1.0, 1.0] {
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: c.x, y: body.minY - s * 0.18))
                p.addLine(to: CGPoint(x: c.x + CGFloat(side) * s * 0.22, y: body.minY - s * 0.44))
                p.addLine(to: CGPoint(x: c.x + CGFloat(side) * s * 0.34, y: body.minY - s * 0.36))
            }, with: .color(Theme.boneDim.opacity(0.85)), lineWidth: 1)
        }
        // A drying rack with two or three hides on it.
        let rackY = body.maxY - s * 0.05
        let rack = CGRect(x: body.maxX + s * 0.12, y: rackY - s * 0.6,
                          width: s * 0.62, height: s * 0.6)
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: rack.minX, y: rack.maxY))
            p.addLine(to: CGPoint(x: rack.minX, y: rack.minY))
            p.addLine(to: CGPoint(x: rack.maxX, y: rack.minY))
            p.addLine(to: CGPoint(x: rack.maxX, y: rack.maxY))
        }, with: .color(Theme.boneDim.opacity(0.7)), lineWidth: 1)
        for i in 0..<3 where (seed >> UInt64(i * 3)) & 1 == 1 {
            let x = rack.minX + rack.width * (CGFloat(i) + 0.5) / 3
            ctx.fill(Path(CGRect(x: x - s * 0.07, y: rack.minY,
                                 width: s * 0.14, height: s * 0.36)),
                     with: .color(Theme.accent.opacity(0.32)))
        }
    }

    /// A stack of timber taller than the shed it came out of, and the frame saw
    /// that cut it.
    private static func sawmill(
        _ c: CGPoint, _ s: CGFloat, _ aspect: CGFloat, _ time: Double,
        _ f: Surfaces, _ ctx: inout GraphicsContext
    ) {
        let w = s * 1.7 * aspect
        let shed = CGRect(x: c.x - w * 0.5, y: c.y - s * 0.62, width: w * 0.68, height: s * 0.95)
        SettlementStructures.groundShadow(at: c, halfWidth: w * 0.5,
                                          footY: shed.maxY + s * 0.05, context: &ctx)
        // An open-sided shed: posts and a lean-to roof, no front wall.
        ctx.fill(Path(shed), with: .color(f.wall.opacity(0.55)))
        let lean = Path { p in
            p.move(to: CGPoint(x: shed.minX - s * 0.1, y: shed.minY + s * 0.16))
            p.addLine(to: CGPoint(x: shed.maxX + s * 0.1, y: shed.minY - s * 0.3))
            p.addLine(to: CGPoint(x: shed.maxX + s * 0.1, y: shed.minY - s * 0.12))
            p.addLine(to: CGPoint(x: shed.minX - s * 0.1, y: shed.minY + s * 0.34))
            p.closeSubpath()
        }
        ctx.fill(lean, with: .color(f.roof))
        ctx.stroke(lean, with: .color(f.bright), lineWidth: 1)
        for x in [shed.minX, shed.maxX] {
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: x, y: shed.maxY))
                p.addLine(to: CGPoint(x: x, y: shed.minY + s * 0.2))
            }, with: .color(f.ink), lineWidth: 1.2)
        }
        // The blade, turning slowly.
        let r = s * 0.3
        let spin = time * 1.1
        ctx.stroke(Path(ellipseIn: CGRect(x: shed.midX - r, y: shed.midY - r * 0.9,
                                          width: r * 2, height: r * 2)),
                   with: .color(Theme.boneDim.opacity(0.8)), lineWidth: 1)
        for tooth in 0..<8 {
            let a = spin + Double(tooth) * .pi / 4
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: shed.midX + CGFloat(cos(a)) * r * 0.7,
                                   y: shed.midY - r * 0.9 + r + CGFloat(sin(a)) * r * 0.7))
                p.addLine(to: CGPoint(x: shed.midX + CGFloat(cos(a)) * r,
                                      y: shed.midY - r * 0.9 + r + CGFloat(sin(a)) * r))
            }, with: .color(Theme.boneDim.opacity(0.55)), lineWidth: 0.7)
        }
        // The stack: logs end-on, which is what a timber yard looks like.
        let stackX = shed.maxX + s * 0.3
        for row in 0..<3 {
            for col in 0..<(3 - row) {
                let rr = s * 0.13
                let x = stackX + CGFloat(col) * rr * 2.1 + CGFloat(row) * rr
                let y = c.y + s * 0.34 - CGFloat(row) * rr * 1.8
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: rr * 2, height: rr * 2)),
                         with: .color(f.stone))
                ctx.stroke(Path(ellipseIn: CGRect(x: x, y: y, width: rr * 2, height: rr * 2)),
                           with: .color(f.ink), lineWidth: 0.6)
            }
        }
    }

    /// A ring of stones, two posts and a windlass. Small, and it should read as
    /// small — half the point is that the colony's plainest thing is not drawn
    /// as a grain silo.
    private static func well(
        _ c: CGPoint, _ s: CGFloat, _ f: Surfaces, _ ctx: inout GraphicsContext
    ) {
        let r = s * 0.42
        SettlementStructures.groundShadow(at: c, halfWidth: r, footY: c.y + r * 0.7, context: &ctx)
        let ring = CGRect(x: c.x - r, y: c.y - r * 0.55, width: r * 2, height: r * 1.15)
        ctx.fill(Path(ellipseIn: ring), with: .color(f.stone))
        ctx.stroke(Path(ellipseIn: ring), with: .color(f.ink), lineWidth: 1)
        ctx.fill(Path(ellipseIn: ring.insetBy(dx: r * 0.28, dy: r * 0.18)),
                 with: .color(Theme.ink.opacity(0.75)))
        // The frame over it, and a bucket hanging in the middle.
        for side in [-1.0, 1.0] {
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: c.x + CGFloat(side) * r * 0.8, y: c.y - r * 0.2))
                p.addLine(to: CGPoint(x: c.x + CGFloat(side) * r * 0.8, y: c.y - r * 1.5))
            }, with: .color(f.ink), lineWidth: 1.4)
        }
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: c.x - r * 0.95, y: c.y - r * 1.5))
            p.addLine(to: CGPoint(x: c.x + r * 0.95, y: c.y - r * 1.5))
        }, with: .color(f.roof), lineWidth: 2)
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: c.x, y: c.y - r * 1.45))
            p.addLine(to: CGPoint(x: c.x, y: c.y - r * 0.85))
        }, with: .color(Theme.boneDim.opacity(0.7)), lineWidth: 0.7)
        ctx.fill(Path(CGRect(x: c.x - r * 0.16, y: c.y - r * 0.9,
                             width: r * 0.32, height: r * 0.28)),
                 with: .color(f.wall))
    }

    // MARK: - Fire and craft

    /// The hearth that glows. A squat stone hut under a chimney too big for it,
    /// with the door open onto the fire and an anvil in the yard.
    /// The bloomery and the foundry. A foundry is the heavier of the two and
    /// sends up more than a bloomery does.
    private static func forge(
        _ c: CGPoint, _ s: CGFloat, _ aspect: CGFloat, _ time: Double,
        _ night: Double, _ v: StructureVariant, _ f: Surfaces, _ ctx: inout GraphicsContext
    ) {
        let w = s * (1.2 + CGFloat(v.tier) * 0.08) * aspect, h = s * 0.95
        let body = CGRect(x: c.x - w / 2, y: c.y - h * 0.45, width: w, height: h)
        SettlementStructures.groundShadow(at: c, halfWidth: w / 2,
                                          footY: body.maxY + s * 0.06, context: &ctx)
        ctx.fill(Path(body), with: .color(f.stone))
        ctx.stroke(Path(body), with: .color(f.ink), lineWidth: 1)
        // A shallow roof, and the stack.
        let roof = CGRect(x: body.minX - s * 0.12, y: body.minY - s * 0.16,
                          width: body.width + s * 0.24, height: s * 0.2)
        ctx.fill(Path(roof), with: .color(f.roof))
        let stack = CGRect(x: body.minX + w * 0.14, y: body.minY - s * 1.0,
                           width: s * 0.3, height: s * 0.9)
        ctx.fill(Path(stack), with: .color(f.stone))
        ctx.stroke(Path(stack), with: .color(f.ink), lineWidth: 0.8)
        // Heat off the top, and the fire through the door.
        let beat = 0.55 + 0.45 * sin(time * 2.6)
        for i in 0..<3 {
            let t = Double(i) / 3
            let rise = s * CGFloat(0.25 + t * 0.5)
            ctx.fill(Path(ellipseIn: CGRect(x: stack.midX - s * 0.11 - CGFloat(t) * s * 0.06,
                                            y: stack.minY - rise,
                                            width: s * 0.22 + CGFloat(t) * s * 0.14,
                                            height: s * 0.16)),
                     with: .color(Theme.boneDim.opacity(0.16 * (1 - t))))
        }
        let mouth = CGRect(x: c.x + w * 0.06, y: body.midY - s * 0.06,
                           width: w * 0.26, height: h * 0.44)
        ctx.fill(Path(mouth), with: .color(Theme.accent.opacity(0.35 + beat * 0.35 + night * 0.2)))
        ctx.stroke(Path(mouth), with: .color(f.ink), lineWidth: 0.7)
        // The anvil, outside where the light is.
        let anvilY = body.maxY + s * 0.02
        ctx.fill(Path { p in
            p.move(to: CGPoint(x: body.minX - s * 0.42, y: anvilY))
            p.addLine(to: CGPoint(x: body.minX - s * 0.12, y: anvilY))
            p.addLine(to: CGPoint(x: body.minX - s * 0.2, y: anvilY - s * 0.16))
            p.addLine(to: CGPoint(x: body.minX - s * 0.34, y: anvilY - s * 0.16))
            p.closeSubpath()
        }, with: .color(Theme.boneDim.opacity(0.75)))
    }

    /// Cylinders, catwalks, pipework and a flare. Nothing else in the colony
    /// looks like a refinery, which was the trouble: it used to look like a
    /// factory.
    /// The chemical plant and the oil refinery. Both are tank farms; a
    /// refinery is the larger and the smokier.
    private static func tanks(
        _ c: CGPoint, _ s: CGFloat, _ aspect: CGFloat, _ time: Double,
        _ v: StructureVariant, _ f: Surfaces, _ ctx: inout GraphicsContext
    ) {
        let w = s * (1.75 + CGFloat(v.tier) * 0.08) * aspect
        SettlementStructures.groundShadow(at: c, halfWidth: w / 2,
                                          footY: c.y + s * 0.62, context: &ctx)
        let radii: [CGFloat] = [0.42, 0.32, 0.26]
        var x = c.x - w * 0.44
        for (i, rk) in radii.enumerated() {
            let r = s * rk
            let top = c.y + s * 0.55 - r * 2.2
            let barrel = CGRect(x: x, y: top, width: r * 2, height: r * 2.2)
            ctx.fill(Path(barrel), with: .color(f.wall))
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: top - r * 0.28,
                                            width: r * 2, height: r * 0.56)),
                     with: .color(f.stone))
            ctx.stroke(Path(barrel), with: .color(f.ink), lineWidth: 0.9)
            // A band around the middle and a ladder up the side.
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: x, y: barrel.midY))
                p.addLine(to: CGPoint(x: x + r * 2, y: barrel.midY))
            }, with: .color(Theme.boneDim.opacity(0.5)), lineWidth: 0.6)
            if i == 0 {
                for rung in 0..<4 {
                    let y = barrel.minY + barrel.height * (CGFloat(rung) + 0.6) / 4
                    ctx.stroke(Path { p in
                        p.move(to: CGPoint(x: x + r * 1.85, y: y))
                        p.addLine(to: CGPoint(x: x + r * 2.15, y: y))
                    }, with: .color(Theme.boneDim.opacity(0.6)), lineWidth: 0.5)
                }
            }
            x += r * 2 + s * 0.14
        }
        // The pipe run along the front, and the flare at the end.
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: c.x - w * 0.44, y: c.y + s * 0.58))
            p.addLine(to: CGPoint(x: c.x + w * 0.44, y: c.y + s * 0.58))
        }, with: .color(f.stone), lineWidth: 2.2)
        let flareX = c.x + w * 0.44
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: flareX, y: c.y + s * 0.58))
            p.addLine(to: CGPoint(x: flareX, y: c.y - s * 0.95))
        }, with: .color(f.ink), lineWidth: 1.4)
        let flame = 0.5 + 0.5 * sin(time * 5.1)
        ctx.fill(Path { p in
            p.move(to: CGPoint(x: flareX - s * 0.1, y: c.y - s * 0.95))
            p.addLine(to: CGPoint(x: flareX, y: c.y - s * (1.2 + 0.16 * CGFloat(flame))))
            p.addLine(to: CGPoint(x: flareX + s * 0.1, y: c.y - s * 0.95))
            p.closeSubpath()
        }, with: .color(Theme.accent.opacity(0.55 + 0.3 * flame)))
    }

    /// An engine shed with an arched mouth, a water tower beside it, and track
    /// running out of the front.
    private static func rail(
        _ c: CGPoint, _ s: CGFloat, _ aspect: CGFloat,
        _ f: Surfaces, _ ctx: inout GraphicsContext
    ) {
        let w = s * 1.8 * aspect, h = s * 1.15
        let shed = CGRect(x: c.x - w * 0.5, y: c.y - h * 0.55, width: w * 0.78, height: h)
        SettlementStructures.groundShadow(at: c, halfWidth: w / 2,
                                          footY: shed.maxY + s * 0.05, context: &ctx)
        ctx.fill(Path(shed), with: .color(f.wall))
        ctx.stroke(Path(shed), with: .color(f.ink), lineWidth: 1)
        // A shallow vaulted roof.
        let vault = Path { p in
            p.move(to: CGPoint(x: shed.minX - s * 0.1, y: shed.minY))
            p.addQuadCurve(to: CGPoint(x: shed.maxX + s * 0.1, y: shed.minY),
                           control: CGPoint(x: shed.midX, y: shed.minY - s * 0.62))
            p.closeSubpath()
        }
        ctx.fill(vault, with: .color(f.roof))
        ctx.stroke(vault, with: .color(f.bright), lineWidth: 1)
        // The mouth the engines come out of.
        let mouth = Path { p in
            let mw = shed.width * 0.42
            p.move(to: CGPoint(x: shed.midX - mw / 2, y: shed.maxY))
            p.addLine(to: CGPoint(x: shed.midX - mw / 2, y: shed.midY))
            p.addQuadCurve(to: CGPoint(x: shed.midX + mw / 2, y: shed.midY),
                           control: CGPoint(x: shed.midX, y: shed.minY + s * 0.1))
            p.addLine(to: CGPoint(x: shed.midX + mw / 2, y: shed.maxY))
            p.closeSubpath()
        }
        ctx.fill(mouth, with: .color(Theme.ink.opacity(0.7)))
        ctx.stroke(mouth, with: .color(f.ink), lineWidth: 0.8)
        // Sleepers running away from the door.
        for sleeper in 0..<4 {
            let y = shed.maxY + s * (0.08 + CGFloat(sleeper) * 0.13)
            let half = shed.width * 0.2
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: shed.midX - half, y: y))
                p.addLine(to: CGPoint(x: shed.midX + half, y: y))
            }, with: .color(Theme.boneDim.opacity(0.45)), lineWidth: 0.7)
        }
        // The water tower.
        let towerX = shed.maxX + s * 0.36
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: towerX - s * 0.16, y: shed.maxY))
            p.addLine(to: CGPoint(x: towerX - s * 0.1, y: shed.midY - s * 0.1))
            p.move(to: CGPoint(x: towerX + s * 0.16, y: shed.maxY))
            p.addLine(to: CGPoint(x: towerX + s * 0.1, y: shed.midY - s * 0.1))
        }, with: .color(f.ink), lineWidth: 1.2)
        let barrel = CGRect(x: towerX - s * 0.26, y: shed.midY - s * 0.62,
                            width: s * 0.52, height: s * 0.52)
        ctx.fill(Path(barrel), with: .color(f.stone))
        ctx.stroke(Path(barrel), with: .color(f.ink), lineWidth: 0.8)
    }

    // MARK: - Knowing

    /// The clean block: a glass band, a flat roof and the plant on top of it.
    /// `electronics_lab`, `data_center`, `research_campus` and `ai_core` are
    /// all this clean block. `variant` is what keeps four of the most expensive
    /// buildings in the game from being one drawing: how far the glazing runs,
    /// what stands on the roof, and whether there is anyone inside at night —
    /// an `ai_core` is worked by two people and a research campus by six.
    private static func lab(
        _ c: CGPoint, _ s: CGFloat, _ aspect: CGFloat, _ night: Double,
        _ v: StructureVariant, _ f: Surfaces, _ ctx: inout GraphicsContext
    ) {
        let w = s * (1.55 + CGFloat(v.tier) * 0.07) * aspect, h = s * 1.15
        let body = CGRect(x: c.x - w / 2, y: c.y - h * 0.55, width: w, height: h)
        SettlementStructures.groundShadow(at: c, halfWidth: w / 2,
                                          footY: body.maxY + s * 0.05, context: &ctx)
        ctx.fill(Path(roundedRect: body, cornerRadius: s * 0.06), with: .color(f.wall))
        ctx.stroke(Path(roundedRect: body, cornerRadius: s * 0.06),
                   with: .color(f.ink), lineWidth: 1)
        // One long window instead of many small ones — that is what makes it
        // read as modern next to a house full of shutters.
        let band = CGRect(x: body.minX + s * 0.12, y: body.minY + h * 0.22,
                          width: body.width - s * 0.24, height: h * 0.3)
        ctx.fill(Path(band), with: .color(f.lit.opacity(
            (v.nightShift ? 0.3 : 0.12) + night * (v.nightShift ? 0.4 : 0.1))))
        ctx.stroke(Path(band), with: .color(Theme.boneDim.opacity(0.6)), lineWidth: 0.6)
        for mullion in 1..<max(2, v.bays) {
            let x = band.minX + band.width * CGFloat(mullion) / CGFloat(max(2, v.bays))
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: x, y: band.minY))
                p.addLine(to: CGPoint(x: x, y: band.maxY))
            }, with: .color(f.wall), lineWidth: 1)
        }
        // How it is closed off at the top, and what it carries up there.
        SettlementStructures.roofCap(v.roofline, over: body, s: s,
                                     roof: f.roof, ink: f.ink, bright: f.bright, context: &ctx)
        SettlementStructures.roofFurniture(v.rooftop, over: body, s: s,
                                           stone: f.stone, ink: f.ink, bright: f.bright,
                                           lit: f.lit, context: &ctx)
        // Rooftop plant, sized to the building under it.
        let unit = CGRect(x: c.x - w * 0.22, y: body.minY - s * 0.24,
                          width: w * 0.3, height: s * 0.24)
        ctx.fill(Path(unit), with: .color(f.stone))
        ctx.stroke(Path(unit), with: .color(f.ink), lineWidth: 0.7)
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: c.x + w * 0.3, y: body.minY))
            p.addLine(to: CGPoint(x: c.x + w * 0.3, y: body.minY - s * 0.6))
        }, with: .color(Theme.boneDim.opacity(0.7)), lineWidth: 0.8)
    }

    /// A parabolic dish on a mount, with the hut that reads it underneath.
    private static func dish(
        _ c: CGPoint, _ s: CGFloat, _ time: Double,
        _ f: Surfaces, _ ctx: inout GraphicsContext
    ) {
        let hut = CGRect(x: c.x - s * 0.55, y: c.y + s * 0.05, width: s * 1.1, height: s * 0.55)
        SettlementStructures.groundShadow(at: c, halfWidth: s * 0.6,
                                          footY: hut.maxY + s * 0.04, context: &ctx)
        ctx.fill(Path(hut), with: .color(f.wall))
        ctx.stroke(Path(hut), with: .color(f.ink), lineWidth: 1)
        // The dish, drifting slowly across the sky as it tracks.
        let tilt = CGFloat(sin(time * 0.18)) * 0.22
        let cx = c.x + tilt * s * 0.5
        let top = c.y - s * 0.95
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: c.x, y: hut.minY))
            p.addLine(to: CGPoint(x: cx, y: top + s * 0.42))
        }, with: .color(f.ink), lineWidth: 1.6)
        let bowl = Path { p in
            p.move(to: CGPoint(x: cx - s * 0.62, y: top + s * 0.1))
            p.addQuadCurve(to: CGPoint(x: cx + s * 0.62, y: top + s * 0.1),
                           control: CGPoint(x: cx, y: top + s * 0.86))
            p.addQuadCurve(to: CGPoint(x: cx - s * 0.62, y: top + s * 0.1),
                           control: CGPoint(x: cx, y: top - s * 0.16))
            p.closeSubpath()
        }
        ctx.fill(bowl, with: .color(f.stone))
        ctx.stroke(bowl, with: .color(f.bright), lineWidth: 1)
        // The feed at the focus.
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: cx, y: top + s * 0.5))
            p.addLine(to: CGPoint(x: cx, y: top - s * 0.02))
        }, with: .color(Theme.boneDim.opacity(0.8)), lineWidth: 0.8)
        ctx.fill(Path(ellipseIn: CGRect(x: cx - s * 0.07, y: top - s * 0.09,
                                        width: s * 0.14, height: s * 0.14)),
                 with: .color(Theme.accent.opacity(0.6)))
    }

    // MARK: - Trade, rule and care

    /// The bank: a squat strongbox of a building. Columns, a step up to it, and
    /// a door with a wheel on it.
    private static func vault(
        _ c: CGPoint, _ s: CGFloat, _ aspect: CGFloat,
        _ f: Surfaces, _ ctx: inout GraphicsContext
    ) {
        let w = s * 1.55 * aspect, h = s * 1.0
        let body = CGRect(x: c.x - w / 2, y: c.y - h * 0.55, width: w, height: h)
        SettlementStructures.groundShadow(at: c, halfWidth: w / 2,
                                          footY: body.maxY + s * 0.05, context: &ctx)
        ctx.fill(Path(body), with: .color(f.stone))
        ctx.stroke(Path(body), with: .color(f.ink), lineWidth: 1.2)
        // A heavy cornice and a pediment: the architecture of not losing money.
        let cornice = CGRect(x: body.minX - s * 0.14, y: body.minY - s * 0.14,
                             width: body.width + s * 0.28, height: s * 0.16)
        ctx.fill(Path(cornice), with: .color(f.roof))
        let pediment = Path { p in
            p.move(to: CGPoint(x: cornice.minX, y: cornice.minY))
            p.addLine(to: CGPoint(x: c.x, y: cornice.minY - s * 0.4))
            p.addLine(to: CGPoint(x: cornice.maxX, y: cornice.minY))
            p.closeSubpath()
        }
        ctx.fill(pediment, with: .color(f.roof))
        ctx.stroke(pediment, with: .color(f.bright), lineWidth: 1)
        // Columns.
        for i in 0..<4 {
            let x = body.minX + body.width * (CGFloat(i) + 0.5) / 4
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: x, y: body.maxY - s * 0.06))
                p.addLine(to: CGPoint(x: x, y: body.minY + s * 0.06))
            }, with: .color(f.wall), lineWidth: max(1.4, s * 0.11))
        }
        // The door, and the wheel on it.
        let door = CGRect(x: c.x - s * 0.2, y: body.midY - s * 0.02,
                          width: s * 0.4, height: body.maxY - body.midY + s * 0.02)
        ctx.fill(Path(door), with: .color(Theme.ink.opacity(0.6)))
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - s * 0.11, y: door.minY + s * 0.06,
                                          width: s * 0.22, height: s * 0.22)),
                   with: .color(Theme.accent.opacity(0.65)), lineWidth: 1)
    }

    /// Pale walls, a cross, and a lamp that stays lit all night.
    /// The clinic and the hospital. A hospital is a hospital-sized building
    /// with a hospital's windows lit all night; a village clinic is not.
    private static func clinic(
        _ c: CGPoint, _ s: CGFloat, _ aspect: CGFloat, _ night: Double,
        _ v: StructureVariant, _ f: Surfaces, _ ctx: inout GraphicsContext
    ) {
        let w = s * (1.5 + CGFloat(v.tier) * 0.1) * aspect, h = s * 1.05
        let body = CGRect(x: c.x - w / 2, y: c.y - h * 0.55, width: w, height: h)
        SettlementStructures.groundShadow(at: c, halfWidth: w / 2,
                                          footY: body.maxY + s * 0.05, context: &ctx)
        // Deliberately the palest thing in the colony.
        ctx.fill(Path(body), with: .color(Theme.bone.opacity(0.24)))
        ctx.fill(Path(body), with: .color(f.wall.opacity(0.55)))
        ctx.stroke(Path(body), with: .color(f.ink), lineWidth: 1)
        let roof = CGRect(x: body.minX - s * 0.1, y: body.minY - s * 0.16,
                          width: body.width + s * 0.2, height: s * 0.18)
        ctx.fill(Path(roof), with: .color(f.roof))
        // The cross.
        let arm = s * 0.11, span = s * 0.34
        ctx.fill(Path(CGRect(x: c.x - arm / 2, y: body.minY + s * 0.12,
                             width: arm, height: span)), with: .color(Theme.danger.opacity(0.8)))
        ctx.fill(Path(CGRect(x: c.x - span / 2, y: body.minY + s * 0.12 + span / 2 - arm / 2,
                             width: span, height: arm)), with: .color(Theme.danger.opacity(0.8)))
        // An awning over the door, and the lamp under it.
        let awning = Path { p in
            p.move(to: CGPoint(x: c.x - s * 0.42, y: body.maxY - s * 0.34))
            p.addLine(to: CGPoint(x: c.x + s * 0.42, y: body.maxY - s * 0.34))
            p.addLine(to: CGPoint(x: c.x + s * 0.3, y: body.maxY - s * 0.5))
            p.addLine(to: CGPoint(x: c.x - s * 0.3, y: body.maxY - s * 0.5))
            p.closeSubpath()
        }
        ctx.fill(awning, with: .color(f.stone))
        ctx.stroke(awning, with: .color(f.ink), lineWidth: 0.6)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.07, y: body.maxY - s * 0.32,
                                        width: s * 0.14, height: s * 0.14)),
                 with: .color(Theme.accent.opacity(0.5 + night * 0.45)))
    }

    /// A run of arches carrying a channel. The only building in the colony that
    /// is longer than it is anything else.
    private static func aqueduct(
        _ c: CGPoint, _ s: CGFloat, _ aspect: CGFloat,
        _ f: Surfaces, _ ctx: inout GraphicsContext
    ) {
        let w = s * 2.3 * aspect
        let deck = CGRect(x: c.x - w / 2, y: c.y - s * 0.62, width: w, height: s * 0.22)
        SettlementStructures.groundShadow(at: c, halfWidth: w / 2,
                                          footY: c.y + s * 0.5, context: &ctx)
        let piers = 4
        let bay = w / CGFloat(piers)
        for i in 0..<piers {
            let x = deck.minX + bay * CGFloat(i)
            let arch = Path { p in
                p.move(to: CGPoint(x: x + bay * 0.12, y: c.y + s * 0.48))
                p.addLine(to: CGPoint(x: x + bay * 0.12, y: deck.maxY + bay * 0.22))
                p.addQuadCurve(to: CGPoint(x: x + bay * 0.88, y: deck.maxY + bay * 0.22),
                               control: CGPoint(x: x + bay * 0.5, y: deck.maxY - bay * 0.14))
                p.addLine(to: CGPoint(x: x + bay * 0.88, y: c.y + s * 0.48))
                p.addLine(to: CGPoint(x: x + bay, y: c.y + s * 0.48))
                p.addLine(to: CGPoint(x: x + bay, y: deck.maxY))
                p.addLine(to: CGPoint(x: x, y: deck.maxY))
                p.addLine(to: CGPoint(x: x, y: c.y + s * 0.48))
                p.closeSubpath()
            }
            ctx.fill(arch, with: .color(f.stone))
            ctx.stroke(arch, with: .color(f.ink), lineWidth: 0.8)
        }
        ctx.fill(Path(deck), with: .color(f.wall))
        ctx.stroke(Path(deck), with: .color(f.bright), lineWidth: 1)
        // The water it carries, which is the whole point of it.
        ctx.fill(Path(CGRect(x: deck.minX + s * 0.06, y: deck.minY + s * 0.04,
                             width: deck.width - s * 0.12, height: s * 0.07)),
                 with: .color(Theme.accent.opacity(0.35)))
    }

    // MARK: - Holding the line

    /// A run of wall rather than a tower: stakes while it is timber,
    /// crenellations once it is cut stone.
    /// A line of stakes and a stone rampart are the same run of wall at two
    /// weights. `heft` comes off `defense`, so the drawing and the number a
    /// raid is resolved against cannot drift apart.
    private static func palisade(
        _ c: CGPoint, _ s: CGFloat, _ aspect: CGFloat, _ era: Era, _ seed: UInt64,
        _ v: StructureVariant, _ f: Surfaces, _ ctx: inout GraphicsContext
    ) {
        let w = s * (2.05 + CGFloat(v.heft) * 0.08) * aspect
        let masonry = era != .earlySettlement
        SettlementStructures.groundShadow(at: c, halfWidth: w / 2,
                                          footY: c.y + s * 0.5, context: &ctx)
        guard masonry else {
            // A row of sharpened stakes, each leaning its own way.
            var h2 = seed | 1
            let count = 9
            for i in 0..<count {
                h2 ^= h2 >> 33; h2 = h2 &* 0xFF51_AFD7_ED55_8CCD
                let lean = CGFloat(Double((h2 >> 40) & 0xFF) / 255 - 0.5) * s * 0.09
                let x = c.x - w / 2 + w * (CGFloat(i) + 0.5) / CGFloat(count)
                let top = c.y - s * (0.62 + CGFloat((h2 >> 20) & 7) * 0.03)
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: c.y + s * 0.45))
                    p.addLine(to: CGPoint(x: x + lean, y: top))
                }, with: .color(f.wall), lineWidth: max(1.6, s * 0.15))
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: x + lean - s * 0.06, y: top + s * 0.09))
                    p.addLine(to: CGPoint(x: x + lean, y: top))
                    p.addLine(to: CGPoint(x: x + lean + s * 0.06, y: top + s * 0.09))
                }, with: .color(f.bright), lineWidth: 0.7)
            }
            // The rail that ties them together.
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - w / 2, y: c.y - s * 0.12))
                p.addLine(to: CGPoint(x: c.x + w / 2, y: c.y - s * 0.16))
            }, with: .color(f.roof), lineWidth: 1.6)
            return
        }
        let body = CGRect(x: c.x - w / 2, y: c.y - s * 0.55, width: w, height: s * 1.0)
        ctx.fill(Path(body), with: .color(f.stone))
        ctx.stroke(Path(body), with: .color(f.ink), lineWidth: 1)
        // Courses, and the merlons along the top.
        for course in 1..<3 {
            let y = body.minY + body.height * CGFloat(course) / 3
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: body.minX, y: y))
                p.addLine(to: CGPoint(x: body.maxX, y: y))
            }, with: .color(Theme.boneDim.opacity(0.28)), lineWidth: 0.5)
        }
        let merlons = 6
        for i in 0..<merlons where i % 2 == 0 {
            let mw = body.width / CGFloat(merlons)
            ctx.fill(Path(CGRect(x: body.minX + mw * CGFloat(i), y: body.minY - s * 0.2,
                                 width: mw, height: s * 0.2)), with: .color(f.stone))
        }
    }

    /// Long, low, and under a banner. Everything about it says *quarters*.
    private static func barracks(
        _ c: CGPoint, _ s: CGFloat, _ aspect: CGFloat, _ time: Double,
        _ f: Surfaces, _ ctx: inout GraphicsContext
    ) {
        let w = s * 2.0 * aspect, h = s * 0.9
        let body = CGRect(x: c.x - w / 2, y: c.y - h * 0.5, width: w, height: h)
        SettlementStructures.groundShadow(at: c, halfWidth: w / 2,
                                          footY: body.maxY + s * 0.05, context: &ctx)
        ctx.fill(Path(body), with: .color(f.wall))
        let roof = Path { p in
            p.move(to: CGPoint(x: body.minX - s * 0.12, y: body.minY))
            p.addLine(to: CGPoint(x: body.minX + s * 0.24, y: body.minY - s * 0.42))
            p.addLine(to: CGPoint(x: body.maxX - s * 0.24, y: body.minY - s * 0.42))
            p.addLine(to: CGPoint(x: body.maxX + s * 0.12, y: body.minY))
            p.closeSubpath()
        }
        ctx.fill(roof, with: .color(f.roof))
        ctx.stroke(roof, with: .color(f.bright), lineWidth: 1)
        ctx.stroke(Path(body), with: .color(f.ink), lineWidth: 1)
        // A file of identical small windows — the giveaway.
        for i in 0..<5 {
            let x = body.minX + body.width * (CGFloat(i) + 0.5) / 5
            ctx.fill(Path(CGRect(x: x - s * 0.07, y: body.midY - s * 0.14,
                                 width: s * 0.14, height: s * 0.22)),
                     with: .color(Theme.ink.opacity(0.55)))
        }
        // The banner, moving in whatever wind there is.
        let poleX = body.maxX + s * 0.26
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: poleX, y: body.maxY))
            p.addLine(to: CGPoint(x: poleX, y: body.minY - s * 0.9))
        }, with: .color(f.ink), lineWidth: 1.2)
        let flap = CGFloat(sin(time * 1.9)) * s * 0.07
        ctx.fill(Path { p in
            p.move(to: CGPoint(x: poleX, y: body.minY - s * 0.86))
            p.addLine(to: CGPoint(x: poleX + s * 0.44 + flap, y: body.minY - s * 0.74))
            p.addLine(to: CGPoint(x: poleX + s * 0.4, y: body.minY - s * 0.44))
            p.addLine(to: CGPoint(x: poleX, y: body.minY - s * 0.5))
            p.closeSubpath()
        }, with: .color(Theme.danger.opacity(0.55)))
        // A rack of spears leaning by the door.
        for i in 0..<3 {
            let x = body.minX - s * 0.3 + CGFloat(i) * s * 0.09
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: x, y: body.maxY))
                p.addLine(to: CGPoint(x: x + s * 0.12, y: body.minY - s * 0.1))
            }, with: .color(Theme.boneDim.opacity(0.7)), lineWidth: 0.8)
        }
    }

    // MARK: - Power

    /// Three blades on a tall mast, turning. Nothing else in the colony is that
    /// shape, which is exactly why the wind farm needed its own.
    private static func turbine(
        _ c: CGPoint, _ s: CGFloat, _ time: Double,
        _ f: Surfaces, _ ctx: inout GraphicsContext
    ) {
        let footY = c.y + s * 0.7
        SettlementStructures.groundShadow(at: c, halfWidth: s * 0.3, footY: footY, context: &ctx)
        let hub = CGPoint(x: c.x, y: c.y - s * 1.15)
        ctx.fill(Path { p in
            p.move(to: CGPoint(x: c.x - s * 0.14, y: footY))
            p.addLine(to: CGPoint(x: c.x - s * 0.05, y: hub.y))
            p.addLine(to: CGPoint(x: c.x + s * 0.05, y: hub.y))
            p.addLine(to: CGPoint(x: c.x + s * 0.14, y: footY))
            p.closeSubpath()
        }, with: .color(f.wall))
        let spin = time * 0.9
        for blade in 0..<3 {
            let a = spin + Double(blade) * 2 * .pi / 3
            let tip = CGPoint(x: hub.x + CGFloat(cos(a)) * s * 0.95,
                              y: hub.y + CGFloat(sin(a)) * s * 0.95)
            let side = CGPoint(x: hub.x + CGFloat(cos(a + 0.35)) * s * 0.22,
                               y: hub.y + CGFloat(sin(a + 0.35)) * s * 0.22)
            ctx.fill(Path { p in
                p.move(to: hub)
                p.addLine(to: side)
                p.addLine(to: tip)
                p.closeSubpath()
            }, with: .color(f.bright.opacity(0.85)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: hub.x - s * 0.1, y: hub.y - s * 0.1,
                                        width: s * 0.2, height: s * 0.2)),
                 with: .color(f.stone))
    }

    /// A curved wall with water piled behind it and white water below.
    private static func dam(
        _ c: CGPoint, _ s: CGFloat, _ aspect: CGFloat, _ time: Double,
        _ f: Surfaces, _ ctx: inout GraphicsContext
    ) {
        let w = s * 2.2 * aspect
        SettlementStructures.groundShadow(at: c, halfWidth: w / 2,
                                          footY: c.y + s * 0.6, context: &ctx)
        // The reservoir, held above.
        let lake = Path { p in
            p.move(to: CGPoint(x: c.x - w / 2, y: c.y - s * 0.95))
            p.addLine(to: CGPoint(x: c.x + w / 2, y: c.y - s * 0.95))
            p.addQuadCurve(to: CGPoint(x: c.x - w / 2, y: c.y - s * 0.95),
                           control: CGPoint(x: c.x, y: c.y - s * 0.05))
            p.closeSubpath()
        }
        ctx.fill(lake, with: .color(Theme.accent.opacity(0.22)))
        // The wall itself, bowed upstream.
        let wall = Path { p in
            p.move(to: CGPoint(x: c.x - w / 2, y: c.y - s * 0.55))
            p.addQuadCurve(to: CGPoint(x: c.x + w / 2, y: c.y - s * 0.55),
                           control: CGPoint(x: c.x, y: c.y - s * 0.15))
            p.addLine(to: CGPoint(x: c.x + w * 0.42, y: c.y + s * 0.5))
            p.addLine(to: CGPoint(x: c.x - w * 0.42, y: c.y + s * 0.5))
            p.closeSubpath()
        }
        ctx.fill(wall, with: .color(f.stone))
        ctx.stroke(wall, with: .color(f.ink), lineWidth: 1.1)
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: c.x - w / 2, y: c.y - s * 0.55))
            p.addQuadCurve(to: CGPoint(x: c.x + w / 2, y: c.y - s * 0.55),
                           control: CGPoint(x: c.x, y: c.y - s * 0.15))
        }, with: .color(f.bright), lineWidth: 1.2)
        // The spillway, and the white water at the foot of it.
        let gate = CGRect(x: c.x - s * 0.2, y: c.y - s * 0.4, width: s * 0.4, height: s * 0.9)
        ctx.fill(Path(gate), with: .color(Theme.accent.opacity(0.4)))
        for i in 0..<4 {
            let phase = time * 2.4 + Double(i)
            let r = s * (0.06 + 0.04 * CGFloat(0.5 + 0.5 * sin(phase)))
            ctx.fill(Path(ellipseIn: CGRect(
                x: c.x - s * 0.24 + CGFloat(i) * s * 0.14, y: c.y + s * 0.42, width: r * 2, height: r * 1.4)),
                     with: .color(Theme.bone.opacity(0.3)))
        }
    }
}
