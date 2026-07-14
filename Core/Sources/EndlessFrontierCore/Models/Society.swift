import Foundation

/// A colonist's standing, derived from their wealth relative to their
/// neighbours: the poorest 40 %, the middle, and the top 15 %.
public enum WealthClass: String, Codable, Sendable, CaseIterable {
    case poor
    case middle
    case wealthy

    /// The wealthy carry a second voice in the assembly — the inequality of
    /// influence that makes revolts feel earned.
    public var votes: Int { self == .wealthy ? 2 : 1 }
}

/// A law the assembly has passed, and when it lapses.
public struct LawInstance: Codable, Sendable, Equatable, Identifiable {
    public let definitionID: String
    public let enactedTick: Int
    public let expiresTick: Int

    public var id: String { definitionID }

    public init(definitionID: String, enactedTick: Int, expiresTick: Int) {
        self.definitionID = definitionID
        self.enactedTick = enactedTick
        self.expiresTick = expiresTick
    }
}

/// A motion the assembly has debated and put before the leader — the player.
/// The council has already voted; the leader may ratify or veto, and either
/// choice against the assembly's will costs standing.
public struct LawProposal: Codable, Sendable, Equatable {
    public let definitionID: String
    public let settlementID: UUID
    public let proposedTick: Int
    public let votesFor: Int
    public let votesAgainst: Int

    public var councilApproves: Bool { votesFor > votesAgainst }

    public init(
        definitionID: String,
        settlementID: UUID,
        proposedTick: Int,
        votesFor: Int,
        votesAgainst: Int
    ) {
        self.definitionID = definitionID
        self.settlementID = settlementID
        self.proposedTick = proposedTick
        self.votesFor = votesFor
        self.votesAgainst = votesAgainst
    }
}

/// The distributional shape of a settlement's wealth: the Gini coefficient and
/// the class boundaries it implies. Recomputed once a year.
public struct SocietyStats: Codable, Sendable, Equatable {
    /// 0 = perfect equality, 1 = one colonist owns everything.
    public var gini: Double
    /// The 40th and 85th wealth percentiles — the class boundaries.
    public var poorCeiling: Double
    public var wealthyFloor: Double
    /// Lifetime count of uprisings, for the chronicle.
    public var revolts: Int

    public init(gini: Double = 0, poorCeiling: Double = 0, wealthyFloor: Double = 0, revolts: Int = 0) {
        self.gini = gini
        self.poorCeiling = poorCeiling
        self.wealthyFloor = wealthyFloor
        self.revolts = revolts
    }

    /// Which class a given wealth falls into.
    public func wealthClass(of wealth: Double) -> WealthClass {
        if wealth < poorCeiling { return .poor }
        if wealth < wealthyFloor { return .middle }
        return .wealthy
    }
}
