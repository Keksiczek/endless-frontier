import SwiftUI
import EndlessFrontierCore

/// The inside of a building — the room, its furniture, and the places people
/// actually stand to work.
///
/// Until now a building was a silhouette and its workers were scattered
/// somewhere on its lot: a smith "at the workshop" stood on the roof as often
/// as beside it, and a granary was a shed with nothing in it. That is the last
/// place the world was still an abstraction pretending to be a place — you
/// could see *that* someone worked here and never see them *working*.
///
/// A building is now a room. It has a floor, walls with a door in them, and
/// fittings that say what the room is for: a bed and a hearth in a house, an
/// anvil and a bench in a workshop, sacks in the granary, an altar in the
/// temple. Every fitting a person uses is a **station**, and the simulation's
/// own roster (`BuildingPlacement.assignedPawnIDs`) decides who stands at which
/// one — so the smith you watch hammering is the smith the engine employs.
///
/// Zoom in and the roof lifts off (see `roofFade`). Zoomed out you see a town
/// of roofs; pushed in close you see the work going on under them.
///
/// Strictly presentational. Station geometry is a pure function of
/// `(glyph, seed, lot)`, shared with `AgentMotion` so the person is drawn at
/// the bench that is drawn — nothing here is stored and nothing writes back.
enum SettlementInterior {

    // MARK: - Geometry

    /// How far inside its lot the wall stands, as a fraction of the lot's side.
    /// The gap outside it is the yard the building sits in.
    static let wallInset: Double = 0.10

    /// Fittings the rooms are furnished with. A fitting either *is* a station
    /// (someone works at it) or is clutter that makes the room look lived in.
    enum Fitting: String, CaseIterable, Sendable {
        case bed, hearth, table          // a home
        case bench, anvil, rack          // craft
        case desk, shelf                 // learning
        case counter, crate              // exchange
        case sack, barrel                // stores
        case altar, pew                  // faith
        case watchpost, weapons          // defence
        case millstone, machine, cart    // industry
        case panel, console              // the late eras

        /// Whether a colonist stands and works at this.
        var isStation: Bool {
            switch self {
            case .crate, .sack, .barrel, .shelf, .rack, .pew, .weapons, .hearth:
                return false
            default:
                return true
            }
        }
    }

    /// One fitting's place inside its lot, in lot-fractions of −0.5…0.5.
    ///
    /// Deliberately lot-relative rather than in pixels or map space: the
    /// renderer multiplies by the pixel footprint, `AgentMotion` multiplies by
    /// the normalised one, and both land on the same spot. That is the whole
    /// reason a colonist can be drawn *at* the anvil rather than near it.
    struct Slot: Equatable, Sendable {
        let dx: Double
        let dy: Double
        let fitting: Fitting
    }

    /// The room's furniture, in a stable order. Deterministic in `seed`, so a
    /// given building is always laid out the same way.
    ///
    /// The plan is a ring around the inside of the walls with the floor left
    /// clear in the middle — the shape almost every real workroom has, and the
    /// one that keeps people from being drawn on top of each other.
    static func slots(for glyph: SettlementRenderer.BuildingGlyph,
                      seed: UInt64, stations: Int) -> [Slot] {
        let plan = furnishing(glyph)
        // Enough seats for everyone the engine posted here, within reason: a
        // room is a room, not a stadium.
        let wanted = max(plan.minimum, min(plan.maximum, stations))
        var slots: [Slot] = []
        var h = seed | 1

        func roll() -> Double {
            h ^= h >> 33; h = h &* 0xFF51_AFD7_ED55_8CCD; h ^= h >> 29
            return Double((h >> 40) & 0xFFFF) / 65535
        }

        // Work stations first, laid along the inside of the walls.
        let ring = perimeter(count: wanted, jitter: { roll() })
        for (i, point) in ring.enumerated() {
            slots.append(Slot(dx: point.dx, dy: point.dy,
                              fitting: plan.stations[i % plan.stations.count]))
        }
        // Then the clutter that makes it a room rather than a diagram, tucked
        // into the corners the stations left alone.
        for (i, fitting) in plan.clutter.enumerated() {
            let corner = corners[(i + Int(h % 4)) % corners.count]
            slots.append(Slot(dx: corner.dx * (0.80 + roll() * 0.14),
                              dy: corner.dy * (0.80 + roll() * 0.14),
                              fitting: fitting))
        }
        return slots
    }

