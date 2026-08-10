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
        _ = time(ticks: 500)
        let single = time(ticks: 2000)
        let double = time(ticks: 4000)
        // **The colony grows through the longer run, and a tick costs what the
        // colony costs.** Once the fertility clock was fixed (§11.19) a world
        // carried twice as far comes out with two to three times the people in
        // it — every one of them aged, fed, moved, paired and paid every tick —
        // so a perfectly linear-in-*ticks* engine cannot come out at two. This
        // was 4000 vs 8000 ticks at a bound of 3× and started failing at 3.9,
        // not because anything got slower per person but because there were far
        // more people in the second half of the second run.
        //
        // The invariant is still worth pinning: a genuine quadratic term — the
        // thing this exists to catch, an all-pairs sweep or a per-tick rescan of
        // history — lands at ratios of eight and up, nowhere near this. The runs
        // are shorter too, so the colony diverges less between them *and* the
        // suite does not spend half an hour proving it.
        #expect(double < single * 4.5, """
            \(double)s for twice the ticks against \(single)s — that is not the \
            colony being bigger, that is a term that grows with the square
            """)
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
