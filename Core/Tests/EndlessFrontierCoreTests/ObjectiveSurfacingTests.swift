import Foundation
import Testing
@testable import EndlessFrontierCore

/// The new economy systems (caravans, specialisations) surface as objectives so
/// the player discovers them.
@Suite("Objectives for new systems")
struct ObjectiveSurfacingTests {
    private func reg() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    @Test("A cut-off outpost prompts a supply objective")
    func strandedOutpostPromptsSupply() throws {
        let r = try reg()
        let capital = Settlement(name: "Capital", kind: .capital, population: 40)
        let outpost = Settlement(name: "Far Post", kind: .outpost, population: 8)  // no trade route → isolated
        let world = WorldState(settlements: [capital, outpost])
        let ids = ObjectivesEngine.current(world, registry: r, limit: 50).map(\.id)
        #expect(ids.contains("supply_\(outpost.id)"))
    }

    @Test("A connected outpost does not prompt a supply objective")
    func connectedOutpostNoSupply() throws {
        let r = try reg()
        let capital = Settlement(name: "Capital", kind: .capital, population: 40)
        let outpost = Settlement(name: "Near Post", kind: .outpost, population: 8)
        var world = WorldState(settlements: [capital, outpost])
        world.tradeRoutes = [TradeRoute(fromID: capital.id, toID: outpost.id, resource: .food, amountPerTick: 5)]
        let ids = ObjectivesEngine.current(world, registry: r, limit: 50).map(\.id)
        #expect(!ids.contains("supply_\(outpost.id)"))
    }

    @Test("An established balanced settlement prompts a specialise objective")
    func balancedSettlementPromptsSpecialise() throws {
        let r = try reg()
        let capital = Settlement(name: "Capital", kind: .capital, population: 40, specialization: .balanced)
        let world = WorldState(settlements: [capital])
        let ids = ObjectivesEngine.current(world, registry: r, limit: 50).map(\.id)
        #expect(ids.contains("specialise_\(capital.id)"))
    }

    @Test("A specialised settlement does not prompt a specialise objective")
    func specialisedSettlementNoPrompt() throws {
        let r = try reg()
        let capital = Settlement(name: "Capital", kind: .capital, population: 40, specialization: .industrial)
        let world = WorldState(settlements: [capital])
        let ids = ObjectivesEngine.current(world, registry: r, limit: 50).map(\.id)
        #expect(!ids.contains("specialise_\(capital.id)"))
    }
}
