import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Labor auto-assignment")
struct LaborTests {
    private let registry = Fixtures.registry()

    private func village(idleAdults: Int = 0, children: Int = 0, assigned: [WorkKind] = []) -> Settlement {
        var pawns: [Pawn] = []
        var n = 0
        func id() -> UUID {
            n += 1
            return UUID(uuidString: String(format: "00000000-0000-0000-0C0C-%012d", n))!
        }
        pawns += (0..<idleAdults).map { _ in Pawn(id: id(), name: "Idle") }
        pawns += (0..<children).map { _ in Pawn(id: id(), name: "Kid", age: 0) }
        pawns += assigned.map { Pawn(id: id(), name: "Worker", assignedWork: $0) }
        return Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-8a32c39c808d")!, name: "Village", kind: .capital, pawns: pawns)
    }

    @Test("Idle adults are put to work")
    func idleAdultsAssigned() {
        let s = LaborEngine.assignIdleAdults(village(idleAdults: 10), registry: registry)
        #expect(s.pawns.allSatisfy { $0.assignedWork != .idle })
    }

    @Test("Children are left idle until they come of age")
    func childrenStayIdle() {
        let s = LaborEngine.assignIdleAdults(village(idleAdults: 2, children: 3), registry: registry)
        let kids = s.pawns.filter { $0.age == 0 }
        #expect(kids.allSatisfy { $0.assignedWork == .idle })
    }

    @Test("A manually assigned specialist is not reshuffled")
    func manualChoicesStick() {
        // One trader among idle adults; auto-assign must not move them.
        var s = village(idleAdults: 5, assigned: [.trade])
        let traderID = s.pawns.first { $0.assignedWork == .trade }!.id
        s = LaborEngine.assignIdleAdults(s, registry: registry)
        #expect(s.pawns.first { $0.id == traderID }?.assignedWork == .trade)
    }

    @Test("Assignment spreads across roles by quota, favouring farming")
    func spreadsByQuota() {
        let s = LaborEngine.assignIdleAdults(village(idleAdults: 20), registry: registry)
        let byWork = Dictionary(grouping: s.pawns, by: \.assignedWork).mapValues(\.count)
        // Farming has the highest quota, so it should be the most-staffed role.
        let farming = byWork[.farming, default: 0]
        #expect(farming >= 4)
        #expect(byWork.keys.count >= 4)   // several roles filled, not all farmers
    }

    @Test("Healing stays unstaffed in a tiny settlement")
    func healingGatedBySize() {
        let s = LaborEngine.assignIdleAdults(village(idleAdults: 6), registry: registry)
        #expect(s.pawns.allSatisfy { $0.assignedWork != .healing })
    }

    @Test("Auto-assignment is deterministic")
    func deterministic() {
        let a = LaborEngine.assignIdleAdults(village(idleAdults: 15), registry: registry)
        let b = LaborEngine.assignIdleAdults(village(idleAdults: 15), registry: registry)
        #expect(a.pawns.map(\.assignedWork) == b.pawns.map(\.assignedWork))
    }
}
