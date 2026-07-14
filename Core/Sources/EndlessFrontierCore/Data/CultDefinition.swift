import Foundation

/// A faith that can take root in a settlement once a temple stands. Data-driven:
/// adding a cult is adding JSON.
public struct CultDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: LocalizedText
    /// What the faithful say of it — chronicle flavour.
    public let creed: LocalizedText
    /// Morale the faith adds at full devotion (scaled by `faith`).
    public let moraleAtFullFaith: Double
    /// How much the faith softens disaster (0…1 of the tension spike).
    public let solace: Double

    public init(
        id: String,
        name: LocalizedText,
        creed: LocalizedText,
        moraleAtFullFaith: Double = 8,
        solace: Double = 0.3
    ) {
        self.id = id
        self.name = name
        self.creed = creed
        self.moraleAtFullFaith = moraleAtFullFaith
        self.solace = solace
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, creed, solace
        case moraleAtFullFaith = "morale_at_full_faith"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(LocalizedText.self, forKey: .name)
        creed = try c.decode(LocalizedText.self, forKey: .creed)
        moraleAtFullFaith = try c.decodeIfPresent(Double.self, forKey: .moraleAtFullFaith) ?? 8
        solace = try c.decodeIfPresent(Double.self, forKey: .solace) ?? 0.3
    }
}

/// The state of a settlement's faith: which cult holds it, how fervent it is,
/// and whether a prophet is stirring the people.
public struct FaithState: Codable, Sendable, Equatable {
    /// The cult that took root, if a temple has been raised.
    public var cultID: String?
    /// Devotion, 0…100.
    public var faith: Double
    /// A prophet walks among the people, preaching for a temple.
    public var prophetStirring: Bool
    /// Great rites held — chronicle material.
    public var rites: Int

    public init(cultID: String? = nil, faith: Double = 0, prophetStirring: Bool = false, rites: Int = 0) {
        self.cultID = cultID
        self.faith = faith
        self.prophetStirring = prophetStirring
        self.rites = rites
    }

    public var hasTemple: Bool { cultID != nil }
}
