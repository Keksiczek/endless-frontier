import Testing
@testable import EndlessFrontierCore

@Suite("Tension calculator")
struct TensionTests {
    @Test("Tension stays within bounds")
    func bounded() {
        let state = Fixtures.world()
        let t = TensionCalculator.calculate(state, config: .default)
        #expect(t >= 0 && t <= 100)
    }

    @Test("Recent disasters raise tension")
    func disastersRaiseTension() {
        var calm = Fixtures.world()
        calm.tick = 100
        let baseline = TensionCalculator.calculate(calm, config: .default)

        var tense = calm
        tense.eventHistory = [
            HistoricalEvent(templateID: "quake", type: .disaster, tick: 98),
            HistoricalEvent(templateID: "raid", type: .threat, tick: 99)
        ]
        let raised = TensionCalculator.calculate(tense, config: .default)
        #expect(raised > baseline)
    }

    @Test("Higher era ramps baseline tension up")
    func eraRamp() {
        var early = Fixtures.world()
        early.era = .earlySettlement
        var late = early
        late.era = .medieval
        #expect(TensionCalculator.calculate(late, config: .default)
                > TensionCalculator.calculate(early, config: .default))
    }
}

@Suite("Story planner")
struct StoryPlannerTests {
    static let opportunity = EventTemplate(
        id: "boon", type: .opportunity, name: "Boon", era: [], weight: 100,
        cooldownTicks: 100,
        effects: [.statDelta(stat: .parse("global.prosperity"), delta: 5)],
        narrativeHint: "Good fortune."
    )
    static let flavor = EventTemplate(
        id: "calm", type: .flavor, name: "Calm", era: [], weight: 100,
        cooldownTicks: 5, narrativeHint: "A quiet day."
    )
    static let gated = EventTemplate(
        id: "scholar", type: .opportunity, name: "Scholar", era: [], weight: 100,
        conditions: [.techResearched("writing")], narrativeHint: "A scholar visits."
    )

    /// Firing is probabilistic — quiet is the storyteller's default. These
    /// tests are about the *mechanism* (eligibility, cooldown, effects), so
    /// they pin the dice at certainty; the odds themselves are covered by
    /// `EventDensityTests`. Without this, "no event fired" assertions would
    /// pass vacuously whenever the roll simply came up short.
    static let alwaysFires: WorldConfig = {
        var config = WorldConfig.default
        config.majorEventChance = 1
        config.minorEventChance = 1
        return config
    }()

    func registry(_ events: [EventTemplate]) -> GameDataRegistry {
        Fixtures.registry(events: events, config: Self.alwaysFires)
    }

    @Test("Planner is deterministic for the same seed and state")
    func deterministic() {
        let reg = registry([Self.opportunity, Self.flavor])
        var state = Fixtures.world()
        state.rngSeed = 12345
        state.tick = 10

        let a = StoryPlanner.run(state, registry: reg)
        let b = StoryPlanner.run(state, registry: reg)
        #expect(a.fired.map(\.templateID) == b.fired.map(\.templateID))
        #expect(a.state.rngSeed == b.state.rngSeed)
    }

    @Test("Events whose conditions are unmet never fire")
    func conditionGating() {
        let reg = registry([Self.gated])
        var state = Fixtures.world()
        state.tick = 10
        // writing not researched → gated event ineligible.
        let result = StoryPlanner.run(state, registry: reg)
        #expect(!result.fired.contains { $0.templateID == "scholar" })
    }

    @Test("Cooldown blocks an event from re-firing too soon")
    func cooldownRespected() {
        let reg = registry([Self.opportunity])
        var state = Fixtures.world()
        state.tick = 50
        state.eventCooldowns["boon"] = 10   // fired at tick 10, cooldown 100 → blocked until 110
        let result = StoryPlanner.run(state, registry: reg)
        #expect(result.fired.isEmpty)
    }

    @Test("A fired event records history, sets cooldown, and applies effects")
    func firingMutatesWorld() {
        let reg = registry([Self.opportunity])
        var state = Fixtures.world()
        state.tick = 10
        state.globalStats.prosperity = 40
        let result = StoryPlanner.run(state, registry: reg)
        #expect(result.fired.map(\.templateID) == ["boon"])
        #expect(result.state.eventCooldowns["boon"] == 10)
        #expect(result.state.globalStats.prosperity > 40)   // +5 effect applied
    }
}

/// An event has to still be felt on the tick after it happened.
///
/// It was not. `PawnEngine` recomputes `mood` from needs every single tick, and
/// `pawn_mood` wrote into `mood` — so a golden age lifted the colony's spirits
/// for one tick and the engine wrote over it before anybody could notice. Every
/// authored mood effect in `events.json` was decoration. It lands on
/// `Pawn.moodShift` now, which the mood formula reads and which fades over a
/// season.
@Suite("An event is felt")
struct MoodShiftTests {

    private func colony() throws -> (WorldState, GameDataRegistry) {
        let reg = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: reg, seed: 99)
        // Nobody hungry, nobody cold: the mood under test is the event's.
        for index in state.settlements[0].pawns.indices {
            state.settlements[0].pawns[index].needs = PawnNeeds()
        }
        return (state, reg)
    }

    @Test("A good year is still remembered a tick later")
    func aLiftOutlivesTheTickItLandedOn() throws {
        let (start, reg) = try colony()
        let lifted = EffectApplier.apply(
            start, effect: .pawnMoodDelta(delta: 12, selector: .all), registry: reg)
        let before = TickEngine.advance(start, ticks: 2, registry: reg).state
        let after = TickEngine.advance(lifted, ticks: 2, registry: reg).state
        func averageMood(_ s: WorldState) -> Double {
            let pawns = s.settlements[0].pawns
            return pawns.reduce(0) { $0 + $1.mood } / Double(max(1, pawns.count))
        }
        #expect(averageMood(after) > averageMood(before) + 1,
                "the colony felt the event for exactly one tick and then forgot it")
    }

    /// …and it has to actually *reach* nothing, or one good harvest marks a
    /// colonist for life. Arithmetic rather than a world, because a living world
    /// keeps firing new events into the same field — which is the point of it,
    /// and makes it useless for measuring a fade.
    @Test("…and a season later it has worn off")
    func aLiftFades() {
        var left = PawnEngine.moodShiftLimit
        for _ in 0..<15 { left *= PawnEngine.moodShiftDecay }   // one season
        #expect(left < PawnEngine.moodShiftLimit / 2, """
            a season on, the strongest feeling a colony can hold still carries \
            \(left) of \(PawnEngine.moodShiftLimit) — that is a mark for life, \
            not a mood
            """)
        // And not so fast that nobody ever notices: still most of it next tick.
        #expect(PawnEngine.moodShiftDecay > 0.9)
    }

    @Test("A colonist a disaster picked out is named in the chronicle")
    func theHurtOneHasAName() throws {
        let (start, reg) = try colony()
        let before = start.settlements[0].journal.entries.count
        let hurt = EffectApplier.apply(
            start, effect: .pawnHealthDelta(delta: -8, selector: .lowestHealth), registry: reg)
        #expect(hurt.settlements[0].journal.entries.count > before,
                "somebody was hurt and the chronicle does not say who")
    }
}
