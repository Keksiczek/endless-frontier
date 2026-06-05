import Foundation

/// Player-driven construction and colonist assignment on a settlement's
/// in-settlement grid (`ColonyMap`). Pure and deterministic: every function
/// takes a settlement and returns a new one, leaving the input unchanged on an
/// invalid action (matching the rest of the engine's style).
///
/// Building here keeps the spatial layout and the count-based
/// `Settlement.buildings` ledger in sync, so the resource loop — which still
/// reads `buildings` — stays the single source of truth for the economy.
public enum ColonyBuilder {
    /// Default grid size used when a settlement is built on for the first time.
    public static let defaultWidth = 12
    public static let defaultHeight = 12

    /// Ensures the settlement has a colony grid, creating an empty one if needed.
    public static func ensureMap(
        _ settlement: Settlement,
        width: Int = defaultWidth,
        height: Int = defaultHeight
    ) -> Settlement {
        guard settlement.colony == nil else { return settlement }
        var s = settlement
        s.colony = ColonyMap(width: width, height: height)
        return s
    }

    /// `true` if `definitionID` can be placed at `coord` right now (in bounds,
    /// tile free, and the building exists). A `nil` map is treated as an empty
    /// default-sized grid, since `place` will create one.
    public static func canPlace(
        _ settlement: Settlement,
        definitionID: String,
        at coord: TileCoord,
        registry: GameDataRegistry
    ) -> Bool {
        guard registry.building(definitionID) != nil else { return false }
        let map = settlement.colony ?? ColonyMap(width: defaultWidth, height: defaultHeight)
        return map.isInBounds(coord) && map.placement(at: coord) == nil
    }

    /// Places a building on the grid at `coord` and increments the matching
    /// `BuildingInstance` count. Creates the grid if the settlement has none.
    /// Returns the settlement unchanged if the action is invalid.
    public static func place(
        _ settlement: Settlement,
        definitionID: String,
        at coord: TileCoord,
        registry: GameDataRegistry
    ) -> Settlement {
        guard registry.building(definitionID) != nil else { return settlement }
        var s = ensureMap(settlement)
        guard var map = s.colony, map.isInBounds(coord), map.placement(at: coord) == nil else {
            return settlement
        }

        let placement = BuildingPlacement(
            id: placementID(definitionID, coord),
            definitionID: definitionID,
            coord: coord
        )
        map.placements.append(placement)
        s.colony = map

        // Keep the count-based economy ledger in step with the layout.
        if let i = s.buildings.firstIndex(where: { $0.definitionID == definitionID }) {
            s.buildings[i].count += 1
        } else {
            s.buildings.append(BuildingInstance(definitionID: definitionID, count: 1))
        }
        return s
    }

    /// Removes whatever building stands on `coord`, decrements the ledger, and
    /// frees any colonists that were assigned to it. Unchanged if the tile is
    /// empty.
    public static func remove(_ settlement: Settlement, at coord: TileCoord) -> Settlement {
        var s = settlement
        guard var map = s.colony,
              let index = map.placements.firstIndex(where: { $0.coord == coord }) else {
            return settlement
        }
        let removed = map.placements[index]
        map.placements.remove(at: index)
        s.colony = map

        // Free the colonists who worked here.
        for pawnID in removed.assignedPawnIDs {
            if let pi = s.pawns.firstIndex(where: { $0.id == pawnID }) {
                s.pawns[pi].assignedWork = .idle
            }
        }

        // Decrement the ledger, dropping the entry when it hits zero.
        if let bi = s.buildings.firstIndex(where: { $0.definitionID == removed.definitionID }) {
            s.buildings[bi].count -= 1
            if s.buildings[bi].count <= 0 {
                s.buildings.remove(at: bi)
            }
        }
        return s
    }

