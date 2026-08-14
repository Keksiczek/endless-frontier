import Testing
import Foundation
@testable import EndlessFrontierCore

/// The three situations that look identical when the player is shown one
/// number, and have nothing to do with each other.
///
/// This is the 2026-08-13 famine written as a test: production was healthy,
/// plots outnumbered what was wanted two to one, cooks and farmers both scaled
/// — and the harvest was lying in the fields under a dead colonist's claim.
/// Finding it took a day and came down to reading two figures side by side.
@Suite("A number in the bar can be followed to where it stops")
struct StoreBreakdownTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private func town(
        food: Double = 0, shelf: [String: Int] = [:], piles: [HaulPile] = [], cooks: Int = 0
    ) -> Settlement {
        var s = Settlement(
            id: UUID(uuidString: "5709E0A0-0000-0000-0000-000000000001")!,
            name: "Larder", kind: .capital,
            storage: [.food: food], storageCapacity: .uniform(5000))
        s.stockpile = shelf
        for i in 0..<cooks {
            var pawn = Pawn(
                id: UUID(uuidString: "5709E0A0-C00C-0000-0000-\(String(format: "%012d", i))")!,
                name: "Cook \(i)")
            pawn.age = 30 * 60
            pawn.assignedWork = .cooking
            s.pawns.append(pawn)
        }
        var map = LocalMap(river: RiverShape(baseY: 0.9, amplitude: 0, phase: 0),
                           nodes: [], pois: [])
        map.piles = piles
        s.localMap = map
        return s
    }

    private func stage(_ id: String, _ stages: [StoreStage]) -> StoreStage? {
        stages.first { $0.id == id }
    }

    @Test("A full shelf and an empty larder is a kitchen problem, and says so")
    func shelfFullNobodyCooking() throws {
        let reg = try registry()
        let grain = try #require(CookingEngine.foodstuffs(reg).sorted().first)
        let stages = StoreBreakdown.food(
            town(food: 0, shelf: [grain: 400], cooks: 0), registry: reg)

        #expect(stage("shelf", stages)?.amount == 400)
        #expect(stage("meals", stages)?.amount == 0)
        // The sentence a player needs, in both languages (rule 7).
        let note = try #require(stage("shelf", stages)?.note)
        #expect(note.resolve(.en).contains("nobody is cooking"))
        #expect(note.resolve(.cs).contains("nikdo nevaří"))
    }

    @Test("A harvest lying in the fields is a carrying problem, and says so")
    func reapedButNotCarried() throws {
        let reg = try registry()
        let grain = try #require(CookingEngine.foodstuffs(reg).sorted().first)
        let heap = HaulPile(
            id: UUID(uuidString: "5709E0A0-9111-0000-0000-000000000001")!,
            position: LocalPoint(x: 0.4, y: 0.4), itemID: grain, amount: 260)
        let stages = StoreBreakdown.food(
            town(food: 0, shelf: [:], piles: [heap], cooks: 2), registry: reg)

        #expect(stage("lying", stages)?.amount == 260)
        #expect(stage("shelf", stages)?.amount == 0)
        let note = try #require(stage("lying", stages)?.note)
        #expect(note.resolve(.cs).contains("Leží na poli"))
    }

    @Test("The two situations are told apart, which one number cannot do")
    func theSameZeroMeansTwoThings() throws {
        let reg = try registry()
        let grain = try #require(CookingEngine.foodstuffs(reg).sorted().first)
        let heap = HaulPile(
            id: UUID(uuidString: "5709E0A0-9111-0000-0000-000000000002")!,
            position: LocalPoint(x: 0.4, y: 0.4), itemID: grain, amount: 260)

        let kitchenFault = StoreBreakdown.food(
            town(food: 0, shelf: [grain: 400], cooks: 0), registry: reg)
        let carryingFault = StoreBreakdown.food(
            town(food: 0, piles: [heap], cooks: 2), registry: reg)

        // Identical headline: both colonies read `food: 0`.
        #expect(stage("meals", kitchenFault)?.amount == stage("meals", carryingFault)?.amount)
        // …and the breakdown separates them.
        #expect(stage("shelf", kitchenFault)?.amount != stage("shelf", carryingFault)?.amount)
        #expect(stage("lying", kitchenFault)?.amount != stage("lying", carryingFault)?.amount)
    }

    @Test("Materials name the made goods, which is the trap that froze the game")
    func materialsSeparateStoreFromShelf() throws {
        let reg = try registry()
        var s = town()
        s.storage[.materials] = 5500
        let stages = StoreBreakdown.materials(s, registry: reg)

        #expect(stage("store", stages)?.amount == 5500)
        #expect(stage("made", stages)?.amount == 0)
        // A colony rich in `materials` and out of `timber_bundle` builds
        // nothing, and until 2026-08-13 there was nowhere that said so.
        let note = try #require(stage("made", stages)?.note)
        #expect(note.resolve(.en).contains("timber"))
        #expect(note.resolve(.cs).contains("trámy"))
    }

    @Test("Every stage of every resource reads in Czech as well as English")
    func everyStageIsBilingual() throws {
        let reg = try registry()
        let s = town(food: 10, shelf: ["grain": 5])
        for resource in ResourceType.allCases {
            for stage in StoreBreakdown.of(resource, in: s, registry: reg) {
                #expect(!stage.label.resolve(.cs).isEmpty)
                #expect(stage.label.resolve(.cs) != stage.label.resolve(.en),
                        "\(resource) / \(stage.id) is the same in both languages")
            }
        }
    }

    @Test("The shelf names its kinds, biggest first")
    func shelfNamesTheKinds() throws {
        let reg = try registry()
        let kinds = CookingEngine.foodstuffs(reg).sorted()
        try #require(kinds.count >= 2)
        let stages = StoreBreakdown.food(
            town(shelf: [kinds[0]: 30, kinds[1]: 90]), registry: reg)

        let shelf = try #require(stage("shelf", stages))
        #expect(shelf.amount == 120)
        // Which is the whole ask: not "120 food" but *what* the 120 is.
        #expect(shelf.items.count == 2)
        #expect(shelf.items.first?.id == kinds[1], "biggest first")
        #expect(shelf.items.first?.amount == 90)
        #expect(shelf.items.allSatisfy { !$0.name.resolve(.cs).isEmpty })
    }

    @Test("Timber and stone are told apart where they lie")
    func materialKindsAreNamed() throws {
        let reg = try registry()
        func heap(_ n: Int, _ id: String, _ amount: Int) -> HaulPile {
            HaulPile(id: UUID(uuidString: String(format: "5709E0A0-9111-0000-0000-%012d", n))!,
                     position: LocalPoint(x: 0.3, y: 0.3), itemID: id, amount: amount)
        }
        var s = town(piles: [heap(10, "wood", 40), heap(11, "rough_stone", 15)])
        s.storage[.materials] = 900
        let stages = StoreBreakdown.materials(s, registry: reg)

        let lying = try #require(stage("lying", stages))
        #expect(lying.amount == 55)
        #expect(lying.items.map(\.id) == ["wood", "rough_stone"], "biggest first")
    }

    @Test("Food kinds do not leak into the materials chain")
    func theTwoChainsDoNotMix() throws {
        let reg = try registry()
        let grain = try #require(CookingEngine.foodstuffs(reg).sorted().first)
        var s = town(shelf: [grain: 500, "timber_bundle": 7])
        s.storage[.materials] = 100

        let made = try #require(stage("made", StoreBreakdown.materials(s, registry: reg)))
        // The shelf is one dictionary and the two chains share it, so this is
        // the join that would quietly count grain as building stock.
        #expect(made.amount == 7)
        #expect(made.items.map(\.id) == ["timber_bundle"])
    }
}
