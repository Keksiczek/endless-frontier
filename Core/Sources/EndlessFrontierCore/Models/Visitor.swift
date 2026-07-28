import Foundation

/// Somebody from outside, on your ground.
///
/// The world beyond the valley has existed for a long time — tribes with names
/// and grudges, trade routes, marriages, wars — and none of it ever *arrived*.
/// It was a panel. You read that the Kamenní were wary of you the way you read
/// a spreadsheet, and the only outsiders who ever set foot on the map were
/// raiders.
///
/// A `Visitor` is a party walking in over your own ground: traders with mules,
/// an envoy with a retinue, refugees from a hard winter somewhere else. They
/// come in from the edge, do their business at the heart of the town, and go
/// back the way they came. What they *do* is the same diplomacy and trade the
/// panel always described — it simply happens to somebody, somewhere, in front
/// of you.
public enum VisitorKind: String, Codable, Sendable, CaseIterable {
    /// Goods for goods. Arrives where there is something worth coming for.
    case trader
    /// A word from a neighbouring people, and what they think of you.
    case envoy
    /// Somebody else's bad winter, at your gate.
    case refugee
    /// A traveller with nothing to sell and a story worth hearing.
    case wanderer

    /// How many walk in together.
    public var partySize: Int {
        switch self {
        case .trader: return 3
        case .envoy: return 4
        case .refugee: return 3
        case .wanderer: return 1
        }
    }

    /// Whether they lead pack animals — drawn, and the reason a trader reads as
    /// a trader from across the valley.
    public var hasPackAnimals: Bool {
        switch self {
        case .trader: return true
        case .envoy, .refugee, .wanderer: return false
        }
    }

    public var displayName: LocalizedText {
        switch self {
        case .trader: return LocalizedText(values: [.en: "Traders", .cs: "Obchodníci"])
        case .envoy: return LocalizedText(values: [.en: "An envoy", .cs: "Vyslanec"])
        case .refugee: return LocalizedText(values: [.en: "Refugees", .cs: "Uprchlíci"])
        case .wanderer: return LocalizedText(values: [.en: "A wanderer", .cs: "Poutník"])
        }
    }
}

/// Where a visiting party is in its visit.
public enum VisitorPhase: String, Codable, Sendable {
    /// Walking in from the edge of the map.
    case arriving
    /// Standing in the square, doing whatever they came to do.
    case visiting
    /// Walking back out.
    case leaving
}

/// One party of outsiders on a settlement's local map.
public struct Visitor: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let kind: VisitorKind
    /// Who they are from — a tribe's own name, so the journal can say it.
    public let fromName: String
    /// The tribe they belong to, when they belong to one. Nil for a wanderer.
    public let tribeID: UUID?
    /// Where the party is right now, in the local map's normalised space.
    public var position: LocalPoint
    /// The edge they came in by, and will go back out by.
    public let entry: LocalPoint
    public var phase: VisitorPhase
    /// Ticks left standing in the square before they start home.
    public var ticksRemaining: Int
    /// Whether the business has been done. A visit pays once.
    public var settled: Bool

    public init(id: UUID, kind: VisitorKind, fromName: String, tribeID: UUID? = nil,
                position: LocalPoint, entry: LocalPoint,
                phase: VisitorPhase = .arriving, ticksRemaining: Int = 0,
                settled: Bool = false) {
        self.id = id
        self.kind = kind
        self.fromName = fromName
        self.tribeID = tribeID
        self.position = position
        self.entry = entry
        self.phase = phase
        self.ticksRemaining = ticksRemaining
        self.settled = settled
    }
}
