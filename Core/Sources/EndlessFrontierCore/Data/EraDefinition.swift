import Foundation

/// A requirement that must be met to advance into the era it belongs to.
/// Tagged union keyed on `type`.
public enum EraMilestone: Codable, Sendable, Equatable {
    case techResearched(String)
    case globalStat(stat: String, min: Double)
    case settlementCount(min: Int)
    case populationTotal(min: Double)

    private enum CodingKeys: String, CodingKey {
        case type, techId, stat, min
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "tech_researched":
            self = .techResearched(try c.decode(String.self, forKey: .techId))
        case "global_stat":
            let stat = try c.decode(String.self, forKey: .stat)
            let min = try c.decode(Double.self, forKey: .min)
            self = .globalStat(stat: stat, min: min)
        case "settlement_count":
            self = .settlementCount(min: try c.decode(Int.self, forKey: .min))
        case "population_total":
            self = .populationTotal(min: try c.decode(Double.self, forKey: .min))
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "Unknown milestone type: \(other)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .techResearched(id):
            try c.encode("tech_researched", forKey: .type)
            try c.encode(id, forKey: .techId)
        case let .globalStat(stat, min):
            try c.encode("global_stat", forKey: .type)
            try c.encode(stat, forKey: .stat)
            try c.encode(min, forKey: .min)
        case let .settlementCount(min):
            try c.encode("settlement_count", forKey: .type)
            try c.encode(min, forKey: .min)
        case let .populationTotal(min):
            try c.encode("population_total", forKey: .type)
            try c.encode(min, forKey: .min)
        }
    }
}

/// The milestones required to *enter* a given era. Loaded from `eras.json`.
public struct EraDefinition: Codable, Sendable, Identifiable, Equatable {
    public let era: Era
    public let milestones: [EraMilestone]

    public var id: Era { era }

    public init(era: Era, milestones: [EraMilestone]) {
        self.era = era
        self.milestones = milestones
    }
}
