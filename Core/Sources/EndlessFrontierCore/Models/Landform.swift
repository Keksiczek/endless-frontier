import Foundation

/// A piece of country with **extent** — a ravine, an oasis, a mesa, the walls
/// of something older.
///
/// Keks: *"geograficke formace na mapach že tam bude fyzicky … co je v simulaci
/// to je na plátně."* The valley had two ways of holding a feature and neither
/// was this. `SceneryProp` is decoration and says so in its own doc comment — no
/// simulation effect, drawn and nothing more. `LocalPOI` *is* simulation, but a
/// POI is a **point**: somewhere to send a party, with no ground under it. What
/// was missing is the thing in between — country that occupies cells, that a
/// walker has to go round, and that the canvas draws because it is there rather
/// than because it looks nice.
///
/// Cells are `LocalMap` indices, the same space `StoneField` uses, so a landform
/// and a massif are the same kind of claim on the ground and the router treats
/// them alike (`ColonyRoute.Occupancy`).
public enum LandformKind: String, Codable, Sendable, CaseIterable {
    /// Water and shade in dry country. Passable — and the reason a desert
    /// colony is somewhere rather than nowhere.
    case oasis
    /// A cut in the ground. Not passable, and the most useful landform for
    /// exactly that reason: it makes a valley a shape rather than a field.
    case ravine
    /// A flat-topped block of rock standing out of flat country. Not passable.
    case mesa
    /// Walls, low and roofless, of something that stood here first. Partly
    /// passable — you walk the streets, not the walls.
    case ruinField
    /// A bowl of sheltered ground, out of the wind. Passable.
    case hollow

    /// Whether a walker has to go round it.
    ///
    /// This is the whole difference between a landform and a scenery prop: a
    /// prop is a picture, and this is ground somebody cannot cross.
    public var blocksMovement: Bool {
        switch self {
        case .ravine, .mesa: return true
        // You can walk into an oasis, a hollow, or the streets of a ruin —
        // and the ruin's *walls* are drawn standing without claiming the whole
        // footprint, or a big ruin would wall a colony out of its own valley.
        case .oasis, .hollow, .ruinField: return false
        }
    }

    public var displayName: LocalizedText {
        switch self {
        case .oasis: return LocalizedText(values: [.en: "An oasis", .cs: "Oáza"])
        case .ravine: return LocalizedText(values: [.en: "A ravine", .cs: "Rokle"])
        case .mesa: return LocalizedText(values: [.en: "A mesa", .cs: "Stolová hora"])
        case .ruinField: return LocalizedText(values: [.en: "Old walls", .cs: "Staré zdi"])
        case .hollow: return LocalizedText(values: [.en: "A hollow", .cs: "Úval"])
        }
    }

    /// What it means for the colony, said in a line.
    public var note: LocalizedText {
        switch self {
        case .oasis:
            return LocalizedText(values: [.en: "water, in country that has none",
                                          .cs: "voda tam, kde žádná není"])
        case .ravine:
            return LocalizedText(values: [.en: "nobody crosses this",
                                          .cs: "tudy nikdo neprojde"])
        case .mesa:
            return LocalizedText(values: [.en: "rock, and a wall at your back",
                                          .cs: "kámen, a hradba za zády"])
        case .ruinField:
            return LocalizedText(values: [.en: "somebody built here before you",
                                          .cs: "někdo tu stavěl před tebou"])
        case .hollow:
            return LocalizedText(values: [.en: "out of the wind",
                                          .cs: "mimo vítr"])
        }
    }

    /// Which countries grow this, and how likely it is per map.
    func chance(in biomeID: String) -> Double {
        switch (self, biomeID) {
        case (.oasis, "desert"): return 0.85
        case (.oasis, _): return 0
        case (.mesa, "desert"): return 0.55
        case (.mesa, "plains"), (.mesa, "homeland"): return 0.25
        case (.mesa, _): return 0.10
        case (.ravine, "mountains"): return 0.70
        case (.ravine, "tundra"), (.ravine, "forest"): return 0.35
        case (.ravine, _): return 0.25
        case (.hollow, "tundra"), (.hollow, "mountains"): return 0.45
        case (.hollow, _): return 0.30
        // Old walls belong to nowhere in particular — somebody built
        // everywhere, which is rather the point of them.
        case (.ruinField, _): return 0.30
        }
    }
}

