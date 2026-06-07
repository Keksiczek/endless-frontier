import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Colony builder")
struct ColonyBuilderTests {
    private func town(pawnCount: Int = 0) -> Settlement {
        let pawns = (0..<pawnCount).map { Pawn(name: "P\($0)") }
        return Settlement(name: "Town", kind: .capital,
                          population: Double(max(pawnCount, 1)), pawns: pawns)
    }

    @Test("Placing a building adds it to the grid and the ledger")
    func placeSyncsLedger() {
        let reg = Fixtures.registry()
        let after = ColonyBuilder.place(town(), definitionID: "farm", at: TileCoord(1, 1), registry: reg)

        #expect(after.colony?.placements.count == 1)
        #expect(after.colony?.placement(at: TileCoord(1, 1))?.definitionID == "farm")
        #expect(after.buildings.first { $0.definitionID == "farm" }?.count == 1)
    }

    @Test("Placing the same building twice stacks the ledger count")
    func placeStacksLedger() {
        let reg = Fixtures.registry()
        var s = ColonyBuilder.place(town(), definitionID: "farm", at: TileCoord(0, 0), registry: reg)
        s = ColonyBuilder.place(s, definitionID: "farm", at: TileCoord(1, 0), registry: reg)

        #expect(s.colony?.placements.count == 2)
        #expect(s.buildings.first { $0.definitionID == "farm" }?.count == 2)
    }

    @Test("Placing out of bounds leaves the settlement unchanged")
    func placeOutOfBounds() {
        let reg = Fixtures.registry()
        let base = town()
        let after = ColonyBuilder.place(base, definitionID: "farm", at: TileCoord(999, 999), registry: reg)
        #expect(after == base)
    }

    @Test("Placing on an occupied tile is rejected")
    func placeOccupied() {
        let reg = Fixtures.registry()
        let first = ColonyBuilder.place(town(), definitionID: "farm", at: TileCoord(2, 2), registry: reg)
        let second = ColonyBuilder.place(first, definitionID: "library", at: TileCoord(2, 2), registry: reg)
        #expect(second == first)   // unchanged
        #expect(second.colony?.placements.count == 1)
    }

    @Test("Removing a building clears the tile and decrements the ledger")
    func removeClears() {
        let reg = Fixtures.registry()
        let placed = ColonyBuilder.place(town(), definitionID: "farm", at: TileCoord(3, 3), registry: reg)
        let removed = ColonyBuilder.remove(placed, at: TileCoord(3, 3))

        #expect(removed.colony?.placements.isEmpty == true)
        #expect(removed.buildings.contains { $0.definitionID == "farm" } == false)
    }

    @Test("Assigning a colonist sets their work to the building's kind")
    func assignSetsWork() {
        let reg = Fixtures.registry()
        let s0 = ColonyBuilder.place(town(pawnCount: 1), definitionID: "farm", at: TileCoord(0, 0), registry: reg)
        let pawnID = s0.pawns[0].id
        let placementID = s0.colony!.placements[0].id

        let s1 = ColonyBuilder.assign(s0, pawnID: pawnID, to: placementID, registry: reg)
        #expect(s1.pawns[0].assignedWork == .farming)          // farm produces food
        #expect(s1.colony?.placements[0].assignedPawnIDs == [pawnID])
    }

    @Test("Assignment respects the building's worker cap")
    func assignRespectsCap() {
        let reg = Fixtures.registry()                          // farm workers == 2
        var s = ColonyBuilder.place(town(pawnCount: 3), definitionID: "farm", at: TileCoord(0, 0), registry: reg)
        let placementID = s.colony!.placements[0].id
        for pawn in s.pawns {
            s = ColonyBuilder.assign(s, pawnID: pawn.id, to: placementID, registry: reg)
        }
        #expect(s.colony?.placements[0].assignedPawnIDs.count == 2)   // third was rejected
        #expect(s.pawns[2].assignedWork == .idle)
    }

    @Test("Unassigning frees the colonist and sets them idle")
    func unassignIdles() {
        let reg = Fixtures.registry()
        let s0 = ColonyBuilder.place(town(pawnCount: 1), definitionID: "farm", at: TileCoord(0, 0), registry: reg)
        let pawnID = s0.pawns[0].id
        let placementID = s0.colony!.placements[0].id
        let s1 = ColonyBuilder.assign(s0, pawnID: pawnID, to: placementID, registry: reg)
        let s2 = ColonyBuilder.unassign(s1, pawnID: pawnID)

        #expect(s2.pawns[0].assignedWork == .idle)
        #expect(s2.colony?.placements[0].assignedPawnIDs.isEmpty == true)
    }

