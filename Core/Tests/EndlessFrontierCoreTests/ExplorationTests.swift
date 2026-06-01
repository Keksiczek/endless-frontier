import Testing
@testable import EndlessFrontierCore

@Suite("Exploration")
struct ExplorationTests {
    /// A registry with several biomes so the factory can seed unknown regions.
    private func bundled() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    @Test("New game seeds one explored region and several unknown ones")
    func newGameMap() throws {
        let reg = try bundled()
        let world = GameWorldFactory.newGame(registry: reg)
        let explored = world.regions.filter { $0.explorationState == .fullyExplored }
        let unknown = world.regions.filter { $0.explorationState == .unknown }
        #expect(explored.count == 1)
        #expect(unknown.count >= 1)
        // Exploration is adjacency-gated: only unknown regions next to a known
        // one are reachable, so the frontier is a subset of all unknowns.
        let frontier = ExplorationEngine.exploreableRegions(world)
        #expect(frontier.count >= 1)
        #expect(frontier.count <= unknown.count)
        let knownCoords = Set(world.regions.filter { $0.explorationState != .unknown }.map(\.coord))
        #expect(frontier.allSatisfy { region in
            region.coord.neighbors().contains { knownCoords.contains($0) }
        })
    }

    @Test("Starting an expedition costs resources and sets it active")
    func startExpedition() throws {
        let reg = try bundled()
        var world = GameWorldFactory.newGame(registry: reg)
        world.settlements[0].storage[.food] = 300
        world.settlements[0].storage[.materials] = 300
        let target = ExplorationEngine.exploreableRegions(world)[0]
        let foodBefore = world.settlements[0].storage[.food]

        let after = ExplorationEngine.startExpedition(world, targetRegionID: target.id, registry: reg)
        #expect(after.activeExpedition?.targetRegionID == target.id)
        #expect(after.settlements[0].storage[.food] < foodBefore)   // cost paid
        #expect(after.regions.first { $0.id == target.id }?.explorationState == .unknown)  // not yet revealed
    }

    @Test("Cannot start a second expedition while one is active")
    func singleExpedition() throws {
        let reg = try bundled()
        var world = GameWorldFactory.newGame(registry: reg)
        world.settlements[0].storage[.food] = 999
        world.settlements[0].storage[.materials] = 999
        let targets = ExplorationEngine.exploreableRegions(world)
        world = ExplorationEngine.startExpedition(world, targetRegionID: targets[0].id, registry: reg)
        let blocked = ExplorationEngine.startExpedition(world, targetRegionID: targets[1].id, registry: reg)
        #expect(blocked.activeExpedition?.targetRegionID == targets[0].id)  // unchanged
    }

    @Test("Expedition cannot start without enough resources")
    func insufficientResources() throws {
        let reg = try bundled()
        var world = GameWorldFactory.newGame(registry: reg)
        world.settlements[0].storage[.food] = 0
        world.settlements[0].storage[.materials] = 0
        let target = ExplorationEngine.exploreableRegions(world)[0]
        let after = ExplorationEngine.startExpedition(world, targetRegionID: target.id, registry: reg)
        #expect(after.activeExpedition == nil)
    }

    @Test("Completing an expedition reveals the region and sets its biome flag")
    func completionRevealsRegion() throws {
        let reg = try bundled()
        var world = GameWorldFactory.newGame(registry: reg)
        world.settlements[0].storage[.food] = 999
        world.settlements[0].storage[.materials] = 999
        let target = ExplorationEngine.exploreableRegions(world)[0]
        let biomeFlag = reg.biome(target.biomeID)?.worldFlag

        world = ExplorationEngine.startExpedition(world, targetRegionID: target.id, registry: reg)
        let duration = world.activeExpedition?.ticksRemaining ?? 0
        #expect(duration > 0)

        var fired: [HistoricalEvent] = []
        for _ in 0..<duration {
            let result = ExplorationEngine.advanceOneTick(world, registry: reg)
            world = result.state
            fired.append(contentsOf: result.fired)
        }

        #expect(world.activeExpedition == nil)
        #expect(world.regions.first { $0.id == target.id }?.explorationState == .fullyExplored)
        if let biomeFlag {
            #expect(world.worldFlags[biomeFlag] == true)
        }
        #expect(fired.contains { $0.templateID == "region_discovered" })
    }

    @Test("TickEngine advances an active expedition to completion")
    func tickEngineAdvancesExpedition() throws {
        let reg = try bundled()
        var world = GameWorldFactory.newGame(registry: reg)
        world.settlements[0].storage[.food] = 999
        world.settlements[0].storage[.materials] = 999
        let target = ExplorationEngine.exploreableRegions(world)[0]
        world = ExplorationEngine.startExpedition(world, targetRegionID: target.id, registry: reg)
        let duration = world.activeExpedition?.ticksRemaining ?? 0

        let after = TickEngine.advance(world, ticks: duration + 1, registry: reg).state
        #expect(after.activeExpedition == nil)
        #expect(after.regions.first { $0.id == target.id }?.explorationState == .fullyExplored)
    }
}
