import Foundation
import Testing
@testable import EndlessFrontierCore

/// Balance regression guard: auto-play a fresh world for a long stretch and
/// assert the colony stays healthy and the metrics stay sane. If a tuning
/// change makes basic play unsurvivable, these fail loudly.
@Suite("Balance harness")
struct BalanceTests {
    private func reg() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    @Test("A basically-managed colony survives a long run")
    func colonySurvives() throws {
        let r = try reg()
        let series = BalanceHarness.run(seed: 0xC0FFEE, ticks: 600, sampleEvery: 50, registry: r)
        let final = series.last!
        #expect(final.population > 0)        // not driven extinct by basic management
        #expect(final.tick >= 600)
    }

    @Test("Every sampled metric stays within sane bounds")
    func metricsStayBounded() throws {
        let r = try reg()
        let series = BalanceHarness.run(seed: 42, ticks: 500, sampleEvery: 50, registry: r)
        for s in series {
            #expect(s.threat >= 0 && s.threat <= 100)
            #expect(s.morale >= 0 && s.morale <= 100)
            #expect(s.stability >= 0 && s.stability <= 100)
            #expect(s.food >= 0)
            #expect(s.materials >= 0)
            #expect(s.population >= 0)
            #expect(!s.population.isNaN && !s.food.isNaN)
        }
    }

    @Test("The harness is deterministic for a given seed")
    func deterministic() throws {
        let r = try reg()
        let a = BalanceHarness.run(seed: 7, ticks: 300, sampleEvery: 50, registry: r)
        let b = BalanceHarness.run(seed: 7, ticks: 300, sampleEvery: 50, registry: r)
        #expect(a == b)
    }

    @Test("Different seeds produce different histories")
    func seedsDiverge() throws {
        let r = try reg()
        let a = BalanceHarness.run(seed: 1, ticks: 300, sampleEvery: 50, registry: r)
        let b = BalanceHarness.run(seed: 2, ticks: 300, sampleEvery: 50, registry: r)
        #expect(a != b)
    }
}
