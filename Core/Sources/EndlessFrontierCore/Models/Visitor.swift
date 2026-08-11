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
    /// A family that heard the place was doing well, and has come to stay.
    ///
    /// The only visitor who comes for the colony *itself* rather than out of
    /// somebody else's politics: no tribe sends them, and what decides whether
    /// they come at all is what the colony looks like from outside — full
    /// larder, spare beds, people in good heart. They are also the only kind
    /// who never leave.
    case settler

    /// How many walk in together.
    public var partySize: Int {
        switch self {
        case .trader: return 3
        case .envoy: return 4
        case .refugee: return 3
        case .wanderer: return 1
        // A household: two who came together, sometimes with a child. Small on
        // purpose — §11.2 asked for a village you can hold in your head, so
        // arrivals have to be memorable rather than a faucet.
        case .settler: return 2
        }
    }

    /// Whether they lead pack animals — drawn, and the reason a trader reads as
    /// a trader from across the valley.
    public var hasPackAnimals: Bool {
        switch self {
        case .trader: return true
        // Everything they own is on the handcart, which is the picture.
        case .settler: return true
        case .envoy, .refugee, .wanderer: return false
        }
    }

    public var displayName: LocalizedText {
        switch self {
        case .trader: return LocalizedText(values: [.en: "Traders", .cs: "Obchodníci"])
        case .envoy: return LocalizedText(values: [.en: "An envoy", .cs: "Vyslanec"])
        case .refugee: return LocalizedText(values: [.en: "Refugees", .cs: "Uprchlíci"])
        case .wanderer: return LocalizedText(values: [.en: "A wanderer", .cs: "Poutník"])
        case .settler: return LocalizedText(values: [.en: "Settlers", .cs: "Osadníci"])
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
    ///
    /// This is the *simulation's* answer, on the tick — what everything that
    /// reasons about a visit reads. What the canvas draws is `walk`.
    public var position: LocalPoint
    /// The leg they just walked, so the canvas can draw them crossing the
    /// ground instead of standing still and jumping.
    ///
    /// A tick is two real minutes and a party moved one stride per tick, so a
    /// visitor stood frozen for two minutes at a time. This is the same fix
    /// `Pawn.haulWalk` got, in the shape that suits a walker whose next target
    /// is not known in advance: the leg runs from where they were to where they
    /// now are, and the canvas asks for a *fraction* of it. Nil until they have
    /// taken their first step — and in a save written before this, which is
    /// simply a party standing at `position` until they next move.
    public var walk: WalkPath?
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
                settled: Bool = false, walk: WalkPath? = nil) {
        self.walk = walk
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

    /// Where to draw them at a *continuous* tick. Falls back to the tick's own
    /// answer for a party that has not moved yet, or one out of an old save.
    public func position(at tick: Double) -> LocalPoint {
        walk?.position(at: tick) ?? position
    }
}
