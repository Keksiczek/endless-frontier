import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Expansion & multi-city")
struct ExpansionTests {
    /// A world with a capital plus one fully-explored empty region.
    private func worldWithFrontier() -> (WorldState, GameDataRegistry, UUID) {
        let reg = Fixtures.registry()
        let region = Region(name: "Frontier", biomeID: "plains", explorationState: .fullyExplored)
        var capital = Settlement(
            name: "Capital", kind: .capital, population: 50,
            storage: [.materials: 200, .influence: 200], storageCapacity: 500
        )
        capital.buildings = [BuildingInstance(definitionID: "farm", count: 1)]
        let world = WorldState(settlements: [capital], regions: [region])
        return (world, reg, region.id)
    }

    @Test("Founding an outpost adds a settlement, pays cost, and links the region")
    func foundOutpost() {
        let (world, reg, regionID) = worldWithFrontier()
        let materialsBefore = world.settlements[0].storage[.materials]

        let after = ExpansionEngine.foundOutpost(world, regionID: regionID, name: "Outpost A", registry: reg)
        #expect(after.settlements.count == 2)
        #expect(after.settlements.last?.kind == .outpost)
        #expect(after.settlements[0].storage[.materials] < materialsBefore)
        #expect(after.regions.first { $0.id == regionID }?.settlementIDs.count == 1)
    }

    @Test("Cannot found an outpost in an unexplored region")
    func cannotFoundUnexplored() {
        var (world, reg, _) = worldWithFrontier()
        let unknown = Region(name: "Unknown", biomeID: "forest", explorationState: .unknown)
        world.regions.append(unknown)
        let after = ExpansionEngine.foundOutpost(world, regionID: unknown.id, name: "X", registry: reg)
        #expect(after.settlements.count == 1)   // unchanged
    }

    @Test("Trade routes move resources between settlements each tick")
    func tradeRouteTransfers() {
        let (base, reg, regionID) = worldWithFrontier()
        var world = ExpansionEngine.foundOutpost(base, regionID: regionID, name: "Outpost", registry: reg)
        let capitalID = world.settlements[0].id
        let outpostID = world.settlements[1].id
        world.settlements[0].storage[.food] = 100
        world = GameEngine.addTradeRoute(world, from: capitalID, to: outpostID, resource: .food, amountPerTick: 10)

        let outpostFoodBefore = world.settlements[1].storage[.food]
        let after = MultiCityEngine.applyTradeRoutes(world)
        #expect(after.settlements[1].storage[.food] == outpostFoodBefore + 10)
        #expect(after.settlements[0].storage[.food] == 90)
    }

    @Test("An unconnected outpost loses stability; a connected one does not")
    func isolationPenalty() {
        let (base, reg, regionID) = worldWithFrontier()
        let world = ExpansionEngine.foundOutpost(base, regionID: regionID, name: "Lonely", registry: reg)
        let stabilityBefore = world.settlements[1].stats.stability

        let isolated = MultiCityEngine.applyIsolationPenalty(world, config: reg.config)
        #expect(isolated.settlements[1].stats.stability < stabilityBefore)

        // Connect it to the capital → no penalty.
        let connected = GameEngine.addTradeRoute(
            world, from: world.settlements[0].id, to: world.settlements[1].id,
            resource: .food, amountPerTick: 5
        )
        let afterConnected = MultiCityEngine.applyIsolationPenalty(connected, config: reg.config)
        #expect(afterConnected.settlements[1].stats.stability == stabilityBefore)
    }

    @Test("Capital is always connected")
    func capitalConnected() {
        let (world, _, _) = worldWithFrontier()
        let connected = MultiCityEngine.connectedSettlementIDs(world)
        #expect(connected.contains(world.settlements[0].id))
    }

    @Test("An outpost meeting thresholds is promoted to a city")
    func outpostPromotion() {
        let (base, reg, regionID) = worldWithFrontier()
        var world = ExpansionEngine.foundOutpost(base, regionID: regionID, name: "Boomtown", registry: reg)
        world.settlements[1].population = reg.config.cityUpgradePopulation + 10
        world.settlements[1].stats.stability = reg.config.cityUpgradeStability + 10

        let after = MultiCityEngine.promoteOutposts(world, config: reg.config)
        #expect(after.settlements[1].kind == .city)
    }
}
