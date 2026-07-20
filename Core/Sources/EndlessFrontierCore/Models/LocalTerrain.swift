import Foundation

/// What a patch of ground is made of. The local map is tiled with these,
/// distributed deterministically from the world seed and the biome — so every
/// settlement sits in recognisably different country.
public enum GroundCover: String, Codable, Sendable, CaseIterable {
    case grass
    case meadow
    case dirt
    case sand
    case rock
    case snow
    case marsh
}

/// A decorative feature standing on the map: a tree, a boulder, a patch of
/// flowers. Purely scenery — it has no simulation effect — but it is generated
/// from the seed, so a given world always grows the same landscape.
public enum SceneryKind: String, Codable, Sendable, CaseIterable {
    case tree
    case pine
    case bush
    case rock
    case boulder
    case flowers
    case reeds
    case stump
    case pond
    case cactus
    case snowdrift
    case ruinPillar = "ruin_pillar"
}

public struct SceneryProp: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let kind: SceneryKind
    public let position: LocalPoint
    /// Size multiplier (roughly 0.7…1.3) so a copse doesn't look stamped.
    public let scale: Double

    public init(id: Int, kind: SceneryKind, position: LocalPoint, scale: Double) {
        self.id = id
        self.kind = kind
        self.position = position
        self.scale = scale
    }
}

/// The ground-cover tiling of a local map: a pure function of
/// `(terrainSeed, biome, cell)`, never stored, so saves stay small and the
/// same world always looks the same.
///
/// Cover is picked from a per-biome weighting, sampled on a coarse patch grid
/// so terrain forms *patches* rather than television static, with a little
/// fine-grained speckle on top.
public enum LocalTerrain {
    /// Side of a coarse patch, in fog-grid cells.
    static let patchSize = 4
    /// Chance a cell breaks from its patch and takes its own cover.
    static let speckleChance = 0.22

    /// The cover of one grid cell.
    public static func cover(
        terrainSeed: UInt64,
        biomeID: String,
        column: Int,
        row: Int
    ) -> GroundCover {
        let table = weights(for: biomeID)
        // The patch this cell belongs to decides the base cover…
        let patch = hash(terrainSeed, column / patchSize, row / patchSize)
        var pick = weighted(table, unit(patch))
        // …but a minority of cells speckle, so edges aren't blocky.
        let fine = hash(terrainSeed &+ 0x51_ED_27, column, row)
        if unit(fine &>> 8) < speckleChance {
            pick = weighted(table, unit(fine))
        }
        return pick
    }

    /// Per-biome cover mix. The dominant cover carries the biome's character.
    public static func weights(for biomeID: String) -> [(GroundCover, Double)] {
        switch biomeID {
        case "forest":
            return [(.grass, 0.40), (.meadow, 0.20), (.dirt, 0.28), (.rock, 0.12)]
        case "desert":
            return [(.sand, 0.68), (.dirt, 0.20), (.rock, 0.12)]
        case "tundra":
            return [(.snow, 0.54), (.rock, 0.20), (.dirt, 0.14), (.grass, 0.12)]
        case "mountains":
            return [(.rock, 0.54), (.dirt, 0.24), (.grass, 0.14), (.snow, 0.08)]
        case "coast":
            return [(.sand, 0.34), (.grass, 0.28), (.marsh, 0.22), (.meadow, 0.16)]
        default: // plains & homeland
            return [(.grass, 0.48), (.meadow, 0.30), (.dirt, 0.16), (.rock, 0.06)]
        }
    }

    /// The scenery mix a biome scatters, and how much of it.
    public static func sceneryMix(for biomeID: String) -> (kinds: [(SceneryKind, Double)], count: Int) {
        switch biomeID {
        case "forest":
            return ([(.pine, 0.42), (.tree, 0.26), (.bush, 0.16), (.stump, 0.10), (.rock, 0.06)], 46)
        case "desert":
            return ([(.cactus, 0.42), (.rock, 0.30), (.boulder, 0.18), (.bush, 0.10)], 26)
        case "tundra":
            return ([(.snowdrift, 0.40), (.rock, 0.26), (.pine, 0.20), (.boulder, 0.14)], 30)
        case "mountains":
            return ([(.boulder, 0.40), (.rock, 0.32), (.pine, 0.18), (.bush, 0.10)], 34)
        case "coast":
            return ([(.reeds, 0.36), (.pond, 0.18), (.bush, 0.20), (.tree, 0.16), (.rock, 0.10)], 32)
        default: // plains & homeland
            return ([(.tree, 0.28), (.bush, 0.24), (.flowers, 0.24), (.rock, 0.14), (.pond, 0.10)], 36)
        }
    }

    // MARK: - Maths

    static func weighted<T>(_ table: [(T, Double)], _ roll: Double) -> T {
        let total = table.reduce(0) { $0 + $1.1 }
        var pick = roll * total
        for (value, weight) in table {
            pick -= weight
            if pick <= 0 { return value }
        }
        return table[table.count - 1].0
    }

    static func hash(_ seed: UInt64, _ a: Int, _ b: Int) -> UInt64 {
        var h = seed &* 0x9E37_79B9_7F4A_7C15
        h = (h ^ UInt64(bitPattern: Int64(a))) &* 0xD1B5_4A32_D192_ED03
        h = (h ^ UInt64(bitPattern: Int64(b))) &* 0xCBF2_9CE4_8422_2325
        return h ^ (h >> 29)
    }

    static func unit(_ h: UInt64) -> Double {
        Double(h & 0xFFFF_FFFF) / Double(0x1_0000_0000)
    }
}
