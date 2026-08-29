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

    // MARK: - The floors under the shares

    /// Rule 6 in the quota table: **can every colony the game allows staff the
    /// trades it cannot live without?**
    ///
    /// Written as a sweep over every size rather than as one village, because
    /// the failure is arithmetic and only shows at the small end: a share of
    /// 0.07 is a person and a half in a town of twenty and half a person in a
    /// hamlet of seven, and `rebalance` moves nobody for less than half a body
    /// — so the trades at the bottom of the table become unfillable somewhere
    /// on the way down and nothing said where.
    @Test("A colony of any size can staff the trades it cannot live without")
    func everyColonyCanStaffItsEssentials() {
        for adults in 2...40 {
            var s = LaborEngine.assignIdleAdults(village(idleAdults: adults), registry: registry)
            // …and it has to survive losing them, which is the case the shares
            // never reached: nobody is idle, so only `rebalance` can answer.
            for work in LaborEngine.floors.map(\.work) {
                for i in s.pawns.indices where s.pawns[i].assignedWork == work {
                    s.pawns[i].assignedWork = .logging
                }
            }
            // A few cadences to let the slow hand work, one person at a time.
            for _ in 0..<LaborEngine.floors.count * 3 {
                s = LaborEngine.rebalance(s, registry: registry)
            }
            for (work, hands) in LaborEngine.floors {
                let staffed = s.pawns.count { $0.assignedWork == work }
                #expect(staffed >= hands,
                        "\(adults) adults and \(staffed) at \(work.rawValue) — it wants \(hands)")
            }
        }
    }

    /// The other half: a floor must not become a hole the colony falls into,
    /// taking the last farmer to make a cook and the last cook to make a farmer
    /// for ever.
    @Test("Filling one floor never empties another")
    func floorsDoNotRobEachOther() {
        var s = village(assigned: [.farming, .cooking])
        let before = s.pawns.map(\.assignedWork)
        for _ in 0..<8 { s = LaborEngine.rebalance(s, registry: registry) }
        #expect(s.pawns.map(\.assignedWork) == before)
    }

    /// Standing orders still outrank the floor — a player who switches the
    /// kitchen off gets a colony that eats raw, which is a valve that exists.
    @Test("Orders that switch a trade off beat its floor")
    func ordersBeatTheFloor() {
        var s = village(idleAdults: 12)
        s.policy = ColonyPolicy(trades: [.cooking: .off])
        s = LaborEngine.assignIdleAdults(s, registry: registry)
        #expect(s.pawns.allSatisfy { $0.assignedWork != .cooking })
    }

    @Test("Auto-assignment is deterministic")
    func deterministic() {
        let a = LaborEngine.assignIdleAdults(village(idleAdults: 15), registry: registry)
        let b = LaborEngine.assignIdleAdults(village(idleAdults: 15), registry: registry)
        #expect(a.pawns.map(\.assignedWork) == b.pawns.map(\.assignedWork))
    }
}

/// **A trade whose ground is worked out does not keep its hands.**
///
/// Measured 2026-08-29 (`OreProbe`): a plains colony has one iron seam by
/// design, it is empty by year thirty — and the colony went on posting miners
/// at it. Fourteen at year two hundred, with **nobody ever at a face**: a
/// tenth of a town swinging picks at bare rock while the fields wanted hands.
@Suite("Hands follow the ground")
struct WorkedOutGroundTests {

    private func map(stone: Double) -> LocalMap {
        LocalMap(
            river: RiverShape(baseY: 0.5, amplitude: 0.05, phase: 0),
            nodes: [ResourceNode(id: 1, kind: .stone, position: LocalPoint(x: 0.3, y: 0.3),
                                 amount: stone, capacity: 200),
                    ResourceNode(id: 2, kind: .forest, position: LocalPoint(x: 0.6, y: 0.4),
                                 amount: 200, capacity: 200)],
            pois: [], exploredCells: Set(0..<(LocalMap.gridColumns * LocalMap.gridRows)))
    }

    @Test("An empty seam keeps a token watch and not a shift")
    func minersLeaveABareSeam() {
        let full = LaborEngine.quotaTable(
            hasTemple: false, hasWalls: false, policy: ColonyPolicy(),
            fullness: LaborEngine.poolFullness(map(stone: 200)))
        let bare = LaborEngine.quotaTable(
            hasTemple: false, hasWalls: false, policy: ColonyPolicy(),
            fullness: LaborEngine.poolFullness(map(stone: 0)))
        let mining: ([(work: WorkKind, share: Double)]) -> Double = { table in
            table.first { $0.work == .mining }?.share ?? 0
        }
        #expect(mining(bare) < mining(full), "a bare seam asks for as many hands as a full one")
        #expect(mining(bare) > 0, "and not none: somebody has to notice a new seam")
        // The wood is untouched, so logging is not punished for the rock.
        let logging: ([(work: WorkKind, share: Double)]) -> Double = { table in
            table.first { $0.work == .logging }?.share ?? 0
        }
        #expect(logging(bare) == logging(full), "the forest was not the thing that ran out")
    }
}
