import Testing
@testable import EndlessFrontierCore

@Suite("Endless map")
struct EndlessMapTests {
    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    @Test("Per-hex generation is a pure function of seed and coordinate")
    func perHexDeterministic() throws {
        let reg = try registry()
        let coord = HexCoord(4, -2)
        let a = MapGenerator.region(at: coord, mapSeed: 123, registry: reg)
        let b = MapGenerator.region(at: coord, mapSeed: 123, registry: reg)
        #expect(a == b)
        // A different seed generally yields different content at the same hex.
        let c = MapGenerator.region(at: coord, mapSeed: 999, registry: reg)
        #expect(a.biomeID != c.biomeID || a.kind != c.kind || a.hazardLevel != c.hazardLevel)
    }

    @Test("Revealing the frontier generates new unknown neighbours (the map grows)")
    func frontierGrows() throws {
        let reg = try registry()
        var regions = [MapGenerator.region(at: .origin, mapSeed: 7, registry: reg)]
        MapGenerator.expandFrontier(around: .origin, regions: &regions, mapSeed: 7, registry: reg)
        #expect(regions.count == 7)   // homeland + 6 neighbours
        #expect(regions.filter { $0.explorationState == .unknown }.count == 6)

        // Pushing the frontier outward keeps adding new land.
        let edge = HexCoord(1, 0)
        MapGenerator.expandFrontier(around: edge, regions: &regions, mapSeed: 7, registry: reg)
        #expect(regions.count > 7)
    }

    @Test("Expanding the frontier is idempotent (no duplicate hexes)")
    func expansionIdempotent() throws {
        let reg = try registry()
        var regions = [MapGenerator.region(at: .origin, mapSeed: 7, registry: reg)]
        MapGenerator.expandFrontier(around: .origin, regions: &regions, mapSeed: 7, registry: reg)
        let after = regions.count
        MapGenerator.expandFrontier(around: .origin, regions: &regions, mapSeed: 7, registry: reg)
        #expect(regions.count == after)
        #expect(Set(regions.map(\.coord)).count == regions.count)   // all coords unique
    }

    @Test("Hazard rises with distance from the homeland")
    func hazardScalesWithDistance() throws {
        let reg = try registry()
        // A far hex carries the accumulated ring hazard regardless of biome.
        let far = MapGenerator.region(at: HexCoord(12, 0), mapSeed: 1, registry: reg)
        #expect(far.hazardLevel >= 6)
    }

    @Test("Exploring through TickEngine eventually enlarges the world")
    func tickEngineGrowsWorld() throws {
        let reg = try registry()
        var world = GameWorldFactory.newGame(registry: reg, seed: 3)
        world.settlements[0].storage[.food] = 99_999
        world.settlements[0].storage[.materials] = 99_999

        // Explore outward repeatedly; the region count should strictly grow
        // once expeditions reach the current edge.
        let startCount = world.regions.count
        for _ in 0..<6 {
            guard let target = ExplorationEngine.exploreableRegions(world).max(by: {
                $0.coord.distance(to: .origin) < $1.coord.distance(to: .origin)
            }) else { break }
            world = ExplorationEngine.startExpedition(world, targetRegionID: target.id, registry: reg)
            let duration = (world.activeExpedition?.ticksRemaining ?? 0) + 1
            world = TickEngine.advance(world, ticks: duration, registry: reg).state
        }
        #expect(world.regions.count > startCount)
        #expect(!ExplorationEngine.exploreableRegions(world).isEmpty)   // frontier never closes
    }
}
