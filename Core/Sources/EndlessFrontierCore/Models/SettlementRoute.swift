import Foundation

/// **The way round, rather than the way through.**
///
/// `SettlementPaths.line` draws the shortest line between two tiles, and that
/// is what `PathEngine` wore its tracks along — so a way from the smithy to the
/// granary went straight over whatever stood between them. Keks, looking at his
/// town: *"Cesty to křižují přes všechno doprostřed, tak není ideální."*
///
/// The world map solved the same problem one scale up: `RoadEngine.cut` lays a
/// link between two hexes by what the ground costs rather than by where the
/// ruler falls. This is that, on the build grid — an A\* whose cost is what the
/// ground under the tile is:
///
/// - **open ground** is the unit of cost;
/// - **a track people already wear** is cheaper, so traffic gathers onto the
///   ways that exist instead of each pair of buildings inventing its own —
///   which is the whole reason a village has streets and not a cat's cradle;
/// - **a plaza or a garden path** the player laid out is cheaper still, so the
///   square you paint is the square people cross;
/// - **the ground a building owns** is dear enough that a walk goes round it,
///   but never forbidden: a lot with no way out of it must not strand the
///   person living in it, and the two ends of every walk are *inside* lots by
///   construction.
///
/// The search is boxed to the two ends plus a margin. A route across a town is
/// tens of tiles, not a thousand, and an unbounded A\* over 1156 tiles run once
/// per colonist per pass would be the most expensive thing in the tick.
///
/// Pure and deterministic: ties break on the tile's own coordinates, so the
/// same two ends always give the same street (rule 3).
public enum SettlementRoute {

    /// What one step across open ground costs.
    public static let openCost = 1.0

    /// What a beaten way costs instead, at full wear. A track is easier going
    /// *and* it is where people already are, and both pull the next walk onto
    /// it.
    public static let wornCost = 0.45

    /// What laid ground — a plaza, a garden walk — costs. Under a worn track:
    /// somebody paved this on purpose.
    public static let pavedCost = 0.35

    /// What crossing **water** costs.
    ///
    /// Keks: *"ať se věci negenerují a moc nechodí na moře — teď tam jsou POI,
    /// řeky, vše tam normálně chodí."* Measured by grepping for it: `isWater`
    /// is asked in exactly two places in the whole engine — planting a sapling
    /// and one generator fallback. Nothing about walking, hauling, routing,
    /// building or the beasts has ever asked. The water is drawn and it is not
    /// *there*.
    ///
    /// Dearer than a building and still not forbidden, on purpose: a colony
    /// laid out across a river must not strand the half of itself on the far
    /// bank, and a ford is a real thing. What this buys is that a walk goes
    /// round the water when there is any way round at all — which, on a coast,
    /// there always is.
    public static let acrossDeepWater = 40.0

    /// …and what wading through the shallows costs.
    ///
    /// Dear enough that a walk keeps to the sand when there is sand, cheap
    /// enough that a ford is a way across rather than a wall — about three
    /// times the going on open ground, which is roughly what it is.
    public static let acrossShallows = 3.0

    /// What crossing the ground a building stands on costs.
    ///
    /// High enough that any way round inside the search box wins, low enough
    /// that a lot walled in by its neighbours still has an answer. Seven open
    /// tiles is a generous detour for a building two or three across.
    public static let occupiedCost = 7.0

    /// How far outside the box between the two ends the search may wander.
    ///
    /// A detour has to be able to leave the straight line or it is not a
    /// detour. Six tiles is room to go round a four-tile works and back.
    public static let detourMargin = 6

    /// A ceiling on the search, so a pathological layout costs a bounded amount
    /// rather than the whole grid.
    static let mostNodes = 4000

    /// What the ground under each tile costs to walk on, built once for a whole
    /// pass rather than per journey (rule 38).
    ///
    /// `free` is the lots whose ground is not charged for — in practice the two
    /// buildings a journey runs between, so nobody pays a toll to leave home.
    public struct Ground: Sendable {
        let width: Int
        let height: Int
        var cost: [Double]

        /// `water` is the ground the map says is under water — the shore and,
        /// where it flows, the river. Passed in rather than read off the colony
        /// because the build grid knows nothing about either: a `ColonyMap` is
        /// tiles and lots, and the water lives on the `LocalMap` beside it.
        public init(colony: ColonyMap, worn: [TileCoord: Double],
                    water: ((LocalPoint) -> PathEngine.WaterDepth)? = nil) {
            width = max(1, colony.width)
            height = max(1, colony.height)
            cost = Array(repeating: openCost, count: width * height)
            if let water {
                for y in 0..<height {
                    for x in 0..<width {
                        let at = SettlementGeometry.canvasPoint(tileX: x, tileY: y, in: colony)
                        guard let index = index(TileCoord(x, y)) else { continue }
                        switch water(at) {
                        case .dry:     break
                        case .shallow: cost[index] = acrossShallows
                        case .deep:    cost[index] = acrossDeepWater
                        }
                    }
                }
            }
            for (coord, wear) in worn {
                guard let index = index(coord) else { continue }
                // Part-worn ground is part of the way there: a track at half
                // wear is half the saving of a beaten one.
                let share = min(1, max(0, wear))
                cost[index] = openCost + (wornCost - openCost) * share
            }
            for zone in colony.zones {
                guard let index = index(zone.coord) else { continue }
                cost[index] = min(cost[index], pavedCost)
            }
            for placement in colony.placements {
                for tile in placement.footprint {
                    guard let index = index(tile) else { continue }
                    cost[index] = occupiedCost
                }
            }
        }

