import Foundation

/// Axial hex-grid coordinate. The world map is a hex grid so regions tile
/// cleanly and every region has six neighbours (good for gradual, adjacency-
/// based exploration and future map features).
public struct HexCoord: Codable, Sendable, Equatable, Hashable {
    public let q: Int
    public let r: Int

    public init(_ q: Int, _ r: Int) {
        self.q = q
        self.r = r
    }

    public static let origin = HexCoord(0, 0)

    /// The six axial neighbour directions.
    public static let directions: [HexCoord] = [
        HexCoord(1, 0), HexCoord(1, -1), HexCoord(0, -1),
        HexCoord(-1, 0), HexCoord(-1, 1), HexCoord(0, 1)
    ]

    public func neighbors() -> [HexCoord] {
        HexCoord.directions.map { HexCoord(q + $0.q, r + $0.r) }
    }

    /// Hex distance (number of steps) between two coordinates.
    public func distance(to other: HexCoord) -> Int {
        let dq = q - other.q
        let dr = r - other.r
        return (abs(dq) + abs(dq + dr) + abs(dr)) / 2
    }

    /// All coordinates within `radius` rings of the origin (radius 0 = just
    /// the origin), in a stable order.
    public static func disc(radius: Int) -> [HexCoord] {
        var coords: [HexCoord] = []
        for q in -radius...radius {
            let rLow = max(-radius, -q - radius)
            let rHigh = min(radius, -q + radius)
            for r in rLow...rHigh {
                coords.append(HexCoord(q, r))
            }
        }
        return coords
    }
}
