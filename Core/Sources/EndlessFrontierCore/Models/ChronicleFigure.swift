import Foundation

/// **Somebody the chronicle remembers by name.**
///
/// The annals could say a colony went from twenty-one souls to two hundred and
/// fifty-one and could not say who any of them were. `ColonyLog` is a
/// hundred-and-forty-entry ring — right for a diary, useless for a history that
/// spans two centuries — and `WorldRecord` is all aggregates. So a chronicle of
/// a civilisation had no people in it.
///
/// Deliberately four facts and nothing else. Every field here is paid for in
/// save size for the life of the world, and a name, a span and a reason is what
/// a line in an annal actually needs.
public struct ChronicleFigure: Codable, Sendable, Equatable, Identifiable {
    /// Why the chronicle noticed them at all.
    public enum Standing: String, Codable, Sendable {
        /// They were there when there was nothing.
        case founder
        /// They outlived nearly everybody.
        case elder

        public var label: LocalizedText {
            switch self {
            case .founder:
                return LocalizedText(values: [.en: "of the founding", .cs: "ze zakladatelů"])
            case .elder:
                return LocalizedText(values: [.en: "an elder", .cs: "kmet"])
            }
        }
    }

    /// The colonist's own id, so a figure and the pawn are the same person and
    /// nobody is remembered twice.
    public let id: UUID
    public let name: String
    /// May be negative: a founder was born before there was anywhere to be born.
    public let bornYear: Int
    /// `nil` while they are still alive.
    public var diedYear: Int?
    public var standing: Standing

    public init(id: UUID, name: String, bornYear: Int,
                diedYear: Int? = nil, standing: Standing) {
        self.id = id
        self.name = name
        self.bornYear = bornYear
        self.diedYear = diedYear
        self.standing = standing
    }

    public var isAlive: Bool { diedYear == nil }
    /// How long they lived, where the chronicle knows both ends.
    public var age: Int? { diedYear.map { $0 - bornYear } }
}
