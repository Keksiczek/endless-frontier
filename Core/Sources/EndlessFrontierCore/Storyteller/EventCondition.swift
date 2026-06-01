import Foundation

/// A predicate on world state that gates whether an event is eligible to
/// fire. Conditions are distinguished by which keys are present (the data
/// files do not use a `type` discriminator for conditions).
public enum EventCondition: Codable, Sendable, Equatable {
    case statMin(stat: StatPath, min: Double)
    case statMax(stat: StatPath, max: Double)
    case worldFlag(flag: String, present: Bool)
    case techResearched(String)
    case settlementCountMin(Int)

    private enum CodingKeys: String, CodingKey {
        case stat, min, max, worldFlag, present, techResearched, settlementCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        if c.contains(.techResearched) {
            self = .techResearched(try c.decode(String.self, forKey: .techResearched))
            return
        }
        if c.contains(.worldFlag) {
            let flag = try c.decode(String.self, forKey: .worldFlag)
            let present = try c.decodeIfPresent(Bool.self, forKey: .present) ?? true
            self = .worldFlag(flag: flag, present: present)
            return
        }
        if c.contains(.settlementCount) {
            let min = try c.decode(Int.self, forKey: .min)
            self = .settlementCountMin(min)
            return
        }
        if c.contains(.stat) {
            let stat = try c.decode(StatPath.self, forKey: .stat)
            if let minValue = try c.decodeIfPresent(Double.self, forKey: .min) {
                self = .statMin(stat: stat, min: minValue)
                return
            }
            if let maxValue = try c.decodeIfPresent(Double.self, forKey: .max) {
                self = .statMax(stat: stat, max: maxValue)
                return
            }
        }
        throw DecodingError.dataCorruptedError(
            forKey: .stat,
            in: c,
            debugDescription: "Unrecognised event condition shape"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .statMin(stat, min):
            try c.encode(stat, forKey: .stat)
            try c.encode(min, forKey: .min)
        case let .statMax(stat, max):
            try c.encode(stat, forKey: .stat)
            try c.encode(max, forKey: .max)
        case let .worldFlag(flag, present):
            try c.encode(flag, forKey: .worldFlag)
            try c.encode(present, forKey: .present)
        case let .techResearched(id):
            try c.encode(id, forKey: .techResearched)
        case let .settlementCountMin(min):
            try c.encode(true, forKey: .settlementCount)
            try c.encode(min, forKey: .min)
        }
    }
}