    /// Assigns a colonist to staff a placed building, setting their work to the
    /// kind that building employs. Respects the building's worker cap and moves
    /// the colonist off any building they were previously on. Unchanged if the
    /// pawn, placement or building can't be found, or the building is full.
    public static func assign(
        _ settlement: Settlement,
        pawnID: UUID,
        to placementID: UUID,
        registry: GameDataRegistry
    ) -> Settlement {
        var s = settlement
        guard var map = s.colony,
              let pIdx = map.placements.firstIndex(where: { $0.id == placementID }),
              s.pawns.contains(where: { $0.id == pawnID }),
              let def = registry.building(map.placements[pIdx].definitionID) else {
            return settlement
        }

        // Respect the worker cap (workers == 0 means no staffing, e.g. housing).
        let alreadyHere = map.placements[pIdx].assignedPawnIDs.filter { $0 != pawnID }.count
        guard def.workers > 0, alreadyHere < def.workers else { return settlement }

        // Move the pawn off every building, then onto this one.
        for i in map.placements.indices {
            map.placements[i].assignedPawnIDs.removeAll { $0 == pawnID }
        }
        map.placements[pIdx].assignedPawnIDs.append(pawnID)
        s.colony = map

        if let pi = s.pawns.firstIndex(where: { $0.id == pawnID }) {
            s.pawns[pi].assignedWork = workKind(for: def)
        }
        return s
    }

    /// Removes a colonist from any building and sets them idle.
    public static func unassign(_ settlement: Settlement, pawnID: UUID) -> Settlement {
        var s = settlement
        guard var map = s.colony else { return settlement }
        for i in map.placements.indices {
            map.placements[i].assignedPawnIDs.removeAll { $0 == pawnID }
        }
        s.colony = map
        if let pi = s.pawns.firstIndex(where: { $0.id == pawnID }) {
            s.pawns[pi].assignedWork = .idle
        }
        return s
    }

    /// The kind of work a building employs, derived from the resource it
    /// produces most. Buildings that produce nothing a colonist can work toward
    /// (e.g. pure energy, housing or defence) map to `.idle`.
    public static func workKind(for def: BuildingDefinition) -> WorkKind {
        var best: WorkKind = .idle
        var bestAmount = 0.0
        for kind in WorkKind.allCases {
            guard let resource = kind.resource else { continue }
            let amount = def.production[resource]
            if amount > bestAmount {
                bestAmount = amount
                best = kind
            }
        }
        return best
    }

    /// Lays a settlement's existing buildings out on a fresh grid, one tile per
    /// building (filling rows left to right). Used to seed the layout for a new
    /// game *without* touching the economy ledger — the caller already holds the
    /// matching `buildings`, so this only mirrors them spatially.
    public static func seededLayout(
        for buildings: [BuildingInstance],
        width: Int = defaultWidth,
        height: Int = defaultHeight
    ) -> ColonyMap {
        var map = ColonyMap(width: width, height: height)
        var index = 0
        for instance in buildings {
            for _ in 0..<max(1, instance.count) {
                let coord = TileCoord(index % width, index / width)
                guard map.isInBounds(coord) else { return map }
                map.placements.append(
                    BuildingPlacement(
                        id: placementID(instance.definitionID, coord),
                        definitionID: instance.definitionID,
                        coord: coord
                    )
                )
                index += 1
            }
        }
        return map
    }

    /// Best-effort: assigns a colonist to the first placed building that employs
    /// their current work and still has room. Leaves them as-is if none fits.
    public static func autoAssign(
        _ settlement: Settlement,
        pawnID: UUID,
        registry: GameDataRegistry
    ) -> Settlement {
        guard let map = settlement.colony,
              let pawn = settlement.pawns.first(where: { $0.id == pawnID }) else {
            return settlement
        }
        for placement in map.placements {
            guard let def = registry.building(placement.definitionID) else { continue }
            if workKind(for: def) == pawn.assignedWork,
               def.workers > 0,
               placement.assignedPawnIDs.count < def.workers {
                return assign(settlement, pawnID: pawnID, to: placement.id, registry: registry)
            }
        }
        return settlement
    }

    // MARK: - Deterministic placement ids

    /// A stable id for a placement, hashed from its definition and tile so the
    /// same build action always produces the same id (FNV-1a style, matching
    /// the seeding used elsewhere in the engine).
    private static func placementID(_ definitionID: String, _ coord: TileCoord) -> UUID {
        var h: UInt64 = 0x9E37_79B9_7F4A_7C15
        for byte in definitionID.utf8 {
            h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3
        }
        h = (h ^ UInt64(bitPattern: Int64(coord.x))) &* 0x0100_0000_01B3
        h = (h ^ UInt64(bitPattern: Int64(coord.y))) &* 0x0100_0000_01B3
        var rng = SeededRNG(seed: h ^ (h >> 29))
        return rng.nextUUID()
    }
}
