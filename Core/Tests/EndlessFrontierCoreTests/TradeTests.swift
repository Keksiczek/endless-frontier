import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Trade routes")
struct TradeTests {
    @Test("A trade route can be added and removed")
    func addRemove() {
        let a = Settlement(name: "A", kind: .capital, population: 10)
        let b = Settlement(name: "B", kind: .outpost, population: 5)
        var world = WorldState(settlements: [a, b])

        world = GameEngine.addTradeRoute(world, from: a.id, to: b.id, resource: .food, amountPerTick: 5)
        #expect(world.tradeRoutes.count == 1)
        let routeID = world.tradeRoutes[0].id

        world = GameEngine.removeTradeRoute(world, routeID: routeID)
        #expect(world.tradeRoutes.isEmpty)
    }

    @Test("A route connecting an outpost to the capital spares it the isolation penalty")
    func connectionEndsIsolation() {
        let reg = Fixtures.registry()
        let capital = Settlement(name: "Cap", kind: .capital, population: 20)
        var outpost = Settlement(name: "Out", kind: .outpost, population: 10, storage: [.food: 50])
        outpost.stats.stability = 50
        var world = WorldState(settlements: [capital, outpost])

        let isolated = MultiCityEngine.applyIsolationPenalty(world, config: reg.config)
        #expect(isolated.settlements[1].stats.stability < 50)

        world = GameEngine.addTradeRoute(world, from: capital.id, to: outpost.id, resource: .food, amountPerTick: 5)
        let connected = MultiCityEngine.applyIsolationPenalty(world, config: reg.config)
        #expect(connected.settlements[1].stats.stability == 50)
    }
}
