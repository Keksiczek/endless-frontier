import Foundation
import Testing
@testable import EndlessFrontierCore

/// The whole game is offline-catch-up: on foreground the world fast-forwards by
/// up to `maxOfflineTicks` (30 days). That has to stay fast even with every
/// inhabitant simulated as a pawn across several settlements — this guards it.
@Suite("Offline catch-up performance")
struct OfflineCatchUpTests {
    @Test("Catch-up cost stays linear in tick count (no O(n²) regression)")
    func catchUpScalesLinearly() throws {
        let registry = try GameDataRegistry.bundled()
        // Warm to a populated steady state so timing reflects a real colony.
        let warm = TickEngine.advance(GameWorldFactory.newGame(registry: registry, seed: 4242),
                                      ticks: 2000, registry: registry).state

        func time(ticks: Int) -> TimeInterval {
            let start = Date()
            _ = TickEngine.advance(warm, ticks: ticks, registry: registry)
            return Date().timeIntervalSince(start)
        }
        // Prime caches, then compare N vs 2N. Linear work ⇒ ratio ≈ 2.
        _ = time(ticks: 1000)
        let single = time(ticks: 4000)
        let double = time(ticks: 8000)
        // Allow generous slack for timer noise; a quadratic term would blow
        // well past this (ratio ≥ 4).
        #expect(double < single * 3.0)
    }

    @Test("A long offline catch-up produces a living, bounded world")
    func longOfflineCatchUp() throws {
        let registry = try GameDataRegistry.bundled()
        let world = GameWorldFactory.newGame(registry: registry, seed: 4242)

        // 12,000 ticks (~8 in-game years) is long enough to reach the housing
        // ceiling and prove the colony neither dies out nor grows unbounded.
        let result = TickEngine.advance(world, ticks: 12_000, registry: registry)

        #expect(result.state.tick == 12_000)
        #expect(result.state.totalPopulation > 0)
        // Bounded by housing: never runs away. Conception stops at capacity,
        // but pregnancies already carried come to term, so a modest overshoot
        // (larger while family-support laws are in force) is expected.
        let capital = result.state.settlements[0]
        let capacity = ResourceLoop.housingCapacity(capital, registry: registry)
        #expect(capital.population <= capacity * 1.3)
    }

    @Test("Catch-up is deterministic across the full offline window")
    func catchUpDeterministic() throws {
        let registry = try GameDataRegistry.bundled()
        let world = GameWorldFactory.newGame(registry: registry, seed: 77)
        let a = TickEngine.advance(world, ticks: 2000, registry: registry).state
        let b = TickEngine.advance(world, ticks: 2000, registry: registry).state
        #expect(a == b)
    }
}
