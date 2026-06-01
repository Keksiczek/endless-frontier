import Testing
@testable import EndlessFrontierCore

@Suite("Pawn growth & mood breaks")
struct PawnGrowthTests {
    private func wellFed(_ pawn: Pawn) -> Settlement {
        Settlement(name: "Camp", kind: .capital, population: 1, pawns: [pawn],
                   storage: [.food: 500], storageCapacity: 500, stats: SettlementStats(morale: 60))
    }

    @Test("A working colonist gains skill through learning-by-doing")
    func skillGrowth() {
        let farmer = Pawn(name: "Mara", skills: [.farming: 5],
                          needs: PawnNeeds(hunger: 100, rest: 100, recreation: 100),
                          assignedWork: .farming)
        var s = wellFed(farmer)
        // ~200 ticks at 0.5 XP/tick → one level. Run enough to be sure.
        for _ in 0..<250 { s = PawnEngine.advanceOneTick(s) }
        #expect(s.pawns[0].skill(.farming) >= 6)
    }

    @Test("Skill is capped at the maximum")
    func skillCap() {
        let master = Pawn(name: "Max", skills: [.farming: 20], skillXP: [.farming: 99],
                          needs: PawnNeeds(hunger: 100, rest: 100, recreation: 100),
                          assignedWork: .farming)
        var s = wellFed(master)
        for _ in 0..<10 { s = PawnEngine.advanceOneTick(s) }
        #expect(s.pawns[0].skill(.farming) == 20)
    }

    @Test("Sustained low mood triggers a mental break that stops work")
    func moodBreak() {
        // Starving, joyless pawn → mood collapses → break.
        let miserable = Pawn(name: "Glum", trait: .pessimist, skills: [.farming: 10],
                             needs: PawnNeeds(hunger: 5, rest: 5, recreation: 5),
                             mood: 10, assignedWork: .farming)
        var s = Settlement(name: "Camp", kind: .capital, population: 1, pawns: [miserable],
                           storage: [.food: 0], storageCapacity: 500, stats: SettlementStats(morale: 60))
        let foodBefore = s.storage[.food]
        s = PawnEngine.advanceOneTick(s)
        #expect(s.pawns[0].isBroken)
        #expect(s.storage[.food] == foodBefore)   // produced nothing while broken
    }

    @Test("A broken colonist recovers once mood climbs back up")
    func recovery() {
        let recovering = Pawn(name: "Hope", needs: PawnNeeds(hunger: 100, rest: 100, recreation: 100),
                              mood: 100, assignedWork: .idle, isBroken: true)
        let s = PawnEngine.advanceOneTick(wellFed(recovering))
        #expect(s.pawns[0].isBroken == false)
    }

    @Test("Skill growth keeps the seed-reproducibility guarantee")
    func reproducible() throws {
        let registry = try GameDataRegistry.bundled()
        let world = GameWorldFactory.newGame(registry: registry, seed: 11)
        let a = TickEngine.advance(world, ticks: 500, registry: registry)
        let b = TickEngine.advance(world, ticks: 500, registry: registry)
        #expect(a.state == b.state)
    }
}
