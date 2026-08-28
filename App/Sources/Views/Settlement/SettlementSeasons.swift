import SwiftUI
import EndlessFrontierCore

/// What the seasons do to the *land*, as opposed to what they do to a colour
/// multiplier.
///
/// Winter used to be a bluish wash laid over the same green field, and spring
/// was the same field 22% greener. That reads as a filter, not as weather. Snow
/// does not tint a meadow: it *lies* on it, filling the hollows first while the
/// wind keeps the ridges bare, and it is still lying there in the middle of
/// winter and gone by the end of it. Spring is not green — spring is mud, and
/// standing meltwater, and then it dries.
///
/// So the season gets a skin: a second cover laid over the ground's own, decided
/// per tile from the relief (`SettlementLight.relief`, the same hills the light
/// picks out, so drifts collect exactly where the shading says the hollows are),
/// the cover underneath, how far through its season the year has got, and — for
/// autumn — whether there is a wood overhead to drop leaves.
///
/// Presentational and pure. Nothing here is stored; nothing writes back.
enum SettlementSeasons {

    /// The second cover a tile wears this season.
    enum Skin: Hashable, CaseIterable {
        case bare        // the ground's own cover, showing through
        case snow
        case drift       // snow the wind has heaped, brighter and scalloped
        case mud
        case puddle      // standing meltwater
        case litter      // fallen leaves under a wood
        case parched     // grass burnt off in high summer
    }

    /// How much of the ground a season's skin has taken, 0…1, which is the one
    /// number that has to be *reachable*: a winter that never gets past a
    /// dusting is a winter nobody sees.
    ///
    /// `progress` is how far through this season the year has got.
    static func coverage(season: Season, progress: Double,
                         country: Country = .temperate) -> Double {
        let p = max(0, min(1, progress))
        let held = country.holds(season)
        switch season {
        case .winter:
            // Lying by the first week, deep by midwinter, still deep at its end
            // — a thaw is spring's business, not winter's.
            return smoothstep(0.02, 0.40, p) * held
        case .spring:
            // The melt is *first*: spring opens as mud and dries out of it.
            return (1 - smoothstep(0.05, 0.62, p)) * held
        case .autumn:
            return smoothstep(0.10, 0.70, p) * held
        case .summer:
            return smoothstep(0.22, 0.78, p) * held
        }
    }

    // MARK: - What country this is

    /// How much of each season's dressing a particular country actually gets.
    ///
    /// **It does not snow in the desert.** The dressing above was season and
    /// progress and nothing else, so every valley in the world went white on
    /// the same day and thawed on the same day: a dune sea in January was
    /// drawn as a tundra in January, and the biome the map generator works so
    /// hard to choose was — again — a colour. `Climate` has said for a while
    /// that the desert is eleven degrees warmer and the tundra thirteen colder;
    /// nothing on the canvas read it.
    ///
    /// Snow wants **cold and water**, which is why the two fields it is built
    /// from are the ones that mean exactly that: `temperature_shift` and the
    /// biome's own `niche.moisture`. A cold wet country lies deep, a cold dry
    /// one gets a scouring and bare ground, and a hot one gets nothing at all
    /// whatever the calendar says.
    struct Country: Equatable {
        /// °C this country adds to the season — negative is cold.
        var shift: Double
        /// −1 (desert) … +1 (fen). The biome's `niche.moisture`.
        var moisture: Double

        /// The middling place the canvas used to assume everywhere was.
        static let temperate = Country(shift: 0, moisture: 0)

        /// Read off the biome, so a seventh biome is drawn correctly the day
        /// its JSON lands rather than the day somebody remembers this file.
        init(shift: Double = 0, moisture: Double = 0) {
            self.shift = shift
            self.moisture = moisture
        }

        init(biomeID: String, registry: GameDataRegistry) {
            guard let biome = registry.biome(biomeID) else {
                self = .temperate
                return
            }
            // A biome with no niche stated is the middling wet — the field
            // is optional in the schema and the answer must not be "desert".
            self.init(shift: biome.temperatureShift,
                      moisture: biome.niche?.moisture ?? 0)
        }

        /// **Calibrated so the ordinary country is unchanged.** The temperate
        /// valley these bands were tuned against still goes fully white at
        /// midwinter and fully to mud in spring: this only takes dressing
        /// *away*, from the places that have no business wearing it. Plains,
        /// forest, tundra and mountains all come out at 1; the coast, mild and
        /// wet, keeps three quarters of its snow; the desert keeps none.

        /// How damp, 0 (dune sea) … 1. Saturates quickly, because only a real
        /// desert is dry enough for it to matter — a `niche.moisture` of −0.05
        /// is a tundra, not a drought.
        var dampness: Double { max(0, min(1, 1.35 + moisture)) }

        /// How cold, 0 (a hot country) … 1. Everything at or below the plains'
        /// own temperature is simply "cold enough to snow"; the scale is for
        /// the warm end, where the coast sits at +4 and the desert at +11.
        var coldness: Double { max(0, min(1, (10 - shift) / 8)) }