/// One landform standing on the local map.
public struct Landform: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let kind: LandformKind
    /// The cells it covers, as `LocalMap` indices.
    public var cells: Set<Int>
    /// Its middle, for labelling and for sending somebody to it.
    public let centre: LocalPoint

    public init(id: Int, kind: LandformKind, cells: Set<Int>, centre: LocalPoint) {
        self.id = id
        self.kind = kind
        self.cells = cells
        self.centre = centre
    }

    public var isEmpty: Bool { cells.isEmpty }

    /// Whether a point falls on this landform.
    public func contains(_ point: LocalPoint) -> Bool {
        cells.contains(LocalMap.cellIndex(point))
    }

    /// Whether a point falls on ground a walker cannot cross.
    public func blocks(_ point: LocalPoint) -> Bool {
        kind.blocksMovement && contains(point)
    }
}

/// Builds the country's shapes deterministically — same seed, same land.
public enum LandformFactory {

    /// The biggest a landform gets, in cells. A ravine that took a third of the
    /// map would wall the colony in, and the fallback for "no way round" is to
    /// walk straight through (rule 22) — which would put the feature back to
    /// being decoration.
    static let mostCells = 34

    /// The most country one valley stands up.
    ///
    /// Was two, and two was chosen when the colony took a 0.58 span of the map:
    /// with the valley doubled there is genuinely more ground to put things on,
    /// and a map with one feature on it reads the same as a map with none. Still
    /// bounded, because a valley with a ravine *and* a mesa *and* old walls
    /// *and* an oasis is a theme park rather than a place.
    static let mostForms = 4

    /// What a fresh map stands up, given its country.
    ///
    /// **Two things made every valley look like every other valley**, and
    /// neither was the number of kinds:
    ///
    /// 1. The kinds were asked in `allCases` order and the loop stopped at two.
    ///    So the *first* kinds in the source file — an oasis, a ravine — took
    ///    both slots whenever they rolled, and a hollow was very nearly
    ///    unreachable. The list was a priority queue and nobody meant it to be.
    /// 2. Every form that was not a ravine was the same round blob of the same
    ///    ten-to-twenty-six cells. One shape, one size.
    ///
    /// So the order is shuffled from the map's own seed, and a form picks a
    /// *shape* as well as a place. Deterministic throughout: the shuffle is a
    /// seeded sort, so one seed is one valley for ever (rule 3).
    public static func forMap(biomeID: String, rng: inout SeededRNG) -> [Landform] {
        var forms: [Landform] = []
        var taken: Set<Int> = []
        // A shuffle, not source order — but a *seeded* one, so the sequence is
        // fixed for a given world and varies between worlds.
        var rolled: [(kind: LandformKind, roll: Double)] = []
        for kind in LandformKind.allCases { rolled.append((kind, rng.nextUnit())) }
        rolled.sort { a, b in
            a.roll == b.roll ? a.kind.rawValue < b.kind.rawValue : a.roll < b.roll
        }
        let order: [LandformKind] = rolled.map(\.kind)
        for kind in order where forms.count < mostForms {
            guard rng.nextUnit() < kind.chance(in: biomeID) else { continue }
            let form = blob(kind: kind, id: forms.count, avoiding: taken, rng: &rng)
            guard !form.isEmpty else { continue }
            taken.formUnion(form.cells)
            forms.append(form)
        }
        return forms
    }

    /// The shape a piece of country takes.
    ///
    /// Country is not all one shape, and until now it was: a ravine walked in a
    /// line and everything else was a random-walk blob. These are the four
    /// shapes that read differently at a glance from across the valley.
    enum Shape: CaseIterable {
        /// Long and thin — a cut, a seam, a wall of old stone.
        case vein
        /// Round and solid — a bowl, a stand of rock, a pool.
        case round
        /// Long *and* thick: a ridge you go round rather than a line you step
        /// over.
        case ridge
        /// Several lobes with gaps between them — a broken field, the shape old
        /// walls actually leave behind.
        case scatter
    }

