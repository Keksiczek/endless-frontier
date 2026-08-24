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
/// **What saves written before beasts were data are carrying.**
///
/// Species used to be this enum with six hand-written tables hanging off it,
/// and an `Animal` stored the case. They are `animals.json` now
/// (`AnimalDefinition`), so a twelfth beast is a JSON entry rather than Swift
/// in five files — but every colony already on disk has `"species": "deer"`
/// and no numbers beside it, and `Animal.init(from:)` has no registry.
///
/// So these eleven are **frozen**. Nothing is ever added: no save can contain
/// a beast that did not exist when it was written. A snapshot of history, not
/// a second source of truth — `animals.json` is the authority for everything
/// the world puts on a map from now on, and `AnimalContentTests` holds the two
/// in agreement for the eleven that appear in both.
enum LegacyAnimalSpecies: String, CaseIterable {
    case deer, boar, hare, fox, wolf, bear
    // Six species meant one valley's wild was every valley's wild, and the
    // country a colony sat in said almost nothing about what walked through it.
    // These five are chosen so each biome gets something that is *only* there:
    // an elk in the cold woods, a goat on the crags, a lynx that hunts them, a
    // badger in the hedges and a grouse worth a snare.
    case elk, goat, lynx, badger, grouse

    var isPredator: Bool {
        switch self {
        case .wolf, .bear, .fox, .lynx: return true
        // A badger is an omnivore, but for this simulation what matters is
        // whether a hunter may take it and whether a herd flees it — and the
        // answer to both is that it is small game, not a threat.
        case .deer, .boar, .hare, .elk, .goat, .badger, .grouse: return false
        }
    }

