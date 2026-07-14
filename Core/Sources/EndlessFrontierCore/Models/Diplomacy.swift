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
        defections: Int = 0
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
    }
}
