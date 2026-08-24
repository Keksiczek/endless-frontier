import Testing
import Foundation
@testable import EndlessFrontierCore

/// One of your towns keeping another alive. These pin the parts that fail
/// quietly: a realm that never notices, a capital that starves itself being
/// generous, or a road carrying a cart every tick.
@Suite("A cart went out to the outpost")
struct SupplyTests {

    private var registry: GameDataRegistry {
        GameDataRegistry(buildings: [], techs: [], eras: [], biomes: [], events: [],
                         config: .default)
    }

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-5099-%012d", n))!
    }

    private func town(_ n: Int, name: String, souls: Int, food: Double,
                      materials: Double = 300) -> Settlement {
        var s = Settlement(id: id(n), name: name, regionID: UUID())
        s.pawns = (0..<souls).map { i in
            Pawn(id: id(100 * (n + 1) + i), name: "\(name)\(i)")
        }
        s.storage[ResourceType.food] = food
        s.storage[ResourceType.materials] = materials
        return s
    }

    private func realm(_ settlements: [Settlement]) -> WorldState {
        var w = WorldState(settlements: settlements)
        w.mapSeed = 31
        return w
    }

    @Test("A town with full stores sends a cart to one that is short")
    func aShortTownIsSupplied() {
        var w = realm([town(0, name: "Capital", souls: 20, food: 900),
                       town(1, name: "Outpost", souls: 10, food: 5)])
        w.tick = SupplyEngine.interval
        let after = SupplyEngine.advanceOneTick(w, registry: registry)
        #expect(!after.caravans.isEmpty, "nobody noticed the outpost was starving")
        let cart = after.caravans[0]
        #expect(cart.destinationID == w.settlements[1].id)
        #expect(cart.load == .resource(.food))
        #expect(cart.cargo > 0)
        #expect(!cart.guards.isEmpty, "a cart goes out with people, not on its own")
    }

    @Test("The goods and the guards actually leave the sending town")
    func shippingCosts() {
        var w = realm([town(0, name: "Capital", souls: 20, food: 900),
                       town(1, name: "Outpost", souls: 10, food: 5)])
        w.tick = SupplyEngine.interval
        let before = w.settlements[0].storage[ResourceType.food]
        let hands = w.settlements[0].pawns.count
        let after = SupplyEngine.advanceOneTick(w, registry: registry)
        #expect(after.settlements[0].storage[ResourceType.food] < before)
        #expect(after.settlements[0].pawns.count < hands, "the escort walked out of town")
    }

    @Test("Nobody starves their own town to save another")
    func thinStoresStayHome() {
        var w = realm([town(0, name: "Capital", souls: 20, food: 60),
                       town(1, name: "Outpost", souls: 10, food: 5)])
        w.tick = SupplyEngine.interval
        #expect(SupplyEngine.advanceOneTick(w, registry: registry).caravans.isEmpty)
    }

    @Test("A well-stocked realm sends nothing")
    func nothingToDo() {
        var w = realm([town(0, name: "Capital", souls: 20, food: 900),
                       town(1, name: "Outpost", souls: 10, food: 800)])
        w.tick = SupplyEngine.interval
        #expect(SupplyEngine.advanceOneTick(w, registry: registry).caravans.isEmpty)
    }

    @Test("One cart at a time on any given road")
    func theRoadIsNotAConveyor() {
        var w = realm([town(0, name: "Capital", souls: 20, food: 2000),
                       town(1, name: "Outpost", souls: 10, food: 1)])
        for step in 0..<6 {
            w.tick = SupplyEngine.interval * (step + 1)
            w = SupplyEngine.advanceOneTick(w, registry: registry)
        }
        let pair = w.caravans.count {
            $0.originID == w.settlements[0].id && $0.destinationID == w.settlements[1].id
        }
        #expect(pair <= SupplyEngine.maxInFlightPerPair)
    }

    @Test("A lone settlement has nobody to ship to")
    func oneTownShipsNothing() {
        var w = realm([town(0, name: "Alone", souls: 10, food: 1)])
        w.tick = SupplyEngine.interval
        #expect(SupplyEngine.advanceOneTick(w, registry: registry).caravans.isEmpty)
    }

    @Test("Shortness is measured in mouths, not in units")
    func needScalesWithPopulation() {
        let small = town(0, name: "Hamlet", souls: 4, food: 100)
        let big = town(1, name: "City", souls: 60, food: 100)
        #expect(SupplyEngine.comfortable(small, resource: .food)
                < SupplyEngine.comfortable(big, resource: .food))
        #expect(SupplyEngine.spare(small, resource: .food) > 0)
        #expect(SupplyEngine.spare(big, resource: .food) == 0)
    }

    @Test("The realm only looks at itself on its own cadence")
    func supplyIsOnACadence() {
        var w = realm([town(0, name: "Capital", souls: 20, food: 900),
                       town(1, name: "Outpost", souls: 10, food: 5)])
        w.tick = SupplyEngine.interval + 1
        #expect(SupplyEngine.advanceOneTick(w, registry: registry).caravans.isEmpty)
    }

    @Test("The same realm ships the same way twice")
    func supplyIsDeterministic() {
        var w = realm([town(0, name: "Capital", souls: 20, food: 900),
                       town(1, name: "Outpost", souls: 10, food: 5)])
        w.tick = SupplyEngine.interval
        let a = SupplyEngine.advanceOneTick(w, registry: registry)
        let b = SupplyEngine.advanceOneTick(w, registry: registry)
        #expect(a.caravans.map(\.cargo) == b.caravans.map(\.cargo))
        #expect(a.caravans.map(\.destinationID) == b.caravans.map(\.destinationID))
    }
}
