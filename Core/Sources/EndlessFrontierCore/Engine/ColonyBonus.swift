import Foundation

/// Computes the layout synergies on a settlement's colony grid: a building
/// rewards being placed next to complementary neighbours (see `AdjacencyRule`).
/// Pure and deterministic. Bonuses only exist when the settlement has a colony
/// grid, so settlements without a layout are entirely unaffected.
public enum ColonyBonus {
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

    /// Total extra morale contribution from all satisfied adjacency rules.
    public static func adjacencyMorale(_ settlement: Settlement, registry: GameDataRegistry) -> Double {
        var total = 0.0
        forEachSatisfiedRule(settlement, registry: registry) { rule in total += rule.morale }
        return total
    }

    /// Visits every adjacency rule that is currently satisfied (its building is
    /// placed next to a matching neighbour), once per matching neighbour.
    static func forEachSatisfiedRule(
        _ settlement: Settlement,
        registry: GameDataRegistry,
        _ body: (AdjacencyRule) -> Void
    ) {
        guard let map = settlement.colony else { return }
        var byCoord: [TileCoord: String] = [:]
        for placement in map.placements { byCoord[placement.coord] = placement.definitionID }

        for placement in map.placements {
            guard let def = registry.building(placement.definitionID), !def.adjacency.isEmpty else { continue }
            let neighbours = [
                TileCoord(placement.coord.x + 1, placement.coord.y),
                TileCoord(placement.coord.x - 1, placement.coord.y),
                TileCoord(placement.coord.x, placement.coord.y + 1),
                TileCoord(placement.coord.x, placement.coord.y - 1)
            ]
            for neighbour in neighbours {
                guard let neighbourID = byCoord[neighbour] else { continue }
                for rule in def.adjacency where rule.neighbor == neighbourID {
                    body(rule)
                }
            }
        }
    }
}
