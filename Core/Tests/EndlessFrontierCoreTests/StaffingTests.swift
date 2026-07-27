import Foundation
import Testing
@testable import EndlessFrontierCore

/// A colonist's *trade* (`assignedWork`) and their *post* (the building whose
/// roster they are on) used to meet exactly once, at founding. Everyone born
/// afterwards, come of age, or moved to another trade held a trade with no
/// address — so a century in, the workshops stood empty on paper while the town
/// was full of smiths.
@Suite("Colonists take up a post at a building that wants their trade")
struct StaffingTests {
    private let registry = Fixtures.registry(buildings: [
        BuildingDefinition(id: "farm", era: .earlySettlement, name: "Farm",
                           cost: [.materials: 20], workers: 2, production: [.food: 10]),
        BuildingDefinition(id: "library", era: .earlySettlement, name: "Library",
                           cost: [.materials: 30], workers: 1, production: [.knowledge: 5]),
        // Employs people, produces nothing the ledger counts — only the `work`
        // field can say what goes on inside.
        BuildingDefinition(id: "hospital", era: .earlySettlement, name: "Hospital",
                           cost: [.materials: 40], workers: 2, work: .healing)
    ])

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-5AFF-%012d", n))!
    }

    /// A settlement with a laid-out colony and a roster nobody has been seated on.
    private func town(_ trades: [WorkKind], buildings: [String]) -> Settlement {
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-5AFF-FFFFFFFFFFFF")!,
                           name: "Postville", kind: .capital,
                           pawns: trades.enumerated().map { i, w in
                               Pawn(id: id(i + 1), name: "Worker \(i)", assignedWork: w)
                           })
        var map = ColonyMap(width: 12, height: 12)
        for (i, bid) in buildings.enumerated() {
            map.placements.append(
                BuildingPlacement(id: id(900 + i), definitionID: bid,
                                  coord: TileCoord(i * 3, 0),
                                  width: 1, height: 1))
        }
        s.colony = map
        return s
    }

    private func roster(_ s: Settlement, _ definitionID: String) -> [UUID] {
        s.colony?.placements.first { $0.definitionID == definitionID }?.assignedPawnIDs ?? []
    }

    @Test("A farmer with no post is seated at the farm")
    func tradesFindTheirBuilding() {
        let s = LaborEngine.staffBuildings(town([.farming], buildings: ["farm"]),
                                           registry: registry)
        #expect(roster(s, "farm") == [id(1)])
    }

    @Test("A colonist is never seated at a building for someone else's trade")
    func tradesDoNotCross() {
        let s = LaborEngine.staffBuildings(town([.farming, .research],
                                                buildings: ["farm", "library"]),
                                           registry: registry)
        #expect(roster(s, "farm") == [id(1)])
        #expect(roster(s, "library") == [id(2)])
    }

    /// The reason `BuildingDefinition.work` exists at all.
    @Test("A hospital produces nothing and still gets its healers")
    func aBuildingMayNameItsTrade() {
        let s = LaborEngine.staffBuildings(town([.healing], buildings: ["hospital"]),
                                           registry: registry)
        #expect(roster(s, "hospital") == [id(1)])
    }

    @Test("A building takes no more hands than it employs")
    func benchesAreFinite() {
        let s = LaborEngine.staffBuildings(
            town([.research, .research, .research], buildings: ["library"]),
            registry: registry)
        #expect(roster(s, "library").count == 1)   // library employs one
    }

    @Test("Changing trade vacates the old post")
    func aChangedTradeGivesUpItsBench() {
        var s = LaborEngine.staffBuildings(town([.farming], buildings: ["farm", "library"]),
                                           registry: registry)
        #expect(roster(s, "farm") == [id(1)])
        s.pawns[0].assignedWork = .research
        s = LaborEngine.staffBuildings(s, registry: registry)
        #expect(roster(s, "farm").isEmpty)
        #expect(roster(s, "library") == [id(1)])
    }

    @Test("Children and the idle hold no post")
    func onlyWorkingAdultsAreSeated() {
        var s = town([.farming], buildings: ["farm"])
        s.pawns.append(Pawn(id: id(2), name: "Kid", assignedWork: .farming, age: 0))
        s.pawns.append(Pawn(id: id(3), name: "Loafer", assignedWork: .idle))
        let staffed = LaborEngine.staffBuildings(s, registry: registry)
        #expect(staffed.pawns.count == 3)
        #expect(roster(staffed, "farm") == [id(1)])
    }

    @Test("A building site is not a workplace until its roof is on")
    func sitesAreNotStaffed() {
        var s = town([.farming], buildings: ["farm"])
        s.colony?.placements[0].underConstruction = true
        let staffed = LaborEngine.staffBuildings(s, registry: registry)
        #expect(roster(staffed, "farm").isEmpty)
    }

    @Test("Nobody holds two posts at once")
    func onePostEach() {
        let s = LaborEngine.staffBuildings(town([.farming], buildings: ["farm", "farm"]),
                                           registry: registry)
        let seats = s.colony?.placements.flatMap(\.assignedPawnIDs) ?? []
        #expect(seats == [id(1)])
    }

    /// The world must not drift between two runs of the same seed.
    @Test("Staffing the same town twice fills the same benches")
    func staffingIsDeterministic() {
        let a = LaborEngine.staffBuildings(
            town([.farming, .farming, .research], buildings: ["farm", "library"]),
            registry: registry)
        let b = LaborEngine.staffBuildings(
            town([.farming, .farming, .research], buildings: ["farm", "library"]),
            registry: registry)
        #expect(a.colony?.placements.map(\.assignedPawnIDs)
                == b.colony?.placements.map(\.assignedPawnIDs))
    }

    /// Value types: an untouched settlement must come back untouched, or every
    /// tick pays to copy a colony that did not change.
    @Test("A settled town is returned unchanged")
    func steadyStateIsFree() {
        let once = LaborEngine.staffBuildings(town([.farming], buildings: ["farm"]),
                                              registry: registry)
        let twice = LaborEngine.staffBuildings(once, registry: registry)
        #expect(once == twice)
    }

    @Test("A colony with no layout yet is left alone")
    func noGridNoPosts() {
        var s = town([.farming], buildings: [])
        s.colony = nil
        #expect(LaborEngine.staffBuildings(s, registry: registry).colony == nil)
    }
}
