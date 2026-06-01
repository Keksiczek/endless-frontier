import Foundation

/// A standing supply line moving one resource from a source settlement to a
/// destination each tick. Trade routes also establish *connectivity*: a
/// settlement linked (directly or transitively) to the capital is considered
/// supplied and avoids the isolation stability penalty.
public struct TradeRoute: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let fromID: UUID
    public let toID: UUID
    public let resource: ResourceType
    public let amountPerTick: Double

    public init(
        id: UUID = UUID(),
        fromID: UUID,
        toID: UUID,
        resource: ResourceType,
        amountPerTick: Double
    ) {
        self.id = id
        self.fromID = fromID
        self.toID = toID
        self.resource = resource
        self.amountPerTick = amountPerTick
    }
}
