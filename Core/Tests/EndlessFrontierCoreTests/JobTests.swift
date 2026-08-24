import Foundation
import Testing
@testable import EndlessFrontierCore

/// A trade says what a colonist *does*; a job says what they are *doing*.
/// Until this layer there was only the trade, so nobody ever went to a
/// particular tree — the canvas guessed a plausible spot and the economy
/// harvested an abstract pool, and the logger drawn under a trunk had no
/// relationship to it.

private let mapSeed: UInt64 = 5150

private func id(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-30B5-%012d", n))!
}

private func wooded(trees: Int = 3, rocks: Int = 2) -> LocalMap {
    var map = LocalMap(river: RiverShape(baseY: 0.5, amplitude: 0.04, phase: 0),
                       nodes: [], pois: [],
                       // Work is only offered on charted ground, so a fixture
                       // that tests job-posting has to have some.
                       exploredCells: Set(0..<(LocalMap.gridColumns * LocalMap.gridRows)),
                       terrainSeed: mapSeed, usesEntityLand: true)
    map.trees = (0..<trees).map {
        Tree(id: $0, species: "oak", position: LocalPoint(x: 0.2 + Double($0) * 0.1, y: 0.3),
             age: LegacyTreeSpecies.oak.maturityTicks)
    }
    map.rocks = (0..<rocks).map {
        Rock(id: $0, kind: .granite, position: LocalPoint(x: 0.7, y: 0.2 + Double($0) * 0.1),
             amount: 50, capacity: 50)
    }
    return map
}

private func town(_ trades: [WorkKind], map: LocalMap = wooded()) -> Settlement {
    var s = Settlement(id: id(1), name: "Jobstown", kind: .capital,
                       pawns: trades.enumerated().map { i, w in
                           Pawn(id: id(100 + i), name: "Hand \(i)", assignedWork: w)
                       })
    s.localMap = map
    return s
}

@Suite("Every worker is on a named piece of work")
struct JobBoardTests {
    private let registry = Fixtures.registry()

    @Test("Standing wood is offered as work")
    func treesBecomeJobs() {
        let jobs = JobBoard.post(for: town([]), registry: registry)
        #expect(jobs.count { $0.kind == .fellTree } == 3)
        #expect(jobs.allSatisfy { $0.kind != .fellTree || $0.treeID != nil })
    }

    @Test("A logger is given a tree, not a general direction")
    func loggersGetATree() {
        let s = JobBoard.assign(town([.logging]), registry: registry)
        let job = s.pawns[0].currentJob
        #expect(job?.kind == .fellTree)
        #expect(job?.treeID != nil)
    }

    @Test("Two loggers do not chop the same trunk")
    func jobsAreNotSharedOut() {
        let s = JobBoard.assign(town([.logging, .logging]), registry: registry)
        let held = s.pawns.compactMap(\.currentJob?.id)
        #expect(held.count == 2)
        #expect(Set(held).count == 2)
    }

    @Test("Nobody is given work outside their trade")
    func tradesAreRespected() {
        let s = JobBoard.assign(town([.mining]), registry: registry)
        #expect(s.pawns[0].currentJob?.kind == .quarryRock)
    }

    /// The reason job ids are derived from the target rather than freshly made.
    @Test("A colonist keeps the job they are already on")
    func workIsNotDroppedAndRepicked() {
        var s = JobBoard.assign(town([.logging]), registry: registry)
        let first = s.pawns[0].currentJob
        s = JobBoard.assign(s, registry: registry)
        #expect(s.pawns[0].currentJob == first)
    }

    @Test("Work that has stopped existing is taken away")
    func finishedWorkIsReleased() {
        var s = JobBoard.assign(town([.logging]), registry: registry)
        #expect(s.pawns[0].currentJob != nil)
        s.localMap?.trees = []
        s = JobBoard.assign(s, registry: registry)
        #expect(s.pawns[0].currentJob == nil)
    }

    @Test("Children, the sick and the away hold no job")
    func onlyWorkersWork() {
        var s = town([.logging])
        s.pawns.append(Pawn(id: id(200), name: "Kid", assignedWork: .logging, age: 0))
        s.pawns.append(Pawn(id: id(201), name: "Sick", assignedWork: .logging,
                            health: 10, isBroken: true))
        let staffed = JobBoard.assign(s, registry: registry)
        #expect(staffed.pawns[1].currentJob == nil)
        #expect(staffed.pawns[2].currentJob == nil)
    }

