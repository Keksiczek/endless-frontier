import Foundation

/// Deterministically builds a settlement's `LocalMap` from `(mapSeed, regionID)`
/// and its biome, honouring the rule `content = f(mapSeed, coord)`: the same
/// world always grows the same wilderness around the same settlement.
///
/// The biome decides the character of the place — how many fields and forests,
/// what scenery stands on the ground, whether a river runs through it — so a
/// mountain outpost and a coastal town read as genuinely different country.
public enum LocalMapGenerator {
    public static func generate(
        mapSeed: UInt64,
        regionID: UUID,
        biome: BiomeDefinition?,
        flavor: RegionKind = .wilderness
    ) -> LocalMap {
        var rng = SeededRNG(seed: seed(mapSeed: mapSeed, regionID: regionID))
        let biomeID = biome?.id ?? "plains"

        // A river crosses most country, but not the driest: a desert map gets a
        // dry wash pushed to the very edge instead.
        let riverBase: Double
        if biomeID == "desert" {
            riverBase = rng.nextUnit() < 0.5 ? 0.06 : 0.94
        } else {
            riverBase = rng.nextUnit() < 0.5 ? 0.16 : 0.82
        }
        let river = RiverShape(
            baseY: riverBase,
            amplitude: 0.025 + rng.nextUnit() * 0.06,
            phase: rng.nextUnit() * 6.283185
        )

        var nodeID = 0
        func makeNodes(_ kind: LocalResourceKind, count: Int) -> [ResourceNode] {
            (0..<max(0, count)).map { _ in
                let position = landPoint(river: river, rng: &rng)
                let capacity = 160 + rng.nextUnit() * 120   // 160…280
                defer { nodeID += 1 }
                return ResourceNode(id: nodeID, kind: kind, position: position,
                                    amount: capacity, capacity: capacity)
            }
        }

        // Biome shapes what the land actually offers.
        let mix = depositMix(for: biomeID)
        var nodes: [ResourceNode] = []
        nodes += makeNodes(.field, count: mix.fields)
        nodes += makeNodes(.forest, count: mix.forests)
        nodes += makeNodes(.stone, count: mix.stone)
        nodes += makeNodes(.herbs, count: mix.herbs)

        // Points of interest: a fixed cast, scattered across the map — plus
        // whatever the region's character adds (see below).
        let poiKinds: [LocalPOIKind] = [.ruins, .cave, .spring, .treasure, .shrine, .wreck]
        var pois = poiKinds.enumerated().map { index, kind in
            LocalPOI(id: index, kind: kind, position: landPoint(river: river, rng: &rng))
        }

        // Scenery: the landscape's furniture, biome-appropriate and seeded.
        let (kinds, count) = LocalTerrain.sceneryMix(for: biomeID)
        var scenery = (0..<count).map { index -> SceneryProp in
            let kind = LocalTerrain.weighted(kinds, rng.nextUnit())
            // Reeds and ponds belong by the water; everything else keeps its feet dry.
            let wetLoving = (kind == .reeds || kind == .pond)
            let position = wetLoving
                ? riversidePoint(river: river, rng: &rng)
                : landPoint(river: river, rng: &rng)
            return SceneryProp(id: index, kind: kind, position: position,
                               scale: 0.7 + rng.nextUnit() * 0.6)
        }

        // The region's character marks its ground. A lost city is *streets* of
        // fallen pillars; a sanctuary blooms; plain ruins scatter a few stones.
        // The same seed shapes the same chunk whether you merely survey it or
        // later settle it — what the scouts saw is what the settlers get.
        var propID = scenery.count
        var poiID = pois.count
        func addProps(_ kind: SceneryKind, _ n: Int, around center: LocalPoint, spread: Double) {
            for _ in 0..<n {
                let a = rng.nextUnit() * 2 * .pi
                let r = rng.nextUnit() * spread
                let p = LocalPoint(x: min(0.95, max(0.05, center.x + cos(a) * r)),
                                   y: min(0.95, max(0.05, center.y + sin(a) * r)))
                scenery.append(SceneryProp(id: propID, kind: kind, position: p,
                                           scale: 0.8 + rng.nextUnit() * 0.5))
                propID += 1
            }
        }
        switch flavor {
        case .lostCity:
            let heart = landPoint(river: river, rng: &rng)
            addProps(.ruinPillar, 9, around: heart, spread: 0.16)
            pois.append(LocalPOI(id: poiID, kind: .treasure, position: heart)); poiID += 1
            pois.append(LocalPOI(id: poiID, kind: .ruins,
                                 position: landPoint(river: river, rng: &rng))); poiID += 1
            nodes.append(ResourceNode(id: nodeID, kind: .stone,
                                      position: landPoint(river: river, rng: &rng),
                                      amount: 260, capacity: 260)); nodeID += 1
        case .sanctuary:
            let hallow = landPoint(river: river, rng: &rng)
            addProps(.flowers, 6, around: hallow, spread: 0.10)
            pois.append(LocalPOI(id: poiID, kind: .shrine, position: hallow)); poiID += 1
        case .ruins:
            addProps(.ruinPillar, 4, around: landPoint(river: river, rng: &rng), spread: 0.2)
        case .dungeon:
            pois.append(LocalPOI(id: poiID, kind: .cave,
                                 position: landPoint(river: river, rng: &rng))); poiID += 1
        default:
            break
        }

        // A herd sized by how much the land can feed.
        let capacity = herdCapacity(for: biomeID, rng: &rng)
        let wildlife = WildlifeState(
            deerHerd: capacity * (0.4 + rng.nextUnit() * 0.3),
            deerCapacity: capacity,
            predatorPressure: 8 + rng.nextUnit() * 8
        )

        var map = LocalMap(
            river: river, nodes: nodes, pois: pois, wildlife: wildlife,
            biomeID: biomeID,
            terrainSeed: seed(mapSeed: mapSeed, regionID: regionID) ^ 0x7E_44_A1_04_5E_ED,
            scenery: scenery)
        // The settlement sits at the centre; its surroundings start revealed.
        map.reveal(around: LocalPoint(x: 0.5, y: 0.5), radius: 0.28)
        return map
    }

