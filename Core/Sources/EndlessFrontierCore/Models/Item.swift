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
/// **What a weapon throws at somebody.**
///
/// Fifty-eight weapons shipped with a `class` and a `damage`, which is to say
/// that a sling, a longbow, a musket, a pistol and a railgun were one thing
/// with five numbers on it. They were drawn identically too — six bone-coloured
/// shafts, whatever had been fired — because the canvas had nothing else to go
/// on. Keks: *"at ma kazda zbran unikat, pistol strili mensi nez sniper"*.
///
/// So the shot is a thing with a kind, and the kind is what every part of it is
/// derived from: how big it draws, how fast it crosses, what it leaves behind
/// it, and whether it goes off when it arrives. One enum, read by the engine
/// (what may be shot at, and from how far) and by the canvas (what it looks
/// like) — never two lists that drift.
public enum ProjectileKind: String, Codable, Sendable, CaseIterable {
    /// Nothing leaves the hand. Every melee weapon.
    case none
    /// A shaft from a bow — the one the game already drew.
    case arrow
    /// Shorter, heavier, flatter: a crossbow.
    case bolt
    /// A stone from a sling or a hand.
    case stone
    /// A blowpipe dart, and anything else small and slow.
    case dart
    /// A lead ball out of a smoothbore, in a great deal of smoke.
    case ball
    /// A rifled round: small, fast, and gone before it is seen.
    case bullet
    /// A burst of shot from one barrel — a cone rather than a line.
    case shot
    /// An artillery shell: it arcs, and it goes off where it lands.
    case shell
    /// Thrown, arcs high, goes off after it stops.
    case grenade
    /// Carries its own fire, leaves a trail, goes off on arrival.
    case rocket
    /// No flight at all — a line drawn the instant it is fired.
    case beam

    /// Whether this one goes off where it lands rather than simply hitting.
    public var bursts: Bool {
        switch self {
        case .shell, .grenade, .rocket: return true
        default: return false
        }
    }

    /// Whether it travels on a curve rather than flat. What arcs can be lobbed
    /// over a wall; what does not, cannot.
    public var arcs: Bool {
        switch self {
        case .arrow, .stone, .grenade, .shell: return true
        default: return false
        }
    }

    /// How far it crosses the valley in one action step, as a fraction of the
    /// local map. Feeds the canvas' flight and nothing else — a shot resolves
    /// in the step it is fired in, the way it always has.
    public var speed: Double {
        switch self {
        case .none:               return 0
        case .stone, .grenade:    return 0.20
        case .arrow, .dart:       return 0.35
        case .bolt, .ball:        return 0.55
        case .rocket:             return 0.6
        case .shell:              return 0.7
        case .shot, .bullet:      return 1.6
        case .beam:               return 8
        }
    }
}

/// What a weapon does, and — since it stopped being a number — what it throws.
public struct CombatProfile: Codable, Sendable, Equatable {
    public let damage: Double
    public let kind: WeaponClass

    /// What leaves the weapon. Absent in every entry written before this
    /// existed, and those are answered for rather than left blank: a ranged
    /// weapon with nothing stated shoots an arrow, which is what the game drew
    /// for all of them anyway, and a melee one shoots nothing.
    public let projectile: ProjectileKind

    /// How far it carries, as a fraction of the local map. Nil means "the
    /// ordinary reach of its kind" — `SiegeEngine.bowRange`. **This is the
    /// pistol-and-sniper difference**, and the first thing about a ranged
    /// weapon that was ever anything but damage.
    public let range: Double?

    /// How wide the shot goes, in fractions of the map at the far end. A
    /// smoothbore scatters, a scoped rifle does not.
    public let spread: Double?

    /// How big the thing that leaves it is, drawn. 1 is an arrow.
    public let caliber: Double?

    /// How many shots one action step's worth of fire is drawn as. A bow looses
    /// once; a machine gun does not.
    public let shots: Int?

    /// How far the burst reaches, for the kinds that burst. Fraction of the map.
    public let blast: Double?

    public init(damage: Double, kind: WeaponClass,
                projectile: ProjectileKind? = nil, range: Double? = nil,
                spread: Double? = nil, caliber: Double? = nil,
                shots: Int? = nil, blast: Double? = nil) {
        self.damage = damage
        self.kind = kind
        self.projectile = projectile ?? (kind == .ranged ? .arrow : .none)
        self.range = range
        self.spread = spread
        self.caliber = caliber
        self.shots = shots
        self.blast = blast
    }

