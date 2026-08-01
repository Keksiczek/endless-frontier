import Testing
import Foundation
@testable import EndlessFrontierCore

/// The mountain is dug into at the face, one block at a time, and never grows
/// back. These pin the parts that would fail quietly: a massif raised over the
/// town, a face nobody can reach, or blocks that reappear.
@Suite("The mountain you dig into")
struct StoneFieldTests {

    private func wall(columns: Range<Int>, rows: Range<Int>) -> StoneField {
        var solid: Set<Int> = []
        for c in columns {
            for r in rows { solid.insert(StoneField.index(column: c, row: r)) }
        }
        return StoneField(solid: solid, seed: 4242, usesBlocks: true)
    }

    // MARK: - The face

    @Test("Only blocks with open ground beside them can be worked")
    func onlyTheFaceIsWorkable() {
        // A 3×3 block of rock in the middle of the map: the eight around the
        // edge are faces, the one in the middle is not.
        let field = wall(columns: 10..<13, rows: 10..<13)
        let middle = StoneField.index(column: 11, row: 11)
        #expect(field.isSolid(middle))
        #expect(!field.isFace(middle))
        #expect(field.faces().count == 8)
    }

    @Test("Rock running off the edge of the map is still workable from the rim")
    func theMapEdgeCountsAsOpen() {
        let field = wall(columns: 0..<2, rows: 0..<2)
        #expect(field.faces().count == 4)
    }

    @Test("Digging a block opens the ones behind it")
    func theFaceAdvances() {
        var field = wall(columns: 10..<13, rows: 10..<13)
        let middle = StoneField.index(column: 11, row: 11)
        // Cut the block in front of the middle one until it goes.
        let front = StoneField.index(column: 11, row: 10)
        var broke = false
        for _ in 0..<40 {
            let dug = StoneEngine.mine(field, miners: 1)
            field = dug.field
            if dug.broken.contains(front) { broke = true }
            if !field.isSolid(front) { break }
        }
        #expect(broke || !field.isSolid(front))
        #expect(field.isFace(middle) || !field.isSolid(middle))
    }

    // MARK: - Working it

    @Test("A block takes several ticks and then gives up its stone")
    func aBlockYieldsWhenItBreaks() {
        var field = wall(columns: 5..<6, rows: 5..<6)
        var total = 0.0
        var ticks = 0
        while !field.isEmpty, ticks < 100 {
            let dug = StoneEngine.mine(field, miners: 1)
            field = dug.field
            total += dug.yield.values.reduce(0, +)
            ticks += 1
        }
        #expect(field.isEmpty)
        #expect(ticks > 1, "a block of hillside should not come out in one swing")
        #expect(total >= StoneEngine.yieldPerBlock)
    }

    @Test("Rock does not grow back")
    func stoneIsFinite() {
        var field = wall(columns: 5..<7, rows: 5..<6)
        for _ in 0..<200 { field = StoneEngine.mine(field, miners: 4).field }
        #expect(field.isEmpty)
        // And nothing puts it back.
        #expect(StoneEngine.mine(field, miners: 4).yield.isEmpty)
    }

    @Test("A crew spreads along the face instead of piling on one block")
    func minersSpreadOut() {
        let field = wall(columns: 4..<10, rows: 4..<5)
        let dug = StoneEngine.mine(field, miners: 4)
        #expect(dug.field.cut.count == 4)
    }

    @Test("Work banked in a block survives the tick")
    func workIsBankedInTheRock() {
        let field = wall(columns: 5..<6, rows: 5..<6)
        let once = StoneEngine.mine(field, miners: 1).field
        let twice = StoneEngine.mine(once, miners: 1).field
        let index = StoneField.index(column: 5, row: 5)
        #expect((twice.cut[index] ?? 0) > (once.cut[index] ?? 0))
    }

    // MARK: - Raising one

