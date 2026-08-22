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
    /// **Who spoke, and why.** Keks: *"sněm by mohl být dynamický, že by lidé
    /// volili dle svých vlastností, zkušeností, názorů."* The count alone
    /// cannot say that — two hundred and eleven against two hundred and four
    /// is a number, and *"Mara, sedlák, byla proti: to je práce navíc"* is an
    /// assembly. Capped at `AssemblyEngine.voicesKept`, loudest first: a town
    /// of four hundred writes four hundred lines into every save otherwise.
    public var voices: [AssemblyVoice] = []
    /// How many adults were in the room at all, which the tallies cannot say
    /// because a vote is weighted by class (`WealthClass.votes`).
    public var turnout: Int = 0

    public var councilApproves: Bool { votesFor > votesAgainst }

    public init(
        definitionID: String,
        settlementID: UUID,
        proposedTick: Int,
        votesFor: Int,
        votesAgainst: Int,
        voices: [AssemblyVoice] = [],
        turnout: Int = 0
    ) {
        self.definitionID = definitionID
        self.settlementID = settlementID
        self.proposedTick = proposedTick
        self.votesFor = votesFor
        self.votesAgainst = votesAgainst
        self.voices = voices
        self.turnout = turnout
    }

    private enum CodingKeys: String, CodingKey {
        case definitionID, settlementID, proposedTick, votesFor, votesAgainst
        case voices, turnout
    }

    /// Hand-written, because a synthesised decoder demands every key and a
    /// motion already on the table when the update lands is a decision the
    /// player cannot shrug off (rule 37).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        definitionID = try c.decode(String.self, forKey: .definitionID)
        settlementID = try c.decode(UUID.self, forKey: .settlementID)
        proposedTick = try c.decode(Int.self, forKey: .proposedTick)
        votesFor = try c.decode(Int.self, forKey: .votesFor)
        votesAgainst = try c.decode(Int.self, forKey: .votesAgainst)
        voices = try c.decodeIfPresent([AssemblyVoice].self, forKey: .voices) ?? []
        turnout = try c.decodeIfPresent(Int.self, forKey: .turnout) ?? 0
    }
}

/// **One colonist's vote, and the thing that decided it.**
///
/// Kept as a record rather than recomputed, because the assembly sits once and
/// the world moves on: by the time the player opens the council screen the
/// woman who spoke may be hungrier, richer or dead, and the motion is still
/// the motion she spoke on.
public struct AssemblyVoice: Codable, Sendable, Equatable, Identifiable {
    public let pawnID: UUID
    public let name: String
    /// What they do for a living, which is most of what an ordinary person's
    /// politics is about.
    public let trade: WorkKind
    public let wealth: WealthClass
    public let forIt: Bool
    /// The term that moved them furthest from the middle. Not the whole of
    /// their reasoning — the *loudest* part of it, which is what somebody
    /// would actually say if asked.
    public let reason: VoteReason
    /// How far from the middle they ended up, 0…1. A colonist at 0.02 said
    /// "if you like"; one at 0.4 stood up.
    public let conviction: Double

    public var id: UUID { pawnID }

    public init(pawnID: UUID, name: String, trade: WorkKind, wealth: WealthClass,
                forIt: Bool, reason: VoteReason, conviction: Double) {
        self.pawnID = pawnID
        self.name = name
        self.trade = trade
        self.wealth = wealth
        self.forIt = forIt
        self.reason = reason
        self.conviction = conviction
    }
}

/// Why somebody voted the way they did — the shortest true answer.
public enum VoteReason: String, Codable, Sendable, CaseIterable {
    /// The kind of person they are. `LawDefinition.voteBias` against their genes.
    case nature
    /// What it would mean for their work.
    case trade
    /// Rich or poor, and which way this law cuts.
    case standing
    /// Years and skill — somebody who has done the work long enough to have
    /// seen this tried before.
    case experience
    /// Hungry, hurt, sleeping rough. People who are suffering want change.
    case hardship
    /// Their household voted this way, and so did they.
    case household
    /// They are the Leader, or they are the Leader's.
    case leader
    /// Nothing much moved them either way.
    case undecided
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