    @Test("The same colony hands out the same work twice")
    func assignmentIsDeterministic() {
        let a = JobBoard.assign(town([.logging, .mining, .logging]), registry: registry)
        let b = JobBoard.assign(town([.logging, .mining, .logging]), registry: registry)
        #expect(a.pawns.map(\.currentJob) == b.pawns.map(\.currentJob))
    }

    /// Reported from a real game: colonists walking off into ground nobody has
    /// charted. Jobs came from every tree on the map, fog or not — and the
    /// canvas refuses to draw anyone under fog, so they simply vanished en route.
    @Test("No work is offered out in the fog")
    func jobsStayOnChartedGround() {
        var map = wooded(trees: 3, rocks: 0)
        map.exploredCells = []                      // nothing charted at all
        let jobs = JobBoard.post(for: town([.logging], map: map), registry: registry)
        #expect(jobs.isEmpty)

        // Chart the ground the wood stands on and the work appears.
        var charted = map
        charted.reveal(around: LocalPoint(x: 0.3, y: 0.3), radius: 0.3)
        #expect(!JobBoard.post(for: town([.logging], map: charted), registry: registry).isEmpty)
    }

    @Test("A settlement with no map offers nothing")
    func nothingToDo() {
        var s = town([.logging])
        s.localMap = nil
        #expect(JobBoard.post(for: s, registry: registry).isEmpty)
        #expect(JobBoard.assign(s, registry: registry).pawns[0].currentJob == nil)
    }

    /// A job's position must agree with where the renderer draws the thing, or
    /// a colonist is sent to a building that is on screen somewhere else.
    @Test("A building's job sits where the building is drawn")
    func geometryAgrees() {
        var colony = ColonyMap(width: 18, height: 18)
        colony.placements = [BuildingPlacement(id: id(9), definitionID: "farm",
                                               coord: TileCoord(0, 0), width: 2, height: 2)]
        let p = SettlementGeometry.canvasPoint(for: colony.placements[0], in: colony)
        // Top-left corner of an 18×18 grid, so up and left of the heart.
        #expect(p.x < SettlementGeometry.heart.x)
        #expect(p.y < SettlementGeometry.heart.y)
        #expect(abs(p.x - SettlementGeometry.heart.x) < SettlementGeometry.span)
    }
}

@Suite("The deposit is what is standing on it")
struct EntityEconomyTests {
    private let registry = Fixtures.registry()

    private func forestMap() -> LocalMap {
        var map = wooded(trees: 4, rocks: 0)
        map.nodes = [ResourceNode(id: 0, kind: .forest,
                                  position: LocalPoint(x: 0.25, y: 0.3),
                                  amount: 500, capacity: 500)]
        return map
    }

    @Test("A forest deposit reads the timber actually standing on it")
    func woodIsTheNumber() {
        let synced = FloraEngine.syncDeposits(forestMap())
        // Only the wood *near this node* counts as its stock.
        let node = synced.nodes[0]
        let claimed = synced.trees
            .filter { FloraEngine.within($0.position, node.position, FloraEngine.claimRadius) }
            .reduce(0.0) { $0 + $1.timberYield }
        #expect(node.amount == min(500, claimed))
        #expect(node.amount > 0)
        #expect(claimed < synced.trees.reduce(0.0) { $0 + $1.timberYield },
                "the fixture should have wood outside the node's reach")
    }

    @Test("Felling the wood empties the deposit with it")
    func fellingDrainsTheDeposit() {
        var map = FloraEngine.syncDeposits(forestMap())
        let before = map.nodes[0].amount
        map.trees = []
        map = FloraEngine.syncDeposits(map)
        #expect(map.nodes[0].amount == 0)
        #expect(before > 0)
    }

    @Test("A quarry that is worked out stays worked out")
    func stoneDoesNotComeBack() {
        var map = wooded(trees: 0, rocks: 2)
        map.nodes = [ResourceNode(id: 0, kind: .stone, position: LocalPoint(x: 0.7, y: 0.25),
                                  amount: 100, capacity: 100)]
        for i in map.rocks.indices { map.rocks[i].amount = 0 }
        map = FloraEngine.syncDeposits(map)
        #expect(map.nodes[0].amount == 0)
    }

    @Test("Ground with nothing standing on it keeps the old arithmetic")
    func fieldsAreUntouched() {
        var map = wooded()
        map.nodes = [ResourceNode(id: 0, kind: .field, position: LocalPoint(x: 0.5, y: 0.5),
                                  amount: 42, capacity: 100)]
        #expect(FloraEngine.syncDeposits(map).nodes[0].amount == 42)
        #expect(!FloraEngine.isEntityBacked(.field, in: map))
        #expect(FloraEngine.isEntityBacked(.forest, in: map))
    }

    @Test("A map with no entities at all is left exactly as it was")
    func oldSavesAreSafe() {
        var map = LocalMap(river: RiverShape(baseY: 0.5, amplitude: 0.04, phase: 0),
                           nodes: [ResourceNode(id: 0, kind: .forest,
                                                position: LocalPoint(x: 0.3, y: 0.3),
                                                amount: 77, capacity: 200)],
                           pois: [])
        map = FloraEngine.syncDeposits(map)
        #expect(map.nodes[0].amount == 77)
        #expect(!FloraEngine.isEntityBacked(.forest, in: map))
    }
}

