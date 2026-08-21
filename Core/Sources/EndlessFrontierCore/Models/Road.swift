import Foundation

/// **A made way between two neighbouring hexes.**
///
/// The world map had no road concept at all, and three systems were the poorer
/// for it, each in the same way — *distance was a number nobody could change*:
///
/// - `RegionExpeditionEngine.travelTicks` is `hexes × travelTicksPerHex`, so a
///   party crossing a fen and a party crossing a plain took the same time and
///   nothing the colony built could ever make either quicker.
/// - `TradeRoute` names an origin and a destination and **no path**, so a route
///   through a mountain range and a route to next door cost the same.
/// - Forty-six conveyances carry a `regionPace` from 0.7 to 50, and the world
///   had nowhere for a lorry to be faster than a mule. The bank was content
///   with no reader — the shape `docs/HANDOFF-GENERATION.md` warns about.
///
/// A road is deliberately **per edge**, not per journey. You build the piece
/// between here and the next hex, and a route is a chain of pieces that grows
/// as the colony can afford it — so a half-finished road is a real state, and
/// so is a road somebody has cut.
public struct RoadLink: Codable, Sendable, Equatable, Identifiable {
    /// Stable and derived, never random: the id is the two coords in a fixed
    /// order, so two worlds from one seed build the same roads under the same
    /// names (rule 3, and `GameWorldFactory`'s founding UUIDs learned it the
    /// hard way).
    public var id: String { RoadLink.key(a, b) }

    /// The two ends, always stored in canonical order so `a→b` and `b→a` are
    /// one road and not two.
    public let a: HexCoord
    public let b: HexCoord
    public var grade: RoadGrade
    /// How sound it is, 0…1. A road is a building lying on its side: weather
    /// takes it, and a way nobody mends goes back to being country.
    public var condition: Double
    /// Who laid it. See `RoadOrigin` — the difference is not cosmetic.
    public var origin: RoadOrigin

    public init(a: HexCoord, b: HexCoord, grade: RoadGrade = .track,
                condition: Double = 1, origin: RoadOrigin = .built) {
        let (first, second) = RoadLink.ordered(a, b)
        self.a = first
        self.b = second
        self.grade = grade
        self.condition = max(0, min(1, condition))
        self.origin = origin
    }

    // Resilient decode: `origin` postdates every road already in a save, and
    // everything in one was laid by somebody who is still alive.
    private enum CodingKeys: String, CodingKey { case a, b, grade, condition, origin }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        a = try c.decode(HexCoord.self, forKey: .a)
        b = try c.decode(HexCoord.self, forKey: .b)
        grade = try c.decode(RoadGrade.self, forKey: .grade)
        condition = try c.decode(Double.self, forKey: .condition)
        origin = try c.decodeIfPresent(RoadOrigin.self, forKey: .origin) ?? .built
    }

    /// Canonical ordering, so a link is the same link whichever way you name
    /// it. Sorted by q then r — any total order would do; this one is stable
    /// across launches, which `String.hashValue` would not be.
    static func ordered(_ x: HexCoord, _ y: HexCoord) -> (HexCoord, HexCoord) {
        if x.q != y.q { return x.q < y.q ? (x, y) : (y, x) }
        return x.r <= y.r ? (x, y) : (y, x)
    }

    public static func key(_ x: HexCoord, _ y: HexCoord) -> String {
        let (first, second) = ordered(x, y)
        return "\(first.q),\(first.r)|\(second.q),\(second.r)"
    }

    /// The end that is not this one, or `nil` if the coord is not on this link.
    public func other(than coord: HexCoord) -> HexCoord? {
        if coord == a { return b }
        if coord == b { return a }
        return nil
    }

    /// What this road is worth to somebody travelling it *today*.
    ///
    /// A ruined road is not a road. Condition scales the whole benefit rather
    /// than being a separate subtraction, so a paved way at half condition is
    /// still better than a track in good order and worse than a paved way that
    /// has been kept — which is the ordering that makes maintenance a decision.
    public var effectiveSpeed: Double {
        1 + (grade.speed - 1) * max(0, min(1, condition))
    }
}

/// Who made a way, which decides what weather is still allowed to do to it.
public enum RoadOrigin: String, Codable, Sendable, Equatable {
    /// Laid by somebody in this world's own history — the council, the player,
    /// a gesture to a neighbour. Weather takes it back if nobody keeps it.
    case built
    /// **Already there when the first colonist arrived.** A stone way running
    /// out of empty country into more empty country, with nothing at either
    /// end that anybody now living remembers.
    ///
    /// It does not wear away below `RoadEngine.ancientFloor`, and the reason is
    /// not a special case for the sake of one: everything weather was going to
    /// take from it, weather took centuries ago. What is left is the bed, and a
    /// bed is what makes an old road worth finding — building on one is
    /// cheaper, because the hard half of the work is done.
    case ancient
}