        /// How much of this season's dressing lies here.
        func holds(_ season: Season) -> Double {
            switch season {
            case .winter:
                // Snow wants cold *and* water, and multiplying is what makes a
                // hot desert get none however dry-cold the night is.
                return coldness * dampness
            case .spring:
                // Mud is last winter's snow. No snow, no melt — a desert
                // spring is dust, which is the ground's own colour. The floor
                // is the rain a dry place still gets.
                return max(0.12 * dampness, coldness * dampness)
            case .autumn:
                // Leaves need a wood, and `skin` already asks for the canopy;
                // this only thins the litter where the country is sparse.
                return max(0, min(1, 0.55 + 0.45 * dampness))
            case .summer:
                // The other way round, and read off the raw moisture rather
                // than the saturating `dampness`: a fen stays green through
                // August and a dune sea burns off entirely, and the ordinary
                // valley — moisture 0 — is left exactly where it was tuned.
                return max(0, min(1, 1 - 0.5 * max(0, moisture)))
            }
        }
    }

    /// Which skin a single tile wears.
    ///
    /// - `relief`: 0 (a hollow) … 1 (a ridge), from `SettlementLight`.
    /// - `wood`: how much canopy stands over this cell, 0…1.
    /// - `hash`: the tile's own noise, for the scatter within a band.
    static func skin(
        cover: GroundCover, season: Season, coverage: Double,
        relief: Double, wood: Double, hash h: UInt64
    ) -> Skin {
        guard coverage > 0.01 else { return .bare }
        // A little jitter on the threshold, so the snow line is a ragged edge
        // and not a contour drawn with a ruler.
        let grain = (SettlementGround.unit(h >> 24) - 0.5) * 0.22
        switch season {
        case .winter:
            if cover == .snow { return .drift }          // already white; give it shape
            // Hollows fill first and ridges stay scoured. Bare rock and sand
            // shed it; marsh and grass hold it.
            let holds: Double = (cover == .rock || cover == .sand) ? 0.72 : 1.0
            guard relief + grain < coverage * 1.18 * holds else { return .bare }
            // The wind heaps a minority of it into drifts.
            return SettlementGround.unit(h >> 30) < 0.18 ? .drift : .snow
        case .spring:
            guard cover != .rock, cover != .snow else { return .bare }
            guard relief + grain < coverage * 0.86 else { return .bare }
            // The very bottom of a hollow is still under water.
            if relief < coverage * 0.28, SettlementGround.unit(h >> 34) < 0.34 { return .puddle }
            return .mud
        case .autumn:
            guard wood > 0.05 else { return .bare }
            guard cover == .grass || cover == .meadow || cover == .dirt else { return .bare }
            guard SettlementGround.unit(h >> 36) < coverage * wood * 1.35 else { return .bare }
            return .litter
        case .summer:
            guard cover == .grass || cover == .meadow else { return .bare }
            // A ridge dries out long before a hollow does.
            guard relief + grain > 1 - coverage * 0.72 else { return .bare }
            return .parched
        }
    }

    /// What a skin is painted in, and how much of the ground it hides.
    ///
    /// Returned as raw components rather than as a `Color` on purpose: the
    /// ground blends this into the cover's own colour and fills the result
    /// **opaque**. Laying a translucent sheet over the earth instead put a
    /// visible grid across the whole valley — every tile is drawn a hair larger
    /// than its cell so no seam shows, and a hair of overlap that is harmless
    /// under an opaque fill blends twice under a see-through one, so each tile
    /// edge came out as a bright line and the map turned into brickwork.
    ///
    /// Snow is also *not* white. Painted white it swallowed the valley: the
    /// buildings, the deer and the people all went to dark specks on a bright
    /// sheet. It sits in the same cold, dim palette as everything else.
    static func tint(_ skin: Skin) -> (r: Double, g: Double, b: Double, weight: Double)? {
        switch skin {
        case .bare:    return nil
        case .snow:    return (0.52, 0.57, 0.66, 0.70)
        case .drift:   return (0.64, 0.69, 0.78, 0.78)
        case .mud:     return (0.24, 0.18, 0.13, 0.70)
        case .puddle:  return (0.27, 0.35, 0.42, 0.76)
        case .litter:  return (0.42, 0.27, 0.13, 0.58)
        case .parched: return (0.44, 0.40, 0.23, 0.48)
        }
    }

