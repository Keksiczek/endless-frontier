import Testing
@testable import EndlessFrontierCore

@Suite("Resource loop")
struct ResourceLoopTests {
    @Test("Farm net food production accounts for population upkeep")
    func farmNetProduction() {
        // Farm makes +10 food; population 50 eats 50 * 0.1 = 5 → net +5.
        let registry = Fixtures.registry()
        let state = Fixtures.world(food: 100, population: 50)
        let next = ResourceLoop.advanceOneTick(state, registry: registry)
        #expect(abs(next.settlements[0].storage[.food] - 105) < 1e-9)
    }

    @Test("Starvation shrinks population and lowers morale")
    func starvation() {
        let registry = Fixtures.registry()
        // No buildings → no food production; storage starts at 0.
        let state = Fixtures.world(food: 0, population: 50, buildings: [])
        let next = ResourceLoop.advanceOneTick(state, registry: registry)
        #expect(next.settlements[0].storage[.food] == 0)            // clamped
        #expect(next.settlements[0].population < 50)                 // people lost
        #expect(next.settlements[0].stats.morale < 60)              // morale hit
    }

    @Test("Storage never exceeds capacity")
    func storageClampedToCapacity() {
        let registry = Fixtures.registry()
        var state = Fixtures.world(food: 499, population: 0)
        state.settlements[0].storageCapacity = 500
        let next = ResourceLoop.advanceOneTick(state, registry: registry)
        #expect(next.settlements[0].storage[.food] <= 500)
    }

    @Test("Global knowledge output reflects building production")
    func globalKnowledgeOutput() {
        let registry = Fixtures.registry()
        let state = Fixtures.world(
            buildings: [
                BuildingInstance(definitionID: "farm", count: 1),
                BuildingInstance(definitionID: "library", count: 2)
            ]
        )
        let next = ResourceLoop.advanceOneTick(state, registry: registry)
        // 2 libraries * 5 knowledge = 10.
        #expect(abs(next.globalStats.knowledgeOutput - 10) < 1e-9)
    }
}
