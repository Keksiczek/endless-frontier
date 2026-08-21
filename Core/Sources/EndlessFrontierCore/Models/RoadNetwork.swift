import Foundation

/// **Every made way in the world, and how to get from here to there over it.**
///
/// Held as a dictionary keyed by `RoadLink.id` rather than an array, because
/// every question the game asks is *"is there a road on this edge"* and the
/// answer has to be cheap: pathfinding asks it once per neighbour per hex
/// visited, and the caravan engine asks it every tick.
///
/// Pure and `Sendable`, like everything else in the Core. Nothing here reaches
/// for a clock or an unseeded die, so two worlds from one seed lay the same
/// roads and route the same caravans over them.
public struct RoadNetwork: Codable, Sendable, Equatable {
    public private(set) var links: [String: RoadLink]

    public init(links: [RoadLink] = []) {
        self.links = Dictionary(links.map { ($0.id, $0) }) { _, latest in latest }
    }

    public var all: [RoadLink] {
        // Sorted, because a dictionary's order is not stable across launches
        // and anything that walks this list — a drawing, a save, a test —
        // would otherwise disagree with itself (see `SettlementGround.Tone`).
        links.values.sorted { $0.id < $1.id }
    }

    public var isEmpty: Bool { links.isEmpty }

    public func link(_ a: HexCoord, _ b: HexCoord) -> RoadLink? {
        links[RoadLink.key(a, b)]
    }

    /// Adds a road, or **upgrades** one that is already there.
    ///
    /// Upgrading is not the same as replacing: paving a road you already have
    /// starts from sound stone, so a colony that keeps its ways in repair is
    /// rewarded for it rather than starting again.
    public mutating func lay(_ link: RoadLink) {
        if let existing = links[link.id], existing.grade >= link.grade {
            // Never quietly downgrade a way somebody paid for.
            links[link.id] = RoadLink(a: existing.a, b: existing.b,
                                      grade: existing.grade,
                                      condition: max(existing.condition, link.condition))
            return
        }
        links[link.id] = link
    }

    public mutating func update(_ link: RoadLink) {
        links[link.id] = link
    }

    /// Takes a way off the map entirely — what a ruined road becomes, and what
    /// an enemy who cuts one leaves behind.
    public mutating func remove(_ a: HexCoord, _ b: HexCoord) {
        links.removeValue(forKey: RoadLink.key(a, b))
    }

    /// Every road that touches this hex.
    public func touching(_ coord: HexCoord) -> [RoadLink] {
        coord.neighbors().compactMap { link(coord, $0) }
    }
}

// MARK: - Getting there

extension RoadNetwork {
    /// The result of asking how far it is: the hexes passed through, and what
    /// the journey costs in *hex-equivalents of open plain*.
    public struct Route: Sendable, Equatable {
        public let hexes: [HexCoord]
        /// Cost in plain-hexes. Multiply by `travelTicksPerHex` for ticks.
        public let cost: Double
        /// True when every step of it runs on a made way. A caravan on a
        /// finished road is safer as well as faster; one that has to leave the
        /// road for a stretch is not.
        public let fullyMade: Bool

        public var hexCount: Int { max(0, hexes.count - 1) }
    }

