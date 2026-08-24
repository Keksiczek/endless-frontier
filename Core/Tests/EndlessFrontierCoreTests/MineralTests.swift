import Testing
import Foundation
@testable import EndlessFrontierCore

/// **The rock had no way back, and a valley is not only trees.**
///
/// Measured on a real save 113 years in: nine outcrops, every one broken to
/// nothing; the stone, iron and clay deposits reading 0 of 223, 182 and 135;
/// and no massif under a plains valley to fall back on. So no stone, no clay
/// and no ore, for ever — and with them no brick, no iron, and nothing at all
/// downstream of either.
@Suite("The ground opens again")
struct MineralTests {

    static func valley(
        _ kinds: [LocalResourceKind], capacity: Double = 200, spent: Bool = true
    ) -> LocalMap {
        var nodes: [ResourceNode] = []
        var rocks: [Rock] = []
        for (i, kind) in kinds.enumerated() {
            let at = LocalPoint(x: 0.2 + Double(i) * 0.25, y: 0.5)
            nodes.append(ResourceNode(id: i, kind: kind, position: at,
                                           amount: spent ? 0 : capacity, capacity: capacity))
            rocks.append(Rock(id: i, kind: FloraFactory.rockKinds(for: kind)[0],
                              position: at, amount: spent ? 0 : capacity,
                              capacity: capacity))
        }
        var m = LocalMap(river: RiverShape(baseY: 0.9, amplitude: 0, phase: 0),
                         nodes: nodes, pois: [],
                         wildlife: WildlifeState(deerHerd: 0, deerCapacity: 0),
                         terrainSeed: 7, trees: [], rocks: rocks)
        m.usesEntityLand = true
        return m
    }

    static func passes(_ map: LocalMap, biome: BiomeDefinition?, count: Int) -> LocalMap {
        var m = map
        for i in 0..<count {
            m = MineralEngine.surfaced(m, biome: biome, mapSeed: 4242,
                                        tick: i * MineralEngine.interval)
        }
        return m
    }

    @Test("A worked-out valley gives up new rock")
    func theGroundOpens() throws {
        let registry = try GameDataRegistry.bundled()
        let m = Self.passes(Self.valley([.stone]), biome: registry.biome("plains"), count: 40)
        let live = m.rocks.filter { !$0.isSpent }
        #expect(!live.isEmpty, "nothing surfaced in forty passes")
        #expect(m.nodes[0].amount > 0, "the deposit still reads empty")
    }

    /// The fault the strict minimum had: three deposits at zero are tied, and
    /// the tie went to the lowest array index every pass, so the clay in Keks's
    /// valley stood at three units — one short of a brick — for forty years
    /// while the stone tripled.
    @Test("Every worked-out deposit gets a turn, not just the first")
    func nobodyIsStarved() throws {
        let registry = try GameDataRegistry.bundled()
        let m = Self.passes(Self.valley([.stone, .ironOre, .clay]),
                            biome: registry.biome("plains"), count: 120)
        for node in m.nodes {
            let opened = m.rocks.filter { $0.kind.deposit == node.kind }.count
            #expect(opened > 1, "\(node.kind.rawValue) never opened again (\(opened) outcrops)")
        }
    }

    @Test("A deposit does not open past its own working face")
    func theFaceIsBounded() throws {
        let registry = try GameDataRegistry.bundled()
        // Nothing is being worked, so every outcrop that opens stays live.
        let m = Self.passes(Self.valley([.stone], spent: false),
                            biome: registry.biome("mountains"), count: 200)
        let live = m.rocks.filter { !$0.isSpent }.count
        #expect(live <= MineralEngine.mostOutcropsPerNode + 1,
                "\(live) faces open on one deposit")
    }

    @Test("Lean country opens slower than rich country")
    func theBiomeDecides() throws {
        let registry = try GameDataRegistry.bundled()
        let lean = Self.passes(Self.valley([.stone]), biome: registry.biome("plains"), count: 60)
        let rich = Self.passes(Self.valley([.stone]), biome: registry.biome("mountains"), count: 60)
        #expect(rich.rocks.count >= lean.rocks.count,
                "a mountain valley opened no faster than the plains")
    }

    @Test("A valley with nothing under it stays that way")
    func noSeamNoRock() throws {
        let registry = try GameDataRegistry.bundled()
        // Fields and herbs are not broken out of anything.
        let m = Self.passes(Self.valley([.field, .herbs]),
                            biome: registry.biome("plains"), count: 60)
        #expect(m.rocks.count == 2, "rock surfaced where there is no seam")
    }
}
