import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Persistence")
struct PersistenceTests {
    @Test("World survives a save / load round-trip")
    func roundTrip() throws {
        let registry = Fixtures.registry()
        let world = Fixtures.world()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ef-test-\(UUID().uuidString).json")
        let store = WorldStore(url: url)
        defer { try? store.deleteSave() }

        try store.save(world)
        let loaded = try store.load()
        #expect(loaded == world)
        _ = registry
    }

    @Test("Loading with no save returns nil")
    func loadMissing() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ef-missing-\(UUID().uuidString).json")
        #expect(try WorldStore(url: url).load() == nil)
    }

    @Test("Resources encode as a compact object keyed by resource name")
    func resourcesObjectEncoding() throws {
        let data = try JSONEncoder().encode(Resources([.food: 5, .energy: 0, .materials: 2]))
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"food\":5"))
        #expect(json.contains("\"materials\":2"))
        #expect(!json.contains("energy"))   // zero entries omitted
    }
}

@Suite("Bundled game data")
struct BundledDataTests {
    @Test("All shipped JSON loads and decodes")
    func registryLoads() throws {
        let registry = try GameDataRegistry.bundled()
        #expect(!registry.buildings.isEmpty)
        #expect(!registry.techs.isEmpty)
        #expect(!registry.events.isEmpty)
        #expect(!registry.biomes.isEmpty)
        #expect(registry.eraDefinition(.ancient) != nil)
        #expect(registry.config.plannerInterval == 10)
    }

    @Test("New game produces a valid starting world")
    func newGameValid() throws {
        let registry = try GameDataRegistry.bundled()
        let world = GameWorldFactory.newGame(registry: registry)
        #expect(world.settlements.count == 1)
        #expect(world.regions.count == 1)
        #expect(world.settlements[0].population > 0)
        #expect(world.worldFlags["biome:plains_present"] == true)
    }

    @Test("Long simulation stays within invariants and never crashes")
    func longRunInvariants() throws {
        let registry = try GameDataRegistry.bundled()
        var world = GameWorldFactory.newGame(registry: registry, seed: 99)
        world = TechEngine.setResearch(world, techID: "basic_tools", registry: registry)

        let result = TickEngine.advance(world, ticks: 3000, registry: registry)
        let final = result.state

        #expect(final.tick == 3000)
        for settlement in final.settlements {
            #expect(settlement.population >= 0)
            #expect(settlement.stats.morale >= 0 && settlement.stats.morale <= 100)
            #expect(settlement.stats.stability >= 0 && settlement.stats.stability <= 100)
            for resource in ResourceType.allCases {
                #expect(settlement.storage[resource] >= 0)
                #expect(settlement.storage[resource] <= settlement.storageCapacity)
            }
        }
        #expect(final.globalStats.prosperity >= 0 && final.globalStats.prosperity <= 100)
        #expect(final.globalStats.threatLevel >= 0 && final.globalStats.threatLevel <= 100)
    }

    @Test("Identical seeds yield identical 1000-tick histories")
    func reproducibleRuns() throws {
        let registry = try GameDataRegistry.bundled()
        let world = GameWorldFactory.newGame(registry: registry, seed: 7)
        let a = TickEngine.advance(world, ticks: 1000, registry: registry)
        let b = TickEngine.advance(world, ticks: 1000, registry: registry)
        #expect(a.state == b.state)
        #expect(a.fired.map(\.templateID) == b.fired.map(\.templateID))
    }
}
