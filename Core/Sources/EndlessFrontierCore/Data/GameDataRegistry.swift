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
    public let config: WorldConfig
    public let mapGen: MapGenConfig

    public init(
        buildings: [BuildingDefinition] = [],
        techs: [TechDefinition] = [],
        eras: [EraDefinition] = [],
        biomes: [BiomeDefinition] = [],
        events: [EventTemplate] = [],
        config: WorldConfig = .default,
        mapGen: MapGenConfig = .default
    ) {
        self.buildings = Dictionary(uniqueKeysWithValues: buildings.map { ($0.id, $0) })
        self.techs = Dictionary(uniqueKeysWithValues: techs.map { ($0.id, $0) })
        self.eras = Dictionary(uniqueKeysWithValues: eras.map { ($0.era, $0) })
        self.biomes = Dictionary(uniqueKeysWithValues: biomes.map { ($0.id, $0) })
        self.events = events
        self.config = config
        self.mapGen = mapGen
    }

    public func building(_ id: String) -> BuildingDefinition? { buildings[id] }
    public func tech(_ id: String) -> TechDefinition? { techs[id] }
    public func biome(_ id: String) -> BiomeDefinition? { biomes[id] }
    public func eraDefinition(_ era: Era) -> EraDefinition? { eras[era] }

    /// Techs whose prerequisites are all met and that aren't yet researched.
    public func availableTechs(researched: Set<String>) -> [TechDefinition] {
        techs.values
            .filter { !researched.contains($0.id) }
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
        // map-gen is optional: fall back to defaults if the file is absent.
        let mapGen = (try? load(MapGenConfig.self, "map-gen")) ?? .default
        return GameDataRegistry(
            buildings: try load([BuildingDefinition].self, "buildings"),
            techs: try load([TechDefinition].self, "techs"),
            eras: try load([EraDefinition].self, "eras"),
            biomes: try load([BiomeDefinition].self, "biomes"),
            events: try load([EventTemplate].self, "events"),
            config: try load(WorldConfig.self, "world-config"),
            mapGen: mapGen
        )
    }
}