    /// How many deposits of each kind a biome yields.
    static func depositMix(for biomeID: String) -> (fields: Int, forests: Int, stone: Int, herbs: Int) {
        switch biomeID {
        case "forest":    return (2, 6, 2, 3)
        case "desert":    return (1, 1, 4, 1)
        case "tundra":    return (1, 2, 3, 2)
        case "mountains": return (1, 2, 6, 1)
        case "coast":     return (3, 2, 2, 3)
        default:          return (4, 3, 2, 2)   // plains & homeland
        }
    }

    /// The land's carrying capacity for game.
    static func herdCapacity(for biomeID: String, rng: inout SeededRNG) -> Double {
        let base: Double
        switch biomeID {
        case "forest":    base = 110
        case "plains":    base = 95
        case "coast":     base = 80
        case "tundra":    base = 55
        case "mountains": base = 50
        case "desert":    base = 35
        default:          base = 90
        }
        return base * (0.85 + rng.nextUnit() * 0.3)
    }

    /// A point on dry land (away from the river), biased toward the interior.
    private static func landPoint(river: RiverShape, rng: inout SeededRNG) -> LocalPoint {
        for _ in 0..<24 {
            let x = 0.06 + rng.nextUnit() * 0.88
            let y = 0.06 + rng.nextUnit() * 0.88
            if abs(y - river.y(atX: x)) > 0.09 {
                return LocalPoint(x: x, y: y)
            }
        }
        let y = river.baseY < 0.5 ? 0.7 : 0.3
        return LocalPoint(x: 0.2 + rng.nextUnit() * 0.6, y: y)
    }

    /// A point hugging the riverbank — where reeds grow and ponds gather.
    private static func riversidePoint(river: RiverShape, rng: inout SeededRNG) -> LocalPoint {
        let x = 0.06 + rng.nextUnit() * 0.88
        let side: Double = rng.nextUnit() < 0.5 ? -1 : 1
        let offset = (0.03 + rng.nextUnit() * 0.05) * side
        let y = min(0.96, max(0.04, river.y(atX: x) + offset))
        return LocalPoint(x: x, y: y)
    }

    static func seed(mapSeed: UInt64, regionID: UUID) -> UInt64 {
        var h = mapSeed &* 0x9E37_79B9_7F4A_7C15
        let b = regionID.uuid
        let hi = UInt64(b.0) << 56 | UInt64(b.1) << 48 | UInt64(b.2) << 40 | UInt64(b.3) << 32
            | UInt64(b.4) << 24 | UInt64(b.5) << 16 | UInt64(b.6) << 8 | UInt64(b.7)
        let lo = UInt64(b.8) << 56 | UInt64(b.9) << 48 | UInt64(b.10) << 40 | UInt64(b.11) << 32
            | UInt64(b.12) << 24 | UInt64(b.13) << 16 | UInt64(b.14) << 8 | UInt64(b.15)
        h = (h ^ hi) &* 0xD1B5_4A32_D192_ED03
        h = (h ^ lo) &* 0xCBF2_9CE4_8422_2325
        return h ^ (h >> 29)
    }
}
