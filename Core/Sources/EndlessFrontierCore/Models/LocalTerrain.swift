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

    /// Chance a cell breaks from the land and takes its own cover, once the
    /// ground has a shape of its own. Far below `speckleChance`, which was
    /// doing the work of hiding square patch edges: land with a *form* wants a
    /// little grit on it, not a quarter of itself dissolved.
    static let grit = 0.06

    /// The cover of one grid cell.
    ///
    /// **The ground has a shape now.** This used to draw cover from a per-biome
    /// weighting on a four-by-four patch grid, with a fifth of the cells
    /// speckling to hide the seams — which is a colour scatter, not a country.
    /// A player looking at it saw grass with rock in it, never a ridge, never a
    /// hollow, never a bank of marsh where the ground falls to the water.
    ///
    /// So: two cheap fields, `elevation` and `moisture`, each a few octaves of
    /// value noise off the same seed, and the cover read off *both*. Height
    /// makes ridges and basins; wetness makes marsh in the hollows and sand on
    /// the dry rises. Bands mean the map has slopes — grass giving way to dirt
    /// giving way to rock as the ground climbs — which is what reads as
    /// geography.
    ///
    /// Still a pure function of `(terrainSeed, biome, cell)`: nothing is stored,
    /// saves are unchanged, and the same world always looks the same. The biome
    /// no longer picks the cover directly — it *tilts the land*, which is the
    /// honest way round: a desert is dry ground, not a bag of sand tiles.
    public static func cover(
        terrainSeed: UInt64,
        biomeID: String,
        column: Int,
        row: Int
    ) -> GroundCover {
        let land = shape(of: biomeID)
        let height = min(1, max(0, elevation(terrainSeed, column, row) + land.lift))
        let wet = min(1, max(0, moisture(terrainSeed, column, row) + land.damp))

        // A little grit, so a band's edge is a shoreline rather than a ruled
        // line — and so a cold country still has bare stone showing through.
        let fine = hash(terrainSeed &+ 0x51_ED_27, column, row)
        if unit(fine &>> 8) < grit {
            return weighted(weights(for: biomeID), unit(fine))
        }

        switch height {
        case let h where h > 0.80:
            return land.cold ? .snow : .rock
        case let h where h > 0.64:
            return .rock
        case let h where h < 0.30 && wet > 0.58:
            // The bottom of the land, where the water stands.
            return land.cold ? .snow : .marsh
        default:
            if wet < 0.30 { return land.cold ? .rock : .sand }
            if wet < 0.46 { return .dirt }
            if wet > 0.70 { return land.cold ? .snow : .meadow }
            return land.cold ? .snow : .grass
        }
    }

    /// How a biome tilts its ground: how high it stands, how wet it is, and
    /// whether the top of it is under snow.
    static func shape(of biomeID: String) -> (lift: Double, damp: Double, cold: Bool) {
        switch biomeID {
        case "forest":    return (0.02, 0.16, false)
        case "desert":    return (-0.02, -0.30, false)
        // A tundra is a **cold plain**, not a cold mountain. Lifted and dry, it
        // came out dominated by bare rock — the height band above 0.64 and the
        // dry band below 0.30 both answer `rock` in a cold country, and between
        // them they took most of the map. Low and damp puts the snow back where
        // the eye expects it. Guarded by "Each biome's dominant cover matches
        // its character".
        case "tundra":    return (-0.06, 0.14, true)
        case "mountains": return (0.26, -0.04, false)
        case "coast":     return (-0.14, 0.22, false)
        default:          return (0, 0.06, false)   // plains & homeland
        }
    }

    /// How far the ground stands, 0…1 — three octaves of value noise.
    ///
    /// Value noise rather than anything cleverer because it is a handful of
    /// hashes and a lerp: this is asked once per visible cell, every frame, and
    /// the shape it makes is already the shape a valley has.
    static func elevation(_ seed: UInt64, _ column: Int, _ row: Int) -> Double {
        var total = 0.0, amplitude = 1.0, weight = 0.0, wavelength = 22.0
        for octave in 0..<3 {
            total += amplitude * valueNoise(
                seed &+ UInt64(octave) &* 0x9E37_79B9,
                Double(column) / wavelength, Double(row) / wavelength)
            weight += amplitude
            amplitude *= 0.5
            wavelength *= 0.42
        }
        return total / max(0.0001, weight)
    }

    /// How wet the ground is, 0…1 — the same field off a different salt, and at
    /// a longer wavelength, so wetness runs in broad country rather than
    /// following every rise.
    static func moisture(_ seed: UInt64, _ column: Int, _ row: Int) -> Double {
        var total = 0.0, amplitude = 1.0, weight = 0.0, wavelength = 34.0
        for octave in 0..<2 {
            total += amplitude * valueNoise(
                (seed ^ 0xA01_5D4E_7F) &+ UInt64(octave) &* 0x85EB_CA6B,
                Double(column) / wavelength, Double(row) / wavelength)
            weight += amplitude
            amplitude *= 0.5
            wavelength *= 0.5
        }
        return total / max(0.0001, weight)
    }

    /// Bilinearly interpolated lattice noise, 0…1.
    static func valueNoise(_ seed: UInt64, _ x: Double, _ y: Double) -> Double {
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
        let fx = x - Double(x0), fy = y - Double(y0)
        // Smoothstep, so the lattice does not show as a diamond grid.
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let a = unit(hash(seed, x0, y0)), b = unit(hash(seed, x0 + 1, y0))
        let c = unit(hash(seed, x0, y0 + 1)), d = unit(hash(seed, x0 + 1, y0 + 1))
        return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy
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
