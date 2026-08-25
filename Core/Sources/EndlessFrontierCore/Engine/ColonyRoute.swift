import Foundation

/// A way across the settlement that goes **round** the buildings rather than
/// through them.
///
/// Keks, watching the valley: *"nyní se chodí přes domy."* Every walk in the
/// game was a straight line — `ErrandEngine` set off from a job and arrived at
/// a granary, `HaulEngine` carried a load home, and both took the shortest path
/// on the map, which runs through the middle of whatever stands in the way. On
/// a colony that had grown into a town that is most of the walks.
///
/// This is deliberately **not** a general pathfinder. It is A* over the colony's
/// own tile grid, which is the only grid buildings occupy, and it answers the
/// only question anybody asks: give me a line from here to there that does not
/// cross a roof. Everything outside the colony grid — the woods, the shore, the
/// far plots — is open ground and needs no route at all.
///
/// Cheap enough to sit where it does, and it has to be (rule 4): a route is
/// worked out **once, when a walk begins**, and is then a stored list of
/// corners the walker follows. Nothing here runs per tick.
///
/// Deterministic throughout: neighbours are walked in a fixed order and ties
/// break on the tile's own index, never on a dictionary's order.
public enum ColonyRoute {

    /// How far apart two points have to be before it is worth routing at all.
    /// Below this the walk is a few paces and no building fits in it.
    static let worthRouting: Double = 0.04

    /// The most tiles A* will open before giving up and letting them walk the
    /// straight line. A colony grid is a few hundred tiles; this is a fuse, not
    /// a budget.
    static let mostTilesSearched = 900

    // MARK: - What stands where

    /// Which building covers each tile, laid out flat so the answer is an index
    /// rather than a search.
    ///
    /// **This is the whole of §11.23's second half.** `ColonyMap.placement(at:)`
    /// is `placements.first { $0.covers(coord) }` — a linear walk of every
    /// building in the colony — and routing asks it *per sampled point along a
    /// line*: about a hundred and thirty samples for a walk across a 64×64 grid,
    /// times a hundred buildings, per walker, per tick. Measured on a 12 000-tick
    /// run: 2 582 of 2 596 samples under `advanceSettlement` were here.
    ///
    /// Built once — by `HaulEngine` at the top of its tick, by `corners` itself
    /// for a one-off caller — and then every lookup is an array subscript. The
    /// routes that come out are identical; this only changes what it costs to
    /// ask.
    public struct Occupancy: Sendable {
        let width: Int
        let height: Int
        /// Tile index → the building standing on it. Nil where the ground is open.
        private let byTile: [UUID?]
        /// Tiles standing in solid rock.
        ///
        /// **A massif is not a building, and routing only ever asked about
        /// buildings** — so colonists, haulers and errand-runners walked
        /// straight through the cliff face they were supposed to be mining.
        /// The stone lives on the *local map's* grid rather than the colony's,
        /// so each colony tile is tested by where its middle actually falls.
        private let solid: [Bool]

        public init(_ colony: ColonyMap, stone: StoneField = StoneField(),
                    landforms: [Landform] = []) {
            width = max(0, colony.width)
            height = max(0, colony.height)
            var tiles = [UUID?](repeating: nil, count: width * height)
            var rock = [Bool](repeating: false, count: width * height)
            // A ravine and a mesa are ground nobody crosses, exactly like a
            // massif — same question, so the same answer and the same array.
            let walls = landforms.filter { $0.kind.blocksMovement }
            if !stone.isEmpty || !walls.isEmpty {
                for y in 0..<height {
                    for x in 0..<width {
                        let middle = SettlementGeometry.canvasPoint(tileX: x, tileY: y, in: colony)
                        rock[y * width + x] = stone.block(at: middle) != nil
                            || walls.contains { $0.contains(middle) }
                    }
                }
            }
            solid = rock
            // `ColonyMap.placement(at:)` answers with the **first** placement
            // that covers a tile, so where two overlap the earlier one wins.
            // Walking the list backwards means `placements[0]` writes last and
            // is what stays — the same answer, from an array subscript.
            for placement in colony.placements.reversed() {
                let w = max(1, placement.width), h = max(1, placement.height)
                for y in placement.coord.y..<(placement.coord.y + h) {
                    guard y >= 0, y < height else { continue }
                    for x in placement.coord.x..<(placement.coord.x + w) {
                        guard x >= 0, x < width else { continue }
                        tiles[y * width + x] = placement.id
                    }
                }
            }
            byTile = tiles
        }

