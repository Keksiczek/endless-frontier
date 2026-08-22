import Testing
import Foundation
@testable import EndlessFrontierCore

/// The settlement had roofs and no ways between them, which is why a village
/// read as boxes standing on grass. These tests are mostly about **reach**:
/// a track worn at a rate no colony ever achieves is the shape this project
/// keeps finding (rules 6, 69), so the numbers below are asserted against what
/// an ordinary town actually walks.
@Suite("The ways worn inside a town")
struct SettlementPathTests {

    /// A colony grid with two lots on it, far enough apart to have a way
    /// between them and near enough that the walk is counted.
    private func colony() -> ColonyMap {
        var map = ColonyMap(width: 34, height: 34)
        map.placements = [
            BuildingPlacement(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
                              definitionID: "house", coord: TileCoord(10, 16), width: 2, height: 2),
            BuildingPlacement(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
                              definitionID: "workshop", coord: TileCoord(22, 16), width: 3, height: 3)
        ]
        return map
    }

    private func town(walkers: Int) -> Settlement {
        let map = colony()
        let home = map.placements[0].id
        let shop = map.placements[1]
        let work = SettlementGeometry.canvasPoint(for: shop, in: map)
        var people = Fixtures.pawns(walkers, work: .crafting)
        for index in people.indices {
            people[index].homeID = home
            people[index].currentJob = Job(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 500))!,
                kind: .craftItem, position: work, placementID: shop.id)
        }
        var s = Settlement(name: "Track Town", pawns: people, colony: map)
        s.localMap = nil
        return s
    }

    // MARK: - The line itself

    @Test("A way between two lots is connected, not a dotted line of corners")
    func lineIsSupercover() {
        let tiles = SettlementPaths.line(from: TileCoord(0, 0), to: TileCoord(4, 3))
        #expect(tiles.first == TileCoord(0, 0))
        #expect(tiles.last == TileCoord(4, 3))
        for (a, b) in zip(tiles, tiles.dropFirst()) {
            let step = abs(a.x - b.x) + abs(a.y - b.y)
            #expect(step == 1, "a track that jumps a corner is drawn as dots, not as a road")
        }
    }

    @Test("A way is the same way walked from either end")
    func lineIsSymmetric() {
        let there = Set(SettlementPaths.line(from: TileCoord(3, 9), to: TileCoord(11, 4)))
        let back = Set(SettlementPaths.line(from: TileCoord(11, 4), to: TileCoord(3, 9)))
        #expect(there == back)
    }

    // MARK: - Reachability: can an ordinary town actually wear a path?

    /// Rule 6. A wear rate that never crosses `visibleAbove` is a feature
    /// nobody would ever see, and that is the failure mode worth a test.
    @Test("A dozen people going to work wear a visible track within a few years")
    func aTownWearsItsOwnStreets() {
        var s = town(walkers: 12)
        // Ten passes is five in-game years at `PathEngine.interval`.
        for _ in 0..<10 { s = PathEngine.wear(s) }
        let worn = s.paths.worn
        #expect(!worn.isEmpty, "twelve people walking one route every day left no mark")
        // The way runs between the two lots, so a tile in the middle of it must
        // be one of the worn ones.
        #expect(s.paths.wear(at: TileCoord(16, 17)) >= SettlementPaths.visibleAbove)
    }

    @Test("One person walking alone does not make a road")
    func aSinglePairOfFeetIsNotAStreet() {
        var s = town(walkers: 1)
        for _ in 0..<40 { s = PathEngine.wear(s) }
        #expect(s.paths.worn.isEmpty,
                "a track needs a couple of households, or every colonist draws their own road")
    }

    @Test("A track settles rather than climbing for ever")
    func wearHasACeiling() {
        var s = town(walkers: 6)
        for _ in 0..<10 { s = PathEngine.wear(s) }
        let early = s.paths.wear(at: TileCoord(16, 17))
        for _ in 0..<40 { s = PathEngine.wear(s) }
        let late = s.paths.wear(at: TileCoord(16, 17))
        #expect(late <= 1.0)
        #expect(abs(late - early) < 0.2,
                "wear must reach an equilibrium, or every route in a town saturates")
    }

    @Test("A way nobody walks any more goes back to grass")
    func abandonedWaysFade() {
        var s = town(walkers: 12)
        for _ in 0..<20 { s = PathEngine.wear(s) }
        #expect(!s.paths.worn.isEmpty)
        // The shop burns down and everybody stays home.
        for index in s.pawns.indices { s.pawns[index].currentJob = nil }
        s.colony?.placements.removeLast()
        for _ in 0..<40 { s = PathEngine.wear(s) }
        #expect(s.paths.wear(at: TileCoord(20, 17)) < SettlementPaths.visibleAbove,
                "the grass has to take a track back, or a town keeps every street it ever had")
    }

    @Test("People with no work still wear a way to the green")
    func theGreenIsWalkedOn() {
        var s = town(walkers: 10)
        for index in s.pawns.indices { s.pawns[index].currentJob = nil }
        for _ in 0..<20 { s = PathEngine.wear(s) }
        let green = TileCoord(SettlementGeometry.greenOrigin(34) + SettlementGeometry.greenTiles / 2,
                              SettlementGeometry.greenOrigin(34) + SettlementGeometry.greenTiles / 2)
        #expect(s.paths.wear(at: green) >= SettlementPaths.visibleAbove)
    }

    /// A hunter's job is a beast somewhere out in the valley; a made way drawn
    /// to wherever a deer stood this season is exactly the invented drawing
    /// rule 18 forbids.
    @Test("A journey right across the valley does not become a street")
    func longJourneysAreNotStreets() {
        var s = town(walkers: 20)
        let far = SettlementGeometry.canvasPoint(tileX: 33, tileY: 2, in: s.colony!)
        for index in s.pawns.indices {
            s.pawns[index].currentJob = Job(id: UUID(), kind: .stalkAnimal, position: far)
        }
        for _ in 0..<20 { s = PathEngine.wear(s) }
        #expect(s.paths.wear(at: TileCoord(30, 5)) < SettlementPaths.visibleAbove)
    }

    // MARK: - It has to survive being saved

    /// Rule 73 — the roads network was written for a fortnight before anybody
    /// noticed it had no `CodingKeys` case and was never saved at all.
    @Test("Ways worn into a town are still there when the save is loaded")
    func pathsSurviveARoundTrip() throws {
        var s = town(walkers: 12)
        for _ in 0..<10 { s = PathEngine.wear(s) }
        #expect(!s.paths.isEmpty, "nothing to round-trip means the test proves nothing (rule 73)")
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(Settlement.self, from: data)
        #expect(back.paths.tiles == s.paths.tiles)
    }

    @Test("A save written before the town had ways loads as a town with none")
    func oldSavesLoad() throws {
        var s = town(walkers: 3)
        for _ in 0..<5 { s = PathEngine.wear(s) }
        var json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(s)) as! [String: Any]
        json.removeValue(forKey: "paths")
        let data = try JSONSerialization.data(withJSONObject: json)
        let back = try JSONDecoder().decode(Settlement.self, from: data)
        #expect(back.paths.isEmpty)
    }

    // MARK: - Wiring

    @Test("A world left to itself wears its own streets")
    func theTickWearsPaths() throws {
        let registry = try GameDataRegistry.bundled()
        var world = GameWorldFactory.newGame(registry: registry, seed: 4242,
                                             now: Date(timeIntervalSince1970: 1_700_000_000))
        world = TickEngine.advance(world, ticks: PathEngine.interval * 6, registry: registry).state
        #expect(!world.settlements[0].paths.isEmpty,
                "the engine exists and nothing calls it is this project's commonest bug")
    }
}
