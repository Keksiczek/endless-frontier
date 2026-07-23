import Testing
import Foundation
@testable import EndlessFrontierCore

/// Reported from a real game: "the maps are all almost the same, they don't
/// read what's on the world map, and the landscape doesn't actually determine
/// anything."
///
/// All three were true and for different reasons. The homeland was hardcoded to
/// plains, so the one valley a player looks at for an entire game was the same
/// country every run. `resource_affinity` sat in `biomes.json` being decoded and
/// read by nothing. The region's `hazardLevel` — computed from biome, kind and
/// distance from home — never reached the ground the colony stood on. And every
/// map got the identical cast of all six landmarks, so no valley ever had
/// anything the last one didn't.
@Suite("The land is different, and it matters")
struct MapVarietyTests {
    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }
    private let region = UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000001")!

    // MARK: - The world map reaches the ground

    @Test("A new game's homeland is not always the same country")
    func homelandVaries() throws {
        let reg = try registry()
        let biomes = Set((0..<40).map { seed in
            GameWorldFactory.newGame(registry: reg, seed: UInt64(seed) &* 0x9E37).settlements[0]
                .localMap!.biomeID
        })
        #expect(biomes.count > 1,
                "every run started in the same valley — homeland was hardcoded to plains")
    }

    @Test("The homeland a seed picks is stable for that seed")
    func homelandIsDeterministic() throws {
        let reg = try registry()
        for seed in [UInt64(1), 99, 40_000] {
            let a = GameWorldFactory.newGame(registry: reg, seed: seed).settlements[0].localMap!.biomeID
            let b = GameWorldFactory.newGame(registry: reg, seed: seed).settlements[0].localMap!.biomeID
            #expect(a == b)
        }
    }

    @Test("Only biomes the data nominates can be a homeland")
    func homelandRespectsTheData() throws {
        let reg = try registry()
        let allowed = Set(reg.biomes.values.filter { $0.homelandWeight > 0 }.map(\.id))
        #expect(!allowed.isEmpty, "biomes.json must nominate somewhere to start")
        for seed in 0..<40 {
            let id = GameWorldFactory.newGame(registry: reg, seed: UInt64(seed) &* 0x71F3)
                .settlements[0].localMap!.biomeID
            #expect(allowed.contains(id))
        }
    }

    @Test("A biome set that nominates nobody still yields a playable world")
    func homelandFallsBackSafely() {
        let reg = Fixtures.registry(biomes: [
            BiomeDefinition(id: "plains", name: "Plains"),   // homelandWeight defaults to 0
            BiomeDefinition(id: "forest", name: "Forest")
        ])
        let world = GameWorldFactory.newGame(registry: reg, seed: 5)
        #expect(world.settlements[0].localMap != nil)
    }

    @Test("Dangerous country has more to fear from the dark")
    func hazardReachesTheWildlife() throws {
        let reg = try registry()
        let calm = LocalMapGenerator.generate(mapSeed: 3, regionID: region,
                                              biome: reg.biome("plains"), hazard: 0)
        let wild = LocalMapGenerator.generate(mapSeed: 3, regionID: region,
                                              biome: reg.biome("plains"), hazard: 8)
        #expect(wild.wildlife.predatorPressure > calm.wildlife.predatorPressure,
                "a frontier valley was exactly as safe as the homeland")
    }

    // MARK: - The landscape decides what is in the ground

    @Test("A mountain holds more stone than a plain does")
    func affinityShapesDeposits() throws {
        let reg = try registry()
        func stone(_ biomeID: String) -> Double {
            let map = LocalMapGenerator.generate(mapSeed: 21, regionID: region,
                                                 biome: reg.biome(biomeID))
            let nodes = map.nodes.filter { $0.kind == .stone }
            return nodes.isEmpty ? 0 : nodes.reduce(0) { $0 + $1.capacity } / Double(nodes.count)
        }
        #expect(stone("mountains") > stone("plains"),
                "materials 1.5 vs 0.8 must mean something in the ground")
    }

    @Test("A desert field is a hard field")
    func affinityPunishesPoorCountry() throws {
        let reg = try registry()
        func field(_ biomeID: String) -> Double {
            let map = LocalMapGenerator.generate(mapSeed: 21, regionID: region,
                                                 biome: reg.biome(biomeID))
            let nodes = map.nodes.filter { $0.kind == .field }
            return nodes.isEmpty ? 0 : nodes.reduce(0) { $0 + $1.capacity } / Double(nodes.count)
        }
        #expect(field("desert") < field("plains"))
    }

    @Test("Poor country is poor, never barren", arguments: ["desert", "tundra", "mountains"])
    func affinityIsClamped(biomeID: String) throws {
        let reg = try registry()
        let map = LocalMapGenerator.generate(mapSeed: 8, regionID: region, biome: reg.biome(biomeID))
        for node in map.nodes {
            #expect(node.capacity > 0, "a hostile biome must not put a hole in the map")
            #expect(node.amount == node.capacity)
        }
    }

    @Test("A biome that states no affinity is left ordinary")
    func silentAffinityIsNeutral() {
        let plain = BiomeDefinition(id: "plains", name: "Plains")
        for kind in LocalResourceKind.allCases {
            #expect(LocalMapGenerator.affinity(plain, for: kind) == 1)
        }
        #expect(LocalMapGenerator.affinity(nil, for: .field) == 1)
    }

    // MARK: - Landmarks belong to their country

    @Test("The cast of landmarks differs between countries")
    func poiCastVariesByBiome() throws {
        let reg = try registry()
        // Same seed, same region — only the country differs.
        func cast(_ biomeID: String) -> Set<LocalPOIKind> {
            Set(LocalMapGenerator.generate(mapSeed: 4, regionID: region,
                                           biome: reg.biome(biomeID)).pois.map(\.kind))
        }
        let casts = ["mountains", "desert", "coast", "forest"].map(cast)
        #expect(Set(casts).count > 1, "every map used to hold the identical six")
    }

    @Test("Two seeds in the same country still give different valleys")
    func poiCastVariesBySeed() throws {
        let reg = try registry()
        let casts = (0..<12).map { seed in
            Set(LocalMapGenerator.generate(mapSeed: UInt64(seed), regionID: region,
                                           biome: reg.biome("plains")).pois.map(\.kind))
        }
        #expect(Set(casts).count > 1)
    }

    /// Weighted, not forbidden: over many deserts a spring should be rarer than
    /// on the plains, but the point is the odds, not a ban.
    @Test("Water is scarce in the desert and ordinary on the plains")
    func springsAreRareInTheDesert() throws {
        let reg = try registry()
        func springs(_ biomeID: String) -> Int {
            (0..<80).count { seed in
                LocalMapGenerator.generate(mapSeed: UInt64(seed) &* 0x2545,
                                           regionID: region, biome: reg.biome(biomeID))
                    .pois.contains { $0.kind == .spring }
            }
        }
        #expect(springs("desert") < springs("plains"))
    }

    @Test("Mountains are riddled with caves")
    func cavesFavourMountains() throws {
        let reg = try registry()
        func caves(_ biomeID: String) -> Int {
            (0..<80).count { seed in
                LocalMapGenerator.generate(mapSeed: UInt64(seed) &* 0x2545,
                                           regionID: region, biome: reg.biome(biomeID))
                    .pois.contains { $0.kind == .cave }
            }
        }
        #expect(caves("mountains") > caves("coast"))
    }

    /// The hard invariant: same seed and inputs, same world.
    @Test("Generation stays deterministic for a seed")
    func generationIsDeterministic() throws {
        let reg = try registry()
        let a = LocalMapGenerator.generate(mapSeed: 77, regionID: region,
                                           biome: reg.biome("tundra"), hazard: 4)
        let b = LocalMapGenerator.generate(mapSeed: 77, regionID: region,
                                           biome: reg.biome("tundra"), hazard: 4)
        #expect(a == b)
    }
}
