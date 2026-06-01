import Testing
@testable import EndlessFrontierCore

@Suite("Hex coordinates")
struct HexCoordTests {
    @Test("Disc size grows by ring (1, 7, 19, 37)")
    func discSizes() {
        #expect(HexCoord.disc(radius: 0).count == 1)
        #expect(HexCoord.disc(radius: 1).count == 7)
        #expect(HexCoord.disc(radius: 2).count == 19)
        #expect(HexCoord.disc(radius: 3).count == 37)
    }

    @Test("Every hex has six distinct neighbours")
    func neighbours() {
        let n = HexCoord.origin.neighbors()
        #expect(n.count == 6)
        #expect(Set(n).count == 6)
    }

    @Test("Distance is symmetric and correct")
    func distance() {
        #expect(HexCoord.origin.distance(to: HexCoord(0, 0)) == 0)
        #expect(HexCoord.origin.distance(to: HexCoord(2, 0)) == 2)
        #expect(HexCoord(1, -1).distance(to: HexCoord(-1, 1)) == 2)
    }
}

@Suite("Map generation")
struct MapGenerationTests {
    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    @Test("Map covers the configured radius with a homeland at the origin")
    func layout() throws {
        let reg = try registry()
        let regions = MapGenerator.generate(seed: 1, registry: reg)
        #expect(regions.count == HexCoord.disc(radius: reg.mapGen.mapRadius).count)
        let homeland = regions.first { $0.coord == .origin }
        #expect(homeland?.kind == .homeland)
        #expect(homeland?.explorationState == .fullyExplored)
        #expect(regions.filter { $0.kind == .homeland }.count == 1)
    }

    @Test("Generation is deterministic for the same seed")
    func deterministic() throws {
        let reg = try registry()
        let a = MapGenerator.generate(seed: 42, registry: reg)
        let b = MapGenerator.generate(seed: 42, registry: reg)
        #expect(a == b)
    }

    @Test("Different seeds produce different maps")
    func variety() throws {
        let reg = try registry()
        let a = MapGenerator.generate(seed: 1, registry: reg)
        let b = MapGenerator.generate(seed: 2, registry: reg)
        // At least one non-homeland hex differs in biome or kind.
        let differs = zip(a, b).contains { lhs, rhs in
            lhs.coord != .origin && (lhs.biomeID != rhs.biomeID || lhs.kind != rhs.kind)
        }
        #expect(differs)
    }

    @Test("Special sites (ruins/dungeon/anomaly) can appear across many seeds")
    func specialSites() throws {
        let reg = try registry()
        var sawSpecial = false
        for seed in UInt64(0)..<30 {
            let regions = MapGenerator.generate(seed: seed, registry: reg)
            if regions.contains(where: { [.ruins, .dungeon, .anomaly].contains($0.kind) }) {
                sawSpecial = true
                break
            }
        }
        #expect(sawSpecial)
    }
}
