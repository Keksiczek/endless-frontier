import SwiftUI
import EndlessFrontierCore

/// **The ways worn into the town, sampled where the ground is drawn.**
///
/// The Core keeps wear per build-grid tile (`SettlementPaths`, written only by
/// `PathEngine`). The ground is drawn on the *local map's* grid, subdivided
/// finer than that, so a track has to be asked for at a point rather than at a
/// tile — otherwise a way comes out as a staircase of 34ths of the valley.
///
/// Sampled **bilinearly** between the four tiles around a point, which is what
/// gives a street soft shoulders instead of a hard edge, and read straight
/// through `SettlementGeometry` so the drawing and the simulation cannot
/// disagree about where a tile is (rule 35).
///
/// Presentation only. Nothing here writes anything (rule 1) — the wear comes
/// from journeys the engine already decided people make.
struct SettlementTracks {
    private let wear: [TileCoord: Double]
    private let width: Int
    private let height: Int

    /// How many steps a track's darkness is quantised into.
    ///
    /// The ground batches its fills by finished colour, so every extra step is
    /// another bucket over the whole valley. Three reads as a way with a
    /// shoulder either side of it; a continuous ramp would be a bucket per
    /// tile and no batching at all.
    static let steps = 3

    /// How far a fully beaten tile pulls the ground toward packed earth.
    static let deepestTint = 0.72

    /// Packed, walked-bare earth. Not the ground's own dirt colour: a street is
    /// darker and greyer than a ploughed field, because it is trodden rather
    /// than turned.
    static let earth = (r: 0.34, g: 0.28, b: 0.21)

    init?(settlement: Settlement?) {
        guard let settlement, let colony = settlement.colony,
              !settlement.paths.isEmpty else { return nil }
        wear = settlement.paths.lookup()
        width = max(1, colony.width)
        height = max(1, colony.height)
    }

    /// How beaten the ground is at a point of the local map, 0…1.
    func wear(atU u: Double, v: Double) -> Double {
        let heart = SettlementGeometry.heart, span = SettlementGeometry.span
        // Fractional build-grid coordinates, measured from tile *centres* so
        // the interpolation is symmetric about a tile rather than about its
        // top-left corner.
        let fx = ((u - heart.x) / span + 0.5) * Double(width) - 0.5
        let fy = ((v - heart.y) / span + 0.5) * Double(height) - 0.5
        let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
        let tx = fx - Double(x0), ty = fy - Double(y0)
        // Outside the town there is nothing to sample, and asking is common —
        // most of the valley is not the build grid.
        guard x0 >= -1, y0 >= -1, x0 <= width, y0 <= height else { return 0 }
        let a = wear[TileCoord(x0, y0)] ?? 0
        let b = wear[TileCoord(x0 + 1, y0)] ?? 0
        let c = wear[TileCoord(x0, y0 + 1)] ?? 0
        let d = wear[TileCoord(x0 + 1, y0 + 1)] ?? 0
        if a == 0 && b == 0 && c == 0 && d == 0 { return 0 }
        let top = a + (b - a) * tx
        let bottom = c + (d - c) * tx
        return top + (bottom - top) * ty
    }

    /// Which of `steps` bands of trodden-ness a point falls in, 0 for none.
    ///
    /// Nothing below `SettlementPaths.visibleAbove` shows at all — that is the
    /// Core's own line between trodden grass and a way, and the drawing must
    /// not draw one where the simulation says there is not one (rule 18).
    func band(atU u: Double, v: Double) -> Int {
        let value = wear(atU: u, v: v)
        guard value >= SettlementPaths.visibleAbove else { return 0 }
        let above = (value - SettlementPaths.visibleAbove) / (1 - SettlementPaths.visibleAbove)
        return min(Self.steps, 1 + Int(above * Double(Self.steps - 1) + 0.5))
    }
}
