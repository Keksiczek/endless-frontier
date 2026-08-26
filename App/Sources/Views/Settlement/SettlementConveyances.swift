import SwiftUI
import EndlessFrontierCore

/// Draws whatever the colony moves things with — a travois, a pack elk, a hand
/// cart, and every wagon, locomotive, truck and lifter that comes after.
///
/// **Composed, not drawn.** There will be sixty of these across six eras, and
/// sixty hand-drawn vehicles is not a plan: it is the building bank's problem
/// again one layer up, where nineteen buildings already share four pictures. So
/// a conveyance is assembled from four questions its definition already
/// answers — what carries it, what draws it, what it holds, how it is covered —
/// plus the era's materials and its own seed. Two carts of the same class in
/// the same era differ; a cart and a wagon differ a great deal; and a
/// conveyance generated next month arrives already drawn.
///
/// Presentation only: nothing here writes `WorldState`, and who is riding is
/// `StableEngine.assignRiders`'s answer, read off `Conveyance.riderID`.
enum SettlementConveyances {

    // MARK: - What one is made of

    /// How the load is held off the ground.
    enum Undercarriage: Equatable {
        /// Poles dragged behind — a travois, a sledge. No wheel at all.
        case skids
        /// Wheels, and how many.
        case wheels(Int)
        /// A hull that floats.
        case hull
        /// Nothing touches the ground.
        case none
    }

    /// What is over the load.
    enum Cover: Equatable {
        case open
        /// Hoops and a cloth tilt — the covered wagon.
        case tilt
        /// A closed box: a van, a boxcar, a container.
        case box
        /// Glass and panel — a cab somebody sits in.
        case glazed
    }

    /// What makes it go.
    enum Draught: Equatable {
        /// Shafts a person pulls between.
        case shafts
        /// The beast itself is the conveyance.
        case beast
        /// A boiler and a stack.
        case boiler
        /// A block, and a bonnet over it.
        case engine
        /// Blades, or a gasbag.
        case lift
    }

    /// One conveyance, as a set of parts to draw. Everything here is derived —
    /// never stored, never authored per vehicle.
    struct Build {
        var undercarriage: Undercarriage
        var cover: Cover
        var draught: Draught
        /// How long the load bed is, in body widths.
        var bed: CGFloat
        /// …and how deep.
        var depth: CGFloat
        /// Wheel radius as a fraction of the bed's depth.
        var wheel: CGFloat
        /// How high the whole thing stands off the ground.
        var lift: CGFloat
    }

