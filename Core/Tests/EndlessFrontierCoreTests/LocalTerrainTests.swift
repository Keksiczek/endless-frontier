import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Local terrain & scenery")
struct LocalTerrainTests {
    static let registry = try! GameDataRegistry.bundled()

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
        let forest = LocalMapGenerator.generate(mapSeed: 5, regionID: region, biome: biome("forest"), registry: Self.registry)
        let desert = LocalMapGenerator.generate(mapSeed: 5, regionID: region, biome: biome("desert"), registry: Self.registry)

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
        let map = LocalMapGenerator.generate(mapSeed: 11, regionID: region, biome: biome("plains"), registry: Self.registry)
        #expect(!map.scenery.isEmpty)
        #expect(map.scenery.count <= 80)
        for prop in map.scenery {
            #expect((0...1).contains(prop.position.x))
            #expect((0...1).contains(prop.position.y))
            #expect(prop.scale >= 0.7 && prop.scale <= 1.3)
        }
        let again = LocalMapGenerator.generate(mapSeed: 11, regionID: region, biome: biome("plains"), registry: Self.registry)
        #expect(again == map)
    }

    @Test("The map carries its biome and a terrain seed, and survives a save")
    func mapCarriesTerrain() throws {
        let map = LocalMapGenerator.generate(mapSeed: 8, regionID: region, biome: biome("coast"), registry: Self.registry)
        #expect(map.biomeID == "coast")
        #expect(map.terrainSeed != 0)
        let restored = try JSONDecoder().decode(
            LocalMap.self, from: JSONEncoder().encode(map))
        #expect(restored == map)
        #expect(restored.cover(column: 4, row: 4) == map.cover(column: 4, row: 4))
    }
}

/// **A new biome must be answered by every system, not fall into `default`.**
///
/// Adding a country is a row in `biomes.json` plus fourteen `switch`es across
/// the Core, and the failure mode is silent: a `default:` arm answers, the map
/// generates, nothing crashes, and the seventh biome is the plains with a
/// different name on the world map. That is this project's commonest bug shape
/// wearing new clothes — content that loads and that nothing reaches.
///
/// So the test does not check *what* each answer is. It checks that the answer
/// is the biome's own: distinct from the fallback the unknown-biome path gives.
/// A country allowed to agree with the default on one or two axes is fine; one
/// that agrees on all of them has not really been added.
@Suite("Every country the game ships is its own country")
struct BiomeCoverageTests {
    static let registry = try! GameDataRegistry.bundled()

    /// A biome id nothing knows, so `default:` is what answers for it.
    private static let unknown = "no_such_biome"

    private func fingerprint(_ id: String) -> [String] {
        let shape = LocalTerrain.shape(of: id)
        let stone = StoneEngine.seamMix(for: id)
        return [
            "\(shape.lift)/\(shape.damp)/\(shape.cold)",
            LocalTerrain.weights(for: id).map { "\($0.0)\($0.1)" }.joined(),
            "\(LocalTerrain.sceneryMix(for: id).count)",
            "\(FloraFactory.wildTreeCount(for: id))",
            FloraFactory.species(for: id, registry: Self.registry).map { $0.id }.joined(),
            "\(StoneEngine.massifWeight(for: id))",
            "\(stone.iron)/\(stone.clay)",
            "\(RiverShape.chance(biomeID: id))",
            AnimalFactory.mix(for: id).map { "\($0.0)\($0.1)\($0.2)" }.joined(),
        ]
    }

    @Test("No shipped biome is answered by the fallback on every axis")
    func everyBiomeIsSomewhereInParticular() throws {
        let registry = try GameDataRegistry.bundled()
        let fallback = fingerprint(Self.unknown)
        for biome in registry.biomes.values {
            // `plains` **is** the fallback, deliberately: every switch in the
            // Core reads `default: // plains & homeland`. Naming the one
            // exception is honest; lowering the bar for all seven so it passes
            // would be the test quietly agreeing not to look.
            guard biome.id != "plains" else { continue }
            let mine = fingerprint(biome.id)
            let own = zip(mine, fallback).filter { $0 != $1 }.count
            #expect(own >= 6,
                    "'\(biome.id)' answers like an unknown country on \(mine.count - own) of \(mine.count) axes — it is the default with a new name")
        }
    }

    /// The homeland is deliberately the default's country, so it is the one
    /// exception and worth naming rather than quietly excluding.
    @Test("Two different countries are never the same country")
    func biomesDifferFromEachOther() throws {
        let registry = try GameDataRegistry.bundled()
        var seen: [String: String] = [:]
        for biome in registry.biomes.values {
            let key = fingerprint(biome.id).joined(separator: "|")
            if let twin = seen[key] {
                Issue.record("'\(biome.id)' and '\(twin)' generate the same country")
            }
            seen[key] = biome.id
        }
    }

    @Test("Every biome states a world flag an event can gate on")
    func everyBiomeCanBeAskedAbout() throws {
        let registry = try GameDataRegistry.bundled()
        for biome in registry.biomes.values {
            #expect(biome.worldFlag == "biome:\(biome.id)_present",
                    "'\(biome.id)' must be nameable by an event's condition")
        }
    }
}
