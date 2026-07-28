import Testing
import Foundation
@testable import EndlessFrontierCore

/// Timber and stone are carried now, not conjured. These pin the joints where
/// that goes wrong quietly: two haulers on one heap, a load that never arrives,
/// or goods that get paid for twice.
@Suite("Carrying it home")
struct HaulTests {

    private func registry() -> GameDataRegistry {
        GameDataRegistry(
            buildings: [
                BuildingDefinition(id: "granary", era: .earlySettlement, name: "Granary",
                                   cost: [.materials: 20], storage: 200)
            ],
            techs: [], eras: [], biomes: [], events: [], config: .default)
    }

    private func colony(hands: Int, piles: [(String, Int, LocalPoint)]) -> Settlement {
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-CA11-000000000001")!,
                           name: "Carryford", regionID: UUID())
        s.pawns = (0..<hands).map { i in
            Pawn(id: UUID(uuidString: String(format: "00000000-0000-0000-CA11-1000%08d", i))!,
                 name: "Hand \(i)")
        }
        var map = LocalMap(river: RiverShape(baseY: 0.9, amplitude: 0, phase: 0),
                           nodes: [], pois: [])
        map.reveal(around: LocalPoint(x: 0.5, y: 0.5), radius: 2)
        map.piles = piles.enumerated().map { index, pile in
            HaulPile(id: UUID(uuidString: String(format: "00000000-0000-0000-CA11-2000%08d", index))!,
                     position: pile.2, itemID: pile.0, amount: pile.1)
        }
        s.localMap = map
        return s
    }

    private func run(_ settlement: Settlement, ticks: Int) -> Settlement {
        var s = settlement
        for tick in 0..<ticks {
            s = HaulEngine.advanceOneTick(s, registry: registry(), tick: tick)
        }
        return s
    }

    @Test("A heap on the ground ends up in the storehouse")
    func aLoadArrives() {
        let after = run(colony(hands: 1, piles: [("wood", 4, LocalPoint(x: 0.8, y: 0.3))]),
                        ticks: 80)
        #expect(after.stockpile["wood"] == 4)
        #expect(after.localMap?.piles.isEmpty == true)
        #expect(after.pawns[0].carrying == nil, "and they put it down when they got there")
    }

    @Test("It takes walking — distance is a real cost")
    func haulingTakesTime() {
        let near = run(colony(hands: 1, piles: [("wood", 4, LocalPoint(x: 0.52, y: 0.53))]),
                       ticks: 4)
        let far = run(colony(hands: 1, piles: [("wood", 4, LocalPoint(x: 0.95, y: 0.05))]),
                      ticks: 4)
        #expect((near.stockpile["wood"] ?? 0) > (far.stockpile["wood"] ?? 0))
    }

    @Test("Two haulers never walk to the same heap")
    func aHeapIsClaimed() {
        var s = colony(hands: 4, piles: [("wood", 4, LocalPoint(x: 0.75, y: 0.3))])
        s = HaulEngine.advanceOneTick(s, registry: registry(), tick: 0)
        let claimed = s.localMap?.piles.filter { $0.claimedBy != nil } ?? []
        #expect(claimed.count <= 1)
        // …and after it is picked up, only one person is carrying it.
        let after = run(s, ticks: 60)
        #expect(after.pawns.count { $0.carrying != nil } == 0)
        #expect(after.stockpile["wood"] == 4)
    }

    @Test("Several heaps come in one after another")
    func aCrewClearsTheGround() {
        let after = run(colony(hands: 3, piles: [
            ("wood", 4, LocalPoint(x: 0.7, y: 0.3)),
            ("rough_stone", 3, LocalPoint(x: 0.3, y: 0.7)),
            ("wood", 2, LocalPoint(x: 0.6, y: 0.8)),
        ]), ticks: 120)
        #expect(after.localMap?.piles.isEmpty == true)
        #expect(after.stockpile["wood"] == 6)
        #expect(after.stockpile["rough_stone"] == 3)
    }

    @Test("Nobody hauls out of the fog")
    func theUnchartedIsLeftAlone() {
        var s = colony(hands: 2, piles: [("wood", 4, LocalPoint(x: 0.9, y: 0.9))])
        s.localMap?.exploredCells = []
        let after = run(s, ticks: 60)
        #expect(after.stockpile["wood"] == nil)
        #expect(after.localMap?.piles.count == 1)
    }

    @Test("Someone away at a landmark carries nothing")
    func theAbsentDoNotHaul() {
        var s = colony(hands: 2, piles: [("wood", 4, LocalPoint(x: 0.7, y: 0.3))])
        let trip = UUID()
        for i in s.pawns.indices { s.pawns[i].expeditionID = trip }
        let after = run(s, ticks: 60)
        #expect(after.stockpile["wood"] == nil)
    }

    @Test("Heaps close together become one, so a wood is not a confetti of logs")
    func nearbyDropsMerge() {
        var rng = SeededRNG(seed: 7)
        var map = LocalMap(river: RiverShape(baseY: 0.9, amplitude: 0, phase: 0),
                           nodes: [], pois: [])
        map = HaulEngine.drop(map, itemID: "wood", amount: 4,
                              at: LocalPoint(x: 0.5, y: 0.5), tick: 0, rng: &rng)
        map = HaulEngine.drop(map, itemID: "wood", amount: 4,
                              at: LocalPoint(x: 0.51, y: 0.51), tick: 1, rng: &rng)
        #expect(map.piles.count == 1)
        #expect(map.piles[0].amount == 8)
        // …but a different good keeps its own heap.
        map = HaulEngine.drop(map, itemID: "rough_stone", amount: 2,
                              at: LocalPoint(x: 0.5, y: 0.5), tick: 2, rng: &rng)
        #expect(map.piles.count == 2)
    }

    @Test("The ground does not silt up for ever")
    func pilesAreCapped() {
        var rng = SeededRNG(seed: 11)
        var map = LocalMap(river: RiverShape(baseY: 0.9, amplitude: 0, phase: 0),
                           nodes: [], pois: [])
        for i in 0..<(HaulEngine.maxPiles * 2) {
            map = HaulEngine.drop(map, itemID: "wood", amount: 1,
                                  at: LocalPoint(x: Double(i % 20) / 20 + 0.01,
                                                 y: Double(i / 20) / 20 + 0.01),
                                  tick: i, rng: &rng)
        }
        #expect(map.piles.count <= HaulEngine.maxPiles)
    }

    @Test("Timber and stone are hauled; a field's crop is not")
    func theLineIsDrawnWhereItShouldBe() {
        #expect(HaulEngine.isHauled(.forest))
        #expect(HaulEngine.isHauled(.stone))
        #expect(HaulEngine.isHauled(.ironOre))
        #expect(!HaulEngine.isHauled(.field))
        #expect(!HaulEngine.isHauled(.herbs))
    }

    @Test("A save written before hauling has no heaps and nobody carrying")
    func oldSavesCarryNothing() throws {
        let json = """
        {"river":{"baseY":0.8,"amplitude":0.02,"phase":0},"nodes":[],"pois":[]}
        """
        let map = try JSONDecoder().decode(LocalMap.self, from: Data(json.utf8))
        #expect(map.piles.isEmpty)
    }
}
