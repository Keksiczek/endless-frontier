import Testing
import Foundation
@testable import EndlessFrontierCore

/// **The wood is the bottom of the whole item tree, and it ran out.**
///
/// Measured on a real save 113 years in: seven trees left in the valley, every
/// one below workable growth, nine loggers with nothing to swing at. No `wood`
/// meant no `saw_timber` and no `burn_charcoal`; no charcoal meant `smelt_iron`
/// had never once run; and with no timber bundles, every building in the book
/// that lists a crafted cost — thirty-one of fifty-nine, including every
/// generator — was permanently unbuildable.
///
/// These pin the two halves of the floor that stops it: a stand that is never
/// felled, and seed that is set fast enough to matter.
@Suite("A wood the colony cannot fell to nothing")
struct WoodChainTests {

    static func wood(_ count: Int, growth: Double, species: TreeSpecies = .birch) -> [Tree] {
        (0..<count).map { i in
            Tree(id: i, species: species,
                 position: LocalPoint(x: 0.1 + Double(i % 20) * 0.04,
                                      y: 0.1 + Double(i / 20) * 0.04),
                 age: Int(Double(species.maturityTicks) * growth))
        }
    }

    static func map(_ trees: [Tree]) -> LocalMap {
        var m = LocalMap(river: RiverShape(baseY: 0.5, amplitude: 0.05, phase: 0),
                         nodes: [], pois: [],
                         wildlife: WildlifeState(deerHerd: 0, deerCapacity: 0),
                         terrainSeed: 99, trees: trees, rocks: [])
        m.usesEntityLand = true
        return m
    }

    @Test("The axes stop before the last seed-bearing trees")
    func theStandSurvives() {
        var m = Self.map(Self.wood(FloraEngine.seedStand + 2, growth: 1))
        // A hundred shifts of a whole colony's loggers, which before this would
        // have taken every tree in the valley several times over.
        for _ in 0..<400 { m = FloraEngine.fell(m, loggers: 12).map }
        let bearing = m.trees.filter { $0.growth >= FloraEngine.bearingGrowth }.count
        #expect(bearing >= FloraEngine.seedStand,
                "only \(bearing) bearing trees left of \(FloraEngine.seedStand)")
    }

    @Test("A tree the player marked is felled even when the wood is at its floor")
    func aMarkOutranksTheFloor() {
        let trees = Self.wood(FloraEngine.seedStand, growth: 1)
        var m = Self.map(trees)
        let target = trees[0].id
        for _ in 0..<40 { m = FloraEngine.fell(m, loggers: 1, marked: [target]).map }
        #expect(!m.trees.contains { $0.id == target },
                "a marked tree is a decision, and the colony ignored it")
    }

    @Test("Nothing is felled before it has ever set seed")
    func nothingIsFelledBeforeItBears() {
        #expect(FloraEngine.minimumWorkableGrowth >= FloraEngine.bearingGrowth,
                "harvesting under breeding age is how the valley emptied")
    }

    @Test("A stripped valley comes back inside a colony's lifetime")
    func aStrippedValleyRecovers() {
        // What the save actually held: seven saplings and nothing else.
        var m = Self.map(Self.wood(7, growth: 0))
        // Fifty years, seeded on the cadence `WildlifeEngine` uses.
        let pass = LaborEngine.staffingInterval * 5
        for tick in stride(from: 0, to: 3000, by: pass) {
            m = FloraEngine.advanceOneTick(m, by: pass)
            m = FloraEngine.reseeded(m, mapSeed: 4242, tick: tick)
        }
        let bearing = m.trees.filter { $0.growth >= FloraEngine.bearingGrowth }.count
        #expect(m.trees.count > 30, "only \(m.trees.count) trees after fifty years")
        #expect(bearing >= FloraEngine.seedStand,
                "only \(bearing) of them bearing — the wood has no future")
    }
}

/// **Crafting from the list, in parallel.**
///
/// Keks: *"asi by bylo fajn moct z toho seznamu craftit paralelně."* His town
/// has seven lumberyards and six bloomeries and worked **one** lumberyard order
/// at a time, because the bench was keyed on the building's id rather than on
/// how many of them stand.
@Suite("Every shop that stands is a bench")
struct ParallelBenchTests {

    static func settlement(_ registry: GameDataRegistry) -> Settlement {
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-0B01-f7695d4586ee")!,
                           name: "Bench", kind: .capital)
        for slot in 0..<3 {
            s.buildings.append(BuildingInstance.founding("lumberyard", at: s.id, slot: slot))
        }
        s.stockpile["wood"] = 999
        return s
    }

    @Test("Three lumberyards work three orders at once")
    func threeShopsThreeBenches() throws {
        let registry = try GameDataRegistry.bundled()
        var s = Self.settlement(registry)
        for i in 0..<3 {
            s.craftOrders.append(CraftOrder(id: UUID(), recipeID: "saw_timber",
                                           wanted: nil, placedTick: i))
        }
        let benches = CraftingEngine.workableBenches(
            at: s, researched: [], crafters: 6, registry: registry)
        #expect(benches.count == 3, "only \(benches.count) of three lumberyards is working")
    }

    @Test("No more benches than there are hands to stand at them")
    func handsAreTheCeiling() throws {
        let registry = try GameDataRegistry.bundled()
        var s = Self.settlement(registry)
        for i in 0..<3 {
            s.craftOrders.append(CraftOrder(id: UUID(), recipeID: "saw_timber",
                                           wanted: nil, placedTick: i))
        }
        let benches = CraftingEngine.workableBenches(
            at: s, researched: [], crafters: 1, registry: registry)
        #expect(benches.count == 1,
                "one crafter opened \(benches.count) benches and each order crawls")
    }
}
