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
        var s = Settlement(name: "T", kind: .capital)
        s = ColonyBuilder.place(s, definitionID: "farm", at: TileCoord(0, 0), registry: reg)
        s = ColonyBuilder.place(s, definitionID: "well", at: TileCoord(1, 0), registry: reg)

        #expect(ColonyBonus.adjacencyProduction(s, registry: reg)[.food] == 2)
        #expect(ColonyBonus.adjacencyMorale(s, registry: reg) == 1)
    }

    @Test("No bonus when the buildings are not adjacent")
    func noBonusApart() {
        let reg = registry()
        var s = Settlement(name: "T", kind: .capital)
        s = ColonyBuilder.place(s, definitionID: "farm", at: TileCoord(0, 0), registry: reg)
        s = ColonyBuilder.place(s, definitionID: "well", at: TileCoord(5, 5), registry: reg)

        #expect(ColonyBonus.adjacencyProduction(s, registry: reg)[.food] == 0)
        #expect(ColonyBonus.adjacencyMorale(s, registry: reg) == 0)
    }

    @Test("Adjacency feeds the resource loop's per-tick production")
    func adjacencyFeedsTick() {
        let reg = registry()
        var s = Settlement(name: "T", kind: .capital, population: 0,
                           storage: [.food: 0], storageCapacity: 9999)
        s = ColonyBuilder.place(s, definitionID: "farm", at: TileCoord(0, 0), registry: reg)
        s = ColonyBuilder.place(s, definitionID: "well", at: TileCoord(1, 0), registry: reg)

        var world = WorldState(settlements: [s])
        world = TickEngine.advance(world, ticks: 1, registry: reg).state
        // farm base food 10 + adjacency 2, no population upkeep, no events.
        #expect(world.settlements[0].storage[.food] == 12)
    }

    @Test("A settlement with no colony grid gets no synergies")
    func noColonyNoBonus() {
        let reg = registry()
        let s = Settlement(name: "T", kind: .capital,
                           buildings: [BuildingInstance(definitionID: "farm", count: 1)])
        #expect(ColonyBonus.adjacencyProduction(s, registry: reg)[.food] == 0)
    }

    @Test("Painted zones add morale, and it flows through the morale bonus")
    func zoneMorale() {
        let reg = registry()
        var s = Settlement(name: "T", kind: .capital)
        s = ColonyBuilder.paintZone(s, at: TileCoord(2, 2), kind: .park)
        s = ColonyBuilder.paintZone(s, at: TileCoord(3, 2), kind: .park)
        // park = 0.6 morale per tile × 2 tiles.
        #expect(abs(ColonyBonus.zoneMorale(s) - 1.2) < 1e-9)
        #expect(ColonyBonus.adjacencyMorale(s, registry: reg) >= 1.2)
    }

    @Test("Repainting replaces a tile's zone; erasing clears it")
    func zonePaintErase() {
        var s = Settlement(name: "T", kind: .capital)
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
        var s = Settlement(name: "T", kind: .capital)
        for x in 0..<12 { for y in 0..<10 {
            s = ColonyBuilder.paintZone(s, at: TileCoord(x, y), kind: .park)
        } }
        #expect(ColonyBonus.zoneMorale(s) == ColonyBonus.maxZoneMorale)
    }
}