        public func placementID(at coord: TileCoord) -> UUID? {
            guard coord.x >= 0, coord.y >= 0, coord.x < width, coord.y < height
            else { return nil }
            return byTile[coord.y * width + coord.x]
        }

        /// Whether this tile is solid rock — impassable, and belonging to
        /// nobody, so it can never be in the `allowed` set the way the building
        /// somebody is walking *into* is.
        public func isSolidRock(at coord: TileCoord) -> Bool {
            guard coord.x >= 0, coord.y >= 0, coord.x < width, coord.y < height
            else { return false }
            return solid[coord.y * width + coord.x]
        }
    }

    /// The corners of a walk from `a` to `b` that keeps out of the buildings.
    ///
    /// Empty means "go straight" — either the straight line was already clear,
    /// one of the ends is off the colony grid, or no way round exists (a
    /// courtyard walled in by its own town). Returning empty rather than
    /// failing is deliberate: a colonist who cannot find a way round still has
    /// to be able to eat, and a walk that never happens is the shape of bug
    /// this project keeps producing (rule 22).
    /// Pass an `Occupancy` when the caller is routing more than one walk over
    /// the same colony — building it per walk is the cost this exists to avoid.
    public static func corners(
        from a: LocalPoint, to b: LocalPoint, in colony: ColonyMap?,
        stone: StoneField = StoneField(), landforms: [Landform] = [],
        occupancy: Occupancy? = nil
    ) -> [LocalPoint] {
        // A massif or a ravine blocks a walk even on ground nobody has built
        // on, so "no buildings" is no longer the same question as "nothing in
        // the way".
        let walled = landforms.contains { $0.kind.blocksMovement }
        guard let colony, !colony.placements.isEmpty || !stone.isEmpty || walled,
              SiegeField.distance(a, b) > worthRouting,
              let start = tile(a, in: colony), let goal = tile(b, in: colony)
        else { return [] }
        let where_ = occupancy ?? Occupancy(colony, stone: stone, landforms: landforms)
        // The building they are walking *to* is not in the way — they are going
        // inside it. Neither is the one they are stood in.
        let allowed = Set([where_.placementID(at: start),
                           where_.placementID(at: goal)].compactMap { $0 })
        guard crossesABuilding(from: a, to: b, in: colony, standing: where_, allowing: allowed)
        else { return [] }
        guard let tiles = search(from: start, to: goal, in: colony,
                                 standing: where_, allowing: allowed)
        else { return [] }
        return straighten(tiles, in: colony, standing: where_, allowing: allowed, from: a, to: b)
    }

    /// The total length of a walk through these corners — what the walk costs
    /// in time, so going round is slower than going through would have been.
    public static func length(from a: LocalPoint, through corners: [LocalPoint],
                              to b: LocalPoint) -> Double {
        var total = 0.0
        var here = a
        for corner in corners {
            total += SiegeField.distance(here, corner)
            here = corner
        }
        return total + SiegeField.distance(here, b)
    }

    // MARK: - Is anything in the way

