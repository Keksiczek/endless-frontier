import Foundation

/// The standing changes a law makes while it is in force. Engines read the
/// aggregate of every active law rather than checking law ids, so new laws are
/// pure content.
public struct LawModifiers: Codable, Sendable, Equatable {
    public var foodUpkeepMultiplier: Double
    public var birthRateMultiplier: Double
    public var knowledgeMultiplier: Double
    public var depositRegrowthMultiplier: Double
    public var moraleFlat: Double
    public var defenseFlat: Double
    public var influencePerTick: Double
    /// Fraction of yearly wages the settlement takes as tax.
    public var wageTaxFraction: Double

    public init(
        foodUpkeepMultiplier: Double = 1,
        birthRateMultiplier: Double = 1,
        knowledgeMultiplier: Double = 1,
        depositRegrowthMultiplier: Double = 1,
        moraleFlat: Double = 0,
        defenseFlat: Double = 0,
        influencePerTick: Double = 0,
        wageTaxFraction: Double = 0
    ) {
        self.foodUpkeepMultiplier = foodUpkeepMultiplier
        self.birthRateMultiplier = birthRateMultiplier
        self.knowledgeMultiplier = knowledgeMultiplier
        self.depositRegrowthMultiplier = depositRegrowthMultiplier
        self.moraleFlat = moraleFlat
        self.defenseFlat = defenseFlat
        self.influencePerTick = influencePerTick
        self.wageTaxFraction = wageTaxFraction
    }

    private enum CodingKeys: String, CodingKey {
        case foodUpkeepMultiplier = "food_upkeep_multiplier"
        case birthRateMultiplier = "birth_rate_multiplier"
        case knowledgeMultiplier = "knowledge_multiplier"
        case depositRegrowthMultiplier = "deposit_regrowth_multiplier"
        case moraleFlat = "morale_flat"
        case defenseFlat = "defense_flat"
        case influencePerTick = "influence_per_tick"
        case wageTaxFraction = "wage_tax_fraction"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        foodUpkeepMultiplier = try c.decodeIfPresent(Double.self, forKey: .foodUpkeepMultiplier) ?? 1
        birthRateMultiplier = try c.decodeIfPresent(Double.self, forKey: .birthRateMultiplier) ?? 1
        knowledgeMultiplier = try c.decodeIfPresent(Double.self, forKey: .knowledgeMultiplier) ?? 1
        depositRegrowthMultiplier = try c.decodeIfPresent(Double.self, forKey: .depositRegrowthMultiplier) ?? 1
        moraleFlat = try c.decodeIfPresent(Double.self, forKey: .moraleFlat) ?? 0
        defenseFlat = try c.decodeIfPresent(Double.self, forKey: .defenseFlat) ?? 0
        influencePerTick = try c.decodeIfPresent(Double.self, forKey: .influencePerTick) ?? 0
        wageTaxFraction = try c.decodeIfPresent(Double.self, forKey: .wageTaxFraction) ?? 0
    }

    /// Combines two laws' modifiers (multipliers multiply, flats add).
    public func combined(with other: LawModifiers) -> LawModifiers {
        LawModifiers(
            foodUpkeepMultiplier: foodUpkeepMultiplier * other.foodUpkeepMultiplier,
            birthRateMultiplier: birthRateMultiplier * other.birthRateMultiplier,
            knowledgeMultiplier: knowledgeMultiplier * other.knowledgeMultiplier,
            depositRegrowthMultiplier: depositRegrowthMultiplier * other.depositRegrowthMultiplier,
            moraleFlat: moraleFlat + other.moraleFlat,
            defenseFlat: defenseFlat + other.defenseFlat,
            influencePerTick: influencePerTick + other.influencePerTick,
            wageTaxFraction: min(0.6, wageTaxFraction + other.wageTaxFraction)
        )
    }
}

