import Testing
import Foundation
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
        let capital = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-534225a77b42")!, name: "C", kind: .capital, pawns: [hurt])
        let world = WorldState(settlements: [capital])
        let objectives = ObjectivesEngine.current(world, registry: reg)
        #expect(objectives.first?.category == .colonists)
        #expect(objectives.first?.title.resolve(.en).contains("Wren") == true)
        // …and in Czech too. A name is the same in both, so this is the cheap
        // proof that the Czech line is a real sentence and not the English one
        // falling through.
        #expect(objectives.first?.title.resolve(.cs).contains("Wren") == true)
        #expect(objectives.first?.title.resolve(.cs) != objectives.first?.title.resolve(.en))
    }

    /// **Every objective the game can raise speaks Czech.**
    ///
    /// `ObjectivesEngine` was English string literals and `ObjectivesPanel`
    /// printed them straight, so the panel that answers "what should I do next"
    /// answered a Czech player in English — for months, because the bilingual
    /// guard walks `GameData` and this is Swift in an engine.
    ///
    /// Worlds shaped to make each source fire, so this covers the objectives
    /// that only exist in trouble rather than only the ones a new game shows.
    /// The `covers` assertion is the part that keeps it honest: without it the
    /// test passes just as happily over three objectives as over eleven, and a
    /// source that stopped firing would look like a clean bill of health.
    @Test("Every objective the engine can raise reads in Czech as well as English")
    func objectivesSpeakBoth() throws {
        let reg = try GameDataRegistry.bundled()
        var raised: [Objective] = []

        raised += ObjectivesEngine.current(GameWorldFactory.newGame(registry: reg, seed: 1),
                                           registry: reg, limit: 50)

        // A colony in trouble: hurt, broken, crowded, threatened, unfocused.
        var hurt = Pawn(name: "Wren", health: 12)
        hurt.assignedWork = .farming
        var broken = Pawn(name: "Ferd")
        broken.isBroken = true
        var world = GameWorldFactory.newGame(registry: reg, seed: 7)
        world.globalStats.threatLevel = 90
        if var capital = world.settlements.first {
            capital.pawns.append(hurt)
            capital.pawns.append(broken)
            capital.specialization = .balanced
            capital.stats.defense = 0
            // Past the roofs it has: `build_housing` fires at 85% of capacity.
            let capacity = ResourceLoop.housingCapacity(capital, registry: reg)
            while Double(capital.pawns.count) < capacity { capital.pawns.append(Pawn(name: "N")) }
            world.settlements[0] = capital
        }
        // A second town nobody can reach and nobody is carting to.
        let stranded = Settlement(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000BEEF")!,
            name: "Daleká", kind: .outpost,
            pawns: [Pawn(name: "Ota")])
        world.settlements.append(stranded)
        // …and a site standing open in charted country.
        if let index = world.regions.firstIndex(where: { $0.kind == .ruins })
            ?? world.regions.indices.first {
            world.regions[index].kind = .ruins
            world.regions[index].explorationState = .fullyExplored
            world.regions[index].siteCleared = false
        }
        raised += ObjectivesEngine.current(world, registry: reg, limit: 50)

        // Defence wants its own, *small* world: militia strength comes off the
        // able-bodied, so the crowded colony above is over the threshold by
        // sheer headcount and never raises it.
        var lone = Settlement(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D0")!,
                              name: "Sama", kind: .capital, pawns: [Pawn(name: "Jed")])
        lone.stats.defense = 0
        var threatened = WorldState(settlements: [lone])
        threatened.globalStats.threatLevel = 90
        raised += ObjectivesEngine.current(threatened, registry: reg, limit: 50)

        #expect(!raised.isEmpty)
        // Which sources this world actually reached. A guard that silently
        // stops covering half the engine is worse than no guard.
        let ids = Set(raised.map(\.id))
        func covers(_ prefix: String) -> Bool { ids.contains { $0.hasPrefix(prefix) } }
        for source in ["tend_", "morale_break", "prepare_defense", "build_housing",
                       "era_", "pick_research", "site_", "supply_", "specialise_"] {
            #expect(covers(source), "no world in this test raises \(source)")
        }

        for objective in raised {
            let titleEN = objective.title.resolve(.en)
            let titleCS = objective.title.resolve(.cs)
            let detailEN = objective.detail.resolve(.en)
            let detailCS = objective.detail.resolve(.cs)
            #expect(!titleCS.isEmpty, "\(objective.id): no Czech title")
            #expect(titleCS != titleEN, "\(objective.id): Czech title is the English one")
            // A detail is optional in shape but never half-written.
            if !detailEN.isEmpty {
                #expect(detailCS != detailEN, "\(objective.id): Czech detail is the English one")
            }
        }
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
