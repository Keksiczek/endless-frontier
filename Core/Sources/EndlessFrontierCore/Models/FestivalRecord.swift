import Foundation

/// **What a midsummer was like**, kept so it can be drawn.
///
/// `FestivalEngine` spends the larder, lifts everybody's mood and writes a line
/// in the journal — all inside one tick, leaving nothing behind. So the fires
/// the whole colony gathers at were a thing the simulation did and the canvas
/// had no way to show (rule 18). This is the two numbers a picture needs: when,
/// and how good it was.
public struct FestivalRecord: Codable, Sendable, Equatable {
    /// The tick the fires were lit on.
    public let tick: Int
    /// 0…1 — what the larder could put on the table against what the colony
    /// wanted. Below `FestivalEngine.leanBelow` it is a lean year, and the
    /// drawing should be as thin as the feast was.
    public let lavishness: Double

    public init(tick: Int, lavishness: Double) {
        self.tick = tick
        self.lavishness = max(0, min(1, lavishness))
    }
}
