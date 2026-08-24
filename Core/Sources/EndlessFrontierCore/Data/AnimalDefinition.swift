import Foundation

/// **What a kind of beast is**, as data rather than as a `switch`.
///
/// The same move `FloraDefinition` made for trees, and for the same reason:
/// `AnimalSpecies` was eleven enum cases with six hand-written tables hanging
/// off them and a biome mix in a seventh, so a twelfth beast meant Swift in
/// five files and a new drawing. `Tools/generate.py kinds` refused animals
/// outright — *"`AnimalFactory` builds beasts in code; there is no
/// animals.json to write into."*
///
/// **`build` is the part that makes a new beast look like itself.** The canvas
/// has drawn eight bodies for a while — a deer's high shoulder, an elk's
/// weight, a goat's horns, a boar's hump, a small game bird or hare, a canid,
/// a lynx, a badger — and every one was reachable only by naming an enum case.
/// A species names its build and has a real animal on the day it ships, which
/// is the whole difference between content and a list of words
/// (`ef-composition-not-shapes`).
public struct AnimalDefinition: Codable, Sendable, Identifiable, Equatable {

    /// The body the canvas draws it with. A closed set: each case is a piece of
    /// drawing that exists, and a beast asking for a build nobody drew would be
    /// an animal that is not there.
    public enum Build: String, Codable, Sendable, CaseIterable {
        /// A high shoulder and a light frame — deer and their kin.
        case deer
        /// The same frame with weight and a rack on it.
        case elk
        /// …and the same frame with horns that sweep back.
        case goat
        /// Low, humped and heavy at the front.
        case boar
        /// Small game — something a snare takes.
        case small
        /// A dog's outline: level back, long muzzle, brush.
        case canid
        /// Short-bodied, high-rumped, tufted.
        case lynx
        /// Low and broad, close to the ground.
        case badger
    }

    /// How a beast lives, which decides what it does when it meets another one.
    ///
    /// Not `isPredator: Bool`, because the interesting middle exists: a badger
    /// is an omnivore, and what matters to the simulation is that a hunter may
    /// take it and a herd need not run from it. The two questions the game
    /// actually asks — *does this hunt* and *is this game* — both fall out of
    /// this without anybody writing a second flag.
    public enum Diet: String, Codable, Sendable, CaseIterable {
        case grazer
        case forager
        case hunter

        /// Whether the herd runs from it and a hunter thinks twice.
        public var isPredator: Bool { self == .hunter }
    }

    /// How many of a kind a country carries, and how many at most.
    public struct Range: Codable, Sendable, Equatable {
        public let id: String
        public let min: Int
        public let max: Int

        public init(id: String, min: Int, max: Int) {
            self.id = id
            self.min = Swift.max(0, min)
            self.max = Swift.max(self.min, max)
        }
    }

    public let id: String
    public let name: LocalizedText
    public let build: Build
    public let diet: Diet
    /// How big it is drawn against a person. A grouse is a little over one, an
    /// elk is four and a bear is nearer five.
    public let size: Double
    /// Full health for an adult.
    public let baseHealth: Double
    /// The comfort band in °C — below `comfortLow` it suffers cold, above
    /// `comfortHigh` it suffers heat.
    public let comfortLow: Double
    public let comfortHigh: Double
    /// Where it lives, and how many. A species named by no biome lives nowhere,
    /// which the content check treats as a fault rather than as a choice.
    public let biomes: [Range]
    /// How readily it gentles, 0…1. **This is what makes taming a choice**: a
    /// boar is worth the season it costs, a bear is a long shot that pays for
    /// itself at the gate, and nobody sane spends a winter on a hare.
    public let tameability: Double
    /// What a tamed one is *for*.
    public let role: TamedRole
    public let description: LocalizedText

    public var isPredator: Bool { diet.isPredator }

    public init(
        id: String,
        name: LocalizedText,
        build: Build = .deer,
        diet: Diet = .grazer,
        size: Double = 3,
        baseHealth: Double = 80,
        comfortLow: Double = -25,
        comfortHigh: Double = 30,
        biomes: [Range] = [],
        tameability: Double = 0.4,
        role: TamedRole = .companion,
        description: LocalizedText = LocalizedText("")
    ) {
        self.id = id
        self.name = name
        self.build = build
        self.diet = diet
        self.size = max(0.2, size)
        self.baseHealth = max(1, baseHealth)
        self.comfortLow = comfortLow
        self.comfortHigh = comfortHigh
        self.biomes = biomes
        self.tameability = Swift.min(1, Swift.max(0, tameability))
        self.role = role
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, build, diet, size, baseHealth
        case comfortLow, comfortHigh, biomes, tameability, role, description
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(LocalizedText.self, forKey: .name)
        build = try c.decodeIfPresent(Build.self, forKey: .build) ?? .deer
        diet = try c.decodeIfPresent(Diet.self, forKey: .diet) ?? .grazer
        size = max(0.2, try c.decodeIfPresent(Double.self, forKey: .size) ?? 3)
        baseHealth = max(1, try c.decodeIfPresent(Double.self, forKey: .baseHealth) ?? 80)
        comfortLow = try c.decodeIfPresent(Double.self, forKey: .comfortLow) ?? -25
        comfortHigh = try c.decodeIfPresent(Double.self, forKey: .comfortHigh) ?? 30
        biomes = try c.decodeIfPresent([Range].self, forKey: .biomes) ?? []
        tameability = Swift.min(1, Swift.max(0, try c.decodeIfPresent(Double.self, forKey: .tameability) ?? 0.4))
        role = try c.decodeIfPresent(TamedRole.self, forKey: .role) ?? .companion
        description = try c.decodeIfPresent(LocalizedText.self, forKey: .description) ?? ""
    }
}
