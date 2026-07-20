import Foundation

/// Where a neighbouring people stands with you, read off the relations score.
public enum DiplomaticStanding: String, Codable, Sendable, CaseIterable {
    case allied
    case friendly
    case neutral
    case tense
    case war

    public init(score: Double) {
        switch score {
        case 60...: self = .allied
        case 25..<60: self = .friendly
        case -25..<25: self = .neutral
        case -60..<(-25): self = .tense
        default: self = .war
        }
    }
}

/// A neighbouring people — not a settlement you command, but one that grew from
/// your own: colonists who walked out and founded their own hearth. They trade,
/// they marry, they raid, and they take in your malcontents.
///
/// Deliberately lighter than `Settlement`: diplomacy only needs their numbers,
/// their character, their faith and their spears.
public struct Tribe: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var regionID: UUID?
    public let foundedTick: Int
    /// Why they left — chronicle flavour.
    public let originStory: LocalizedText

    public var population: Double
    /// The average disposition of their people — how alike you are decides how
    /// well you get on.
    public var genes: Genes
    public var cultID: String?
    public var defense: Double
    /// Their granary — what a raid can carry off, and what a caravan can bring.
    public var stores: Double

    /// Relations with the player's civilisation, −100…100.
    public var standing: Double
    /// Old wounds that keep relations from healing.
    public var grudge: Double
    /// Whether the leaders' houses have been joined by marriage.
    public var married: Bool
    public var wars: Int
    public var defections: Int
    /// A people who were in the valley long before you came — seeded at world
    /// creation, unlike the tribes that secede out of your own settlement.
    public var isNative: Bool
    /// Whether you have actually met them. Native peoples start hidden and are
    /// found by expeditions; everything diplomatic waits for first contact.
    public var discovered: Bool

    public var status: DiplomaticStanding { DiplomaticStanding(score: standing) }

    public init(
        id: UUID,
        name: String,
        regionID: UUID? = nil,
        foundedTick: Int,
        originStory: LocalizedText,
        population: Double,
        genes: Genes,
        cultID: String? = nil,
        defense: Double = 10,
        stores: Double = 60,
        standing: Double = 0,
        grudge: Double = 0,
        married: Bool = false,
        wars: Int = 0,
        defections: Int = 0,
        isNative: Bool = false,
        discovered: Bool = true
    ) {
        self.id = id
        self.name = name
        self.regionID = regionID
        self.foundedTick = foundedTick
        self.originStory = originStory
        self.population = population
        self.genes = genes
        self.cultID = cultID
        self.defense = defense
        self.stores = stores
        self.standing = standing
        self.grudge = grudge
        self.married = married
        self.wars = wars
        self.defections = defections
        self.isNative = isNative
        self.discovered = discovered
    }

    // MARK: - Codable (resilient: native peoples arrived after the first V2 cut)

    private enum CodingKeys: String, CodingKey {
        case id, name, regionID, foundedTick, originStory, population, genes
        case cultID, defense, stores, standing, grudge, married, wars, defections
        case isNative, discovered
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        regionID = try c.decodeIfPresent(UUID.self, forKey: .regionID)
        foundedTick = try c.decode(Int.self, forKey: .foundedTick)
        originStory = try c.decode(LocalizedText.self, forKey: .originStory)
        population = try c.decode(Double.self, forKey: .population)
        genes = try c.decode(Genes.self, forKey: .genes)
        cultID = try c.decodeIfPresent(String.self, forKey: .cultID)
        defense = try c.decode(Double.self, forKey: .defense)
        stores = try c.decode(Double.self, forKey: .stores)
        standing = try c.decode(Double.self, forKey: .standing)
        grudge = try c.decode(Double.self, forKey: .grudge)
        married = try c.decode(Bool.self, forKey: .married)
        wars = try c.decode(Int.self, forKey: .wars)
        defections = try c.decode(Int.self, forKey: .defections)
        // Tribes saved before natives existed are emergent — and already met.
        isNative = try c.decodeIfPresent(Bool.self, forKey: .isNative) ?? false
        discovered = try c.decodeIfPresent(Bool.self, forKey: .discovered) ?? true
    }
}
