import Foundation

/// How fast anybody crosses their own colony.
///
/// One number, because there was not one. A hauler moved at `0.06`, somebody on
/// an errand at `0.09`, a fighter closing on a raider at `0.030`, and the drawn
/// day at `4.5` — four rates in three different units that happened to share a
/// screen. The first two were **per world tick**, and a world tick is two real
/// minutes and about six in-game days, so a colonist fetching a sack from the
/// far side of the village took sixteen ticks — three in-game months, half an
/// hour of real time — to walk across a place you can see all of at once.
///
/// On the canvas that is a person covering about one and a half points a
/// second, which is under the eye's threshold for motion. The figures were
/// never frozen; they were walking **thirty times slower than the colonist
/// standing next to them**, and reading as furniture. Everything else on the
/// screen — the day-clock walkers, the battle line — was fine, which is why
/// this looked like a rendering fault and was not one.
///
/// So walking is measured on the **action step** (`WorldClock`), not on the
/// world tick, and the pace is set from the thing being modelled rather than
/// from the unit it happened to be written in: a person crosses a village in a
/// few minutes, which is a *fraction* of a tick, not several of them. A typical
/// trip — a fifth of the map — is two or three steps.
///
/// Rule 14's cousin, and worth writing down: a rate expressed in the wrong unit
/// is not a balance choice, it is an arithmetic mistake wearing one. Check what
/// a number is *per* before deciding whether it is too small.
public enum WalkPace {

    /// How far a colonist covers in one action step, in local-map units.
    ///
    /// Crossing the whole valley takes about twelve and a half of them, which is
    /// a tick and a half — a few real minutes for the longest walk on the map,
    /// and a few tens of seconds for an ordinary one. Distance still costs time,
    /// which was always the point (`WalkPath`); it just costs an amount of time
    /// a person would recognise.
    public static let perStep: Double = 0.08

    /// …and how far they get with a load on their back.
    ///
    /// Slower, because a sack of grain is heavy and the walk home should cost
    /// more than the walk out — but on the same clock, so the difference is a
    /// quarter rather than an order of magnitude nobody chose.
    public static let carryingPerStep: Double = 0.06

    /// The same pace against the civilisation's clock, for anything still
    /// counting in whole ticks.
    public static var perTick: Double {
        perStep * Double(WorldClock.actionStepsPerTick)
    }

    /// How many action steps a walk of `distance` takes at `pace`. Never zero:
    /// a walk that arrives on the step it left is a teleport.
    public static func steps(for distance: Double, pace: Double = perStep) -> Int {
        max(1, Int((distance / max(0.0001, pace)).rounded(.up)))
    }
}
