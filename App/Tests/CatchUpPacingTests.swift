import Testing
import Foundation
@testable import EndlessFrontier

/// **A progress bar that does not move is a spinner with extra steps.**
///
/// `GameEngine.openSession` reports after each slice, and the slice was a flat
/// 240 ticks. A tick costs roughly what the colony costs to walk, so the
/// default was written against a colony of twenty-odd and quietly became a
/// minute of silence at a hundred and sixty. Watched on a real save at year
/// 155: the overlay read *"0 years · 0%"* for about forty seconds — which is
/// the exact symptom the bar was added to cure.
///
/// The slice is sized by pawn count now. These pin the shape of that curve
/// rather than the numbers in it, so the budget can be retuned without
/// rewriting the suite — except the clamps, which are the whole point.
@Suite("Catch-up pacing")
struct CatchUpPacingTests {

    @Test("A small colony keeps the slice it always had")
    func smallColonyUnchanged() {
        // The old flat default, at the size it was written for.
        #expect(GameViewModel.sliceTicks(forPawns: 40) == 240)
        #expect(GameViewModel.sliceTicks(forPawns: 12) == 240)
        #expect(GameViewModel.sliceTicks(forPawns: 1) == 240)
    }

    @Test("A big colony gets a slice it can finish")
    func bigColonyIsSliced() {
        let small = GameViewModel.sliceTicks(forPawns: 40)
        let big = GameViewModel.sliceTicks(forPawns: 160)
        #expect(big < small, "160 colonists must not wait on a 40-colonist slice")
        // The save this was found on. A quarter of the work per reading.
        #expect(big == 60)
    }

    @Test("The slice never reaches zero, however big the colony")
    func neverStalls() {
        for pawns in [500, 5_000, 100_000] {
            #expect(GameViewModel.sliceTicks(forPawns: pawns) >= 16,
                    "a slice of nothing never finishes the catch-up")
        }
    }

    @Test("An empty world does not divide by zero")
    func noColonists() {
        #expect(GameViewModel.sliceTicks(forPawns: 0) == 240)
    }

    /// The property that makes the whole thing safe to vary: **work per slice
    /// stays roughly constant**, which is why the bar moves at the same pace
    /// whatever the colony has grown to. Sampled across two orders of
    /// magnitude, inside the clamps.
    @Test("Work per reading of the bar stays about the same", arguments: [40, 60, 100, 160, 240, 480])
    func constantWorkPerSlice(pawns: Int) {
        let work = GameViewModel.sliceTicks(forPawns: pawns) * pawns
        // Integer division makes this approximate rather than exact.
        #expect(work >= 240 * 40 * 8 / 10)
        #expect(work <= 240 * 40 * 12 / 10)
    }

    /// **The slice sizes itself to the clock, not to a head-count.**
    ///
    /// Head-count was a proxy for what a tick costs, fixed at the start of an
    /// absence the colony grows all the way through. Timing the last slice is
    /// the measurement itself: aim at a couple of frames, correct by the ratio,
    /// and never move by more than half or double in one step so one throttled
    /// slice does not send the size to an end.
    @Test("A slow slice shrinks the next one, a fast slice grows it")
    func slicesFollowTheClock() {
        let slow = GameViewModel.resized(240, took: 4.0)
        #expect(slow < 240, "four seconds a slice and the next one is no smaller")
        #expect(slow >= GameViewModel.minSlice)
        #expect(slow >= 120, "one slow slice must not send the size to the floor")

        let fast = GameViewModel.resized(240, took: 0.001)
        #expect(fast > 240, "a slice that costs nothing stays small for ever")
        #expect(fast <= 480, "and does not double twice in one step")
        #expect(fast <= GameViewModel.maxSlice)

        // On target, it holds — a size that oscillates around the right answer
        // reports at an uneven pace, which reads worse than a slower steady one.
        let steady = GameViewModel.resized(240, took: GameViewModel.sliceSeconds)
        #expect(steady == 240)
    }
}
