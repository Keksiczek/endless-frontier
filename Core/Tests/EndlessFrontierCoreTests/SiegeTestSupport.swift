import Foundation
@testable import EndlessFrontierCore

/// Runs any live siege out to its end.
///
/// A raid used to be settled inside `DiplomacyEngine.raid`, so a test could
/// declare one and read the outcome on the next line. It opens a `Siege` now —
/// a fight with its middle left open so the player can stand in it — and the
/// outcome exists once the action clock has carried it to the end.
///
/// This is the same path a player who closed the app takes: nobody gives an
/// order, the world clock walks over the top, and the fighting happens exactly
/// as it would have.
enum SiegeTestSupport {
    static func fightItOut(
                /// Generous by default: a fight runs until a side breaks now, not
        /// until a clock expires, so "fight it out" cannot be a fixed number of
        /// ticks any more. It stops as soon as the siege is over.
        _ world: WorldState, registry: GameDataRegistry, ticks: Int = 60
    ) -> WorldState {
        var s = world
        let start = s.tick
        for tick in start..<(start + max(1, ticks)) {
            for step in 0..<WorldClock.actionStepsPerTick {
                s = ActionLoop.advanceStep(
                    s, clock: WorldClock(tick: tick, step: step), registry: registry)
            }
            if s.settlements.allSatisfy({ $0.siege == nil }) { break }
        }
        return s
    }
}
