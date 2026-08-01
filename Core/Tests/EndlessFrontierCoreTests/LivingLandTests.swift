import Foundation
import Testing
@testable import EndlessFrontierCore

/// The land used to be numbers: a forest was an `amount` that dipped when
/// someone worked it, a rock was the same, and the wild was a `Double` called
/// `deerHerd`. Nobody ever felled a tree — a number fell. These cover the layer
/// that replaces them with things that stand somewhere, grow, and are gone.

private func mapWith(trees: [Tree] = [], rocks: [Rock] = [],
                     animals: [Animal] = [], capacity: Double = 80,
                     herd: Double = 40, seed: UInt64 = 99) -> LocalMap {
    LocalMap(river: RiverShape(baseY: 0.5, amplitude: 0.05, phase: 0),
             nodes: [], pois: [],
             wildlife: WildlifeState(deerHerd: herd, deerCapacity: capacity,
                                     predatorPressure: 10, animals: animals),
             terrainSeed: seed, trees: trees, rocks: rocks)
}

private func animal(_ species: AnimalSpecies, id: Int, age: Int = 100,
                    health: Double? = nil) -> Animal {
    Animal(id: UUID(uuidString: String(format: "00000000-0000-0000-A11A-%012d", id))!,
           species: species, sex: .female, age: age, health: health)
}

@Suite("A forest is trees, and a rock is a body with ore in it")
struct FloraTests {

    @Test("A tree grows from sapling to full over its species' lifetime")
    func treesGrow() {
        let sapling = Tree(id: 0, species: .oak, position: LocalPoint(x: 0.5, y: 0.5), age: 0)
        let grown = Tree(id: 1, species: .oak, position: LocalPoint(x: 0.5, y: 0.5),
                         age: TreeSpecies.oak.maturityTicks)
        #expect(sapling.growth == 0)
        #expect(grown.isMature)
        #expect(grown.timberYield > sapling.timberYield)
    }

    @Test("A birch comes back inside a lifetime; an oak does not")
    func speciesDifferInPatience() {
        #expect(TreeSpecies.birch.maturityTicks < TreeSpecies.oak.maturityTicks)
        #expect(TreeSpecies.oak.timber > TreeSpecies.birch.timber)
    }

    @Test("Ageing the wood is the only thing a quiet tick does to it")
    func ticksAgeTheWood() {
        let map = mapWith(trees: [Tree(id: 0, species: .pine,
                                       position: LocalPoint(x: 0.4, y: 0.4), age: 10)])
        let after = FloraEngine.advanceOneTick(map)
        #expect(after.trees[0].age == 11)
        #expect(after.trees.count == 1)
    }

    /// Work banked in the tree, not in the colonist — the whole reason a tree
    /// is an object.
    @Test("Axe-work stays in the tree between shifts")
    func choppingIsBanked() {
        var map = mapWith(trees: [Tree(id: 0, species: .pine,
                                       position: LocalPoint(x: 0.4, y: 0.4),
                                       age: TreeSpecies.pine.maturityTicks)])
        map = FloraEngine.fell(map, loggers: 1).map
        let first = map.trees[0].chopped
        #expect(first > 0)
        map = FloraEngine.fell(map, loggers: 1).map
        #expect(map.trees[0].chopped > first)
    }

    @Test("A tree that comes down is gone, and gives up its timber")
    func fellingRemovesTheTree() {
        var map = mapWith(trees: [Tree(id: 0, species: .oak,
                                       position: LocalPoint(x: 0.4, y: 0.4),
                                       age: TreeSpecies.oak.maturityTicks,
                                       chopped: 0.99)])
        let result = FloraEngine.fell(map, loggers: 1)
        map = result.map
        #expect(result.felled == 1)
        #expect(result.timber > 0)
        #expect(map.trees.isEmpty)
    }

    @Test("Nobody fells a sapling while grown wood is standing")
    func saplingsAreLeftAlone() {
        let map = mapWith(trees: [
            Tree(id: 0, species: .oak, position: LocalPoint(x: 0.4, y: 0.4), age: 0),
            Tree(id: 1, species: .oak, position: LocalPoint(x: 0.5, y: 0.5),
                 age: TreeSpecies.oak.maturityTicks)
        ])
        let after = FloraEngine.fell(map, loggers: 1).map
        #expect(after.trees.first { $0.id == 0 }?.chopped == 0)
        #expect((after.trees.first { $0.id == 1 }?.chopped ?? 0) > 0)
    }

