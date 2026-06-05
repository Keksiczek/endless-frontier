import Foundation

/// Computes the spatial bonuses on a settlement's colony grid: building
/// adjacency synergies (see `AdjacencyRule`) and amenity zones. Pure and
/// deterministic. Bonuses only exist when the settlement has a colony grid, so
/// settlements without a layout are entirely unaffected.
public enum ColonyBonus {
    /// Caps the total morale a settlement can draw from painted zones, so a
    /// colony can't be paved entirely in parks for unbounded happiness.
    public static let maxZoneMorale: Double = 15

    /// Total extra production per tick from all satisfied adjacency rules.
    public static func adjacencyProduction(_ settlement: Settlement, registry: GameDataRegistry) -> Resources {
        var total = Resources()
        forEachSatisfiedRule(settlement, registry: registry) { rule in
            if let resource = rule.resource, rule.bonus != 0 {
                total[resource] = total[resource] + rule.bonus
            }
        }
        return total
    }

    /// Total extra morale from adjacency rules plus painted amenity zones.
    public static func adjacencyMorale(_ settlement: Settlement, registry: GameDataRegistry) -> Double {
        var total = 0.0
        forEachSatisfiedRule(settlement, registry: registry) { rule in total += rule.morale }
        return total + zoneMorale(settlement)
    }

    /// Morale contributed by painted zones (parks, plazas, gardens), capped.
    public static func zoneMorale(_ settlement: Settlement) -> Double {
        guard let map = settlement.colony else { return 0 }
        let raw = map.zones.reduce(0.0) { $0 + $1.kind.moralePerTile }
        return min(maxZoneMorale, raw)
    }

    /// Visits every adjacency rule that is currently satisfied — i.e. its
    /// building borders a matching neighbouring building — once per distinct
    /// neighbouring building (so a large footprint sharing several edges with a
    /// neighbour still only counts that neighbour once).
    static func forEachSatisfiedRule(
        _ settlement: Settlement,
        registry: GameDataRegistry,
        _ body: (AdjacencyRule) -> Void
    ) {
        guard let map = settlement.colony else { return }

        // Map every covered tile to the placement that owns it.
        var owner: [TileCoord: UUID] = [:]
        var definitionByID: [UUID: String] = [:]
        for placement in map.placements {
            definitionByID[placement.id] = placement.definitionID
            for tile in placement.footprint { owner[tile] = placement.id }
        }

        for placement in map.placements {
            guard let def = registry.building(placement.definitionID), !def.adjacency.isEmpty else { continue }

            // The distinct neighbouring buildings bordering this footprint.
            var neighbourIDs: Set<UUID> = []
            for tile in placement.footprint {
                let around = [
                    TileCoord(tile.x + 1, tile.y), TileCoord(tile.x - 1, tile.y),
                    TileCoord(tile.x, tile.y + 1), TileCoord(tile.x, tile.y - 1)
                ]
                for neighbour in around {
                    if let ownerID = owner[neighbour], ownerID != placement.id {
                        neighbourIDs.insert(ownerID)
                    }
                }
            }

            for neighbourID in neighbourIDs {
                guard let neighbourDefinition = definitionByID[neighbourID] else { continue }
                for rule in def.adjacency where rule.neighbor == neighbourDefinition {
                    body(rule)
                }
            }
        }
    }
}
