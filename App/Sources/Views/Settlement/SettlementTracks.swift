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

    /// The made ways arriving from the world map, as segments across the
    /// valley: from the point they cross the map's edge in to the town.
    private let highways: [(from: LocalPoint, to: LocalPoint, halfWidth: Double)]

    init?(settlement: Settlement?, approaches: [RoadApproach] = []) {
        guard let settlement, let colony = settlement.colony else { return nil }
        guard !settlement.paths.isEmpty || !approaches.isEmpty else { return nil }
        wear = settlement.paths.lookup()
        width = max(1, colony.width)
        height = max(1, colony.height)
        let heart = SettlementGeometry.heart
        highways = approaches.map { approach in
            (from: approach.edgePoint, to: heart,
             halfWidth: Self.halfWidth(of: approach.link.grade))
        }
    }

    /// How wide a made way lies on the ground, in map units, measured from its
    /// middle. A build-grid tile is `span / 34` ≈ 0.021 across, so a track is
    /// about one tile wide and a railway about two — which is the difference
    /// between a way people walk and a way something is driven along.
    static func halfWidth(of grade: RoadGrade) -> Double {
        switch grade {
        case .track: return 0.008
        case .road:  return 0.011
        case .paved: return 0.013
        case .rail:  return 0.013
        }
    }

    /// How beaten the ground is at a point of the local map, 0…1 — the ways
    /// the town wore for itself and the ways the world laid to its door,
    /// whichever is the more trodden.
    func wear(atU u: Double, v: Double) -> Double {
        max(worn(atU: u, v: v), highway(atU: u, v: v))
    }

    /// A made way arriving from the world map, drawn into the same ground the
    /// town's own streets are — so a road does not stop dead at the fence and
    /// start again as a different kind of drawing.
    private func highway(atU u: Double, v: Double) -> Double {
        var best = 0.0
        for way in highways {
            let dx = way.to.x - way.from.x, dy = way.to.y - way.from.y
            let lengthSquared = max(1e-9, dx * dx + dy * dy)
            let t = max(0, min(1, ((u - way.from.x) * dx + (v - way.from.y) * dy) / lengthSquared))
            let px = way.from.x + dx * t, py = way.from.y + dy * t
            let distance = ((u - px) * (u - px) + (v - py) * (v - py)).squareRoot()
            guard distance < way.halfWidth else { continue }
            // Hard in the middle, feathered at the verge — a road has a
            // shoulder, and a hard edge on ground drawn at this grain reads as
            // a ruled line rather than as something laid on the earth.
            best = max(best, min(1, 1.15 - distance / way.halfWidth * 0.6))
        }
        return best
    }

    private func worn(atU u: Double, v: Double) -> Double {
        guard !wear.isEmpty else { return 0 }
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
