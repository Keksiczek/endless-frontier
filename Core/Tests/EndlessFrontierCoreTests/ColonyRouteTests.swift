import Testing
import Foundation
@testable import EndlessFrontierCore

/// Walking round the houses rather than through them.
///
/// Keks, watching the valley: *"nyní se chodí přes domy."* Every walk in the
/// game was a straight line — an errand from a job to a granary, a hauler
/// carrying a load home — and the shortest way across a town runs over whatever
/// is standing in it.
@Suite("People walk round the houses")
struct ColonyRouteTests {

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "40074E00-0000-0000-0000-%012d", n))!
    }

    /// A colony with a long barn straight across the middle, so any walk from
    /// one side to the other has to go round one end or the other.
    private func walledColony() -> ColonyMap {
        var colony = ColonyMap(width: 24, height: 24)
        colony.placements = [
            BuildingPlacement(id: id(1), definitionID: "granary",
                              coord: TileCoord(4, 11), width: 16, height: 3)
        ]
        return colony
    }

    private func point(_ x: Int, _ y: Int, in colony: ColonyMap) -> LocalPoint {
        SettlementGeometry.canvasPoint(tileX: x, tileY: y, in: colony)
    }

    // MARK: - The complaint

    @Test("A walk across a barn goes round it")
    func theWalkGoesRound() {
        let colony = walledColony()
        let a = point(12, 3, in: colony)      // north of the barn
        let b = point(12, 20, in: colony)     // south of it
        #expect(ColonyRoute.crossesABuilding(from: a, to: b, in: colony, allowing: []),
                "the fixture does not actually put a building in the way")

        let corners = ColonyRoute.corners(from: a, to: b, in: colony)
        #expect(!corners.isEmpty, "they walked straight through the barn")

        // Every leg of the route has to be clear, not just the ends.
        var here = a
        for corner in corners + [b] {
            #expect(!ColonyRoute.crossesABuilding(from: here, to: corner,
                                                  in: colony, allowing: []),
                    "a leg of the route still goes through the barn")
            here = corner
        }
    }

    @Test("Going round costs more than going through would have")
    func theLongWayIsLonger() {
        let colony = walledColony()
        let a = point(12, 3, in: colony)
        let b = point(12, 20, in: colony)
        let corners = ColonyRoute.corners(from: a, to: b, in: colony)
        #expect(ColonyRoute.length(from: a, through: corners, to: b)
                > SiegeField.distance(a, b),
                "the detour was free, so distance has stopped being a cost")
    }

    // MARK: - …without becoming a nuisance

    @Test("A clear walk is still a straight line")
    func nothingInTheWayMeansNoCorners() {
        let colony = walledColony()
        // Both ends north of the barn.
        let a = point(4, 3, in: colony)
        let b = point(18, 5, in: colony)
        #expect(ColonyRoute.corners(from: a, to: b, in: colony).isEmpty)
    }

    /// The building somebody is *going to* is not in their way — they are going
    /// inside it. Without this every walk to the granary would refuse to end.
    @Test("The place you are walking to is not an obstacle")
    func theDestinationIsNotInTheWay() {
        let colony = walledColony()
        let outside = point(12, 3, in: colony)
        let doorway = point(12, 12, in: colony)   // inside the barn itself
        #expect(ColonyRoute.corners(from: outside, to: doorway, in: colony).isEmpty)
    }

    @Test("A colony with nothing built in it needs no routing")
    func anEmptyColonyIsAllOpenGround() {
        let empty = ColonyMap(width: 24, height: 24)
        #expect(ColonyRoute.corners(from: point(2, 2, in: empty),
                                    to: point(20, 20, in: empty), in: empty).isEmpty)
        #expect(ColonyRoute.corners(from: point(2, 2, in: empty),
                                    to: point(20, 20, in: empty), in: nil).isEmpty)
    }

    /// Ground outside the colony grid — the woods, the far plots, the shore —
    /// is open, and asking for a route across it must not cost anything or
    /// invent corners in the middle of a field.
    @Test("A walk that starts off the colony grid is left alone")
    func openCountryNeedsNoRoute() {
        let colony = walledColony()
        let farField = LocalPoint(x: 0.02, y: 0.02)
        #expect(ColonyRoute.corners(from: farField, to: point(12, 20, in: colony),
                                    in: colony).isEmpty)
    }

    // MARK: - The rules that must not break

    @Test("The same two points always give the same way round")
    func routingIsDeterministic() {
        let colony = walledColony()
        let a = point(12, 3, in: colony), b = point(12, 20, in: colony)
        #expect(ColonyRoute.corners(from: a, to: b, in: colony)
                == ColonyRoute.corners(from: a, to: b, in: colony))
    }

    /// A route is a handful of corners, not a tile-by-tile staircase — a
    /// colonist who walks every cell centre reads as a piece on a board rather
    /// than somebody cutting across a square.
    @Test("A route is corners, not a staircase")
    func routesAreStraightened() {
        let colony = walledColony()
        let corners = ColonyRoute.corners(from: point(12, 3, in: colony),
                                          to: point(12, 20, in: colony), in: colony)
        #expect(corners.count <= 4, "\(corners.count) corners to walk round one barn")
    }

    /// A walled-in courtyard has no way out, and a colonist who cannot find one
    /// still has to be able to eat. Refusing the walk is the shape of bug this
    /// project keeps producing (rule 22) — so no route means walk straight.
    @Test("Somewhere with no way round is walked straight rather than not at all")
    func theresAlwaysAWalk() {
        var colony = ColonyMap(width: 24, height: 24)
        // A ring of building sealing the middle off entirely.
        colony.placements = [
            BuildingPlacement(id: id(2), definitionID: "wall", coord: TileCoord(8, 8),
                              width: 8, height: 1),
            BuildingPlacement(id: id(3), definitionID: "wall", coord: TileCoord(8, 15),
                              width: 8, height: 1),
            BuildingPlacement(id: id(4), definitionID: "wall", coord: TileCoord(8, 8),
                              width: 1, height: 8),
            BuildingPlacement(id: id(5), definitionID: "wall", coord: TileCoord(15, 8),
                              width: 1, height: 8)
        ]
        let inside = point(11, 11, in: colony)
        let outside = point(2, 2, in: colony)
        // Whatever it decides, it must decide *something* and not hang.
        _ = ColonyRoute.corners(from: inside, to: outside, in: colony)
    }
}