    /// Full health for an adult of this species.
    var baseHealth: Double {
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
    var comfortLow: Double {
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
    var comfortHigh: Double {
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

    var displayName: LocalizedText {
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
    var bodyPlan: [AnimalBodyPartKind] {
        [.head, .torso, .frontLeftLeg, .frontRightLeg, .backLeftLeg, .backRightLeg]
    }

    /// How big it is drawn against a person.
    ///
    /// **Load-bearing, not decoration.** Meat, retaliation and whether a beast
    /// is dangerous at all are derived from size now, so a beast that falls
    /// back to a default size is a beast that is quietly the wrong animal —
    /// which is exactly what happened when this was missing: every `Animal`
    /// built by name came out at `Animal.defaultSize`, so a boar stopped being
    /// dangerous and a bear stopped being worth a season's eating.
    var size: Double {
        switch self {
        case .grouse: return 1.3
        case .hare: return 1.5
        case .badger: return 2.0
        case .fox: return 2.2
        case .goat: return 2.6
        case .lynx: return 2.8
        case .boar: return 3.0
        case .wolf: return 3.2
        case .deer: return 3.4
        case .elk: return 4.2
        case .bear: return 4.6
        }
    }

    var build: AnimalDefinition.Build {
        switch self {
        case .elk: return .elk
        case .goat: return .goat
        case .boar: return .boar
        case .hare, .grouse: return .small
        case .fox, .wolf, .bear: return .canid
        case .lynx: return .lynx
        case .badger: return .badger
        case .deer: return .deer
        }
    }
}

/// A part of an animal's body — losing a vital one kills, losing a leg cripples.
public enum AnimalBodyPartKind: String, Codable, Sendable, CaseIterable {
    case head, torso, frontLeftLeg, frontRightLeg, backLeftLeg, backRightLeg

    /// The body every animal is born with.
    ///
    /// It hung off the species and answered the same six parts for all eleven
    /// of them, which is a table pretending to be a decision. It belongs to the
    /// part kinds, and a species that wants a different body will need the game
    /// to grow wings before it needs a field.
    public static let wholeBody: [AnimalBodyPartKind] = [
        .head, .torso, .frontLeftLeg, .frontRightLeg, .backLeftLeg, .backRightLeg
    ]

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
    /// Which kind of beast this is — an `AnimalDefinition` id.
    public var species: String
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

    // MARK: - What this beast is, carried on the beast

    /// Full health for an adult of its kind, how big it is drawn, the body the
    /// canvas draws, and whether it hunts.
    ///
    /// **Copied onto the animal when it is born**, for the reason `Tree` does
    /// the same: these are read in the middle of a hunt, a roam and a frame —
    /// `isPredator` alone is asked once per animal per animal every think —
    /// and threading a registry through `AnimalEngine.roam`, `HuntEngine` and
    /// the canvas would be a registry in twenty signatures to answer a question
    /// a beast already knows about itself.
    public let baseHealth: Double
    public let size: Double
    public let build: AnimalDefinition.Build
    public let isPredator: Bool
    /// The comfort band in °C. Carried for the same reason the rest is: the
    /// cold check runs on every beast every tick, deep inside a pure engine
    /// function with no book to hand.
    public let comfortLow: Double
    public let comfortHigh: Double

    public init(id: UUID, species: String, sex: AnimalSex, age: Int,
                health: Double? = nil, body: [AnimalBodyPart]? = nil,
                conditions: [AnimalCondition] = [],
                position: LocalPoint = LocalPoint(x: 0.5, y: 0.5),
                walk: WalkPath? = nil,
                activity: AnimalActivity = .grazing,
                tameProgress: Double = 0,
                baseHealth: Double? = nil, size: Double? = nil,
                build: AnimalDefinition.Build? = nil, isPredator: Bool? = nil,
                comfortLow: Double? = nil, comfortHigh: Double? = nil) {
        let legacy = LegacyAnimalSpecies(rawValue: species)
        self.walk = walk
        self.id = id
        self.species = species
        self.sex = sex
        self.age = age
        self.baseHealth = baseHealth ?? legacy?.baseHealth ?? 80
        self.size = size ?? legacy?.size ?? Animal.defaultSize
        self.build = build ?? legacy?.build ?? .deer
        self.isPredator = isPredator ?? legacy?.isPredator ?? false
        self.comfortLow = comfortLow ?? legacy?.comfortLow ?? -25
        self.comfortHigh = comfortHigh ?? legacy?.comfortHigh ?? 30
        self.health = health ?? self.baseHealth
        self.body = body ?? AnimalBodyPartKind.wholeBody.map { AnimalBodyPart(kind: $0) }
        self.conditions = conditions
        self.position = position
        self.activity = activity
        self.tameProgress = min(1, max(0, tameProgress))
    }

    /// One of a kind the content describes.
    public init(id: UUID, definition: AnimalDefinition, sex: AnimalSex, age: Int,
                health: Double? = nil, position: LocalPoint = LocalPoint(x: 0.5, y: 0.5)) {
        self.init(id: id, species: definition.id, sex: sex, age: age,
                  health: health, position: position,
                  baseHealth: definition.baseHealth, size: definition.size,
                  build: definition.build, isPredator: definition.isPredator,
                  comfortLow: definition.comfortLow, comfortHigh: definition.comfortHigh)
    }

    /// How big a beast nobody described is drawn. Between a fox and a boar —
    /// the size at which "some animal" is neither a mouse nor a bear.
    public static let defaultSize: Double = 2.6

    // MARK: - Codable (resilient: beasts stood nowhere before they roamed)

    private enum CodingKeys: String, CodingKey {
        case id, species, sex, age, health, body, conditions, position, activity
        case tameProgress, walk, baseHealth, size, build, isPredator
        case comfortLow, comfortHigh
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        species = try c.decode(String.self, forKey: .species)
        // A beast born before species were data carries only its name. The
        // frozen table is what that name meant — see `LegacyAnimalSpecies`.
        let legacy = LegacyAnimalSpecies(rawValue: species)
        baseHealth = try c.decodeIfPresent(Double.self, forKey: .baseHealth)
            ?? legacy?.baseHealth ?? 80
        size = try c.decodeIfPresent(Double.self, forKey: .size)
            ?? legacy?.size ?? Animal.defaultSize
        build = try c.decodeIfPresent(AnimalDefinition.Build.self, forKey: .build)
            ?? legacy?.build ?? .deer
        isPredator = try c.decodeIfPresent(Bool.self, forKey: .isPredator)
            ?? legacy?.isPredator ?? false
        comfortLow = try c.decodeIfPresent(Double.self, forKey: .comfortLow)
            ?? legacy?.comfortLow ?? -25
        comfortHigh = try c.decodeIfPresent(Double.self, forKey: .comfortHigh)
            ?? legacy?.comfortHigh ?? 30
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

    /// How much meat one point of an animal's drawn size is worth.
    ///
    /// Set so the eleven that shipped keep very nearly the yields they had —
    /// a bear was 34 at size 4.6, a hare 3 at 1.5 — which is what makes this a
    /// derivation rather than a rebalance.
    public static let meatPerSize: Double = 7.2

    /// How much meat a carcass of this kind is worth. A bear is a season's
    /// eating and a hare is a supper, and until the hunt took *named animals*
    /// there was no way for that to be true.
    public var meatYield: Double {
        // **Derived from how big it is**, not from a table of eleven numbers.
        //
        // Size and meat said the same thing twice (rule 8) and could disagree:
        // an elk drawn at 4.2 and a bear at 4.6 carried 30 and 34, which is the
        // same ratio the sizes already gave. A beast the content adds now feeds
        // the colony in proportion to how big it looks, which is the answer a
        // player would predict from looking at it.
        let carcass = size * Animal.meatPerSize
        // A half-starved beast carries less on it.
        return carcass * (0.55 + 0.45 * min(1, health / baseHealth))
    }

    /// Whether this is a beast that fights back. A cornered boar is the reason
    /// hunting is dangerous work and not a harvest.
    /// **Derived from what it is and how big it is**, rather than from a
    /// twelfth list of names. Anything that hunts fights back, and so does
    /// anything heavy enough to be worth being afraid of — an elk in rut will
    /// put a hunter in the ground and a cornered lynx is not a fox, while a
    /// goat of the same weight only ever runs because it does not hunt.
    public var isDangerous: Bool {
        isPredator || size >= Animal.dangerousFrom
    }

    /// How big a plant-eater has to be before it is worth being careful of.
    /// Set between a goat and a boar, which is where the line was drawn by
    /// hand before this.
    public static let dangerousFrom: Double = 2.9

    /// What it does to a hunter who gets it wrong, before armour.
    /// Also derived: what it hits with is what it has, and what it has is its
    /// weight. Zero for anything that is not dangerous at all, so a hare is a
    /// hare whatever the arithmetic says.
    public var retaliation: Double {
        guard isDangerous else { return 0 }
        return size * Animal.retaliationPerSize
    }

    /// A bear at 4.6 comes out around thirty-four and a wolf at 3.2 around
    /// twenty-three, which is where the hand-written table had them.
    public static let retaliationPerSize: Double = 7.3

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
    public static func herd(_ species: AnimalDefinition, count: Int,
                            rng: inout SeededRNG) -> [Animal] {
        (0..<max(0, count)).map { _ in
            let sex: AnimalSex = rng.nextUnit() < 0.5 ? .male : .female
            let years = 1 + rng.nextUnit() * 4          // yearling to a few years
            let id = rng.nextUUID()
            return Animal(id: id, definition: species,
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
        biomeID: String = "plains", hazard: Int = 0,
        registry: GameDataRegistry, rng: inout SeededRNG
    ) -> [Animal] {
        var animals: [Animal] = []
        for (species, fewest, most) in mix(for: biomeID, registry: registry) {
            let count = fewest + Int(rng.nextUnit() * Double(max(1, most - fewest + 1)))
            animals += herd(species, count: count, rng: &rng)
        }
        // Wilder country carries more of them, up to a pack.
        if hazard > 0 {
            // Whatever this country's own hunter is. A valley with no predator
            // in the book simply stays quiet, rather than having a wolf posted
            // into it because the code knew that word.
            if let hunter = registry.animals(inBiome: biomeID)
                .first(where: { $0.0.isPredator })?.0 {
                animals += herd(hunter, count: min(4, 1 + hazard / 2), rng: &rng)
            }
        }
        return animals
    }

    /// What lives in a given country, and how many.
    ///
    /// Read off `animals.json` rather than a `switch`, so a beast added to the
    /// content lives somewhere on the day it ships. A biome the content names
    /// nothing for gets an empty valley — a content hole, which the tests
    /// refuse, rather than a silent default that hides it.
    public static func mix(
        for biomeID: String, registry: GameDataRegistry
    ) -> [(AnimalDefinition, Int, Int)] {
        registry.animals(inBiome: biomeID).map { ($0.0, $0.1.min, $0.1.max) }
    }

}
