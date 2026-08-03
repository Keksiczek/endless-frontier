import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Neighbours & diplomacy")
struct DiplomacyTests {
    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }
    private static let capitalID = UUID(uuidString: "00000000-0000-0000-0D19-000000000001")!
    private static let tribeID = UUID(uuidString: "00000000-0000-0000-0D19-000000000002")!

    private func folk(_ count: Int, mood: Double = 70) -> [Pawn] {
        (0..<count).map { i in
            Pawn(id: UUID(uuidString: String(format: "00000000-0000-0000-0D1A-%012d", i + 1))!,
                 name: "Citizen \(i)", mood: mood, assignedWork: .farming)
        }
    }

    private func capital(_ pawns: [Pawn], morale: Double = 60, defense: Double = 20,
                         food: Double = 300) -> Settlement {
        Settlement(id: Self.capitalID, name: "Home", kind: .capital, pawns: pawns,
                   storage: [.food: food], storageCapacity: 9999,
                   stats: SettlementStats(stability: 60, morale: morale, defense: defense))
    }

    private func tribe(standing: Double, population: Double = 30,
                       genes: Genes = Genes(), stores: Double = 100) -> Tribe {
        Tribe(id: Self.tribeID, name: "Neighbours", foundedTick: 0,
              originStory: "They left.", population: population, genes: genes,
              stores: stores, standing: standing)
    }

    private func world(_ settlement: Settlement, tribes: [Tribe] = [], year: Int = 1,
                       config: WorldConfig) -> WorldState {
        WorldState(tick: year * config.ticksPerYear, mapSeed: 3,
                   settlements: [settlement], tribes: tribes)
    }

    // MARK: - Secession

    @Test("A miserable settlement sheds malcontents, who found their own people")
    func miseryBreedsSecession() throws {
        let reg = try registry()
        var w = world(capital(folk(20, mood: 20), morale: 20), config: reg.config)
        // Roll forward a few years — an unhappy town will eventually split.
        for year in 1...12 where w.tribes.isEmpty {
            w.tick = year * reg.config.ticksPerYear
            w = DiplomacyEngine.secede(w, registry: reg, year: year)
        }
        let tribe = try #require(w.tribes.first)
        #expect(tribe.population >= 4)
        #expect(w.settlements[0].pawns.count < 20)          // they really left
        #expect(tribe.standing < 25)                        // and left in anger
        #expect(!tribe.originStory.resolve(.cs).isEmpty)
    }

    @Test("A content settlement keeps its people")
    func contentSettlementHoldsTogether() throws {
        let reg = try registry()
        var w = world(capital(folk(20, mood: 90), morale: 90), config: reg.config)
        for year in 1...12 {
            w.tick = year * reg.config.ticksPerYear
            w = DiplomacyEngine.secede(w, registry: reg, year: year)
        }
        #expect(w.tribes.isEmpty)
        #expect(w.settlements[0].pawns.count == 20)
    }

    @Test("Only a handful of neighbours ever appear")
    func tribesAreCapped() throws {
        let reg = try registry()
        var w = world(capital(folk(60, mood: 10), morale: 10), config: reg.config)
        for year in 1...80 {
            w.tick = year * reg.config.ticksPerYear
            w = DiplomacyEngine.secede(w, registry: reg, year: year)
        }
        #expect(w.tribes.count <= DiplomacyEngine.maxTribes)
    }

    // MARK: - Standing

    @Test("Standing reads as a diplomatic status")
    func standingReadsAsStatus() {
        #expect(DiplomaticStanding(score: 80) == .allied)
        #expect(DiplomaticStanding(score: 40) == .friendly)
        #expect(DiplomaticStanding(score: 0) == .neutral)
        #expect(DiplomaticStanding(score: -40) == .tense)
        #expect(DiplomaticStanding(score: -80) == .war)
    }

    @Test("Like-minded neighbours drift toward friendship; opposites toward hostility")
    func compatibilityDrivesStanding() throws {
        let reg = try registry()
        let ours = folk(10).map { p -> Pawn in
            var q = p
            q.genes = Genes(sociability: 0.8, courage: 0.5)
            return q
        }
        let alike = tribe(standing: 0, genes: Genes(sociability: 0.8, courage: 0.5))
        let opposite = tribe(standing: 0, genes: Genes(sociability: 0.1, courage: 1.0))

        var friendly = world(capital(ours), tribes: [alike], config: reg.config)
        var hostile = world(capital(ours), tribes: [opposite], config: reg.config)
        for _ in 0..<20 {
            var r1 = SeededRNG(seed: 5)
            var r2 = SeededRNG(seed: 5)
            friendly = DiplomacyEngine.drift(friendly, tribeIndex: 0, registry: reg, rng: &r1)
            hostile = DiplomacyEngine.drift(hostile, tribeIndex: 0, registry: reg, rng: &r2)
        }
        #expect(friendly.tribes[0].standing > hostile.tribes[0].standing)
    }

    @Test("A shared faith binds two peoples closer than a rival one")
    func sharedFaithBinds() throws {
        let reg = try registry()
        var ourFaith = capital(folk(10))
        ourFaith.faith = FaithState(cultID: "sun", faith: 60)

        var same = tribe(standing: 0); same.cultID = "sun"
        var other = tribe(standing: 0); other.cultID = "wolf"

        var a = world(ourFaith, tribes: [same], config: reg.config)
        var b = world(ourFaith, tribes: [other], config: reg.config)
        for _ in 0..<10 {
            var r1 = SeededRNG(seed: 9)
            var r2 = SeededRNG(seed: 9)
            a = DiplomacyEngine.drift(a, tribeIndex: 0, registry: reg, rng: &r1)
            b = DiplomacyEngine.drift(b, tribeIndex: 0, registry: reg, rng: &r2)
        }
        #expect(a.tribes[0].standing > b.tribes[0].standing)
    }

    // MARK: - War & trade

    @Test("A raid loots the granary; strong walls keep the people alive")
    func raidLootsAndWallsProtect() throws {
        let reg = try registry()
        let raiders = tribe(standing: -80, population: 40, genes: Genes(courage: 1.0))

        var undefended = world(capital(folk(12), defense: 0, food: 400),
                               tribes: [raiders], config: reg.config)
        var fortified = world(capital(folk(12), defense: 100, food: 400),
                              tribes: [raiders], config: reg.config)
        var r1 = SeededRNG(seed: 4)
        var r2 = SeededRNG(seed: 4)
        undefended = DiplomacyEngine.raid(undefended, tribeIndex: 0, capitalIndex: 0,
                                          registry: reg, rng: &r1)
        fortified = DiplomacyEngine.raid(fortified, tribeIndex: 0, capitalIndex: 0,
                                         registry: reg, rng: &r2)
        // A raid is a siege now — fought out over the action clock, by the
        // player if they are there and by the world if they are not.
        undefended = SiegeTestSupport.fightItOut(undefended, registry: reg)
        fortified = SiegeTestSupport.fightItOut(fortified, registry: reg)

        #expect(undefended.settlements[0].storage[.food] < 400)          // grain carried off
        #expect(fortified.settlements[0].storage[.food]
                > undefended.settlements[0].storage[.food])              // walls kept more
        #expect(fortified.settlements[0].pawns.count == 12)              // and everyone alive
        #expect(undefended.tribes[0].wars == 1)
    }

    @Test("Friendly neighbours trade grain and knowledge")
    func friendlyNeighboursTrade() throws {
        let reg = try registry()
        var w = world(capital(folk(10), food: 100), tribes: [tribe(standing: 80)], config: reg.config)
        var traded = false
        for seed in 0..<20 where !traded {
            var rng = SeededRNG(seed: UInt64(seed))
            let after = DiplomacyEngine.resolveRelations(w, tribeIndex: 0, registry: reg, rng: &rng)
            if after.settlements[0].storage[.food] > w.settlements[0].storage[.food] {
                traded = true
                w = after
            }
        }
        #expect(traded)
    }

    @Test("A year of diplomacy is deterministic")
    func deterministic() throws {
        let reg = try registry()
        let w = world(capital(folk(24, mood: 30), morale: 30),
                      tribes: [tribe(standing: -50, population: 40)],
                      year: 4, config: reg.config)
        let a = DiplomacyEngine.advanceYear(w, registry: reg)
        let b = DiplomacyEngine.advanceYear(w, registry: reg)
        #expect(a == b)
    }

    // MARK: - A grudge has to be able to start

    /// Named for the reachability, not the behaviour (rule 6 / rule 13).
    ///
    /// Grudge had exactly one source — a quarrel — and a quarrel needed
    /// standing below −15, while standing drifts toward a compatibility of 62
    /// or better. Every term of the loop was inside the loop, so it never
    /// started: measured over two hundred years, six peoples sat at 0/0/0/+75/
    /// +80/+82 and not one war was ever declared. Every fight in the game was
    /// wolves.
    @Test("A people can come to hate you without hating you first")
    func crowdingBuildsAGrudge() throws {
        let reg = try registry()
        // A colony four times their size, on perfectly good terms to begin with.
        var w = world(capital(folk(120), morale: 80),
                      tribes: [tribe(standing: 60, population: 30)], config: reg.config)
        w.tribes[0].discovered = true
        #expect(DiplomacyEngine.crowding(w, tribeIndex: 0) > 0,
                "being four times their size has to weigh something")

        for year in 1...60 {
            w.tick = year * reg.config.ticksPerYear
            w = DiplomacyEngine.advanceYear(w, registry: reg)
            // Keep the colony big: the point is the pressure, not the drift.
            w.settlements[0].pawns = folk(120)
            w.tribes[0].population = 30
        }
        #expect(w.tribes[0].grudge > 20, "sixty years of crowding them cost nothing")
        #expect(w.tribes[0].standing < DiplomacyEngine.warStanding,
                "…and it never turned into anything")
    }

    /// The other half of the same lever: it has to be a pressure the player can
    /// manage, not a countdown to a war they cannot avoid.
    @Test("A neighbour you do not crowd bears you no grudge")
    func livingSmallCostsNothing() throws {
        let reg = try registry()
        let w = world(capital(folk(20)), tribes: [tribe(standing: 40, population: 40)],
                      config: reg.config)
        #expect(DiplomacyEngine.crowding(w, tribeIndex: 0) == 0)
    }

    @Test("Tribes survive a save round-trip")
    func tribesPersist() throws {
        let reg = try registry()
        let w = world(capital(folk(8)), tribes: [tribe(standing: 30)], config: reg.config)
        let restored = try JSONDecoder().decode(WorldState.self, from: JSONEncoder().encode(w))
        #expect(restored.tribes == w.tribes)
    }
}
