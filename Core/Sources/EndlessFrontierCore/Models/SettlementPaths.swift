import Foundation

/// **The ways worn into a settlement's own ground.**
///
/// The world map has had roads for a while (`RoadNetwork`, per hex edge), and
/// the settlement had none at all — so a village read as boxes standing on
/// grass, with nothing between them that anybody had made. Keks: *"silnice
/// jsou jen na mapě světa i když jsem je chtěl viditelné na mapě osady."*
///
/// A track here is not built and not paid for. It is **worn**, by the journeys
/// the colony's own people already make: from the roof they sleep under to the
/// work they were given, and from a roof to the green for everybody who has no
/// work yet. Rule 69 is the whole design — a background rate has to come from
/// the thing that is *always true*, and people living somewhere and working
/// somewhere else is true for as long as the colony is. Nothing is invented
/// here that the simulation does not already decide (rule 18): the two ends of
/// every journey counted are `Pawn.homeID` and `Pawn.currentJob.position`.
///
/// Stored **sparse**, keyed on the build grid: a tile nobody crosses is absent
/// rather than zero. A grown colony wears a few hundred of its 1156 tiles, and
/// a dense array of doubles would be most of a save file saying nothing.
public struct PathTile: Codable, Sendable, Equatable {
    public let coord: TileCoord
    /// How beaten this piece of ground is, 0…1. `SettlementPaths.visibleAbove`
    /// is where it starts to read as a way rather than as trodden grass.
    public var wear: Double

    public init(coord: TileCoord, wear: Double) {
        self.coord = coord
        self.wear = min(1, max(0, wear))
    }
}

public struct SettlementPaths: Codable, Sendable, Equatable {
    public private(set) var tiles: [PathTile]

    public init(tiles: [PathTile] = []) {
        // Sorted on the way in, because a drawing, a save and a test all walk
        // this list and an unordered one would have them disagree.
        self.tiles = tiles.sorted { ($0.coord.y, $0.coord.x) < ($1.coord.y, $1.coord.x) }
    }

    public var isEmpty: Bool { tiles.isEmpty }

    /// Tiles beaten hard enough to read as a way.
    public var worn: [PathTile] { tiles.filter { $0.wear >= Self.visibleAbove } }

    public func wear(at coord: TileCoord) -> Double {
        tiles.first { $0.coord == coord }?.wear ?? 0
    }

    /// Every worn tile as a lookup, for anything asking tile-by-tile — a
    /// renderer sampling the whole grid does it thousands of times a frame and
    /// must not walk the array for each one (rule 38).
    public func lookup() -> [TileCoord: Double] {
        Dictionary(tiles.map { ($0.coord, $0.wear) }) { a, b in max(a, b) }
    }

    /// Below this a tile is trodden grass, not a track.
    ///
    /// Set so that **one** person walking a route habitually does not make a
    /// road out of it: `PathEngine` settles a route at about
    /// `0.1 × the number of people on it`, so a way needs a couple of
    /// households before it shows.
    public static let visibleAbove = 0.12

    // MARK: - Building it

    /// Sets a tile's wear, adding it if it is new. Kept private to the module
    /// so the only thing that writes wear is `PathEngine` — the canvas may
    /// read this and may never touch it (rule 1).
    mutating func set(_ coord: TileCoord, to wear: Double) {
        let value = min(1, max(0, wear))
        if let index = tiles.firstIndex(where: { $0.coord == coord }) {
            if value <= 0 {
                tiles.remove(at: index)
            } else {
                tiles[index].wear = value
            }
        } else if value > 0 {
            tiles.append(PathTile(coord: coord, wear: value))
            tiles.sort { ($0.coord.y, $0.coord.x) < ($1.coord.y, $1.coord.x) }
        }
    }

    /// Replaces the whole field at once, dropping anything the grass has taken
    /// back. Cheaper than `set` per tile when a whole pass is being rebuilt.
    mutating func replace(with wear: [TileCoord: Double], floor: Double) {
        tiles = wear.compactMap { coord, value in
            value > floor ? PathTile(coord: coord, wear: min(1, value)) : nil
        }
        .sorted { ($0.coord.y, $0.coord.x) < ($1.coord.y, $1.coord.x) }
    }

    // MARK: - Walking between two tiles

    /// Every tile a walk from `a` to `b` crosses, corners included.
    ///
    /// A **supercover** line rather than plain Bresenham: a diagonal step is
    /// taken as two, so the track is connected on the grid and does not come
    /// out as a dotted line of tiles touching only at their corners — which is
    /// what a way drawn tile by tile looks like when it is allowed to skip.
    /// The same way whichever end it is walked from. Bresenham's tie-break
    /// depends on which end it starts at, so a colonist walking to work and
    /// their neighbour walking home wore **two** streets a tile apart. The way
    /// is laid from the lower end and turned round for the walker who is going
    /// the other way (rule 35's shape: one road, one answer).
    public static func line(from a: TileCoord, to b: TileCoord) -> [TileCoord] {
        if (b.y, b.x) < (a.y, a.x) { return line(from: b, to: a).reversed() }
        var x = a.x, y = a.y
        let dx = abs(b.x - a.x), dy = abs(b.y - a.y)
        let sx = b.x > a.x ? 1 : -1, sy = b.y > a.y ? 1 : -1
        var tiles = [TileCoord(x, y)]
        var error = dx - dy
        // Bounded: the grid is finite and each turn of the loop moves one step
        // closer on one axis, so this cannot run longer than dx + dy.
        var guardCount = dx + dy + 2
        while (x != b.x || y != b.y) && guardCount > 0 {
            guardCount -= 1
            let doubled = error * 2
            if doubled > -dy && x != b.x {
                x += sx
                error -= dy
            } else if y != b.y {
                y += sy
                error += dx
            } else if x != b.x {
                x += sx
                error -= dy
            }
            tiles.append(TileCoord(x, y))
        }
        return tiles
    }
}
