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
/// - `equipment` buffs the colonist who carries it (in a specific body slot).
/// - `artifact` buffs the whole colony while held in a settlement's vault.
/// - `material` is a crafting ingredient with no direct effect.
public enum ItemSlot: String, Codable, Sendable, Equatable {
    case equipment
    case artifact
    case material
}

/// A colonist's equipment slots. A pawn may carry one item per slot.
public enum EquipmentSlot: String, Codable, Sendable, Equatable, CaseIterable {
    case weapon
    case armor
    case trinket
}

/// How a weapon fights: shoulder to shoulder, or from a distance.
/// Ranged weapons loose a volley before raiders reach the walls; melee power
/// decides the clash itself (see `CombatEngine`).
public enum WeaponClass: String, Codable, Sendable, Equatable {
    case melee
    case ranged
}

/// A weapon's fighting characteristics. Tools that live in the weapon slot
/// (an axe, a pick) carry a token profile — a colonist swinging an axe is not
/// unarmed — while true arms carry real ones.
public struct CombatProfile: Codable, Sendable, Equatable {
    public let damage: Double
    public let kind: WeaponClass

    public init(damage: Double, kind: WeaponClass) {
        self.damage = damage
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case damage
        case kind = "class"
    }
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
    public let name: LocalizedText
    public let rarity: ItemRarity
    public let slot: ItemSlot
    public let equipSlot: EquipmentSlot?   // which body slot, for equipment items
    public let effects: [ItemEffect]
    /// How the item fights, when it can (weapons and weapon-slot tools).
    public let combat: CombatProfile?
    public let description: LocalizedText

    public init(id: String, name: LocalizedText, rarity: ItemRarity, slot: ItemSlot,
                equipSlot: EquipmentSlot? = nil, effects: [ItemEffect] = [],
                combat: CombatProfile? = nil, description: LocalizedText = "") {
        self.id = id
        self.name = name
        self.rarity = rarity
        self.slot = slot
        self.equipSlot = equipSlot
        self.effects = effects
        self.combat = combat
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, rarity, slot, equipSlot, effects, combat, description
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(LocalizedText.self, forKey: .name)
        rarity = try c.decode(ItemRarity.self, forKey: .rarity)
        slot = try c.decode(ItemSlot.self, forKey: .slot)
        equipSlot = try c.decodeIfPresent(EquipmentSlot.self, forKey: .equipSlot)
        effects = try c.decodeIfPresent([ItemEffect].self, forKey: .effects) ?? []
        combat = try c.decodeIfPresent(CombatProfile.self, forKey: .combat)
        description = try c.decodeIfPresent(LocalizedText.self, forKey: .description) ?? ""
    }
}

/// A specific held item, referencing its definition by id.
/// How well a particular thing was made.
///
/// `ItemRarity` is a property of the *definition* — what kind of thing this is,
/// and how often the world gives one up. Quality is a property of the **piece**:
/// two iron swords off the same bench are the same rarity and not the same
/// sword, because one of them was made by somebody who had been doing it for
/// thirty years.
///
/// This is what makes a skilled crafter worth having. Before it, skill made a
/// smith *faster* and nothing else, so a master and an apprentice turned out
/// identical goods and the only reason to train anybody was throughput.
public enum ItemQuality: String, Codable, Sendable, CaseIterable, Comparable {
    case shoddy
    case plain
    case fine
    case masterwork

    public var index: Int { ItemQuality.allCases.firstIndex(of: self) ?? 0 }

    public static func < (a: ItemQuality, b: ItemQuality) -> Bool { a.index < b.index }

    /// What a piece of this quality is worth against a plain one — its damage
    /// if it is a weapon, its protection if it is armour, its price always.
    public var multiplier: Double {
        switch self {
        case .shoddy: return 0.75
        case .plain: return 1
        case .fine: return 1.25
        case .masterwork: return 1.6
        }
    }

    public var label: LocalizedText {
        switch self {
        case .shoddy: return LocalizedText(values: [.en: "Shoddy", .cs: "Odbytý"])
        case .plain: return LocalizedText(values: [.en: "Plain", .cs: "Prostý"])
        case .fine: return LocalizedText(values: [.en: "Fine", .cs: "Povedený"])
        case .masterwork: return LocalizedText(values: [.en: "Masterwork", .cs: "Mistrovský"])
        }
    }

    /// What a crafter of a given skill turns out, from one roll in 0…1.
    ///
    /// Skill is 0…20. A beginner mostly makes plain work and botches some of
    /// it; a master rarely botches anything and now and then makes something
    /// people talk about. Nobody is ever *guaranteed* a masterwork — that is
    /// the point of a masterwork.
    public static func rolled(skill: Int, roll: Double) -> ItemQuality {
        let hand = min(1, max(0, Double(skill) / 20))
        let botch = 0.28 * (1 - hand)              // 28% green → 0% master
        let master = 0.02 + 0.20 * hand * hand     // 2% green → 22% master
        let fine = 0.15 + 0.35 * hand              // 15% green → 50% master
        if roll < botch { return .shoddy }
        if roll > 1 - master { return .masterwork }
        if roll > 1 - master - fine { return .fine }
        return .plain
    }
}

public struct ItemInstance: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let definitionID: String
    /// How well *this one* was made. Old saves and everything the world hands
    /// out rather than makes are plain (rule 3).
    public var quality: ItemQuality

    public init(id: UUID = UUID(), definitionID: String, quality: ItemQuality = .plain) {
        self.id = id
        self.definitionID = definitionID
        self.quality = quality
    }

    private enum CodingKeys: String, CodingKey { case id, definitionID, quality }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        definitionID = try c.decode(String.self, forKey: .definitionID)
        quality = try c.decodeIfPresent(ItemQuality.self, forKey: .quality) ?? .plain
    }
}
