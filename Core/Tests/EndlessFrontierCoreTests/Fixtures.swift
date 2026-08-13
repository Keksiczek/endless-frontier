import Foundation
@testable import EndlessFrontierCore

/// Small hand-built registries and worlds used across tests, so unit tests
/// don't depend on the shipped JSON content (which `BundledDataTests` covers).
enum Fixtures {
    static func registry(
        buildings: [BuildingDefinition] = defaultBuildings,
        techs: [TechDefinition] = defaultTechs,
        eras: [EraDefinition] = defaultEras,
        biomes: [BiomeDefinition] = defaultBiomes,
        events: [EventTemplate] = [],
        config: WorldConfig = .default
    ) -> GameDataRegistry {
        GameDataRegistry(
            buildings: buildings,
            techs: techs,
            eras: eras,
            biomes: biomes,
            events: events,
            config: config
        )
    }

    static let defaultBuildings: [BuildingDefinition] = [
        BuildingDefinition(
            id: "farm", era: .earlySettlement, name: "Farm",
            cost: [.materials: 20], workers: 2,
            production: [.food: 10], moraleEffect: 1
        ),
        BuildingDefinition(
            id: "library", era: .earlySettlement, name: "Library",
            cost: [.materials: 30], workers: 1,
            production: [.knowledge: 5], moraleEffect: 1
        )
    ]

    static let defaultTechs: [TechDefinition] = [
        TechDefinition(id: "basic_tools", name: "Basic Tools", era: .earlySettlement,
                       cost: [.knowledge: 30],
                       effects: [.unlockBuilding(buildingID: "library")]),
        TechDefinition(id: "writing", name: "Writing", era: .earlySettlement,
                       requires: ["basic_tools"], cost: [.knowledge: 50])
    ]

    static let defaultEras: [EraDefinition] = [
        EraDefinition(era: .ancient, milestones: [
            .techResearched("writing"),
            .populationTotal(min: 60)
        ])
    ]

    static let defaultBiomes: [BiomeDefinition] = [
        BiomeDefinition(id: "plains", name: "Plains", baseHazard: 1, worldFlag: "biome:plains_present")
    ]

    /// `count` deterministic adult inhabitants (idle by default, so they
    /// consume food but don't produce anything unless a test says so).
    static func pawns(_ count: Int, work: WorkKind = .idle) -> [Pawn] {
        (0..<count).map { i in
            Pawn(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", i + 1))!,
                name: "Settler \(i + 1)",
                assignedWork: work
            )
        }
    }

    /// A single-settlement world with one farm and a knowledge baseline.
    /// `population` becomes that many real inhabitants (pawns).
    static func world(
        food: Double = 100,
        materials: Double = 100,
        population: Int = 50,
        buildings: [BuildingInstance] = [BuildingInstance(definitionID: "farm", count: 1)],
        tick: Int = 0
    ) -> WorldState {
        let settlement = Settlement(
            name: "Test Town",
            pawns: pawns(population),
            buildings: buildings,
            storage: [.food: food, .materials: materials],
            storageCapacity: .uniform(500)
        )
        return WorldState(tick: tick, settlements: [settlement])
    }
}
