import Foundation
import Testing
@testable import EndlessFrontierCore

/// Finding a point of interest pays out once and makes the journal — reveal
/// used to flip the flag silently and the promised reward never existed.
@Suite("POI discovery")
struct POIDiscoveryTests {
    private let registry = Fixtures.registry()

    @Test("New maps seed all six kinds of point of interest")
    func generatorSeedsAllKinds() {
        let map = LocalMapGenerator.generate(mapSeed: 42, regionID: UUID(
            uuidString: "CCCCCCCC-0000-0000-0000-000000000001")!, biome: nil)
        #expect(Set(map.pois.map(\.kind)) == Set(LocalPOIKind.allCases))
    }

    @Test("Each kind grants its reward and writes the journal", arguments: LocalPOIKind.allCases)
    func rewards(kind: LocalPOIKind) {
        var s = Settlement(id: UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000002")!,
                           name: "T", kind: .capital, pawns: Fixtures.pawns(4),
                           storage: [:], storageCapacity: 500)
        for i in s.pawns.indices {
            s.pawns[i].health = 50
            s.pawns[i].needs.recreation = 50
        }
        let before = s
        let poi = LocalPOI(id: 9, kind: kind, position: LocalPoint(x: 0.2, y: 0.2), discovered: true)
        let after = ResourceLoop.grantPOIDiscovery(s, poi: poi, tick: 30)

        #expect(after.journal.entries.contains { $0.kind == .discovery })
        switch kind {
        case .ruins:
            #expect(after.storage[.knowledge] > before.storage[.knowledge])
        case .cave, .wreck:
            #expect(after.storage[.materials] > before.storage[.materials])
        case .treasure:
            #expect(after.storage[.materials] > before.storage[.materials])
            #expect(after.storage[.influence] > before.storage[.influence])
        case .spring:
            #expect(after.pawns[0].health > before.pawns[0].health)
        case .shrine:
            #expect(after.pawns[0].needs.recreation > before.pawns[0].needs.recreation)
        }
    }

    @Test("Scouts who walk into a POI trigger the find exactly once")
    func scoutingDiscovers() {
        var map = LocalMapGenerator.generate(mapSeed: 7, regionID: UUID(
            uuidString: "CCCCCCCC-0000-0000-0000-000000000003")!, biome: nil)
        // Nothing found yet at the start of the test.
        for i in map.pois.indices { map.pois[i].discovered = false }
        var s = Settlement(id: UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000004")!,
                           name: "T", kind: .capital,
                           pawns: Fixtures.pawns(6, work: .scouting),
                           storage: [:], storageCapacity: 500)
        s.localMap = map

        // Enough scouted years for the walkers to cross the whole valley.
        for tick in 0..<1200 {
            s = ResourceLoop.chartGround(s, tick: tick, mapSeed: 7, config: registry.config)
        }
        let found = s.localMap?.pois.filter(\.discovered).count ?? 0
        #expect(found > 0)
        let discoveryLines = s.journal.entries.filter { $0.kind == .discovery }.count
        #expect(discoveryLines == found)   // one line per find, never repeated
    }
}