    /// The stations alone, in the order colonists take them.
    static func stationSlots(for glyph: SettlementRenderer.BuildingGlyph,
                             seed: UInt64, stations: Int) -> [Slot] {
        slots(for: glyph, seed: seed, stations: stations).filter { $0.fitting.isStation }
    }

    /// Where a dwelling's beds stand.
    ///
    /// A separate question from the workroom's stations: a house is laid out
    /// around sleeping, so its beds go along the walls in a row rather than
    /// being scattered among benches. Deterministic in the seed, so the same
    /// house always has its beds in the same corners — the whole point being
    /// that a colonist has *their own* bed to go back to.
    static func bedSlots(seed: UInt64, sleepers: Int) -> [Slot] {
        let count = max(1, min(sleepers, 12))
        var h = seed | 1
        return perimeter(count: count, jitter: {
            h ^= h >> 33; h = h &* 0xFF51_AFD7_ED55_8CCD; h ^= h >> 29
            return Double((h >> 40) & 0xFFFF) / 65535
        }).map { Slot(dx: $0.dx, dy: $0.dy, fitting: .bed) }
    }

    private static let corners: [(dx: Double, dy: Double)] = [
        (-0.34, -0.30), (0.34, -0.30), (-0.34, 0.30), (0.34, 0.30),
    ]

    /// `count` places spread around the inside of the walls, walking the
    /// perimeter so two stations are never on top of each other.
    private static func perimeter(count: Int, jitter: () -> Double) -> [(dx: Double, dy: Double)] {
        guard count > 0 else { return [] }
        let reach = 0.5 - wallInset - 0.06
        return (0..<count).map { i in
            // Walk the perimeter of a square, starting at the back wall so the
            // first (and often only) worker faces the door.
            let t = (Double(i) + 0.5) / Double(count)
            let side = Int(t * 4) % 4
            let along = (t * 4).truncatingRemainder(dividingBy: 1) * 2 - 1
            let wobble = (jitter() - 0.5) * 0.06
            switch side {
            case 0: return (dx: along * reach + wobble, dy: -reach)          // back wall
            case 1: return (dx: reach, dy: along * reach + wobble)           // right
            case 2: return (dx: -along * reach + wobble, dy: reach * 0.86)   // front, clear of the door
            default: return (dx: -reach, dy: -along * reach + wobble)        // left
            }
        }
    }