    /// Which shapes a kind of country comes in. A ravine is always a cut; a
    /// ruin field is always broken; the rest can be either of two things, which
    /// is where the variety comes from.
    static func shapes(for kind: LandformKind) -> [Shape] {
        switch kind {
        case .ravine:    return [.vein, .vein, .ridge]      // usually a cut
        case .ruinField: return [.scatter, .scatter, .vein] // usually broken
        case .mesa:      return [.round, .ridge]
        case .oasis:     return [.round, .scatter]
        case .hollow:    return [.round, .vein]
        }
    }

    /// A patch of country around a seeded point, grown by walking outward.
    ///
    /// Kept **off the town's ground**. The colony builds outward from the heart
    /// and its grid now reaches `SettlementGeometry.span / 2` in each direction;
    /// a ravine through the settlement's own building land is not a feature, it
    /// is a bug report. The old radius band (0.26…0.42) was clear of a 0.58 span
    /// and sits squarely inside an 0.82 one, so it moves out with the town.
    static func blob(kind: LandformKind, id: Int, avoiding taken: Set<Int>,
                     rng: inout SeededRNG) -> Landform {
        let angle = rng.nextUnit() * 2 * .pi
        let clear = SettlementGeometry.span / 2 + 0.04
        let radius = clear + rng.nextUnit() * (0.60 - clear)
        let centre = LocalPoint(
            x: min(0.94, max(0.06, 0.5 + cos(angle) * radius)),
            y: min(0.92, max(0.08, 0.52 + sin(angle) * radius * 0.8)))

        let shapes = shapes(for: kind)
        let shape = shapes[min(shapes.count - 1, Int(rng.nextUnit() * Double(shapes.count)))]
        // Size varies with the shape as well as with the roll: a vein is a line
        // and needs length, a scatter needs enough cells to break into pieces.
        let floor = shape == .scatter ? 14 : 9
        let want = floor + Int(rng.nextUnit() * Double(mostCells - floor))
        var cells: Set<Int> = []
        var cursor = LocalMap.cellIndex(centre)
        let drift = rng.nextUnit() < 0.5 ? 1 : -1
        let fall = rng.nextUnit() < 0.5 ? 1 : -1

        for step in 0..<want {
            if !taken.contains(cursor) { cells.insert(cursor) }
            var column = cursor % LocalMap.gridColumns
            var row = cursor / LocalMap.gridColumns
            switch shape {
            case .vein:
                column += drift
                if step % 3 == 0 { row += rng.nextUnit() < 0.5 ? 1 : -1 }
            case .round:
                column += rng.nextUnit() < 0.5 ? 1 : -1
                row += rng.nextUnit() < 0.5 ? 1 : -1
            case .ridge:
                // A line with width: it walks along, and every other cell it
                // also claims the one beside it.
                column += drift
                if step % 2 == 0 {
                    let beside = row + fall
                    if beside >= 0, beside < LocalMap.gridRows {
                        let index = beside * LocalMap.gridColumns + column
                        if !taken.contains(index) { cells.insert(index) }
                    }
                }
                if step % 4 == 0 { row += fall }
            case .scatter:
                // Lobes: it walks a few cells, then hops a gap and starts
                // again, which is what a broken field looks like from above.
                if step % 5 == 4 {
                    column += drift * 2
                    row += rng.nextUnit() < 0.5 ? 2 : -2
                } else {
                    column += rng.nextUnit() < 0.5 ? 1 : -1
                    row += rng.nextUnit() < 0.5 ? 1 : -1
                }
            }
            guard column >= 0, column < LocalMap.gridColumns,
                  row >= 0, row < LocalMap.gridRows else { break }
            cursor = row * LocalMap.gridColumns + column
        }
        return Landform(id: id, kind: kind, cells: cells, centre: centre)
    }
}
