import Foundation

/// Procedurally generates the hex world map. Generation is **per-hex**: a
/// region's content is a pure function of `(mapSeed, coord)`, so any hex can be
/// generated lazily, in any order, and always comes out the same. That makes
/// the map both fully reproducible *and* endlessly extensible — as the player
/// pushes outward, new rings are generated on demand and the frontier never
/// ends.
///
/// Difficulty scales with distance from the homeland (more hazard, more
/// special sites), so there is always a reason — and a risk — to explore
/// further.
public enum MapGenerator {
    static let regionNames = [
        "The Reach", "Far Hollow", "Greywater", "Stormwatch", "The Verge",
        "Ashfall", "Dimming Wood", "Saltmere", "Highmoor", "Blackvale",
        "Sunder Flats", "Coldspring", "Ember Hills", "Mistfen", "Thornmarch",
        "Duskwater", "Ironcrag", "Palewood", "Redhollow", "Windmere",
        "Hagstone", "Brackenfell", "Lornwood", "Mirefax", "Caldgrave"
    ]

    /// Deterministic per-hex seed.
    static func hexSeed(_ mapSeed: UInt64, _ coord: HexCoord) -> UInt64 {
        var h = mapSeed &* 0x9E37_79B9_7F4A_7C15
        h = (h ^ UInt64(bitPattern: Int64(coord.q))) &* 0xD1B5_4A32_D192_ED03
        h = (h ^ UInt64(bitPattern: Int64(coord.r))) &* 0xCBF2_9CE4_8422_2325
        return h ^ (h >> 29)
    }

    /// The region at a coordinate. Pure: same `(mapSeed, coord)` → same region.
    public static func region(at coord: HexCoord, mapSeed: UInt64, registry: GameDataRegistry) -> Region {
        let biomeIDs = registry.biomes.keys.sorted()
        let homelandBiome = biomeIDs.contains("plains") ? "plains" : (biomeIDs.first ?? "plains")
        var rng = SeededRNG(seed: hexSeed(mapSeed, coord))

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

        let config = registry.mapGen
        let ring = coord.distance(to: .origin)
        let kind = rollKind(config: config, ring: ring, rng: &rng)
        let biomeID = rollBiome(biomeIDs: biomeIDs, config: config, rng: &rng)
        let baseHazard = registry.biome(biomeID)?.baseHazard ?? 1
        let hazard = baseHazard
            + hazardBonus(for: kind, config: config)
            + Int(Double(ring) * config.hazardPerRing)
        let name = regionNames.isEmpty ? "Region \(coord.q),\(coord.r)"
            : regionNames[nameIndex(coord) % regionNames.count]

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

    /// The initial world: a disc of regions of radius `mapRadius`. Only a
    /// starting frontier — the world grows beyond it as the player explores.
    public static func generate(seed: UInt64, registry: GameDataRegistry) -> [Region] {
        HexCoord.disc(radius: max(1, registry.mapGen.mapRadius))
            .map { region(at: $0, mapSeed: seed, registry: registry) }
    }

    /// Ensures every neighbour of `coord` exists in `regions`, generating the
    /// missing ones (unknown). Called when a region is revealed so the frontier
    /// keeps expanding outward without bound.
    public static func expandFrontier(
        around coord: HexCoord,
        regions: inout [Region],
        mapSeed: UInt64,
        registry: GameDataRegistry
    ) {
        let existing = Set(regions.map(\.coord))
        for neighbour in coord.neighbors() where !existing.contains(neighbour) {
            regions.append(region(at: neighbour, mapSeed: mapSeed, registry: registry))
        }
    }

    // MARK: - Rolls

    static func rollKind(config: MapGenConfig, ring: Int, rng: inout SeededRNG) -> RegionKind {
        let bonus = Double(ring) * config.specialChancePerRing
        let ruins = config.ruinsChance + bonus
        let dungeon = config.dungeonChance + bonus
        let anomaly = config.anomalyChance + bonus
        let roll = rng.nextUnit()
        if roll < ruins { return .ruins }
        if roll < ruins + dungeon { return .dungeon }
        if roll < ruins + dungeon + anomaly { return .anomaly }
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

    /// Stable name index for a coordinate (so a hex always keeps its name).
    static func nameIndex(_ coord: HexCoord) -> Int {
        abs(coord.q &* 73_856_093 ^ coord.r &* 19_349_663)
    }
}
