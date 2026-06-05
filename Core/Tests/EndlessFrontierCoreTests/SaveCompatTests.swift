import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Save compatibility")
struct SaveCompatTests {
    @Test("A save missing newer fields loads with defaults instead of failing")
    func partialSaveLoads() throws {
        // Simulates an older save that predates many fields.
        let json = #"{ "tick": 42, "era": "ancient" }"#
        let world = try JSONDecoder().decode(WorldState.self, from: Data(json.utf8))
        #expect(world.tick == 42)
        #expect(world.era == .ancient)
        #expect(world.settlements.isEmpty)              // defaulted
        #expect(world.regions.isEmpty)                  // defaulted
        #expect(world.scheduledEffects.isEmpty)         // defaulted
        #expect(world.schemaVersion == WorldState.currentSchemaVersion)
    }

    @Test("An empty object decodes to a default world")
    func emptySaveLoads() throws {
        let world = try JSONDecoder().decode(WorldState.self, from: Data("{}".utf8))
        #expect(world == WorldState())
    }

    @Test("Encode carries the schema version")
    func encodesSchemaVersion() throws {
        let data = try JSONEncoder().encode(WorldState(tick: 5))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["schemaVersion"] as? Int == WorldState.currentSchemaVersion)
    }

    @Test("Full round-trip is lossless")
    func roundTrip() throws {
        let reg = try GameDataRegistry.bundled()
        let world = TickEngine.advance(GameWorldFactory.newGame(registry: reg, seed: 8),
                                       ticks: 200, registry: reg).state
        let data = try JSONEncoder().encode(world)
        let restored = try JSONDecoder().decode(WorldState.self, from: data)
        #expect(restored == world)
    }
}