    private enum CodingKeys: String, CodingKey {
        case damage, projectile, range, spread, caliber, shots, blast
        case kind = "class"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let damage = try c.decode(Double.self, forKey: .damage)
        let kind = try c.decode(WeaponClass.self, forKey: .kind)
        self.init(
            damage: damage, kind: kind,
            projectile: try c.decodeIfPresent(ProjectileKind.self, forKey: .projectile),
            range: try c.decodeIfPresent(Double.self, forKey: .range),
            spread: try c.decodeIfPresent(Double.self, forKey: .spread),
            caliber: try c.decodeIfPresent(Double.self, forKey: .caliber),
            shots: try c.decodeIfPresent(Int.self, forKey: .shots),
            blast: try c.decodeIfPresent(Double.self, forKey: .blast))
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
/// **What a piece of armour is made of, and how much of a person it covers.**
///
/// The mirror of `CombatProfile`, and it exists for the same reason. Keks,
/// looking at his colonists: *"brnění taky, itemy taky… vše musí být i grafické
/// a unikátní a vypadat tak co to je."* He is right, and the data was the
/// reason: an armour item carried a name, a rarity, an effect and a
/// description, and **nothing a drawing could read** — so thirty-nine
/// different coats, from a hide jerkin to a powered harness, were all the same
/// figure with the same tunic. Rule 47: nothing can be drawn out of a field
/// that does not exist.
///
/// Three things, because three is what a line-art figure at fourteen points
/// tall can actually show: what it is made of (which decides how it is
/// stroked), how much of the body it wraps, and whether there is something on
/// the head. Everything else — the segment count, the sheen, the collar — is
/// derived from those in `SettlementFigures`, exactly as a building's whole
/// look is derived in `StructureVariant`.
///
/// Absent on a piece nobody has described yet: the drawing falls back to what
/// the item's rarity and its effects imply, so a new coat looks like *something*
/// the day it is authored and like *itself* the day somebody says what it is.
public struct ArmourProfile: Codable, Sendable, Equatable {

    /// What it is made of. Decides the stroke: cloth drapes, mail is a mesh of
    /// dots, plate is two or three hard segments with a highlight.
    public enum Material: String, Codable, Sendable, CaseIterable {
        case cloth, hide, leather, wood, bone, bronze, mail, plate, composite, powered
    }

    /// How much of a person is inside it.
    public enum Coverage: String, Codable, Sendable, CaseIterable {
        /// A jerkin, a cuirass — the trunk only.
        case torso
        /// …and sleeves down the arms.
        case torsoArms = "torso_arms"
        /// …and the legs: a full harness.
        case full
        /// A helm, a hood, a mask, and nothing else.
        case head
        /// A cloak or a mantle over the shoulders.
        case mantle
    }

    public let material: Material
    public let coverage: Coverage
    /// Whether it comes with something on the head, over and above `coverage`.
    public let helm: Bool
    /// A tint, 0…1 round the colour wheel, for the pieces whose material does
    /// not already say their colour (dyed cloth, painted plate). Nil takes the
    /// material's own.
    public let tint: Double?

    public init(material: Material, coverage: Coverage = .torso,
                helm: Bool = false, tint: Double? = nil) {
        self.material = material
        self.coverage = coverage
        self.helm = helm
        self.tint = tint
    }

    private enum CodingKeys: String, CodingKey { case material, coverage, helm, tint }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            material: try c.decode(Material.self, forKey: .material),
            coverage: try c.decodeIfPresent(Coverage.self, forKey: .coverage) ?? .torso,
            helm: try c.decodeIfPresent(Bool.self, forKey: .helm) ?? false,
            tint: try c.decodeIfPresent(Double.self, forKey: .tint))
    }
}