    /// The parts one definition is made of.
    ///
    /// Read off the fields that already exist and already mean something —
    /// `cargo` is how much it holds, so it sets the bed; `pace` is how fast it
    /// goes, so it sets the wheel; `era` sets what it is made of. Nothing here
    /// needs a new field in `conveyances.json`, which is what keeps step 7 a
    /// generation job rather than a drawing job.
    static func build(_ def: ConveyanceDefinition, seed: UInt64) -> Build {
        let jitter = { (n: UInt64, spread: CGFloat) -> CGFloat in
            CGFloat(Double((seed &* 0x9E37_79B9_7F4A_7C15 &+ n) >> 41 & 0x3FF) / 1023 - 0.5)
                * spread
        }
        let cargo = CGFloat(max(0, def.cargo))
        let pace = CGFloat(max(0.2, def.pace))
        // A bed grows with what it holds, and stops growing: a lifter that
        // carries forty is not forty times a handcart on the screen.
        //
        // **In body heights**, which is the unit everything else here is in —
        // `wheel` is written against "a dray rolls on something the height of a
        // person" and `s` is the figure's height. The bed was not: at
        // `0.7 + √cargo × 0.42` a three-sack travois came out **1.4 times a
        // person's height wide**, which against a body about a quarter of its
        // height across is a cart five times wider than the man pulling it.
        // Keks, with a screenshot: *"nese dost velký náklad, zda ok."* It was
        // not. A handcart is about half a person's height across; a great
        // wagon is wider than a person is tall, and nothing is wider than that.
        let bed = 0.30 + sqrt(cargo) * 0.13 + jitter(1, 0.05)
        let depth = 0.16 + sqrt(cargo) * 0.035 + jitter(2, 0.02)

        switch def.kind {
        case .mount:
            return Build(undercarriage: .none, cover: .open, draught: .beast,
                         bed: 0.55, depth: 0.18, wheel: 0, lift: 0.55 + jitter(3, 0.08))
        case .cart:
            // The one real fork inside a class: something with no wheel at all
            // is dragged, and that is the whole of what a travois is. Wheels
            // arrive with load, and a fifth and sixth with a great deal of it.
            let axles = cargo <= 3 ? 0 : (cargo <= 6 ? 2 : (cargo <= 12 ? 4 : 6))
            let hauled = def.requiresAnimal != nil
            return Build(
                undercarriage: axles == 0 ? .skids : .wheels(axles),
                cover: cover(for: def, cargo: cargo, seed: seed),
                draught: hauled ? .beast : .shafts,
                bed: bed, depth: depth,
                // A big wheel is a fast wheel, which is true of carts and reads
                // instantly: a dray rolls on something the height of a person.
                wheel: 0.5 + pace * 0.22 + jitter(4, 0.08),
                lift: axles == 0 ? 0.1 : 0.24 + jitter(5, 0.05))
        case .rail:
            return Build(
                undercarriage: .wheels(cargo <= 8 ? 4 : 6),
                cover: def.riders > 0 ? .glazed : .box,
                draught: def.era.index <= Era.earlyIndustrial.index ? .boiler : .engine,
                bed: bed + 0.5, depth: depth + 0.1,
                wheel: 0.42 + jitter(6, 0.06), lift: 0.3)
        case .motor:
            return Build(
                undercarriage: .wheels(cargo <= 6 ? 4 : 6),
                cover: def.riders > 1 ? .glazed : cover(for: def, cargo: cargo, seed: seed),
                draught: .engine,
                bed: bed, depth: depth,
                wheel: 0.36 + pace * 0.06 + jitter(7, 0.05),
                lift: 0.26 + jitter(8, 0.05))
        case .air:
            return Build(
                undercarriage: .none, cover: cargo >= 8 ? .box : .glazed,
                draught: .lift, bed: bed, depth: depth + 0.12,
                wheel: 0, lift: 1.1 + jitter(9, 0.2))
        }
    }

    /// What is over the load. Cloth before the machine age, a closed box after
    /// it, and open whenever the thing is small enough not to need one.
    private static func cover(
        for def: ConveyanceDefinition, cargo: CGFloat, seed: UInt64
    ) -> Cover {
        guard cargo >= 4 else { return .open }
        if def.era.index >= Era.modern.index { return .box }
        if def.era.index >= Era.medieval.index {
            // Half the wagons of an age have their tilt up. The seed decides,
            // so the same wagon is the same wagon every frame.
            return (seed >> 17) & 1 == 0 ? .tilt : .open
        }
        return .open
    }

    // MARK: - Drawing one

