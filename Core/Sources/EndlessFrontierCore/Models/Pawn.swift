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

/// A named colonist — the individual unit of the colony. Every inhabitant of
/// a settlement is a pawn: the macro `Settlement.population` is derived from
/// the pawn count, and lives (birth, growth, old age, inheritance) play out
/// through the `PopulationEngine`.
public struct Pawn: Codable, Sendable, Identifiable, Equatable {
    /// The age (in years) at which a colonist starts working and voting.
    public static let adultAgeYears = 14
    /// The default age for pawns created without an explicit one (founders,
    /// recruits, test fixtures): a working adult in their prime.
    public static let defaultAdultAgeTicks = 1500   // 25 years at 60 ticks/year

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
    public var equipment: [EquipmentSlot: ItemInstance]  // one item per slot
    public var age: Int                  // in ticks; interpret via config.ticksPerYear
    public var genes: Genes
    public var wealth: Double            // personal savings — class standing, inheritance
    public var pregnancyTicksRemaining: Int   // 0 = not expecting

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
        isBroken: Bool = false,
        equipment: [EquipmentSlot: ItemInstance] = [:],
        age: Int = Pawn.defaultAdultAgeTicks,
        genes: Genes = Genes(),
        wealth: Double = 0,
        pregnancyTicksRemaining: Int = 0
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
        self.equipment = equipment
        self.age = age
        self.genes = genes
        self.wealth = wealth
        self.pregnancyTicksRemaining = pregnancyTicksRemaining
    }

    public func skill(_ kind: WorkKind) -> Int { skills[kind] ?? 0 }

    /// Whole in-game years lived.
    public func ageYears(ticksPerYear: Int) -> Int {
        guard ticksPerYear > 0 else { return 0 }
        return age / ticksPerYear
    }

    /// Adults work, vote and can bear children.
    public func isAdult(ticksPerYear: Int) -> Bool {
        ageYears(ticksPerYear: ticksPerYear) >= Pawn.adultAgeYears
    }

    // MARK: - Codable (resilient to pre-V2 saves without life-cycle fields)

    private enum CodingKeys: String, CodingKey {
        case id, name, trait, skills, skillXP, needs, mood, assignedWork
        case health, isBroken, equipment
        case age, genes, wealth, pregnancyTicksRemaining
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        trait = try c.decode(PawnTrait.self, forKey: .trait)
        skills = try c.decode([WorkKind: Int].self, forKey: .skills)
        skillXP = try c.decode([WorkKind: Double].self, forKey: .skillXP)
        needs = try c.decode(PawnNeeds.self, forKey: .needs)
        mood = try c.decode(Double.self, forKey: .mood)
        assignedWork = try c.decode(WorkKind.self, forKey: .assignedWork)
        health = try c.decode(Double.self, forKey: .health)
        isBroken = try c.decode(Bool.self, forKey: .isBroken)
        equipment = try c.decodeIfPresent([EquipmentSlot: ItemInstance].self, forKey: .equipment) ?? [:]
        age = try c.decodeIfPresent(Int.self, forKey: .age) ?? Pawn.defaultAdultAgeTicks
        genes = try c.decodeIfPresent(Genes.self, forKey: .genes) ?? Genes()
        wealth = try c.decodeIfPresent(Double.self, forKey: .wealth) ?? 0
        pregnancyTicksRemaining = try c.decodeIfPresent(Int.self, forKey: .pregnancyTicksRemaining) ?? 0
    }
}
