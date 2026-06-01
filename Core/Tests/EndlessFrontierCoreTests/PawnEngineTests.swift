import Testing
@testable import EndlessFrontierCore

@Suite("Pawn engine")
struct PawnEngineTests {
    private func settlement(pawns: [Pawn], food: Double = 100) -> Settlement {
        Settlement(name: "Camp", population: Double(pawns.count), pawns: pawns,
                   storage: [.food: food], storageCapacity: 500,
                   stats: SettlementStats(morale: 50))
    }

    @Test("Needs decay each tick when nothing restores them")
    func needsDecay() {
        let pawn = Pawn(name: "Ada", needs: PawnNeeds(hunger: 50, rest: 50, recreation: 50))
        let s = PawnEngine.advanceOneTick(settlement(pawns: [pawn], food: 0))
        #expect(s.pawns[0].needs.hunger < 50)   // no food → hunger falls
    }

    @Test("A hungry pawn eats, restoring hunger and consuming settlement food")
    func eating() {
        let pawn = Pawn(name: "Bo", needs: PawnNeeds(hunger: 40, rest: 80, recreation: 80))
        let s = PawnEngine.advanceOneTick(settlement(pawns: [pawn], food: 100))
        #expect(s.pawns[0].needs.hunger > 40)        // ate
        #expect(s.storage[.food] < 100)             // food consumed
    }

    @Test("Trait shifts mood: an optimist is happier than a pessimist with identical needs")
    func traitMood() {
        let needs = PawnNeeds(hunger: 60, rest: 60, recreation: 60)
        let optimist = PawnEngine.advanceOneTick(
            settlement(pawns: [Pawn(name: "O", trait: .optimist, needs: needs)]))
        let pessimist = PawnEngine.advanceOneTick(
            settlement(pawns: [Pawn(name: "P", trait: .pessimist, needs: needs)]))
        #expect(optimist.pawns[0].mood > pessimist.pawns[0].mood)
    }

    @Test("A skilled assigned worker produces more of its resource than an idle pawn")
    func workOutput() {
        let farmer = Pawn(name: "Farmer", skills: [.farming: 20],
                          needs: PawnNeeds(hunger: 100, rest: 100, recreation: 100),
                          assignedWork: .farming)
        let idler = Pawn(name: "Idler",
                         needs: PawnNeeds(hunger: 100, rest: 100, recreation: 100),
                         assignedWork: .idle)
        let withFarmer = PawnEngine.advanceOneTick(settlement(pawns: [farmer], food: 100))
        let withIdler = PawnEngine.advanceOneTick(settlement(pawns: [idler], food: 100))
        #expect(withFarmer.storage[.food] > withIdler.storage[.food])
    }

    @Test("Colony morale drifts toward the colonists' average mood")
    func moraleDrift() {
        // Happy pawns (high needs) should pull a low settlement morale up.
        let happy = Pawn(name: "Joy", needs: PawnNeeds(hunger: 100, rest: 100, recreation: 100))
        let s = PawnEngine.advanceOneTick(settlement(pawns: [happy], food: 100))
        #expect(s.stats.morale > 50)
    }

    @Test("A settlement with no pawns is unchanged")
    func noPawnsNoOp() {
        let s = settlement(pawns: [], food: 100)
        #expect(PawnEngine.advanceOneTick(s) == s)
    }
}
