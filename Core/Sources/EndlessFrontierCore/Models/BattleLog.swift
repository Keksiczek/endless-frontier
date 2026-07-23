import Foundation

/// One thing that happened inside a battle, stamped with *when* inside the tick
/// it happened.
public struct BattleMoment: Codable, Sendable, Equatable, Identifiable {
    /// What kind of beat this is — the canvas picks an animation by it.
    public enum Kind: String, Codable, Sendable {
        case volley      // archers loose from the wall
        case charge      // the attackers reach the line
        case clash       // melee at the palisade
        case wound       // a named defender is hurt
        case death       // …or killed
        case plunder     // stores carried off
        case repelled    // the attack breaks
    }

    public let id: Int
    /// Position inside the tick, 0…1. A tick is a real minute; this is what
    /// lets a battle be *watched* instead of appearing as a finished result.
    public let at: Double
    public let kind: Kind
    /// The colonist this beat happened to, when it happened to someone.
    public let pawnID: UUID?
    public let pawnName: String?
    /// How much was dealt, taken or carried off — damage, or goods.
    public let amount: Double

    public init(id: Int, at: Double, kind: Kind, pawnID: UUID? = nil,
                pawnName: String? = nil, amount: Double = 0) {
        self.id = id
        self.at = min(1, max(0, at))
        self.kind = kind
        self.pawnID = pawnID
        self.pawnName = pawnName
        self.amount = amount
    }
}

/// A battle as an ordered sequence of moments within a single tick.
///
/// Combat used to resolve as one arithmetic step: a strength number met a
/// defense number, some colonists lost health, and the player was told the
/// outcome. There was nothing to *watch*, and nothing a renderer could animate,
/// because no intermediate state ever existed.
///
/// This is the sub-tick layer the animated combat needs. The simulation still
/// resolves the battle entirely within one whole tick — determinism is
/// untouched, the outcome is identical whether or not anyone is looking — but
/// it now records the order and timing of what happened, so presentation can
/// play it back over real seconds. Sub-tick time lives in the *record*, not in
/// the tick loop.
public struct BattleLog: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    /// The tick this battle happened on.
    public let tick: Int
    /// Who attacked, for the headline.
    public let attackerName: String
    public let defenderName: String
    public let moments: [BattleMoment]
    public let repelled: Bool

    public init(id: UUID, tick: Int, attackerName: String, defenderName: String,
                moments: [BattleMoment], repelled: Bool) {
        self.id = id
        self.tick = tick
        self.attackerName = attackerName
        self.defenderName = defenderName
        self.moments = moments.sorted { $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at }
        self.repelled = repelled
    }

    /// The moments that have played by a given point inside the tick.
    public func moments(upTo progress: Double) -> [BattleMoment] {
        moments.filter { $0.at <= progress }
    }

    public var deaths: Int { moments.count { $0.kind == .death } }
    public var wounded: Int { moments.count { $0.kind == .wound } }
    public var plunder: Double { moments.first { $0.kind == .plunder }?.amount ?? 0 }
}