    @Test("A mountain never grows over the colony's own ground")
    func theTownIsNeverWalledIn() {
        let river = RiverShape(baseY: 0.85, amplitude: 0.02, phase: 0)
        for seed in UInt64(1)...40 {
            var rng = SeededRNG(seed: seed)
            let field = StoneEngine.raise(biomeID: "mountains", river: river,
                                          shore: nil, rng: &rng)
            for block in field.solid {
                let p = StoneField.centre(of: block)
                let dx = p.x - SettlementGeometry.heart.x
                let dy = p.y - SettlementGeometry.heart.y
                #expect((dx * dx + dy * dy).squareRoot() > StoneEngine.colonyClearance - 0.03,
                        "seed \(seed) put rock on the town")
            }
        }
    }

    @Test("Mountain country actually gets a mountain, and the plains rarely do")
    func biomesDiffer() {
        let river = RiverShape(baseY: 0.85, amplitude: 0.02, phase: 0)
        func blocks(_ biome: String) -> Int {
            var total = 0
            for seed in UInt64(1)...25 {
                var rng = SeededRNG(seed: seed &* 7919)
                total += StoneEngine.raise(biomeID: biome, river: river,
                                           shore: nil, rng: &rng).blockCount
            }
            return total
        }
        let mountains = blocks("mountains")
        let plains = blocks("plains")
        #expect(mountains > 0)
        #expect(mountains > plains * 3, "mountains \(mountains) vs plains \(plains)")
    }

    @Test("Raising a mountain is deterministic for a seed")
    func raisingIsDeterministic() {
        let river = RiverShape(baseY: 0.85, amplitude: 0.02, phase: 0)
        var a = SeededRNG(seed: 12345)
        var b = SeededRNG(seed: 12345)
        #expect(StoneEngine.raise(biomeID: "tundra", river: river, shore: nil, rng: &a).solid
                == StoneEngine.raise(biomeID: "tundra", river: river, shore: nil, rng: &b).solid)
    }

    // MARK: - It is in the way

    @Test("Nothing is built inside a cliff")
    func rockBlocksBuilding() {
        let registry = GameDataRegistry(
            buildings: [BuildingDefinition(id: "hut", era: .earlySettlement, name: "Hut",
                                           cost: [.materials: 10], housing: 4)],
            techs: [], eras: [], biomes: [], events: [], config: .default)
        var settlement = Settlement(id: UUID(), name: "Under the hill", regionID: UUID())
        settlement = ColonyBuilder.ensureMap(settlement)
        guard let colony = settlement.colony else { return }

        // Put rock exactly on one build tile.
        let tile = TileCoord(3, 3)
        let placement = BuildingPlacement(id: UUID(), definitionID: "", coord: tile,
                                          width: 1, height: 1)
        let point = SettlementGeometry.canvasPoint(for: placement, in: colony)
        var map = LocalMap(river: RiverShape(baseY: 0.9, amplitude: 0, phase: 0),
                           nodes: [], pois: [])
        map.stone = StoneField(solid: [LocalMap.cellIndex(point)], seed: 1, usesBlocks: true)
        settlement.localMap = map

        #expect(!ColonyBuilder.canPlace(settlement, definitionID: "hut", at: tile,
                                        registry: registry))
        // …and somewhere clear of it, you can.
        #expect(ColonyBuilder.canPlace(settlement, definitionID: "hut", at: TileCoord(14, 14),
                                       registry: registry))
    }

    @Test("A map with no mountain says so rather than looking like a dug-out one")
    func absenceIsExplicit() {
        let none = StoneField()
        #expect(!none.usesBlocks)
        #expect(none.isEmpty)
        // A massif dug flat is empty too — and must still say it has the layer.
        var dug = wall(columns: 5..<6, rows: 5..<6)
        for _ in 0..<100 { dug = StoneEngine.mine(dug, miners: 1).field }
        #expect(dug.isEmpty)
        #expect(dug.usesBlocks)
    }

    @Test("A save written before mountains decodes without one")
    func oldSavesHaveNoMountain() throws {
        let json = """
        {"river":{"baseY":0.8,"amplitude":0.02,"phase":0},"nodes":[],"pois":[]}
        """
        let map = try JSONDecoder().decode(LocalMap.self, from: Data(json.utf8))
        #expect(map.stone.isEmpty)
        #expect(!map.stone.usesBlocks)
    }
}
