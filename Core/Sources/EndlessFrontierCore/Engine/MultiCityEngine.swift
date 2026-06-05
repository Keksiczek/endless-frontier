import Foundation

/// Per-tick multi-settlement economy: trade-route transfers, the isolation
/// stability penalty for unconnected settlements, and automatic outpost →
/// city promotion. Runs in the tick loop right after the resource loop.
public enum MultiCityEngine {
    public static func advanceOneTick(_ state: WorldState, registry: GameDataRegistry) -> WorldState {
        var s = state
        guard s.settlements.count > 1 || !s.tradeRoutes.isEmpty else {
            return promoteOutposts(s, config: registry.config)
        }
        s = applyTradeRoutes(s)
        s = applyIsolationPenalty(s, config: registry.config)
        s = promoteOutposts(s, config: registry.config)
        return s
    }

    /// Settlement IDs reachable from the capital through trade routes
    /// (treated as undirected edges). The capital is always connected.
    public static func connectedSettlementIDs(_ state: WorldState) -> Set<UUID> {
        guard let capital = state.settlements.first(where: { $0.kind == .capital })
            ?? state.settlements.first else { return [] }

        var adjacency: [UUID: Set<UUID>] = [:]
        for route in state.tradeRoutes {
            adjacency[route.fromID, default: []].insert(route.toID)
            adjacency[route.toID, default: []].insert(route.fromID)
        }

        var connected: Set<UUID> = [capital.id]
        var frontier: [UUID] = [capital.id]
        while let node = frontier.popLast() {
            for neighbour in adjacency[node] ?? [] where !connected.contains(neighbour) {
                connected.insert(neighbour)
                frontier.append(neighbour)
            }
        }
        return connected
    }

    // MARK: - Steps

    static func applyTradeRoutes(_ state: WorldState) -> WorldState {
        var s = state
        for route in s.tradeRoutes {
            guard let from = s.settlements.firstIndex(where: { $0.id == route.fromID }),
                  let to = s.settlements.firstIndex(where: { $0.id == route.toID }) else { continue }
            // A mercantile source settlement pushes more goods per tick.
            let throughput = route.amountPerTick * s.settlements[from].specialization.profile.tradeThroughput
            let available = min(throughput, s.settlements[from].storage[route.resource])
            guard available > 0 else { continue }
            let capacity = s.settlements[to].storageCapacity
            let room = max(0, capacity - s.settlements[to].storage[route.resource])
            let moved = min(available, room)
            s.settlements[from].storage[route.resource] -= moved
            s.settlements[to].storage[route.resource] += moved
        }
        return s
    }

    static func applyIsolationPenalty(_ state: WorldState, config: WorldConfig) -> WorldState {
        let connected = connectedSettlementIDs(state)
        var s = state
        s.settlements = s.settlements.map { settlement in
            guard settlement.kind != .capital, !connected.contains(settlement.id) else { return settlement }
            var copy = settlement
            copy.stats.stability = max(0, copy.stats.stability - config.isolationStabilityPenalty)
            return copy
        }
        return s
    }

    static func promoteOutposts(_ state: WorldState, config: WorldConfig) -> WorldState {
        var s = state
        s.settlements = s.settlements.map { settlement in
            guard settlement.kind == .outpost,
                  settlement.population >= config.cityUpgradePopulation,
                  settlement.stats.stability >= config.cityUpgradeStability else { return settlement }
            var copy = settlement
            copy.kind = .city
            return copy
        }
        return s
    }
}
