import Testing
import Foundation
@testable import EndlessFrontierCore

/// Combat resolved as a single arithmetic step: a strength number met a defense
/// number and the player was handed the verdict. There was nothing to watch and
/// nothing a renderer could animate, because no intermediate state ever existed.
///
/// `BattleLog` is the sub-tick layer that fixes it. The simulation still settles
/// a battle inside one whole tick — determinism untouched, the outcome the same
/// whether or not anyone is looking — but it now records *the order and timing*
/// of what happened. Sub-tick time lives in the record, not in the tick loop.
@Suite("A battle has an inside")
struct BattleLogTests {
    private func recorded(_ build: (inout CombatEngine.BattleRecorder) -> Void) -> BattleLog {
        var r = CombatEngine.BattleRecorder()
        build(&r)
        return r.finish(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!,
                        tick: 40, attackerName: "Vorenn", defenderName: "Home", repelled: false)
    }

    @Test("Beats are spread across the tick, in order, and none is clipped")
    func momentsSpanTheTick() {
        let log = recorded { r in
            r.record(.volley, amount: 4)
            r.record(.charge, amount: 30)
            r.record(.clash, amount: 22)
            r.record(.plunder, amount: 12)
        }
        #expect(log.moments.count == 4)
        #expect(log.moments.map(\.kind) == [.volley, .charge, .clash, .plunder])
        // Strictly inside the tick and strictly increasing: a beat at exactly 0
        // or 1 would be clipped by a player joining or leaving mid-tick.
        #expect(log.moments.allSatisfy { $0.at > 0 && $0.at < 1 })
        #expect(zip(log.moments, log.moments.dropFirst()).allSatisfy { $0.at < $1.at })
    }

    @Test("A single beat still lands inside the tick")
    func singleMoment() {
        let log = recorded { $0.record(.repelled) }
        #expect(log.moments.count == 1)
        #expect(log.moments[0].at > 0 && log.moments[0].at < 1)
    }

    @Test("Playback reveals the battle progressively, never out of order")
    func playbackIsProgressive() {
        let log = recorded { r in
            r.record(.volley); r.record(.charge); r.record(.clash); r.record(.death)
        }
        #expect(log.moments(upTo: 0).isEmpty, "nothing has happened at the top of the tick")
        #expect(log.moments(upTo: 1).count == log.moments.count, "all of it by the end")
        // Monotonic: watching further never un-sees a beat.
        var seen = 0
        for step in stride(from: 0.0, through: 1.0, by: 0.05) {
            let now = log.moments(upTo: step).count
            #expect(now >= seen)
            seen = now
        }
    }

    @Test("The log counts what happened to people")
    func tallies() {
        let log = recorded { r in
            r.record(.wound, pawnName: "Mara", amount: 12)
            r.record(.death, pawnName: "Joss", amount: 40)
            r.record(.plunder, amount: 30)
        }
        #expect(log.wounded == 1)
        #expect(log.deaths == 1)
        #expect(log.plunder == 30)
    }

    // MARK: - Wired into a real raid

    private func raidWorld() throws -> (WorldState, GameDataRegistry) {
        let reg = try GameDataRegistry.bundled()
        var world = GameWorldFactory.newGame(registry: reg, seed: 4242)
        world.settlements[0].storage[.food] = 400
        // A people next door, met and hostile enough to come.
        for i in world.tribes.indices {
            world.tribes[i].discovered = true
            world.tribes[i].standing = -80
            world.tribes[i].population = 90
        }
        return (world, reg)
    }

    @Test("A raid leaves a record of how it went, not just how it ended")
    func raidRecordsItself() throws {
        var (world, reg) = try raidWorld()
        var found: BattleLog?
        for _ in 0..<400 {
            world = TickEngine.advance(world, ticks: 10, registry: reg).state
            if let log = world.settlements[0].lastBattle { found = log; break }
        }
        let log = try #require(found, "no raid landed in 4000 ticks — check the hostility setup")

        #expect(!log.moments.isEmpty)
        #expect(log.moments.contains { $0.kind == .charge }, "a raid has a charge in it")
        #expect(log.moments.allSatisfy { $0.at > 0 && $0.at < 1 })
        #expect(log.attackerName != log.defenderName)
        // Every beat about a person names them — an animation needs a subject.
        for moment in log.moments where moment.kind == .wound || moment.kind == .death {
            #expect(moment.pawnID != nil)
            #expect(moment.pawnName != nil)
        }
    }

    /// The hard invariant: recording must not change what happens.
    @Test("Battles stay deterministic for a seed")
    func deterministic() throws {
        let (world, reg) = try raidWorld()
        let a = TickEngine.advance(world, ticks: 1500, registry: reg).state
        let b = TickEngine.advance(world, ticks: 1500, registry: reg).state
        #expect(a.settlements[0].lastBattle == b.settlements[0].lastBattle)
        #expect(a.settlements[0].pawns.map(\.health) == b.settlements[0].pawns.map(\.health))
    }

    @Test("A battle survives a save, so a raid can still be watched after a reload")
    func roundTrips() throws {
        let log = recorded { r in
            r.record(.volley, amount: 3)
            r.record(.death, pawnID: UUID(), pawnName: "Mara", amount: 40)
        }
        var s = Settlement(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!,
                           name: "Home")
        s.lastBattle = log
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(Settlement.self, from: data)
        #expect(back.lastBattle == log)
    }

