import Testing
import Foundation
@testable import EndlessFrontierCore

/// Tribes finally appear — and then do nothing. Measured over 250 years with
/// three neighbours standing: **0 wars, 0 marriages, 0 defections**, relations
/// simply drifting to friendly and parking there.
///
/// Every gate is the codebase's signature bug again — a threshold above what
/// the system driving it can produce:
/// · `drift` caps compatibility at 45 + 12 (shared faith) = **57**, and
///   measured standings landed at 45/50/56 — exactly that ceiling.
/// · marriage needed `standing > 70`: unreachable by arithmetic.
/// · war needed `standing < -45`, but even an angry secession opens at −35 and
///   drift pulls it *up* from there.
/// · defection needed `morale < 45` — the very condition that made secession
///   unreachable in the first place.
@Suite("Tribes — the gates must be reachable")
struct TribeGateTests {
    private var registry: GameDataRegistry { Fixtures.registry(config: .default) }

    private func world(standing: Double, morale: Double = 80, gini: Double = 0.1) -> WorldState {
        var settlement = Settlement(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D9")!,
            name: "Seat",
            pawns: Fixtures.pawns(30, work: .farming),
            storage: [.food: 400, .influence: 100]
        )
        settlement.stats.morale = morale
        settlement.stats.defense = 40
        settlement.society.gini = gini
        settlement.society.poorCeiling = 10
        settlement.society.wealthyFloor = 500
        settlement.leaderID = settlement.pawns.first?.id
        var state = WorldState(tick: 600, settlements: [settlement])
        state.mapSeed = 7
        state.tribes = [
            Tribe(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000DA")!,
                  name: "Sousedé", foundedTick: 0,
                  originStory: LocalizedText("They left."),
                  population: 40, genes: Genes(), cultID: nil,
                  defense: 10, stores: 200, standing: standing)
        ]
        return state
    }

    /// What relations can actually reach on their own — the ceiling every
    /// friendly gate has to live under.
    @Test("Relations can climb high enough for the friendliest gates")
    func driftCanReachTheFriendlyGates() {
        var s = world(standing: 0)
        var rng = SeededRNG(seed: 11)
        for _ in 0..<200 {
            s = DiplomacyEngine.drift(s, tribeIndex: 0, registry: registry, rng: &rng)
        }
        let reached = s.tribes[0].standing
        #expect(reached > DiplomacyEngine.marriageStanding,
                "a people this compatible must be able to reach a marriage (got \(reached))")
    }

    @Test("Two houses can actually be joined")
    func marriageHappens() {
        var married = false
        for seed in 0..<60 {
            var s = world(standing: 75)
            var rng = SeededRNG(seed: UInt64(seed) &* 2_654_435_761)
            s = DiplomacyEngine.resolveRelations(s, tribeIndex: 0, registry: registry, rng: &rng)
            if s.tribes[0].married { married = true; break }
        }
        #expect(married)
    }

    @Test("A people who hate you will eventually fall on your granaries")
    func warHappens() {
        var raided = false
        for seed in 0..<60 {
            var s = world(standing: -60)
            let before = s.settlements[0].storage[.food]
            var rng = SeededRNG(seed: UInt64(seed) &* 2_654_435_761)
            s = DiplomacyEngine.resolveRelations(s, tribeIndex: 0, registry: registry, rng: &rng)
            if s.settlements[0].storage[.food] < before { raided = true; break }
        }
        #expect(raided, "war must be reachable, or the neighbours are scenery")
    }

    /// The same insight that fixed secession: it's the poor who leave. A
    /// contented-on-average colony can still be one its poorest slip out of.
    @Test("An unequal colony leaks its poorest to friendlier neighbours")
    func defectionFollowsInequality() {
        var defected = false
        for seed in 0..<60 {
            var s = world(standing: 40, morale: 80, gini: 0.6)
            // A wealth chasm: a handful hold everything.
            for i in s.settlements[0].pawns.indices {
                s.settlements[0].pawns[i].wealth = i < 3 ? 900 : 2
            }
            let before = s.settlements[0].pawns.count
            var rng = SeededRNG(seed: UInt64(seed) &* 2_654_435_761)
            s = DiplomacyEngine.resolveRelations(s, tribeIndex: 0, registry: registry, rng: &rng)
            if s.settlements[0].pawns.count < before {
                defected = true
                #expect(s.tribes[0].defections == 1)
                break
            }
        }
        #expect(defected, "someone with nothing should look over the fence")
    }

    @Test("A fair, contented colony holds on to its people")
    func fairColoniesKeepTheirPeople() {
        var s = world(standing: 40, morale: 85, gini: 0.05)
        for i in s.settlements[0].pawns.indices { s.settlements[0].pawns[i].wealth = 100 }
        let before = s.settlements[0].pawns.count
        for seed in 0..<60 {
            var rng = SeededRNG(seed: UInt64(seed) &* 2_654_435_761)
            s = DiplomacyEngine.resolveRelations(s, tribeIndex: 0, registry: registry, rng: &rng)
        }
        #expect(s.settlements[0].pawns.count == before,
                "nobody walks out on a colony that treats them well")
    }
}

/// The colonists were 12 hard-coded English names — Rurik, Sable, Wren — reused
/// for every soul in a world meant to run for weeks. The source sim built
/// Slavic names from syllables, which is where this world's voice came from.
@Suite("Names — the colony sounds like itself")
struct NameTests {
    @Test("Names are built, not picked from a list of twelve")
    func namesAreVaried() {
        var seen = Set<String>()
        for seed in 0..<400 {
            var rng = SeededRNG(seed: UInt64(seed) &* 6_364_136_223_846_793_005)
            seen.insert(PawnFactory.name(using: &rng))
        }
        #expect(seen.count > 100, "a world you keep for weeks needs more than a dozen names (got \(seen.count))")
    }

    @Test("A name is deterministic for a seed")
    func namesAreDeterministic() {
        var a = SeededRNG(seed: 4242)
        var b = SeededRNG(seed: 4242)
        #expect(PawnFactory.name(using: &a) == PawnFactory.name(using: &b))
    }

    @Test("Every name is properly formed")
    func namesAreWellFormed() {
        for seed in 0..<200 {
            var rng = SeededRNG(seed: UInt64(seed))
            let name = PawnFactory.name(using: &rng)
            #expect(!name.isEmpty)
            #expect(name.first!.isUppercase, "\(name) should read as a name")
        }
    }
}
