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
/// `coord` is the **top-left origin**; the building occupies a `width × height`
/// footprint of tiles from there. The `id` is derived deterministically from
/// the definition and coordinate (not a random UUID) so that placing a building
/// is reproducible — the same build action on the same tile always yields the
/// same placement, keeping the simulation's determinism guarantee intact.
public struct BuildingPlacement: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let definitionID: String
    public var coord: TileCoord
    public var width: Int
    public var height: Int
    public var assignedPawnIDs: [UUID]

    public init(id: UUID, definitionID: String, coord: TileCoord,
                width: Int = 1, height: Int = 1, assignedPawnIDs: [UUID] = []) {
        self.id = id
        self.definitionID = definitionID
        self.coord = coord
        self.width = max(1, width)
        self.height = max(1, height)
        self.assignedPawnIDs = assignedPawnIDs
    }

    /// Every tile this building covers.
    public var footprint: [TileCoord] {
        var tiles: [TileCoord] = []
        for dy in 0..<max(1, height) {
            for dx in 0..<max(1, width) {
                tiles.append(TileCoord(coord.x + dx, coord.y + dy))
            }
        }
        return tiles
    }

    /// `true` if `tile` falls inside this building's footprint.
    public func covers(_ tile: TileCoord) -> Bool {
        tile.x >= coord.x && tile.x < coord.x + max(1, width)
            && tile.y >= coord.y && tile.y < coord.y + max(1, height)
    }

    // Resilient decoding: older saves predate `width`/`height`, so default them
    // to a 1×1 footprint rather than failing the whole settlement load.
    private enum CodingKeys: String, CodingKey {
        case id, definitionID, coord, width, height, assignedPawnIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        definitionID = try c.decode(String.self, forKey: .definitionID)
        coord = try c.decode(TileCoord.self, forKey: .coord)
        width = max(1, try c.decodeIfPresent(Int.self, forKey: .width) ?? 1)
        height = max(1, try c.decodeIfPresent(Int.self, forKey: .height) ?? 1)
        assignedPawnIDs = try c.decodeIfPresent([UUID].self, forKey: .assignedPawnIDs) ?? []
    }
}

/// A designation painted onto colony tiles — a park, plaza or garden. Zones are
/// an amenity layer independent of buildings: they make colonists happier.
public enum ZoneKind: String, Codable, Sendable, CaseIterable, Equatable {
    case park
    case plaza
    case garden

    /// Morale contributed per tile of this zone (summed, then capped).
    public var moralePerTile: Double {
        switch self {
        case .park: return 0.6
        case .plaza: return 0.5
        case .garden: return 0.4
        }
    }

    public var displayName: String { rawValue.capitalized }
}

/// One painted zone tile.
public struct ZoneTile: Codable, Sendable, Equatable {
    public let coord: TileCoord
    public let kind: ZoneKind

    public init(coord: TileCoord, kind: ZoneKind) {
        self.coord = coord
        self.kind = kind
    }
}

/// The in-settlement spatial layout: a square grid of tiles holding placed
/// buildings (with footprints) and painted amenity zones. This is an
/// **optional overlay** on top of the count-based `Settlement.buildings`
/// economy — the resource loop still reads `buildings`, while this map is what
/// the player lays out, sees, and assigns colonists to. `ColonyBuilder` keeps
/// the two in sync.
public struct ColonyMap: Codable, Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var placements: [BuildingPlacement]
    public var zones: [ZoneTile]

    public init(width: Int = 12, height: Int = 12,
                placements: [BuildingPlacement] = [], zones: [ZoneTile] = []) {
        self.width = width
        self.height = height
        self.placements = placements
        self.zones = zones
    }

    /// `true` if `coord` lies inside the grid.
    public func isInBounds(_ coord: TileCoord) -> Bool {
        coord.x >= 0 && coord.y >= 0 && coord.x < width && coord.y < height
    }

    /// The placement whose footprint covers `coord`, if any.
    public func placement(at coord: TileCoord) -> BuildingPlacement? {
        placements.first { $0.covers(coord) }
    }

    /// The zone painted on `coord`, if any.
    public func zoneKind(at coord: TileCoord) -> ZoneKind? {
        zones.first { $0.coord == coord }?.kind
    }

    /// Total tiles covered by buildings.
    public var occupiedTileCount: Int {
        placements.reduce(0) { $0 + max(1, $1.width) * max(1, $1.height) }
    }

    /// `true` if every tile is occupied by a building.
    public var isFull: Bool {
        occupiedTileCount >= width * height
    }

    /// Number of tiles not covered by any building.
    public var freeTiles: Int {
        max(0, width * height - occupiedTileCount)
    }

    // Resilient decoding: older saves predate `zones`.
    private enum CodingKeys: String, CodingKey {
        case width, height, placements, zones
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 12
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 12
        placements = try c.decodeIfPresent([BuildingPlacement].self, forKey: .placements) ?? []
        zones = try c.decodeIfPresent([ZoneTile].self, forKey: .zones) ?? []
    }
}
