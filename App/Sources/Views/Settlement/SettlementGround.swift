import SwiftUI
import EndlessFrontierCore

/// The earth itself, and the dark that hides the rest of it.
///
/// The ground used to be the fog grid painted in: one flat rectangle of colour
/// per cell, forty across and twenty-five down. On a phone that grid is three
/// times taller than it is wide, so a meadow came out as a *column* of green
/// and the whole valley read as a bar chart. Nothing in the world is worse to
/// look at than a landscape drawn on a spreadsheet.
///
/// Three things fix it, and all three are free:
///
/// 1. **A square grain.** The fog grid stays the game's grid — deposits, sight,
///    scouting all speak it — but the earth is drawn on a finer lattice
///    subdivided until its tiles are roughly square, so the *texture* of the
///    ground no longer inherits the aspect of a gameplay abstraction.
/// 2. **Interlocking edges.** A tile near the border of its cell sometimes
///    takes the neighbouring cell's cover, so grass and dirt dovetail instead
///    of meeting on a ruled line.
/// 3. **Grain on the surface.** Blades in grass, speckle in dirt, ripples in
///    sand, cracks in rock, sparkle in snow — one or two strokes on a minority
///    of tiles, batched per cover so a whole map is a handful of draws.
///
/// The fog gets the same treatment from the other side: instead of a black
/// staircase it falls off over three steps, so the edge of the known world
/// looks like distance rather than damage.
///
/// Strictly presentational, and a pure function of `(terrainSeed, biome, cell)`
/// — nothing here is stored and nothing writes back.
enum SettlementGround {

    /// How big a ground tile wants to be on screen, as a fraction of the
    /// canvas's short side. Small enough to have grain, big enough that a full
    /// map is hundreds of tiles rather than thousands.
    static let grain: CGFloat = 1.0 / 46.0

    /// Odds a tile near its cell's edge borrows the neighbour's cover.
    static let dither = 0.30

    /// Odds a tile carries a mark of texture.
    static let textureChance = 0.34

    // MARK: - The earth

    static func draw(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap,
        season: Season, zoom: CGFloat
    ) {
        let cols = LocalMap.gridColumns, rows = LocalMap.gridRows
        let cw = rect.width / CGFloat(cols), ch = rect.height / CGFloat(rows)
        let want = min(rect.width, rect.height) * grain
        // Subdivide whichever axis is coarser until a tile is roughly square.
        let subX = max(1, min(6, Int((cw / max(1, want)).rounded())))
        let subY = max(1, min(6, Int((ch / max(1, want)).rounded())))
        let tw = cw / CGFloat(subX), th = ch / CGFloat(subY)

        var batches: [GroundCover: Path] = [:]
        var shade: [GroundCover: Path] = [:]
        var texture: [GroundCover: Path] = [:]

        for index in map.exploredCells {
            let col = index % cols, row = index / cols
            guard row < rows else { continue }
            let own = map.cover(column: col, row: row)
            for sy in 0..<subY {
                for sx in 0..<subX {
                    let h = hash(map.terrainSeed &+ 0x9D_11_A5, col * 8 + sx, row * 8 + sy)
                    let cover = dithered(own, map: map, col: col, row: row,
                                         sx: sx, sy: sy, subX: subX, subY: subY, hash: h)
                    let x = rect.minX + CGFloat(col) * cw + CGFloat(sx) * tw
                    let y = rect.minY + CGFloat(row) * ch + CGFloat(sy) * th
                    // A hair of overlap, so no seam shows between tiles.
                    let tile = CGRect(x: x, y: y, width: tw + 0.7, height: th + 0.7)
                    batches[cover, default: Path()].addRect(tile)
                    // A third of the tiles are a shade darker, which is what
                    // keeps a field from reading as one printed colour.
                    if (h >> 12) & 7 < 2 {
                        shade[cover, default: Path()].addRect(tile)
                    }
                    if unit(h >> 20) < textureChance {
                        mark(&texture, cover: cover, at: CGPoint(x: x + tw / 2, y: y + th / 2),
                             size: min(tw, th), hash: h)
                    }
                }
            }
        }

        for (cover, path) in batches {
            context.fill(path, with: .color(coverColor(cover, season: season)))
        }
        for (_, path) in shade {
            context.fill(path, with: .color(Theme.ink.opacity(0.10)))
        }
        for (cover, path) in texture {
            context.stroke(path, with: .color(textureColour(cover, season: season)),
                           style: StrokeStyle(lineWidth: max(0.4, min(tw, th) * 0.10),
                                              lineCap: .round))
        }
    }

