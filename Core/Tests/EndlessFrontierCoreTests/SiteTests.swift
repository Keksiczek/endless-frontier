import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Special sites")
struct SiteTests {
    private func world(kind: RegionKind, hazard: Int = 4, pawns: [Pawn] = []) -> (WorldState, UUID) {
        let region = Region(name: "Site", coord: HexCoord(2, 0), kind: kind, biomeID: "plains",
                            hazardLevel: hazard, explorationState: .fullyExplored)
        let capital = Settlement(name: "Capital", kind: .capital, population: Double(max(pawns.count, 1)),
                                 pawns: pawns, storage: [:], storageCapacity: 9999)
        let state = WorldState(mapSeed: 1, settlements: [capital], regions: [region])
        return (state, region.id)
    }

    @Test("Excavating ruins grants knowledge and influence, then clears the site")
    func ruins() {
        let (state, id) = world(kind: .ruins, hazard: 5)
        let result = SiteEngine.interact(state, regionID: id, registry: Fixtures.registry())
        let (after, outcome) = try! #require(result)
        #expect(outcome.kind == .ruins)
        #expect(after.settlements[0].storage[.knowledge] > 0)
        #expect(after.settlements[0].storage[.influence] > 0)
        #expect(after.regions[0].siteCleared)
    }

    @Test("A cleared site cannot be interacted with again")
    func clearedSiteInert() {
        let (state, id) = world(kind: .ruins)
        let (after, _) = SiteEngine.interact(state, regionID: id, registry: Fixtures.registry())!
        #expect(SiteEngine.interact(after, regionID: id, registry: Fixtures.registry()) == nil)
    }

    @Test("Delving a dungeon yields materials and can wound a colonist")
    func dungeon() {
        let (state, id) = world(kind: .dungeon, hazard: 9,
                                pawns: [Pawn(name: "Scout", health: 100)])
        let (after, outcome) = SiteEngine.interact(state, regionID: id, registry: Fixtures.registry())!
        #expect(after.settlements[0].storage[.materials] > 0)
        #expect(outcome.rewards[.materials] > 0)
        // High hazard → injury very likely; the colonist took damage or died.
        let hurt = (after.settlements[0].pawns.first?.health ?? 100) < 100
        #expect(hurt || outcome.died)
    }

    @Test("Probing an anomaly grants knowledge but raises threat")
    func anomaly() {
        let (state, id) = world(kind: .anomaly, hazard: 6)
        let before = state.globalStats.threatLevel
        let (after, outcome) = SiteEngine.interact(state, regionID: id, registry: Fixtures.registry())!
        #expect(after.settlements[0].storage[.knowledge] > 0)
        #expect(after.globalStats.threatLevel > before)
        #expect(outcome.threatGain > 0)
    }

    @Test("Wilderness and unexplored regions have no site to interact with")
    func noSite() {
        let reg = Fixtures.registry()
        let (plain, plainID) = world(kind: .wilderness)
        #expect(SiteEngine.interact(plain, regionID: plainID, registry: reg) == nil)

        var unexplored = world(kind: .ruins).0
        unexplored.regions[0].explorationState = .unknown
        #expect(SiteEngine.interact(unexplored, regionID: unexplored.regions[0].id, registry: reg) == nil)
    }

    @Test("Loot scales with hazard (distance)")
    func lootScales() {
        let reg = Fixtures.registry()
        let (near, nearID) = world(kind: .ruins, hazard: 1)
        let (far, farID) = world(kind: .ruins, hazard: 10)
        let nearLoot = SiteEngine.interact(near, regionID: nearID, registry: reg)!.1.rewards[.knowledge]
        let farLoot = SiteEngine.interact(far, regionID: farID, registry: reg)!.1.rewards[.knowledge]
        #expect(farLoot > nearLoot)
    }

    @Test("Site interaction is deterministic")
    func deterministic() {
        let (state, id) = world(kind: .dungeon, hazard: 8, pawns: [Pawn(name: "A", health: 100)])
        let a = SiteEngine.interact(state, regionID: id, registry: Fixtures.registry())!.0
        let b = SiteEngine.interact(state, regionID: id, registry: Fixtures.registry())!.0
        #expect(a == b)
    }
}
