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

    func registry(_ events: [EventTemplate]) -> GameDataRegistry {
        Fixtures.registry(events: events)
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
