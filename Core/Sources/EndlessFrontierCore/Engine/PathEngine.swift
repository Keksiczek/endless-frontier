import Foundation

/// **What wears the ways inside a settlement.**
///
/// `RoadEngine` does this for the world map, between hexes, and the two are
/// deliberately not the same system: a world road is *built*, graded and paid
/// for, and a village track is only ever *walked*. Nobody decides to have a
/// path from the smithy to the granary. It is there because for forty years
/// somebody has gone that way twice a day.
///
/// So the rate is people, and the relief is grass. Every `interval` ticks:
///
/// 1. every tile's wear decays by a **share** of itself, not by a fixed amount
///    — a subtractive decay against a per-walker gain has exactly one
///    equilibrium and everything above it saturates (rule 6's shape in a
///    ledger);
/// 2. every colonist with a roof and work adds `gainPerWalker` to each tile
///    between the two;
/// 3. everybody with a roof and no work adds the same on the way to the green,
///    which is where the colony gathers.
///
/// Equilibrium is `gainPerWalker / decayPerRun × walkers` = **0.1 per walker**,
/// so a route needs a couple of households before it reads as a way at all
/// (`SettlementPaths.visibleAbove`) and about ten before it is a beaten street.
///
/// Deterministic and pure: no die is rolled here and no clock is read.
public enum PathEngine {
    /// How often the ways are re-worn, in ticks. A tick is about six in-game
    /// days, so this is roughly twice a year — the pattern of who lives where
    /// and works where changes over seasons, not over minutes, and this runs
    /// inside a catch-up that replays tens of thousands of ticks (rule 4).
    public static let interval = 30

    /// What one person walking one route contributes to each tile of it.
    public static let gainPerWalker = 0.012

    /// The share of a track the grass takes back each run.
    public static let decayPerRun = 0.12

    /// Below this a tile is dropped from the sparse field entirely.
    public static let forgetBelow = 0.01

    /// A journey longer than this many tiles is not counted.
    ///
    /// A hunter's job is a beast three-quarters of the way across the valley
    /// and outside the town altogether; drawing a made way to wherever a deer
    /// happened to be standing this season is exactly the invented drawing
    /// rule 18 forbids. Half the grid's width — a way across the town, not a
    /// way out of it.
    public static let furthestJourney = 20

    public static func advanceOneTick(_ state: WorldState, registry: GameDataRegistry) -> WorldState {
        guard state.tick % interval == 0 else { return state }
        var s = state
        for index in s.settlements.indices {
            s.settlements[index] = wear(s.settlements[index])
        }
        return s
    }

    /// One pass of wearing and weathering over a single settlement.
    public static func wear(_ settlement: Settlement) -> Settlement {
        guard let colony = settlement.colony else { return settlement }
        var s = settlement

        // Start from what is already there, decayed. Everything that is walked
        // again this pass is topped straight back up.
        var field: [TileCoord: Double] = [:]
        for tile in s.paths.tiles {
            let left = tile.wear * (1 - decayPerRun)
            if left > forgetBelow { field[tile.coord] = left }
        }

        let homes = Dictionary(colony.placements.map { ($0.id, $0) }) { a, _ in a }
        let green = TileCoord(SettlementGeometry.greenOrigin(colony.width) + SettlementGeometry.greenTiles / 2,
                              SettlementGeometry.greenOrigin(colony.height) + SettlementGeometry.greenTiles / 2)

        // **What the ground is, before anybody walks on it.** Built once for
        // the whole pass — a hundred colonists asking tile by tile what stands
        // where would walk the placements list a hundred times (rule 38).
        // Read off the field as it was *last* pass, so today's traffic gathers
        // onto yesterday's ways rather than onto ways it is laying as it goes:
        // an order-dependent route is a route that depends on the order pawns
        // happen to sit in the array, which is not determinism you can rely on.
        let ground = SettlementRoute.Ground(colony: colony, worn: s.paths.lookup(),
                                            water: waterDepth(s))
        // Two colonists out of the same house doing the same work walk the same
        // street. Routing it twice is the same answer for the same money.
        var routes: [Route: [TileCoord]] = [:]

        for pawn in s.pawns where !pawn.isAway {
            guard let homeID = pawn.homeID, let home = homes[homeID] else { continue }
            let from = centre(of: home)
            let to: TileCoord
            if let job = pawn.currentJob,
               let tile = SettlementGeometry.tile(at: job.position, in: colony) {
                to = tile
            } else {
                // No work: the green. A child, an elder and anybody between
                // posts still crosses the town, and the plaza being walked on
                // is the one piece of ground the colony always uses.
                to = green
            }
            guard abs(to.x - from.x) + abs(to.y - from.y) <= furthestJourney else { continue }
            let key = Route(from: from, to: to)
            let walked: [TileCoord]
            if let known = routes[key] {
                walked = known
            } else {
                // The two lots this journey runs between are the walker's own
                // ground; everything else standing in the way is gone round.
                let ends = [home, colony.placement(at: to)].compactMap { $0 }
                walked = SettlementRoute.walk(from: from, to: to,
                                              ground: ground, freeLots: ends)
                routes[key] = walked
            }
            for tile in walked {
                field[tile, default: 0] += gainPerWalker
            }
        }

        s.paths.replace(with: field, floor: forgetBelow)
        return s
    }

