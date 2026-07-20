import Foundation

/// The four seasons of the in-game year. Purely derived from the world tick —
/// never stored — so the calendar stays deterministic and free to recompute.
///
/// A year is `config.ticksPerYear` ticks long and divides into four equal
/// seasons, starting in spring at tick 0.
public enum Season: Int, Codable, Sendable, CaseIterable, Equatable {
    case spring = 0
    case summer = 1
    case autumn = 2
    case winter = 3

    /// The season a given tick falls in.
    public init(tick: Int, ticksPerYear: Int) {
        guard ticksPerYear >= 4 else {
            self = .spring
            return
        }
        let tickOfYear = ((tick % ticksPerYear) + ticksPerYear) % ticksPerYear
        let seasonLength = ticksPerYear / 4
        let index = min(3, tickOfYear / seasonLength)
        self = Season(rawValue: index) ?? .spring
    }

    /// Completed in-game years at a given tick (year 0 = the founding year).
    public static func year(tick: Int, ticksPerYear: Int) -> Int {
        guard ticksPerYear > 0 else { return 0 }
        return max(0, tick / ticksPerYear)
    }
}

public extension WorldState {
    /// The current season of this world under the given tuning.
    func season(_ config: WorldConfig) -> Season {
        Season(tick: tick, ticksPerYear: config.ticksPerYear)
    }

    /// The current in-game year of this world under the given tuning.
    func year(_ config: WorldConfig) -> Int {
        Season.year(tick: tick, ticksPerYear: config.ticksPerYear)
    }
}
