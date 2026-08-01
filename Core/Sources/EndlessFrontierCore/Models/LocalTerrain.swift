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
    // Geology and growth added because every valley read as the same flat
    // field with a stream through it. A coast should have driftwood and dunes,
    // a mountain should have a face you could not walk up.
    case cliff          // a rock face, shadowed at its foot
    case crag           // a jagged spire
    case dune           // a ridge of blown sand
    case deadTree       // a bleached snag
    case tallGrass      // tufts that move in the wind
    case mushroom       // a cluster in the leaf litter
    case driftwood      // bleached wood above the tideline
    case hotSpring      // steaming water

    /// What the land calls this, when you tap it.
    ///
    /// Scenery was the one layer of the valley with nothing to say. A bed of
    /// flowers, a stand of reeds, a snag, a cactus — all drawn, none of them
    /// able to answer for themselves, which is exactly the complaint that the
    /// world should be *things* rather than decoration.
    public var displayName: LocalizedText {
        switch self {
        case .tree:       return LocalizedText(values: [.en: "A tree", .cs: "Strom"])
        case .pine:       return LocalizedText(values: [.en: "A pine", .cs: "Borovice"])
        case .bush:       return LocalizedText(values: [.en: "A bush", .cs: "Keř"])
        case .rock:       return LocalizedText(values: [.en: "A stone", .cs: "Kámen"])
        case .boulder:    return LocalizedText(values: [.en: "A boulder", .cs: "Balvan"])
        case .flowers:    return LocalizedText(values: [.en: "Wildflowers", .cs: "Polní květy"])
        case .reeds:      return LocalizedText(values: [.en: "Reeds", .cs: "Rákosí"])
        case .stump:      return LocalizedText(values: [.en: "A stump", .cs: "Pařez"])
        case .pond:       return LocalizedText(values: [.en: "A pond", .cs: "Tůň"])
        case .cactus:     return LocalizedText(values: [.en: "A cactus", .cs: "Kaktus"])
        case .snowdrift:  return LocalizedText(values: [.en: "A snowdrift", .cs: "Závěj"])
        case .ruinPillar: return LocalizedText(values: [.en: "A fallen pillar", .cs: "Padlý sloup"])
        case .cliff:      return LocalizedText(values: [.en: "A rock face", .cs: "Skalní stěna"])
        case .crag:       return LocalizedText(values: [.en: "A crag", .cs: "Skalisko"])
        case .dune:       return LocalizedText(values: [.en: "A dune", .cs: "Duna"])
        case .deadTree:   return LocalizedText(values: [.en: "A dead tree", .cs: "Suchý strom"])
        case .tallGrass:  return LocalizedText(values: [.en: "Tall grass", .cs: "Vysoká tráva"])
        case .mushroom:   return LocalizedText(values: [.en: "Mushrooms", .cs: "Houby"])
        case .driftwood:  return LocalizedText(values: [.en: "Driftwood", .cs: "Naplavené dřevo"])
        case .hotSpring:  return LocalizedText(values: [.en: "A hot spring", .cs: "Horký pramen"])
        }
    }

    /// A line about what this is *for*, when there is one — the difference
    /// between a label and a thing that belongs to the world.
    public var note: LocalizedText? {
        switch self {
        case .flowers:   return LocalizedText(values: [.en: "bees and dye", .cs: "včely a barvivo"])
        case .mushroom:  return LocalizedText(values: [.en: "food, if you know them",
                                                       .cs: "jídlo, když je znáš"])
        case .reeds:     return LocalizedText(values: [.en: "thatch", .cs: "došky"])
        case .tallGrass: return LocalizedText(values: [.en: "fodder", .cs: "krmivo"])
        case .driftwood: return LocalizedText(values: [.en: "firewood", .cs: "dříví na oheň"])
        case .hotSpring: return LocalizedText(values: [.en: "warm all winter",
                                                       .cs: "teplý celou zimu"])
        case .pond:      return LocalizedText(values: [.en: "water", .cs: "voda"])
        case .stump:     return LocalizedText(values: [.en: "somebody felled this",
                                                       .cs: "tohle někdo pokácel"])
        default:         return nil
        }
    }
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
        // Counts are up by roughly half across the board: a valley of forty
        // props over a whole local map is one thing every fifty points, which
        // reads as a bare field with ornaments on it rather than as country.
        // Every kind here answers when it is tapped, so more of them is more
        // world rather than more wallpaper.
        case "forest":
            return ([(.pine, 0.30), (.tree, 0.20), (.bush, 0.14), (.stump, 0.06),
                     (.mushroom, 0.11), (.deadTree, 0.05), (.tallGrass, 0.07),
                     (.flowers, 0.04), (.rock, 0.03)], 74)
        case "desert":
            return ([(.cactus, 0.30), (.dune, 0.24), (.rock, 0.18), (.boulder, 0.12),
                     (.crag, 0.08), (.deadTree, 0.05), (.bush, 0.03)], 46)
        case "tundra":
            return ([(.snowdrift, 0.28), (.rock, 0.17), (.pine, 0.14), (.crag, 0.11),
                     (.deadTree, 0.09), (.hotSpring, 0.06), (.boulder, 0.09),
                     (.tallGrass, 0.06)], 50)
        case "mountains":
            return ([(.cliff, 0.22), (.boulder, 0.22), (.crag, 0.19), (.rock, 0.17),
                     (.pine, 0.09), (.hotSpring, 0.05), (.flowers, 0.06)], 58)
        case "coast":
            return ([(.reeds, 0.22), (.dune, 0.18), (.driftwood, 0.15), (.bush, 0.13),
                     (.tree, 0.10), (.cliff, 0.08), (.rock, 0.07), (.flowers, 0.07)], 56)
        default: // plains & homeland
            return ([(.tallGrass, 0.23), (.tree, 0.18), (.bush, 0.16), (.flowers, 0.19),
                     (.rock, 0.09), (.pond, 0.05), (.mushroom, 0.06), (.deadTree, 0.04)], 62)
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
