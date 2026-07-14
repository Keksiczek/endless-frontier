import Foundation

/// Deterministically builds a settlement's `LocalMap` from `(mapSeed, regionID)`
/// and its biome, honouring the rule `content = f(mapSeed, coord)`: the same
/// world always grows the same wilderness around the same settlement.
public enum LocalMapGenerator {
    /// How many deposits of each kind a temperate map gets before biome affinity
    /// nudges the counts.
    static let baseFieldCount = 3
    static let baseForestCount = 3
    static let baseStoneCount = 2
    static let baseHerbCount = 2

    public static func generate(
        mapSeed: UInt64,
        regionID: UUID,
        biome: BiomeDefinition?
    ) -> LocalMap {
        var rng = SeededRNG(seed: seed(mapSeed: mapSeed, regionID: regionID))

        // River: near the top or bottom edge, gently waving.
        let river = RiverShape(
            baseY: rng.nextUnit() < 0.5 ? 0.16 : 0.82,
            amplitude: 0.03 + rng.nextUnit() * 0.05,
            phase: rng.nextUnit() * 6.283185
        )

        // Biome affinity scales deposit counts and richness a little.
        let affinity = biome?.resourceAffinity ?? Resources()
        func bonus(_ resource: ResourceType) -> Int {
            affinity[resource] >= 1 ? 1 : 0
        }

        var nodeID = 0
        func makeNodes(_ kind: LocalResourceKind, count: Int) -> [ResourceNode] {
            (0..<count).map { _ in
                let position = landPoint(river: river, rng: &rng)
                let capacity = 160 + rng.nextUnit() * 120   // 160…280
                defer { nodeID += 1 }
                return ResourceNode(id: nodeID, kind: kind, position: position,
                                    amount: capacity, capacity: capacity)
            }
        }

        var nodes: [ResourceNode] = []
        nodes += makeNodes(.field, count: baseFieldCount + bonus(.food))
        nodes += makeNodes(.forest, count: baseForestCount + bonus(.materials))
        nodes += makeNodes(.stone, count: baseStoneCount + bonus(.materials))
        nodes += makeNodes(.herbs, count: baseHerbCount + bonus(.knowledge))

        // Points of interest: a fixed cast, scattered farther out.
        let poiKinds: [LocalPOIKind] = [.ruins, .cave, .spring, .treasure]
        let pois = poiKinds.enumerated().map { index, kind in
            LocalPOI(id: index, kind: kind, position: landPoint(river: river, rng: &rng))
        }

        var map = LocalMap(river: river, nodes: nodes, pois: pois)
        // The settlement sits at the centre; its surroundings start revealed.
        map.reveal(around: LocalPoint(x: 0.5, y: 0.5), radius: 0.28)
        return map
    }

    /// A point on dry land (away from the river), biased toward the interior.
    private static func landPoint(river: RiverShape, rng: inout SeededRNG) -> LocalPoint {
        for _ in 0..<24 {
            let x = 0.08 + rng.nextUnit() * 0.84
            let y = 0.08 + rng.nextUnit() * 0.84
            if abs(y - river.y(atX: x)) > 0.1 {
                return LocalPoint(x: x, y: y)
            }
        }
        // Fallback: opposite half from the river.
        let y = river.baseY < 0.5 ? 0.7 : 0.3
        return LocalPoint(x: 0.2 + rng.nextUnit() * 0.6, y: y)
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
