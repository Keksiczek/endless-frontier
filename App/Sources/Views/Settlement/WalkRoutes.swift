import Foundation
import EndlessFrontierCore

/// **The streets, remembered.**
///
/// `SettlementRoute` works out a way round the buildings rather than through
/// them, and that is what `PathEngine` now wears its tracks along. The people
/// have to walk the same lines, or the canvas draws a street going round the
/// smithy and a colonist going straight over its roof — which is worse than
/// the straight line was, because now there is a made way beside them that they
/// are visibly ignoring.
///
/// A route is only worked out when nothing here already knows it. The canvas
/// asks thirty times a second and a colonist's two ends change a handful of
/// times an in-game day, so all but the first ask is a dictionary lookup.
/// Everything is dropped when the town changes shape — a new roof can close an
/// alley, and a remembered route through it would walk people into a wall.
///
/// Presentation only. Nothing here is written back to `WorldState` (rule 5);
/// the ground it reads is the colony's own layout and the wear `PathEngine`
/// already put there.
final class WalkRoutes: @unchecked Sendable {
    static let shared = WalkRoutes()

    /// Below this many tiles apart, a walk is a walk and not a journey: routing
    /// it can only ever return the straight line it already was, at the cost of
    /// a search.
    static let worthRouting = 3

    /// How many routes are kept. A town's people have far fewer distinct
    /// journeys than they have people — a household walks one street to one
    /// bench — so this is generous, and it is a ceiling rather than a target.
    static let mostRemembered = 900

    private struct Key: Hashable {
        let from: TileCoord
        let to: TileCoord
    }

    private let lock = NSLock()
    private var signature = 0
    private var ground: SettlementRoute.Ground?
    private var routes: [Key: [LocalPoint]] = [:]

    /// The way from `a` to `b` as points on the local map, or `nil` when the
    /// two are near enough that the straight line is the answer.
    ///
    /// Both ends are kept exactly as given: a colonist finishes standing at
    /// their bench, not at the middle of the tile it sits on.
    func route(from a: LocalPoint, to b: LocalPoint,
               colony: ColonyMap?, worn: [TileCoord: Double],
               water: ((LocalPoint) -> PathEngine.WaterDepth)? = nil) -> [LocalPoint]? {
        guard let colony, !colony.placements.isEmpty,
              let fromTile = SettlementGeometry.tile(at: a, in: colony),
              let toTile = SettlementGeometry.tile(at: b, in: colony),
              abs(fromTile.x - toTile.x) + abs(fromTile.y - toTile.y) >= Self.worthRouting
        else { return nil }

        let stamp = Self.signature(of: colony, worn: worn)
        let key = Key(from: fromTile, to: toTile)

        lock.lock()
        if stamp != signature {
            signature = stamp
            ground = SettlementRoute.Ground(colony: colony, worn: worn, water: water)
            routes.removeAll(keepingCapacity: true)
        }
        if let known = routes[key] {
            lock.unlock()
            return stitch(known, from: a, to: b)
        }
        let field = ground ?? SettlementRoute.Ground(colony: colony, worn: worn, water: water)
        ground = field
        lock.unlock()

        let ends = [colony.placement(at: fromTile), colony.placement(at: toTile)].compactMap { $0 }
        let tiles = SettlementRoute.walk(from: fromTile, to: toTile,
                                         ground: field, freeLots: ends)
        let points = tiles.map { SettlementGeometry.canvasPoint(tileX: $0.x, tileY: $0.y, in: colony) }

        lock.lock()
        if routes.count >= Self.mostRemembered { routes.removeAll(keepingCapacity: true) }
        routes[key] = points
        lock.unlock()
        return stitch(points, from: a, to: b)
    }

    /// The route's own tiles with the walker's real two ends on either end of
    /// it, and the tile centres nearest those ends dropped — otherwise somebody
    /// leaving a bench walks backwards to the middle of its tile first.
    private func stitch(_ points: [LocalPoint], from a: LocalPoint, to b: LocalPoint) -> [LocalPoint] {
        guard points.count > 2 else { return [a, b] }
        return [a] + points.dropFirst().dropLast() + [b]
    }

    /// What the town looks like, as one number. Changes when a building is
    /// placed, finished, moved or lost, and when the ways have been re-worn.
    private static func signature(of colony: ColonyMap, worn: [TileCoord: Double]) -> Int {
        var hasher = Hasher()
        hasher.combine(colony.width)
        hasher.combine(colony.height)
        hasher.combine(colony.placements.count)
        hasher.combine(colony.zones.count)
        hasher.combine(worn.count)
        for placement in colony.placements {
            hasher.combine(placement.coord.x)
            hasher.combine(placement.coord.y)
            hasher.combine(placement.width)
            hasher.combine(placement.height)
        }
        return hasher.finalize()
    }
}

/// Sampling a walk: where somebody is, a fraction of the way along a line of
/// points, and which way they are looking.
enum WalkAlong {
    /// The point `u` (0…1) of the way along `points`, measured by length so the
    /// pace is even round the corners rather than jumping at each one.
    static func point(_ points: [LocalPoint], at u: Double) -> (at: LocalPoint, heading: LocalPoint) {
        guard points.count > 1 else {
            let only = points.first ?? LocalPoint(x: 0.5, y: 0.5)
            return (only, only)
        }
        var lengths: [Double] = []
        var total = 0.0
        for i in 1..<points.count {
            let dx = points[i].x - points[i - 1].x, dy = points[i].y - points[i - 1].y
            let leg = (dx * dx + dy * dy).squareRoot()
            total += leg
            lengths.append(leg)
        }
        guard total > 0 else { return (points[0], points[points.count - 1]) }
        let want = min(max(0, u), 1) * total
        var walked = 0.0
        for i in lengths.indices {
            if walked + lengths[i] >= want || i == lengths.count - 1 {
                let within = lengths[i] > 0 ? (want - walked) / lengths[i] : 0
                let a = points[i], b = points[i + 1]
                return (LocalPoint(x: a.x + (b.x - a.x) * min(1, max(0, within)),
                                   y: a.y + (b.y - a.y) * min(1, max(0, within))), b)
            }
            walked += lengths[i]
        }
        return (points[points.count - 1], points[points.count - 1])
    }

    /// How long the whole walk is, in map units.
    static func length(_ points: [LocalPoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<points.count {
            let dx = points[i].x - points[i - 1].x, dy = points[i].y - points[i - 1].y
            total += (dx * dx + dy * dy).squareRoot()
        }
        return total
    }
}
