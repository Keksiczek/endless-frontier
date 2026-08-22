import Testing
import Foundation
@testable import EndlessFrontierCore

/// Keks: *"sněm by mohl být dynamický, že by lidé volili dle svých vlastností,
/// zkušeností, názorů."*
///
/// The vote already walked the roster. What it read of each person was four
/// genes and a wealth class, against a random term half again as wide as
/// everything else put together — so the tally was a coin flip with a lean on
/// it, and nothing anybody had lived through came into the room.
@Suite("An assembly of people who have lived somewhere")
struct AssemblyTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private func law(_ registry: GameDataRegistry, _ id: String) throws -> LawDefinition {
        try #require(registry.law(id))
    }

    /// A town of adults with a wealth spread, so classes and skills exist.
    private func town(_ count: Int = 40, work: WorkKind = .farming) -> Settlement {
        var pawns = Fixtures.pawns(count, work: work)
        for index in pawns.indices {
            pawns[index].age = (24 + index % 30) * 60
            pawns[index].wealth = Double(index) * 3
            pawns[index].skills[work] = 4 + index % 7
        }
        var s = Settlement(name: "Sněmovna", pawns: pawns)
        s.society = SocietyStats(gini: 0.3, poorCeiling: 40, wealthyFloor: 100)
        return s
    }

    private func world(_ settlement: Settlement) -> WorldState {
        WorldState(tick: 600, settlements: [settlement])
    }

    // MARK: - It is still an assembly

    @Test("Every adult in the settlement has a say")
    func everybodyVotes() throws {
        let registry = try registry()
        let s = town(40)
        var rng = SeededRNG(seed: 7)
        let vote = AssemblyEngine.vote(on: try law(registry, "night_watch"), in: s,
                                       state: world(s), registry: registry, rng: &rng)
        #expect(vote.turnout == 40)
        #expect(vote.votesFor + vote.votesAgainst >= 40, "the wealthy carry two voices")
    }

    @Test("Children do not vote")
    func onlyAdultsVote() throws {
        let registry = try registry()
        var s = town(20)
        for index in s.pawns.indices where index % 2 == 0 { s.pawns[index].age = 8 * 60 }
        var rng = SeededRNG(seed: 7)
        let vote = AssemblyEngine.vote(on: try law(registry, "school"), in: s,
                                       state: world(s), registry: registry, rng: &rng)
        #expect(vote.turnout == 10)
    }

    @Test("The same assembly reaches the same result twice")
    func theVoteIsDeterministic() throws {
        let registry = try registry()
        let s = town(30)
        var a = SeededRNG(seed: 99), b = SeededRNG(seed: 99)
        let first = AssemblyEngine.vote(on: try law(registry, "tithe"), in: s,
                                        state: world(s), registry: registry, rng: &a)
        let second = AssemblyEngine.vote(on: try law(registry, "tithe"), in: s,
                                         state: world(s), registry: registry, rng: &b)
        #expect(first == second)
    }

    /// The determinism fault this actually shipped with, caught by the
    /// catch-up test and worth its own guard: `loudest` picked the biggest
    /// term out of a *dictionary*, whose iteration order is not stable between
    /// two runs of the same program.
    @Test("A colonist gives the same reason every time they are asked")
    func theReasonIsStable() {
        var thinking = AssemblyEngine.Reasoning()
        thinking.terms = [.nature: 0.3, .trade: 0.3, .standing: 0.3, .hardship: 0.3]
        let answers = Set((0..<64).map { _ in thinking.loudest })
        #expect(answers.count == 1, "a tie must break the same way every time it is asked")
    }

    // MARK: - Vlastnosti: what kind of person they are

    /// Nature is read **against the colony's own people**, not against an
    /// abstraction: genes drift toward a common stock, so an absolute reading
    /// gave every colonist the same term and the room voted as one body —
    /// measured, eight of thirty laws came out unanimous. The argument in an
    /// assembly is about who *dissents*.
    @Test("The colonist who differs from their neighbours is the one who dissents")
    func natureMoves() throws {
        let registry = try registry()
        let motion = try law(registry, "night_watch")
        #expect(motion.voteBias.courage != 0, "rule 67: this law must actually be about nerve")
        var s = town(40)
        for index in s.pawns.indices {
            s.pawns[index].genes = Genes(industry: 0.5, fertility: 0.5,
                                         sociability: 0.5, courage: 0.5)
        }
        s.pawns[0].genes = Genes(industry: 0.5, fertility: 0.5, sociability: 0.5, courage: 0.95)
        s.pawns[1].genes = Genes(industry: 0.5, fertility: 0.5, sociability: 0.5, courage: 0.05)
        let stock = AssemblyEngine.GeneStock(of: s.pawns)
        var rng = SeededRNG(seed: 5)
        let bold = AssemblyEngine.weigh(motion, by: s.pawns[0], in: s, stock: stock,
                                        ticksPerYear: 60, rng: &rng)
        let timid = AssemblyEngine.weigh(motion, by: s.pawns[1], in: s, stock: stock,
                                         ticksPerYear: 60, rng: &rng)
        let sign = motion.voteBias.courage > 0 ? 1.0 : -1.0
        #expect((bold.terms[.nature] ?? 0) * sign > (timid.terms[.nature] ?? 0) * sign,
                "the brave and the timid must not read this law the same way")
    }

    @Test("A colony that agrees with itself has no argument about its own nature")
    func aUniformColonyDoesNotInventFactions() throws {
        let registry = try registry()
        var s = town(40)
        for index in s.pawns.indices {
            s.pawns[index].genes = Genes(industry: 0.5, fertility: 0.5,
                                         sociability: 0.5, courage: 0.5)
        }
        let stock = AssemblyEngine.GeneStock(of: s.pawns)
        var rng = SeededRNG(seed: 5)
        let motion = try law(registry, "night_watch")
        let terms = s.pawns.prefix(6).map { pawn -> Double in
            AssemblyEngine.weigh(motion, by: pawn, in: s, stock: stock,
                                 ticksPerYear: 60, rng: &rng).terms[.nature] ?? 0
        }
        #expect(terms.allSatisfy { abs($0 - terms[0]) < 0.001 },
                "a hundredth of variation must not be amplified into a political faction")
    }

    // MARK: - Názory: what it would mean for their work

    /// The term that did not exist. A hewing law is a lumberjack's living and
    /// a forester's grievance, and until now both voted on temperament alone.
    @Test("A trade votes its own interest")
    func tradeMoves() throws {
        let registry = try registry()
        let motion = try law(registry, "forest_protection")
        #expect(motion.voteBias.favour(of: .logging) < 0)
        #expect(motion.voteBias.favour(of: .foraging) > 0)
        let loggers = town(40, work: .logging), foragers = town(40, work: .foraging)
        var a = SeededRNG(seed: 11), b = SeededRNG(seed: 11)
        let loggerVote = AssemblyEngine.vote(on: motion, in: loggers, state: world(loggers),
                                             registry: registry, rng: &a)
        let foragerVote = AssemblyEngine.vote(on: motion, in: foragers, state: world(foragers),
                                              registry: registry, rng: &b)
        #expect(foragerVote.votesFor > loggerVote.votesFor,
                "the people whose living it protects must be the people who vote for it")
    }

    @Test("Every law says something to somebody's trade")
    func everyLawTouchesATrade() throws {
        let registry = try registry()
        for motion in registry.laws.values {
            #expect(!motion.voteBias.tradeFavour.isEmpty,
                    "'\(motion.id)' means nothing to anybody's work — nobody can vote their interest on it")
            for (trade, _) in motion.voteBias.tradeFavour {
                #expect(WorkKind(rawValue: trade) != nil,
                        "'\(motion.id)' names a trade that does not exist: \(trade)")
            }
        }
    }

    // MARK: - Zkušenosti: how loudly an opinion is held

    /// Experience is not a seventh opinion, it is how firmly the others are
    /// held — which is what makes a colony's politics change as it ages.
    @Test("A practised trade votes its interest harder than a green one")
    func experienceSharpensAnOpinion() throws {
        let registry = try registry()
        let motion = try law(registry, "great_hewing")
        var green = town(60, work: .logging), seasoned = town(60, work: .logging)
        for index in green.pawns.indices {
            green.pawns[index].age = 18 * 60
            green.pawns[index].skills[.logging] = 0
            seasoned.pawns[index].age = 52 * 60
            seasoned.pawns[index].skills[.logging] = 12
        }
        var a = SeededRNG(seed: 3), b = SeededRNG(seed: 3)
        let greenVote = AssemblyEngine.vote(on: motion, in: green, state: world(green),
                                            registry: registry, rng: &a)
        let seasonedVote = AssemblyEngine.vote(on: motion, in: seasoned, state: world(seasoned),
                                               registry: registry, rng: &b)
        // Hewing is a lumberjack's law, so the practised ones are more for it —
        // and, more to the point, less divided. A room of boys who started last
        // spring is a coin flip about the wood, and it should be.
        #expect(seasonedVote.votesFor > greenVote.votesFor)
        let seasonedSplit = abs(seasonedVote.votesFor - seasonedVote.votesAgainst)
        let greenSplit = abs(greenVote.votesFor - greenVote.votesAgainst)
        #expect(seasonedSplit > greenSplit,
                "for \(seasonedVote.votesFor) vs \(greenVote.votesFor): a room full of people who know the work should not be a coin flip")
    }

    // MARK: - What their own life is like

    @Test("A colony having a bad decade votes for change")
    func hardshipMoves() throws {
        let registry = try registry()
        // A law that says nothing to the town's trade, so what is being
        // measured is hardship and not a livelihood in disguise.
        let motion = try law(registry, "day_of_rest")
        var comfortable = town(60, work: .healing), suffering = town(60, work: .healing)
        // `needs.hunger` is satiety: 5 is a colonist starving, 95 is one who
        // has eaten. Written the other way round it passed for the wrong
        // reason, because the engine read it the other way round too.
        for index in suffering.pawns.indices {
            suffering.pawns[index].needs.hunger = 5
            suffering.pawns[index].health = 45
            suffering.pawns[index].mood = 20
        }
        for index in comfortable.pawns.indices {
            comfortable.pawns[index].needs.hunger = 95
            comfortable.pawns[index].health = 100
            comfortable.pawns[index].mood = 90
            comfortable.pawns[index].homeID = UUID()
        }
        var a = SeededRNG(seed: 21), b = SeededRNG(seed: 21)
        let easy = AssemblyEngine.vote(on: motion, in: comfortable, state: world(comfortable),
                                       registry: registry, rng: &a)
        let hard = AssemblyEngine.vote(on: motion, in: suffering, state: world(suffering),
                                       registry: registry, rng: &b)
        #expect(hard.votesFor > easy.votesFor,
                "people whose life is going badly want something — anything — to change")
    }

    /// The fault the test above shipped with, and the reason it is worth its
    /// own guard: `PawnNeeds.hunger` is **satiety** — `PawnEngine` decays it
    /// and kills at `<= 0` — so a colony with full bellies was the one the
    /// assembly counted as suffering.
    @Test("A full belly is not a hardship")
    func hungerIsSatiety() {
        var fed = Fixtures.pawns(1)[0]
        fed.needs.hunger = 100
        fed.health = 100
        fed.mood = 80
        fed.homeID = UUID()
        var starving = fed
        starving.needs.hunger = 0
        #expect(AssemblyEngine.hardship(of: fed) == 0)
        #expect(AssemblyEngine.hardship(of: starving) > 0.3)
    }

    /// Rule 23, written down as an arithmetic the data has to keep: half the
    /// die has to be able to cross the widest stake a green voter holds, or a
    /// trade is unanimous about its own law before it knows the work.
    @Test("No law asks more of a trade than the die can answer")
    func theDieCanCrossALivelihood() throws {
        let registry = try registry()
        for motion in registry.laws.values {
            for (trade, favour) in motion.voteBias.tradeFavour {
                #expect(abs(favour) <= AssemblyEngine.widestLivelihood,
                        "'\(motion.id)' stakes \(favour) on \(trade), which no doubt can cross")
            }
        }
        let greenStake = AssemblyEngine.widestLivelihood * AssemblyEngine.greenShare
        #expect(AssemblyEngine.widestDoubt / 2 > greenStake,
                "a room of people new to the work must still be able to disagree")
    }

    // MARK: - The room, made legible

    @Test("A motion carries the people who made it, loudest first")
    func voicesAreRecorded() throws {
        let registry = try registry()
        let s = town(60)
        var rng = SeededRNG(seed: 31)
        let vote = AssemblyEngine.vote(on: try law(registry, "wealth_levy"), in: s,
                                       state: world(s), registry: registry, rng: &rng)
        #expect(vote.voices.count == AssemblyEngine.voicesKept)
        #expect(vote.voices == vote.voices.sorted { $0.conviction > $1.conviction }
                || vote.voices.map(\.conviction) == vote.voices.map(\.conviction).sorted(by: >))
        #expect(vote.voices.allSatisfy { !$0.name.isEmpty })
        // …and somebody's reason is a real one, not "nothing much moved them".
        #expect(vote.voices.contains { $0.reason != .undecided })
    }

    @Test("The wealthy speak against a levy on the wealthy")
    func standingIsReported() throws {
        let registry = try registry()
        let motion = try law(registry, "wealth_levy")
        #expect(motion.voteBias.poorFavour > 0, "rule 67: the law must actually cut this way")
        var s = town(60)
        for index in s.pawns.indices { s.pawns[index].wealth = 500 }   // everybody wealthy
        var rng = SeededRNG(seed: 41)
        let vote = AssemblyEngine.vote(on: motion, in: s, state: world(s),
                                       registry: registry, rng: &rng)
        #expect(vote.votesAgainst > vote.votesFor)
        #expect(vote.voices.contains { $0.reason == .standing && !$0.forIt })
    }

    // MARK: - Wiring

    @Test("A motion put before the player survives being saved")
    func proposalsRoundTrip() throws {
        let registry = try registry()
        let s = town(30)
        var rng = SeededRNG(seed: 51)
        let vote = AssemblyEngine.vote(on: try law(registry, "school"), in: s,
                                       state: world(s), registry: registry, rng: &rng)
        #expect(!vote.voices.isEmpty, "rule 73: nothing to round-trip proves nothing")
        let back = try JSONDecoder().decode(
            LawProposal.self, from: try JSONEncoder().encode(vote))
        #expect(back == vote)
    }

    @Test("A motion saved before anybody was named still loads")
    func oldProposalsLoad() throws {
        let json = """
        {"definitionID":"school","settlementID":"00000000-0000-0000-0000-000000000001",
         "proposedTick":10,"votesFor":7,"votesAgainst":3}
        """
        let back = try JSONDecoder().decode(LawProposal.self, from: Data(json.utf8))
        #expect(back.voices.isEmpty)
        #expect(back.turnout == 0)
        #expect(back.councilApproves)
    }
}