    /// The mark scratched on a skinned tile — the thing that makes it read as
    /// snow rather than as a pale rectangle.
    static func mark(
        _ into: inout [Skin: Path], skin: Skin, at c: CGPoint, size: CGFloat, hash h: UInt64
    ) {
        guard skin != .bare else { return }
        // Sparse and well jittered. At a third of the tiles, centred, a scallop
        // on every drift stopped reading as snow and started reading as
        // brickwork — a regular mark on a regular lattice always will.
        guard SettlementGround.unit(h >> 40) < 0.15 else { return }
        let jx = (CGFloat(SettlementGround.unit(h >> 44)) - 0.5) * size * 1.1
        let jy = (CGFloat(SettlementGround.unit(h >> 48)) - 0.5) * size * 1.1
        let p = CGPoint(x: c.x + jx, y: c.y + jy)
        var path = into[skin] ?? Path()
        switch skin {
        case .bare:
            return
        case .snow, .drift:
            // **One mark repeated is wallpaper.** A single scallop, at one size,
            // on a lattice is read by the eye as a pattern rather than as
            // country — Keks, on a winter screenshot: *"textury mi přijdou
            // pořád stejné."* Three marks and a size that varies is enough: the
            // eye stops finding the repeat.
            let scale = 0.7 + CGFloat(SettlementGround.unit(h >> 52)) * 0.7
            switch SettlementGround.unit(h >> 56) {
            case ..<0.45:
                // The lip of a drift, seen from above.
                path.move(to: CGPoint(x: p.x - size * 0.30 * scale, y: p.y + size * 0.08))
                path.addQuadCurve(
                    to: CGPoint(x: p.x + size * 0.30 * scale, y: p.y + size * 0.06),
                    control: CGPoint(x: p.x, y: p.y - size * 0.24 * scale))
            case ..<0.78:
                // Wind-combed snow: two short parallel runs.
                for k in 0..<2 {
                    let dy = size * (0.05 + CGFloat(k) * 0.16) * scale
                    path.move(to: CGPoint(x: p.x - size * 0.24 * scale, y: p.y + dy))
                    path.addLine(to: CGPoint(x: p.x + size * 0.20 * scale, y: p.y + dy * 0.6))
                }
            default:
                // Crust broken open — a speck of what is underneath.
                path.addEllipse(in: CGRect(x: p.x - size * 0.09 * scale,
                                           y: p.y - size * 0.06 * scale,
                                           width: size * 0.18 * scale,
                                           height: size * 0.12 * scale))
            }
        case .mud:
            // A rut, as if something wheeled has been through.
            path.move(to: CGPoint(x: p.x - size * 0.26, y: p.y - size * 0.10))
            path.addLine(to: CGPoint(x: p.x + size * 0.24, y: p.y + size * 0.06))
        case .puddle:
            // A rim of light on standing water.
            path.addEllipse(in: CGRect(x: p.x - size * 0.26, y: p.y - size * 0.13,
                                       width: size * 0.52, height: size * 0.26))
        case .litter:
            // A leaf, on its side.
            path.move(to: CGPoint(x: p.x - size * 0.18, y: p.y))
            path.addQuadCurve(to: CGPoint(x: p.x + size * 0.18, y: p.y),
                              control: CGPoint(x: p.x, y: p.y - size * 0.20))
        case .parched:
            // A crack in dried-out ground.
            path.move(to: CGPoint(x: p.x - size * 0.20, y: p.y - size * 0.12))
            path.addLine(to: CGPoint(x: p.x, y: p.y + size * 0.04))
            path.addLine(to: CGPoint(x: p.x + size * 0.22, y: p.y - size * 0.06))
        }
        into[skin] = path
    }

    /// What the mark is drawn in.
    static func markColour(_ skin: Skin) -> Color {
        switch skin {
        case .snow, .drift:  return Color.white.opacity(0.26)
        case .puddle:        return Color(red: 0.70, green: 0.80, blue: 0.88).opacity(0.44)
        case .mud:           return Color(red: 0.14, green: 0.11, blue: 0.08).opacity(0.55)
        case .litter:        return Color(red: 0.62, green: 0.40, blue: 0.18).opacity(0.60)
        case .parched:       return Color(red: 0.22, green: 0.19, blue: 0.12).opacity(0.45)
        case .bare:          return .clear
        }
    }

    // MARK: - The wood overhead

    /// How much canopy stands over each map cell, 0…1 — built once per frame so
    /// autumn's leaf litter falls under the trees that dropped it rather than
    /// evenly over the valley.
    ///
    /// Only autumn asks for this, so the rest of the year pays nothing.
    static func canopy(map: LocalMap) -> [Double] {
        let cols = LocalMap.gridColumns, rows = LocalMap.gridRows
        var grid = [Double](repeating: 0, count: cols * rows)
        for tree in map.trees {
            let col = min(cols - 1, max(0, Int(tree.position.x * Double(cols))))
            let row = min(rows - 1, max(0, Int(tree.position.y * Double(rows))))
            // A grown tree drops more than a sapling, and a little falls on the
            // cells next door.
            let weight = 0.34 + tree.growth * 0.66
            grid[row * cols + col] += weight
            for (dc, dr) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                let c = col + dc, r = row + dr
                guard c >= 0, c < cols, r >= 0, r < rows else { continue }
                grid[r * cols + c] += weight * 0.34
            }
        }
        for i in grid.indices { grid[i] = min(1, grid[i] / 2.2) }
        return grid
    }

    // MARK: - Curve

    /// The classic smoothstep, used everywhere a season fades in or out.
    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        guard edge1 > edge0 else { return x < edge0 ? 0 : 1 }
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}
