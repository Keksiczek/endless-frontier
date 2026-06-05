import Foundation

/// A coordinate on a settlement's in-settlement build grid (square tiles).
/// This is the *local* colony layout — distinct from `HexCoord`, which is the
/// world map. Origin is the top-left; x grows right, y grows down.
public struct TileCoord: Codable, Sendable, Equatable, Hashable {
    public let x: Int
    public let y: Int

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }
}

/// A single building physically placed on the colony grid, plus the colonists
/// assigned to staff it. References its `BuildingDefinition` by stable id.
///
/// The `id` is derived deterministically from the definition and coordinate
/// (not a random UUID) so that placing a building is reproducible — the same
/// build action on the same tile always yields the same placement, keeping the
/// simulation's determinism guarantee intact.
public struct BuildingPlacement: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let definitionID: String
    public var coord: TileCoord
    public var assignedPawnIDs: [UUID]

    public init(id: UUID, definitionID: String, coord: TileCoord, assignedPawnIDs: [UUID] = []) {
        self.id = id
        self.definitionID = definitionID
        self.coord = coord
        self.assignedPawnIDs = assignedPawnIDs
    }
}

/// The in-settlement spatial layout: a square grid of tiles holding placed
/// buildings. This is an **optional overlay** on top of the count-based
/// `Settlement.buildings` economy — the resource loop still reads `buildings`,
/// while this map is what the player lays out, sees, and assigns colonists to.
/// `ColonyBuilder` keeps the two in sync.
public struct ColonyMap: Codable, Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var placements: [BuildingPlacement]

    public init(width: Int = 12, height: Int = 12, placements: [BuildingPlacement] = []) {
        self.width = width
        self.height = height
        self.placements = placements
    }

    /// `true` if `coord` lies inside the grid.
    public func isInBounds(_ coord: TileCoord) -> Bool {
        coord.x >= 0 && coord.y >= 0 && coord.x < width && coord.y < height
    }

    /// The placement occupying `coord`, if any.
    public func placement(at coord: TileCoord) -> BuildingPlacement? {
        placements.first { $0.coord == coord }
    }

    /// `true` if every tile is occupied.
    public var isFull: Bool {
        placements.count >= width * height
    }

    /// Number of free tiles remaining.
    public var freeTiles: Int {
        max(0, width * height - placements.count)
    }
}
