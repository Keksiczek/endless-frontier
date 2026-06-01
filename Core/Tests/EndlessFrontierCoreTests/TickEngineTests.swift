import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Tick engine")
struct TickEngineTests {
    @Test("Advancing N ticks increments the tick counter by N")
    func tickCounter() {
        let registry = Fixtures.registry()
        let state = Fixtures.world()
        let result = TickEngine.advance(state, ticks: 25, registry: registry)
        #expect(result.state.tick == 25)
    }

    @Test("Zero or negative ticks is a no-op")
    func noOpForZeroTicks() {
        let registry = Fixtures.registry()
        let state = Fixtures.world()
        #expect(TickEngine.advance(state, ticks: 0, registry: registry).state == state)
        #expect(TickEngine.advance(state, ticks: -5, registry: registry).state == state)
    }

    @Test("Elapsed ticks derive from real seconds and are capped")
    func elapsedTicks() {
        var config = WorldConfig.default
        config.realSecondsPerTick = 60
        config.maxOfflineTicks = 100
        let start = Date(timeIntervalSince1970: 0)

        #expect(TickEngine.ticksElapsed(since: start, until: start.addingTimeInterval(600), config: config) == 10)
        // Cap applies: 1_000_000 s / 60 ≈ 16666 → clamped to 100.
        #expect(TickEngine.ticksElapsed(since: start, until: start.addingTimeInterval(1_000_000), config: config) == 100)
        // Clock skew (now before last) yields 0.
        #expect(TickEngine.ticksElapsed(since: start, until: start.addingTimeInterval(-100), config: config) == 0)
    }

    @Test("openSession advances by elapsed time and stamps the timestamp")
    func openSessionAdvances() {
        let registry = Fixtures.registry()
        var state = Fixtures.world()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        state.lastRealTimestamp = t0
        let now = t0.addingTimeInterval(registry.config.realSecondsPerTick * 5)

        let result = GameEngine.openSession(state, now: now, registry: registry)
        #expect(result.state.tick == 5)
        #expect(result.state.lastRealTimestamp == now)
    }
}
