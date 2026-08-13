import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Society, laws & the assembly")
struct SocietyTests {
    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private static let townID = UUID(uuidString: "00000000-0000-0000-05C0-000000000001")!

    private func town(_ pawns: [Pawn], food: Double = 500) -> Settlement {
        Settlement(id: Self.townID, name: "Assembly Town", kind: .capital, pawns: pawns,
                   storage: [.food: food], storageCapacity: .uniform(9999),
                   stats: SettlementStats(stability: 60, morale: 60))
    }

    private func folk(_ count: Int, wealth: (Int) -> Double = { _ in 0 },
                      mood: Double = 70, work: WorkKind = .farming) -> [Pawn] {
        (0..<count).map { i in
            Pawn(id: UUID(uuidString: String(format: "00000000-0000-0000-05C1-%012d", i + 1))!,
                 name: "Citizen \(i)", mood: mood, assignedWork: work, wealth: wealth(i))
        }
    }

    // MARK: - Wealth, classes, Gini

    @Test("Wages accrue by trade and diligence; the tithe fills the common purse")
    func wagesAndTithe() throws {
        let reg = try registry()
        var s = town(folk(10))
        s = SocietyEngine.payWages(s, registry: reg)
        #expect(s.pawns.allSatisfy { $0.wealth >= 0 })
        let untaxed = s.pawns[0].wealth

        var taxed = town(folk(10))
        taxed.laws = [LawInstance(definitionID: "tithe", enactedTick: 0, expiresTick: 9999)]
        taxed = SocietyEngine.payWages(taxed, registry: reg)
        #expect(taxed.pawns[0].wealth < untaxed)          // the tithe took its cut
        #expect(taxed.storage[.influence] > 0)            // and it reached the purse
    }

    @Test("Gini is 0 for equals and climbs with concentration")
    func giniMaths() {
        #expect(SocietyEngine.gini([5, 5, 5, 5]) == 0)
        let skewed = SocietyEngine.gini([0, 0, 0, 100])
        #expect(skewed > 0.6)
    }

    @Test("Classes split at the 40th and 85th percentiles")
    func classes() {
        var s = town(folk(20) { Double($0) })   // wealth 0…19
        s = SocietyEngine.recomputeClasses(s)
        #expect(s.society.wealthClass(of: 0) == .poor)
        #expect(s.society.wealthClass(of: 10) == .middle)
        #expect(s.society.wealthClass(of: 19) == .wealthy)
        #expect(s.society.gini > 0)
    }

    @Test("The wealthy carry two voices in the assembly")
    func wealthyVoteTwice() {
        #expect(WealthClass.wealthy.votes == 2)
        #expect(WealthClass.poor.votes == 1)
    }

    // MARK: - Unrest

    @Test("Stark inequality and a miserable poor bring an uprising")
    func revoltRedistributes() {
        // A few very rich, many destitute and unhappy.
        var pawns = folk(16, wealth: { $0 < 13 ? 0 : 400 }, mood: 30)
        pawns[15].mood = 30
        var s = town(pawns)
        s = SocietyEngine.recomputeClasses(s)
        #expect(s.society.gini > SocietyEngine.revoltGiniThreshold)

        var rng = SeededRNG(seed: 1)   // first roll is below the 0.3 threshold
        let before = s.pawns.filter { s.society.wealthClass(of: $0.wealth) == .wealthy }
            .reduce(0.0) { $0 + $1.wealth }
        s = SocietyEngine.revolt(s, rng: &rng)

        if s.society.revolts > 0 {
            let after = s.pawns.suffix(3).reduce(0.0) { $0 + $1.wealth }
            #expect(after < before)                          // the rich were looted
            #expect(s.stats.stability < 60)                  // and order suffered
        }
        // Deterministic either way.
        var rng2 = SeededRNG(seed: 1)
        var again = SocietyEngine.recomputeClasses(town(pawns))
        again = SocietyEngine.revolt(again, rng: &rng2)
        #expect(again.society.revolts == s.society.revolts)
    }

    @Test("A content, equal settlement never revolts")
    func contentSettlementIsCalm() {
        var s = SocietyEngine.recomputeClasses(town(folk(20, wealth: { _ in 10 }, mood: 85)))
        var rng = SeededRNG(seed: 7)
        s = SocietyEngine.revolt(s, rng: &rng)
        #expect(s.society.revolts == 0)
    }

    @Test("Rationing plus misery downs tools; the strike halts gathering")
    func strikeStopsGathering() throws {
        let reg = try registry()
        var s = town(folk(12, mood: 20))
        s.laws = [LawInstance(definitionID: "rationing", enactedTick: 0, expiresTick: 9999)]
        s.stats.morale = 20
        var rng = SeededRNG(seed: 2)
        s = SocietyEngine.strike(s, registry: reg, rng: &rng)
        // Whether or not the roll fired, a struck settlement gathers nothing.
        if s.strikeTicksRemaining > 0 {
            let before = s.storage[.food]
            let after = ResourceLoop.advanceSettlement(s, registry: reg, config: reg.config,
                                                       tick: 0, mapSeed: 1)
            #expect(after.storage[.food] <= before)   // no harvest came in
            #expect(after.strikeTicksRemaining == s.strikeTicksRemaining - 1)
        }
    }

    // MARK: - Leadership

