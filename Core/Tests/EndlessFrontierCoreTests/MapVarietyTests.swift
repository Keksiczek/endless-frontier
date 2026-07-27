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

    /// Reported again after the first pass: the maps *still* felt the same.
    /// They did — `depositMix` returned a fixed tuple per biome, so every forest
    /// valley held exactly six woods, two fields and one seam. Only the
    /// positions moved, and a landscape whose composition never changes reads as
    /// one landscape however you scatter it.
    @Test("Two valleys of the same country are not the same valley")
    func sameBiomeStillDiffers() throws {
        let reg = try registry()
        let biome = reg.biome("forest")
        // The whole *composition*, not just where things landed.
        let shapes = Set((0..<25).map { seed -> String in
            let map = LocalMapGenerator.generate(
                mapSeed: UInt64(seed) &* 0x9E37_79B9, regionID: region, biome: biome)
            let counts = LocalResourceKind.allCases.map { kind in
                "\(kind.rawValue):\(map.nodes.count { $0.kind == kind })"
            }
            return counts.joined(separator: ",")
        })
        #expect(shapes.count > 8,
                "25 forest valleys produced only \(shapes.count) distinct deposit mixes")
    }

    @Test("A biome still keeps its character — a forest is never woodless")
    func varietyDoesNotErasePlace() throws {
        let reg = try registry()
        for seed in 0..<20 {
            let map = LocalMapGenerator.generate(
                mapSeed: UInt64(seed) &* 0x2545_F491, regionID: region,
                biome: reg.biome("forest"))
            #expect(map.nodes.contains { $0.kind == .forest },
                    "forest map \(seed) has no wood at all")
        }
    }

    @Test("The same seed still grows the same valley")
    func varietyStaysDeterministic() throws {
        let reg = try registry()
        let a = LocalMapGenerator.generate(mapSeed: 777, regionID: region, biome: reg.biome("forest"))
        let b = LocalMapGenerator.generate(mapSeed: 777, regionID: region, biome: reg.biome("forest"))
        #expect(a.nodes.map(\.kind) == b.nodes.map(\.kind))
        #expect(a.trees == b.trees)
        #expect(a.rocks == b.rocks)
    }

    // MARK: - Geography

    /// A coast was a field with a stream through it, exactly like the plains —
    /// the one country whose whole character is the water had none of it.
    @Test("A coastal map actually has a sea")
    func coastsHaveWater() throws {
        let reg = try registry()
        for seed in 0..<10 {
            let map = LocalMapGenerator.generate(
                mapSeed: UInt64(seed) &* 0x9E37, regionID: region, biome: reg.biome("coast"))
            #expect(map.shore != nil, "coast map \(seed) has no shore")
        }
    }

    @Test("Inland country has no sea")
    func inlandIsDry() throws {
        let reg = try registry()
        for id in ["forest", "mountains", "desert", "tundra", "plains"] {
            let map = LocalMapGenerator.generate(
                mapSeed: 4242, regionID: region, biome: reg.biome(id))
            #expect(map.shore == nil, "\(id) grew a coastline")
        }
    }

    @Test("The sea does not always lie on the same side")
    func coastlinesDiffer() throws {
        let reg = try registry()
        let sides = Set((0..<30).compactMap { seed in
            LocalMapGenerator.generate(mapSeed: UInt64(seed) &* 0x2545_F491,
                                       regionID: region, biome: reg.biome("coast")).shore?.side
        })
        #expect(sides.count > 1, "every coast faces the same way")
    }

    /// Nothing may be generated out in the water — a quarry in the sea is the
    /// kind of thing that only shows up on screen.
    @Test("Nothing is placed out at sea")
    func nothingStandsInTheWater() throws {
        let reg = try registry()
        for seed in 0..<12 {
            let map = LocalMapGenerator.generate(
                mapSeed: UInt64(seed) &* 0x85EB_CA6B, regionID: region, biome: reg.biome("coast"))
            guard let shore = map.shore else { continue }
            for node in map.nodes {
                #expect(!shore.isWater(node.position), "a \(node.kind) is in the sea")
            }
            for poi in map.pois {
                #expect(!shore.isWater(poi.position), "a \(poi.kind) is in the sea")
            }
            for tree in map.trees {
                #expect(!shore.isWater(tree.position), "a tree is in the sea")
            }
        }
    }

    @Test("The waterline wanders instead of ruling a straight edge")
    func theCoastlineIsNotALine() {
        let shore = ShoreShape(side: .north, depth: 0.2, amplitude: 0.05, phase: 0.3)
        let reaches = Set((0..<20).map { (shore.reach(at: Double($0) / 20) * 1000).rounded() })
        #expect(reaches.count > 10)
    }

    @Test("Inland and offshore are opposite signs of the same measure")
    func inlandDistanceAgreesWithWater() {
        for side in ShoreShape.Side.allCases {
            let shore = ShoreShape(side: side, depth: 0.2, amplitude: 0.04, phase: 1)
            for i in 0..<40 {
                let p = LocalPoint(x: Double(i % 8) / 8 + 0.05, y: Double(i / 8) / 5 + 0.05)
                #expect(shore.isWater(p) == (shore.distanceInland(p) < 0))
            }
        }
    }

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
