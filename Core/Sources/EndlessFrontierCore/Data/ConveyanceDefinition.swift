import Foundation

/// What a conveyance *is* — one kind of thing that carries a body or a load.
///
/// **A mount and a cart are the same thing.** Both move a body faster than its
/// legs, carry more than a back can, have to be kept, and can be lost. They
/// differ only in what supplies them: a mount is an animal the colony gentled,
/// a vehicle is something it built. Writing horses and then carts and then
/// trucks as three systems is how a game ends up with three half-working ones,
/// so there is one definition and every age uses it — a travois and an orbital
/// lifter differ in their numbers and in nothing else.
///
/// See `docs/MOUNTS_AND_VEHICLES.md` for the design and the four seams this has
/// to reach before any of it is more than a picture of a horse.
public struct ConveyanceDefinition: Codable, Sendable, Identifiable, Equatable {

    /// What supplies it, and therefore how the colony comes by one.
    public enum Class: String, Codable, Sendable, CaseIterable {
        /// A tamed beast somebody rides. Backed by an `Animal`, so it can be
        /// hurt, fall ill and die.
        case mount
        /// Pulled or pushed: travois, handcart, wagon, barge.
        case cart
        /// Runs on a way that has to be built between two places.
        case rail
        /// Burns something. Grounded by a shortage of it.
        case motor
        /// Ignores the ground entirely, and pays for the privilege.
        case air
    }

    public let id: String
    public let name: LocalizedText
    public let description: LocalizedText
    public let era: Era

    /// What kind of thing this is. `mount` reads `requiresAnimal`; the rest
    /// ignore it.
    public let kind: Class

    /// For a mount: which species it is, by the raw value of `AnimalSpecies`.
    /// A conveyance naming a species the wild never produces is a conveyance
    /// the colony can never tame.
    public let requiresAnimal: String?
    /// Where it is made or kept — a `buildings.json` id.
    public let requiresBuilding: String?
    /// What has to be known first — a `techs.json` id.
    public let requiresTech: String?
    /// What one costs to build, by item id.
    public let materials: [String: Int]

    /// How many people it carries, including whoever is driving.
    public let riders: Int
    /// How much it carries, in multiples of what one colonist's back holds.
    public let cargo: Int

    /// How much faster than walking it crosses the **local map**, as a
    /// multiplier on `WalkPace`. Below 1 is legitimate and interesting: a
    /// travois is slower than a person and carries three times as much, which
    /// is the first real trade-off the colony ever gets.
    public let pace: Double

    /// The same idea on the **road between places** — expeditions and caravans,
    /// which count in ticks rather than in action steps.
    ///
    /// Stated separately rather than derived, because the two are measured in
    /// different units and one number applied to both without conversion is
    /// rule 34 waiting to happen. A barge is fast on a river and useless in a
    /// valley; a mule is the reverse.
    public let regionPace: Double

    /// What keeping one costs, per tick, per conveyance. A horse eats whether
    /// or not it is ridden — this is what makes forty of them a decision
    /// (rule 14: a rate times an entity count).
    ///
    /// `Resources` rather than `[ResourceType: Double]`: Swift encodes a
    /// dictionary whose key is not `String` or `Int` as a **flat array**, so
    /// `"upkeep": {"food": 0.35}` threw `typeMismatch` and — because the
    /// registry rethrows now (rule 40) — took every other bank down with it.
    /// Every other cost in this repository is already a `Resources`, which is
    /// the answer this should have reached for first.
    public let upkeep: Resources

    /// The ground it can cross, by `GroundCover` raw value. **Empty means
    /// anything**, which is what an airship is for.
    ///
    /// This is the field that stops the whole system being a straight upgrade
    /// ladder. A cart cannot cross marsh or scree; a mule takes a pass a horse
    /// refuses; an airship does not care and burns fuel the whole time. Without
    /// it every conveyance is strictly better than the last and the only
    /// question is whether you have unlocked it, which is not a choice.
    public let terrain: [String]

    /// What it is worth in a fight — a rider charges, a wagon is something to
    /// stand behind. Nil for the things that are no use at all in one.
    public let combat: [String: Double]?

    public init(
        id: String,
        name: LocalizedText,
        description: LocalizedText,
        era: Era,
        kind: Class,
        requiresAnimal: String? = nil,
        requiresBuilding: String? = nil,
        requiresTech: String? = nil,
        materials: [String: Int] = [:],
        riders: Int = 1,
        cargo: Int = 1,
        pace: Double = 1,
        regionPace: Double = 1,
        upkeep: Resources = Resources(),
        terrain: [String] = [],
        combat: [String: Double]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.era = era
        self.kind = kind
        self.requiresAnimal = requiresAnimal
        self.requiresBuilding = requiresBuilding
        self.requiresTech = requiresTech
        self.materials = materials
        self.riders = max(0, riders)
        self.cargo = max(0, cargo)
        self.pace = max(0.05, pace)
        self.regionPace = max(0.05, regionPace)
        self.upkeep = upkeep
        self.terrain = terrain
        self.combat = combat
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, era, materials, riders, cargo, pace, upkeep
        case terrain, combat
        case kind = "class"
        case requiresAnimal = "requires_animal"
        case requiresBuilding = "requires_building"
        case requiresTech = "requires_tech"
        case regionPace = "region_pace"
    }

    /// Everything but `id`, `name`, `class` and `era` is optional, so the
    /// plainest entry in the file is four lines. Defaults here rather than in
    /// the file, and stated once — the synthesised decoder demanding every key
    /// is what took the whole motion bank down while the build stayed green
    /// (rule 41).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(LocalizedText.self, forKey: .name)
        description = try c.decodeIfPresent(LocalizedText.self, forKey: .description)
            ?? LocalizedText("")
        era = try c.decodeIfPresent(Era.self, forKey: .era) ?? .earlySettlement
        kind = try c.decodeIfPresent(Class.self, forKey: .kind) ?? .cart
        requiresAnimal = try c.decodeIfPresent(String.self, forKey: .requiresAnimal)
        requiresBuilding = try c.decodeIfPresent(String.self, forKey: .requiresBuilding)
        requiresTech = try c.decodeIfPresent(String.self, forKey: .requiresTech)
        materials = try c.decodeIfPresent([String: Int].self, forKey: .materials) ?? [:]
        riders = max(0, try c.decodeIfPresent(Int.self, forKey: .riders) ?? 1)
        cargo = max(0, try c.decodeIfPresent(Int.self, forKey: .cargo) ?? 1)
        pace = max(0.05, try c.decodeIfPresent(Double.self, forKey: .pace) ?? 1)
        regionPace = max(0.05, try c.decodeIfPresent(Double.self, forKey: .regionPace) ?? 1)
        upkeep = try c.decodeIfPresent(Resources.self, forKey: .upkeep) ?? Resources()
        terrain = try c.decodeIfPresent([String].self, forKey: .terrain) ?? []
        combat = try c.decodeIfPresent([String: Double].self, forKey: .combat)
    }

    /// Whether this can be taken over a given ground at all.
    public func canCross(_ cover: GroundCover) -> Bool {
        terrain.isEmpty || terrain.contains(cover.rawValue)
    }
}