/// Rule 23 — print the distribution before setting a threshold against it.
/// Run with `EF_DIAG=1 swift test --package-path Core --filter ZZAssemblyDiag`.
@Suite("assembly diag", .enabled(if: ProcessInfo.processInfo.environment["EF_DIAG"] != nil, "diag"))
struct ZZAssemblyDiag {

    @Test("how a real colony divides")
    func theShapeOfARoom() throws {
        let registry = try GameDataRegistry.bundled()
        var world = GameWorldFactory.newGame(registry: registry, seed: 4242)
        world = TickEngine.advance(world, ticks: 3000, registry: registry).state
        guard let s = world.settlements.first else { return }

        print("""

        ── the assembly ───────────────────────────────────────────────
        \(s.pawns.count) souls. `for` is the share of the room in favour;
        a law nobody can be against is not a decision.

        law                      | for%  split | loudest reasons
        """)
        for motion in registry.laws.values.sorted(by: { $0.id < $1.id }) {
            var rng = SeededRNG(seed: 4242 &+ UInt64(motion.id.count))
            let vote = AssemblyEngine.vote(on: motion, in: s, state: world,
                                           registry: registry, rng: &rng)
            let total = max(1, vote.votesFor + vote.votesAgainst)
            var reasons: [VoteReason: Int] = [:]
            for voice in vote.voices { reasons[voice.reason, default: 0] += 1 }
            let named = reasons.sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue
                                       : $0.value > $1.value }
                .prefix(3).map { "\($0.key.rawValue) \($0.value)" }.joined(separator: ", ")
            print(String(format: "%-24@ | %4.0f%% %5d | %@", motion.id,
                         Double(vote.votesFor) / Double(total) * 100,
                         abs(vote.votesFor - vote.votesAgainst), named))
        }
        print("──────────────────────────────────────────────────────────────\n")
    }
}
