import Foundation

/// The inside of a world tick.
///
/// `TickEngine` runs the civilisation: harvests, births, wages, seasons, laws.
/// Those are world-tick things and they stay exactly where they were. This runs
/// the *other* kind of thing — what people are physically doing — on the finer
/// grid `WorldClock` defines, so a march, a shift and a fight advance several
/// times inside the tick the harvest lands on.
///
/// Why it matters beyond tidiness: a party used to cross the valley in whole
/// world-tick jumps, and the canvas covered for it by interpolating between
/// them. That interpolation was a guess about a position the simulation never
/// held. Now the position exists, at eight times the resolution, and the
/// drawing is a reading of the world rather than a plausible story about it.
///
/// Deterministic like everything else: every system here is a pure function of
/// `(state, clock, registry)`.
public enum ActionLoop {
    /// Advances one action step. Called `WorldClock.actionStepsPerTick` times
    /// per world tick, before the world systems settle the tick.
    public static func advanceStep(
        _ state: WorldState, clock: WorldClock, registry: GameDataRegistry
    ) -> WorldState {
        var s = state
        s.settlements = s.settlements.map { settlement in
            LocalPOIEngine.advanceStep(settlement, clock: clock,
                                       mapSeed: s.mapSeed, registry: registry)
        }
        return s
    }
}
