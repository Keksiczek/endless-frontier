import Foundation

/// Something the colony has been told to make.
///
/// Crafting used to be a button: press it and a sword appeared, out of nothing
/// but a stockpile, instantly, made by nobody, anywhere. The recipe named a
/// workshop and the colony required a workshop to stand — and no colonist could
/// ever be a person who worked in one, because there was no such trade. The
/// whole tree was a vending machine bolted to the side of a settlement.
///
/// An order is the other shape: a thing you *want*, put on a bench, that
/// somebody has to walk to and work at until it exists. It is a standing
/// instruction like every other lever in this game — you say what the colony
/// should make, not which colonist should make it this minute.
public struct CraftOrder: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let recipeID: String
    /// How many to make, or `nil` for a standing order that never finishes —
    /// "always be making arrows".
    public var wanted: Int?
    /// How many have come off the bench so far.
    public var made: Int
    /// Worker-ticks banked toward the next one.
    public var progress: Double
    /// Set aside without losing its place or its part-finished work.
    public var paused: Bool
    /// The tick it was put on the bench, so the oldest order is worked first
    /// and a queue is a queue rather than a shuffle.
    public let placedTick: Int

    public init(id: UUID, recipeID: String, wanted: Int? = 1,
                made: Int = 0, progress: Double = 0, paused: Bool = false,
                placedTick: Int = 0) {
        self.id = id
        self.recipeID = recipeID
        self.wanted = wanted.map { max(1, $0) }
        self.made = max(0, made)
        self.progress = max(0, progress)
        self.paused = paused
        self.placedTick = placedTick
    }

    /// Whether the colony has made everything it was asked for.
    public var isComplete: Bool {
        guard let wanted else { return false }   // a standing order never is
        return made >= wanted
    }

    /// How far through the one currently on the bench, 0…1.
    public func fraction(of workPerUnit: Double) -> Double {
        guard workPerUnit > 0 else { return 0 }
        return min(1, max(0, progress / workPerUnit))
    }

    /// What is left to make, when there is a number.
    public var remaining: Int? {
        guard let wanted else { return nil }
        return max(0, wanted - made)
    }

    private enum CodingKeys: String, CodingKey {
        case id, recipeID, wanted, made, progress, paused, placedTick
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        recipeID = try c.decode(String.self, forKey: .recipeID)
        wanted = try c.decodeIfPresent(Int.self, forKey: .wanted)
        made = try c.decodeIfPresent(Int.self, forKey: .made) ?? 0
        progress = try c.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        placedTick = try c.decodeIfPresent(Int.self, forKey: .placedTick) ?? 0
    }
}
