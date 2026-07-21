import Foundation

/// The world runs on two clocks.
///
/// It used to run on one, and that one tick had to be everything at once: a
/// colonist's whole working day, a sixtieth of their aging, and an entire
/// battle from the first arrow to the last body. Anything that wanted to
/// *happen over time* — a fight, a march, a shift at the seam — had nowhere
/// finer to happen in, so it collapsed into a single arithmetic step and the
/// player was handed a result instead of watching an event.
///
/// So:
///
/// - **World tick** — the civilisation's clock. Harvests, births, wages,
///   seasons, laws, diplomacy, the chronicle. `WorldState.tick` counts these,
///   and `ticksPerYear` still measures years in them, so every number the game
///   is balanced on keeps its meaning.
/// - **Action step** — the *inside* of a world tick, and the unit of things
///   people do: a round of a fight, a stage of a march, a stint at the rock
///   face. `actionStepsPerTick` of them make one world tick.
///
/// Both are integers and both are simulated. This is deliberately not the same
/// as the canvas's frame interpolation (`TickClock` in the app): that smooths
/// *drawing* between whole ticks and is allowed to be approximate. This is the
/// simulation's own finer grain — deterministic, saved, and identical whether
/// or not anybody is watching.
public struct WorldClock: Codable, Sendable, Equatable, Hashable {
    /// How many action steps subdivide one world tick.
    ///
    /// Eight because that is what a fight needs to have a shape — an opening,
    /// a few exchanges, and an end — and everything else that resolves inside
    /// a tick fits comfortably in the same grid.
    public static let actionStepsPerTick = 8

    /// The world tick this moment belongs to.
    public let tick: Int
    /// Which action step inside that tick, `0 ..< actionStepsPerTick`.
    public let step: Int

    public init(tick: Int, step: Int = 0) {
        self.tick = tick
        self.step = min(max(0, step), Self.actionStepsPerTick - 1)
    }

    /// Where this moment falls inside its world tick, `0…1`. What presentation
    /// interpolates against.
    public var position: Double {
        (Double(step) + 0.5) / Double(Self.actionStepsPerTick)
    }

    /// The absolute action step since the world began — a single monotonic
    /// number for ordering anything against anything.
    public var absoluteStep: Int { tick * Self.actionStepsPerTick + step }

    /// The next action step, rolling into the following world tick.
    public func advanced() -> WorldClock {
        step + 1 < Self.actionStepsPerTick
            ? WorldClock(tick: tick, step: step + 1)
            : WorldClock(tick: tick + 1, step: 0)
    }

    /// The clock at the start of a world tick.
    public static func start(of tick: Int) -> WorldClock { WorldClock(tick: tick, step: 0) }

    /// Rebuilds a clock from an absolute step count.
    public static func at(absoluteStep: Int) -> WorldClock {
        let steps = actionStepsPerTick
        let tick = Int((Double(absoluteStep) / Double(steps)).rounded(.down))
        return WorldClock(tick: tick, step: absoluteStep - tick * steps)
    }
}
