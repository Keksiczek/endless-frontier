import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Local map generation")
struct LocalMapTests {
    /// The book the generator plants out of. A valley cannot be stood up
    /// without it — see `LocalMapGenerator.generate`.
    static let registry = try! GameDataRegistry.bundled()

    private let region = UUID(uuidString: "00000000-0000-0000-0A0A-000000000001")!

    @Test("Generation is deterministic for the same seed and region")
    func deterministic() {
        let a = LocalMapGenerator.generate(mapSeed: 99, regionID: region, biome: nil, registry: Self.registry)
        let b = LocalMapGenerator.generate(mapSeed: 99, regionID: region, biome: nil, registry: Self.registry)
        #expect(a == b)
    }

    @Test("Different seeds or regions produce different maps")
    func varies() {
        let base = LocalMapGenerator.generate(mapSeed: 1, regionID: region, biome: nil, registry: Self.registry)
        let otherSeed = LocalMapGenerator.generate(mapSeed: 2, regionID: region, biome: nil, registry: Self.registry)
        let otherRegion = LocalMapGenerator.generate(
            mapSeed: 1, regionID: UUID(uuidString: "00000000-0000-0000-0B0B-000000000002")!, biome: nil, registry: Self.registry)
        #expect(base != otherSeed)
        #expect(base != otherRegion)
    }

    /// **Not every kind on every map, and that is the design.** This used to
    /// require all of them in one valley; coal and oil broke it, correctly.
    /// `depositMix` puts seams in the mountains and the tundra and seeps in the
    /// desert, the tundra and the coast, and neither in a forest — which is
    /// what makes the industrial ages a reason to settle somewhere else. So the
    /// assertion is the one that still has teeth: a valley holds what its own
    /// country says it holds, and **every kind is somewhere** — "not
    /// everywhere" and "nowhere" being one typo apart.
    @Test("A generated map has the deposits its country holds, full and on dry land")
    func depositsWellFormed() {
        let map = LocalMapGenerator.generate(mapSeed: 7, regionID: region, biome: nil, registry: Self.registry)
        let mix = LocalMapGenerator.depositMix(for: "plains")
        let expected: [LocalResourceKind: Int] = [
            .field: mix.fields, .forest: mix.forests, .stone: mix.stone,
            .herbs: mix.herbs, .ironOre: mix.ironOre, .clay: mix.clay,
            .coal: mix.coal, .oilSeep: mix.oilSeep,
        ]
        for (kind, wanted) in expected {
            #expect(map.nodes.contains { $0.kind == kind } == (wanted > 0),
                    "\(kind) on a plains map, where the mix says \(wanted)")
        }
        // …and nothing is stranded: somewhere in the world, every kind is dug.
        for kind in LocalResourceKind.allCases {
            let anywhere = ["plains", "forest", "desert", "tundra", "mountains", "coast"]
                .map(LocalMapGenerator.depositMix(for:))
                .contains { mix in
                    switch kind {
                    case .field: return mix.fields > 0
                    case .forest: return mix.forests > 0
                    case .stone: return mix.stone > 0
                    case .herbs: return mix.herbs > 0
                    case .ironOre: return mix.ironOre > 0
                    case .clay: return mix.clay > 0
                    case .coal: return mix.coal > 0
                    case .oilSeep: return mix.oilSeep > 0
                    }
                }
            #expect(anywhere, "\(kind) is in no country in the world")
        }
        for node in map.nodes {
            #expect(node.amount == node.capacity)   // starts full
            #expect(abs(node.position.y - map.river.y(atX: node.position.x)) > 0.05)   // off the water
            #expect((0...1).contains(node.position.x))
            #expect((0...1).contains(node.position.y))
        }
    }

    /// A map used to get the identical cast of all six kinds — which is why two
    /// valleys felt like the same valley. Now it gets a handful, drawn from what
    /// the country plausibly holds.
    @Test("Landmarks are a handful, all different, and on dry land")
    func pois() {
        let map = LocalMapGenerator.generate(mapSeed: 7, regionID: region, biome: nil, registry: Self.registry)
        #expect(LocalMapGenerator.poiCountRange.contains(map.pois.count))
        #expect(Set(map.pois.map(\.kind)).count == map.pois.count, "no map holds the same place twice")
        #expect(Set(map.pois.map(\.id)).count == map.pois.count, "ids must be unique — they key the UI")
        for poi in map.pois {
            #expect(abs(poi.position.y - map.river.y(atX: poi.position.x)) > 0.05)
        }
    }

    @Test("The settlement centre starts revealed, the far edges do not")
    func fogOfWar() {
        let map = LocalMapGenerator.generate(mapSeed: 7, regionID: region, biome: nil, registry: Self.registry)
        #expect(map.isExplored(LocalPoint(x: 0.5, y: 0.5)))
        #expect(!map.isExplored(LocalPoint(x: 0.02, y: 0.02)))
        #expect(map.exploredFraction > 0 && map.exploredFraction < 1)
    }

    @Test("Revealing around a point uncovers cells and discovers a hidden POI")
    func revealDiscoversPOIs() {
        var map = LocalMapGenerator.generate(mapSeed: 7, regionID: region, biome: nil, registry: Self.registry)
        // POIs near the centre are already revealed at founding; take one that
        // still lies out in the fog.
        guard let index = map.pois.firstIndex(where: { !$0.discovered }) else {
            Issue.record("expected at least one undiscovered POI")
            return
        }
        let position = map.pois[index].position
        #expect(!map.isExplored(position))
        map.reveal(around: position, radius: 0.15)
        #expect(map.isExplored(position))
        #expect(map.pois[index].discovered)
    }

    @Test("The biome decides what deposits the land offers")
    func biomeShapesDeposits() {
        let mountains = BiomeDefinition(id: "mountains", name: "Mountains")
        let plains = BiomeDefinition(id: "plains", name: "Plains")
        let rocky = LocalMapGenerator.generate(mapSeed: 5, regionID: region, biome: mountains, registry: Self.registry)
        let fertile = LocalMapGenerator.generate(mapSeed: 5, regionID: region, biome: plains, registry: Self.registry)

        #expect(rocky.nodes.filter { $0.kind == .stone }.count
                > fertile.nodes.filter { $0.kind == .stone }.count)
        #expect(fertile.nodes.filter { $0.kind == .field }.count
                > rocky.nodes.filter { $0.kind == .field }.count)
    }

    @Test("A new game's capital comes with a generated local map")
    func factoryPopulatesLocalMap() throws {
        let registry = try GameDataRegistry.bundled()
        let world = GameWorldFactory.newGame(registry: registry, seed: 123)
        #expect(world.settlements[0].localMap != nil)
        #expect(!(world.settlements[0].localMap?.nodes.isEmpty ?? true))
    }

    @Test("Local map survives a save round-trip")
    func codableRoundTrip() throws {
        let map = LocalMapGenerator.generate(mapSeed: 7, regionID: region, biome: nil, registry: Self.registry)
        let data = try JSONEncoder().encode(map)
        let restored = try JSONDecoder().decode(LocalMap.self, from: data)
        #expect(restored == map)
    }
}
