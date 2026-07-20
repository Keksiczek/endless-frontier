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

    public var id: String { "\(a.uuidString)~\(b.uuidString)" }

    public init(between first: UUID, and second: UUID, kind: RelationKind, strength: Double) {
        if first.uuidString <= second.uuidString {
            self.a = first
            self.b = second
        } else {
            self.a = second
            self.b = first
        }
        self.kind = kind
        self.strength = strength
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
