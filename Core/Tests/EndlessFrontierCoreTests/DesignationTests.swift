import Testing
import Foundation
@testable import EndlessFrontierCore

/// Keks: *"vše drawn je there, ale pak na věci nejde klikat, vybírat je k akci
/// — max doufat, že se někdy něco stane a někdo k nim půjde."*
///
/// The canvas could already *hit* a tree, a rock or a heap; every one of them
/// answered with a label. What is tested here is the half that turns watching
/// into playing: a marked thing is the one the colony works next, a mark
/// outlives nothing it points at, and none of it orders a person anywhere.
@Suite("A thing the player pointed at")
struct DesignationTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private func valley(trees: Int = 6, rocks: Int = 4) -> LocalMap {
        var map = LocalMap(river: RiverShape(baseY: 0.5, amplitude: 0.04, phase: 0),
                           nodes: [], pois: [],
                           // Work is only offered on charted ground.
                           exploredCells: Set(0..<(LocalMap.gridColumns * LocalMap.gridRows)),
                           terrainSeed: 7, usesEntityLand: true)
        map.trees = (0..<trees).map { i in
            Tree(id: i, species: .oak,
                 position: LocalPoint(x: 0.2 + Double(i) * 0.1, y: 0.3),
                 age: TreeSpecies.oak.maturityTicks)
        }
        map.rocks = (0..<rocks).map { i in
            Rock(id: i, kind: .granite,
                 position: LocalPoint(x: 0.3, y: 0.2 + Double(i) * 0.1),
                 amount: 40, capacity: 40)
        }
        return map
    }

    private func town(_ map: LocalMap) -> Settlement {
        var s = Settlement(name: "Marked", pawns: Fixtures.pawns(6, work: .logging))
        s.localMap = map
        return s
    }

    // MARK: - Marking

    @Test("A tap marks a thing, and the same tap again lifts the mark")
    func toggling() {
        var s = town(valley())
        s = DesignationEngine.toggle(s, target: .tree(3), tick: 100)
        #expect(DesignationEngine.isMarked(s, target: .tree(3)))
        #expect(s.designations.count == 1)
        #expect(s.designations[0].kind == .fell, "a tree is felled; there is nothing to choose")
        s = DesignationEngine.toggle(s, target: .tree(3), tick: 120)
        #expect(!DesignationEngine.isMarked(s, target: .tree(3)))
        #expect(s.designations.isEmpty)
    }

    @Test("Each kind of thing takes the order that suits it")
    func kindsFollowTheTarget() {
        #expect(Designation.Kind.forTarget(.tree(1)) == .fell)
        #expect(Designation.Kind.forTarget(.rock(1)) == .mine)
        #expect(Designation.Kind.forTarget(.pile(UUID())) == .haul)
        #expect(Designation.Kind.forTarget(.animal(UUID())) == .hunt)
        // …and every one of them says so in both languages.
        for kind in Designation.Kind.allCases {
            #expect(!kind.label.resolve(.cs).isEmpty)
            #expect(kind.label.resolve(.cs) != kind.label.resolve(.en))
            #expect(kind.standing.resolve(.cs) != kind.standing.resolve(.en))
        }
    }

    @Test("A player cannot write four thousand marks into a save")
    func markingIsBounded() {
        var s = town(valley(trees: 200))
        for i in 0..<200 { s = DesignationEngine.toggle(s, target: .tree(i), tick: 10) }
        #expect(s.designations.count == DesignationEngine.limit)
    }

    // MARK: - The colony works what was marked

    /// The whole point. `fell` takes the biggest tree standing; a marked
    /// sapling has to beat an unmarked oak, or pointing at something means
    /// nothing.
    @Test("The axe goes into the tree that was marked, not the biggest one")
    func fellingFollowsTheMark() {
        var map = valley(trees: 5)
        // Make the last tree the runt, and mark it.
        map.trees[4].age = TreeSpecies.oak.maturityTicks / 3
        let biggest = map.trees.max { $0.timberYield < $1.timberYield }?.id
        #expect(biggest != 4)
        let unmarked = FloraEngine.fell(map, loggers: 1)
        let marked = FloraEngine.fell(map, loggers: 1, marked: [4])
        // One logger, one tick: whichever tree took the axe has a chip in it.
        let chippedUnmarked = unmarked.map.trees.first { $0.chopped > 0 }?.id
        let chippedMarked = marked.map.trees.first { $0.chopped > 0 }?.id
        #expect(chippedUnmarked == biggest)
        #expect(chippedMarked == 4, "a marked runt outranks an unmarked oak")
    }

    @Test("The pick goes into the seam that was marked, not the softest")
    func quarryingFollowsTheMark() {
        var map = valley(rocks: 3)
        // The two rocks beside it are soft, so the default pick — softest
        // first — would never choose this one.
        map.rocks[0] = Rock(id: 0, kind: .clayBank,
                            position: LocalPoint(x: 0.3, y: 0.2), amount: 40, capacity: 40)
        map.rocks[1] = Rock(id: 1, kind: .limestone,
                            position: LocalPoint(x: 0.3, y: 0.3), amount: 40, capacity: 40)
        map.rocks[2] = Rock(id: 2, kind: .granite,
                            position: LocalPoint(x: 0.7, y: 0.7), amount: 40, capacity: 40)
        let unmarked = FloraEngine.quarry(map, miners: 1)
        let marked = FloraEngine.quarry(map, miners: 1, marked: [2])
        func worked(_ result: (map: LocalMap, yield: [LocalResourceKind: Double],
                               broken: [(kind: LocalResourceKind, amount: Double, at: LocalPoint)])) -> Int? {
            result.map.rocks.first { $0.amount < 40 }?.id
        }
        #expect(worked(unmarked) != 2, "the softest rock is the default")
        #expect(worked(marked) == 2)
    }

    @Test("A hauler walks past a nearer heap to fetch the marked one")
    func haulingFollowsTheMark() {
        var map = valley()
        let near = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let far = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
        map.piles = [
            HaulPile(id: near, position: LocalPoint(x: 0.51, y: 0.51), itemID: "wood", amount: 4),
            HaulPile(id: far, position: LocalPoint(x: 0.05, y: 0.95), itemID: "wood", amount: 4)
        ]
        let yard = LocalPoint(x: 0.5, y: 0.5)
        #expect(HaulEngine.nearestUnclaimed(in: map, to: yard)
                == map.piles.firstIndex { $0.id == near })
        #expect(HaulEngine.nearestUnclaimed(in: map, to: yard, marked: [far])
                == map.piles.firstIndex { $0.id == far })
    }

    @Test("The hunt takes the beast that was marked")
    func huntingFollowsTheMark() {
        let near = Animal(id: UUID(), species: .deer, sex: .female, age: 300,
                          position: LocalPoint(x: 0.52, y: 0.5))
        let far = Animal(id: UUID(), species: .deer, sex: .male, age: 300,
                         position: LocalPoint(x: 0.62, y: 0.5))
        let herd = [near, far]
        let from = LocalPoint(x: 0.5, y: 0.5)
        #expect(HuntEngine.quarry(in: herd, from: from, taken: []) == 0)
        #expect(HuntEngine.quarry(in: herd, from: from, taken: [], marked: [far.id]) == 1)
        // A mark is not a teleport: a beast outside the hunters' reach stays
        // outside it.
        let away = Animal(id: UUID(), species: .deer, sex: .female, age: 300,
                          position: LocalPoint(x: 0.99, y: 0.99))
        #expect(HuntEngine.quarry(in: [away], from: from, taken: [], marked: [away.id]) == nil)
    }

    // MARK: - A mark does not outlive its thing

    @Test("A felled tree takes its mark with it")
    func sweepingDropsWhatIsGone() {
        var s = town(valley(trees: 3, rocks: 2))
        s = DesignationEngine.toggle(s, target: .tree(1), tick: 10)
        s = DesignationEngine.toggle(s, target: .rock(0), tick: 10)
        s = DesignationEngine.toggle(s, target: .animal(UUID()), tick: 10)
        #expect(s.designations.count == 3)
        // The tree comes down, the seam is worked out, and the beast was never
        // in this valley.
        s.localMap?.trees.removeAll { $0.id == 1 }
        s.localMap?.rocks[0].amount = 0
        s = DesignationEngine.prune(s)
        #expect(s.designations.isEmpty, "a mark over grass is an icon that can never be satisfied")
    }

    @Test("A mark on something still standing survives the sweep")
    func sweepingKeepsWhatIsThere() {
        var s = town(valley())
        s = DesignationEngine.toggle(s, target: .tree(2), tick: 10)
        s = DesignationEngine.prune(s)
        #expect(DesignationEngine.isMarked(s, target: .tree(2)))
    }

    @Test("A colony with no valley loaded keeps the player's list")
    func sweepingIsNotDestructive() {
        var s = Settlement(name: "No map")
        s = DesignationEngine.toggle(s, target: .tree(1), tick: 10)
        #expect(DesignationEngine.prune(s).designations.count == 1)
    }

    // MARK: - Wiring

    @Test("Marks survive being saved")
    func marksRoundTrip() throws {
        var s = town(valley())
        s = DesignationEngine.toggle(s, target: .tree(1), tick: 10)
        s = DesignationEngine.toggle(s, target: .pile(UUID()), tick: 12)
        let back = try JSONDecoder().decode(Settlement.self, from: try JSONEncoder().encode(s))
        #expect(back.designations == s.designations)
    }

    @Test("A colony saved before anybody could point at anything still loads")
    func oldSavesLoad() throws {
        // A settlement as an older build wrote it: no `designations` key at all.
        var before = Settlement(name: "Old")
        before.designations = [Designation(target: .tree(1), placedTick: 5)]
        var object = try #require(try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(before)) as? [String: Any])
        object.removeValue(forKey: "designations")
        let older = try JSONSerialization.data(withJSONObject: object)
        let back = try JSONDecoder().decode(Settlement.self, from: older)
        #expect(back.designations.isEmpty)
    }

    /// The line this feature must not cross: marking a thing must not move
    /// anybody. It changes *which* target the trade works, never who works it.
    @Test("Marking a thing does not reassign a single colonist")
    func nobodyIsOrderedAnywhere() throws {
        let registry = try registry()
        let plain = town(valley())
        var marked = plain
        marked = DesignationEngine.toggle(marked, target: .tree(0), tick: 10)
        // The tick itself moves people between trades (`LaborEngine`), so what
        // has to be shown is that **the mark** moves nobody: the same colony,
        // one tick, with and without it.
        let a = ResourceLoop.advanceSettlement(plain, registry: registry,
                                               config: registry.config, tick: 20)
        let b = ResourceLoop.advanceSettlement(marked, registry: registry,
                                               config: registry.config, tick: 20)
        #expect(a.pawns.map { ($0.id, $0.assignedWork) }
                    .elementsEqual(b.pawns.map { ($0.id, $0.assignedWork) }, by: ==))
    }
}
