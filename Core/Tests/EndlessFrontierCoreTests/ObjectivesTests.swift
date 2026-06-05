import Testing
@testable import EndlessFrontierCore

@Suite("Objectives")
struct ObjectivesTests {
    @Test("A new game surfaces early objectives toward the next era")
    func newGameObjectives() throws {
        let reg = try GameDataRegistry.bundled()
        let world = GameWorldFactory.newGame(registry: reg, seed: 1)
        let objectives = ObjectivesEngine.current(world, registry: reg)
        #expect(!objectives.isEmpty)
        // Idle scholars → "choose research" should appear early.
        #expect(objectives.contains { $0.id == "pick_research" })
        // Era milestones present (e.g. research writing / grow population).
        #expect(objectives.contains { $0.category == .era })
    }

    @Test("An endangered colonist is the top priority")
    func hurtColonistFirst() {
        let reg = Fixtures.registry()
        let hurt = Pawn(name: "Wren", health: 15)
        let capital = Settlement(name: "C", kind: .capital, population: 1, pawns: [hurt])
        let world = WorldState(settlements: [capital])
        let objectives = ObjectivesEngine.current(world, registry: reg)
        #expect(objectives.first?.category == .colonists)
        #expect(objectives.first?.title.contains("Wren") == true)
    }

    @Test("Era stat objectives report measurable progress")
    func eraProgress() throws {
        let reg = try GameDataRegistry.bundled()
        var world = GameWorldFactory.newGame(registry: reg, seed: 1)
        world.globalStats.prosperity = 20   // ancient needs 35
        let objectives = ObjectivesEngine.current(world, registry: reg, limit: 20)
        let stat = objectives.first { $0.id == "era_stat_prosperity" }
        #expect(stat != nil)
        if let progress = stat?.progress {
            #expect(abs(progress - (20.0 / 35.0)) < 0.01)
        }
    }

    @Test("The list is capped at the requested limit")
    func limitRespected() throws {
        let reg = try GameDataRegistry.bundled()
        let world = GameWorldFactory.newGame(registry: reg, seed: 1)
        #expect(ObjectivesEngine.current(world, registry: reg, limit: 3).count <= 3)
    }

    @Test("Objectives are deterministic for the same state")
    func deterministic() throws {
        let reg = try GameDataRegistry.bundled()
        let world = GameWorldFactory.newGame(registry: reg, seed: 1)
        let a = ObjectivesEngine.current(world, registry: reg)
        let b = ObjectivesEngine.current(world, registry: reg)
        #expect(a == b)
    }
}
