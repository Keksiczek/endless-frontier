import Foundation

/// A parsed reference to a stat or resource in the world, used by both
/// event conditions and effects.
///
/// String forms understood:
/// - `global.prosperity`, `global.stability`, `global.threatLevel`
/// - `global.food` … (a `ResourceType` raw value → aggregate across settlements)
/// - `settlement:all.morale`  (applies to / requires of every settlement)
/// - `settlement:any.stability` (requires at least one settlement)
/// - `settlement:closest.defense`
public struct StatPath: Codable, Sendable, Equatable {
    public enum Target: String, Sendable, Equatable {
        case global
        case settlementAll
        case settlementAny
        case settlementClosest
    }

    public let target: Target
    public let stat: String
    public let raw: String

    public init(target: Target, stat: String, raw: String) {
        self.target = target
        self.stat = stat
        self.raw = raw
    }

    public static func parse(_ string: String) -> StatPath {
        let parts = string.split(separator: ".", maxSplits: 1).map(String.init)
        let scopeToken = parts.first ?? ""
        let stat = parts.count > 1 ? parts[1] : ""
        let target: Target
        switch scopeToken {
        case "settlement:all": target = .settlementAll
        case "settlement:any": target = .settlementAny
        case "settlement:closest": target = .settlementClosest
        default: target = .global
        }
        return StatPath(target: target, stat: stat, raw: string)
    }

    /// `true` if `stat` names one of the five core resources.
    public var resource: ResourceType? {
        ResourceType(rawValue: stat)
    }

    // Codable as a single string.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = StatPath.parse(try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }
}
