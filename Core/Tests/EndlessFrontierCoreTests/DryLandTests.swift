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
                biome: coast, registry: registry)
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

    @Test("A beast will not walk into deep water")
    func theWildKeepsItsFeet() throws {
        let registry = try GameDataRegistry.bundled()
        let map = Self.coastMaps(1, registry: registry)[0]
        let deep = try #require(AnimalEngine.deepWater(on: map),
                                "a coast map with no deep water in it")
        let shore = try #require(map.shore)

        // A beast standing on the beach, told to walk straight out to sea.
        let landing: LocalPoint
        switch shore.side {
        case .north: landing = LocalPoint(x: 0.5, y: 0.02)
        case .south: landing = LocalPoint(x: 0.5, y: 0.98)
        case .west:  landing = LocalPoint(x: 0.02, y: 0.5)
        case .east:  landing = LocalPoint(x: 0.98, y: 0.5)
        }
        // Somewhere dry to set off from: walk in from the middle.
        let from = LocalPoint(x: 0.5, y: 0.5)
        #expect(!deep(from), "the middle of the map is out of its depth")
        let to = AnimalEngine.step(from: from, toward: landing, by: 0.9, deep: deep)
        #expect(!deep(to), "a beast walked into the deep")
    }

    @Test("A beast already out of its depth is not frozen there")
    func theStrandedCanStillMove() throws {
        let registry = try GameDataRegistry.bundled()
        let map = Self.coastMaps(1, registry: registry)[0]
        let deep = try #require(AnimalEngine.deepWater(on: map))
        let shore = try #require(map.shore)
        // A save written before the wild knew about water can have a beast in
        // it. Refusing to move it would leave it there for ever.
        let stuck: LocalPoint
        switch shore.side {
        case .north: stuck = LocalPoint(x: 0.5, y: 0.01)
        case .south: stuck = LocalPoint(x: 0.5, y: 0.99)
        case .west:  stuck = LocalPoint(x: 0.01, y: 0.5)
        case .east:  stuck = LocalPoint(x: 0.99, y: 0.5)
        }
        guard deep(stuck) else { return }
        let out = AnimalEngine.step(from: stuck, toward: LocalPoint(x: 0.5, y: 0.5),
                                    by: 0.1, deep: deep)
        #expect(out != stuck, "a stranded beast cannot move at all")
    }

    @Test("A colony does not build in the sea")
    func nothingIsBuiltInTheSea() throws {
        let registry = try GameDataRegistry.bundled()
        var settlement = Settlement(
            id: UUID(uuidString: "00000000-0000-0000-DBBB-f7695d4586ee")!,
            name: "Strand", kind: .capital)
        // A shore that reaches **into the built ground**. A generated coast
        // usually keeps its water outside the build grid, so a test taking one
        // at random measures nothing — the case worth refusing is the colony
        // whose grid genuinely touches the sea.
        var map = Self.coastMaps(1, registry: registry)[0]
        map.shore = ShoreShape(side: .north, depth: 0.35, amplitude: 0.04, phase: 0)
        settlement.localMap = map
        settlement = ColonyBuilder.ensureMap(settlement)
        let wet = ColonyBuilder.drowned(in: settlement)
        #expect(!wet.isEmpty, "a coast colony whose grid touches no water")

        // Raise a run of buildings the way the colony does when nobody steers.
        for _ in 0..<24 {
            settlement = ColonyBuilder.placeSiteAtFirstFit(
                settlement, definitionID: "hut", registry: registry).settlement
        }
        let placed = settlement.colony?.placements ?? []
        #expect(!placed.isEmpty, "nothing was built at all")
        for placement in placed {
            for tile in placement.footprint {
                #expect(!wet.contains(tile),
                        "\(placement.definitionID) stands in the sea at \(tile)")
            }
        }
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
