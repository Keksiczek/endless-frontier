import Foundation

/// A world change that unfolds over time rather than instantly:
/// - a `resource` drip applies `perTick` for `ticksRemaining` ticks
///   (used by `resource_delta` effects with `duration_ticks`),
/// - a `triggerEvent` fires another event template at `firesAtTick`
///   (used by `trigger_event` effects with `delay_ticks`).
///
/// Stored on `WorldState` so the schedule survives offline catch-up and
/// persistence, preserving determinism.
public struct ScheduledEffect: Codable, Sendable, Equatable {
    public enum Kind: Codable, Sendable, Equatable {
        case resource(resource: ResourceType, perTick: Double, scope: StatPath.Target)
        case triggerEvent(eventID: String)
    }

    public var kind: Kind
    /// For `triggerEvent`: the tick at which it should fire.
    public var firesAtTick: Int
    /// For `resource`: remaining ticks to apply the drip.
    public var ticksRemaining: Int

    public init(kind: Kind, firesAtTick: Int = 0, ticksRemaining: Int = 0) {
        self.kind = kind
        self.firesAtTick = firesAtTick
        self.ticksRemaining = ticksRemaining
    }
}
