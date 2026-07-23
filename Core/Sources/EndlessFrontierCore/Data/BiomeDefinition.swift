import Foundation

/// A data-defined biome. Loaded from `biomes.json`. When a region of this
/// biome is revealed, `worldFlag` (if any) is set so events can gate on it
/// (e.g. `biome:plains_present`).
public struct BiomeDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let baseHazard: Int
    public let resourceAffinity: Resources
    public let worldFlag: String?
    /// Relative chance this biome is the one the player wakes up in. Zero (the
    /// default) means never. The homeland used to be hardcoded to plains, so
    /// the map a player stares at for the whole game was the same country every
    /// single run — this is the knob that fixes it, in data rather than code.
    public let homelandWeight: Double

    public init(
        id: String,
        name: String,
        baseHazard: Int = 0,
        resourceAffinity: Resources = Resources(),
        worldFlag: String? = nil,
        homelandWeight: Double = 0
    ) {
        self.id = id
        self.name = name
        self.baseHazard = baseHazard
        self.resourceAffinity = resourceAffinity
        self.worldFlag = worldFlag
        self.homelandWeight = homelandWeight
    }

    private enum CodingKeys: String, CodingKey {
        case id, name
        case baseHazard = "base_hazard"
        case resourceAffinity = "resource_affinity"
        case worldFlag = "world_flag"
        case homelandWeight = "homeland_weight"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        baseHazard = try c.decodeIfPresent(Int.self, forKey: .baseHazard) ?? 0
        resourceAffinity = try c.decodeIfPresent(Resources.self, forKey: .resourceAffinity) ?? Resources()
        worldFlag = try c.decodeIfPresent(String.self, forKey: .worldFlag)
        homelandWeight = try c.decodeIfPresent(Double.self, forKey: .homelandWeight) ?? 0
    }
}
