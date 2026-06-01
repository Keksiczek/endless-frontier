import Foundation

/// An effect granted when a tech is researched. Tagged union keyed on `type`.
public enum TechEffect: Codable, Sendable, Equatable {
    case unlockBuilding(buildingID: String)
    case modifier(stat: String, delta: Double, multiplicative: Bool)
    case unlockEventCategory(String)

    private enum CodingKeys: String, CodingKey {
        case type, buildingId, stat, delta, mode, eventCategory
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "unlock_building":
            self = .unlockBuilding(buildingID: try c.decode(String.self, forKey: .buildingId))
        case "modifier":
            let stat = try c.decode(String.self, forKey: .stat)
            let delta = try c.decode(Double.self, forKey: .delta)
            let mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "additive"
            self = .modifier(stat: stat, delta: delta, multiplicative: mode == "multiplicative")
        case "unlock_event_category":
            self = .unlockEventCategory(try c.decode(String.self, forKey: .eventCategory))
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "Unknown tech effect type: \(other)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .unlockBuilding(buildingID):
            try c.encode("unlock_building", forKey: .type)
            try c.encode(buildingID, forKey: .buildingId)
        case let .modifier(stat, delta, multiplicative):
            try c.encode("modifier", forKey: .type)
            try c.encode(stat, forKey: .stat)
            try c.encode(delta, forKey: .delta)
            try c.encode(multiplicative ? "multiplicative" : "additive", forKey: .mode)
        case let .unlockEventCategory(category):
            try c.encode("unlock_event_category", forKey: .type)
            try c.encode(category, forKey: .eventCategory)
        }
    }
}

/// A node in the tech-tree DAG. Loaded from `techs.json`.
public struct TechDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let era: Era
    public let requires: [String]
    public let cost: Resources
    public let effects: [TechEffect]
    public let description: String?

    public init(
        id: String,
        name: String,
        era: Era,
        requires: [String] = [],
        cost: Resources,
        effects: [TechEffect] = [],
        description: String? = nil
    ) {
        self.id = id
        self.name = name
        self.era = era
        self.requires = requires
        self.cost = cost
        self.effects = effects
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, era, requires, cost, effects, description
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        era = try c.decode(Era.self, forKey: .era)
        requires = try c.decodeIfPresent([String].self, forKey: .requires) ?? []
        cost = try c.decode(Resources.self, forKey: .cost)
        effects = try c.decodeIfPresent([TechEffect].self, forKey: .effects) ?? []
        description = try c.decodeIfPresent(String.self, forKey: .description)
    }

    /// Knowledge cost (the primary research currency).
    public var knowledgeCost: Double { cost[.knowledge] }
}
