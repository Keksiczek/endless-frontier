import Foundation

/// A building's footprint on the colony grid, in tiles. Defaults to 1×1.
/// Decoded from a JSON object like `{ "w": 2, "h": 2 }`.
public struct TileSize: Codable, Sendable, Equatable {
    public let width: Int
    public let height: Int

    public init(width: Int = 1, height: Int = 1) {
        self.width = max(1, width)
        self.height = max(1, height)
    }

    private enum CodingKeys: String, CodingKey { case width = "w", height = "h" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = max(1, try c.decodeIfPresent(Int.self, forKey: .width) ?? 1)
        height = max(1, try c.decodeIfPresent(Int.self, forKey: .height) ?? 1)
    }
}

/// A layout synergy: a building gains a bonus for each orthogonally-adjacent
/// neighbour of a given kind on the colony grid. Data-defined so designers can
/// tune which buildings reward being placed together. A rule grants *either* a
/// per-tick production bonus (`resource` + `bonus`) or a morale bonus
/// (`morale`).
public struct AdjacencyRule: Codable, Sendable, Equatable {
    public let neighbor: String       // building id that triggers the bonus
    public let resource: ResourceType?
    public let bonus: Double
    public let morale: Double

    public init(neighbor: String, resource: ResourceType? = nil, bonus: Double = 0, morale: Double = 0) {
        self.neighbor = neighbor
        self.resource = resource
        self.bonus = bonus
        self.morale = morale
    }

    private enum CodingKeys: String, CodingKey { case neighbor, resource, bonus, morale }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        neighbor = try c.decode(String.self, forKey: .neighbor)
        resource = try c.decodeIfPresent(ResourceType.self, forKey: .resource)
        bonus = try c.decodeIfPresent(Double.self, forKey: .bonus) ?? 0
        morale = try c.decodeIfPresent(Double.self, forKey: .morale) ?? 0
    }
}