        func index(_ coord: TileCoord) -> Int? {
            guard coord.x >= 0, coord.y >= 0, coord.x < width, coord.y < height else { return nil }
            return coord.y * width + coord.x
        }

        func cost(at coord: TileCoord) -> Double? {
            index(coord).map { cost[$0] }
        }
    }

    /// The way from `a` to `b`, tiles included at both ends.
    ///
    /// Falls back to the straight line when the two ends are the same tile,
    /// when either is off the grid, or when the bounded search finds nothing —
    /// a drawn way that is wrong is better than a colonist with nowhere to walk.
    public static func walk(
        from a: TileCoord, to b: TileCoord,
        ground: Ground, freeLots: [BuildingPlacement] = []
    ) -> [TileCoord] {
        guard a != b else { return [a] }
        guard ground.index(a) != nil, ground.index(b) != nil else {
            return SettlementPaths.line(from: a, to: b)
        }
        // The ground the walker's own two buildings stand on is theirs to cross.
        var toll = Set<Int>()
        for lot in freeLots {
            for tile in lot.footprint {
                if let index = ground.index(tile) { toll.insert(index) }
            }
        }
        func step(onto coord: TileCoord) -> Double? {
            guard let index = ground.index(coord) else { return nil }
            return toll.contains(index) ? openCost : ground.cost[index]
        }

        let minX = min(a.x, b.x) - detourMargin, maxX = max(a.x, b.x) + detourMargin
        let minY = min(a.y, b.y) - detourMargin, maxY = max(a.y, b.y) + detourMargin
        func inBox(_ c: TileCoord) -> Bool {
            c.x >= minX && c.x <= maxX && c.y >= minY && c.y <= maxY
        }

        // A\* with a Manhattan heuristic, which is admissible because the
        // cheapest ground costs `pavedCost` — scaled by it so the estimate can
        // never overshoot and the route stays a true cheapest one.
        var best: [TileCoord: Double] = [a: 0]
        var cameFrom: [TileCoord: TileCoord] = [:]
        var open: [(estimate: Double, cost: Double, at: TileCoord)] =
            [(heuristic(a, b), 0, a)]
        var settled = Set<TileCoord>()
        var expanded = 0

        while !open.isEmpty, expanded < mostNodes {
            // A small frontier; a linear pick keeps this a hundred lines
            // shorter than a heap and is measurably not the cost here.
            var pick = 0
            for i in open.indices where isBefore(open[i], open[pick]) { pick = i }
            let node = open.remove(at: pick)
            guard !settled.contains(node.at) else { continue }
            settled.insert(node.at)
            expanded += 1

            if node.at == b { return trace(cameFrom, to: b) }

            for next in neighbours(of: node.at) {
                guard inBox(next), !settled.contains(next), let toll = step(onto: next)
                else { continue }
                let cost = node.cost + toll
                if let known = best[next], known <= cost { continue }
                best[next] = cost
                cameFrom[next] = node.at
                open.append((cost + heuristic(next, b), cost, next))
            }
        }
        return SettlementPaths.line(from: a, to: b)
    }

    /// The four ways off a tile. Four and not eight on purpose: a town's ways
    /// run along the edges of the ground people own, and a diagonal cuts the
    /// corner off every lot it passes.
    static func neighbours(of coord: TileCoord) -> [TileCoord] {
        [TileCoord(coord.x + 1, coord.y), TileCoord(coord.x - 1, coord.y),
         TileCoord(coord.x, coord.y + 1), TileCoord(coord.x, coord.y - 1)]
    }

    static func heuristic(_ a: TileCoord, _ b: TileCoord) -> Double {
        Double(abs(a.x - b.x) + abs(a.y - b.y)) * pavedCost
    }

    /// Deterministic ordering for the frontier: cheapest estimate first, and
    /// where two agree, the tile that sorts first. Without the tie-break the
    /// same two ends could give two different streets on two runs (rule 3).
    static func isBefore(
        _ lhs: (estimate: Double, cost: Double, at: TileCoord),
        _ rhs: (estimate: Double, cost: Double, at: TileCoord)
    ) -> Bool {
        if lhs.estimate != rhs.estimate { return lhs.estimate < rhs.estimate }
        return (lhs.at.y, lhs.at.x) < (rhs.at.y, rhs.at.x)
    }

    static func trace(_ cameFrom: [TileCoord: TileCoord], to end: TileCoord) -> [TileCoord] {
        var out = [end]
        var at = end
        var guardCount = mostNodes
        while let previous = cameFrom[at], guardCount > 0 {
            out.append(previous)
            at = previous
            guardCount -= 1
        }
        return out.reversed()
    }
}
