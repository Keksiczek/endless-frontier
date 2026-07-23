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
    /// When set, the route carries this *material* (by item id) out of the
    /// origin's stockpile instead of `resource` out of its storage.
    ///
    /// Ore and clay are deliberately not everywhere — a coastal colony has clay
    /// beds and no iron. Without a way to ship materials that was not a
    /// constraint but a dead end: nothing in the game could move an ingot
    /// between two towns, so "found your forge where the ore is" was the only
    /// answer the world had.
    public let materialID: String?

    /// Whether this route carries goods rather than an abstract resource.
    public var carriesMaterial: Bool { materialID != nil }

    public init(
        id: UUID = UUID(),
        fromID: UUID,
        toID: UUID,
        resource: ResourceType,
        amountPerTick: Double,
        materialID: String? = nil
    ) {
        self.id = id
        self.fromID = fromID
        self.toID = toID
        self.resource = resource
        self.amountPerTick = amountPerTick
        self.materialID = materialID
    }

    // MARK: - Codable (resilient: material routes came later)

    private enum CodingKeys: String, CodingKey {
        case id, fromID, toID, resource, amountPerTick, materialID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        fromID = try c.decode(UUID.self, forKey: .fromID)
        toID = try c.decode(UUID.self, forKey: .toID)
        resource = try c.decode(ResourceType.self, forKey: .resource)
        amountPerTick = try c.decode(Double.self, forKey: .amountPerTick)
        materialID = try c.decodeIfPresent(String.self, forKey: .materialID)
    }
}