    @Test("Removing a staffed building frees its colonists")
    func removeFreesPawns() {
        let reg = Fixtures.registry()
        let s0 = ColonyBuilder.place(town(pawnCount: 1), definitionID: "farm", at: TileCoord(0, 0), registry: reg)
        let s1 = ColonyBuilder.assign(s0, pawnID: s0.pawns[0].id, to: s0.colony!.placements[0].id, registry: reg)
        let s2 = ColonyBuilder.remove(s1, at: TileCoord(0, 0))
        #expect(s2.pawns[0].assignedWork == .idle)
    }

    @Test("Placement is deterministic for the same action")
    func deterministicPlacement() {
        let reg = Fixtures.registry()
        let a = ColonyBuilder.place(town(), definitionID: "farm", at: TileCoord(4, 5), registry: reg)
        let b = ColonyBuilder.place(town(), definitionID: "farm", at: TileCoord(4, 5), registry: reg)
        #expect(a.colony?.placements[0].id == b.colony?.placements[0].id)
    }

    @Test("Save round-trip preserves the colony layout")
    func colonySurvivesCoding() throws {
        let reg = Fixtures.registry()
        let s = ColonyBuilder.place(town(), definitionID: "farm", at: TileCoord(1, 2), registry: reg)
        let world = WorldState(settlements: [s])
        let data = try JSONEncoder().encode(world)
        let decoded = try JSONDecoder().decode(WorldState.self, from: data)
        #expect(decoded == world)
        #expect(decoded.settlements[0].colony?.placements.first?.coord == TileCoord(1, 2))
    }

    @Test("Seeded layout mirrors the building ledger, one tile per building")
    func seededLayout() {
        let reg = Fixtures.registry()
        let buildings = [BuildingInstance(definitionID: "farm", count: 2),
                         BuildingInstance(definitionID: "library", count: 1)]
        let map = ColonyBuilder.seededLayout(for: buildings, registry: reg)
        #expect(map.placements.count == 3)
        #expect(map.placements.filter { $0.definitionID == "farm" }.count == 2)
    }

    private func keepRegistry() -> GameDataRegistry {
        Fixtures.registry(buildings: [
            BuildingDefinition(id: "keep", era: .earlySettlement, name: "Keep",
                               footprint: TileSize(width: 2, height: 2))
        ])
    }

    @Test("A multi-tile building occupies its whole footprint")
    func multiTileFootprint() {
        let reg = keepRegistry()
        let s = ColonyBuilder.place(Settlement(name: "T", kind: .capital),
                                    definitionID: "keep", at: TileCoord(0, 0), registry: reg)
        #expect(s.colony?.placements.count == 1)
        #expect(s.colony?.placement(at: TileCoord(1, 1))?.definitionID == "keep")  // covers far corner
        #expect(s.colony?.freeTiles == 12 * 12 - 4)
    }

    @Test("A footprint can't overlap another building; demolishing any tile removes it")
    func footprintCollisionAndRemoval() {
        let reg = keepRegistry()
        var s = ColonyBuilder.place(Settlement(name: "T", kind: .capital),
                                    definitionID: "keep", at: TileCoord(0, 0), registry: reg)
        let overlap = ColonyBuilder.place(s, definitionID: "keep", at: TileCoord(1, 1), registry: reg)
        #expect(overlap.colony?.placements.count == 1)   // rejected — shares a tile

        s = ColonyBuilder.remove(s, at: TileCoord(1, 0))  // a non-origin covered tile
        #expect(s.colony?.placements.isEmpty == true)
    }

    @Test("GameEngine.placeBuilding pays the cost and lays the tile")
    func enginePlacePays() throws {
        let reg = try GameDataRegistry.bundled()
        let cap = Settlement(name: "C", kind: .capital, storage: [.materials: 100], storageCapacity: 9999)
        let world = WorldState(settlements: [cap])
        let after = GameEngine.placeBuilding(world, settlementID: cap.id,
                                             buildingID: "farm_basic", at: TileCoord(0, 0), registry: reg)
        #expect(after.settlements[0].storage[.materials] == 80)   // farm_basic costs 20 materials
        #expect(after.settlements[0].colony?.placements.count == 1)
        #expect(after.settlements[0].buildings.first { $0.definitionID == "farm_basic" }?.count == 1)
    }

    @Test("GameEngine.placeBuilding is rejected when the cost can't be paid")
    func enginePlaceUnaffordable() throws {
        let reg = try GameDataRegistry.bundled()
        let cap = Settlement(name: "C", kind: .capital, storage: [.materials: 5], storageCapacity: 9999)
        let world = WorldState(settlements: [cap])
        let after = GameEngine.placeBuilding(world, settlementID: cap.id,
                                             buildingID: "farm_basic", at: TileCoord(0, 0), registry: reg)
        #expect(after == world)
    }
}
