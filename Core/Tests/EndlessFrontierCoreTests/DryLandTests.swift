import Testing
import Foundation
@testable import EndlessFrontierCore

/// **Nothing stands in the sea, and nobody walks into it.**
///
/// Keks, on a coast colony: *"ať se věci negenerují a moc nechodí na moře —
/// teď tam jsou POI, řeky, vše tam normálně chodí."*
///
/// The generator has had `landPoint` since the shore existed and it does check
/// the water. `riversidePoint` — where reeds, ponds and half the landmarks go —
/// **never did**: it takes the river's bank at a random `x`, and on a coast map
/// the river runs *into* the sea, so its bank near the outflow is open water.
/// One of the two pickers was right and the other was never asked to be.
///
/// Swept across many seeds rather than one, because a fault that needs the
/// river's mouth and the shore's wobble to line up shows in one map in five.
@Suite("Nothing stands in the sea")
struct DryLandTests {

    /// Coast regions, so there is a sea to stand in at all.
    static func coastMaps(_ count: Int, registry: GameDataRegistry) -> [LocalMap] {
        let coast = registry.biome("coast")
        return (0..<count).map { i in
            LocalMapGenerator.generate(
                mapSeed: 4242,
                regionID: UUID(uuidString: String(format: "00000000-0000-0000-C0A5-%012d", i))!,
                biome: coast)
        }
    }

    @Test("No landmark is out at sea")
    func poisAreOnLand() throws {
        let registry = try GameDataRegistry.bundled()
        var wet: [(map: Int, poi: String, at: LocalPoint)] = []
        for (index, map) in Self.coastMaps(40, registry: registry).enumerated() {
            guard let shore = map.shore else { continue }
            for poi in map.pois where shore.isWater(poi.position) {
                wet.append((index, poi.kind.rawValue, poi.position))
            }
        }
        #expect(wet.isEmpty, "landmarks in the water: \(wet.prefix(6))")
    }

    @Test("The water has a shallow edge and a deep middle")
    func waterHasDepth() throws {
        let registry = try GameDataRegistry.bundled()
        var settlement = Settlement(
            id: UUID(uuidString: "00000000-0000-0000-DEEB-f7695d4586ee")!,
            name: "Strand", kind: .capital)
        settlement.localMap = Self.coastMaps(1, registry: registry)[0]
        let depth = try #require(PathEngine.waterDepth(settlement),
                                 "a coast map with no water in it")
        guard let shore = settlement.localMap?.shore else { return }

        var seen: Set<String> = []
        for i in 0...400 {
            let t = Double(i) / 400
            // A line straight out to sea from the middle of the shore's side.
            let p: LocalPoint
            switch shore.side {
            case .north: p = LocalPoint(x: 0.5, y: t)
            case .south: p = LocalPoint(x: 0.5, y: 1 - t)
            case .west:  p = LocalPoint(x: t, y: 0.5)
            case .east:  p = LocalPoint(x: 1 - t, y: 0.5)
            }
            switch depth(p) {
            case .dry: seen.insert("dry")
            case .shallow: seen.insert("shallow")
            case .deep: seen.insert("deep")
            }
        }
        #expect(seen == ["dry", "shallow", "deep"],
                "walking out to sea only ever met \(seen.sorted())")
    }

    @Test("A dry valley is not asked about water at all")
    func dryValleysCostNothing() {
        var settlement = Settlement(
            id: UUID(uuidString: "00000000-0000-0000-D2AA-f7695d4586ee")!,
            name: "Inland", kind: .capital)
        // A wash that does not flow is a line on the ground, not a channel.
        settlement.localMap = LocalMap(
            river: RiverShape(baseY: 0.82, amplitude: 0.05, phase: 0, flows: false),
            nodes: [], pois: [],
            wildlife: WildlifeState(deerHerd: 0, deerCapacity: 0),
            terrainSeed: 7, trees: [], rocks: [])
        #expect(PathEngine.waterDepth(settlement) == nil,
                "a dry valley pays for a test it can never fail")
    }

    @Test("Nothing grows or outcrops in the water")
    func thingsAreOnLand() throws {
        let registry = try GameDataRegistry.bundled()
        var wet = 0
        var counted = 0
        for map in Self.coastMaps(40, registry: registry) {
            guard let shore = map.shore else { continue }
            for tree in map.trees { counted += 1; if shore.isWater(tree.position) { wet += 1 } }
            for rock in map.rocks { counted += 1; if shore.isWater(rock.position) { wet += 1 } }
            for node in map.nodes { counted += 1; if shore.isWater(node.position) { wet += 1 } }
        }
        #expect(counted > 0, "no coast map generated anything to check")
        #expect(wet == 0, "\(wet) of \(counted) things stand in the sea")
    }
}
