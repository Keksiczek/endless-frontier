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
    /// Deliberately **room-relative** rather than in pixels or map space: the
    /// renderer multiplies by the room's pixel size, `AgentMotion` by the
    /// normalised one (`WorkSite.place`), and both land on the same spot. That
    /// is the whole reason a colonist can be drawn *at* the anvil rather than
    /// near it.
    ///
    /// It said "lot-relative" for a while after the drawing had moved to the
    /// room, and the one caller that believed the comment — the beds — put a
    /// household to sleep across the whole parcel while their mattresses were
    /// drawn inside the walls.
    struct Slot: Equatable, Sendable {
        let dx: Double
        let dy: Double
        /// Which of the drawings stands here.
        let fitting: Fitting
        /// …and **which piece of furniture it is**, when the content named one.
        /// A plank cot and a sprung bed are both `bed`; this is what makes them
        /// look and read unlike each other (`FittingDefinition`).
        var piece: FittingDefinition?

        init(dx: Double, dy: Double, fitting: Fitting, piece: FittingDefinition? = nil) {
            self.dx = dx
            self.dy = dy
            self.fitting = fitting
            self.piece = piece
        }

        /// A slot furnished from the book. Falls back to a crate when the
        /// content names a shape the canvas cannot draw — loudly wrong in the
        /// content test rather than quietly missing on screen.
        init(dx: Double, dy: Double, piece: FittingDefinition) {
            self.init(dx: dx, dy: dy,
                      fitting: Fitting(rawValue: piece.shape) ?? .crate,
                      piece: piece)
        }
    }

    /// The room's furniture, in a stable order. Deterministic in `seed`, so a
    /// given building is always laid out the same way.
    ///
    /// The plan is a ring around the inside of the walls with the floor left
    /// clear in the middle — the shape almost every real workroom has, and the
    /// one that keeps people from being drawn on top of each other.
    static func slots(for glyph: SettlementRenderer.BuildingGlyph,
                      seed: UInt64, stations: Int,
                      era: Era, registry: GameDataRegistry) -> [Slot] {
        let plan = furnishing(glyph, era: era, registry: registry)
        guard !plan.stations.isEmpty else {
            // A room the book furnishes with nothing to stand at is still a
            // room: it gets its corners and no ring. Better than seating people
            // at furniture that does not exist.
            return clutterSlots(for: glyph, seed: seed, era: era, registry: registry)
        }
        // Enough seats for everyone the engine posted here, within reason: a
        // room is a room, not a stadium.
        //
        // The ceiling used to be a small constant per kind, and a workshop the
        // engine had posted eight people to laid out five places — so three of
        // them were seated *on top of* somebody else by `index % count`, which
        // is what "lidi v budovách jsou hodně na sobě" looks like from the
        // inside. The ring is laid out by division, not by a fixed pitch, so
        // more places do not overlap; they just stand closer. `stationCeiling`
        // is where the "not a stadium" part lives now.
        let wanted = max(plan.minimum, min(stationCeiling(plan.maximum), stations))
        var slots: [Slot] = []
        var h = seed | 1

        func roll() -> Double {
            h ^= h >> 33; h = h &* 0xFF51_AFD7_ED55_8CCD; h ^= h >> 29
            return Double((h >> 40) & 0xFFFF) / 65535
        }

        // Work stations first, laid along the inside of the walls — and on a
        // second, tighter ring once the wall is full, which is how a real
        // crowded workroom is arranged and how ten people stand in one room
        // without standing in each other.
        let onWall = min(wanted, ringCapacity)
        var ring = perimeter(count: onWall, jitter: { roll() })
        if wanted > onWall {
            ring += perimeter(count: wanted - onWall, jitter: { roll() }, scale: 0.55)
        }
        for (i, point) in ring.enumerated() {
            slots.append(Slot(dx: point.dx, dy: point.dy,
                              piece: plan.stations[i % plan.stations.count]))
        }
        // Then the clutter that makes it a room rather than a diagram, tucked
        // into the corners the stations left alone.
        //
        // **Not all of it, and not the same of it.** Keks, at zoom: *"vypadají
        // uvnitř budovy skoro stejně."* Every room of a kind was furnished from
        // the same list in the same order, so ten huts were ten copies of one
        // hut with the furniture jittered a few pixels. A household keeps some
        // of what it could keep: the seed picks which corners are used and what
        // stands in them, so two houses on one street are two houses.
        slots += clutterSlots(for: glyph, seed: h, era: era, registry: registry)
        return slots
    }

    /// The things in the corners: what a room keeps that nobody works at.
    ///
    /// Its own function because a house with somebody living in it takes a
    /// different route through `draw` — beds first — and used to arrive with no
    /// corners furnished at all.
    static func clutterSlots(
        for glyph: SettlementRenderer.BuildingGlyph, seed: UInt64,
        era: Era, registry: GameDataRegistry
    ) -> [Slot] {
        let plan = furnishing(glyph, era: era, registry: registry)
        guard !plan.clutter.isEmpty else { return [] }
        var h = seed | 1
        func roll() -> Double {
            h ^= h >> 33; h = h &* 0xFF51_AFD7_ED55_8CCD; h ^= h >> 29
            return Double((h >> 40) & 0xFFFF) / 65535
        }
        let nooks = shuffled(corners, roll: { roll() })
        // At least two, where there are two to keep. One thing in a corner is
        // a room with a box in it; the difference between that and a room
        // somebody lives in is a couple of objects.
        let kept = max(min(2, plan.clutter.count),
                       min(plan.clutter.count, 1 + Int(roll() * Double(plan.clutter.count))))
        return shuffled(plan.clutter, roll: { roll() }).prefix(kept).enumerated().map { i, piece in
            let nook = nooks[i % nooks.count]
            return Slot(dx: nook.dx * (0.80 + roll() * 0.14),
                        dy: nook.dy * (0.80 + roll() * 0.14),
                        piece: piece)
        }
    }

    /// A seeded shuffle — deterministic in whatever `roll` is drawing from, so
    /// a given building is always furnished the same way (rule 3's shape in the
    /// drawing: the same seed is the same room, every launch).
    private static func shuffled<T>(_ items: [T], roll: () -> Double) -> [T] {
        var out = items
        guard out.count > 1 else { return out }
        for i in stride(from: out.count - 1, to: 0, by: -1) {
            let j = min(i, Int(roll() * Double(i + 1)))
            out.swapAt(i, j)
        }
        return out
    }

    /// The stations alone, in the order colonists take them.
    static func stationSlots(for glyph: SettlementRenderer.BuildingGlyph,
                             seed: UInt64, stations: Int,
                             era: Era, registry: GameDataRegistry) -> [Slot] {
        slots(for: glyph, seed: seed, stations: stations, era: era, registry: registry)
            .filter { $0.fitting.isStation }
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

    /// **What is actually in store, standing on the floor.**
    ///
    /// Keks: *"ve skladu neleží suroviny."* A granary was furnished with two
    /// sacks whether the colony was starving or sitting on four thousand, so
    /// the one building whose whole purpose is *how much is in it* was the one
    /// building that could not show it. The fittings above are furniture; this
    /// is stock, and it fills the floor from the back wall forward.
    ///
    /// Presentation only, and derived: it reads `Settlement.storage` against
    /// `storageCapacity` and writes nothing (the canvas never feeds the
    /// simulation).
    static func storeSlots(fullness: Double, fitting: Fitting, seed: UInt64) -> [Slot] {
        let share = min(1, max(0, fullness))
        guard share > 0.02 else { return [] }
        // A full store is a packed floor; an empty one is a swept one. Rows of
        // three, because a wall of goods reads as goods and a scatter reads as
        // mess.
        let count = max(1, Int((share * Double(storeCeiling)).rounded()))
        var h = seed | 1
        func roll() -> Double {
            h ^= h >> 33; h = h &* 0xFF51_AFD7_ED55_8CCD; h ^= h >> 29
            return Double((h >> 40) & 0xFFFF) / 65535
        }
        let perRow = 3
        return (0..<count).map { i in
            let row = i / perRow, column = i % perRow
            // Back wall first, then forward — a store fills from the far end.
            let dy = -0.30 + Double(row) * 0.17 + (roll() - 0.5) * 0.03
            let dx = -0.26 + Double(column) * 0.26 + (roll() - 0.5) * 0.05
            return Slot(dx: dx, dy: min(0.30, dy), fitting: fitting)
        }
    }

    /// **What is on the floor, by kind.**
    ///
    /// `storeSlots` answers *how full*; this answers *what of*. A colony's
    /// `stockpile` is concrete goods — logs, cut stone, hides, ore — and a
    /// warehouse holding four hundred logs and one holding four hundred hides
    /// were the same drawing, which is the abstract-number fault the piles
    /// outside the door do not have.
    enum Goods: String, Sendable, CaseIterable {
        case timber, stone, ore, hide, cloth, grain

        /// What a raw material id reads as on a floor. Unknown goods fall to
        /// crates rather than being dropped — a store holding something the
        /// drawing has no shape for still has something in it.
        static func of(_ itemID: String) -> Goods {
            switch itemID {
            case "wood", "timber_bundle", "plank", "planks": return .timber
            case "rough_stone", "cut_stone", "brick", "clay": return .stone
            case "iron_ore", "coal", "copper_ore", "ingot", "iron_ingot": return .ore
            case "hide", "leather", "pelt": return .hide
            case "cloth", "wool", "linen", "thread": return .cloth
            default: return .grain
            }
        }
    }

    /// The most stock one room will show. Past this it is a wall of sacks and
    /// another sack says nothing.
    static let storeCeiling = 9

    /// The places a room keeps things that are not workstations.
    ///
    /// Four corners was too few twice over: a plan wanting five things put the
    /// fifth on top of the first (`i % corners.count`), and four objects in a
    /// room read as a diagram of a room rather than a room. The four mid-wall
    /// nooks are pulled further in on the axis they sit against, so nothing
    /// stands in the doorway or through a wall.
    private static let corners: [(dx: Double, dy: Double)] = [
        (-0.34, -0.30), (0.34, -0.30), (-0.34, 0.30), (0.34, 0.30),
        (0, -0.32), (-0.36, 0), (0.36, 0), (0, 0.31),
    ]

    /// `count` places spread around the inside of the walls, walking the
    /// perimeter so two stations are never on top of each other.
    /// How many places one lap of the wall holds before it is worth starting a
    /// second ring inside it. Eight is two a side.
    static let ringCapacity = 8

    /// The most places any room lays out. Past this a room is a crowd scene,
    /// and the engine posting thirty people to one building is the thing to
    /// fix rather than the drawing.
    private static func stationCeiling(_ stated: Int) -> Int { max(stated, 12) }

    private static func perimeter(count: Int, jitter: () -> Double,
                                  scale: Double = 1) -> [(dx: Double, dy: Double)] {
        guard count > 0 else { return [] }
        let reach = (0.5 - wallInset - 0.06) * scale
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
    /// **What furnishes this kind of room, in this age.**
    ///
    /// This was a `switch` over the building shapes with no notion of *when*,
    /// so a medieval workshop and a near-future assembly plant were furnished
    /// from the same two lines and shared their crates. Keks, twice: *"budovy
    /// mají nudné interiéry, pořád stejné … vesnice je moderní až v
    /// budoucnosti, canvas vypadá stejně."*
    ///
    /// It reads `fittings.json` now (`FittingDefinition`). An entry names the
    /// rooms it belongs in and the ages it belongs to, so furnishing a room is
    /// a query rather than a case — and a fitting written for one age
    /// *replaces* the timeless one rather than being added to a list nobody
    /// can reach.
    ///
    /// The floor and ceiling on how many places a room lays out stay here:
    /// they are about the room's geometry, not about its furniture.
    static func furnishing(
        _ glyph: SettlementRenderer.BuildingGlyph, era: Era, registry: GameDataRegistry
    ) -> (stations: [FittingDefinition], clutter: [FittingDefinition],
          minimum: Int, maximum: Int) {
        let all = registry.fittings(inRoom: glyph.rawValue, era: era)
        // An age's own furniture wins outright. A room with a `machine` written
        // for the industrial age should show that machine, not that machine
        // *and* the timeless one — otherwise every age adds clutter and a
        // far-future workshop is a museum of its own history.
        let dated = Set(all.filter { !$0.eras.isEmpty }.map(\.shape))
        let kept = all.filter { !$0.eras.isEmpty || !dated.contains($0.shape) }
        let stations = kept.filter { $0.role == .station }
        let clutter = kept.filter { $0.role == .clutter }
        return (stations, clutter,
                stations.isEmpty ? 0 : 1,
                max(1, stations.count + clutter.count))
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
        at c: CGPoint, footprint: CGSize, size: CGFloat, seed: UInt64, era: Era,
        workers: Int, residents: Int = 0, night: Double, time: Double,
        /// How full this building's own store is, 0…1, and what the goods in
        /// it look like. Nil for a building that stores nothing.
        stock: (fullness: Double, fitting: Fitting)? = nil,
        /// The concrete goods this store is holding, biggest heap first — logs,
        /// cut stone, hides. Answers *what of*, where `stock` answers *how
        /// full*, and it is what stops a warehouse of timber and a warehouse of
        /// hides being the same drawing.
        goods: [(kind: Goods, count: Int)] = [],
        /// The book the room is furnished out of (`FittingDefinition`).
        registry: GameDataRegistry
    ) {
        guard isLegible(footprint: footprint) else { return }
        // **Inside the walls that are actually drawn**, not inside the lot.
        // See `SettlementStructures.bodyRect`: the room used to be sized off
        // the footprint and the house off `s`, so the floor and its lamplight
        // spilled past the walls and the building glowed through them at night.
        let shell = SettlementStructures.bodyRect(glyph, at: c, s: size,
                                                   seed: seed, footprint: footprint)
        let room = shell.insetBy(dx: shell.width * wallInset,
                                 dy: shell.height * wallInset)
        guard room.width > 4, room.height > 4 else { return }
        // Everything below places its fittings in fractions of `footprint`;
        // they belong in fractions of the **room**, which is what stops a bed
        // being drawn in the street.
        let footprint = CGSize(width: room.width, height: room.height)
        let c = CGPoint(x: room.midX, y: room.midY)

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
            // A bed apiece and a fire — **and the rest of what a household
            // owns.** This branch used to stop at the beds, so the moment
            // anybody moved in, a home lost the table, the shelf and the barrel
            // that made it a home: an occupied house was furnished with less
            // than an empty one.
            plan = bedSlots(seed: seed, sleepers: residents)
                + [Slot(dx: 0, dy: 0.12, fitting: .hearth)]
                + clutterSlots(for: glyph, seed: seed &* 0x9E37_79B9,
                               era: era, registry: registry)
        } else {
            plan = slots(for: glyph, seed: seed, stations: workers,
                         era: era, registry: registry)
        }
        // …and the goods, over the furniture rather than instead of it: a
        // granary still has its scales and its shelf, it just also has the
        // grain.
        let stocked = stock.map {
            storeSlots(fullness: $0.fullness, fitting: $0.fitting, seed: seed &* 0x2545_F491)
        } ?? []
        // The goods themselves, along the back wall, before the furniture so
        // a bench stands in front of the pile rather than under it.
        for (index, heap) in goods.prefix(3).enumerated() {
            let across = -0.24 + Double(index) * 0.24
            goodsStack(&context, heap.kind,
                       at: CGPoint(x: c.x + CGFloat(across) * footprint.width,
                                   y: c.y - footprint.height * 0.30),
                       scale: min(room.width, room.height), palette: palette,
                       count: heap.count)
        }
        for slot in plan + stocked {
            let p = CGPoint(x: c.x + CGFloat(slot.dx) * footprint.width,
                            y: c.y + CGFloat(slot.dy) * footprint.height)
            // **The piece, not just the shape.** Two entries can share one
            // drawing — a plank cot and a sprung bed are both `bed` — and what
            // keeps them from being the same object on screen is the size the
            // content gave it and what it says the thing is made of.
            fitting(&context, slot.fitting, at: p,
                    scale: min(room.width, room.height) * CGFloat(slot.piece?.scale ?? 1),
                    palette: palette.tinted(slot.piece?.tint),
                    night: night, time: time, seed: seed)
        }
        walls(&context, room: room, palette: palette, seed: seed)
    }

    /// Where the colonists posted here stand, in pixels — the same slots the
    /// fittings were drawn at.
    static func stationPoints(
        glyph: SettlementRenderer.BuildingGlyph, at c: CGPoint,
        footprint: CGSize, size: CGFloat, seed: UInt64, workers: Int,
        era: Era, registry: GameDataRegistry
    ) -> [CGPoint] {
        // The same room the fittings were drawn in — a worker standing at a
        // bench that is inside the walls must be inside them too.
        let shell = SettlementStructures.bodyRect(glyph, at: c, s: size,
                                                   seed: seed, footprint: footprint)
        let room = shell.insetBy(dx: shell.width * wallInset,
                                 dy: shell.height * wallInset)
        return stationSlots(for: glyph, seed: seed, stations: workers,
                            era: era, registry: registry).map {
            CGPoint(x: room.midX + CGFloat($0.dx) * room.width,
                    y: room.midY + CGFloat($0.dy) * room.height)
        }
    }

    // MARK: - Surfaces

    struct Palette {
        let floor: Color
        let plank: Color
        let wall: Color
        let wood: Color
        let metal: Color
        let cloth: Color

        /// The same room, seen through what one piece of furniture is made of.
        ///
        /// A fitting states its `tint` and the drawings reach for
        /// `palette.wood` / `.metal` / `.cloth` by name, so the cheapest honest
        /// way to make a *metal* bench out of the wooden-bench drawing is to
        /// hand it a palette whose wood **is** the metal. The room's own
        /// materials still set the actual colours, so a smithy's iron and a
        /// hut's iron are the same iron — a fitting picks which of them it is,
        /// not what they look like.
        func tinted(_ tint: FittingDefinition.Tint?) -> Palette {
            guard let tint else { return self }
            switch tint {
            case .wood: return self
            case .metal:
                return Palette(floor: floor, plank: plank, wall: wall,
                               wood: metal, metal: metal, cloth: cloth)
            case .cloth:
                return Palette(floor: floor, plank: plank, wall: wall,
                               wood: cloth, metal: metal, cloth: cloth)
            case .stone:
                return Palette(floor: floor, plank: plank, wall: wall,
                               wood: wall, metal: metal, cloth: cloth)
            case .glow:
                // Lit from inside: the accent is the colony's own firelight, so
                // a furnace mouth and a screen are the same warm as the hearth.
                return Palette(floor: floor, plank: plank, wall: wall,
                               wood: Theme.accent.opacity(0.75), metal: metal,
                               cloth: Theme.accent.opacity(0.55))
            }
        }
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
    /// One stack of goods: shapes that read from across the valley — log ends,
    /// squared blocks, a rolled hide — rather than the same crate six times.
    static func goodsStack(
        _ context: inout GraphicsContext, _ kind: Goods, at p: CGPoint,
        scale: CGFloat, palette: Palette, count: Int
    ) {
        let s = max(2.2, scale * 0.15)
        let high = max(1, min(3, count))
        for row in 0..<high {
            let y = p.y - CGFloat(row) * s * 0.42
            switch kind {
            case .timber:
                // Log ends, seen from above the pile.
                for i in 0..<3 {
                    let x = p.x + CGFloat(i - 1) * s * 0.42
                    context.fill(Path(ellipseIn: CGRect(x: x - s * 0.19, y: y - s * 0.19,
                                                        width: s * 0.38, height: s * 0.38)),
                                 with: .color(palette.wood))
                    context.stroke(Path(ellipseIn: CGRect(x: x - s * 0.19, y: y - s * 0.19,
                                                          width: s * 0.38, height: s * 0.38)),
                                   with: .color(Theme.ink.opacity(0.4)), lineWidth: 0.4)
                }
            case .stone:
                for i in 0..<2 {
                    let r = CGRect(x: p.x + CGFloat(i) * s * 0.5 - s * 0.5,
                                   y: y - s * 0.2, width: s * 0.46, height: s * 0.36)
                    context.fill(Path(r), with: .color(palette.wall))
                    context.stroke(Path(r), with: .color(Theme.ink.opacity(0.4)), lineWidth: 0.4)
                }
            case .ore:
                for i in 0..<3 {
                    let x = p.x + CGFloat(i - 1) * s * 0.34
                    context.fill(Path(ellipseIn: CGRect(x: x - s * 0.14, y: y - s * 0.12,
                                                        width: s * 0.28, height: s * 0.24)),
                                 with: .color(Theme.boneDim.opacity(0.75)))
                }
            case .hide:
                let r = CGRect(x: p.x - s * 0.42, y: y - s * 0.16,
                               width: s * 0.84, height: s * 0.3)
                context.fill(Path(roundedRect: r, cornerRadius: s * 0.15),
                             with: .color(palette.cloth))
                context.stroke(Path(roundedRect: r, cornerRadius: s * 0.15),
                               with: .color(Theme.ink.opacity(0.35)), lineWidth: 0.4)
            case .cloth:
                let r = CGRect(x: p.x - s * 0.34, y: y - s * 0.2,
                               width: s * 0.68, height: s * 0.34)
                context.fill(Path(r), with: .color(palette.cloth.opacity(0.9)))
                context.stroke(Path(r), with: .color(Theme.bone.opacity(0.3)), lineWidth: 0.4)
            case .grain:
                let r = CGRect(x: p.x - s * 0.26, y: y - s * 0.28,
                               width: s * 0.52, height: s * 0.5)
                context.fill(Path(roundedRect: r, cornerRadius: s * 0.22),
                             with: .color(Theme.accent.opacity(0.5)))
                context.stroke(Path(roundedRect: r, cornerRadius: s * 0.22),
                               with: .color(Theme.ink.opacity(0.35)), lineWidth: 0.4)
            }
        }
    }

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