    /// **How deep the water is here.**
    ///
    /// Keks, having asked for the water to be real at all: *"udělej rovnou
    /// hlubokou a mělkou."* One `isWater` is a wall — it would send a colony
    /// the long way round a stream it has waded across every day of its life,
    /// and make the beach as unwalkable as the open sea. The shallows are the
    /// part of the water people actually use.
    public enum WaterDepth: Sendable, Equatable {
        /// Ground. Nothing to think about.
        case dry
        /// Ankle to knee — the surf on a beach, the edge of a channel, a ford.
        /// Slower going than a road and perfectly ordinary.
        case shallow
        /// Over your head. A colony that walks here is a colony drowning.
        case deep
    }

    /// What the water does on this settlement's ground, or `nil` where there is
    /// none — a dry valley pays nothing for a test it cannot fail.
    ///
    /// The river is only water where it **flows**: a dry wash on a desert map
    /// is a line on the ground people cross, and charging anything to walk over
    /// it would send the whole colony the long way round a ditch.
    public static func waterDepth(
        _ settlement: Settlement
    ) -> ((LocalPoint) -> WaterDepth)? {
        guard let map = settlement.localMap else { return nil }
        let shore = map.shore
        let river = map.river.flows ? map.river : nil
        guard shore != nil || river != nil else { return nil }
        return { p in
            // The sea shelves: `distanceInland` is negative out at sea, so the
            // first stretch past the waterline is where you can still stand.
            if let shore, shore.isWater(p) {
                return shore.distanceInland(p) > -shallowsReach ? .shallow : .deep
            }
            // A channel is deepest down its middle and shallow at both edges,
            // which is what makes a ford a place rather than a rule.
            if let river {
                let across = abs(p.y - river.y(atX: p.x))
                if across <= riverHalfWidth * 0.55 { return .deep }
                if across <= riverHalfWidth { return .shallow }
            }
            return .dry
        }
    }

    /// How far out from the waterline you can still put a foot down.
    public static let shallowsReach = 0.035

    /// How wide the channel is, either side of the river's line. The same
    /// margin `LocalMapGenerator.landPoint` keeps clear of it.
    public static let riverHalfWidth = 0.09

    /// One journey, as the two ends of it. Two people making the same journey
    /// are one route worked out once.
    struct Route: Hashable {
        let from: TileCoord
        let to: TileCoord
    }

    /// The middle tile of a placement's lot — where its door is, near enough.
    static func centre(of placement: BuildingPlacement) -> TileCoord {
        TileCoord(placement.coord.x + max(1, placement.width) / 2,
                  placement.coord.y + max(1, placement.height) / 2)
    }
}