@Suite("The hunt reads the animals, not a number about them")
struct HuntingEntityTests {
    private func valley(prey: Int, capacity: Double = 80) -> LocalMap {
        LocalMap(river: RiverShape(baseY: 0.5, amplitude: 0.04, phase: 0),
                 nodes: [], pois: [],
                 wildlife: WildlifeState(
                    deerHerd: capacity, deerCapacity: capacity, predatorPressure: 5,
                    animals: (0..<prey).map {
                        Animal(id: UUID(uuidString: String(format:
                            "00000000-0000-0000-DEE5-%012d", $0))!,
                               species: .deer, sex: .female, age: 100)
                    },
                    usesEntities: true))
    }

    /// The whole point of the entities. The abstract herd stays brim-full while
    /// every beast on the map is dead, and the larder used not to notice.
    @Test("A valley whose beasts died stops feeding its hunters")
    func deadBeastsMeanNoMeat() {
        let full = valley(prey: 20)
        let empty = valley(prey: 0)
        #expect(full.wildlife.deerHerd == empty.wildlife.deerHerd)   // same number…
        #expect(WildlifeEngine.huntingFactor(full.wildlife)
                > WildlifeEngine.huntingFactor(empty.wildlife))      // …different hunt
    }

    @Test("The fraction is a head count where there are heads to count")
    func fractionReadsTheAnimals() {
        let map = valley(prey: 10, capacity: 80)   // capacity 80 → 20 head
        #expect(map.wildlife.preyCapacity == 20)
        #expect(map.wildlife.preyCount == 10)
        #expect(abs(map.wildlife.herdFraction - 0.5) < 0.001)
    }

    /// The distinction the flag exists for: a map that never had an entity
    /// layer still reads the old number, while a map that *has* one and has
    /// lost every beast reads zero. Both have no animals.
    @Test("A save that predates the animals still uses the old number")
    func oldSavesKeepTheAbstraction() {
        let old = LocalMap(river: RiverShape(baseY: 0.5, amplitude: 0.04, phase: 0),
                           nodes: [], pois: [],
                           wildlife: WildlifeState(deerHerd: 40, deerCapacity: 80,
                                                   predatorPressure: 5))
        #expect(!old.wildlife.usesEntities)
        #expect(abs(old.wildlife.herdFraction - 0.5) < 0.001)

        let emptied = valley(prey: 0, capacity: 80)   // has the layer, lost the beasts
        #expect(emptied.wildlife.usesEntities)
        #expect(emptied.wildlife.herdFraction == 0)
    }

    @Test("Predators are not counted as game")
    func wolvesAreNotStock() {
        var map = valley(prey: 4)
        map.wildlife.animals.append(
            Animal(id: UUID(uuidString: "00000000-0000-0000-DEE5-FFFFFFFFFFFF")!,
                   species: .wolf, sex: .male, age: 200))
        #expect(map.wildlife.preyCount == 4)
    }
}