    /// Whether the straight line from `a` to `b` passes over a roof.
    ///
    /// Sampled along the line at half a tile, which is fine for a grid this
    /// coarse: a building is at least one tile across, so it cannot hide
    /// between two samples.
    /// `standing` is optional so a one-off caller — a test, a single question
    /// asked once — does not have to build the colony's occupancy itself. The
    /// walkers pass one in, because they ask this a hundred times a tick.
    static func crossesABuilding(
        from a: LocalPoint, to b: LocalPoint, in colony: ColonyMap,
        standing: Occupancy? = nil, allowing allowed: Set<UUID>
    ) -> Bool {
        let standing = standing ?? Occupancy(colony)
        let span = SiegeField.distance(a, b)
        let tileSpan = SettlementGeometry.span(of: colony) / Double(max(colony.width, colony.height))
        let steps = max(2, Int((span / (tileSpan * 0.5)).rounded(.up)))
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let p = LocalPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            guard let coord = tile(p, in: colony) else { continue }
            // Rock first: a cliff belongs to nobody, so it can never be the
            // building they are walking into and is never allowed through.
            if standing.isSolidRock(at: coord) { return true }
            guard let standingHere = standing.placementID(at: coord) else { continue }
            if !allowed.contains(standingHere) { return true }
        }
        return false
    }

    // MARK: - The search

    /// A*, four-way, over the colony's tiles.
    static func search(
        from start: TileCoord, to goal: TileCoord, in colony: ColonyMap,
        standing: Occupancy, allowing allowed: Set<UUID>
    ) -> [TileCoord]? {
        func blocked(_ c: TileCoord) -> Bool {
            if standing.isSolidRock(at: c) { return true }
            guard let here = standing.placementID(at: c) else { return false }
            return !allowed.contains(here)
        }
        func index(_ c: TileCoord) -> Int { c.y * colony.width + c.x }
        func heuristic(_ c: TileCoord) -> Double {
            Double(abs(c.x - goal.x) + abs(c.y - goal.y))
        }

        var cameFrom: [Int: TileCoord] = [:]
        var cost: [Int: Double] = [index(start): 0]
        // A plain array kept sorted is faster than a heap at this size and,
        // more to the point, has an order that does not depend on anything but
        // the numbers in it.
        var open: [(tile: TileCoord, score: Double)] = [(start, heuristic(start))]
        var opened = 0

        while !open.isEmpty {
            open.sort { $0.score == $1.score ? index($0.tile) < index($1.tile) : $0.score < $1.score }
            let here = open.removeFirst().tile
            if here == goal {
                var path = [here]
                var cursor = here
                while let previous = cameFrom[index(cursor)] {
                    path.append(previous)
                    cursor = previous
                }
                return path.reversed()
            }
            opened += 1
            guard opened < mostTilesSearched else { return nil }

            let soFar = cost[index(here)] ?? 0
            for delta in [TileCoord(0, -1), TileCoord(-1, 0),
                          TileCoord(1, 0), TileCoord(0, 1)] {
                let next = TileCoord(here.x + delta.x, here.y + delta.y)
                guard colony.isInBounds(next), !blocked(next) else { continue }
                let stepped = soFar + 1
                if let known = cost[index(next)], known <= stepped { continue }
                cost[index(next)] = stepped
                cameFrom[index(next)] = here
                open.append((next, stepped + heuristic(next)))
            }
        }
        return nil
    }

    // MARK: - Making it a walk rather than a staircase

    /// Drops every corner the walker does not actually need.
    ///
    /// A* returns a tile-by-tile staircase, and a colonist who walks it looks
    /// like a piece on a board. Keeping only the corners where the line would
    /// otherwise clip a building turns it back into somebody cutting across a
    /// square — which is what a person does, and what the canvas should draw.
    static func straighten(
        _ tiles: [TileCoord], in colony: ColonyMap, standing: Occupancy,
        allowing allowed: Set<UUID>, from a: LocalPoint, to b: LocalPoint
    ) -> [LocalPoint] {
        let points = tiles.map { centre(of: $0, in: colony) }
        var kept: [LocalPoint] = []
        var here = a
        var i = 0
        while i < points.count {
            // Once the door is in sight, stop cornering and walk at it.
            if !crossesABuilding(from: here, to: b, in: colony,
                                 standing: standing, allowing: allowed) { break }
            // Otherwise cut to the furthest corner still in a straight line
            // from here. Nothing reachable leaves `furthest` at `i`, which
            // still moves us on a tile — a tight gap has to produce a walk
            // rather than nothing.
            var furthest = i
            for j in (i..<points.count).reversed()
            where !crossesABuilding(from: here, to: points[j], in: colony,
                                    standing: standing, allowing: allowed) {
                furthest = j
                break
            }
            kept.append(points[furthest])
            here = points[furthest]
            i = furthest + 1
        }
        return kept
    }

    // MARK: - Grid and canvas

    /// The tile a canvas point falls on, or nil if it is off the colony grid.
    static func tile(_ p: LocalPoint, in colony: ColonyMap) -> TileCoord? {
        guard colony.width > 0, colony.height > 0 else { return nil }
        let span = SettlementGeometry.span(of: colony)
        let fx = (p.x - SettlementGeometry.heart.x) / span + 0.5
        let fy = (p.y - SettlementGeometry.heart.y) / span + 0.5
        guard fx >= 0, fy >= 0, fx < 1, fy < 1 else { return nil }
        return TileCoord(min(colony.width - 1, Int(fx * Double(colony.width))),
                         min(colony.height - 1, Int(fy * Double(colony.height))))
    }

    /// …and the middle of a tile, back in canvas space.
    static func centre(of tile: TileCoord, in colony: ColonyMap) -> LocalPoint {
        SettlementGeometry.canvasPoint(tileX: tile.x, tileY: tile.y, in: colony)
    }
}
