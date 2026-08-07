import Foundation

/// Somebody who came to take the colony and did not walk home.
///
/// The third door into a village that cannot grow out of its own cradle
/// (§11.10), and the only one the colony *takes* rather than is offered. A
/// raid that breaks against the wall leaves people on the ground who are not
/// dead, and what happens to them next is a thing a colony decides.
///
/// A captive is deliberately **not** a `Pawn` in `Settlement.pawns`.
/// `Settlement.population` is derived from `pawns.count`, and forty-odd call
/// sites walk that array for labour, births, elections, jobs, housing and the
/// canvas — a captive flagged on a `Pawn` would need every one of them to
/// remember to skip it, and the first one that forgot would quietly marry the
/// prisoner off. They live in their own list until the day they stop being
/// captives, and on that day the whole `Pawn` moves across intact: the person
/// who joins the colony is the person who was carried in.
public struct Captive: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID { pawn.id }

    /// The person. Already a full colonist in every respect except belonging —
    /// a name, an age, genes and a trade — so conversion is a move between two
    /// arrays rather than an act of creation.
    public var pawn: Pawn
    /// Who they came with, so the journal can name it.
    public let takenFrom: String
    /// …and which people, when the attacker was a people at all. Nil is a
    /// warband nobody claims.
    public let takenFromTribeID: UUID?
    public let takenTick: Int

    /// How far round they have come: **−1 is out the gate the first dark
    /// night, +1 is one of us**.
    ///
    /// A slope rather than a countdown, because what moves it is what the
    /// colony is like to live in — fed, in good heart, and with something to
    /// believe in. A colony that wins its fights and then starves its prisoners
    /// does not gain people, and should not.
    public var trust: Double

    public init(pawn: Pawn, takenFrom: String, takenFromTribeID: UUID? = nil,
                takenTick: Int, trust: Double = 0) {
        self.pawn = pawn
        self.takenFrom = takenFrom
        self.takenFromTribeID = takenFromTribeID
        self.takenTick = takenTick
        self.trust = trust
    }

    // MARK: - Codable (resilient: every field optional with a sane default)

    private enum CodingKeys: String, CodingKey {
        case pawn, takenFrom, takenFromTribeID, takenTick, trust
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pawn = try c.decode(Pawn.self, forKey: .pawn)
        takenFrom = try c.decodeIfPresent(String.self, forKey: .takenFrom) ?? ""
        takenFromTribeID = try c.decodeIfPresent(UUID.self, forKey: .takenFromTribeID)
        takenTick = try c.decodeIfPresent(Int.self, forKey: .takenTick) ?? 0
        trust = try c.decodeIfPresent(Double.self, forKey: .trust) ?? 0
    }
}