/// A data-defined building. Loaded from `buildings.json`. The resource loop
/// reads `production` and `consumption` each tick; `workers` gates how many
/// of a building a settlement's population can staff.
public struct BuildingDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let era: Era
    public let name: LocalizedText
    public let cost: Resources
    /// Goods the build also consumes, by item id — timber, brick, ingots.
    ///
    /// Without this the whole production chain had no customer but the armoury:
    /// you could saw a thousand beams and the only thing that ever wanted them
    /// was a sword. A building that eats brick is what makes a kiln worth
    /// standing.
    public let materialCost: [String: Int]
    public let workers: Int
    public let production: Resources
    public let consumption: Resources
    public let moraleEffect: Double
    public let defense: Double
    public let housing: Double
    /// Storage capacity this building adds to its settlement, per instance,
    /// **per resource**. Capacity is derived from buildings the same way
    /// `housing` is, so a colony that wants deeper stores has to build for them.
    ///
    /// Typed as of 2026-08-13. It used to be one number that
    /// `ResourceLoop.storageCapacity` applied to every `ResourceType` alike, so
    /// a granary — *"Stores grain against the lean months"* — deepened the
    /// colony's store of **knowledge and influence** by exactly as much as its
    /// store of grain. That was visible in the balance trace, where `materials`
    /// and `influence` sat pinned at the identical value for half a two-century
    /// run: two unrelated resources agreeing to four digits is one cap wearing
    /// five hats.
    public let storage: Resources
    /// What this building costs per tick to keep standing. When `nil` the
    /// resource loop derives it from `cost` — see `ResourceLoop.upkeep(for:)`,
    /// which is what makes upkeep scale with era without hand-authoring 46
    /// entries. Set it explicitly to opt a building out, or to give it an
    /// upkeep its build cost wouldn't imply.
    public let upkeep: Resources?
    public let pollution: Double
    /// **How much more of a raw good this building gets out of the same
    /// trunk, seam or load**, keyed by the good's item id: `{"wood": 0.6}` is
    /// three fifths again as much usable timber off a felled tree.
    ///
    /// Keks, on a colony whose forest genuinely cannot feed it: *"dřevo mě
    /// štve, ale přidávat ho není řešení — je to prostě náročné to uživit;
    /// třeba nějaká industriální pila, co bude zpracovávat dřevo
    /// efektivněji."* He is right that planting harder is not the answer. The
    /// forest sets the rate at which trunks exist (`FloraEngine.seedStand`);
    /// what a colony can change is **how much of each trunk it wastes**, and
    /// that is a building, not a season.
    ///
    /// Recovery is deliberately *not* a recipe. A better recipe competes for
    /// the same wood at the same bench and the colony ends up running both;
    /// this multiplies what reaches the shelf in the first place, so it cannot
    /// be undercut by an older standing order. Summed across every instance
    /// standing, so a second mill is worth having and a tenth is not much.
    ///
    /// Keyed by item rather than by resource because the next one to want it
    /// is a stone-cutting works reading `rough_stone`, and a `Resources` block
    /// could not have said that.
    public let recovery: [String: Double]
    public let footprint: TileSize
    /// The work this building is a place for, when its production doesn't say.
    ///
    /// Most buildings answer this themselves — a foundry produces materials, so
    /// it is a place of mining-work. Some don't produce anything and are still
    /// somewhere a colonist works: a hospital's trade is healing, and its output
    /// is a resource the ledger has no column for. Left `nil`, the work is
    /// derived from production (see `ColonyBuilder.workKind(for:)`), which is
    /// the right answer for all but a handful.
    public let work: WorkKind?
    /// An opaque archetype tag for whoever draws this building, set only where
    /// the shape cannot be read off the numbers.
    ///
    /// A lumberyard, a quarry and a workshop all just "produce materials", so
    /// nothing in the data tells a mill from a mine from a craftsman's shed —
    /// which is how every one of them came to be drawn as the same waterwheel.
    /// The Core stays presentation-agnostic: this is a name it never
    /// interprets, and the renderer maps it (falling back to deriving the shape
    /// from what the building does).
    public let look: String?
    /// How many storeys a dwelling stacks onto its footprint. One for anything
    /// you can walk into off the street; more for a tenement or an arcology,
    /// which is the only honest way a building can hold more people than its
    /// ground would allow.
    public let floors: Int
    public let adjacency: [AdjacencyRule]
    /// Player-facing flavour. `LocalizedText` decodes from a bare string too,
    /// so half-translated content files always load.
    public let description: LocalizedText

    // MARK: - How many people actually live here

    /// How many sleepers one tile of a dwelling takes.
    ///
    /// Two, not three. At three a two-by-two cabin slept a dozen, and a colony
    /// of thirty-seven had a hundred and forty-seven beds standing empty — so
    /// housing was never a claim on anything and the growth curve never bent.
    /// Two makes a hut a household of eight and gives the beds back their say.
    public static let sleepersPerTile = 2

    /// How many people this building **houses** — derived from the ground it
    /// covers and the storeys it stacks on it.
    ///
    /// `housing` in the data used to be an economic number of its own, and it
    /// disagreed with the building: a hut was one tile with four beds in it
    /// and the ledger credited it with thirty, so a colony's population cap
    /// was a village in a shed and everybody past the fourth slept rough. Two
    /// numbers for one thing (CLAUDE.md rule 8). `housing` is a **flag** now —
    /// non-zero means people live here — and this is the number, read by both
    /// the ledger (`ResourceLoop.housingCapacity`) and the beds
    /// (`HouseholdEngine.beds`).
    public var sleepers: Int {
        guard housing > 0 else { return 0 }
        return footprint.width * footprint.height * Self.sleepersPerTile * max(1, floors)
    }

    // MARK: - How much ground it actually has under crop

    /// Tiles of a farm's lot that make up one workable plot.
    public static let tilesPerPlot = 2

    /// How many plots of tilled ground this building owns.
    ///
    /// Derived from the footprint for exactly the reason `sleepers` is (rule
    /// 8): a farm that draws four tiles by three and feeds the colony out of a
    /// flat `production.food` of 6 is two numbers for one thing, and the one
    /// you can point at on the map is the ground. A `farm_basic` is six plots
    /// because it covers twelve tiles.
    ///
    /// Non-zero only for a building whose `work` is farming — the food chain
    /// starts at ground somebody tills, and a granary is a roof over grain, not
    /// a place grain comes from.
    /// **What this building is for**, as one word a player can sort by.
    ///
    /// Keks, having played it: *"sklady jsem taky nenašel jako budovu kam se
    /// itemy a materiál nosí."* The warehouse has been in the game since the
    /// early settlement era and is called *Sklad* — the fault was that the build
    /// bar is one alphabetical strip of every building the colony can raise, so
    /// finding the store means scrolling past eleven things that are not it.
    ///
    /// Derived from what the definition already says rather than a hand-kept
    /// list, in the order a player would ask: a granary is a store even though
    /// it also lifts morale, a palisade is defence even though it costs timber.
    public enum Purpose: String, Codable, Sendable, CaseIterable {
        case home, food, store, defence, work, study
    }

    public var purpose: Purpose {
        if defense > 0 { return .defence }
        if !storage.amounts.filter({ $0.value > 0 }).isEmpty { return .store }
        if housing > 0 { return .home }
        if plots > 0 || production[.food] > 0 { return .food }
        if production[.knowledge] > 0 { return .study }
        return .work
    }

    public var plots: Int {
        guard work == .farming else { return 0 }
        return max(1, footprint.width * footprint.height / Self.tilesPerPlot)
    }

    public init(
        id: String,
        era: Era,
        name: LocalizedText,
        cost: Resources = Resources(),
        materialCost: [String: Int] = [:],
        workers: Int = 0,
        production: Resources = Resources(),
        consumption: Resources = Resources(),
        moraleEffect: Double = 0,
        defense: Double = 0,
        housing: Double = 0,
        storage: Resources = Resources(),
        upkeep: Resources? = nil,
        pollution: Double = 0,
        recovery: [String: Double] = [:],
        footprint: TileSize = TileSize(),
        work: WorkKind? = nil,
        look: String? = nil,
        floors: Int = 1,
        adjacency: [AdjacencyRule] = [],
        description: LocalizedText = LocalizedText("")
    ) {
        self.id = id
        self.era = era
        self.name = name
        self.cost = cost
        self.materialCost = materialCost
        self.workers = workers
        self.production = production
        self.consumption = consumption
        self.moraleEffect = moraleEffect
        self.defense = defense
        self.housing = housing
        self.storage = storage
        self.upkeep = upkeep
        self.pollution = pollution
        self.recovery = recovery
        self.footprint = footprint
        self.work = work
        self.look = look
        self.floors = max(1, floors)
        self.adjacency = adjacency
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case id, era, name, cost, workers, production, consumption
        case materialCost = "material_cost"
        case moraleEffect = "morale_effect"
        case defense, housing, storage, upkeep, pollution, recovery, footprint, work, look, floors
        case adjacency
        case description
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        era = try c.decode(Era.self, forKey: .era)
        name = try c.decode(LocalizedText.self, forKey: .name)
        cost = try c.decodeIfPresent(Resources.self, forKey: .cost) ?? Resources()
        materialCost = try c.decodeIfPresent([String: Int].self, forKey: .materialCost) ?? [:]
        workers = try c.decodeIfPresent(Int.self, forKey: .workers) ?? 0
        production = try c.decodeIfPresent(Resources.self, forKey: .production) ?? Resources()
        consumption = try c.decodeIfPresent(Resources.self, forKey: .consumption) ?? Resources()
        moraleEffect = try c.decodeIfPresent(Double.self, forKey: .moraleEffect) ?? 0
        defense = try c.decodeIfPresent(Double.self, forKey: .defense) ?? 0
        housing = try c.decodeIfPresent(Double.self, forKey: .housing) ?? 0
        // Typed form first; a bare number is the pre-2026-08-13 authoring and
        // reads as physical goods, which is what every building that had one
        // actually held. Nothing ever meant "this shed stores knowledge".
        if let typed = try? c.decodeIfPresent(Resources.self, forKey: .storage) {
            storage = typed ?? Resources()
        } else if let flat = try c.decodeIfPresent(Double.self, forKey: .storage) {
            storage = Resources([.food: flat, .materials: flat])
        } else {
            storage = Resources()
        }
        upkeep = try c.decodeIfPresent(Resources.self, forKey: .upkeep)
        pollution = try c.decodeIfPresent(Double.self, forKey: .pollution) ?? 0
        recovery = try c.decodeIfPresent([String: Double].self, forKey: .recovery) ?? [:]
        footprint = try c.decodeIfPresent(TileSize.self, forKey: .footprint) ?? TileSize()
        work = try c.decodeIfPresent(WorkKind.self, forKey: .work)
        look = try c.decodeIfPresent(String.self, forKey: .look)
        floors = max(1, try c.decodeIfPresent(Int.self, forKey: .floors) ?? 1)
        adjacency = try c.decodeIfPresent([AdjacencyRule].self, forKey: .adjacency) ?? []
        description = try c.decodeIfPresent(LocalizedText.self, forKey: .description) ?? LocalizedText("")
    }
}