/// How much of a road it is. Each grade is a real step, not a multiplier on the
/// last one: a track is feet wearing a line, a road is somebody having levelled
/// and drained it, paving is stone, and rail is a different thing again.
public enum RoadGrade: String, Codable, Sendable, CaseIterable, Comparable {
    /// Beaten by use. Free, and it appears where traffic goes.
    case track
    /// Levelled, drained, and wide enough for a cart.
    case road
    /// Stone or macadam. What a motor wants under it.
    case paved
    /// Track and sleepers. Only a `rail` conveyance may use it, and it is the
    /// fastest thing the world has.
    case rail

    /// How many times faster than open country. Travel time divides by this,
    /// so a `road` halves it.
    public var speed: Double {
        switch self {
        case .track: return 1.35
        case .road:  return 2.0
        case .paved: return 2.8
        case .rail:  return 4.5
        }
    }

    /// Materials to lay one hex of it. A track costs nothing because nobody
    /// builds one — see `RoadEngine.wear`.
    public var cost: Double {
        switch self {
        case .track: return 0
        case .road:  return 30
        case .paved: return 70
        case .rail:  return 160
        }
    }

    /// The earliest age that can lay this. Rail is not a medieval idea.
    public var era: Era {
        switch self {
        case .track: return .earlySettlement
        case .road:  return .ancient
        case .paved: return .medieval
        case .rail:  return .earlyIndustrial
        }
    }

    /// What must be known first. `nil` for what needs no learning.
    ///
    /// A road wanted `the_wheel` and that was wrong twice over. Wrong in
    /// fiction — a levelled, drained way is older than the cart, and people
    /// made roads to walk on. And wrong in the tree: **`the_wheel` is a leaf**
    /// that nothing else requires, so a colony researching its way toward steam
    /// never picks it up, and `RoadProbe` duly showed a world laying railways
    /// and paved ways with not one road under either. Levelling ground needs
    /// no learning; it needs somebody to decide it is worth the labour.
    public var requiresTech: String? {
        switch self {
        case .track: return nil
        case .road:  return nil
        case .paved: return "masonry"
        case .rail:  return "railways"
        }
    }

    /// How fast weather takes it back. Stone lasts; a levelled track does not.
    public var wearPerTick: Double {
        switch self {
        case .track: return 0.0016
        case .road:  return 0.0009
        case .paved: return 0.0004
        case .rail:  return 0.0006
        }
    }

    public var displayName: LocalizedText {
        switch self {
        case .track: return LocalizedText(values: [.en: "Track", .cs: "Vyšlapaná cesta"])
        case .road:  return LocalizedText(values: [.en: "Road", .cs: "Cesta"])
        case .paved: return LocalizedText(values: [.en: "Paved Road", .cs: "Dlážděná silnice"])
        case .rail:  return LocalizedText(values: [.en: "Railway", .cs: "Železnice"])
        }
    }

    public static func < (lhs: RoadGrade, rhs: RoadGrade) -> Bool {
        lhs.speed < rhs.speed
    }
}

/// **What the country charges to cross it.**
///
/// The other half of a road being worth building: open ground is not all the
/// same, so a road through a fen buys far more than a road across a plain, and
/// a pass is the only place a range can be crossed at all.
///
/// Read off the biome and the land's own `RegionFeature`, both of which already
/// exist and are already derived from elevation, moisture and warmth — so this
/// can never disagree with the country the generator drew.
public enum TerrainCost {
    /// Multiplier on the time to cross one hex of open country.
    public static func of(_ region: Region) -> Double {
        biome(region.biomeID) * feature(region.feature)
    }

    static func biome(_ id: String) -> Double {
        switch id {
        case "plains":    return 1.0
        case "coast":     return 1.15
        case "forest":    return 1.35
        case "desert":    return 1.5
        case "tundra":    return 1.6
        // The two the roads exist for. A fen is the worst ground in the game to
        // move an army or a cart across, and it is *why* a colony founded on one
        // trades instead of hauling.
        case "wetlands":  return 2.1
        case "mountains": return 2.4
        default:          return 1.0
        }
    }

    static func feature(_ feature: RegionFeature?) -> Double {
        switch feature {
        case .none:            return 1
        // A pass is the whole reason a range is passable: it takes the
        // mountain penalty most of the way off, which is what makes the hex
        // worth holding and worth fighting over.
        case .some(.pass):     return 0.55
        case .some(.oasis):    return 0.8
        case .some(.plateau):  return 1.1
        case .some(.headland): return 1.15
        case .some(.craterLake): return 1.4
        case .some(.gorge):    return 1.7
        case .some(.fen):      return 1.8
        case .some(.peak):     return 2.2
        }
    }

    /// What it costs to *lay* a road here, as a multiple of the grade's price.
    /// Hard country is dear to build through as well as slow to cross, so the
    /// pass a road most wants is also the piece that takes longest to earn.
    public static func buildingCost(_ region: Region) -> Double {
        // Sub-linear in the crossing cost: a fen is twice as slow to walk and
        // about half again as dear to bridge, not twice. Otherwise the one
        // road worth having is the one nobody can ever afford (rule 21).
        1 + (of(region) - 1) * 0.6
    }
}
