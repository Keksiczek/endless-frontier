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
    public let name: LocalizedText
    public let era: Era
    public let requires: [String]
    public let cost: Resources
    public let effects: [TechEffect]
    /// A study that is never finished: it stays on the board after completion,
    /// its effects stack, and each completion makes the next dearer. This is
    /// what gives knowledge a sink that outlives the 29-tech tree, in a game
    /// whose whole premise is one endless world with no "you finished it" wall.
    public let repeatable: Bool
    public let description: LocalizedText?

    public init(
        id: String,
        name: LocalizedText,
        era: Era,
        requires: [String] = [],
        cost: Resources,
        effects: [TechEffect] = [],
        repeatable: Bool = false,
        description: LocalizedText? = nil
    ) {
        self.id = id
        self.name = name
        self.era = era
        self.requires = requires
        self.cost = cost
        self.effects = effects
        self.repeatable = repeatable
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, era, requires, cost, effects, repeatable, description
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(LocalizedText.self, forKey: .name)
        era = try c.decode(Era.self, forKey: .era)
        requires = try c.decodeIfPresent([String].self, forKey: .requires) ?? []
        cost = try c.decode(Resources.self, forKey: .cost)
        effects = try c.decodeIfPresent([TechEffect].self, forKey: .effects) ?? []
        repeatable = try c.decodeIfPresent(Bool.self, forKey: .repeatable) ?? false
        description = try c.decodeIfPresent(LocalizedText.self, forKey: .description)
    }

    /// Knowledge cost (the primary research currency).
    public var knowledgeCost: Double { cost[.knowledge] }
}
