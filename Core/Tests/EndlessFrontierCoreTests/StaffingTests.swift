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

/// Rosters were bookkeeping: output came from building *counts*, so an empty
/// workshop produced exactly as much as a full one and the whole labour economy
/// was decoration. You could lose half the colony and the ledger wouldn't notice.
@Suite("Who is at the bench decides what comes off it")
struct StaffingEconomyTests {
    private let registry = Fixtures.registry(buildings: [
        BuildingDefinition(id: "farm", era: .earlySettlement, name: "Farm",
                           cost: [.materials: 20], workers: 2, production: [.food: 10]),
        BuildingDefinition(id: "hut", era: .earlySettlement, name: "Hut",
                           cost: [.materials: 10], housing: 30)
    ])

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-B0B0-%012d", n))!
    }

    private func farmTown(staffed: Int) -> Settlement {
        var s = Settlement(id: id(1), name: "Benchville", kind: .capital,
                           buildings: [BuildingInstance(definitionID: "farm", count: 1)])
        var map = ColonyMap(width: 12, height: 12)
        map.placements = [BuildingPlacement(
            id: id(2), definitionID: "farm", coord: TileCoord(0, 0),
            assignedPawnIDs: (0..<staffed).map { id(100 + $0) })]
        s.colony = map
        return s
    }

    @Test("A fully manned building yields more than an empty one")
    func handsAtTheBenchPay() {
        let empty = ResourceLoop.staffingFactors(farmTown(staffed: 0), registry: registry)["farm"]
        let full = ResourceLoop.staffingFactors(farmTown(staffed: 2), registry: registry)["farm"]
        #expect(empty == ResourceLoop.unstaffedFloor)
        #expect(full == 1)
    }

    @Test("Half the hands is half the difference, not half the output")
    func staffingScalesSmoothly() {
        let half = ResourceLoop.staffingFactors(farmTown(staffed: 1), registry: registry)["farm"]
        #expect(half == ResourceLoop.unstaffedFloor + (1 - ResourceLoop.unstaffedFloor) * 0.5)
    }

    /// An empty colony must be set back, not annihilated — a hard floor would
    /// make one bad winter of deaths end the run outright.
    @Test("An unmanned colony is set back, never wiped out")
    func theFloorIsMerciful() {
        #expect(ResourceLoop.unstaffedFloor > 0)
        #expect(ResourceLoop.unstaffedFloor < 1)
    }

    @Test("A settlement with no grid is taken as fully manned")
    func gridlessSettlementsAreUnaffected() {
        var s = farmTown(staffed: 0)
        s.colony = nil
        #expect(ResourceLoop.staffingFactors(s, registry: registry).isEmpty)
    }

    /// A hut has no bench to stand empty, so nothing about staffing may dock it.
    ///
    /// It *does* appear in the table now — every standing building carries its
    /// state of repair, and a hut with the roof off produces no shelter — so
    /// the question is whether the factor is whole, not whether the building is
    /// absent from the map.
    @Test("A building that employs nobody is never docked")
    func unstaffableBuildingsKeepTheirOutput() {
        var s = farmTown(staffed: 0)
        s.colony?.placements.append(BuildingPlacement(
            id: id(3), definitionID: "hut", coord: TileCoord(6, 6)))
        #expect(ResourceLoop.staffingFactors(s, registry: registry)["hut"] == 1)
    }

    @Test("A building falling down produces less, and a ruin produces nothing")
    func disrepairDocksOutput() {
        var s = farmTown(staffed: 2)
        s.colony?.placements.append(BuildingPlacement(
            id: id(4), definitionID: "hut", coord: TileCoord(8, 8), condition: 0.5))
        let battered = ResourceLoop.staffingFactors(s, registry: registry)["hut"] ?? 1
        #expect(battered < 1)

        if var colony = s.colony {
            colony.placements[colony.placements.count - 1].condition = 0.05
            s.colony = colony
        }
        #expect((ResourceLoop.staffingFactors(s, registry: registry)["hut"] ?? 1) == 0)
    }

    @Test("A building site is not docked for standing empty")
    func sitesAreNotCounted() {
        var s = farmTown(staffed: 0)
        s.colony?.placements[0].underConstruction = true
        #expect(ResourceLoop.staffingFactors(s, registry: registry)["farm"] == nil)
    }
}

/// Palisade, watchtower, barracks and stone walls all employ people and produce
/// nothing the ledger counts, so their trade was unknowable and no colonist
/// could ever be seated at them — four buildings whose `workers` was a lie.
@Suite("The walls can finally be manned")
struct GarrisonTests {
    @Test("A garrison is a trade that pays and produces nothing")
    func garrisonIsARealTrade() {
        #expect(WorkKind.garrison.resource == nil)
        #expect(SocietyEngine.wage(for: .garrison) > 0)
    }

    @Test("The defensive buildings all name the garrison as their trade")
    func wallsNameTheirTrade() throws {
        let reg = try GameDataRegistry.bundled()
        for id in ["palisade", "watchtower", "barracks", "stone_walls"] {
            let def = try #require(reg.building(id))
            #expect(ColonyBuilder.workKind(for: def) == .garrison, "\(id)")
            #expect(def.workers > 0, "\(id) employs nobody")
        }
    }

    @Test("Nobody stands a watch before there is anything to watch from")
    func noWallsNoWatch() {
        let quiet = LaborEngine.neediestRole(
            counts: [:], adultCount: 20, population: 20, hasWalls: false)
        #expect(quiet != .garrison)
    }

    @Test("Once walls stand, the watch becomes a role the colony fills")
    func wallsOpenTheRole() {
        // Every other quota already met, so the only deficit left is the watch.
        var counts: [WorkKind: Int] = [:]
        for (work, share) in LaborEngine.quotas {
            counts[work] = Int(share * 100) + 20
        }
        let role = LaborEngine.neediestRole(
            counts: counts, adultCount: 100, population: 100, hasWalls: true)
        #expect(role == .garrison)
    }
}
