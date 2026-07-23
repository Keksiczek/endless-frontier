import Foundation
import Testing
@testable import EndlessFrontierCore

/// Animals are pawn-like: a life with a body that can be hurt part by part.
@Suite("Animals")
struct AnimalTests {
    @Test("Species carry their own traits")
    func speciesTraits() {
        #expect(AnimalSpecies.wolf.isPredator)
        #expect(!AnimalSpecies.deer.isPredator)
        #expect(AnimalSpecies.bear.baseHealth > AnimalSpecies.hare.baseHealth)
        #expect(AnimalSpecies.deer.bodyPlan.contains(.torso))
    }

    @Test("A newborn animal is whole and alive")
    func newbornIsWhole() {
        let a = Animal(id: UUID(), species: .deer, sex: .female, age: 100)
        #expect(a.isAlive)
        #expect(a.canWalk)
        #expect(a.health == AnimalSpecies.deer.baseHealth)
        #expect(a.body.count == 6)
        #expect(a.body.allSatisfy { !$0.missing })
    }

    @Test("Losing legs eventually cripples; losing a vital part kills")
    func injuriesTakeParts() {
        var bear = Animal(id: UUID(), species: .bear, sex: .male, age: 500)
        bear.injure(.frontLeftLeg, by: 45)       // >40 destroys the part
        #expect(bear.bodyPart(.frontLeftLeg)?.missing == true)
        #expect(bear.canWalk)                    // still three legs
        bear.injure(.frontRightLeg, by: 45)
        bear.injure(.backLeftLeg, by: 45)
        #expect(!bear.canWalk)                   // one leg left
        #expect(bear.isAlive)                    // legs aren't fatal on their own

        var deer = Animal(id: UUID(), species: .deer, sex: .female, age: 300)
        #expect(deer.injure(.torso, by: 60) == false)  // a destroyed vital part is fatal
        #expect(!deer.isAlive)
    }

    @Test("The wild population is a deterministic mix of living beasts")
    func factoryProducesLivingBeasts() {
        var rng = SeededRNG(seed: 12345)
        let pop = AnimalFactory.wildPopulation(rng: &rng)
        #expect(pop.count == 9)                              // 6 deer + 2 hare + 1 boar
        #expect(pop.filter { $0.species == .deer }.count == 6)
        #expect(pop.allSatisfy { $0.isAlive && $0.canWalk })

        var rng2 = SeededRNG(seed: 12345)
        let pop2 = AnimalFactory.wildPopulation(rng: &rng2)
        #expect(pop == pop2)                                 // same seed, same beasts
    }

    @Test("Old saves without an animals list still load")
    func resilientDecode() throws {
        let json = #"{"deerHerd":40,"deerCapacity":80,"predatorPressure":10}"#
        let state = try JSONDecoder().decode(WildlifeState.self, from: Data(json.utf8))
        #expect(state.animals.isEmpty)
        #expect(state.deerHerd == 40)
    }
}