    /// What a room of this kind is furnished with, and how many can work in it.
    private static func furnishing(
        _ glyph: SettlementRenderer.BuildingGlyph
    ) -> (stations: [Fitting], clutter: [Fitting], minimum: Int, maximum: Int) {
        switch glyph {
        case .house:
            return ([.bed, .table], [.hearth, .crate], 2, 4)
        case .hall:
            return ([.desk], [.shelf, .shelf, .crate], 1, 5)
        case .market:
            return ([.counter], [.crate, .barrel, .sack], 1, 4)
        case .granary:
            return ([.table], [.sack, .sack, .barrel, .crate], 1, 3)
        case .cookhouse:
            return ([.hearth, .table], [.sack, .barrel, .shelf], 2, 4)
        case .workshop:
            return ([.bench, .anvil], [.rack, .crate], 1, 5)
        case .plant:
            return ([.machine, .bench], [.barrel, .crate], 2, 6)
        case .tower:
            return ([.watchpost], [.weapons, .rack], 1, 4)
        case .temple:
            return ([.altar], [.pew, .pew, .hearth], 1, 3)
        case .mine:
            return ([.cart, .bench], [.crate, .rack], 1, 4)
        case .mill:
            return ([.millstone], [.sack, .sack], 1, 3)
        case .generator:
            return ([.machine], [.barrel, .rack], 1, 3)
        case .array:
            return ([.panel], [.crate], 1, 4)
        case .pad:
            return ([.console, .panel], [.crate, .rack], 1, 5)

        // The trades. Every one of these used to fall through to whatever glyph
        // its numbers implied, so a farm, a well and a granary were the same
        // room of sacks. What a place is furnished with is most of what tells
        // you what happens in it.
        case .tenement:
            return ([.bed, .table], [.bed, .crate, .hearth], 3, 8)
        case .farm:
            return ([.table, .cart], [.sack, .sack, .barrel], 1, 4)
        case .lodge:
            return ([.bench, .rack], [.hearth, .weapons, .crate], 1, 3)
        case .sawmill:
            return ([.bench, .millstone], [.rack, .rack, .crate], 1, 4)
        case .well:
            return ([.barrel], [.crate], 1, 1)
        case .forge:
            return ([.anvil, .bench], [.hearth, .rack, .crate], 1, 4)
        case .tanks:
            return ([.machine, .console], [.barrel, .barrel, .crate], 1, 4)
        case .rail:
            return ([.cart, .bench], [.crate, .crate, .rack], 1, 5)
        case .lab:
            return ([.console, .desk], [.shelf, .panel, .crate], 2, 6)
        case .dish:
            return ([.console], [.panel, .desk], 1, 3)
        case .vault:
            return ([.counter, .desk], [.crate, .crate], 1, 3)
        case .clinic:
            return ([.bed, .desk], [.bed, .shelf, .crate], 2, 5)
        case .aqueduct:
            return ([.barrel], [.crate], 1, 2)
        case .wall:
            return ([.watchpost], [.weapons], 1, 2)
        case .barracks:
            return ([.bed, .table], [.bed, .weapons, .rack], 2, 6)
        case .turbine:
            return ([.machine], [.crate], 1, 2)
        case .dam:
            return ([.machine, .console], [.rack, .crate], 1, 3)
        }
    }

    // MARK: - When the roof comes off

    /// How solidly the roof is drawn at a given zoom: whole from far off,
    /// gone once you are close enough to care who is inside.
    static func roofFade(zoom: CGFloat) -> Double {
        let start: CGFloat = 1.7, end: CGFloat = 2.5
        guard zoom > start else { return 1 }
        guard zoom < end else { return 0 }
        return Double(1 - (zoom - start) / (end - start))
    }

    /// Whether the inside is worth drawing at all: below a few pixels a room
    /// is a smudge, and a town of smudges costs frames for nothing.
    static func isLegible(footprint: CGSize) -> Bool {
        min(footprint.width, footprint.height) >= 16
    }

    // MARK: - Drawing

