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

/// What a beast is presently up to. A far lighter mind than a colonist's — an
/// animal has no schedule, no post and no trade — but enough of one that the
/// valley is inhabited rather than decorated.
public enum AnimalActivity: String, Codable, Sendable {
    case grazing    // head down, drifting with the herd
    case wary       // something is wrong; it has stopped to look
    case fleeing    // running, and not stopping to think about where
    case stalking   // a predator closing on something
    case resting
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

    /// Where it is, in the same normalised space everything else on the local
    /// map lives in.
    ///
    /// It used to be nowhere. The canvas derived a position from the animal's
    /// id and the frame clock, which is the right answer for a *decoration* and
    /// the wrong one for a thing with a body: a deer could not be somewhere a
    /// hunter walks to, could not be startled off a field, could not be found
    /// dead where it fell. Storing it is what lets the hunt be an encounter
    /// between two things that are in the same place.
    public var position: LocalPoint
    /// What it is doing right now — set by the think-step, read by the canvas.
    public var activity: AnimalActivity
    /// How far somebody has got with gentling it, 0…1. At 1 it stops running
    /// and joins the colony (`TamedAnimal`). Wild beasts sit at 0 for ever
    /// unless a hunter starts working at them.
    public var tameProgress: Double

    public init(id: UUID, species: AnimalSpecies, sex: AnimalSex, age: Int,
                health: Double? = nil, body: [AnimalBodyPart]? = nil,
                conditions: [AnimalCondition] = [],
                position: LocalPoint = LocalPoint(x: 0.5, y: 0.5),
                activity: AnimalActivity = .grazing,
                tameProgress: Double = 0) {
        self.id = id
        self.species = species
        self.sex = sex
        self.age = age
        self.health = health ?? species.baseHealth
        self.body = body ?? species.bodyPlan.map { AnimalBodyPart(kind: $0) }
        self.conditions = conditions
        self.position = position
        self.activity = activity
        self.tameProgress = min(1, max(0, tameProgress))
    }

    // MARK: - Codable (resilient: beasts stood nowhere before they roamed)

    private enum CodingKeys: String, CodingKey {
        case id, species, sex, age, health, body, conditions, position, activity
        case tameProgress
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        species = try c.decode(AnimalSpecies.self, forKey: .species)
        sex = try c.decode(AnimalSex.self, forKey: .sex)
        age = try c.decode(Int.self, forKey: .age)
        health = try c.decode(Double.self, forKey: .health)
        body = try c.decode([AnimalBodyPart].self, forKey: .body)
        conditions = try c.decode([AnimalCondition].self, forKey: .conditions)
        // An older save's beasts have never stood anywhere. Scattering them from
        // their own id puts the herd back on the map without a fresh RNG draw,
        // which would shift every roll after it.
        position = try c.decodeIfPresent(LocalPoint.self, forKey: .position)
            ?? Animal.scatter(id)
        activity = try c.decodeIfPresent(AnimalActivity.self, forKey: .activity) ?? .grazing
        tameProgress = try c.decodeIfPresent(Double.self, forKey: .tameProgress) ?? 0
    }

    /// A stable spot on the map for a beast that has never had one, spread over
    /// the middle distance and clear of the built heart.
    public static func scatter(_ id: UUID) -> LocalPoint {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        let b = id.uuid
        for byte in [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7] {
            h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3
        }
        let angle = Double(h % 6283) / 1000
        let radius = 0.18 + Double((h >> 20) % 1000) / 1000 * 0.22
        return LocalPoint(x: min(0.97, max(0.03, 0.5 + cos(angle) * radius)),
                          y: min(0.97, max(0.03, 0.52 + sin(angle) * radius * 0.82)))
    }

    public var isAlive: Bool { health > 0 && bodyPart(.head)?.missing != true && bodyPart(.torso)?.missing != true }

    public func bodyPart(_ kind: AnimalBodyPartKind) -> AnimalBodyPart? {
        body.first { $0.kind == kind }
    }

    /// Can it still stand? A quadruped needs at least two legs.
    public var canWalk: Bool {
        body.filter { $0.kind.isLeg && !$0.missing }.count >= 2
    }

    /// How much meat a carcass of this kind is worth. A bear is a season's
    /// eating and a hare is a supper, and until the hunt took *named animals*
    /// there was no way for that to be true.
    public var meatYield: Double {
        let size: Double
        switch species {
        case .bear: size = 34
        case .boar: size = 22
        case .deer: size = 20
        case .wolf: size = 12
        case .fox: size = 6
        case .hare: size = 3
        }
        // A half-starved beast carries less on it.
        return size * (0.55 + 0.45 * min(1, health / species.baseHealth))
    }

    /// Whether this is a beast that fights back. A cornered boar is the reason
    /// hunting is dangerous work and not a harvest.
    public var isDangerous: Bool {
        switch species {
        case .bear, .boar, .wolf: return true
        case .deer, .fox, .hare: return false
        }
    }

    /// What it does to a hunter who gets it wrong, before armour.
    public var retaliation: Double {
        switch species {
        case .bear: return 34
        case .boar: return 20
        case .wolf: return 15
        default: return 0
        }
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
    ///
    /// They are put down as a *group*: one loose gathering place, with each
    /// beast a short step from it, because a herd is a herd and six deer
    /// scattered over the whole valley is six lone deer.
    public static func herd(_ species: AnimalSpecies, count: Int,
                            rng: inout SeededRNG) -> [Animal] {
        (0..<max(0, count)).map { _ in
            let sex: AnimalSex = rng.nextUnit() < 0.5 ? .male : .female
            let years = 1 + rng.nextUnit() * 4          // yearling to a few years
            let id = rng.nextUUID()
            return Animal(id: id, species: species,
                          sex: sex, age: Int(years * Double(ticksPerYear)),
                          position: Animal.scatter(id))
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
