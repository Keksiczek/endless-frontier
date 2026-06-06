import Foundation
import Testing
@testable import EndlessFrontierCore

/// Caravans are escorted batch shipments: they pull cargo and guards out of the
/// origin, travel over several ticks, can be ambushed, and deliver survivors +
/// cargo to the destination. Everything is deterministic.
@Suite("Caravans")
struct CaravanTests {
    private func reg() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private func escort(_ name: String, health: Double = 100) -> Pawn {
        Pawn(name: name, health: health)
    }

    /// Two settlements with no placed region → fallback travel time (4 ticks).
    private func twoTowns(originFood: Double = 100, guards: [Pawn]) -> WorldState {
        let origin = Settlement(name: "A", kind: .capital, population: Double(guards.count) + 5,
                                pawns: guards, storage: [.food: originFood], storageCapacity: 99999)
        let dest = Settlement(name: "B", kind: .city, population: 5,
                              storage: Resources(), storageCapacity: 99999)
        return WorldState(settlements: [origin, dest])
    }

    @Test("Dispatch pulls cargo and guards out of the origin")
    func dispatchRemovesFromOrigin() throws {
        let g = escort("Ada")
        let w = twoTowns(guards: [g])
        let after = CaravanEngine.dispatch(w, originID: w.settlements[0].id, destinationID: w.settlements[1].id,
                                           resource: .food, amount: 40, guardIDs: [g.id])
        #expect(after.caravans.count == 1)
        #expect(after.settlements[0].storage[.food] == 60)   // 100 - 40
        #expect(after.settlements[0].pawns.isEmpty)          // guard left town
        #expect(after.caravans[0].cargo == 40)
        #expect(after.caravans[0].guards.count == 1)
    }

    @Test("A peaceful caravan delivers cargo and its guards to the destination")
    func deliversOnArrival() throws {
        let r = try reg()
        let g = escort("Ada")
        var w = twoTowns(guards: [g])
        w = CaravanEngine.dispatch(w, originID: w.settlements[0].id, destinationID: w.settlements[1].id,
                                   resource: .food, amount: 40, guardIDs: [g.id])
        w.globalStats.threatLevel = 0                        // no ambushes possible
        for _ in 0..<4 { w = CaravanEngine.advanceOneTick(w, registry: r) }  // fallback travel = 4 ticks
        #expect(w.caravans.isEmpty)
        #expect(w.settlements[1].storage[.food] == 40)       // cargo arrived
        #expect(w.settlements[1].pawns.contains { $0.id == g.id })   // guard migrated in
    }

    @Test("canDispatch rejects impossible shipments")
    func validation() throws {
        let g = escort("Ada")
        let w = twoTowns(guards: [g])
        let o = w.settlements[0].id, d = w.settlements[1].id
        #expect(!CaravanEngine.canDispatch(w, originID: o, destinationID: d, resource: .food, amount: 999, guardIDs: [g.id]))
        #expect(!CaravanEngine.canDispatch(w, originID: o, destinationID: d, resource: .food, amount: 10, guardIDs: []))
        #expect(!CaravanEngine.canDispatch(w, originID: o, destinationID: o, resource: .food, amount: 10, guardIDs: [g.id]))
        #expect(CaravanEngine.canDispatch(w, originID: o, destinationID: d, resource: .food, amount: 10, guardIDs: [g.id]))
    }

    @Test("An overwhelmed caravan loses cargo and wounds its escort")
    func ambushOverwhelms() {
        var caravan = Caravan(originID: UUID(), destinationID: UUID(), resource: .food,
                              cargo: 100, guards: [escort("Lone")], ticksRemaining: 3, totalTicks: 3)
        CaravanEngine.applyAmbush(&caravan, threat: 100)
        #expect(caravan.status == .raided)
        #expect(caravan.cargo < 100)
        #expect(caravan.guards[0].health < 100)
    }

    @Test("A strong escort beats an ambush off without loss")
    func ambushRepelled() {
        let guards = (0..<5).map { escort("G\($0)") }   // 5 × 2 defense = 10 > strength 8 at threat 0
        var caravan = Caravan(originID: UUID(), destinationID: UUID(), resource: .food,
                              cargo: 100, guards: guards, ticksRemaining: 3, totalTicks: 3)
        CaravanEngine.applyAmbush(&caravan, threat: 0)
        #expect(caravan.status == .skirmished)
        #expect(caravan.cargo == 100)
        #expect(caravan.guards.allSatisfy { $0.health == 100 })
    }

    @Test("A caravan with no surviving guards is lost, not delivered")
    func wipedOutIsLost() throws {
        let r = try reg()
        var w = twoTowns(guards: [])
        let lost = Caravan(originID: w.settlements[0].id, destinationID: w.settlements[1].id,
                           resource: .food, cargo: 50, guards: [], ticksRemaining: 1, totalTicks: 4)
        w.caravans = [lost]
        w = CaravanEngine.advanceOneTick(w, registry: r)
        #expect(w.caravans.isEmpty)
        #expect(w.settlements[1].storage[.food] == 0)   // captured — nothing delivered
    }

    @Test("Caravans are deterministic and survive a save round-trip")
    func deterministicAndCodable() throws {
        let g = escort("Ada")
        let w = twoTowns(guards: [g])
        let o = w.settlements[0].id, d = w.settlements[1].id
        let a = CaravanEngine.dispatch(w, originID: o, destinationID: d, resource: .food, amount: 30, guardIDs: [g.id])
        let b = CaravanEngine.dispatch(w, originID: o, destinationID: d, resource: .food, amount: 30, guardIDs: [g.id])
        #expect(a.caravans == b.caravans)
        let data = try JSONEncoder().encode(a)
        let restored = try JSONDecoder().decode(WorldState.self, from: data)
        #expect(restored.caravans == a.caravans)
    }
}
