import Foundation

/// A concrete change applied to the world when an event fires or a choice
/// is taken. Decoded from a tagged union keyed on `type`.
public enum EventEffect: Codable, Sendable, Equatable {
    case resourceDelta(resource: ResourceType, delta: Double, scope: StatPath.Target, durationTicks: Int?)
    case statDelta(stat: StatPath, delta: Double)
    case unlockTech(techID: String)
    case triggerEvent(eventID: String, delayTicks: Int)
    case setWorldFlag(flag: String, value: Bool)

    private enum CodingKeys: String, CodingKey {
        case type
        case resource
        case delta
        case scope
        case durationTicks = "duration_ticks"
        case stat
        case techID = "techId"
        case eventID = "eventId"
        case delayTicks = "delay_ticks"
        case flag
        case value
    }

    private static func scope(from raw: String?) -> StatPath.Target {
        switch raw {
        case "settlement:all": return .settlementAll
        case "settlement:any": return .settlementAny
        case "settlement:closest": return .settlementClosest
        default: return .global
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "resource_delta":
            let resource = try c.decode(ResourceType.self, forKey: .resource)
            let delta = try c.decode(Double.self, forKey: .delta)
            let scopeRaw = try c.decodeIfPresent(String.self, forKey: .scope)
            let duration = try c.decodeIfPresent(Int.self, forKey: .durationTicks)
            self = .resourceDelta(
                resource: resource,
                delta: delta,
                scope: EventEffect.scope(from: scopeRaw),
                durationTicks: duration
            )
        case "stat_delta":
            let stat = try c.decode(StatPath.self, forKey: .stat)
            let delta = try c.decode(Double.self, forKey: .delta)
            self = .statDelta(stat: stat, delta: delta)
        case "unlock_tech":
            self = .unlockTech(techID: try c.decode(String.self, forKey: .techID))
        case "trigger_event":
            let id = try c.decode(String.self, forKey: .eventID)
            let delay = try c.decodeIfPresent(Int.self, forKey: .delayTicks) ?? 0
            self = .triggerEvent(eventID: id, delayTicks: delay)
        case "set_world_flag":
            let flag = try c.decode(String.self, forKey: .flag)
            let value = try c.decodeIfPresent(Bool.self, forKey: .value) ?? true
            self = .setWorldFlag(flag: flag, value: value)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: c,
                debugDescription: "Unknown event effect type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .resourceDelta(resource, delta, scope, duration):
            try c.encode("resource_delta", forKey: .type)
            try c.encode(resource, forKey: .resource)
            try c.encode(delta, forKey: .delta)
            try c.encode(scope.scopeRawValue, forKey: .scope)
            try c.encodeIfPresent(duration, forKey: .durationTicks)
        case let .statDelta(stat, delta):
            try c.encode("stat_delta", forKey: .type)
            try c.encode(stat, forKey: .stat)
            try c.encode(delta, forKey: .delta)
        case let .unlockTech(techID):
            try c.encode("unlock_tech", forKey: .type)
            try c.encode(techID, forKey: .techID)
        case let .triggerEvent(eventID, delay):
            try c.encode("trigger_event", forKey: .type)
            try c.encode(eventID, forKey: .eventID)
            try c.encode(delay, forKey: .delayTicks)
        case let .setWorldFlag(flag, value):
            try c.encode("set_world_flag", forKey: .type)
            try c.encode(flag, forKey: .flag)
            try c.encode(value, forKey: .value)
        }
    }
}

extension StatPath.Target {
    var scopeRawValue: String {
        switch self {
        case .global: return "global"
        case .settlementAll: return "settlement:all"
        case .settlementAny: return "settlement:any"
        case .settlementClosest: return "settlement:closest"
        }
    }
}
