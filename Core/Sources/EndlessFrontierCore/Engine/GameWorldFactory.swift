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
            kind: .capital,
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
            regions: [startingRegion] + unknownRegions(registry: registry, excluding: startingBiome)
        )
    }

    /// A small frontier of unknown regions the player can later explore.
    /// Biomes are drawn from the data, skipping the starting biome.
    private static func unknownRegions(registry: GameDataRegistry, excluding startingBiome: String) -> [Region] {
        let biomeIDs = registry.biomes.keys.sorted().filter { $0 != startingBiome }
        let names = ["The Reach", "Far Hollow", "Greywater", "Stormwatch", "The Verge"]
        return biomeIDs.prefix(names.count).enumerated().map { index, biomeID in
            Region(
                name: names[index],
                biomeID: biomeID,
                hazardLevel: registry.biome(biomeID)?.baseHazard ?? 1,
                explorationState: .unknown
            )
        }
    }
}
