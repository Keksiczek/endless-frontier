import Testing
import Foundation
@testable import EndlessFrontierCore

/// **Expeditions walked over the river.**
///
/// Building asks `ColonyBuilder.drowned(in:)` and the wild asks
/// `AnimalEngine.step(deep:)`. The one journey that crosses the whole valley —
/// a party walking out to the ruins and back — asked nothing: it was a straight
/// bowed line from the gate to the place, and the canvas drew people walking
/// across open water on it. Listed open since the water went in.
@Suite("A party that keeps its feet")
struct DryWayTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }
    private static let seat = UUID(uuidString: "D2FA0000-0000-0000-0000-000000000001")!

    /// A valley with a river straight across the middle of it.
    private func riverTown() -> Settlement {
        // Below the gate, so the heart stands on dry ground and the water lies
        // between the town and the far side of the valley.
        var map = LocalMap(river: RiverShape(baseY: 0.7, amplitude: 0, phase: 0, flows: true),
                           nodes: [], pois: [])
        map.trees = []
        map.rocks = []
        map.scenery = []
        var town = Settlement(id: Self.seat, name: "Ford", storage: [.food: 100],
                              storageCapacity: .uniform(500))
        town.localMap = map
        return town
    }

    @Test("A dry walk needs no detour")
    func openGroundIsWalkedStraight() {
        let town = riverTown()
        // Both ends on the same bank.
        let way = PathEngine.dryWay(from: LocalPoint(x: 0.30, y: 0.20),
                                    to: LocalPoint(x: 0.70, y: 0.20), in: town)
        #expect(way == nil)
    }

    @Test("A walk that would cross deep water bends through a ford")
    func deepWaterIsCrossedSomewhereElse() throws {
        let town = riverTown()
        let from = LocalPoint(x: 0.5, y: 0.35)
        let to = LocalPoint(x: 0.5, y: 0.95)
        let depth = try #require(PathEngine.waterDepth(town))
        #expect(PathEngine.drowns(from: from, to: to, depth: depth),
                "the fixture's river is not in the way — nothing to test")
        let via = try #require(PathEngine.dryWay(from: from, to: to, in: town),
                               "a river with fords in it left a party no way across")
        #expect(!PathEngine.drowns(from: from, to: via, depth: depth))
        #expect(!PathEngine.drowns(from: via, to: to, depth: depth))
    }

    @Test("A valley with no water in it never detours")
    func dryValleysCostNothing() {
        var town = riverTown()
        town.localMap?.river = RiverShape(baseY: 0.5, amplitude: 0, phase: 0, flows: false)
        #expect(PathEngine.dryWay(from: LocalPoint(x: 0.5, y: 0.35),
                                  to: LocalPoint(x: 0.5, y: 0.95), in: town) == nil)
    }

    @Test("The detour is paid for in walking time")
    func goingRoundCostsTime() {
        let straight = LocalPOIEngine.travelTicks(to: LocalPoint(x: 0.5, y: 0.9))
        let round = LocalPOIEngine.travelTicks(to: LocalPoint(x: 0.5, y: 0.9),
                                               via: LocalPoint(x: 0.15, y: 0.5))
        #expect(round > straight, "the water was free")
    }

    @Test("A party dispatched across water carries the way it walked")
    func theExpeditionRemembersItsFord() throws {
        let reg = try registry()
        var town = riverTown()
        town.localMap?.pois = [LocalPOI(id: 1, kind: .ruins,
                                        position: LocalPoint(x: 0.5, y: 0.95),
                                        discovered: true)]
        town.pawns = (0..<6).map { i in
            Pawn(id: UUID(uuidString: String(format: "D2FA0000-0000-0000-0000-%012d", i + 10))!,
                 name: "Hand \(i)", assignedWork: .scouting)
        }
        let world = WorldState(tick: 40, mapSeed: 5, settlements: [town])
        let after = try #require(
            LocalPOIEngine.dispatch(world, settlementID: Self.seat, poiID: 1, registry: reg),
            "nobody was sent")
        let party = try #require(after.settlements[0].expeditions.first)
        let via = try #require(party.via, "the party set off straight across the river")
        let depth = try #require(PathEngine.waterDepth(town))
        #expect(!PathEngine.drowns(from: LocalPOIEngine.heart, to: via, depth: depth))
        #expect(!PathEngine.drowns(from: via, to: LocalPoint(x: 0.5, y: 0.95), depth: depth))
    }

    @Test("The way survives a save")
    func theFordRoundTrips() throws {
        let party = POIExpedition(id: UUID(), poiID: 3, memberIDs: [], departedTick: 2,
                                  travelTicks: 6, workTicks: 4,
                                  via: LocalPoint(x: 0.22, y: 0.48))
        let back = try JSONDecoder().decode(
            POIExpedition.self, from: JSONEncoder().encode(party))
        #expect(back.via == LocalPoint(x: 0.22, y: 0.48))
        // …and a party saved before there were fords simply walked straight.
        let old = POIExpedition(id: UUID(), poiID: 3, memberIDs: [], departedTick: 2,
                                travelTicks: 6, workTicks: 4)
        #expect(old.via == nil)
    }
}
