import Foundation

public enum GameDataError: Error, CustomStringConvertible {
    case missingResource(String)
    case decodingFailed(String, underlying: Error)

    public var description: String {
        switch self {
        case let .missingResource(name):
            return "Missing bundled game-data resource: \(name)"
        case let .decodingFailed(name, underlying):
            return "Failed to decode \(name): \(underlying)"
        }
    }
}

/// Read-only, in-memory registry of all data-driven game content. Loaded
/// once at startup from bundled JSON. The simulation never mutates it.
public struct GameDataRegistry: Sendable {
    public let buildings: [String: BuildingDefinition]
    public let techs: [String: TechDefinition]
    public let eras: [Era: EraDefinition]
    public let biomes: [String: BiomeDefinition]
    public let events: [EventTemplate]
    public let items: [String: ItemDefinition]
    public let recipes: [String: RecipeDefinition]
    public let quests: [String: QuestDefinition]
    public let laws: [String: LawDefinition]
    public let cults: [String: CultDefinition]
    public let plagues: [String: PlagueDefinition]
    /// What cooks can make. Never read directly — go through `cookableMeals`,
    /// which is what guarantees a colony can always eat something.
    public let meals: [String: MealDefinition]
    public let config: WorldConfig
    public let mapGen: MapGenConfig

    /// Every meal a cook may consider, in a stable order.
    ///
    /// Falls back to a single hardcoded pot of gruel when the table is empty.
    /// `meals.json` is loaded with `try?` like every other optional data file,
    /// and rule 9b is the standing reminder of what that costs: one malformed
    /// entry silently empties the whole table. For items that means no loot;
    /// for meals it would mean **the colony cannot cook and everybody starves
    /// with a full granary**, which is not a failure worth shipping. A world
    /// with no meal data eats badly instead of dying.
    ///
    /// Sorted once at load rather than on every read. This is the per-tick
    /// path — `CookingEngine.best` re-chooses a meal inside a `while` loop,
    /// `bankCeiling` reads it every tick, and `ErrandEngine` reaches it through
    /// `foodstuffs` — so a sort over the meal table was being paid tens of
    /// thousands of times to hand back the same answer. The order is what
    /// determinism rests on (see the tie-break in `CookingEngine.best`); it is
    /// the same order, decided in one place.
    public let cookableMeals: [MealDefinition]

    /// Every item id any meal is built out of — what counts as a foodstuff.
    ///
    /// Derived from the meal table rather than listed, so adding a crop to
    /// `meals.json` cannot leave the granary refusing to store it (rule 8: the
    /// ingredients are stated in one place). Read through
    /// `CookingEngine.foodstuffs`, which is where the question is asked from.
    public let foodstuffs: Set<String>

    /// The work the dearest pot on the table costs — what a kitchen's banked
    /// effort has to be able to reach, and therefore what it is capped at.
    ///
    /// Same reason as the two above: `CookingEngine.bankCeiling` asks this
    /// every tick of every settlement, and the meal table does not change
    /// between the answer and the next question. Read through `bankCeiling`,
    /// never off here — that function is where the *meaning* of the number is
    /// written down.
    public let dearestMealWork: Double

