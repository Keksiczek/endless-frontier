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
    static func coverage(season: Season, progress: Double) -> Double {
        let p = max(0, min(1, progress))
        switch season {
        case .winter:
            // Lying by the first week, deep by midwinter, still deep at its end
            // — a thaw is spring's business, not winter's.
            return smoothstep(0.02, 0.40, p)
        case .spring:
            // The melt is *first*: spring opens as mud and dries out of it.
            return 1 - smoothstep(0.05, 0.62, p)
        case .autumn:
            return smoothstep(0.10, 0.70, p)
        case .summer:
            return smoothstep(0.22, 0.78, p)
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
            // A scallop: the lip of a drift, seen from above.
            path.move(to: CGPoint(x: p.x - size * 0.30, y: p.y + size * 0.08))
            path.addQuadCurve(to: CGPoint(x: p.x + size * 0.30, y: p.y + size * 0.06),
                              control: CGPoint(x: p.x, y: p.y - size * 0.24))
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
