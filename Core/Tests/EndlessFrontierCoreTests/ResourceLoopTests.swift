import Testing
@testable import EndlessFrontierCore

@Suite("Resource loop")
struct ResourceLoopTests {
    @Test("Farm production lands in storage and hungry colonists eat it")
    func farmNetProduction() {
        // Farm makes +10 food/tick. Colonists start sated (hunger 80) and
        // only reach the meal threshold (< 70) after ~17 ticks — from then
        // on the settlement's food upkeep is their meals.
        let registry = Fixtures.registry()
        let state = Fixtures.world(food: 100, population: 50)

        let first = ResourceLoop.advanceOneTick(state, registry: registry)
        #expect(abs(first.settlements[0].storage[.food] - 110) < 1e-9)   // nobody hungry yet

        // The clock has to actually run, and it has to run the shape the game
        // runs: a meal is an errand, an errand is walked on the **action grid**
        // (`WalkPace`), and `TickEngine` steps that grid eight times before the
        // civilisation's own systems settle the tick. Driving `ResourceLoop`
        // alone is a colony where nobody ever leaves their work, so nobody ever
        // reaches the granary and nothing is ever eaten.
        var world = state
        for _ in 0..<30 {
            for step in 0..<WorldClock.actionStepsPerTick {
                world = ActionLoop.advanceStep(
                    world, clock: WorldClock(tick: world.tick, step: step),
                    registry: registry)
            }
            world = ResourceLoop.advanceOneTick(world, registry: registry)
            world.tick += 1
        }
        let ate = 100 + 30 * 10 - world.settlements[0].storage[.food]
        #expect(ate > 0)   // meals consumed once hunger crossed the threshold
    }

    @Test("Starvation shrinks population and lowers morale")
    func starvation() {
        let registry = Fixtures.registry()
        // No buildings → no food production; storage starts at 0. Hunger
        // drains (~133 ticks), then health (~50 ticks), then people die.
        var world = Fixtures.world(food: 0, population: 50, buildings: [])
        for _ in 0..<220 { world = ResourceLoop.advanceOneTick(world, registry: registry) }
        #expect(world.settlements[0].storage[.food] == 0)            // clamped
        #expect(world.settlements[0].population < 50)                // people lost
        #expect(world.settlements[0].deathTallies[PawnDeathCause.starvation.rawValue, default: 0] > 0)
        #expect(world.settlements[0].stats.morale < 60)              // morale hit
    }

    @Test("Storage never exceeds capacity")
    func storageClampedToCapacity() {
        let registry = Fixtures.registry()
        var state = Fixtures.world(food: 499, population: 0)
        state.settlements[0].storageCapacity = .uniform(500)
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
