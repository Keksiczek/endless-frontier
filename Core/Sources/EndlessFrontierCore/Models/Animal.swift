import Foundation

/// The wild made of *entities*, not a number.
///
/// Until now the wild was an abstraction — `WildlifeState.deerHerd` was a
/// `Double`, and the deer and wolves on the canvas were pure presentation. An
/// animal is the same *kind* of thing a colonist is: it has a life, a body that
/// can be hurt part by part, warmth it needs, and ills it can catch. This is
/// the foundation for that — a pawn-like animal the simulation can eventually
/// live through the way it lives colonists. RimWorld's insight, ported: an
/// animal is a pawn with a lighter mind, not a separate universe.
///
/// (The abstract `deerHerd` still drives the hunting economy for now; these
/// entities are the layer that grows to replace it — see `WildlifeState`.)

public enum AnimalSex: String, Codable, Sendable, CaseIterable {
    case male, female
}

/// A wild species — a handful to start, prey and predators, each with its own
/// hardiness and comfort band. Traits live here (a Flyweight of the kind
/// `ThingDef` is in RimWorld) so an `Animal` instance stays light.
public enum AnimalSpecies: String, Codable, Sendable, CaseIterable {
    case deer, boar, hare, fox, wolf, bear

    public var isPredator: Bool {
        switch self {
        case .wolf, .bear, .fox: return true
        case .deer, .boar, .hare: return false
        }
    }

    /// Full health for an adult of this species.
    public var baseHealth: Double {
        switch self {
        case .bear: return 170
        case .boar, .wolf: return 110
        case .deer: return 90
        case .fox: return 55
        case .hare: return 35
        }
    }

    /// The comfort band, in °C — below `comfortLow` it suffers cold, above
    /// `comfortHigh` it suffers heat. (Consumed by the temperature layer later.)
    public var comfortLow: Double {
        switch self {
        case .bear, .wolf: return -35
        case .deer, .fox: return -20
        case .boar: return -15
        case .hare: return -25
        }
    }
    public var comfortHigh: Double {
        switch self {
        case .boar: return 38
        case .deer, .hare, .fox: return 32
        case .wolf: return 30
        case .bear: return 28
        }
    }

    public var displayName: LocalizedText {
        switch self {
        case .deer: return LocalizedText(values: [.en: "Deer", .cs: "Jelen"])
        case .boar: return LocalizedText(values: [.en: "Boar", .cs: "Kanec"])
        case .hare: return LocalizedText(values: [.en: "Hare", .cs: "Zajíc"])
        case .fox:  return LocalizedText(values: [.en: "Fox", .cs: "Liška"])
        case .wolf: return LocalizedText(values: [.en: "Wolf", .cs: "Vlk"])
        case .bear: return LocalizedText(values: [.en: "Bear", .cs: "Medvěd"])
        }
    }

    /// The body every animal of this kind is born with. A quadruped plan for
    /// all of them for now; species can diverge later.
    public var bodyPlan: [AnimalBodyPartKind] {
        [.head, .torso, .frontLeftLeg, .frontRightLeg, .backLeftLeg, .backRightLeg]
    }
}

/// A part of an animal's body — losing a vital one kills, losing a leg cripples.
public enum AnimalBodyPartKind: String, Codable, Sendable, CaseIterable {
    case head, torso, frontLeftLeg, frontRightLeg, backLeftLeg, backRightLeg

    /// A part whose destruction is fatal.
    public var isVital: Bool { self == .head || self == .torso }
    public var isLeg: Bool {
        switch self {
        case .frontLeftLeg, .frontRightLeg, .backLeftLeg, .backRightLeg: return true
        default: return false
        }
    }
}

public struct AnimalBodyPart: Codable, Sendable, Equatable {
    public let kind: AnimalBodyPartKind
    /// 0…1: 1 whole, 0 destroyed. A missing part reads as `missing == true`.
    public var condition: Double
    public var missing: Bool

    public init(kind: AnimalBodyPartKind, condition: Double = 1, missing: Bool = false) {
        self.kind = kind
        self.condition = condition
        self.missing = missing
    }
}