    /// Draws one building's inside: floor, fittings, walls and a door. Call
    /// under the silhouette — the roof is drawn over this, fading as you zoom.
    static func draw(
        _ context: inout GraphicsContext,
        glyph: SettlementRenderer.BuildingGlyph,
        at c: CGPoint, footprint: CGSize, seed: UInt64, era: Era,
        workers: Int, residents: Int = 0, night: Double, time: Double
    ) {
        guard isLegible(footprint: footprint) else { return }
        let inset = CGSize(width: footprint.width * wallInset,
                           height: footprint.height * wallInset)
        let room = CGRect(x: c.x - footprint.width / 2 + inset.width,
                          y: c.y - footprint.height / 2 + inset.height,
                          width: footprint.width - inset.width * 2,
                          height: footprint.height - inset.height * 2)
        guard room.width > 4, room.height > 4 else { return }

        let palette = palette(era: era, seed: seed)
        floor(&context, room: room, palette: palette, seed: seed)
        // The room's own lamplight, so a worked building glows after dark.
        if night > 0.05, workers > 0 {
            context.fill(Path(room), with: .color(Theme.accent.opacity(0.10 * night)))
        }
        // A house is furnished around who lives in it: a bed apiece and a
        // hearth. Anything else is furnished around the work done in it.
        let plan: [Slot]
        if glyph == .house, residents > 0 {
            plan = bedSlots(seed: seed, sleepers: residents)
                + [Slot(dx: 0, dy: 0.12, fitting: .hearth)]
        } else {
            plan = slots(for: glyph, seed: seed, stations: workers)
        }
        for slot in plan {
            let p = CGPoint(x: c.x + CGFloat(slot.dx) * footprint.width,
                            y: c.y + CGFloat(slot.dy) * footprint.height)
            fitting(&context, slot.fitting, at: p, scale: min(room.width, room.height),
                    palette: palette, night: night, time: time, seed: seed)
        }
        walls(&context, room: room, palette: palette, seed: seed)
    }

    /// Where the colonists posted here stand, in pixels — the same slots the
    /// fittings were drawn at.
    static func stationPoints(
        glyph: SettlementRenderer.BuildingGlyph, at c: CGPoint,
        footprint: CGSize, seed: UInt64, workers: Int
    ) -> [CGPoint] {
        stationSlots(for: glyph, seed: seed, stations: workers).map {
            CGPoint(x: c.x + CGFloat($0.dx) * footprint.width,
                    y: c.y + CGFloat($0.dy) * footprint.height)
        }
    }

    // MARK: - Surfaces

    private struct Palette {
        let floor: Color
        let plank: Color
        let wall: Color
        let wood: Color
        let metal: Color
        let cloth: Color
    }

    private static func palette(era: Era, seed: UInt64) -> Palette {
        let base = SettlementStructures.materials(era)
        func shade(_ rgb: (Double, Double, Double), _ k: Double) -> Color {
            Color(red: min(1, rgb.0 * k), green: min(1, rgb.1 * k), blue: min(1, rgb.2 * k))
        }
        switch era {
        case .earlySettlement, .ancient, .medieval:
            return Palette(floor: shade(base.wall, 1.45), plank: shade(base.wall, 1.05),
                           wall: shade(base.stone, 1.2),
                           wood: Color(red: 0.40, green: 0.30, blue: 0.20),
                           metal: Color(red: 0.44, green: 0.45, blue: 0.49),
                           cloth: Color(red: 0.55, green: 0.44, blue: 0.34))
        case .earlyIndustrial:
            return Palette(floor: shade(base.stone, 1.5), plank: shade(base.stone, 1.15),
                           wall: shade(base.wall, 1.15),
                           wood: Color(red: 0.38, green: 0.29, blue: 0.21),
                           metal: Color(red: 0.50, green: 0.50, blue: 0.54),
                           cloth: Color(red: 0.46, green: 0.38, blue: 0.32))
        case .modern, .nearFuture:
            return Palette(floor: shade(base.wall, 1.6), plank: shade(base.wall, 1.25),
                           wall: shade(base.stone, 1.3),
                           wood: Color(red: 0.34, green: 0.33, blue: 0.34),
                           metal: Color(red: 0.58, green: 0.60, blue: 0.64),
                           cloth: Color(red: 0.36, green: 0.42, blue: 0.48))
        }
    }

