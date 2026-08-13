import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Colony adjacency synergies")
struct ColonyBonusTests {
    /// A registry with a farm that loves being next to a well, and a well that
    /// lifts morale next to a farm.
    private func registry() -> GameDataRegistry {
        Fixtures.registry(buildings: [
            BuildingDefinition(
                id: "farm", era: .earlySettlement, name: "Farm",
                workers: 2, production: [.food: 10],
                adjacency: [AdjacencyRule(neighbor: "well", resource: .food, bonus: 2)]
            ),
            BuildingDefinition(
                id: "well", era: .earlySettlement, name: "Well",
                adjacency: [AdjacencyRule(neighbor: "farm", morale: 1)]
            )
        ])
    }

    @Test("Adjacent complementary buildings grant production and morale")
    func adjacencyGrantsBonus() {
        let reg = registry()
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-e64efd26898d")!, name: "T", kind: .capital)
        s = ColonyBuilder.place(s, definitionID: "farm", at: TileCoord(0, 0), registry: reg)
        s = ColonyBuilder.place(s, definitionID: "well", at: TileCoord(1, 0), registry: reg)

        #expect(ColonyBonus.adjacencyProduction(s, registry: reg)[.food] == 2)
        #expect(ColonyBonus.adjacencyMorale(s, registry: reg) == 1)
    }

    @Test("No bonus when the buildings are not adjacent")
    func noBonusApart() {
        let reg = registry()
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-9d2acf13f1f8")!, name: "T", kind: .capital)
        s = ColonyBuilder.place(s, definitionID: "farm", at: TileCoord(0, 0), registry: reg)
        s = ColonyBuilder.place(s, definitionID: "well", at: TileCoord(5, 5), registry: reg)

        #expect(ColonyBonus.adjacencyProduction(s, registry: reg)[.food] == 0)
        #expect(ColonyBonus.adjacencyMorale(s, registry: reg) == 0)
    }

    @Test("Adjacency feeds the resource loop's per-tick production")
    func adjacencyFeedsTick() {
        let reg = registry()
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-44b69a27541b")!, name: "T", kind: .capital,                            storage: [.food: 0], storageCapacity: .uniform(9999))
        s = ColonyBuilder.place(s, definitionID: "farm", at: TileCoord(0, 0), registry: reg)
        s = ColonyBuilder.place(s, definitionID: "well", at: TileCoord(1, 0), registry: reg)

        var world = WorldState(settlements: [s])
        world = TickEngine.advance(world, ticks: 1, registry: reg).state
        // Farm base food 10 + adjacency 2, no population upkeep, no events.
        // The colony has no colonists, so the farm runs at `unstaffedFloor` —
        // production now depends on who is actually at the bench. Adjacency is
        // a flat bonus on top and is *not* scaled, which is the thing this test
        // is really about: the +2 survives an empty farm.
        let expected = 10 * ResourceLoop.unstaffedFloor + 2
        #expect(world.settlements[0].storage[.food] == expected)
    }

    @Test("A settlement with no colony grid gets no synergies")
    func noColonyNoBonus() {
        let reg = registry()
        let s = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-3ccd428880cc")!, name: "T", kind: .capital,
                           buildings: [BuildingInstance(definitionID: "farm", count: 1)])
        #expect(ColonyBonus.adjacencyProduction(s, registry: reg)[.food] == 0)
    }

    @Test("Painted zones add morale, and it flows through the morale bonus")
    func zoneMorale() {
        let reg = registry()
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-3137a579224a")!, name: "T", kind: .capital)
        s = ColonyBuilder.paintZone(s, at: TileCoord(2, 2), kind: .park)
        s = ColonyBuilder.paintZone(s, at: TileCoord(3, 2), kind: .park)
        // park = 0.6 morale per tile × 2 tiles.
        #expect(abs(ColonyBonus.zoneMorale(s) - 1.2) < 1e-9)
        #expect(ColonyBonus.adjacencyMorale(s, registry: reg) >= 1.2)
    }

    @Test("Repainting replaces a tile's zone; erasing clears it")
    func zonePaintErase() {
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-1c700058615a")!, name: "T", kind: .capital)
        s = ColonyBuilder.paintZone(s, at: TileCoord(1, 1), kind: .park)
        #expect(s.colony?.zoneKind(at: TileCoord(1, 1)) == .park)

        s = ColonyBuilder.paintZone(s, at: TileCoord(1, 1), kind: .plaza)
        #expect(s.colony?.zones.count == 1)   // replaced, not duplicated
        #expect(s.colony?.zoneKind(at: TileCoord(1, 1)) == .plaza)

        s = ColonyBuilder.eraseZone(s, at: TileCoord(1, 1))
        #expect(s.colony?.zones.isEmpty == true)
    }

    @Test("Zone morale is capped so a colony can't be all parks")
    func zoneMoraleCapped() {
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-c9bcf9e2ac87")!, name: "T", kind: .capital)
        for x in 0..<12 { for y in 0..<10 {
            s = ColonyBuilder.paintZone(s, at: TileCoord(x, y), kind: .park)
        } }
        #expect(ColonyBonus.zoneMorale(s) == ColonyBonus.maxZoneMorale)
    }
}
