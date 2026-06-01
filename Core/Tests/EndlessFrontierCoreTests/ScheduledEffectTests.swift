import Testing
@testable import EndlessFrontierCore

@Suite("Scheduled & duration effects")
struct ScheduledEffectTests {
    private func registry(_ events: [EventTemplate] = []) -> GameDataRegistry {
        Fixtures.registry(events: events)
    }

    @Test("A resource_delta with duration schedules a drip instead of applying instantly")
    func durationSchedulesDrip() {
        let reg = registry()
        var state = Fixtures.world(food: 200)
        state.tick = 0
        let effect = EventEffect.resourceDelta(resource: .food, delta: -100, scope: .global, durationTicks: 20)

        let after = EffectApplier.apply([effect], to: state, registry: reg)
        // No instant change.
        #expect(after.settlements[0].storage[.food] == 200)
        // One scheduled drip of -5/tick for 20 ticks.
        #expect(after.scheduledEffects.count == 1)
        #expect(after.scheduledEffects[0].ticksRemaining == 20)
    }

    @Test("The drip applies its total over its duration and then clears")
    func dripAppliesOverDuration() {
        let reg = registry()
        var state = Fixtures.world(food: 200, buildings: [])   // no production to interfere
        let effect = EventEffect.resourceDelta(resource: .food, delta: -100, scope: .global, durationTicks: 20)
        state = EffectApplier.apply([effect], to: state, registry: reg)

        for _ in 0..<20 {
            state = ScheduledEffectEngine.advanceOneTick(state, registry: reg).state
        }
        #expect(abs(state.settlements[0].storage[.food] - 100) < 1e-6)   // 200 - 100
        #expect(state.scheduledEffects.isEmpty)
    }

    @Test("A trigger_event with delay fires later and applies the target event")
    func delayedTriggerFires() {
        let boon = EventTemplate(
            id: "boon", type: .opportunity, name: "Boon", era: [], weight: 1,
            effects: [.statDelta(stat: .parse("global.prosperity"), delta: 10)],
            narrativeHint: "Good fortune."
        )
        let reg = registry([boon])
        var state = Fixtures.world()
        state.tick = 10
        state.globalStats.prosperity = 30

        state = EffectApplier.apply([.triggerEvent(eventID: "boon", delayTicks: 5)], to: state, registry: reg)
        #expect(state.scheduledEffects.count == 1)

        // Before the fire tick: nothing happens.
        state.tick = 14
        var result = ScheduledEffectEngine.advanceOneTick(state, registry: reg)
        #expect(result.fired.isEmpty)
        #expect(result.state.globalStats.prosperity == 30)

        // At the fire tick: the event fires and its effect applies.
        var atFire = result.state
        atFire.tick = 15
        result = ScheduledEffectEngine.advanceOneTick(atFire, registry: reg)
        #expect(result.fired.map(\.templateID) == ["boon"])
        #expect(result.state.globalStats.prosperity == 40)
        #expect(result.state.scheduledEffects.isEmpty)
    }

    @Test("TickEngine processes scheduled drips during normal advancement")
    func tickEngineRunsSchedule() {
        let reg = registry()
        var state = Fixtures.world(food: 300, buildings: [])
        state = EffectApplier.apply(
            [.resourceDelta(resource: .food, delta: -50, scope: .global, durationTicks: 10)],
            to: state, registry: reg
        )
        let after = TickEngine.advance(state, ticks: 10, registry: reg).state
        // Drip removed 50; population upkeep also consumed food, so just assert the drip cleared
        // and food dropped by at least the drip amount.
        #expect(after.scheduledEffects.isEmpty)
        #expect(after.settlements[0].storage[.food] <= 250)
    }
}
