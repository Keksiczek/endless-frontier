import Foundation

/// What two colonists are to each other.
public enum RelationKind: String, Codable, Sendable, Equatable {
    case friend
    case rival
    case partner
}

/// A bond between two colonists of the same settlement. Stored canonically
/// (`a` sorts before `b`), so the same pair never appears twice.
///
/// Bonds are live simulation state: chats strengthen friendships, quarrels
/// harden rivalries, strong friends may wed, and every bond fades a little
/// each tick unless life refreshes it.
public struct Relationship: Codable, Sendable, Equatable, Identifiable {
    public let a: UUID
    public let b: UUID
    public var kind: RelationKind
    /// How strong the bond is, 0…100.
    public var strength: Double
    /// When this couple last had a child, if they have.
    ///
    /// Children come out of a *bond* now rather than out of a per-colonist dice
    /// roll (see `PopulationEngine`), so the bond is the thing that remembers.
    /// It is what spaces a family: two people who had a child last spring are
    /// not looking for another one this autumn, and that is a fact about them
    /// rather than a cooldown bolted onto the pawn.
    public var lastChildTick: Int?

    public var id: String { "\(a.uuidString)~\(b.uuidString)" }

    public init(between first: UUID, and second: UUID, kind: RelationKind,
                strength: Double, lastChildTick: Int? = nil) {
        if first.uuidString <= second.uuidString {
            self.a = first
            self.b = second
        } else {
            self.a = second
            self.b = first
        }
        self.kind = kind
        self.strength = strength
        self.lastChildTick = lastChildTick
    }

    // MARK: - Codable (resilient: bonds had no memory of children at first)

    private enum CodingKeys: String, CodingKey { case a, b, kind, strength, lastChildTick }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        a = try c.decode(UUID.self, forKey: .a)
        b = try c.decode(UUID.self, forKey: .b)
        kind = try c.decode(RelationKind.self, forKey: .kind)
        strength = try c.decode(Double.self, forKey: .strength)
        lastChildTick = try c.decodeIfPresent(Int.self, forKey: .lastChildTick)
    }

    public func involves(_ id: UUID) -> Bool { a == id || b == id }

    /// The other colonist in the bond, if `id` is one of them.
    public func other(than id: UUID) -> UUID? {
        if a == id { return b }
        if b == id { return a }
        return nil
    }
}

public extension Settlement {
    /// All bonds a colonist has.
    func relationships(of pawnID: UUID) -> [Relationship] {
        relationships.filter { $0.involves(pawnID) }
    }

    /// The colonist's spouse, if they have one.
    func partnerID(of pawnID: UUID) -> UUID? {
        relationships.first { $0.kind == .partner && $0.involves(pawnID) }?.other(than: pawnID)
    }
}