    /// The cover a sub-tile actually takes: its own cell's, unless it sits
    /// against a border and the roll says to take the neighbour's.
    private static func dithered(
        _ own: GroundCover, map: LocalMap, col: Int, row: Int,
        sx: Int, sy: Int, subX: Int, subY: Int, hash h: UInt64
    ) -> GroundCover {
        guard unit(h) < dither else { return own }
        // Which way this tile leans, from where it sits inside its cell.
        let dx = subX == 1 ? 0 : (sx == 0 ? -1 : (sx == subX - 1 ? 1 : 0))
        let dy = subY == 1 ? 0 : (sy == 0 ? -1 : (sy == subY - 1 ? 1 : 0))
        guard dx != 0 || dy != 0 else { return own }
        let nc = col + dx, nr = row + dy
        guard nc >= 0, nc < LocalMap.gridColumns, nr >= 0, nr < LocalMap.gridRows,
              map.exploredCells.contains(nr * LocalMap.gridColumns + nc) else { return own }
        return map.cover(column: nc, row: nr)
    }

    /// The grain of a given earth: what a tile of it has scratched on it.
    private static func mark(
        _ into: inout [GroundCover: Path], cover: GroundCover,
        at c: CGPoint, size: CGFloat, hash h: UInt64
    ) {
        let jx = (CGFloat(unit(h >> 4)) - 0.5) * size * 0.5
        let jy = (CGFloat(unit(h >> 8)) - 0.5) * size * 0.5
        let p = CGPoint(x: c.x + jx, y: c.y + jy)
        var path = into[cover] ?? Path()
        switch cover {
        case .grass, .meadow:
            // Two blades, leaning.
            for k in 0..<2 {
                let lean = (CGFloat(unit(h >> (10 + UInt64(k) * 3))) - 0.5) * size * 0.35
                path.move(to: CGPoint(x: p.x + CGFloat(k) * size * 0.22, y: p.y + size * 0.22))
                path.addLine(to: CGPoint(x: p.x + CGFloat(k) * size * 0.22 + lean,
                                         y: p.y - size * 0.24))
            }
        case .dirt:
            // Pebbles: short flat dashes.
            path.move(to: CGPoint(x: p.x - size * 0.16, y: p.y))
            path.addLine(to: CGPoint(x: p.x + size * 0.16, y: p.y))
        case .sand:
            // Wind ripples.
            path.move(to: CGPoint(x: p.x - size * 0.28, y: p.y))
            path.addQuadCurve(to: CGPoint(x: p.x + size * 0.28, y: p.y),
                              control: CGPoint(x: p.x, y: p.y - size * 0.20))
        case .rock:
            // A crack, angular.
            path.move(to: CGPoint(x: p.x - size * 0.22, y: p.y - size * 0.16))
            path.addLine(to: CGPoint(x: p.x + size * 0.04, y: p.y + size * 0.06))
            path.addLine(to: CGPoint(x: p.x + size * 0.24, y: p.y - size * 0.10))
        case .snow:
            // A glint.
            path.move(to: CGPoint(x: p.x - size * 0.12, y: p.y))
            path.addLine(to: CGPoint(x: p.x + size * 0.12, y: p.y))
            path.move(to: CGPoint(x: p.x, y: p.y - size * 0.12))
            path.addLine(to: CGPoint(x: p.x, y: p.y + size * 0.12))
        case .marsh:
            // A tuft of reed.
            path.move(to: CGPoint(x: p.x, y: p.y + size * 0.24))
            path.addLine(to: CGPoint(x: p.x - size * 0.14, y: p.y - size * 0.24))
            path.move(to: CGPoint(x: p.x, y: p.y + size * 0.24))
            path.addLine(to: CGPoint(x: p.x + size * 0.16, y: p.y - size * 0.20))
        }
        into[cover] = path
    }

    // MARK: - Colour

    /// The raw earth tones, before the season passes over them.
    private static func baseCover(_ cover: GroundCover) -> (r: Double, g: Double, b: Double) {
        switch cover {
        case .grass:  return (0.15, 0.22, 0.15)
        case .meadow: return (0.19, 0.26, 0.16)
        case .dirt:   return (0.23, 0.19, 0.14)
        case .sand:   return (0.29, 0.26, 0.17)
        case .rock:   return (0.19, 0.20, 0.23)
        case .snow:   return (0.30, 0.33, 0.39)
        case .marsh:  return (0.15, 0.23, 0.20)
        }
    }

