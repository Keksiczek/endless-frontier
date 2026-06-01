import Foundation

/// The progression eras. Raw values are stable identifiers used in JSON
/// game data (`era` fields on buildings, techs, events).
///
/// The integer `index` drives the tension "era ramp" and any ordering logic.
public enum Era: String, Codable, Sendable, CaseIterable, Comparable {
    case earlySettlement = "early_settlement"
    case ancient
    case medieval
    case earlyIndustrial = "early_industrial"
    case modern
    case nearFuture = "near_future"

    /// Zero-based ordering index. Earlier eras have lower indices.
    public var index: Int {
        Era.allCases.firstIndex(of: self) ?? 0
    }

    /// The era immediately after this one, or `nil` at the final era.
    public var next: Era? {
        let all = Era.allCases
        guard let i = all.firstIndex(of: self), i + 1 < all.count else { return nil }
        return all[i + 1]
    }

    public static func < (lhs: Era, rhs: Era) -> Bool {
        lhs.index < rhs.index
    }
}
