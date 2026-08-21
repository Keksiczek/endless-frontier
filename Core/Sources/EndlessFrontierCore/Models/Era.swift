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

    /// What to call this age, in the player's language.
    ///
    /// Lives in the Core because the annals are written here now: a chapter
    /// heading is content, and content ships in every language the game speaks.
    /// The app reads this rather than keeping a second copy of the list.
    public var displayName: LocalizedText {
        switch self {
        case .earlySettlement:
            return LocalizedText(values: [.en: "Early Settlement", .cs: "Raná osada"])
        case .ancient:
            return LocalizedText(values: [.en: "Ancient", .cs: "Starověk"])
        case .medieval:
            return LocalizedText(values: [.en: "Medieval", .cs: "Středověk"])
        case .earlyIndustrial:
            return LocalizedText(values: [.en: "Early Industrial", .cs: "Raná industrializace"])
        case .modern:
            return LocalizedText(values: [.en: "Modern", .cs: "Moderní doba"])
        case .nearFuture:
            return LocalizedText(values: [.en: "Near Future", .cs: "Blízká budoucnost"])
        }
    }
}