    @Test("A settlement saved before battles were recorded loads without one")
    func legacyDecodes() throws {
        let s = Settlement(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000003")!,
                           name: "Old")
        let encoded = try JSONEncoder().encode(s)
        var fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        fields.removeValue(forKey: "lastBattle")
        let legacy = try JSONSerialization.data(withJSONObject: fields)
        #expect(try JSONDecoder().decode(Settlement.self, from: legacy).lastBattle == nil)
    }
}

/// The second half of the sub-tick work: the *outcome* now comes out of rounds
/// that advance a clock, not out of one line of algebra with the record spread
/// evenly over it afterwards. A battle has an inside that decides things.
@Suite("Battles are fought in rounds")
struct BattleResolverTests {
    private func defender(_ n: Int, health: Double = 100,
                          melee: Double = 6, ranged: Double = 0) -> BattleResolver.Defender {
        BattleResolver.Defender(
            id: UUID(uuidString: String(format: "CCCCCCCC-0000-0000-0000-%012d", n))!,
            name: "Guard \(n)", health: health,
            ranged: ranged, melee: melee, woundMultiplier: 1)
    }

    private func fight(strength: Double, defenders: [BattleResolver.Defender],
                       fortification: Double = 0, seed: UInt64 = 7) -> BattleOutcome {
        BattleResolver.resolve(
            attackerStrength: strength, attackerName: "Vorenn",
            defenders: defenders, defenderName: "Home",
            fortification: fortification, tick: 12, seed: seed)
    }

    @Test("A strong line breaks the attack and takes the field")
    func strongLineHolds() {
        let outcome = fight(strength: 20, defenders: (0..<8).map { defender($0) })
        #expect(outcome.repelled)
        #expect(outcome.attackerRemaining == 0)
        #expect(outcome.rounds >= 1)
        #expect(outcome.log.moments.contains { $0.kind == .repelled })
    }

    @Test("An overwhelming attack gets through and costs people")
    func weakLineFalls() {
        let outcome = fight(strength: 300, defenders: [defender(0, health: 40)])
        #expect(!outcome.repelled)
        #expect(!outcome.damageByPawn.isEmpty)
    }

    /// The point of rounds: the fight lasts as long as it takes, and a harder
    /// fight takes longer than an easy one.
    @Test("A closer fight runs more rounds than a walkover")
    func roundsReflectTheFight() {
        let easy = fight(strength: 6, defenders: (0..<8).map { defender($0) })
        let hard = fight(strength: 90, defenders: (0..<8).map { defender($0) })
        #expect(hard.rounds > easy.rounds)
    }

    @Test("A battle cannot run forever")
    func roundsAreBounded() {
        // A host too big to break, held by a line too weak to break it: the
        // fight has to be *called*, not looped. Defenders are given absurd
        // health so the loop cannot end by killing them all instead.
        let stalemate = fight(strength: 100_000,
                              defenders: (0..<3).map { defender($0, health: 1e9, melee: 0.001) },
                              fortification: 0)
        #expect(stalemate.rounds == BattleResolver.maxRounds)
        #expect(!stalemate.repelled, "nobody won — but the battle ended")
    }

    @Test("Walls absorb what the line cannot")
    func fortificationSoaks() {
        let bare = fight(strength: 120, defenders: [defender(0)], fortification: 0)
        let walled = fight(strength: 120, defenders: [defender(0)], fortification: 60)
        let bareHurt = bare.damageByPawn.values.reduce(0, +)
        let walledHurt = walled.damageByPawn.values.reduce(0, +)
        #expect(walledHurt < bareHurt)
    }

    @Test("Archers get their volley in before the charge closes")
    func volleyComesFirst() {
        let outcome = fight(strength: 60, defenders: (0..<4).map { defender($0, ranged: 5) })
        let kinds = outcome.log.moments.map(\.kind)
        let volley = try! #require(kinds.firstIndex(of: .volley))
        let charge = try! #require(kinds.firstIndex(of: .charge))
        #expect(volley < charge)
    }

    /// Beats now carry the clock they happened on, and later rounds land later
    /// in the tick — which is what makes playback mean anything.
    @Test("Later rounds land later in the tick")
    func momentsAdvanceWithTheFight() {
        let outcome = fight(strength: 90, defenders: (0..<6).map { defender($0) })
        let clashes = outcome.log.moments.filter { $0.kind == .clash }
        #expect(clashes.count >= 2, "a real fight has more than one exchange")
        #expect(zip(clashes, clashes.dropFirst()).allSatisfy { $0.at < $1.at })
    }

    @Test("The same battle fought twice comes out identical")
    func deterministic() {
        let a = fight(strength: 70, defenders: (0..<5).map { defender($0) })
        let b = fight(strength: 70, defenders: (0..<5).map { defender($0) })
        #expect(a == b)
    }

    @Test("A different seed fights a different battle")
    func seedMatters() {
        let a = fight(strength: 70, defenders: (0..<5).map { defender($0) }, seed: 1)
        let b = fight(strength: 70, defenders: (0..<5).map { defender($0) }, seed: 2)
        #expect(a.log.moments.map(\.amount) != b.log.moments.map(\.amount))
    }

    @Test("Nobody left standing means nobody keeps taking hits")
    func deadDefendersStopBeingHit() {
        let outcome = fight(strength: 400, defenders: [defender(0, health: 10, melee: 0)])
        let hits = outcome.log.moments.filter { $0.kind == .wound || $0.kind == .death }
        #expect(hits.count == 1, "a fallen defender is not wounded again next round")
        #expect(hits.first?.kind == .death)
    }
}
