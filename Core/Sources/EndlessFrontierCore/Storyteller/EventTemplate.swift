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
    public let label: LocalizedText
    public let description: LocalizedText?
    public let cost: Resources
    public let effects: [EventEffect]

    public init(
        id: String,
        label: LocalizedText,
        description: LocalizedText? = nil,
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
        label = try c.decode(LocalizedText.self, forKey: .label)
        description = try c.decodeIfPresent(LocalizedText.self, forKey: .description)
        cost = try c.decodeIfPresent(Resources.self, forKey: .cost) ?? Resources()
        effects = try c.decodeIfPresent([EventEffect].self, forKey: .effects) ?? []
    }
}

/// A data-defined event. Loaded from `events.json`. The storyteller filters
/// templates by era + conditions + cooldown, weights them by tension, and
/// applies the effects of the selected ones.
/// Player-facing event text is `LocalizedText`, not `String`. It was plain
/// `String` — which meant the whole storyteller was structurally incapable of
/// speaking anything but English, and none of the Czech content this game grew
/// out of could be carried across. `LocalizedText` decodes from a bare string
/// as well as a `{ en, cs }` object, so the 48 untranslated templates keep
/// working untouched while new ones ship bilingual.
public struct EventTemplate: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let type: EventType
    public let name: LocalizedText
    public let era: [Era]
    public let weight: Double
    public let cooldownTicks: Int
    public let conditions: [EventCondition]
    public let effects: [EventEffect]
    public let choices: [EventChoice]
    /// How long the Leader has to answer this event's choice before the moment
    /// passes. `nil` falls back to `WorldConfig.decisionDeadlineTicks` — set it
    /// for a moment that keeps or slips faster than most.
    public let decisionTicks: Int?
    public let narrativeHint: LocalizedText

    public init(
        id: String,
        type: EventType,
        name: LocalizedText,
        era: [Era] = [],
        weight: Double,
        cooldownTicks: Int = 50,
        conditions: [EventCondition] = [],
        effects: [EventEffect] = [],
        choices: [EventChoice] = [],
        decisionTicks: Int? = nil,
        narrativeHint: LocalizedText
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
        self.decisionTicks = decisionTicks
        self.narrativeHint = narrativeHint
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, name, era, weight
        case cooldownTicks = "cooldown_ticks"
        case conditions, effects, choices
        case decisionTicks = "decision_ticks"
        case narrativeHint = "narrative_hint"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(EventType.self, forKey: .type)
        name = try c.decode(LocalizedText.self, forKey: .name)
        era = try c.decodeIfPresent([Era].self, forKey: .era) ?? []
        weight = try c.decode(Double.self, forKey: .weight)
        cooldownTicks = try c.decodeIfPresent(Int.self, forKey: .cooldownTicks) ?? 50
        conditions = try c.decodeIfPresent([EventCondition].self, forKey: .conditions) ?? []
        effects = try c.decodeIfPresent([EventEffect].self, forKey: .effects) ?? []
        choices = try c.decodeIfPresent([EventChoice].self, forKey: .choices) ?? []
        decisionTicks = try c.decodeIfPresent(Int.self, forKey: .decisionTicks)
        narrativeHint = try c.decode(LocalizedText.self, forKey: .narrativeHint)
    }

    /// `true` if this template may fire in `era` (empty `era` = all eras).
    public func allows(era candidate: Era) -> Bool {
        era.isEmpty || era.contains(candidate)
    }
}