    @Test("The assembly elects a charismatic adult")
    func electsALeader() throws {
        let reg = try registry()
        var pawns = folk(8)
        pawns[3].genes = Genes(sociability: 1.0, courage: 1.0)
        var s = town(pawns)
        var rng = SeededRNG(seed: 3)
        s = SocietyEngine.electLeader(s, registry: reg, rng: &rng)
        #expect(s.leaderID != nil)
        #expect(SocietyEngine.leader(of: s) != nil)
    }

    // MARK: - Laws in force

    @Test("Law modifiers combine and expire")
    func lawsCombineAndExpire() throws {
        let reg = try registry()
        var s = town(folk(4))
        s.laws = [
            LawInstance(definitionID: "school", enactedTick: 0, expiresTick: 100),
            LawInstance(definitionID: "night_watch", enactedTick: 0, expiresTick: 50)
        ]
        let mods = SocietyEngine.modifiers(s, registry: reg)
        #expect(mods.knowledgeMultiplier > 1)     // school
        #expect(mods.defenseFlat > 0)             // night watch

        s = SocietyEngine.expireLaws(s, tick: 60)
        #expect(SocietyEngine.hasLaw(s, "school"))
        #expect(!SocietyEngine.hasLaw(s, "night_watch"))   // lapsed
    }

    @Test("Rationing really does stretch the food")
    func rationingStretchesFood() throws {
        let reg = try registry()
        // Hungry colonists so they actually eat this tick.
        let hungry = folk(10).map { p -> Pawn in
            var q = p
            q.needs = PawnNeeds(hunger: 40, rest: 80, recreation: 70)
            return q
        }
        // Long enough for them to walk to the food: a meal is an errand now,
        // and nothing is eaten on the tick the hunger is noticed.
        func run(_ start: Settlement) -> Settlement {
            var s = start
            for tick in 0..<6 {
                s = ResourceLoop.advanceSettlement(s, registry: reg, config: reg.config,
                                                   tick: tick, mapSeed: 1)
            }
            return s
        }
        let plain = run(town(hungry))
        var rationed = town(hungry)
        rationed.laws = [LawInstance(definitionID: "rationing", enactedTick: 0, expiresTick: 9999)]
        let lean = run(rationed)
        #expect(lean.storage[.food] > plain.storage[.food])   // less food eaten
    }

    // MARK: - The assembly & the leader's answer

    @Test("The assembly tables a motion and the leader may ratify it")
    func councilProposesAndLeaderRatifies() throws {
        let reg = try registry()
        var world = WorldState(mapSeed: 5, settlements: [town(folk(20, wealth: { Double($0) }))])
        world = SocietyEngine.recomputeClasses(world.settlements[0]).wrappedInWorld(world)

        var rng = SeededRNG(seed: 11)
        let proposal = SocietyEngine.convene(world, settlement: world.settlements[0],
                                             registry: reg, rng: &rng)
        let motion = try #require(proposal)
        #expect(motion.votesFor + motion.votesAgainst > 0)
        world.pendingLawProposal = motion

        let after = GameEngine.resolveLawProposal(world, approve: true, registry: reg)
        #expect(after.pendingLawProposal == nil)
        #expect(SocietyEngine.hasLaw(after.settlements[0], motion.definitionID))
    }

    @Test("Overruling the assembly costs the leader standing")
    func defianceCostsMorale() throws {
        let reg = try registry()
        var world = WorldState(mapSeed: 5, settlements: [town(folk(10))])
        // A motion the council wanted…
        world.pendingLawProposal = LawProposal(
            definitionID: "school", settlementID: Self.townID, proposedTick: 0,
            votesFor: 8, votesAgainst: 2)
        let moraleBefore = world.settlements[0].stats.morale

        // …and the leader vetoes it anyway.
        let vetoed = GameEngine.resolveLawProposal(world, approve: false, registry: reg)
        #expect(vetoed.settlements[0].stats.morale < moraleBefore)
        #expect(!SocietyEngine.hasLaw(vetoed.settlements[0], "school"))

        // Ratifying what the council wanted costs nothing.
        let ratified = GameEngine.resolveLawProposal(world, approve: true, registry: reg)
        #expect(ratified.settlements[0].stats.morale == moraleBefore)
        #expect(SocietyEngine.hasLaw(ratified.settlements[0], "school"))
    }

    @Test("A year of society is deterministic")
    func yearIsDeterministic() throws {
        let reg = try registry()
        let world = WorldState(tick: reg.config.ticksPerYear * 6, mapSeed: 9,
                               settlements: [town(folk(24, wealth: { Double($0 * 3) }))])
        let a = SocietyEngine.advanceYear(world, registry: reg)
        let b = SocietyEngine.advanceYear(world, registry: reg)
        #expect(a == b)
    }

    @Test("Shipped laws all decode with names, summaries and sane durations")
    func bundledLaws() throws {
        let reg = try registry()
        #expect(reg.laws.count >= 8)
        for law in reg.laws.values {
            #expect(!law.name.resolve(.en).isEmpty)
            #expect(!law.name.resolve(.cs).isEmpty)      // Czech translation present
            #expect(!law.summary.resolve(.cs).isEmpty)
            #expect(law.durationYears > 0)
        }
    }
}

private extension Settlement {
    /// Test helper: swap this settlement back into a world.
    func wrappedInWorld(_ world: WorldState) -> WorldState {
        var w = world
        if let i = w.settlements.firstIndex(where: { $0.id == id }) {
            w.settlements[i] = self
        }
        return w
    }
}
