import Foundation

/// A settlement's economic vocation. Specialising trades breadth for a sharp
/// production edge in one direction, plus small standing-stat consequences.
/// `balanced` is the neutral default and applies no modifiers, so an
/// unspecialised settlement behaves exactly as before.
///
/// This is a fixed mechanical set (like `SettlementKind`) rather than JSON
/// content; the tuning lives in `profile` so it stays in one place.
public enum SettlementSpecialization: String, Codable, Sendable, CaseIterable, Equatable {
    case balanced
    case agricultural
    case industrial
    case scholarly
    case fortified
    case mercantile

    public var displayName: String {
        switch self {
        case .balanced: return "Balanced"
        case .agricultural: return "Agricultural"
        case .industrial: return "Industrial"
        case .scholarly: return "Scholarly"
        case .fortified: return "Fortified"
        case .mercantile: return "Mercantile"
        }
    }

    /// A one-line player-facing summary of the trade-off.
    public var summary: String {
        switch self {
        case .balanced: return "No bonuses, no penalties."
        case .agricultural: return "+50% food, but materials output suffers."
        case .industrial: return "+50% materials & +20% energy, but dirtier."
        case .scholarly: return "+60% knowledge, less food."
        case .fortified: return "Strong standing defense, slower materials."
        case .mercantile: return "+50% influence and +30% trade-route throughput."
        }
    }

    /// The mechanical effect of the specialisation.
    public var profile: SpecializationProfile {
        switch self {
        case .balanced:
            return SpecializationProfile()
        case .agricultural:
            return SpecializationProfile(production: [.food: 1.5, .materials: 0.85])
        case .industrial:
            return SpecializationProfile(production: [.materials: 1.5, .energy: 1.2], pollutionFlat: 8)
        case .scholarly:
            return SpecializationProfile(production: [.knowledge: 1.6, .food: 0.9])
        case .fortified:
            return SpecializationProfile(production: [.materials: 0.9], defenseFlat: 12)
        case .mercantile:
            return SpecializationProfile(production: [.influence: 1.5], tradeThroughput: 1.3)
        }
    }
}

/// Tunable modifiers a specialisation applies. Defaults are all-neutral so the
/// `balanced` case (and any unspecified resource) leaves the economy untouched.
public struct SpecializationProfile: Sendable, Equatable {
    /// Per-resource multiplier applied to *gross* building production.
    public let production: [ResourceType: Double]
    /// Added to the settlement's pollution target (industrial runs dirtier).
    public let pollutionFlat: Double
    /// Added to the settlement's defense target (a standing garrison).
    public let defenseFlat: Double
    /// Multiplier on the volume carried by trade routes *originating* here.
    public let tradeThroughput: Double

    public init(
        production: [ResourceType: Double] = [:],
        pollutionFlat: Double = 0,
        defenseFlat: Double = 0,
        tradeThroughput: Double = 1
    ) {
        self.production = production
        self.pollutionFlat = pollutionFlat
        self.defenseFlat = defenseFlat
        self.tradeThroughput = tradeThroughput
    }

    /// The production multiplier for a resource (1.0 when unspecified).
    public func productionMultiplier(_ resource: ResourceType) -> Double {
        production[resource] ?? 1
    }
}