    /// **Cheapest way from one hex to another**, over roads where they exist
    /// and across open country where they do not.
    ///
    /// Dijkstra rather than A*: the maps are small (a few hundred hexes at
    /// most) and a heuristic that has to stay admissible in the presence of
    /// roads *faster than the straight line* is a subtle thing to get wrong.
    /// Correct and cheap beats clever and nearly right.
    ///
    /// `mover` says what is travelling. A `rail` conveyance can only use rails;
    /// everything else may use anything, and takes what benefit its own
    /// `regionPace` allows.
    public func route(
        from start: HexCoord, to goal: HexCoord,
        regions: [HexCoord: Region],
        mover: Mover = .onFoot
    ) -> Route? {
        guard start != goal else { return Route(hexes: [start], cost: 0, fullyMade: true) }

        var best: [HexCoord: Double] = [start: 0]
        var cameFrom: [HexCoord: HexCoord] = [:]
        var offRoad: Set<HexCoord> = []
        var frontier: [(coord: HexCoord, cost: Double)] = [(start, 0)]
        var settled: Set<HexCoord> = []

        while !frontier.isEmpty {
            // A linear scan for the cheapest is fine at this size and keeps the
            // whole thing readable; a heap here would be optimising a search
            // over three hundred hexes.
            var pick = 0
            for (i, entry) in frontier.enumerated() where entry.cost < frontier[pick].cost {
                pick = i
            }
            let current = frontier.remove(at: pick)
            guard !settled.contains(current.coord) else { continue }
            settled.insert(current.coord)
            if current.coord == goal { break }

            for next in current.coord.neighbors() {
                // Only country the map actually has. The world is a finite
                // patch of hexes and a route may not wander off it.
                guard let region = regions[next] else { continue }
                guard let step = stepCost(from: current.coord, to: next,
                                          region: region, mover: mover) else { continue }
                let total = current.cost + step.cost
                if total < best[next] ?? .infinity {
                    best[next] = total
                    cameFrom[next] = current.coord
                    if !step.onRoad { offRoad.insert(next) } else { offRoad.remove(next) }
                    frontier.append((next, total))
                }
            }
        }

        guard let cost = best[goal] else { return nil }
        var hexes = [goal]
        var cursor = goal
        var made = true
        while let previous = cameFrom[cursor] {
            if offRoad.contains(cursor) { made = false }
            hexes.append(previous)
            cursor = previous
        }
        return Route(hexes: hexes.reversed(), cost: cost, fullyMade: made)
    }

    /// What one step costs, and whether it was taken on a made way.
    /// `nil` means the step is not available to this mover at all.
    func stepCost(
        from: HexCoord, to: HexCoord, region: Region, mover: Mover
    ) -> (cost: Double, onRoad: Bool)? {
        let ground = TerrainCost.of(region)
        guard let road = link(from, to) else {
            // No road. A rail conveyance cannot leave the rails — which is the
            // whole trade a railway asks you to make.
            guard mover != .onRails else { return nil }
            return (ground / mover.openCountryPace, false)
        }
        if mover == .onRails && road.grade != .rail {
            return nil
        }
        // A road takes the *country's* penalty off, up to what the road is
        // worth: this is why a made way through a fen buys so much more than
        // one across a plain, and why the pass is the piece worth holding.
        let eased = max(1, ground / road.effectiveSpeed)
        return (eased / mover.roadPace(road.grade), true)
    }

    /// Who is travelling. Only three answers matter to the routing itself; the
    /// finer differences between forty-six conveyances live in `regionPace`.
    public enum Mover: Equatable, Sendable {
        case onFoot
        /// Something with wheels or hooves, carrying its own `regionPace`
        /// relative to a walking party.
        case wheeled(pace: Double)
        /// A rail conveyance: fast, and it may not leave the rails.
        case onRails

        /// How much faster than a walking party across open ground.
        var openCountryPace: Double {
            switch self {
            case .onFoot: return 1
            // A cart off the road is barely quicker than the people leading it,
            // however fast it is on a made way. This is what stops "buy a lorry"
            // being a substitute for building anything.
            case let .wheeled(pace): return min(1.25, max(0.9, pace * 0.35))
            case .onRails: return 1
            }
        }

        /// …and on a made way of this grade, where the machine's own speed is
        /// allowed to tell.
        func roadPace(_ grade: RoadGrade) -> Double {
            switch self {
            case .onFoot: return 1
            case let .wheeled(pace):
                // Paving is what a fast machine is waiting for: a lorry gets
                // little from a track and everything from stone.
                let allowed: Double = grade >= .paved ? 1 : (grade == .road ? 0.55 : 0.25)
                return max(1, 1 + (pace - 1) * allowed)
            case .onRails: return 1
            }
        }
    }
}