    /// The floor: boards, flagstones or plate depending on the age, laid in a
    /// direction fixed per building so a street of houses isn't one texture.
    private static func floor(
        _ context: inout GraphicsContext, room: CGRect, palette: Palette, seed: UInt64
    ) {
        let shape = Path(roundedRect: room, cornerRadius: min(room.width, room.height) * 0.06)
        context.fill(shape, with: .color(palette.floor))
        // Boards, run along the room's long axis.
        let along = room.width >= room.height
        let step = max(3.0, Double(min(room.width, room.height)) / 4.5)
        var lines = Path()
        if along {
            var y = room.minY + CGFloat(step)
            while y < room.maxY - 1 {
                lines.move(to: CGPoint(x: room.minX, y: y))
                lines.addLine(to: CGPoint(x: room.maxX, y: y))
                y += CGFloat(step)
            }
        } else {
            var x = room.minX + CGFloat(step)
            while x < room.maxX - 1 {
                lines.move(to: CGPoint(x: x, y: room.minY))
                lines.addLine(to: CGPoint(x: x, y: room.maxY))
                x += CGFloat(step)
            }
        }
        context.stroke(lines, with: .color(palette.plank.opacity(0.55)), lineWidth: 0.5)
        // A breath of shade down the inside of the walls, so the room has depth
        // rather than reading as a sticker.
        context.stroke(shape, with: .color(Theme.ink.opacity(0.35)),
                       lineWidth: max(1, min(room.width, room.height) * 0.05))
    }

    /// The walls, with a doorway left open on the front.
    private static func walls(
        _ context: inout GraphicsContext, room: CGRect, palette: Palette, seed: UInt64
    ) {
        let thickness = max(1.0, min(room.width, room.height) * 0.055)
        let doorWidth = min(room.width * 0.34, 14)
        // The door sits on the front wall, offset a little per building.
        let offset = (Double((seed >> 17) & 0xFF) / 255 - 0.5) * Double(room.width * 0.3)
        let doorX = room.midX + CGFloat(offset)

        var wall = Path()
        wall.move(to: CGPoint(x: room.minX, y: room.maxY))
        wall.addLine(to: CGPoint(x: room.minX, y: room.minY))
        wall.addLine(to: CGPoint(x: room.maxX, y: room.minY))
        wall.addLine(to: CGPoint(x: room.maxX, y: room.maxY))
        // …and the front wall in two pieces, with the gap between them.
        wall.move(to: CGPoint(x: room.minX, y: room.maxY))
        wall.addLine(to: CGPoint(x: max(room.minX, doorX - doorWidth / 2), y: room.maxY))
        wall.move(to: CGPoint(x: min(room.maxX, doorX + doorWidth / 2), y: room.maxY))
        wall.addLine(to: CGPoint(x: room.maxX, y: room.maxY))
        context.stroke(wall, with: .color(palette.wall),
                       style: StrokeStyle(lineWidth: thickness, lineJoin: .miter))
        context.stroke(wall, with: .color(Theme.bone.opacity(0.30)), lineWidth: 0.6)
        // The threshold, so the gap reads as a door and not as a missing wall.
        context.stroke(Path { p in
            p.move(to: CGPoint(x: max(room.minX, doorX - doorWidth / 2), y: room.maxY))
            p.addLine(to: CGPoint(x: min(room.maxX, doorX + doorWidth / 2), y: room.maxY))
        }, with: .color(Theme.accent.opacity(0.35)), lineWidth: max(0.8, thickness * 0.4))
    }

    // MARK: - Furniture

