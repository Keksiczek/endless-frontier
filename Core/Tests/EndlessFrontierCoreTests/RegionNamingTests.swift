import Testing
import Foundation
@testable import EndlessFrontierCore

/// Reported from a real game: "all the Duskwaters got explored but Send
/// Expedition is still there and that's all."
///
/// There was more than one Duskwater. Names came from a list of 25 taken
/// modulo the coordinate — on a map that is *deliberately endless* and grows
/// every time you reveal a hex, so the same two dozen names repeat forever.
/// A player charts the Duskwater in front of them, sees three more Duskwaters
/// still offering an expedition, and concludes exploring did nothing. The map
/// was lying about which place was which.
@Suite("Every place has its own name")
struct RegionNamingTests {
    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    /// The map grows without bound, so names must too — 25 of them cannot
    /// cover it.
    @Test("A wide sweep of the map has no two places sharing a name")
    func namesAreUniqueAcrossTheMap() throws {
        let reg = try registry()
        var names: [String: HexCoord] = [:]
        var clashes: [(String, HexCoord, HexCoord)] = []

        for q in -12...12 {
            for r in -12...12 {
                let coord = HexCoord(q, r)
                guard coord.distance(to: .origin) <= 12 else { continue }
                let region = MapGenerator.region(at: coord, mapSeed: 1_592_651_789, registry: reg)
                if let seen = names[region.name], seen != coord {
                    clashes.append((region.name, seen, coord))
                }
                names[region.name] = coord
            }
        }
        #expect(clashes.isEmpty,
                "two places must never share a name — the player can't tell them apart. Clashes: \(clashes.prefix(5))")
    }

    @Test("Naming is deterministic and stays with the coordinate")
    func namingIsStable() throws {
        let reg = try registry()
        let a = MapGenerator.region(at: HexCoord(3, -2), mapSeed: 99, registry: reg)
        let b = MapGenerator.region(at: HexCoord(3, -2), mapSeed: 99, registry: reg)
        #expect(a.name == b.name)
    }

    @Test("A different world names its places differently")
    func namesVaryByWorld() throws {
        let reg = try registry()
        let a = MapGenerator.region(at: HexCoord(3, -2), mapSeed: 1, registry: reg)
        let b = MapGenerator.region(at: HexCoord(3, -2), mapSeed: 2, registry: reg)
        #expect(a.name != b.name, "two worlds shouldn't be the same map with different numbers")
    }

    @Test("The homeland keeps its name")
    func homelandIsHomeland() throws {
        let reg = try registry()
        #expect(MapGenerator.region(at: .origin, mapSeed: 42, registry: reg).name == "Homeland")
    }

    @Test("Names read as places, not as coordinates")
    func namesAreReadable() throws {
        let reg = try registry()
        for q in -4...4 {
            let region = MapGenerator.region(at: HexCoord(q, 2), mapSeed: 7, registry: reg)
            #expect(!region.name.isEmpty)
            #expect(!region.name.contains(","), "\(region.name) reads as a grid reference, not a place")
            #expect(region.name.first!.isUppercase)
        }
    }
}
