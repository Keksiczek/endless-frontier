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
    // Six species meant one valley's wild was every valley's wild, and the
    // country a colony sat in said almost nothing about what walked through it.
    // These five are chosen so each biome gets something that is *only* there:
    // an elk in the cold woods, a goat on the crags, a lynx that hunts them, a
    // badger in the hedges and a grouse worth a snare.
    case elk, goat, lynx, badger, grouse

    public var isPredator: Bool {
        switch self {
        case .wolf, .bear, .fox, .lynx: return true
        // A badger is an omnivore, but for this simulation what matters is
        // whether a hunter may take it and whether a herd flees it — and the
        // answer to both is that it is small game, not a threat.
        case .deer, .boar, .hare, .elk, .goat, .badger, .grouse: return false
        }
    }

    /// Full health for an adult of this species.
    public var baseHealth: Double {
        switch self {
        case .bear: return 170
        case .elk: return 150
        case .boar, .wolf: return 110
        case .deer: return 90
        case .lynx: return 80
        case .goat: return 70
        case .badger: return 60
        case .fox: return 55
        case .hare: return 35
        case .grouse: return 22
        }
    }

    /// The comfort band, in °C — below `comfortLow` it suffers cold, above
    /// `comfortHigh` it suffers heat. (Consumed by the temperature layer later.)
    public var comfortLow: Double {
        switch self {
        case .elk: return -38
        case .bear, .wolf: return -35
        case .lynx: return -32
        case .goat, .grouse: return -30
        case .badger: return -26
        case .hare: return -25
        case .deer, .fox: return -20
        case .boar: return -15
        }
    }
    public var comfortHigh: Double {
        switch self {
        case .boar: return 38
        case .goat: return 36
        case .deer, .hare, .fox: return 32
        case .wolf, .badger, .grouse: return 30
        case .bear, .lynx: return 28
        // The one that cannot take a hot summer, which is why it belongs to
        // the cold woods and nowhere else.
        case .elk: return 24
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
        case .elk: return LocalizedText(values: [.en: "Elk", .cs: "Los"])
        case .goat: return LocalizedText(values: [.en: "Wild goat", .cs: "Koza bezoárová"])
        case .lynx: return LocalizedText(values: [.en: "Lynx", .cs: "Rys"])
        case .badger: return LocalizedText(values: [.en: "Badger", .cs: "Jezevec"])
        case .grouse: return LocalizedText(values: [.en: "Grouse", .cs: "Tetřev"])
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
    /// The leg it just walked, so the canvas can draw a beast crossing the
    /// meadow instead of one standing still and jumping.
    ///
    /// A beast thinks every `AnimalEngine.thinkInterval` ticks and a tick is
    /// two real minutes, so grazing deer held one pose for **twenty minutes**
    /// and then teleported a stride. `position` is still the simulation's
    /// answer on the tick — a hunter walks to *that* — and this is the same
    /// stride given a beginning and an end so the canvas can fill in between.
    /// Nil for a beast that has not moved yet, and for one out of an old save.
    public var walk: WalkPath?
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
                walk: WalkPath? = nil,
                activity: AnimalActivity = .grazing,
                tameProgress: Double = 0) {
        self.walk = walk
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
        case tameProgress, walk
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
        // A beast saved before its strides had a beginning and an end is simply
        // standing at `position` until it next thinks (rule 3).
        walk = try c.decodeIfPresent(WalkPath.self, forKey: .walk)
    }

    /// Where to draw it at a *continuous* tick. Falls back to the tick's own
    /// answer for a beast that has not moved yet, or one out of an old save.
    public func position(at tick: Double) -> LocalPoint {
        walk?.position(at: tick) ?? position
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
        // An elk feeds a colony for a week, which is the whole reason to take
        // one on rather than a deer.
        case .elk: size = 30
        case .boar: size = 22
        case .deer: size = 20
        case .goat: size = 14
        case .wolf, .lynx: size = 12
        case .badger: size = 7
        case .fox: size = 6
        case .hare: size = 3
        case .grouse: size = 2
        }
        // A half-starved beast carries less on it.
        return size * (0.55 + 0.45 * min(1, health / species.baseHealth))
    }

    /// Whether this is a beast that fights back. A cornered boar is the reason
    /// hunting is dangerous work and not a harvest.
    public var isDangerous: Bool {
        switch species {
        // An elk in rut will put a hunter in the ground, and a cornered lynx
        // is not a fox. A goat only ever runs.
        case .bear, .boar, .wolf, .elk, .lynx: return true
        case .deer, .fox, .hare, .goat, .badger, .grouse: return false
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

    /// The mixed wild that lives around a fresh settlement.
    ///
    /// Two things were wrong with the old nine-animal valley:
    ///
    /// 1. **It was the same nine everywhere.** Six deer, two hares and a boar,
    ///    in a desert exactly as in a forest — so the wild said nothing about
    ///    the country it lived in.
    /// 2. **Predators were never seeded at all.** `isPredator` is honoured all
    ///    over the engine — hunters skip them, prey flee them, they stalk the
    ///    weak — and not one wolf, fox or bear had ever been put on a map, so
    ///    every one of those paths was dead code. The wild was a pressure
    ///    number with deer drawn next to it.
    ///
    /// `hazard` is the region's own danger, so a frontier valley six rings out
    /// really does have more teeth in it than the homeland.
    /// Deterministic from `rng`.
    public static func wildPopulation(
        biomeID: String = "plains", hazard: Int = 0, rng: inout SeededRNG
    ) -> [Animal] {
        var animals: [Animal] = []
        for (species, fewest, most) in mix(for: biomeID) {
            let count = fewest + Int(rng.nextUnit() * Double(max(1, most - fewest + 1)))
            animals += herd(species, count: count, rng: &rng)
        }
        // Wilder country carries more of them, up to a pack.
        if hazard > 0 {
            animals += herd(.wolf, count: min(4, 1 + hazard / 2), rng: &rng)
        }
        return animals
    }

    /// What lives in a given country, as `(species, fewest, most)`.
    public static func mix(for biomeID: String) -> [(AnimalSpecies, Int, Int)] {
        switch biomeID {
        case "forest":
            return [(.deer, 7, 10), (.hare, 4, 7), (.boar, 3, 5), (.fox, 2, 3),
                    (.wolf, 1, 2), (.elk, 2, 3), (.badger, 2, 3), (.grouse, 3, 5),
                    (.lynx, 1, 2)]
        case "coast":
            return [(.deer, 5, 8), (.hare, 5, 8), (.fox, 2, 3), (.boar, 1, 2),
                    (.grouse, 2, 4), (.badger, 1, 2)]
        case "tundra":
            return [(.deer, 5, 8), (.hare, 3, 5), (.wolf, 2, 4), (.fox, 1, 2),
                    (.elk, 3, 5), (.grouse, 2, 3)]
        case "mountains":
            return [(.deer, 3, 5), (.hare, 3, 5), (.boar, 2, 3), (.bear, 1, 2),
                    (.wolf, 1, 2), (.goat, 4, 7), (.lynx, 1, 2)]
        case "wetlands":
            return [(.grouse, 6, 9), (.boar, 4, 6), (.deer, 4, 6), (.hare, 3, 5),
                    (.badger, 2, 4), (.fox, 2, 3), (.elk, 1, 2)]
        case "desert":
            return [(.hare, 4, 6), (.fox, 2, 3), (.boar, 1, 2), (.deer, 1, 3),
                    (.goat, 2, 4)]
        default: // plains & homeland
            return [(.deer, 10, 14), (.hare, 6, 9), (.boar, 2, 3), (.fox, 2, 3),
                    (.grouse, 3, 5), (.badger, 1, 3)]
        }
    }
}
