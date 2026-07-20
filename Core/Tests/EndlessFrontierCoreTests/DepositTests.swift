import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Local deposit depletion & regrowth")
struct DepositTests {
    private let registry = Fixtures.registry()

    private func loggingVillage(loggers: Int, forestAmount: Double) -> Settlement {
        let pawns = (0..<loggers).map { i in
            Pawn(id: UUID(uuidString: String(format: "00000000-0000-0000-0D0D-%012d", i + 1))!,
                 name: "Logger \(i)", skills: [.logging: 8], assignedWork: .logging)
        }
        let forest = ResourceNode(id: 0, kind: .forest, position: LocalPoint(x: 0.3, y: 0.3),
                                  amount: forestAmount, capacity: 200)
        let map = LocalMap(river: RiverShape(baseY: 0.8, amplitude: 0.03, phase: 0),
                           nodes: [forest], pois: [])
        return Settlement(name: "Timbertown", kind: .capital, pawns: pawns,
                          storage: [.food: 500, .materials: 0], storageCapacity: 9999,
                          localMap: map)
    }

    @Test("Harvesting depletes the matching deposit")
    func harvestDepletes() {
        let s = loggingVillage(loggers: 5, forestAmount: 200)
        let after = ResourceLoop.advanceSettlement(s, registry: registry, config: registry.config,
                                                   tick: 20, mapSeed: 1)   // summer
        let forest = after.localMap!.nodes[0]
        #expect(forest.amount < 200)   // wood was taken
    }

    @Test("An exhausted deposit throttles output to the soft floor, not zero")
    func softFloor() {
        let full = loggingVillage(loggers: 4, forestAmount: 200)
        let empty = loggingVillage(loggers: 4, forestAmount: 0)

        let fullOut = ResourceLoop.advanceSettlement(full, registry: registry, config: registry.config,
                                                     tick: 0, mapSeed: 1).storage[.materials]
        let emptyOut = ResourceLoop.advanceSettlement(empty, registry: registry, config: registry.config,
                                                      tick: 0, mapSeed: 1).storage[.materials]
        #expect(emptyOut > 0)          // some gathering still possible
        #expect(emptyOut < fullOut)    // but a full forest yields more
        // Floor is 0.35 of full; allow slack for the regrowth that also happened.
        #expect(emptyOut >= fullOut * 0.3)
    }

    @Test("Deposits regrow toward capacity when left alone")
    func regrowth() {
        // No loggers → the half-empty forest should recover over time.
        var s = loggingVillage(loggers: 0, forestAmount: 100)
        for tick in 0..<200 {
            s = ResourceLoop.advanceSettlement(s, registry: registry, config: registry.config,
                                               tick: tick, mapSeed: 1)
        }
        #expect(s.localMap!.nodes[0].amount > 100)
    }

    @Test("Gathering factors reflect how full the pools are, keyed by work")
    func factors() {
        let full = loggingVillage(loggers: 1, forestAmount: 200).localMap
        let empty = loggingVillage(loggers: 1, forestAmount: 0).localMap
        #expect(ResourceLoop.gatheringFactors(full)[.logging] == 1.0)
        #expect(ResourceLoop.gatheringFactors(empty)[.logging] == ResourceLoop.depositFloorFactor)
    }
}
