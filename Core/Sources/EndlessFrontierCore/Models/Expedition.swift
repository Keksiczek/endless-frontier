import Foundation

/// An in-progress journey to reveal an unknown region. One expedition runs at
/// a time (a deliberate mobile-friendly constraint). Stored on `WorldState`
/// so it advances during offline catch-up.
public struct Expedition: Codable, Sendable, Equatable {
    public let targetRegionID: UUID
    public var ticksRemaining: Int

    public init(targetRegionID: UUID, ticksRemaining: Int) {
        self.targetRegionID = targetRegionID
        self.ticksRemaining = ticksRemaining
    }
}
