import Testing
import Foundation
import EndlessFrontierCore
@testable import EndlessFrontier

/// **Which clock a live fight is drawn on.**
///
/// A raid stops the world for the player to answer it, and the siege loop goes
/// on resolving a step every second and a half regardless — so the world clock
/// is the one thing on the screen that is *not* moving while the fight is. The
/// old sub-step reading measured the share of a step elapsed against it anyway:
/// the subtraction went negative inside the first dozen seconds, clamped to
/// zero and stayed there for the rest of the raid. Every arrow, every jolt and
/// every stride was then stamped at the same instant of its step for ever.
/// Keks, watching a staged one: *"boj se seká po několika vteřinách."*
///
/// This is the shape rule 34 describes — a rate measured in the wrong unit —
/// and it is invisible to every test that asks whether the *fight* is right,
/// because the fight always was.
@Suite("A fight is drawn on the clock its steps land on")
struct BattleBeatTests {

    private func siege(step: Int) -> Siege {
        var s = Siege(
            id: UUID(uuidString: "B0A70000-0000-0000-0000-000000000001")!,
            startTick: 100, openedAt: 800,
            attackerName: "Raiders", approach: 0, attackers: 12,
            openingStrength: 60, fortification: 10, seed: 0xBEEF, line: [])
        s.advancedTo = s.openedAt + step
        return s
    }

    /// The step is 1.4 real seconds long, so `time` here is seconds since
    /// `DayClock.epoch` — the unit the renderer measures in.
    private func beat(step: Int, at: Double, seconds: Double = 1.4)
    -> SettlementBattle.Beat {
        SettlementBattle.Beat(step: step, at: at, seconds: seconds)
    }

    @Test("A stalled world clock no longer freezes the fight")
    func aPausedWorldStillDrawsAWalk() {
        let fighting = siege(step: 20)
        // The world stopped at tick 100 when the raid began; the siege has since
        // been carried twenty steps by its own loop, so the world clock reads
        // hopelessly behind. This is the exact state a paused raid is in.
        let stalledTick = 101.0

        // The old reading: pinned, whatever moment of the step it is asked at.
        #expect(SettlementBattle.withinStep(of: fighting,
                                            continuousTick: stalledTick) == 0)

        // The beat: the step lands, and the drawing walks across it.
        let landed = 5_000.0
        let start = SettlementBattle.within(fighting, beat: beat(step: fighting.step, at: landed),
                                            time: landed, continuousTick: stalledTick)
        let half = SettlementBattle.within(fighting, beat: beat(step: fighting.step, at: landed),
                                           time: landed + 0.7, continuousTick: stalledTick)
        let end = SettlementBattle.within(fighting, beat: beat(step: fighting.step, at: landed),
                                          time: landed + 1.4, continuousTick: stalledTick)
        #expect(start == 0)
        #expect(abs(half - 0.5) < 1e-9)
        #expect(end == 1)
    }

    @Test("A step that overruns its beat stops at its end, it does not overshoot")
    func theWalkStopsWhenItArrives() {
        let fighting = siege(step: 3)
        let landed = 5_000.0
        let late = SettlementBattle.within(fighting, beat: beat(step: 3, at: landed),
                                           time: landed + 9, continuousTick: 101)
        #expect(late == 1)
    }

    /// A beat left over from an earlier step is not evidence about this one —
    /// a stale stamp believed would replay the last stride from the top.
    @Test("A beat for another step is not believed")
    func staleBeatsAreIgnored() {
        let fighting = siege(step: 7)
        let stale = SettlementBattle.within(
            fighting, beat: beat(step: 3, at: 5_000), time: 5_000.2,
            continuousTick: 101)
        #expect(stale == SettlementBattle.withinStep(of: fighting, continuousTick: 101))
    }

    /// The world-clock reading is still right for the case it was written for:
    /// a fight in a settlement nobody is watching, carried by `ActionLoop`.
    @Test("With no beat, the world clock still carries an unwatched fight")
    func theWorldClockStillWorksWithoutABeat() {
        let fighting = siege(step: 4)
        let perTick = Double(WorldClock.actionStepsPerTick)
        let resolvedAt = Double(fighting.advancedTo) / perTick
        let half = SettlementBattle.within(fighting, beat: nil, time: 0,
                                           continuousTick: resolvedAt + 0.5 / perTick)
        #expect(abs(half - 0.5) < 1e-9)
    }

    /// The progress the phase, the caption and every beat's age are read off
    /// has to move *between* steps too — an arrow whose whole flight is 7% of
    /// one step never leaves the bow otherwise.
    @Test("Progress climbs between two steps, not only at them")
    func progressMovesInsideAStep() {
        let fighting = siege(step: 10)
        let at = SettlementBattle.liveProgress(of: fighting, within: 0)
        let later = SettlementBattle.liveProgress(of: fighting, within: 0.5)
        #expect(later > at)
        #expect(later - at > 0)
        // Half a step of a fight, and no more.
        let next = SettlementBattle.liveProgress(of: siege(step: 11), within: 0)
        #expect(abs((later - at) - (next - later)) < 1e-9)
    }
}
