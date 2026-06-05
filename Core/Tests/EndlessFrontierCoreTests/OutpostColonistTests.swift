import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Outpost colonists")
struct OutpostColonistTests {
    private func worldWithFrontier() -> (WorldState, GameDataRegistry, UUID) {
        let reg = Fixtures.registry()
        let region = Region(name: "Frontier", coord: HexCoord(1, 0), kind: .wilderness,
                            biomeID: "plains", explorationState: .fullyExplored)
        let capital = Settlement(name: "Capital", kind: .capital, population: 50,
                                 storage: [.materials: 200, .influence: 200], storageCapacity: 500)
        let world = WorldState(mapSeed: 1, settlements: [capital], regions: [region])
        return (world, reg, region.id)
    }

    @Test("A founded outpost arrives with real colonists")
    func outpostHasColonists() {
        let (world, reg, regionID) = worldWithFrontier()
        let after = ExpansionEngine.foundOutpost(world, regionID: regionID, name: "Reach", registry: reg)
        let outpost = after.settlements.last
        #expect(outpost?.kind == .outpost)
        #expect((outpost?.pawns.count ?? 0) >= 2)
        #expect(outpost?.pawns.allSatisfy { !$0.name.isEmpty } == true)
    }

    @Test("Outpost colonists are generated deterministically")
    func deterministic() {
        let (world, reg, regionID) = worldWithFrontier()
        let a = ExpansionEngine.foundOutpost(world, regionID: regionID, name: "Reach", registry: reg)
        let b = ExpansionEngine.foundOutpost(world, regionID: regionID, name: "Reach", registry: reg)
        #expect(a.settlements.last?.pawns == b.settlements.last?.pawns)
    }

    @Test("Outpost colonists live and work over ticks (the settlement is alive)")
    func outpostSimulates() throws {
        let reg = try GameDataRegistry.bundled()
        var (world, _, regionID) = worldWithFrontier()
        world = ExpansionEngine.foundOutpost(world, regionID: regionID, name: "Reach", registry: reg)
        let outpostID = world.settlements.last!.id
        // Give the outpost a farm so its colonists can produce.
        let idx = world.settlements.firstIndex { $0.id == outpostID }!
        world.settlements[idx].pawns = world.settlements[idx].pawns.map {
            var p = $0; p.skills[.farming] = 6; p.assignedWork = .farming; return p
        }
        world.settlements[idx].storage[.food] = 100
        let before = world.settlements[idx].storage[.food]
        world = TickEngine.advance(world, ticks: 5, registry: reg).state
        let after = world.settlements.first { $0.id == outpostID }!
        // Colonists ate and worked — needs changed from the default.
        #expect(after.pawns.first?.needs.hunger != 80)
    }
}
