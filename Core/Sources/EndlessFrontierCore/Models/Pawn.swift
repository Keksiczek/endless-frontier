import Foundation

/// A kind of work a colonist can be assigned to. Each maps to the resource it
/// helps produce (idle produces nothing).
public enum WorkKind: String, Codable, Sendable, CaseIterable, Equatable {
    case farming
    case logging
    case mining
    case research
    case trade
    case idle

    /// The resource this work contributes to, if any.
    public var resource: ResourceType? {
        switch self {
        case .farming: return .food
        case .logging, .mining: return .materials
        case .research: return .knowledge
        case .trade: return .influence
        case .idle: return nil
        }
    }
}

/// A colonist's needs, each on a 0–100 scale where 100 is fully satisfied.
public struct PawnNeeds: Codable, Sendable, Equatable {
    public var hunger: Double
    public var rest: Double
    public var recreation: Double

    public init(hunger: Double = 80, rest: Double = 80, recreation: Double = 70) {
        self.hunger = hunger
        self.rest = rest
        self.recreation = recreation
    }

    /// The average satisfaction across needs — the basis for mood.
    public var average: Double {
        (hunger + rest + recreation) / 3
    }

    public func clamped() -> PawnNeeds {
        func c(_ v: Double) -> Double { min(max(v, 0), 100) }
        return PawnNeeds(hunger: c(hunger), rest: c(rest), recreation: c(recreation))
    }
}

/// Selects which colonist(s) a pawn-targeting event effect applies to.
/// Deterministic — no randomness — so the simulation stays reproducible.
public enum PawnSelector: String, Codable, Sendable, Equatable {
    case all
    case first
    case lowestHealth = "lowest_health"
    case lowestMood = "lowest_mood"
}

/// A personality trait that shifts mood and (optionally) skill aptitude.
public enum PawnTrait: String, Codable, Sendable, CaseIterable, Equatable {
    case optimist
    case pessimist
    case hardWorker = "hard_worker"
    case lazy
    case none

    /// Flat mood modifier applied on top of need satisfaction.
    public var moodModifier: Double {
        switch self {
        case .optimist: return 8
        case .pessimist: return -8
        default: return 0
        }
    }
}

/// A named colonist — the individual unit of a RimWorld-style colony. Pawns
/// are simulated on top of the macro `Settlement.population` headcount: they
/// are the characters the player manages and the narrator can talk about.
public struct Pawn: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var trait: PawnTrait
    public var skills: [WorkKind: Int]   // 0…20 per work kind
    public var skillXP: [WorkKind: Double]  // progress toward the next level
    public var needs: PawnNeeds
    public var mood: Double              // 0…100, derived from needs + trait
    public var assignedWork: WorkKind
    public var health: Double            // 0…100
    public var isBroken: Bool            // mental break — stops working until mood recovers

    public init(
        id: UUID = UUID(),
        name: String,
        trait: PawnTrait = .none,
        skills: [WorkKind: Int] = [:],
        skillXP: [WorkKind: Double] = [:],
        needs: PawnNeeds = PawnNeeds(),
        mood: Double = 70,
        assignedWork: WorkKind = .idle,
        health: Double = 100,
        isBroken: Bool = false
    ) {
        self.id = id
        self.name = name
        self.trait = trait
        self.skills = skills
        self.skillXP = skillXP
        self.needs = needs
        self.mood = mood
        self.assignedWork = assignedWork
        self.health = health
        self.isBroken = isBroken
    }

    public func skill(_ kind: WorkKind) -> Int { skills[kind] ?? 0 }
}
