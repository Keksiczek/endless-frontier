import Testing
import Foundation
@testable import EndlessFrontierCore

/// The world ran on one clock, and that one tick had to be everything at once:
/// a colonist's working day, a sixtieth of their aging, and a whole battle.
/// Anything meant to happen *over time* had nowhere finer to happen in, so it
/// collapsed into one arithmetic step.
///
/// Two clocks fix that. The world tick stays exactly what it was — every number
/// the game is balanced on keeps its meaning — and the action step is the grain
/// inside it, where fights, marches and shifts at the rock face actually occur.
@Suite("The world runs on two clocks")
struct WorldClockTests {
    @Test("A step sits inside its world tick, never outside")
    func positionIsInsideTheTick() {
        for step in 0..<WorldClock.actionStepsPerTick {
            let clock = WorldClock(tick: 12, step: step)
            #expect(clock.tick == 12)
            #expect(clock.position > 0 && clock.position < 1)
        }
    }

    @Test("Later steps sit later in the tick")
    func stepsAreOrdered() {
        let positions = (0..<WorldClock.actionStepsPerTick)
            .map { WorldClock(tick: 3, step: $0).position }
        #expect(zip(positions, positions.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("A step out of range is clamped into the grid, not wrapped")
    func stepsAreClamped() {
        #expect(WorldClock(tick: 1, step: -5).step == 0)
        #expect(WorldClock(tick: 1, step: 999).step == WorldClock.actionStepsPerTick - 1)
    }

    @Test("Advancing past the last step rolls into the next world tick")
    func advancingRollsOver() {
        var clock = WorldClock.start(of: 7)
        for _ in 0..<(WorldClock.actionStepsPerTick - 1) { clock = clock.advanced() }
        #expect(clock.tick == 7)
        #expect(clock.step == WorldClock.actionStepsPerTick - 1)

        clock = clock.advanced()
        #expect(clock.tick == 8, "the world tick turns when its steps run out")
        #expect(clock.step == 0)
    }

    @Test("Absolute steps are monotonic and round-trip")
    func absoluteStepsRoundTrip() {
        var clock = WorldClock.start(of: 0)
        var last = -1
        for _ in 0..<(WorldClock.actionStepsPerTick * 3) {
            #expect(clock.absoluteStep > last)
            #expect(WorldClock.at(absoluteStep: clock.absoluteStep) == clock)
            last = clock.absoluteStep
            clock = clock.advanced()
        }
    }

    // MARK: - What the grain buys

    /// The point of the whole thing: a long fight now genuinely occupies more
    /// of its tick than a short one. Under the old even-spread record, two
    /// exchanges and eight looked identical on the clock.
    @Test("A longer battle fills more of its tick than a short one")
    func fightLengthShowsOnTheClock() {
        func fight(strength: Double) -> BattleOutcome {
            BattleResolver.resolve(
                attackerStrength: strength, attackerName: "Vorenn",
                defenders: (0..<6).map {
                    BattleResolver.Defender(
                        id: UUID(uuidString: String(format: "DDDDDDDD-0000-0000-0000-%012d", $0))!,
                        name: "Guard \($0)", health: 100,
                        ranged: 0, melee: 6, woundMultiplier: 1)
                },
                defenderName: "Home", fortification: 0, tick: 5, seed: 11)
        }
        let quick = fight(strength: 5)
        let long = fight(strength: 120)
        #expect(long.rounds > quick.rounds)

        let quickEnd = quick.log.moments.map(\.at).max() ?? 0
        let longEnd = long.log.moments.map(\.at).max() ?? 0
        #expect(longEnd > quickEnd, "a drawn-out fight has to read as drawn out")
    }

    @Test("A battle cannot outlast the tick it happens in")
    func battleFitsInsideOneTick() {
        let outcome = BattleResolver.resolve(
            attackerStrength: 100_000, attackerName: "Host",
            defenders: (0..<3).map {
                BattleResolver.Defender(
                    id: UUID(uuidString: String(format: "DDDDDDDD-1111-0000-0000-%012d", $0))!,
                    name: "Guard \($0)", health: 1e9,
                    ranged: 0, melee: 0.001, woundMultiplier: 1)
            },
            defenderName: "Home", fortification: 0, tick: 5, seed: 3)
        #expect(outcome.rounds == WorldClock.actionStepsPerTick,
                "a round is an action step, so a tick's worth of steps bounds the fight")
        #expect(outcome.log.moments.allSatisfy { $0.at > 0 && $0.at < 1 })
    }