/// Which disposition sways a colonist's vote on a motion, and how strongly.
public struct VoteBias: Codable, Sendable, Equatable {
    public let industry: Double
    public let fertility: Double
    public let sociability: Double
    public let courage: Double
    /// How much the poor favour it over the wealthy (negative = the rich prefer it).
    public let poorFavour: Double
    /// **What it would mean for somebody's work.**
    ///
    /// Genes say what kind of person somebody is; this says what they do all
    /// day, which is most of what an ordinary person's politics is actually
    /// about. A hewing law is a lumberjack's living and a forester's grievance,
    /// and until this existed both of them voted on temperament alone.
    /// Keyed by `WorkKind.rawValue`; a trade the law says nothing about is 0.
    public let tradeFavour: [String: Double]

    public init(
        industry: Double = 0, fertility: Double = 0,
        sociability: Double = 0, courage: Double = 0, poorFavour: Double = 0,
        tradeFavour: [String: Double] = [:]
    ) {
        self.industry = industry
        self.fertility = fertility
        self.sociability = sociability
        self.courage = courage
        self.poorFavour = poorFavour
        self.tradeFavour = tradeFavour
    }

    private enum CodingKeys: String, CodingKey {
        case industry, fertility, sociability, courage
        case poorFavour = "poor_favour"
        case tradeFavour = "trade_favour"
    }

    /// What this law is worth to somebody who does `work` for a living.
    public func favour(of work: WorkKind) -> Double { tradeFavour[work.rawValue] ?? 0 }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        industry = try c.decodeIfPresent(Double.self, forKey: .industry) ?? 0
        fertility = try c.decodeIfPresent(Double.self, forKey: .fertility) ?? 0
        sociability = try c.decodeIfPresent(Double.self, forKey: .sociability) ?? 0
        courage = try c.decodeIfPresent(Double.self, forKey: .courage) ?? 0
        poorFavour = try c.decodeIfPresent(Double.self, forKey: .poorFavour) ?? 0
        tradeFavour = try c.decodeIfPresent([String: Double].self, forKey: .tradeFavour) ?? [:]
    }

    /// A colonist's inclination toward the motion, 0…1-ish before the roll.
    public func inclination(_ pawn: Pawn, wealthClass: WealthClass) -> Double {
        var v = pawn.genes.industry * industry
            + pawn.genes.fertility * fertility
            + pawn.genes.sociability * sociability
            + pawn.genes.courage * courage
        switch wealthClass {
        case .poor: v += poorFavour
        case .wealthy: v -= poorFavour
        case .middle: break
        }
        return v
    }
}

/// A law the assembly can put to a vote. Data-driven: adding a law is adding
/// JSON. `conditions` decide when the council even considers it (reusing the
/// storyteller's condition language), `modifiers` are what it does while in
/// force, and `effects` fire once on enactment.
public struct LawDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: LocalizedText
    public let summary: LocalizedText
    /// How long it stays in force, in in-game years.
    public let durationYears: Int
    /// Council only tables the motion when all of these hold.
    public let conditions: [EventCondition]
    /// Weight when several motions are eligible.
    public let weight: Double
    public let modifiers: LawModifiers
    public let voteBias: VoteBias
    /// One-off effects applied the moment the law passes.
    public let effects: [EventEffect]

    public init(
        id: String,
        name: LocalizedText,
        summary: LocalizedText,
        durationYears: Int = 10,
        conditions: [EventCondition] = [],
        weight: Double = 1,
        modifiers: LawModifiers = LawModifiers(),
        voteBias: VoteBias = VoteBias(),
        effects: [EventEffect] = []
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.durationYears = durationYears
        self.conditions = conditions
        self.weight = weight
        self.modifiers = modifiers
        self.voteBias = voteBias
        self.effects = effects
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, summary, conditions, weight, modifiers, effects
        case durationYears = "duration_years"
        case voteBias = "vote_bias"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(LocalizedText.self, forKey: .name)
        summary = try c.decode(LocalizedText.self, forKey: .summary)
        durationYears = try c.decodeIfPresent(Int.self, forKey: .durationYears) ?? 10
        conditions = try c.decodeIfPresent([EventCondition].self, forKey: .conditions) ?? []
        weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? 1
        modifiers = try c.decodeIfPresent(LawModifiers.self, forKey: .modifiers) ?? LawModifiers()
        voteBias = try c.decodeIfPresent(VoteBias.self, forKey: .voteBias) ?? VoteBias()
        effects = try c.decodeIfPresent([EventEffect].self, forKey: .effects) ?? []
    }
}
