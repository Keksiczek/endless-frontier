import Foundation

/// A data-defined biome. Loaded from `biomes.json`. When a region of this
/// biome is revealed, `worldFlag` (if any) is set so events can gate on it
/// (e.g. `biome:plains_present`).
public struct BiomeDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: LocalizedText
    public let baseHazard: Int
    public let resourceAffinity: Resources
    public let worldFlag: String?
    /// Relative chance this biome is the one the player wakes up in. Zero (the
    /// default) means never. The homeland used to be hardcoded to plains, so
    /// the map a player stares at for the whole game was the same country every
    /// single run — this is the knob that fixes it, in data rather than code.
    public let homelandWeight: Double
    /// Degrees this country runs above or below the ordinary seasonal swing.
    ///
    /// The biome had no temperature at all, so a tundra valley in January was
    /// exactly as cold as a coastal one and the word "tundra" meant nothing to
    /// anybody's body. This is what makes choosing where to live a decision:
    /// see `Climate`.
    public let temperatureShift: Double

    public init(
        id: String,
        name: LocalizedText,
        baseHazard: Int = 0,
        resourceAffinity: Resources = Resources(),
        worldFlag: String? = nil,
        homelandWeight: Double = 0,
        temperatureShift: Double = 0
    ) {
        self.id = id
        self.name = name
        self.baseHazard = baseHazard
        self.resourceAffinity = resourceAffinity
        self.worldFlag = worldFlag
        self.homelandWeight = homelandWeight
        self.temperatureShift = temperatureShift
    }

    private enum CodingKeys: String, CodingKey {
        case id, name
        case baseHazard = "base_hazard"
        case resourceAffinity = "resource_affinity"
        case worldFlag = "world_flag"
        case homelandWeight = "homeland_weight"
        case temperatureShift = "temperature_shift"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(LocalizedText.self, forKey: .name)
        baseHazard = try c.decodeIfPresent(Int.self, forKey: .baseHazard) ?? 0
        resourceAffinity = try c.decodeIfPresent(Resources.self, forKey: .resourceAffinity) ?? Resources()
        worldFlag = try c.decodeIfPresent(String.self, forKey: .worldFlag)
        homelandWeight = try c.decodeIfPresent(Double.self, forKey: .homelandWeight) ?? 0
        // A biome written before the land had weather is middling country.
        temperatureShift = try c.decodeIfPresent(Double.self, forKey: .temperatureShift) ?? 0
    }

    /// The weather in this country.
    public var climate: Climate { Climate(shift: temperatureShift) }
}