    @Test("A worked-out rock stays on the ground rather than vanishing")
    func spentRocksRemain() {
        var map = mapWith(rocks: [Rock(id: 0, kind: .clayBank,
                                       position: LocalPoint(x: 0.3, y: 0.3),
                                       amount: 1, capacity: 40)])
        map = FloraEngine.quarry(map, miners: 4).map
        #expect(map.rocks.count == 1)
        #expect(map.rocks[0].isSpent)
        #expect(map.rocks[0].remaining == 0)
    }

    @Test("Harder stone gives up less for the same work")
    func hardnessCosts() {
        let granite = mapWith(rocks: [Rock(id: 0, kind: .granite,
                                           position: LocalPoint(x: 0.3, y: 0.3),
                                           amount: 100, capacity: 100)])
        let clay = mapWith(rocks: [Rock(id: 0, kind: .clayBank,
                                        position: LocalPoint(x: 0.3, y: 0.3),
                                        amount: 100, capacity: 100)])
        let fromGranite = FloraEngine.quarry(granite, miners: 1).yield[.stone] ?? 0
        let fromClay = FloraEngine.quarry(clay, miners: 1).yield[.clay] ?? 0
        #expect(fromClay > fromGranite)
    }

    @Test("A wood generated from the same seed is the same wood")
    func generationIsDeterministic() {
        var a = SeededRNG(seed: 4242)
        var b = SeededRNG(seed: 4242)
        let centres = [LocalPoint(x: 0.3, y: 0.3), LocalPoint(x: 0.7, y: 0.6)]
        let first = FloraFactory.woods(around: centres, biomeID: "temperate_forest", rng: &a)
        let second = FloraFactory.woods(around: centres, biomeID: "temperate_forest", rng: &b)
        #expect(!first.isEmpty)
        #expect(first == second)
    }

    @Test("Every tree in a generated wood has its own id")
    func idsAreUnique() {
        var rng = SeededRNG(seed: 7)
        let trees = FloraFactory.woods(
            around: [LocalPoint(x: 0.3, y: 0.3), LocalPoint(x: 0.6, y: 0.6)],
            biomeID: "forest", rng: &rng)
        #expect(Set(trees.map(\.id)).count == trees.count)
    }
}

@Suite("The wild lives its own life")
struct AnimalLifeTests {

    @Test("A tick ages every beast")
    func beastsAge() {
        let map = mapWith(animals: [animal(.deer, id: 1, age: 50)])
        let after = AnimalEngine.advanceOneTick(map, tick: 5, ticksPerYear: 60)
        #expect(after.wildlife.animals[0].age == 51)
    }

