import Testing
import Foundation
@testable import EndlessFrontierCore

@Suite("Pawn engine")
struct PawnEngineTests {
    private func settlement(pawns: [Pawn], food: Double = 100) -> Settlement {
        Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-fc0d50535a9f")!, name: "Camp", pawns: pawns,
                   storage: [.food: food], storageCapacity: .uniform(500),
                   stats: SettlementStats(morale: 50))
    }

    @Test("Needs decay each tick when nothing restores them")
    func needsDecay() {
        let pawn = Pawn(name: "Ada", needs: PawnNeeds(hunger: 50, rest: 50, recreation: 50))
        let s = PawnEngine.advanceOneTick(settlement(pawns: [pawn], food: 0))
        #expect(s.pawns[0].needs.hunger < 50)   // no food → hunger falls
    }

    /// Eating is `ErrandEngine`'s now, and it happens **where the food is** —
    /// so this drives the same pair the tick loop drives, in the same order,
    /// and gives the colonist long enough to walk there. A colonist with no
    /// granary built yet eats at the fire in the middle of town, which is still
    /// a walk and still takes a tick.
    @Test("A hungry pawn goes and eats, restoring hunger and consuming settlement food")
    func eating() {
        let pawn = Pawn(name: "Bo", needs: PawnNeeds(hunger: 40, rest: 80, recreation: 80))
        var s = settlement(pawns: [pawn], food: 100)
        for tick in 0..<4 {
            s = ErrandEngine.advanceOneTick(s, tick: tick)
            s = PawnEngine.advanceOneTick(s, tick: tick)
        }
        #expect(s.pawns[0].needs.hunger > 40)        // ate
        #expect(s.storage[.food] < 100)             // food consumed
    }

    @Test("A meal is taken at the granary, not out of thin air")
    func eatingIsAnErrand() {
        let pawn = Pawn(name: "Bo", needs: PawnNeeds(hunger: 40, rest: 80, recreation: 80))
        let posted = ErrandEngine.advanceOneTick(settlement(pawns: [pawn], food: 100), tick: 0)
        let errand = posted.pawns[0].errand
        #expect(errand?.kind == .eat, "hunger past the threshold sends them somewhere")
        #expect(posted.storage[.food] == 100, "nothing is eaten until they get there")
        #expect((errand?.arrivesAt ?? 0) > 0, "and getting there takes time")
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