/// A lasting mark on an animal — a wound, an illness, cold or heat damage. The
/// pawn-like health layer: an animal can *carry* these, not just have a number.
public enum AnimalConditionKind: String, Codable, Sendable {
    case injury, disease, frostbite, heatstroke
}

public struct AnimalCondition: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var kind: AnimalConditionKind
    /// The body part it sits on, when it sits on one.
    public var part: AnimalBodyPartKind?
    /// 0…1 — how bad, and (for illness) how far it has progressed.
    public var severity: Double
    public var label: LocalizedText

    public init(id: UUID = UUID(), kind: AnimalConditionKind, part: AnimalBodyPartKind? = nil,
                severity: Double, label: LocalizedText) {
        self.id = id
        self.kind = kind
        self.part = part
        self.severity = severity
        self.label = label
    }
}

/// One wild animal: a life the world can eventually run the way it runs a pawn.
public struct Animal: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var species: AnimalSpecies
    public var sex: AnimalSex
    /// Age in world ticks.
    public var age: Int
    /// 0…100. Derived down as body parts fail, but stored so illness/starvation
    /// can drain it independently of trauma.
    public var health: Double
    public var body: [AnimalBodyPart]
    public var conditions: [AnimalCondition]

    public init(id: UUID, species: AnimalSpecies, sex: AnimalSex, age: Int,
                health: Double? = nil, body: [AnimalBodyPart]? = nil,
                conditions: [AnimalCondition] = []) {
        self.id = id
        self.species = species
        self.sex = sex
        self.age = age
        self.health = health ?? species.baseHealth
        self.body = body ?? species.bodyPlan.map { AnimalBodyPart(kind: $0) }
        self.conditions = conditions
    }

    public var isAlive: Bool { health > 0 && bodyPart(.head)?.missing != true && bodyPart(.torso)?.missing != true }

    public func bodyPart(_ kind: AnimalBodyPartKind) -> AnimalBodyPart? {
        body.first { $0.kind == kind }
    }

    /// Can it still stand? A quadruped needs at least two legs.
    public var canWalk: Bool {
        body.filter { $0.kind.isLeg && !$0.missing }.count >= 2
    }

    /// Wounds a body part; when its condition hits zero the part is lost, and if
    /// that part was vital the animal dies. Returns whether it is still alive.
    @discardableResult
    public mutating func injure(_ kind: AnimalBodyPartKind, by amount: Double) -> Bool {
        health = max(0, health - amount)
        if let i = body.firstIndex(where: { $0.kind == kind }), !body[i].missing {
            body[i].condition = max(0, body[i].condition - amount / 40)
            if body[i].condition <= 0 {
                body[i].missing = true
                if kind.isVital { health = 0 }
            }
        }
        return isAlive
    }
}

/// Builds wild animals deterministically — same seed, same beasts.
public enum AnimalFactory {
    /// Roughly a year in ticks — animals only need an approximate age here.
    static let ticksPerYear = 60

    /// A group of one species, sized to `count`. Deterministic from `rng`.
    public static func herd(_ species: AnimalSpecies, count: Int,
                            rng: inout SeededRNG) -> [Animal] {
        (0..<max(0, count)).map { _ in
            let sex: AnimalSex = rng.nextUnit() < 0.5 ? .male : .female
            let years = 1 + rng.nextUnit() * 4          // yearling to a few years
            return Animal(id: rng.nextUUID(), species: species,
                          sex: sex, age: Int(years * Double(ticksPerYear)))
        }
    }

    /// The mixed wild that lives around a fresh settlement — a deer herd with a
    /// few hares and a boar for variety. Predators arrive with pressure, they
    /// are not seeded as residents. Deterministic from `rng`.
    public static func wildPopulation(rng: inout SeededRNG) -> [Animal] {
        var animals = herd(.deer, count: 6, rng: &rng)
        animals += herd(.hare, count: 2, rng: &rng)
        animals += herd(.boar, count: 1, rng: &rng)
        return animals
    }
}
