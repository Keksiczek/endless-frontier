import Foundation

/// The category of an event. Drives the tension weight multiplier and how
/// the UI presents the event.
public enum EventType: String, Codable, Sendable, Equatable, CaseIterable {
    case disaster
    case threat
    case opportunity
    case quest
    case flavor
}

/// A player-facing branch inside an event card.
public struct EventChoice: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let description: String?
    public let cost: Resources
    public let effects: [EventEffect]

    public init(
        id: String,
        label: String,
        description: String? = nil,
        cost: Resources = Resources(),
        effects: [EventEffect] = []
    ) {
        self.id = id
        self.label = label
        self.description = description
        self.cost = cost
        self.effects = effects
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, description, cost, effects
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        cost = try c.decodeIfPresent(Resources.self, forKey: .cost) ?? Resources()
        effects = try c.decodeIfPresent([EventEffect].self, forKey: .effects) ?? []
    }
}

/// A data-defined event. Loaded from `events.json`. The storyteller filters
/// templates by era + conditions + cooldown, weights them by tension, and
/// applies the effects of the selected ones.
public struct EventTemplate: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let type: EventType
    public let name: String
    public let era: [Era]
    public let weight: Double
    public let cooldownTicks: Int
    public let conditions: [EventCondition]
    public let effects: [EventEffect]
    public let choices: [EventChoice]
    public let narrativeHint: String

    public init(
        id: String,
        type: EventType,
        name: String,
        era: [Era] = [],
        weight: Double,
        cooldownTicks: Int = 50,
        conditions: [EventCondition] = [],
        effects: [EventEffect] = [],
        choices: [EventChoice] = [],
        narrativeHint: String
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.era = era
        self.weight = weight
        self.cooldownTicks = cooldownTicks
        self.conditions = conditions
        self.effects = effects
        self.choices = choices
        self.narrativeHint = narrativeHint
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, name, era, weight
        case cooldownTicks = "cooldown_ticks"
        case conditions, effects, choices
        case narrativeHint = "narrative_hint"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(EventType.self, forKey: .type)
        name = try c.decode(String.self, forKey: .name)
        era = try c.decodeIfPresent([Era].self, forKey: .era) ?? []
        weight = try c.decode(Double.self, forKey: .weight)
        cooldownTicks = try c.decodeIfPresent(Int.self, forKey: .cooldownTicks) ?? 50
        conditions = try c.decodeIfPresent([EventCondition].self, forKey: .conditions) ?? []
        effects = try c.decodeIfPresent([EventEffect].self, forKey: .effects) ?? []
        choices = try c.decodeIfPresent([EventChoice].self, forKey: .choices) ?? []
        narrativeHint = try c.decode(String.self, forKey: .narrativeHint)
    }

    /// `true` if this template may fire in `era` (empty `era` = all eras).
    public func allows(era candidate: Era) -> Bool {
        era.isEmpty || era.contains(candidate)
    }
}
