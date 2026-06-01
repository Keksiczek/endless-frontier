import Foundation

/// Procedurally generates a hex world map from a seed and `MapGenConfig`.
///
/// Deterministic: a given seed always yields the same map. Varied: different
/// seeds (and config knobs) produce different biome layouts, special sites,
/// and hazards — the basis for replayable worlds.
public enum MapGenerator {
    static let regionNames = [
        "The Reach", "Far Hollow", "Greywater", "Stormwatch", "The Verge",
        "Ashfall", "Dimming Wood", "Saltmere", "Highmoor", "Blackvale",
        "Sunder Flats", "Coldspring", "Ember Hills", "Mistfen", "Thornmarch",
        "Duskwater", "Ironcrag", "Palewood", "Redhollow", "Windmere"
    ]

    /// Builds all regions for a new world. The homeland sits at the origin and
    /// starts fully explored; every other hex is unknown until reached.
    public static func generate(seed: UInt64, registry: GameDataRegistry) -> [Region] {
        let config = registry.mapGen
        let biomeIDs = registry.biomes.keys.sorted()
        let homelandBiome = biomeIDs.contains("plains") ? "plains" : (biomeIDs.first ?? "plains")

        var rng = SeededRNG(seed: seed ^ 0x4D41_5047_454E_0001)
        var nameIndex = 0

        return HexCoord.disc(radius: max(1, config.mapRadius)).map { coord in
            if coord == .origin {
                return Region(
                    id: rng.nextUUID(),
                    name: "Homeland",
                    coord: .origin,
                    kind: .homeland,
                    biomeID: homelandBiome,
                    hazardLevel: registry.biome(homelandBiome)?.baseHazard ?? 0,
                    explorationState: .fullyExplored
                )
            }

            let kind = rollKind(config: config, rng: &rng)
            let biomeID = rollBiome(biomeIDs: biomeIDs, config: config, rng: &rng)
            let baseHazard = registry.biome(biomeID)?.baseHazard ?? 1
            let hazard = baseHazard + hazardBonus(for: kind, config: config)
            let name = regionNames.isEmpty ? "Region \(coord.q),\(coord.r)"
                : regionNames[nameIndex % regionNames.count]
            nameIndex += 1

            return Region(
                id: rng.nextUUID(),
                name: name,
                coord: coord,
                kind: kind,
                biomeID: biomeID,
                hazardLevel: hazard,
                explorationState: .unknown
            )
        }
    }

    static func rollKind(config: MapGenConfig, rng: inout SeededRNG) -> RegionKind {
        let roll = rng.nextUnit()
        if roll < config.ruinsChance { return .ruins }
        if roll < config.ruinsChance + config.dungeonChance { return .dungeon }
        if roll < config.ruinsChance + config.dungeonChance + config.anomalyChance { return .anomaly }
        return .wilderness
    }

    static func rollBiome(biomeIDs: [String], config: MapGenConfig, rng: inout SeededRNG) -> String {
        guard !biomeIDs.isEmpty else { return "plains" }
        let weights = biomeIDs.map { config.biomeWeights[$0] ?? 1.0 }
        let index = rng.weightedIndex(weights) ?? 0
        return biomeIDs[index]
    }

    static func hazardBonus(for kind: RegionKind, config: MapGenConfig) -> Int {
        switch kind {
        case .dungeon: return config.dungeonHazardBonus
        case .anomaly: return config.anomalyHazardBonus
        default: return 0
        }
    }
}