    public init(
        buildings: [BuildingDefinition] = [],
        techs: [TechDefinition] = [],
        eras: [EraDefinition] = [],
        biomes: [BiomeDefinition] = [],
        events: [EventTemplate] = [],
        items: [ItemDefinition] = [],
        recipes: [RecipeDefinition] = [],
        quests: [QuestDefinition] = [],
        laws: [LawDefinition] = [],
        plagues: [PlagueDefinition] = [],
        cults: [CultDefinition] = [],
        meals: [MealDefinition] = [],
        config: WorldConfig = .default,
        mapGen: MapGenConfig = .default
    ) {
        let mealTable = Dictionary(uniqueKeysWithValues: meals.map { ($0.id, $0) })
        let cookable = mealTable.isEmpty
            ? [MealDefinition.fallback]
            : mealTable.values.sorted { $0.id < $1.id }
        self.meals = mealTable
        self.cookableMeals = cookable
        self.foodstuffs = Set(cookable.flatMap(\.ingredients.keys))
        self.dearestMealWork = cookable.map(\.work).max() ?? 1
        self.buildings = Dictionary(uniqueKeysWithValues: buildings.map { ($0.id, $0) })
        self.techs = Dictionary(uniqueKeysWithValues: techs.map { ($0.id, $0) })
        self.eras = Dictionary(uniqueKeysWithValues: eras.map { ($0.era, $0) })
        self.biomes = Dictionary(uniqueKeysWithValues: biomes.map { ($0.id, $0) })
        self.events = events
        self.items = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        self.recipes = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        self.quests = Dictionary(uniqueKeysWithValues: quests.map { ($0.id, $0) })
        self.laws = Dictionary(uniqueKeysWithValues: laws.map { ($0.id, $0) })
        self.plagues = Dictionary(uniqueKeysWithValues: plagues.map { ($0.id, $0) })
        self.cults = Dictionary(uniqueKeysWithValues: cults.map { ($0.id, $0) })
        self.config = config
        self.mapGen = mapGen
    }

    public func building(_ id: String) -> BuildingDefinition? { buildings[id] }
    public func tech(_ id: String) -> TechDefinition? { techs[id] }
    public func biome(_ id: String) -> BiomeDefinition? { biomes[id] }
    public func item(_ id: String) -> ItemDefinition? { items[id] }
    public func quest(_ id: String) -> QuestDefinition? { quests[id] }
    public func law(_ id: String) -> LawDefinition? { laws[id] }
    public func plague(_ id: String) -> PlagueDefinition? { plagues[id] }
    public func cult(_ id: String) -> CultDefinition? { cults[id] }
    public func eraDefinition(_ era: Era) -> EraDefinition? { eras[era] }

    /// Techs whose prerequisites are all met and that aren't yet researched.
    public func availableTechs(researched: Set<String>) -> [TechDefinition] {
        techs.values
            // A repeatable study is never finished, so it stays on the board
            // however many times it's been run.
            .filter { !researched.contains($0.id) || $0.repeatable }
            .filter { $0.requires.allSatisfy(researched.contains) }
            .sorted { $0.id < $1.id }
    }

    // MARK: - Bundled loading

    /// Loads the registry from the package's own resource bundle.
    public static func bundled() throws -> GameDataRegistry {
        try bundled(from: .module)
    }

    /// Loads the registry from JSON files in the `GameData` resource directory
    /// of the given bundle.
    public static func bundled(from bundle: Bundle) throws -> GameDataRegistry {
        let decoder = JSONDecoder()
        func load<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
            guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "GameData")
                ?? bundle.url(forResource: name, withExtension: "json") else {
                throw GameDataError.missingResource(name)
            }
            do {
                return try decoder.decode(T.self, from: Data(contentsOf: url))
            } catch {
                throw GameDataError.decodingFailed(name, underlying: error)
            }
        }
        // map-gen, items and recipes are optional: fall back if absent.
        let mapGen = (try? load(MapGenConfig.self, "map-gen")) ?? .default
        let items = (try? load([ItemDefinition].self, "items")) ?? []
        let recipes = (try? load([RecipeDefinition].self, "recipes")) ?? []
        let quests = (try? load([QuestDefinition].self, "quests")) ?? []
        let laws = (try? load([LawDefinition].self, "laws")) ?? []
        let plagues = (try? load([PlagueDefinition].self, "plagues")) ?? []
        let cults = (try? load([CultDefinition].self, "cults")) ?? []
        let meals = (try? load([MealDefinition].self, "meals")) ?? []
        return GameDataRegistry(
            buildings: try load([BuildingDefinition].self, "buildings"),
            techs: try load([TechDefinition].self, "techs"),
            eras: try load([EraDefinition].self, "eras"),
            biomes: try load([BiomeDefinition].self, "biomes"),
            events: try load([EventTemplate].self, "events"),
            items: items,
            recipes: recipes,
            quests: quests,
            laws: laws,
            plagues: plagues,
            cults: cults,
            meals: meals,
            config: try load(WorldConfig.self, "world-config"),
            mapGen: mapGen
        )
    }
}
