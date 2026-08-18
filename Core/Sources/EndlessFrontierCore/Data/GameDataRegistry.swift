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
    /// How a body moves while it is doing something. Presentation reads this;
    /// the simulation never does, which is why a missing entry costs nothing
    /// but a plain stand.
    public let motions: [String: MotionDefinition]
    /// What each kind of ground looks like. Presentation reads this; the
    /// simulation decides *where* the covers lie and never what colour.
    public let ground: [String: GroundDefinition]
    /// The colour of everything standing on the ground — crops, trees, rock,
    /// landforms. Presentation only, like the two banks beside it.
    public let scenery: [String: SceneryDefinition]
    public let config: WorldConfig
    public let mapGen: MapGenConfig

    /// Every meal a cook may consider, in a stable order.
    ///
    /// Falls back to a single hardcoded pot of gruel when the table is empty.
    /// A world with no meal data eats badly instead of dying.
    ///
    /// This belt stays even though the braces were fixed: `bundled(from:)` no
    /// longer swallows a malformed `meals.json` (a decode error is thrown now,
    /// not turned into `[]`), so the empty table this guards against should be
    /// unreachable. It is kept because of what it guards *against* — a colony
    /// that cannot cook starves with a full granary, and rule 9b is the note
    /// saying that outcome must never be one bad line away.
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
        motions: [MotionDefinition] = [],
        ground: [GroundDefinition] = [],
        scenery: [SceneryDefinition] = [],
        config: WorldConfig = .default,
        mapGen: MapGenConfig = .default
    ) {
        let mealTable = Dictionary(uniqueKeysWithValues: meals.map { ($0.id, $0) })
        let cookable = mealTable.isEmpty
            ? [MealDefinition.fallback]
            : mealTable.values.sorted { $0.id < $1.id }
        self.meals = mealTable
        self.motions = Dictionary(uniqueKeysWithValues: motions.map { ($0.id, $0) })
        self.ground = Dictionary(uniqueKeysWithValues: ground.map { ($0.id, $0) })
        self.scenery = Dictionary(uniqueKeysWithValues: scenery.map { ($0.id, $0) })
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
    /// Never nil: a body with no clip stands there, rather than failing to draw.
    public func motion(_ id: String) -> MotionDefinition {
        motions[id] ?? .standing
    }

    /// Never nil: ground the bank has nothing to say about is plain earth,
    /// not a hole.
    public func ground(_ id: String) -> GroundDefinition {
        ground[id] ?? .plain
    }

    /// Never nil: an unlisted thing is drawn a plain green rather than not at all.
    public func scenery(_ id: String) -> SceneryDefinition {
        scenery[id] ?? .plain
    }

    /// The clip that best fits what somebody is doing and what they do for a
    /// living — a farmer at work sows, a hunter at work stalks, and both fall
    /// back to the plain work clip if the bank has nothing more specific.
    ///
    /// Most specific wins, and ties are broken by id so the same colonist doing
    /// the same thing is drawn the same way twice. Dictionary order is not
    /// stable across runs, and a figure that changes gait every frame because
    /// two clips both matched is worse than no clip at all.
    public func motion(activity: String, work: String?,
                       phase: String? = nil) -> MotionDefinition {
        if let work {
            let fitted = motions.values
                .filter { $0.servesWork.contains(work) && $0.servesActivities.contains(activity) }
                .sorted { $0.id < $1.id }
            // Most specific first: a clip written for *this* moment of the work
            // beats one written for the work in general. Without this the four
            // hunting clips were separated by nothing but the alphabet, so a
            // hunter creeping and a hunter over a carcass were drawn the same.
            if let phase, let matched = fitted.first(where: { $0.servesPhases.contains(phase) }) {
                return matched
            }
            if let best = fitted.first(where: { $0.servesPhases.isEmpty }) ?? fitted.first {
                return best
            }
        }
        let byActivity = motions.values
            .filter { $0.servesWork.isEmpty && $0.servesActivities.contains(activity) }
            .sorted { $0.id < $1.id }
        return byActivity.first ?? motion(activity)
    }
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
        /// Absent is allowed. **Malformed is not.**
        ///
        /// These files used to be loaded with a bare `try?`, which collapsed
        /// two completely different situations into the same empty array: a
        /// file that is not there (fine — the game runs without recipes), and a
        /// file that is there and does not parse (catastrophic, and silent).
        ///
        /// Three generated items named an `equipSlot` the game does not
        /// have. One `DecodingError` later, `items` was `[]` — every recipe
        /// pointed at nothing, every weapon vanished, an armed garrison fought
        /// exactly as well as an unarmed one, and 218 tests failed without one
        /// word about items anywhere in the output. The data was three lines
        /// wrong; the *silence* was the bug.
        func optional<T: Decodable>(_ type: T.Type, _ name: String,
                                    else fallback: T) throws -> T {
            do {
                return try load(type, name)
            } catch GameDataError.missingResource {
                return fallback
            }
            // Anything else — a malformed file — is rethrown and stops the world.
        }
        let mapGen = try optional(MapGenConfig.self, "map-gen", else: .default)
        let items = try optional([ItemDefinition].self, "items", else: [])
        let recipes = try optional([RecipeDefinition].self, "recipes", else: [])
        let quests = try optional([QuestDefinition].self, "quests", else: [])
        let laws = try optional([LawDefinition].self, "laws", else: [])
        let plagues = try optional([PlagueDefinition].self, "plagues", else: [])
        let cults = try optional([CultDefinition].self, "cults", else: [])
        let meals = try optional([MealDefinition].self, "meals", else: [])
        let motions = try optional([MotionDefinition].self, "motions", else: [])
        let ground = try optional([GroundDefinition].self, "ground", else: [])
        let scenery = try optional([SceneryDefinition].self, "scenery", else: [])
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
            motions: motions,
            ground: ground,
            scenery: scenery,
            config: try load(WorldConfig.self, "world-config"),
            mapGen: mapGen
        )
    }
}
