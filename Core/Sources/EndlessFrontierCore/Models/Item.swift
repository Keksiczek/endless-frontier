import Foundation

/// Item rarity. Rarer items are stronger and drop far less often — and the
/// deeper (more hazardous) the site, the better the odds of a rare find.
public enum ItemRarity: String, Codable, Sendable, CaseIterable, Comparable {
    case common
    case uncommon
    case rare
    case epic
    case legendary

    public var index: Int { ItemRarity.allCases.firstIndex(of: self) ?? 0 }

    /// Base drop weight before any hazard bias.
    public var dropWeight: Double {
        switch self {
        case .common: return 50
        case .uncommon: return 28
        case .rare: return 14
        case .epic: return 6
        case .legendary: return 2
        }
    }

    public static func < (lhs: ItemRarity, rhs: ItemRarity) -> Bool { lhs.index < rhs.index }
}

/// Where an item applies its effects.
/// - `equipment` buffs the colonist who carries it.
/// - `artifact` buffs the whole colony while held in a settlement's vault.
public enum ItemSlot: String, Codable, Sendable, Equatable {
    case equipment
    case artifact
}

/// A buff granted by an item. Tagged union keyed on `type`.
public enum ItemEffect: Codable, Sendable, Equatable {
    // Equipment (apply to the carrying colonist)
    case skillBonus(work: WorkKind, amount: Int)
    case moodBonus(Double)
    case healthRegen(Double)
    // Artifact (apply to the colony)
    case colonyProduction(resource: ResourceType, perTick: Double)
    case colonyDefense(Double)
    case colonyMorale(Double)

    private enum CodingKeys: String, CodingKey {
        case type, work, amount, resource, perTick
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "skill_bonus":
            self = .skillBonus(work: try c.decode(WorkKind.self, forKey: .work),
                               amount: try c.decode(Int.self, forKey: .amount))
        case "mood_bonus":
            self = .moodBonus(try c.decode(Double.self, forKey: .amount))
        case "health_regen":
            self = .healthRegen(try c.decode(Double.self, forKey: .amount))
        case "colony_production":
            self = .colonyProduction(resource: try c.decode(ResourceType.self, forKey: .resource),
                                     perTick: try c.decode(Double.self, forKey: .perTick))
        case "colony_defense":
            self = .colonyDefense(try c.decode(Double.self, forKey: .amount))
        case "colony_morale":
            self = .colonyMorale(try c.decode(Double.self, forKey: .amount))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                                                   debugDescription: "Unknown item effect: \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .skillBonus(work, amount):
            try c.encode("skill_bonus", forKey: .type)
            try c.encode(work, forKey: .work)
            try c.encode(amount, forKey: .amount)
        case let .moodBonus(amount):
            try c.encode("mood_bonus", forKey: .type)
            try c.encode(amount, forKey: .amount)
        case let .healthRegen(amount):
            try c.encode("health_regen", forKey: .type)
            try c.encode(amount, forKey: .amount)
        case let .colonyProduction(resource, perTick):
            try c.encode("colony_production", forKey: .type)
            try c.encode(resource, forKey: .resource)
            try c.encode(perTick, forKey: .perTick)
        case let .colonyDefense(amount):
            try c.encode("colony_defense", forKey: .type)
            try c.encode(amount, forKey: .amount)
        case let .colonyMorale(amount):
            try c.encode("colony_morale", forKey: .type)
            try c.encode(amount, forKey: .amount)
        }
    }
}

/// A data-defined item. Loaded from `items.json`.
public struct ItemDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let rarity: ItemRarity
    public let slot: ItemSlot
    public let effects: [ItemEffect]
    public let description: String

    public init(id: String, name: String, rarity: ItemRarity, slot: ItemSlot,
                effects: [ItemEffect] = [], description: String = "") {
        self.id = id
        self.name = name
        self.rarity = rarity
        self.slot = slot
        self.effects = effects
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, rarity, slot, effects, description
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        rarity = try c.decode(ItemRarity.self, forKey: .rarity)
        slot = try c.decode(ItemSlot.self, forKey: .slot)
        effects = try c.decodeIfPresent([ItemEffect].self, forKey: .effects) ?? []
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}

/// A specific held item, referencing its definition by id.
public struct ItemInstance: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let definitionID: String

    public init(id: UUID = UUID(), definitionID: String) {
        self.id = id
        self.definitionID = definitionID
    }
}