    /// The ground as the season paints it: fresh in spring, warm in summer,
    /// rusted in autumn, and pale under winter snow.
    static func coverColor(_ cover: GroundCover, season: Season) -> Color {
        var (r, g, b) = baseCover(cover)
        switch season {
        case .spring:
            g *= 1.22; r *= 0.96
        case .summer:
            r *= 1.12; g *= 1.10; b *= 0.94
        case .autumn:
            r *= 1.38; g *= 1.02; b *= 0.82
        case .winter:
            // Everything cools and lightens toward snow, but keeps a trace of
            // what lies underneath.
            r = r * 0.45 + 0.26; g = g * 0.45 + 0.28; b = b * 0.45 + 0.34
        }
        return Color(red: min(1, r), green: min(1, g), blue: min(1, b))
    }

    /// What the grain on a given earth is drawn in — a lift of the ground's own
    /// colour, never a foreign one, or the map turns into confetti.
    private static func textureColour(_ cover: GroundCover, season: Season) -> Color {
        var (r, g, b) = baseCover(cover)
        let lift: Double = season == .winter ? 0.14 : 0.10
        r += lift; g += lift * 1.15; b += lift * 0.8
        let alpha: Double
        switch cover {
        case .grass, .meadow: alpha = 0.42
        case .snow: alpha = 0.34
        default: alpha = 0.30
        }
        return Color(red: min(1, r), green: min(1, g), blue: min(1, b)).opacity(alpha)
    }

    // MARK: - The dark

    /// The unknown, falling off in steps instead of standing as a wall.
    ///
    /// A single flat black over every uncharted cell drew the frontier as a
    /// staircase of hard rectangles — the most artificial thing on the screen,
    /// on the very edge the player is meant to be drawn towards. Cells are
    /// banded by how far they are from charted ground, so the dark deepens with
    /// distance and the near edge is a haze you can almost see through.
    static func fog(_ context: inout GraphicsContext, rect: CGRect, map: LocalMap) {
        let cols = LocalMap.gridColumns, rows = LocalMap.gridRows
        let cw = rect.width / CGFloat(cols), ch = rect.height / CGFloat(rows)
        // Three bands: touching the known, one step out, and the deep dark.
        var bands: [Int: Path] = [:]
        for row in 0..<rows {
            for col in 0..<cols where !map.exploredCells.contains(row * cols + col) {
                let band = min(2, distanceToKnown(map: map, col: col, row: row, limit: 2))
                bands[band, default: Path()].addRect(
                    CGRect(x: rect.minX + CGFloat(col) * cw, y: rect.minY + CGFloat(row) * ch,
                           width: cw + 0.6, height: ch + 0.6))
            }
        }
        let opacity: [Int: Double] = [0: 0.52, 1: 0.76, 2: 0.90]
        for band in [2, 1, 0] {
            guard let path = bands[band] else { continue }
            context.fill(path, with: .color(Theme.ink.opacity(opacity[band] ?? 0.9)))
        }
    }

    // MARK: - Noise
    //
    // The renderer's own, deliberately not the Core's: this decides where a
    // blade of grass is drawn, which is nobody's business but the canvas's.

    static func hash(_ seed: UInt64, _ a: Int, _ b: Int) -> UInt64 {
        var h = seed &* 0x9E37_79B9_7F4A_7C15
        h = (h ^ UInt64(bitPattern: Int64(a))) &* 0xD1B5_4A32_D192_ED03
        h = (h ^ UInt64(bitPattern: Int64(b))) &* 0xCBF2_9CE4_8422_2325
        return h ^ (h >> 29)
    }

    static func unit(_ h: UInt64) -> Double {
        Double(h & 0xFFFF_FFFF) / Double(0x1_0000_0000)
    }

    /// How many cells away the nearest charted ground is, up to `limit`.
    private static func distanceToKnown(map: LocalMap, col: Int, row: Int, limit: Int) -> Int {
        for radius in 1...max(1, limit) {
            for dy in -radius...radius {
                for dx in -radius...radius where max(abs(dx), abs(dy)) == radius {
                    let c = col + dx, r = row + dy
                    guard c >= 0, c < LocalMap.gridColumns, r >= 0, r < LocalMap.gridRows else { continue }
                    if map.exploredCells.contains(r * LocalMap.gridColumns + c) {
                        return radius - 1
                    }
                }
            }
        }
        return limit
    }
}
