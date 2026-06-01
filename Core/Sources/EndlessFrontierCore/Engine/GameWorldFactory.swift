import Foundation

/// Builds the initial world for a new game: one starting settlement in one
/// revealed region, with starter buildings and resources.
public enum GameWorldFactory {
    public static func newGame(
        registry: GameDataRegistry,
        seed: UInt64 = 0x5EED_F00D,
        now: Date = Date()
    ) -> WorldState {
        let startingBiome = registry.biomes["plains"]?.id ?? registry.biomes.keys.sorted().first ?? "plains"

        let region = Region(
            name: "Homeland",
            biomeID: startingBiome,
            hazardLevel: registry.biome(startingBiome)?.baseHazard ?? 0,
            explorationState: .fullyExplored
        )

        // Starter buildings, only those that actually exist in the data.
        let starterBuildingIDs = ["farm_basic", "lumberyard", "hut"]
        let buildings = starterBuildingIDs
            .filter { registry.building($0) != nil }
            .map { BuildingInstance(definitionID: $0, count: 1) }

        let settlement = Settlement(
            name: "First Light",
            regionID: region.id,
            foundedTick: 0,
            population: 50,
            buildings: buildings,
            storage: [.food: 200, .materials: 120, .energy: 0, .knowledge: 0, .influence: 20],
            storageCapacity: registry.config.defaultStorageCapacity,
            stats: SettlementStats(stability: 60, morale: 60)
        )

        var startingRegion = region
        startingRegion.settlementIDs = [settlement.id]

        var flags: [String: Bool] = [:]
        if let flag = registry.biome(startingBiome)?.worldFlag {
            flags[flag] = true
        }

        // Unlock starter buildings so the player can rebuild them.
        let unlocked = Set(starterBuildingIDs.filter { registry.building($0) != nil })

        return WorldState(
            tick: 0,
            lastRealTimestamp: now,
            rngSeed: seed,
            era: .earlySettlement,
            unlockedBuildings: unlocked,
            worldFlags: flags,
            settlements: [settlement],
            regions: [startingRegion]
        )
    }
}