    /// One fitting, drawn small and flat — this is a room seen from above.
    private static func fitting(
        _ context: inout GraphicsContext, _ kind: Fitting, at p: CGPoint,
        scale: CGFloat, palette: Palette, night: Double, time: Double, seed: UInt64
    ) {
        let s = max(2.4, scale * 0.17)
        func box(_ w: CGFloat, _ h: CGFloat, _ colour: Color, outline: Double = 0.35) {
            let r = CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h)
            context.fill(Path(roundedRect: r, cornerRadius: min(w, h) * 0.22), with: .color(colour))
            context.stroke(Path(roundedRect: r, cornerRadius: min(w, h) * 0.22),
                           with: .color(Theme.ink.opacity(outline)), lineWidth: 0.5)
        }
        func disc(_ d: CGFloat, _ colour: Color) {
            context.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2,
                                                width: d, height: d)), with: .color(colour))
        }

        switch kind {
        case .bed:
            box(s * 1.0, s * 1.5, palette.cloth)
            // A pillow at the head.
            box(s * 0.8, s * 0.42, Theme.bone.opacity(0.55), outline: 0.2)
        case .table:
            box(s * 1.2, s * 0.8, palette.wood)
            context.stroke(Path(CGRect(x: p.x - s * 0.5, y: p.y - s * 0.3,
                                       width: s, height: s * 0.6)),
                           with: .color(Theme.bone.opacity(0.25)), lineWidth: 0.5)
        case .hearth:
            // The fire: the one thing in the room that moves.
            disc(s * 1.1, Color(red: 0.24, green: 0.22, blue: 0.21))
            let flicker = 0.55 + 0.35 * sin(time * 5 + Double(seed % 17))
            disc(s * 0.55, Theme.accent.opacity(0.35 + flicker * 0.5))
            if night > 0.1 {
                let g = s * 2.4
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - g, y: p.y - g, width: g * 2, height: g * 2)),
                    with: .radialGradient(
                        Gradient(colors: [Theme.accent.opacity(0.20 * night), .clear]),
                        center: p, startRadius: 0, endRadius: g))
            }
        case .bench:
            box(s * 1.4, s * 0.55, palette.wood)
            // Tools laid along it.
            context.stroke(Path { path in
                path.move(to: CGPoint(x: p.x - s * 0.5, y: p.y))
                path.addLine(to: CGPoint(x: p.x + s * 0.4, y: p.y))
            }, with: .color(palette.metal.opacity(0.8)), lineWidth: 0.8)
        case .anvil:
            box(s * 0.75, s * 0.5, palette.metal)
            box(s * 0.45, s * 0.75, palette.metal.opacity(0.85), outline: 0.15)
        case .rack:
            box(s * 0.4, s * 1.2, palette.wood)
            for k in 0..<3 {
                let y = p.y - s * 0.45 + CGFloat(k) * s * 0.45
                context.stroke(Path { path in
                    path.move(to: CGPoint(x: p.x - s * 0.2, y: y))
                    path.addLine(to: CGPoint(x: p.x + s * 0.2, y: y))
                }, with: .color(Theme.bone.opacity(0.28)), lineWidth: 0.5)
            }
        case .desk:
            box(s * 1.15, s * 0.65, palette.wood)
            // An open book, pale on the dark wood.
            box(s * 0.45, s * 0.3, Theme.bone.opacity(0.62), outline: 0.15)
        case .shelf:
            box(s * 1.3, s * 0.4, palette.wood)
            for k in 0..<4 {
                let x = p.x - s * 0.5 + CGFloat(k) * s * 0.32
                context.fill(Path(CGRect(x: x, y: p.y - s * 0.14,
                                         width: s * 0.14, height: s * 0.28)),
                             with: .color(Theme.bone.opacity(0.35)))
            }
        case .counter:
            box(s * 1.5, s * 0.45, palette.wood)
            disc(s * 0.28, Theme.accent.opacity(0.7))    // coin on the counter
        case .crate:
            box(s * 0.7, s * 0.7, palette.wood.opacity(0.92))
            context.stroke(Path { path in
                path.move(to: CGPoint(x: p.x - s * 0.35, y: p.y))
                path.addLine(to: CGPoint(x: p.x + s * 0.35, y: p.y))
            }, with: .color(Theme.bone.opacity(0.22)), lineWidth: 0.5)
        case .sack:
            for k in 0..<2 {
                let o = CGFloat(k) * s * 0.34 - s * 0.17
                context.fill(Path(ellipseIn: CGRect(x: p.x + o - s * 0.26, y: p.y - s * 0.32,
                                                    width: s * 0.52, height: s * 0.66)),
                             with: .color(palette.cloth.opacity(0.9)))
            }
        case .barrel:
            disc(s * 0.66, palette.wood)
            context.stroke(Path(ellipseIn: CGRect(x: p.x - s * 0.33, y: p.y - s * 0.33,
                                                  width: s * 0.66, height: s * 0.66)),
                           with: .color(palette.metal.opacity(0.6)), lineWidth: 0.7)
        case .altar:
            box(s * 1.1, s * 0.6, palette.wall)
            disc(s * 0.3, Theme.accent.opacity(0.55 + 0.25 * sin(time * 2)))
        case .pew:
            box(s * 1.3, s * 0.3, palette.wood.opacity(0.85))
        case .watchpost:
            // A firing slit and a stool: someone is meant to be looking out.
            box(s * 0.8, s * 0.5, palette.wall)
            context.stroke(Path { path in
                path.move(to: CGPoint(x: p.x - s * 0.5, y: p.y - s * 0.34))
                path.addLine(to: CGPoint(x: p.x + s * 0.5, y: p.y - s * 0.34))
            }, with: .color(Theme.ink.opacity(0.8)), lineWidth: 1.2)
        case .weapons:
            for k in 0..<3 {
                let x = p.x - s * 0.3 + CGFloat(k) * s * 0.3
                context.stroke(Path { path in
                    path.move(to: CGPoint(x: x, y: p.y + s * 0.4))
                    path.addLine(to: CGPoint(x: x + s * 0.1, y: p.y - s * 0.5))
                }, with: .color(palette.metal.opacity(0.8)), lineWidth: 0.9)
            }
        case .millstone:
            disc(s * 1.15, palette.wall)
            context.stroke(Path(ellipseIn: CGRect(x: p.x - s * 0.58, y: p.y - s * 0.58,
                                                  width: s * 1.16, height: s * 1.16)),
                           with: .color(Theme.bone.opacity(0.35)), lineWidth: 0.7)
            // The stone turns, slowly.
            let a = time * 0.6 + Double(seed % 29)
            context.stroke(Path { path in
                path.move(to: CGPoint(x: p.x - CGFloat(cos(a)) * s * 0.5,
                                      y: p.y - CGFloat(sin(a)) * s * 0.5))
                path.addLine(to: CGPoint(x: p.x + CGFloat(cos(a)) * s * 0.5,
                                         y: p.y + CGFloat(sin(a)) * s * 0.5))
            }, with: .color(Theme.bone.opacity(0.4)), lineWidth: 0.8)
        case .machine:
            box(s * 1.2, s * 0.9, palette.metal.opacity(0.9))
            // A running light, blinking out of phase per machine.
            let on = sin(time * 3 + Double(seed % 11)) > 0
            disc(s * 0.22, (on ? Theme.accent : Theme.danger).opacity(0.8))
        case .cart:
            box(s * 1.0, s * 0.6, palette.wood)
            disc(s * 0.3, palette.metal.opacity(0.7))
        case .panel:
            box(s * 1.4, s * 0.9, Color(red: 0.16, green: 0.22, blue: 0.30))
            context.stroke(Path(CGRect(x: p.x - s * 0.7, y: p.y - s * 0.45,
                                       width: s * 1.4, height: s * 0.9)),
                           with: .color(Color(red: 0.45, green: 0.66, blue: 0.82).opacity(0.7)),
                           lineWidth: 0.6)
        case .console:
            box(s * 1.1, s * 0.7, palette.metal.opacity(0.85))
            for k in 0..<3 {
                let x = p.x - s * 0.3 + CGFloat(k) * s * 0.3
                disc2(&context, at: CGPoint(x: x, y: p.y), d: s * 0.16,
                      colour: Theme.good.opacity(0.5 + 0.4 * sin(time * 4 + Double(k))))
            }
        }
    }

    private static func disc2(_ context: inout GraphicsContext, at p: CGPoint,
                              d: CGFloat, colour: Color) {
        context.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2,
                                            width: d, height: d)), with: .color(colour))
    }
}