    /// Draws a conveyance standing on the ground at `anchor`, facing `facing`
    /// (−1 left, +1 right). `s` is the same body scale a colonist is drawn at,
    /// so a cart is a cart *beside a person* rather than beside the buildings.
    static func draw(
        _ def: ConveyanceDefinition, thing: Conveyance, at anchor: CGPoint,
        s: CGFloat, facing: CGFloat, time: Double, loaded: Bool,
        beast: AnimalDefinition.Build? = nil,
        context ctx: inout GraphicsContext
    ) {
        let seed = hash(thing.id)
        let parts = build(def, seed: seed)
        let mirror: CGFloat = facing < 0 ? -1 : 1
        let material = SettlementStructures.materials(def.era)
        let body = SettlementStructures.tone(material.wall, seed, spread: 0.06)
        let trim = SettlementStructures.tone(material.stone, seed &* 3, spread: 0.05)
        // A worn cart is drawn thinner and greyer, the same way a building in
        // poor condition is. A mount reads its beast's health instead, which is
        // already drawn by `SettlementWildlife`.
        let soundness = thing.isMount ? 1 : max(0.25, CGFloat(thing.condition))
        let line = max(0.55, s * 0.055 * soundness)

        let bedWidth = parts.bed * s
        let bedDepth = parts.depth * s
        let wheelR = parts.wheel * s * 0.5
        let groundY = anchor.y
        let bedY = groundY - parts.lift * s - bedDepth

        SettlementStructures.groundShadow(
            at: CGPoint(x: anchor.x, y: groundY), halfWidth: bedWidth * 0.5,
            footY: groundY, context: &ctx)

        // What holds it up.
        switch parts.undercarriage {
        case .skids:
            // Two poles from the shoulder to the ground behind — the load rides
            // between them, and one end of it drags. Drawn as the two poles,
            // because that is the whole machine.
            for offset in [CGFloat(-0.12), 0.12] {
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: anchor.x + mirror * bedWidth * 0.62,
                                       y: groundY - s * 0.75 + offset * s))
                    p.addLine(to: CGPoint(x: anchor.x - mirror * bedWidth * 0.55,
                                          y: groundY + offset * s * 0.3))
                }, with: .color(body), lineWidth: line * 1.8)
            }
        case let .wheels(count):
            let axles = max(1, count / 2)
            for axle in 0..<axles {
                let t = axles == 1 ? 0.5 : CGFloat(axle) / CGFloat(axles - 1)
                let x = anchor.x - bedWidth * 0.42 + bedWidth * 0.84 * t
                wheel(at: CGPoint(x: x, y: groundY - wheelR), r: wheelR,
                      spokes: def.era.index >= Era.modern.index ? 0 : 6,
                      rolling: loaded ? time : 0, colour: trim, ink: body,
                      line: line, ctx: &ctx)
            }
        case .hull, .none:
            break
        }

        // The load bed itself — every class has one except a mount, which
        // carries on its own back.
        if parts.draught != .beast || def.kind != .mount {
            let rect = CGRect(x: anchor.x - bedWidth * 0.5, y: bedY,
                              width: bedWidth, height: bedDepth)
            ctx.fill(Path(roundedRect: rect, cornerRadius: bedDepth * 0.18),
                     with: .color(body))
            ctx.stroke(Path(roundedRect: rect, cornerRadius: bedDepth * 0.18),
                       with: .color(Theme.ink.opacity(0.7)), lineWidth: line)
            // Planking: three strakes, so a bed reads as boards and not a bar.
            for k in 1...2 {
                let y = rect.minY + rect.height * CGFloat(k) / 3
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: rect.minX + line, y: y))
                    p.addLine(to: CGPoint(x: rect.maxX - line, y: y))
                }, with: .color(Theme.ink.opacity(0.25)), lineWidth: line * 0.6)
            }
            cover(parts.cover, over: rect, body: body, trim: trim,
                  line: line, seed: seed, ctx: &ctx)
            if loaded { cargoOnTop(rect, cover: parts.cover, seed: seed, line: line, ctx: &ctx) }
        }

        // …and what makes it go.
        draught(parts, def: def, anchor: anchor, bed: CGRect(
                    x: anchor.x - bedWidth * 0.5, y: bedY,
                    width: bedWidth, height: bedDepth),
                s: s, mirror: mirror, time: time, body: body, trim: trim,
                line: line, beast: beast, seed: seed, ctx: &ctx)
    }

    // MARK: - The parts

    private static func wheel(
        at c: CGPoint, r: CGFloat, spokes: Int, rolling: Double,
        colour: Color, ink: Color, line: CGFloat, ctx: inout GraphicsContext
    ) {
        let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect), with: .color(Theme.ink.opacity(0.55)))
        ctx.stroke(Path(ellipseIn: rect), with: .color(colour), lineWidth: line * 1.4)
        guard spokes > 0 else {
            // A modern wheel is a tyre with a hub, not a wheelwright's wheel.
            ctx.fill(Path(ellipseIn: rect.insetBy(dx: r * 0.55, dy: r * 0.55)),
                     with: .color(ink))
            return
        }
        for k in 0..<spokes {
            let a = rolling * 1.4 + Double(k) * .pi * 2 / Double(spokes)
            ctx.stroke(Path { p in
                p.move(to: c)
                p.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * r * 0.92,
                                      y: c.y + CGFloat(sin(a)) * r * 0.92))
            }, with: .color(colour.opacity(0.8)), lineWidth: line * 0.7)
        }
    }

    private static func cover(
        _ cover: Cover, over bed: CGRect, body: Color, trim: Color,
        line: CGFloat, seed: UInt64, ctx: inout GraphicsContext
    ) {
        switch cover {
        case .open:
            return
        case .tilt:
            // Hoops and cloth: an arc over the bed, and the ribs showing
            // through it. The silhouette every covered wagon is known by.
            let h = bed.height * 2.1
            let tilt = Path { p in
                p.move(to: CGPoint(x: bed.minX, y: bed.minY))
                p.addQuadCurve(to: CGPoint(x: bed.maxX, y: bed.minY),
                               control: CGPoint(x: bed.midX, y: bed.minY - h * 1.5))
            }
            ctx.fill(tilt, with: .color(Color(red: 0.72, green: 0.69, blue: 0.61).opacity(0.75)))
            ctx.stroke(tilt, with: .color(Theme.ink.opacity(0.6)), lineWidth: line)
            for k in 1...3 {
                let t = CGFloat(k) / 4
                let x = bed.minX + bed.width * t
                let rise = h * 1.15 * (1 - abs(t - 0.5) * 1.2)
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: bed.minY))
                    p.addLine(to: CGPoint(x: x, y: bed.minY - rise))
                }, with: .color(Theme.ink.opacity(0.3)), lineWidth: line * 0.6)
            }
        case .box:
            let box = CGRect(x: bed.minX, y: bed.minY - bed.height * 1.6,
                             width: bed.width, height: bed.height * 1.6)
            ctx.fill(Path(roundedRect: box, cornerRadius: bed.height * 0.12),
                     with: .color(body.opacity(0.95)))
            ctx.stroke(Path(roundedRect: box, cornerRadius: bed.height * 0.12),
                       with: .color(Theme.ink.opacity(0.65)), lineWidth: line)
            // A seam down it, placed off the seed, so a row of containers is
            // not a row of one container.
            let t = CGFloat((seed >> 23) % 5) / 6 + 0.2
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: box.minX + box.width * t, y: box.minY + line))
                p.addLine(to: CGPoint(x: box.minX + box.width * t, y: box.maxY - line))
            }, with: .color(Theme.ink.opacity(0.35)), lineWidth: line * 0.7)
        case .glazed:
            let cab = CGRect(x: bed.minX + bed.width * 0.08,
                             y: bed.minY - bed.height * 1.35,
                             width: bed.width * 0.5, height: bed.height * 1.35)
            ctx.fill(Path(roundedRect: cab, cornerRadius: bed.height * 0.2),
                     with: .color(trim))
            ctx.stroke(Path(roundedRect: cab, cornerRadius: bed.height * 0.2),
                       with: .color(Theme.ink.opacity(0.6)), lineWidth: line)
            ctx.fill(Path(roundedRect: cab.insetBy(dx: cab.width * 0.16,
                                                   dy: cab.height * 0.24),
                          cornerRadius: bed.height * 0.1),
                     with: .color(Theme.accent.opacity(0.28)))
        }
    }

    /// What is riding in it, when it is loaded — sacks and crates, drawn small
    /// enough to read as goods rather than as more vehicle.
    private static func cargoOnTop(
        _ bed: CGRect, cover: Cover, seed: UInt64, line: CGFloat,
        ctx: inout GraphicsContext
    ) {
        guard cover == .open || cover == .tilt else { return }
        let count = 2 + Int((seed >> 29) % 3)
        for k in 0..<count {
            let w = bed.width / CGFloat(count + 1)
            let h = bed.height * (0.7 + CGFloat((seed >> UInt64(k * 3 + 5)) % 4) * 0.12)
            let rect = CGRect(x: bed.minX + w * CGFloat(k) + w * 0.35,
                              y: bed.minY - h, width: w * 0.8, height: h)
            ctx.fill(Path(roundedRect: rect, cornerRadius: h * 0.25),
                     with: .color(Color(red: 0.44, green: 0.36, blue: 0.26)))
            ctx.stroke(Path(roundedRect: rect, cornerRadius: h * 0.25),
                       with: .color(Theme.ink.opacity(0.5)), lineWidth: line * 0.6)
        }
    }

    private static func draught(
        _ parts: Build, def: ConveyanceDefinition, anchor: CGPoint, bed: CGRect,
        s: CGFloat, mirror: CGFloat, time: Double, body: Color, trim: Color,
        line: CGFloat, beast: AnimalDefinition.Build?, seed: UInt64,
        ctx: inout GraphicsContext
    ) {
        switch parts.draught {
        case .beast where def.kind == .mount:
            // The beast is the conveyance. `SettlementWildlife` owns what an
            // animal looks like — one drawing for the wild, the pen and the
            // saddle — so this asks it for the body and adds only the tack: a
            // saddle pad and a rein, where the rider's seat will be.
            if let beast {
                SettlementWildlife.body(
                    beast, at: CGPoint(x: anchor.x, y: anchor.y - s * 0.34),
                    s: s * 0.34, time: time,
                    phase: Double(seed % 6199) / 6199 * 2 * .pi,
                    walking: true, context: &ctx)
            }
            let pad = CGRect(x: anchor.x - s * 0.34, y: anchor.y - s * 0.72,
                             width: s * 0.68, height: s * 0.2)
            ctx.fill(Path(roundedRect: pad, cornerRadius: s * 0.06),
                     with: .color(Color(red: 0.42, green: 0.28, blue: 0.2)))
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: anchor.x + mirror * s * 0.3, y: anchor.y - s * 0.66))
                p.addLine(to: CGPoint(x: anchor.x + mirror * s * 0.72, y: anchor.y - s * 0.8))
            }, with: .color(Theme.ink.opacity(0.7)), lineWidth: line * 0.8)
        case .beast, .shafts:
            // Two shafts reaching forward to whatever is pulling — a person, a
            // pair of hands, an ox. What is on the other end is drawn by
            // whoever is on the other end.
            for offset in [CGFloat(-0.28), 0.28] {
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: bed.midX + mirror * bed.width * 0.42,
                                       y: bed.midY + offset * bed.height))
                    p.addLine(to: CGPoint(x: bed.midX + mirror * (bed.width * 0.5 + s * 0.55),
                                          y: bed.midY - bed.height * 0.2))
                }, with: .color(body), lineWidth: line * 1.3)
            }
        case .boiler:
            let r = bed.height * 0.85
            let barrel = CGRect(x: bed.midX + mirror * bed.width * 0.16 - r,
                                y: bed.minY - r * 1.6, width: r * 2, height: r * 1.6)
            ctx.fill(Path(roundedRect: barrel, cornerRadius: r * 0.4), with: .color(trim))
            ctx.stroke(Path(roundedRect: barrel, cornerRadius: r * 0.4),
                       with: .color(Theme.ink.opacity(0.6)), lineWidth: line)
            let stackX = barrel.midX + mirror * r * 0.6
            ctx.fill(Path(CGRect(x: stackX - r * 0.16, y: barrel.minY - r * 0.7,
                                 width: r * 0.32, height: r * 0.7)),
                     with: .color(Theme.ink.opacity(0.85)))
            // Smoke, drifting back the way it came from.
            for k in 0..<3 {
                let t = (time * 0.6 + Double(k) * 0.33).truncatingRemainder(dividingBy: 1)
                let puff = CGFloat(t)
                let rr = r * (0.16 + puff * 0.3)
                ctx.fill(Path(ellipseIn: CGRect(
                    x: stackX - mirror * puff * r * 1.2 - rr,
                    y: barrel.minY - r * 0.8 - puff * r * 1.4 - rr,
                    width: rr * 2, height: rr * 2)),
                    with: .color(Theme.boneDim.opacity(0.22 * (1 - puff))))
            }
        case .engine:
            let bonnet = CGRect(x: mirror > 0 ? bed.maxX : bed.minX - bed.width * 0.3,
                                y: bed.minY - bed.height * 0.55,
                                width: bed.width * 0.3, height: bed.height * 1.1)
            ctx.fill(Path(roundedRect: bonnet, cornerRadius: bed.height * 0.15),
                     with: .color(trim))
            ctx.stroke(Path(roundedRect: bonnet, cornerRadius: bed.height * 0.15),
                       with: .color(Theme.ink.opacity(0.6)), lineWidth: line)
        case .lift:
            // Blades over it, turning. Two, at opposite phases, so the thing
            // reads as hovering rather than as parked in the air.
            for side in [CGFloat(-1), 1] {
                let x = bed.midX + side * bed.width * 0.36
                let span = bed.width * 0.34 * CGFloat(abs(cos(time * 6 + Double(side))))
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: x - span, y: bed.minY - bed.height * 0.9))
                    p.addLine(to: CGPoint(x: x + span, y: bed.minY - bed.height * 0.9))
                }, with: .color(Theme.boneDim.opacity(0.7)), lineWidth: line)
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: bed.minY))
                    p.addLine(to: CGPoint(x: x, y: bed.minY - bed.height * 0.9))
                }, with: .color(body), lineWidth: line)
            }
        }
    }

    static func hash(_ id: UUID) -> UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in [id.uuid.0, id.uuid.3, id.uuid.7, id.uuid.11, id.uuid.15] {
            h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3
        }
        return h
    }
}