public struct ItemDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: LocalizedText
    public let rarity: ItemRarity
    public let slot: ItemSlot
    /// What the stuff physically **is** — timber, masonry, hide, nothing at
    /// all. Materials carry it; a sword does not need to.
    ///
    /// Read by `Cover.body(of:registry:)`, so a building is made of what it was
    /// actually built out of rather than of one constant, and by anything else
    /// that has to know the difference between a plank and a brick.
    public let substance: Cover.Substance?
    public let equipSlot: EquipmentSlot?   // which body slot, for equipment items
    public let effects: [ItemEffect]
    /// How the item fights, when it can (weapons and weapon-slot tools).
    public let combat: CombatProfile?
    /// What the item **looks like on a body**, when it is worn. See
    /// `ArmourProfile`.
    public let armour: ArmourProfile?
    public let description: LocalizedText

    public init(id: String, name: LocalizedText, rarity: ItemRarity, slot: ItemSlot,
                substance: Cover.Substance? = nil,
                equipSlot: EquipmentSlot? = nil, effects: [ItemEffect] = [],
                combat: CombatProfile? = nil, armour: ArmourProfile? = nil,
                description: LocalizedText = "") {
        self.id = id
        self.name = name
        self.rarity = rarity
        self.slot = slot
        self.substance = substance
        self.equipSlot = equipSlot
        self.effects = effects
        self.combat = combat
        self.armour = armour
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, rarity, slot, substance, equipSlot, effects, combat, armour
        case description
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(LocalizedText.self, forKey: .name)
        rarity = try c.decode(ItemRarity.self, forKey: .rarity)
        slot = try c.decode(ItemSlot.self, forKey: .slot)
        substance = try c.decodeIfPresent(Cover.Substance.self, forKey: .substance)
        equipSlot = try c.decodeIfPresent(EquipmentSlot.self, forKey: .equipSlot)
        effects = try c.decodeIfPresent([ItemEffect].self, forKey: .effects) ?? []
        combat = try c.decodeIfPresent(CombatProfile.self, forKey: .combat)
        armour = try c.decodeIfPresent(ArmourProfile.self, forKey: .armour)
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
    /// How far **this** piece has been used up, `0…1`.
    ///
    /// A second axis beside `quality`, deliberately, and §11.26 C says why: a
    /// masterwork blade with a notched edge is not the same object as a shoddy
    /// new one. Quality is *whose hands made it* and never changes; wear is
    /// *what has happened to it since* and only ever goes up.
    ///
    /// Before this, `quality` was written in `init` and never again anywhere in
    /// the codebase — a sword carried through forty battles was exactly the
    /// sword it was forged as, which is also why a colony's quartermaster had
    /// no reason to ever re-arm anybody (§11.22).
    public var wear: Double

    public init(id: UUID = UUID(), definitionID: String,
                quality: ItemQuality = .plain, wear: Double = 0) {
        self.id = id
        self.definitionID = definitionID
        self.quality = quality
        self.wear = min(1, max(0, wear))
    }

    /// What is left of it, `0…1`.
    public var soundness: Double { 1 - wear }

    /// Past this it is scrap: it is not worth carrying and it does not fight.
    public static let brokenAt = 0.95
    public var isBroken: Bool { wear >= Self.brokenAt }

    /// What this particular piece is worth in the hand, against a plain new one.
    ///
    /// Made-well times kept-well, and the wear half never falls to nothing:
    /// a ruined sword is a club, not a feather. What it *does* do is take a
    /// masterwork down to about where a plain piece started, which is the whole
    /// argument for keeping the smith busy.
    public var effectiveness: Double {
        quality.multiplier * (1 - wear * Self.wearBite)
    }
    /// How much of a piece's worth wear can take. See `effectiveness`.
    public static let wearBite = 0.6

    /// The same piece, `amount` more used up. Immutable, like everything else
    /// in the models: this returns a new one rather than ageing this one.
    public func worn(by amount: Double) -> ItemInstance {
        guard amount > 0 else { return self }
        return ItemInstance(id: id, definitionID: definitionID,
                            quality: quality, wear: min(1, wear + amount))
    }

    private enum CodingKeys: String, CodingKey { case id, definitionID, quality, wear }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        definitionID = try c.decode(String.self, forKey: .definitionID)
        quality = try c.decodeIfPresent(ItemQuality.self, forKey: .quality) ?? .plain
        // Everything made before wear existed is as good as the day it was
        // made, which is what it has been pretending all along (rule 37).
        wear = try c.decodeIfPresent(Double.self, forKey: .wear) ?? 0
    }
}
