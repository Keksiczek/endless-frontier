import Testing
import Foundation
@testable import EndlessFrontierCore

/// Winter has to actually bite, and the things that keep it out have to
/// actually keep it out. This is the recurring bug shape in this codebase — a
/// threshold beyond the reach of the rate meant to cross it — so the reachable
/// cases are pinned first.
@Suite("Cold, and what keeps it out")
struct ComfortTests {

    private func registry() -> GameDataRegistry {
        GameDataRegistry(
            buildings: [
                BuildingDefinition(id: "hut", era: .earlySettlement, name: "Hut",
                                   cost: [.materials: 10], housing: 8)
            ],
            techs: [], eras: [], biomes: [], events: [], config: .default)
    }

    @Test("A person out in a hard winter with nothing is in real trouble")
    func winterIsReachable() {
        let bare = ComfortEngine.target(season: .winter, housed: false,
                                        clothing: 0, shelter: 0)
        #expect(bare < ComfortEngine.freezingBelow,
                "winter must be able to hurt someone with nothing: \(bare)")
    }

    @Test("A roof, a coat and a fire between them make winter survivable")
    func shelterWorks() {
        let sheltered = ComfortEngine.target(season: .winter, housed: true,
                                             clothing: 2,
                                             shelter: ComfortEngine.maxHearthWarmth)
        #expect(sheltered > ComfortEngine.freezingBelow,
                "a housed, clothed colonist by a fire should not be freezing: \(sheltered)")
    }

    @Test("Summer is comfortable for everyone")
    func summerIsFine() {
        for housed in [true, false] {
            #expect(ComfortEngine.target(season: .summer, housed: housed,
                                         clothing: 0, shelter: 0) > 60)
        }
    }

    @Test("Cold costs health, and warmth does not")
    func exposureHurts() {
        var cold = Pawn(name: "Out", needs: PawnNeeds(warmth: 0), health: 100)
        var warm = Pawn(name: "In", needs: PawnNeeds(warmth: 90), health: 100)
        for _ in 0..<20 {
            cold = ComfortEngine.advanceOneTick(cold, season: .winter, shelter: 0)
            warm = ComfortEngine.advanceOneTick(warm, season: .summer, shelter: 0)
        }
        #expect(cold.health < 100)
        #expect(warm.health == 100)
    }

    @Test("Warmth settles toward what the day offers rather than jumping")
    func warmthIsGradual() {
        var pawn = Pawn(name: "Cools", needs: PawnNeeds(warmth: 100))
        let after = ComfortEngine.advanceOneTick(pawn, season: .winter, shelter: 0)
        #expect(after.needs.warmth < 100)
        #expect(after.needs.warmth > 50, "one tick should not strip a whole winter's worth")
        // …and it keeps going.
        pawn = after
        for _ in 0..<60 { pawn = ComfortEngine.advanceOneTick(pawn, season: .winter, shelter: 0) }
        #expect(pawn.needs.warmth < ComfortEngine.freezingBelow)
    }

    @Test("A colony with houses and forges keeps its people warmer")
    func firesCount() {
        var bare = Settlement(id: UUID(), name: "Bare", regionID: UUID())
        var warm = bare
        warm.buildings = [BuildingInstance(definitionID: "hut", count: 3)]
        #expect(ComfortEngine.shelter(warm, registry: registry())
                > ComfortEngine.shelter(bare, registry: registry()))
        bare.buildings = []
        #expect(ComfortEngine.shelter(bare, registry: registry()) == 0)
    }

    @Test("Warmth is one of the needs mood is made of")
    func moodFeelsTheCold() {
        let cold = Pawn(name: "A", needs: PawnNeeds(hunger: 80, rest: 80,
                                                    recreation: 80, warmth: 5))
        let warm = Pawn(name: "B", needs: PawnNeeds(hunger: 80, rest: 80,
                                                    recreation: 80, warmth: 90))
        #expect(cold.needs.average < warm.needs.average)
    }

    @Test("The ledger says why, not just how much")
    func moodHasReasons() {
        let miserable = Pawn(name: "Cold and homeless",
                             trait: .pessimist,
                             needs: PawnNeeds(hunger: 20, rest: 30,
                                              recreation: 40, warmth: 10),
                             homeID: nil)
        let factors = MoodLedger.factors(for: miserable, registry: registry())
        #expect(factors.contains { $0.id == "roofless" })
        #expect(factors.contains { $0.id == "warmth" && $0.amount < 0 })
        #expect(factors.contains { $0.id == "hunger" && $0.amount < 0 })
        #expect(factors.contains { $0.id == "trait" })
        // Biggest reason first — that is the whole use of the list.
        #expect(abs(factors[0].amount) >= abs(factors[factors.count - 1].amount))
    }

    @Test("A contented colonist's reasons are the good ones")
    func goodMoodsHaveReasonsToo() {
        let happy = Pawn(name: "Snug", needs: PawnNeeds(hunger: 95, rest: 95,
                                                        recreation: 90, warmth: 95),
                         homeID: UUID())
        let factors = MoodLedger.factors(for: happy, registry: registry())
        #expect(!factors.isEmpty)
        #expect(factors.allSatisfy { $0.amount > 0 })
    }

    @Test("A save written before warmth decodes warm rather than frozen")
    func oldSavesAreNotFrozen() throws {
        let json = #"{"hunger":80,"rest":80,"recreation":70}"#
        let needs = try JSONDecoder().decode(PawnNeeds.self, from: Data(json.utf8))
        #expect(needs.warmth == 80)
    }
}