    /// The regression this suite exists for. The first pass had winter at −12
    /// against a hardiest comfort floor of −15 and summer at 24 against a
    /// softest ceiling of 28 — so no animal could ever be cold or hot, and two
    /// of the four condition kinds were unreachable code.
    @Test("The seasons actually reach past the beasts' comfort bands")
    func bandsAreReachable() {
        let winter = AnimalEngine.temperature(.winter)
        let summer = AnimalEngine.temperature(.summer)
        #expect(AnimalSpecies.allCases.contains { winter < $0.comfortLow },
                "no species can ever suffer cold")
        #expect(AnimalSpecies.allCases.contains { summer > $0.comfortHigh },
                "no species can ever suffer heat")
        // And it must not be *every* species, or winter is just a cull.
        #expect(AnimalSpecies.allCases.contains { winter >= $0.comfortLow })
        #expect(AnimalSpecies.allCases.contains { summer <= $0.comfortHigh })
    }

    @Test("Winter bites a beast that cannot take the cold")
    func winterBites() {
        // A boar's comfort floor is −15; a hard winter goes below it.
        var after = mapWith(animals: [animal(.boar, id: 1)], seed: 3)
        // The last quarter of a 60-tick year is winter: ticks 45…59.
        for tick in 45..<60 {
            after = AnimalEngine.advanceOneTick(after, tick: tick, ticksPerYear: 60)
        }
        #expect(Season(tick: 45, ticksPerYear: 60) == .winter)
        #expect(after.wildlife.animals[0].conditions.contains { $0.kind == .frostbite })
    }

    @Test("High summer tells on a thick coat")
    func summerTellsOnTheThickCoated() {
        // A bear's ceiling is 28; high summer goes past it.
        var after = mapWith(animals: [animal(.bear, id: 1)], seed: 4)
        for tick in 15..<30 {
            after = AnimalEngine.advanceOneTick(after, tick: tick, ticksPerYear: 60)
        }
        #expect(Season(tick: 15, ticksPerYear: 60) == .summer)
        #expect(after.wildlife.animals[0].conditions.contains { $0.kind == .heatstroke })
    }

    @Test("A beast carrying nothing mends")
    func theUnhurtMend() {
        let map = mapWith(animals: [animal(.deer, id: 1, health: 40)])
        var after = map
        for tick in 0..<10 {
            // Spring: nothing to suffer from.
            after = AnimalEngine.advanceOneTick(after, tick: tick, ticksPerYear: 60)
        }
        #expect(after.wildlife.animals[0].health > 40)
    }

    @Test("A beast whose vitals are gone is taken off the map")
    func theDeadAreRemoved() {
        var dying = animal(.hare, id: 1)
        dying.injure(.head, by: 500)
        let map = mapWith(animals: [dying, animal(.deer, id: 2)])
        let after = AnimalEngine.advanceOneTick(map, tick: 1, ticksPerYear: 60)
        #expect(after.wildlife.animals.count == 1)
        #expect(after.wildlife.animals[0].species == .deer)
    }

    /// The hunt takes the lame and the sick before the strong.
    @Test("Hunting takes the weakest prey first")
    func theHuntTakesTheWeak() {
        let strong = animal(.deer, id: 1, health: 90)
        let weak = animal(.deer, id: 2, health: 20)
        let result = AnimalEngine.hunt(mapWith(animals: [strong, weak]), count: 1)
        #expect(result.taken == 1)
        #expect(result.map.wildlife.animals.map(\.id) == [strong.id])
    }

    @Test("The hunt does not take predators")
    func wolvesAreNotGame() {
        let result = AnimalEngine.hunt(mapWith(animals: [animal(.wolf, id: 1)]), count: 2)
        #expect(result.taken == 0)
        #expect(result.map.wildlife.animals.count == 1)
    }

    @Test("A valley hunted flat stays flat — nothing breeds from nothing")
    func anEmptyValleyStaysEmpty() {
        let map = mapWith(animals: [], capacity: 80)
        let after = AnimalEngine.breed(map, tick: 0, ticksPerYear: 60)
        #expect(after.wildlife.animals.isEmpty)
    }

    @Test("The wild breeds back in spring while there is room")
    func springRefills() {
        let herd = (1...4).map { animal(.deer, id: $0) }
        let map = mapWith(animals: herd, capacity: 80)
        #expect(Season(tick: 0, ticksPerYear: 60) == .spring)
        let after = AnimalEngine.breed(map, tick: 0, ticksPerYear: 60)
        #expect(after.wildlife.animals.count > herd.count)
    }

    @Test("Nothing calves in January")
    func winterHasNoCalves() {
        let herd = (1...4).map { animal(.deer, id: $0) }
        let map = mapWith(animals: herd, capacity: 80)
        let after = AnimalEngine.breed(map, tick: 45, ticksPerYear: 60)
        #expect(after.wildlife.animals.count == herd.count)
    }

    @Test("The same world runs the same wild twice")
    func lifeIsDeterministic() {
        let map = mapWith(animals: (1...5).map { animal(.deer, id: $0) }, seed: 12345)
        var a = map, b = map
        for tick in 0..<50 {
            a = AnimalEngine.advanceOneTick(a, tick: tick, ticksPerYear: 60)
            b = AnimalEngine.advanceOneTick(b, tick: tick, ticksPerYear: 60)
        }
        #expect(a.wildlife.animals == b.wildlife.animals)
    }

    /// Old saves predate all of this and must still load and play.
    @Test("A map with no trees, rocks or beasts is left alone")
    func anEmptyLandIsUntouched() {
        let bare = mapWith()
        #expect(AnimalEngine.advanceOneTick(bare, tick: 3, ticksPerYear: 60) == bare)
        #expect(FloraEngine.advanceOneTick(bare) == bare)
        #expect(FloraEngine.fell(bare, loggers: 3).timber == 0)
    }
}
