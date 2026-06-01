import Testing
@testable import EndlessFrontierCore

@Suite("Pawn-driven drama")
struct PawnDramaTests {
    private func registry() -> GameDataRegistry { Fixtures.registry() }

    private func worldWithPawns(_ pawns: [Pawn]) -> WorldState {
        let capital = Settlement(name: "Capital", kind: .capital, population: Double(pawns.count),
                                 pawns: pawns, storage: [.food: 200, .knowledge: 100], storageCapacity: 500)
        return WorldState(settlements: [capital])
    }

    @Test("pawn_health targets the lowest-health colonist")
    func healthTargetsLowest() {
        let state = worldWithPawns([
            Pawn(name: "A", health: 90),
            Pawn(name: "B", health: 40),
            Pawn(name: "C", health: 100)
        ])
        let after = EffectApplier.apply(
            [.pawnHealthDelta(delta: -20, selector: .lowestHealth)], to: state, registry: registry()
        )
        let pawns = after.settlements[0].pawns
        #expect(pawns[1].health == 20)   // B was lowest
        #expect(pawns[0].health == 90)   // others untouched
        #expect(pawns[2].health == 100)
    }

    @Test("pawn_mood with selector all lifts everyone")
    func moodAll() {
        let state = worldWithPawns([Pawn(name: "A", mood: 50), Pawn(name: "B", mood: 60)])
        let after = EffectApplier.apply(
            [.pawnMoodDelta(delta: 10, selector: .all)], to: state, registry: registry()
        )
        #expect(after.settlements[0].pawns.allSatisfy { $0.mood >= 60 })
    }

    @Test("add_pawn recruits a colonist and bumps population")
    func recruit() {
        let state = worldWithPawns([Pawn(name: "A")])
        let after = EffectApplier.apply([.addPawn], to: state, registry: registry())
        #expect(after.settlements[0].pawns.count == 2)
        #expect(after.settlements[0].population == 2)
    }

    @Test("Recruited colonists are deterministic for the same world state")
    func recruitDeterministic() {
        let state = worldWithPawns([Pawn(name: "A")])
        let a = EffectApplier.apply([.addPawn], to: state, registry: registry())
        let b = EffectApplier.apply([.addPawn], to: state, registry: registry())
        #expect(a.settlements[0].pawns.last == b.settlements[0].pawns.last)
    }

    @Test("remove_pawn drops the selected colonist and the headcount")
    func remove() {
        let state = worldWithPawns([Pawn(name: "A", mood: 80), Pawn(name: "B", mood: 10)])
        let after = EffectApplier.apply(
            [.removePawn(selector: .lowestMood)], to: state, registry: registry()
        )
        #expect(after.settlements[0].pawns.map(\.name) == ["A"])
        #expect(after.settlements[0].population == 1)
    }

    @Test("Starvation eventually kills a colonist, hitting morale and headcount")
    func starvationDeath() {
        let frail = Pawn(name: "Frail", needs: PawnNeeds(hunger: 1, rest: 50, recreation: 50), health: 3)
        var s = Settlement(name: "Camp", kind: .capital, population: 1, pawns: [frail],
                           storage: [.food: 0], storageCapacity: 100, stats: SettlementStats(morale: 60))
        // No food → hunger hits 0 → health drains → death.
        for _ in 0..<5 { s = PawnEngine.advanceOneTick(s) }
        #expect(s.pawns.isEmpty)
        #expect(s.population == 0)
        #expect(s.stats.morale < 60)
    }

    @Test("All shipped pawn events decode and are reachable")
    func bundledPawnEvents() throws {
        let reg = try GameDataRegistry.bundled()
        let ids = Set(reg.events.map(\.id))
        #expect(ids.contains("colonist_illness"))
        #expect(ids.contains("wanderer_joins"))
        #expect(ids.contains("shared_feast"))
    }
}
