import Testing
import Foundation
@testable import EndlessFrontierCore

/// The wild became pawns and stayed food. Taming is the other thing a colony
/// does with animals. These pin the parts that fail quietly: taming nobody can
/// reach, a beast that costs nothing to keep, or one that is worth nothing.
@Suite("Beasts that work for you")
struct TamingTests {

    private var registry: GameDataRegistry {
        GameDataRegistry(buildings: [], techs: [], eras: [], biomes: [], events: [],
                         config: .default)
    }

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-7A3D-%012d", n))!
    }

    private func colony(species: AnimalSpecies = .boar, hunters: Int = 2,
                        food: Double = 500, defense: Double = 0) -> Settlement {
        var s = Settlement(id: id(900), name: "Farmyard", regionID: UUID())
        s.pawns = (0..<hunters).map { i in
            Pawn(id: id(i), name: "Hunter \(i)", assignedWork: .hunting)
        }
        s.storage[ResourceType.food] = food
        s.stats.defense = defense
        var map = LocalMap(river: RiverShape(baseY: 0.9, amplitude: 0, phase: 0),
                           nodes: [], pois: [],
                           wildlife: WildlifeState(animals: [
                            Animal(id: id(500), species: species, sex: .female, age: 200,
                                   position: LocalPoint(x: 0.54, y: 0.54))
                           ], usesEntities: true))
        map.reveal(around: LocalPoint(x: 0.5, y: 0.5), radius: 2)
        s.localMap = map
        return s
    }

    private func run(_ settlement: Settlement, ticks: Int) -> Settlement {
        var s = settlement
        for tick in 0..<ticks {
            s = TamingEngine.advanceOneTick(s, registry: registry, tick: tick, mapSeed: 7)
            s = TamingEngine.keepAnimals(s, registry: registry, tick: tick, mapSeed: 7)
        }
        return s
    }

    // MARK: - Coming round

    /// The recurring bug shape: work that can never reach the threshold it is
    /// meant to cross. Taming has to actually finish.
    @Test("A beast worked at long enough comes round")
    func tamingIsReachable() {
        let after = run(colony(species: .boar, hunters: 2), ticks: 600)
        #expect(!after.tamed.isEmpty, "two hunters, a hundred visits, and nothing came round")
        #expect(after.localMap?.wildlife.animals.isEmpty == true,
                "it should be off the wild list once it is on the books")
    }

    @Test("A colony with nobody out among the animals tames nothing")
    func youHaveToBeOutThere() {
        let after = run(colony(hunters: 0), ticks: 400)
        #expect(after.tamed.isEmpty)
    }

    @Test("A biddable beast comes round sooner than a stubborn one")
    func wildnessMatters() {
        #expect(TamingEngine.wildness(.boar) > TamingEngine.wildness(.bear))
        #expect(TamingEngine.wildness(.hare) > TamingEngine.wildness(.wolf))
        let boar = run(colony(species: .boar), ticks: 200).tamed.count
        let bear = run(colony(species: .bear, defense: 40), ticks: 200).tamed.count
        #expect(boar >= bear)
    }

    @Test("Nobody gentles a wolf from behind a fence they have not built")
    func predatorsNeedAStrongColony() {
        let weak = run(colony(species: .wolf, defense: 0), ticks: 600)
        #expect(weak.tamed.isEmpty, "a defenceless colony has no business with wolves")
        let strong = run(colony(species: .wolf, defense: 40), ticks: 600)
        #expect(!strong.tamed.isEmpty)
    }

    @Test("A valley is not a menagerie")
    func theFarmyardIsCapped() {
        var s = colony()
        s.tamed = (0..<TamingEngine.maxTamed).map { i in
            TamedAnimal(animal: Animal(id: id(600 + i), species: .deer, sex: .male, age: 100),
                        role: .beastOfBurden, tamedTick: 0)
        }
        let after = run(s, ticks: 200)
        #expect(after.tamed.count <= TamingEngine.maxTamed)
    }

    // MARK: - Keeping them

    @Test("A kept beast eats out of the colony's stores")
    func animalsEat() {
        var s = colony(food: 100)
        s.tamed = [TamedAnimal(animal: Animal(id: id(700), species: .boar, sex: .male, age: 200),
                               role: .beastOfBurden, tamedTick: 0)]
        let before = s.storage[ResourceType.food]
        let after = run(s, ticks: 40)
        #expect(after.storage[ResourceType.food] < before)
    }

    @Test("A colony that cannot feed its animals loses them")
    func starvedAnimalsLeaveOrDie() {
        var s = colony(hunters: 0, food: 0)
        s.tamed = [TamedAnimal(animal: Animal(id: id(701), species: .deer, sex: .female,
                                              age: 200, health: 20),
                               role: .beastOfBurden, tamedTick: 0)]
        let after = run(s, ticks: 400)
        #expect(after.tamed.isEmpty)
    }

    // MARK: - What they are worth

    @Test("Each calling is worth its own thing, and none of them everything")
    func bonusesAreByRole() {
        func withBeast(_ species: AnimalSpecies, _ role: TamedRole) -> Settlement {
            var s = colony()
            s.tamed = [TamedAnimal(animal: Animal(id: id(800), species: species,
                                                  sex: .male, age: 200),
                                   role: role, tamedTick: 0)]
            return s
        }
        let mule = TamingEngine.bonuses(withBeast(.boar, .beastOfBurden))
        #expect(mule.haul > 0 && mule.defense == 0)

        let hound = TamingEngine.bonuses(withBeast(.wolf, .guard))
        #expect(hound.defense > 0 && hound.haul == 0)

        let friend = TamingEngine.bonuses(withBeast(.fox, .companion))
        #expect(friend.mood > 0)
    }

    @Test("A herd of mules does not make hauling free")
    func bonusesAreCapped() {
        var s = colony()
        s.tamed = (0..<20).map { i in
            TamedAnimal(animal: Animal(id: id(810 + i), species: .boar, sex: .male, age: 200),
                        role: .beastOfBurden, tamedTick: 0)
        }
        #expect(TamingEngine.bonuses(s).haul <= 0.6)
    }

    @Test("A hurt beast is worth less than a whole one")
    func vigourMatters() {
        func beast(health: Double) -> Settlement {
            var s = colony()
            s.tamed = [TamedAnimal(animal: Animal(id: id(820), species: .wolf, sex: .male,
                                                  age: 200, health: health),
                                   role: .guard, tamedTick: 0)]
            return s
        }
        #expect(TamingEngine.bonuses(beast(health: 110)).defense
                > TamingEngine.bonuses(beast(health: 20)).defense)
    }

    @Test("A species is kept for what it is good at")
    func callingsMakeSense() {
        #expect(TamingEngine.calling(.boar) == .beastOfBurden)
        #expect(TamingEngine.calling(.wolf) == .guard)
        #expect(TamingEngine.calling(.hare) == .companion)
    }

    // MARK: - The rules that must not break

    @Test("Taming is the same for the same world")
    func tamingIsDeterministic() {
        let a = run(colony(), ticks: 300)
        let b = run(colony(), ticks: 300)
        #expect(a.tamed.map(\.id) == b.tamed.map(\.id))
        #expect(a.tamed.map(\.role) == b.tamed.map(\.role))
    }

    @Test("A save from before taming has an empty farmyard and wild beasts")
    func oldSavesHaveNoAnimals() throws {
        let json = """
        {"id":"00000000-0000-0000-7A3D-000000000500","species":"deer","sex":"female",
         "age":100,"health":90,"body":[],"conditions":[]}
        """
        let animal = try JSONDecoder().decode(Animal.self, from: Data(json.utf8))
        #expect(animal.tameProgress == 0)
    }
}
