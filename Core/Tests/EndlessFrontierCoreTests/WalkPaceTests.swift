import Testing
import Foundation
@testable import EndlessFrontierCore

/// **A rate in the wrong unit is an arithmetic mistake, not a balance choice.**
///
/// Everyday walking was written per *world tick* — `0.06` for a hauler, `0.09`
/// for somebody on an errand — while a world tick is two real minutes and about
/// six in-game days. So a colonist fetching a sack from the far side of the
/// village took sixteen ticks, three in-game months, half an hour of real time,
/// to cross a place you can see all of at once. Nothing in the simulation ever
/// complained: the food still arrived, the store still filled, and the only
/// symptom was that the working half of the town appeared to be standing still.
///
/// These pin the shape rather than the number, so the pace can be tuned without
/// silently sliding back into the wrong unit.
@Suite("How fast anybody walks")
struct WalkPaceTests {

    /// The whole colony is one unit square (`SettlementGeometry.span` in canvas
    /// terms). A person crosses that in minutes, not in seasons.
    @Test("Crossing the entire colony is a fraction of a world tick, not several")
    func aWalkIsSmallerThanATick() {
        let corner = LocalPoint(x: 0, y: 0)
        let opposite = LocalPoint(x: 1, y: 1)
        let across = SiegeField.distance(corner, opposite)
        let steps = WalkPace.steps(for: across)
        let ticks = Double(steps) / Double(WorldClock.actionStepsPerTick)
        #expect(ticks < 3,
                """
                the longest walk on the map costs \(steps) steps — \
                \(String(format: "%.1f", ticks)) world ticks, \
                \(String(format: "%.0f", ticks * 120)) real seconds of somebody \
                crossing the screen too slowly to see
                """)
    }

    /// The ordinary case, and the one the eye judges: a trip a fifth of the map
    /// long — a field to a granary, a stump to the woodshed.
    @Test("An ordinary trip across town is a handful of steps")
    func anOrdinaryTripIsWatchable() {
        let steps = WalkPace.steps(for: 0.2)
        #expect(steps >= 2, "a trip that resolves in one step cannot be watched at all")
        #expect(steps <= 5, "\(steps) steps is \(steps * 15) real seconds for two hundred metres")
    }

    /// Loaded is slower than empty-handed — but by a quarter, not by an order
    /// of magnitude nobody chose.
    @Test("A load slows you down without putting you on a different clock")
    func carryingIsSlowerButComparable() {
        #expect(WalkPace.carryingPerStep < WalkPace.perStep)
        #expect(WalkPace.carryingPerStep > WalkPace.perStep / 2)
        #expect(HaulEngine.carrySpeed == WalkPace.carryingPerStep)
        #expect(HaulEngine.emptySpeed == WalkPace.perStep)
        #expect(ErrandEngine.pace == WalkPace.perStep)
    }

    /// A walk that arrives on the step it left is a teleport, and
    /// `WalkPath.position(at:)` would divide by nothing.
    @Test("No walk takes zero steps, however short")
    func nothingTeleports() {
        #expect(WalkPace.steps(for: 0) == 1)
        #expect(WalkPace.steps(for: 0.0001) == 1)
        #expect(WalkPace.steps(for: 1, pace: 0) >= 1, "and a pace of nothing does not divide by it")
    }

    /// The two clocks have to stay tied together, or `perTick` quietly becomes
    /// a second, disagreeing constant.
    @Test("The tick pace is the step pace, eight times")
    func theClocksAgree() {
        #expect(WalkPace.perTick == WalkPace.perStep * Double(WorldClock.actionStepsPerTick))
    }

    /// A battle line closes more warily than a hauler walks, which is a
    /// deliberate difference — but they are on the *same clock*, which is what
    /// stopped being true when walking was measured per tick.
    @Test("A fighter and a hauler are measured against the same clock")
    func combatAndWalkingSharePerStep() {
        #expect(SiegeEngine.pace < WalkPace.perStep, "a line advances warily")
        #expect(SiegeEngine.pace > WalkPace.perStep / 4,
                "…but not so warily that a raid takes an in-game month to reach the wall")
    }
}
