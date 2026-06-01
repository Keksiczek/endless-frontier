import Foundation

/// Tunable options for procedural world-map generation. Loaded from
/// `map-gen.json`. Generation is seeded (so a given seed reproduces a map)
/// but these knobs shape the *variety* a seed can produce.
public struct MapGenConfig: Codable, Sendable, Equatable {
    /// Number of hex rings around the homeland.
    public var mapRadius: Int
    /// Per-region probabilities of being a special site instead of plain
    /// wilderness. Checked in order: ruins → dungeon → anomaly.
    public var ruinsChance: Double
    public var dungeonChance: Double
    public var anomalyChance: Double
    /// Optional biome weighting by biome id. Empty = uniform over all biomes.
    public var biomeWeights: [String: Double]
    /// Extra hazard added on top of a biome's base hazard, by region kind.
    public var dungeonHazardBonus: Int
    public var anomalyHazardBonus: Int
    /// Distance scaling: the further a hex is from the homeland, the more
    /// dangerous and the more likely to hold a special site. This keeps the
    /// (endless) frontier perpetually worth pushing into.
    public var hazardPerRing: Double
    public var specialChancePerRing: Double

    public static let `default` = MapGenConfig(
        mapRadius: 3,
        ruinsChance: 0.10,
        dungeonChance: 0.05,
        anomalyChance: 0.04,
        biomeWeights: [:],
        dungeonHazardBonus: 3,
        anomalyHazardBonus: 2,
        hazardPerRing: 0.6,
        specialChancePerRing: 0.015
    )

    public init(
        mapRadius: Int,
        ruinsChance: Double,
        dungeonChance: Double,
        anomalyChance: Double,
        biomeWeights: [String: Double],
        dungeonHazardBonus: Int,
        anomalyHazardBonus: Int,
        hazardPerRing: Double,
        specialChancePerRing: Double
    ) {
        self.mapRadius = mapRadius
        self.ruinsChance = ruinsChance
        self.dungeonChance = dungeonChance
        self.anomalyChance = anomalyChance
        self.biomeWeights = biomeWeights
        self.dungeonHazardBonus = dungeonHazardBonus
        self.anomalyHazardBonus = anomalyHazardBonus
        self.hazardPerRing = hazardPerRing
        self.specialChancePerRing = specialChancePerRing
    }

    // Resilient decoding: any missing field falls back to the default.
    private enum CodingKeys: String, CodingKey {
        case mapRadius, ruinsChance, dungeonChance, anomalyChance,
             biomeWeights, dungeonHazardBonus, anomalyHazardBonus,
             hazardPerRing, specialChancePerRing
    }

    public init(from decoder: Decoder) throws {
        let d = MapGenConfig.default
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mapRadius = (try? c.decodeIfPresent(Int.self, forKey: .mapRadius)) ?? d.mapRadius
        ruinsChance = (try? c.decodeIfPresent(Double.self, forKey: .ruinsChance)) ?? d.ruinsChance
        dungeonChance = (try? c.decodeIfPresent(Double.self, forKey: .dungeonChance)) ?? d.dungeonChance
        anomalyChance = (try? c.decodeIfPresent(Double.self, forKey: .anomalyChance)) ?? d.anomalyChance
        biomeWeights = (try? c.decodeIfPresent([String: Double].self, forKey: .biomeWeights)) ?? d.biomeWeights
        dungeonHazardBonus = (try? c.decodeIfPresent(Int.self, forKey: .dungeonHazardBonus)) ?? d.dungeonHazardBonus
        anomalyHazardBonus = (try? c.decodeIfPresent(Int.self, forKey: .anomalyHazardBonus)) ?? d.anomalyHazardBonus
        hazardPerRing = (try? c.decodeIfPresent(Double.self, forKey: .hazardPerRing)) ?? d.hazardPerRing
        specialChancePerRing = (try? c.decodeIfPresent(Double.self, forKey: .specialChancePerRing)) ?? d.specialChancePerRing
    }
}