    @Test("Beats sharing a step stay distinguishable but stay in their step")
    func beatsWithinAStep() {
        var r = CombatEngine.BattleRecorder()
        r.record(.clash, step: 2, amount: 1)
        r.record(.wound, step: 2, pawnName: "Mara", amount: 2)
        let log = r.finish(id: UUID(uuidString: "DDDDDDDD-2222-0000-0000-000000000001")!,
                           tick: 1, attackerName: "A", defenderName: "B", repelled: false)
        let slice = 1.0 / Double(WorldClock.actionStepsPerTick)
        #expect(log.moments.count == 2)
        #expect(log.moments[0].at < log.moments[1].at, "recorded order survives")
        for moment in log.moments {
            #expect(moment.at > slice * 2 && moment.at < slice * 3,
                    "a beat on step 2 belongs to step 2's slice")
        }
    }
}

/// The action grid only means something once the tick loop actually runs on it.
/// These pin the loop itself: that steps happen, that they happen the right
/// number of times, and that a party's journey resolves on them rather than in
/// whole world-tick jumps.
@Suite("The tick loop runs on action steps")
struct ActionLoopTests {
    private let seat = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!
    private var registry: GameDataRegistry { Fixtures.registry(buildings: []) }

    private func worldWithParty() -> WorldState {
        var s = Settlement(id: seat, name: "Camp", storage: [.food: 900], storageCapacity: .uniform(2000))
        s.pawns = (0..<8).map { i in
            var p = Pawn(id: UUID(uuidString: String(format: "FFFFFFFF-0000-0000-0000-%012d", 100 + i))!,
                         name: "Hand \(i)", assignedWork: .farming)
            p.age = 25 * registry.config.ticksPerYear
            return p
        }
        var map = LocalMapGenerator.generate(mapSeed: 11, regionID: seat,
                                             biome: Fixtures.defaultBiomes[0])
        map.pois = [LocalPOI(id: 1, kind: .ruins,
                             position: LocalPoint(x: 0.75, y: 0.5), discovered: true)]
        s.localMap = map
        var world = WorldState(tick: 0, settlements: [s])
        world = GameEngine.dispatchToPOI(world, settlementID: seat, poiID: 1, registry: registry)
        return world
    }

    @Test("A world tick is made of exactly one grid of action steps")
    func stepsPerTick() {
        var world = worldWithParty()
        let before = world.tick
        world = TickEngine.advance(world, ticks: 1, registry: registry).state
        #expect(world.tick == before + 1)
        #expect(world.actionStep == 0, "the grid resets at the top of each world tick")
    }

    /// The point of the whole exercise: a party moves *inside* the tick, not
    /// once per tick. Sampling the same journey on successive action steps has
    /// to show it further along.
    @Test("A party advances between action steps, not only between ticks")
    func partyMovesWithinATick() throws {
        let world = worldWithParty()
        let party = try #require(world.settlements[0].expeditions.first)

        let start = Double(party.departedStep)
        let a = party.phaseProgress(atStep: start + 1)
        let b = party.phaseProgress(atStep: start + 3)
        #expect(b > a, "a march that only moved once a tick was eight times too coarse")
        #expect(party.phase(atStep: start + 1) == .outbound)
    }

    @Test("A journey still takes exactly as long as its ticks say")
    func journeyLengthIsUnchanged() throws {
        let world = worldWithParty()
        let party = try #require(world.settlements[0].expeditions.first)
        let steps = WorldClock.actionStepsPerTick

        #expect(!party.isFinished(atStep: Double(party.departedStep + party.totalSteps) - 1))
        #expect(party.isFinished(atStep: Double(party.departedStep + party.totalSteps)))
        #expect(party.totalSteps == party.totalTicks * steps,
                "moving to a finer grid must not change how long the walk is")
    }

    @Test("A party dispatched and left alone comes home on schedule")
    func partyReturnsThroughTheLoop() throws {
        var world = worldWithParty()
        let party = try #require(world.settlements[0].expeditions.first)
        let before = world.settlements[0].storage[.knowledge]

        world = TickEngine.advance(world, ticks: party.totalTicks - 1, registry: registry).state
        #expect(!world.settlements[0].expeditions.isEmpty, "still out there")

        world = TickEngine.advance(world, ticks: 2, registry: registry).state
        #expect(world.settlements[0].expeditions.isEmpty, "home and off the books")
        #expect(world.settlements[0].storage[.knowledge] > before)
    }

    /// The hard invariant, now with a finer loop underneath it.
    @Test("Stepping does not break determinism")
    func deterministic() {
        let world = worldWithParty()
        let a = TickEngine.advance(world, ticks: 40, registry: registry).state
        let b = TickEngine.advance(world, ticks: 40, registry: registry).state
        #expect(a == b)
    }

    @Test("A save from before the action grid loads at the top of a tick")
    func legacyDecodes() throws {
        let world = WorldState(tick: 5, settlements: [])
        let encoded = try JSONEncoder().encode(world)
        var fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        fields.removeValue(forKey: "actionStep")
        let legacy = try JSONSerialization.data(withJSONObject: fields)
        let restored = try JSONDecoder().decode(WorldState.self, from: legacy)
        #expect(restored.actionStep == 0)
        #expect(restored.clock == WorldClock(tick: 5, step: 0))
    }
}
