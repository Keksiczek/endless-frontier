import Foundation
import Testing
@testable import EndlessFrontierCore

/// Animals are pawn-like: a life with a body that can be hurt part by part.
@Suite("Animals")
struct AnimalTests {
    static let book = try! GameDataRegistry.bundled()

    @Test("Species carry their own traits")
    func speciesTraits() {
        #expect(LegacyAnimalSpecies.wolf.isPredator)
        #expect(!LegacyAnimalSpecies.deer.isPredator)
        #expect(LegacyAnimalSpecies.bear.baseHealth > LegacyAnimalSpecies.hare.baseHealth)
        #expect(AnimalBodyPartKind.wholeBody.contains(.torso))
    }

    @Test("A newborn animal is whole and alive")
    func newbornIsWhole() {
        let a = Animal(id: UUID(), species: "deer", sex: .female, age: 100)
        #expect(a.isAlive)
        #expect(a.canWalk)
        #expect(a.health == LegacyAnimalSpecies.deer.baseHealth)
        #expect(a.body.count == 6)
        #expect(a.body.allSatisfy { !$0.missing })
    }

    @Test("Losing legs eventually cripples; losing a vital part kills")
    func injuriesTakeParts() {
        var bear = Animal(id: UUID(), species: "bear", sex: .male, age: 500)
        bear.injure(.frontLeftLeg, by: 45)       // >40 destroys the part
        #expect(bear.bodyPart(.frontLeftLeg)?.missing == true)
        #expect(bear.canWalk)                    // still three legs
        bear.injure(.frontRightLeg, by: 45)
        bear.injure(.backLeftLeg, by: 45)
        #expect(!bear.canWalk)                   // one leg left
        #expect(bear.isAlive)                    // legs aren't fatal on their own

        var deer = Animal(id: UUID(), species: "deer", sex: .female, age: 300)
        #expect(deer.injure(.torso, by: 60) == false)  // a destroyed vital part is fatal
        #expect(!deer.isAlive)
    }

    @Test("The wild population is a deterministic mix of living beasts")
    func factoryProducesLivingBeasts() {
        var rng = SeededRNG(seed: 12345)
        let pop = AnimalFactory.wildPopulation(registry: Self.book, rng: &rng)
        #expect(pop.count >= 20)
        #expect(pop.filter { $0.species == "deer" }.count >= 10)
        #expect(pop.allSatisfy { $0.isAlive && $0.canWalk })

        var rng2 = SeededRNG(seed: 12345)
        let pop2 = AnimalFactory.wildPopulation(registry: Self.book, rng: &rng2)
        #expect(pop == pop2)                                 // same seed, same beasts
    }

    /// Predators were honoured everywhere in the engine — hunters skip them,
    /// prey flee them, they stalk the weak — and never once put on a map, so
    /// every one of those paths was dead code. Named for the reachability
    /// (rule 6), because that is the bug: a mechanic the world cannot reach.
    @Test("The wild actually contains predators")
    func predatorsAreSeeded() {
        var rng = SeededRNG(seed: 4242)
        let forest = AnimalFactory.wildPopulation(biomeID: "forest", registry: Self.book, rng: &rng)
        #expect(forest.contains { $0.isPredator },
                "a forest with no teeth in it is not a forest")
    }

    @Test("The wild says what country it lives in")
    func wildDiffersByBiome() {
        var a = SeededRNG(seed: 7), b = SeededRNG(seed: 7)
        let desert = AnimalFactory.wildPopulation(biomeID: "desert", registry: Self.book, rng: &a)
        let plains = AnimalFactory.wildPopulation(biomeID: "plains", registry: Self.book, rng: &b)
        #expect(desert.count < plains.count, "a desert is not as full as a meadow")
        #expect(desert.filter { $0.species == "deer" }.count
                < plains.filter { $0.species == "deer" }.count)
    }

    /// A hard frontier valley must actually be harder than the homeland — the
    /// region's hazard reached the map's terrain and never its beasts.
    @Test("Wilder country carries more teeth")
    func hazardBringsWolves() {
        var calm = SeededRNG(seed: 99), wild = SeededRNG(seed: 99)
        let home = AnimalFactory.wildPopulation(biomeID: "plains", hazard: 0, registry: Self.book, rng: &calm)
        let frontier = AnimalFactory.wildPopulation(biomeID: "plains", hazard: 6, registry: Self.book, rng: &wild)
        #expect(frontier.filter { $0.isPredator }.count
                > home.filter { $0.isPredator }.count)
    }

    @Test("Old saves without an animals list still load")
    func resilientDecode() throws {
        let json = #"{"deerHerd":40,"deerCapacity":80,"predatorPressure":10}"#
        let state = try JSONDecoder().decode(WildlifeState.self, from: Data(json.utf8))
        #expect(state.animals.isEmpty)
        #expect(state.deerHerd == 40)
    }
}
