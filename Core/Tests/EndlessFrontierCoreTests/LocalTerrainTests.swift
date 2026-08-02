import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Local terrain & scenery")
struct LocalTerrainTests {
    private let region = UUID(uuidString: "00000000-0000-0000-0F0F-000000000001")!
    private func biome(_ id: String) -> BiomeDefinition {
        BiomeDefinition(id: id, name: LocalizedText(id.capitalized))
    }

    @Test("Ground cover is deterministic for a seed and cell")
    func coverDeterministic() {
        let a = LocalTerrain.cover(terrainSeed: 42, biomeID: "plains", column: 7, row: 3)
        let b = LocalTerrain.cover(terrainSeed: 42, biomeID: "plains", column: 7, row: 3)
        #expect(a == b)
    }

    @Test("Each biome's dominant cover matches its character", arguments: [
        ("desert", GroundCover.sand), ("tundra", GroundCover.snow),
        ("mountains", GroundCover.rock), ("plains", GroundCover.grass)
    ])
    func dominantCover(biomeID: String, expected: GroundCover) {
        var tally: [GroundCover: Int] = [:]
        for col in 0..<LocalMap.gridColumns {
            for row in 0..<LocalMap.gridRows {
                let cover = LocalTerrain.cover(terrainSeed: 9, biomeID: biomeID, column: col, row: row)
                tally[cover, default: 0] += 1
            }
        }
        let dominant = tally.max { $0.value < $1.value }?.key
        #expect(dominant == expected)
    }

    @Test("Cover forms patches, not static — neighbours often agree")
    func coverFormsPatches() {
        var agreements = 0, total = 0
        for col in 0..<(LocalMap.gridColumns - 1) {
            for row in 0..<LocalMap.gridRows {
                let a = LocalTerrain.cover(terrainSeed: 3, biomeID: "plains", column: col, row: row)
                let b = LocalTerrain.cover(terrainSeed: 3, biomeID: "plains", column: col + 1, row: row)
                if a == b { agreements += 1 }
                total += 1
            }
        }
        // Pure noise on this table would agree ~35% of the time; patches push it well above.
        #expect(Double(agreements) / Double(total) > 0.55)
    }

    @Test("Biomes grow different landscapes")
    func biomesDiffer() {
        let forest = LocalMapGenerator.generate(mapSeed: 5, regionID: region, biome: biome("forest"))
        let desert = LocalMapGenerator.generate(mapSeed: 5, regionID: region, biome: biome("desert"))

        // Forest is thick with trees; desert is not.
        let forestPines = forest.scenery.filter { $0.kind == .pine || $0.kind == .tree }.count
        let desertPines = desert.scenery.filter { $0.kind == .pine || $0.kind == .tree }.count
        #expect(forestPines > desertPines)
        #expect(desert.scenery.contains { $0.kind == .cactus })

        // And they offer different deposits.
        #expect(forest.nodes.filter { $0.kind == .forest }.count
                > desert.nodes.filter { $0.kind == .forest }.count)
        #expect(desert.nodes.filter { $0.kind == .stone }.count
                > forest.nodes.filter { $0.kind == .stone }.count)

        // A desert herd is thinner than a forest one.
        #expect(desert.wildlife.deerCapacity < forest.wildlife.deerCapacity)
    }

    @Test("Scenery is seeded, bounded and on the map")
    func sceneryWellFormed() {
        let map = LocalMapGenerator.generate(mapSeed: 11, regionID: region, biome: biome("plains"))
        #expect(!map.scenery.isEmpty)
        #expect(map.scenery.count <= 80)
        for prop in map.scenery {
            #expect((0...1).contains(prop.position.x))
            #expect((0...1).contains(prop.position.y))
            #expect(prop.scale >= 0.7 && prop.scale <= 1.3)
        }
        let again = LocalMapGenerator.generate(mapSeed: 11, regionID: region, biome: biome("plains"))
        #expect(again == map)
    }

    @Test("The map carries its biome and a terrain seed, and survives a save")
    func mapCarriesTerrain() throws {
        let map = LocalMapGenerator.generate(mapSeed: 8, regionID: region, biome: biome("coast"))
        #expect(map.biomeID == "coast")
        #expect(map.terrainSeed != 0)
        let restored = try JSONDecoder().decode(
            LocalMap.self, from: JSONEncoder().encode(map))
        #expect(restored == map)
        #expect(restored.cover(column: 4, row: 4) == map.cover(column: 4, row: 4))
    }
}
