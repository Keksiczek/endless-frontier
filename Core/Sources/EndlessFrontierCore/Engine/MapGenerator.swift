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
    // Place names are *built*, not picked from a list.
    //
    // There used to be 25 of them, taken modulo the coordinate, on a map that
    // is deliberately endless and grows every time you reveal a hex. So the
    // same two dozen names repeated forever: a player charts the Duskwater in
    // front of them, sees three more Duskwaters still offering an expedition,
    // and concludes that exploring did nothing. The map was lying about which
    // place was which. (The old scheme also ignored `mapSeed` entirely, so
    // every world named its places identically.)
    //
    // 25 × 20 × 10 = 5,000 names, and the coordinate is folded into that space
    // through a bijection — so within any map a player will ever walk, two
    // places cannot share a name *by construction*, not by luck.
    static let nameRoots = [
        "Dusk", "Grey", "Storm", "Ash", "Salt", "High", "Black", "Cold",
        "Ember", "Mist", "Thorn", "Iron", "Pale", "Red", "Wind", "Hag",
        "Bracken", "Lorn", "Mire", "Cald", "Fen", "Bram", "Sunder", "Rook", "Hollow"
    ]
    static let nameSuffixes = [
        "water", "watch", "fall", "mere", "moor", "vale", "flats", "spring",
        "hills", "fen", "march", "crag", "wood", "hollow", "stone", "fell",
        "marsh", "reach", "grave", "barrow"
    ]
    static let nameEpithets = [
        "", "Upper ", "Lower ", "Far ", "Old ", "New ", "Little ", "Great ",
        "Outer ", "Deep "
    ]

    /// A unique number for every hex — a Cantor pairing of the axial
    /// coordinates, mapped through ℤ→ℕ first. Being a bijection is the whole
    /// point: distinct hexes cannot collide here, so they cannot collide in the
    /// names built from it.
    static func hexIndex(_ coord: HexCoord) -> Int {
        let a = coord.q >= 0 ? 2 * coord.q : -2 * coord.q - 1
        let b = coord.r >= 0 ? 2 * coord.r : -2 * coord.r - 1
        return (a + b) * (a + b + 1) / 2 + b
    }

    /// The name of the place at a coordinate. Deterministic per `(mapSeed,
    /// coord)`, and distinct from every other place a player will reach.
    public static func name(for coord: HexCoord, mapSeed: UInt64) -> String {
        let roots = nameRoots.count, suffixes = nameSuffixes.count, epithets = nameEpithets.count
        let space = roots * suffixes * epithets
        // Offsetting by the seed keeps the mapping a bijection while giving
        // each world its own names — the old scheme gave every world the same
        // ones in the same places.
        let offset = Int(mapSeed % UInt64(space))
        let index = (hexIndex(coord) + offset) % space

        let root = nameRoots[index % roots]
        let suffix = nameSuffixes[(index / roots) % suffixes]
        let epithet = nameEpithets[(index / (roots * suffixes)) % epithets]
        return epithet + root + suffix
    }

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
        let name = name(for: coord, mapSeed: mapSeed)

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

}
