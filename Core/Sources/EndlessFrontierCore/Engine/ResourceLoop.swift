import Foundation

/// The deterministic per-tick economic update: production, consumption,
/// population dynamics, morale drift, and recomputation of global stats.
public enum ResourceLoop {
    public static func advanceOneTick(_ state: WorldState, registry: GameDataRegistry) -> WorldState {
        var s = state
        let config = registry.config
        s.settlements = s.settlements.map { advanceSettlement($0, registry: registry, config: config) }
        s.globalStats = recomputeGlobalStats(s, registry: registry)
        return s
    }

    static func advanceSettlement(
        _ settlement: Settlement,
        registry: GameDataRegistry,
        config: WorldConfig
    ) -> Settlement {
        var s = settlement

        // 1. Net production/consumption from buildings.
        var net = Resources()
        for instance in s.buildings {
            guard let def = registry.building(instance.definitionID) else { continue }
            for resource in ResourceType.allCases {
                let perBuilding = def.production[resource] - def.consumption[resource]
                net[resource] = net[resource] + perBuilding * Double(instance.count)
            }
        }

        // 2. Population food upkeep.
        net[.food] = net[.food] - s.population * config.foodPerPersonPerTick

        // 3. Apply to storage; remember if food went into deficit before clamp.
        var storage = s.storage
        for resource in ResourceType.allCases {
            storage[resource] = storage[resource] + net[resource]
        }
        let starving = storage[.food] < 0
        s.storage = storage.clamped(lower: 0, upper: s.storageCapacity)

        // 4. Population dynamics.
        if starving {
            s.population = max(0, s.population * 0.99)
            s.stats.morale -= 1
        } else {
            let growthFactor = (s.stats.morale - 50) / 5000   // ±1%/tick at morale extremes
            s.population = max(0, s.population + s.population * growthFactor)
        }

        // 5. Morale drifts gently toward a building-driven target.
        let buildingMorale = s.buildings.reduce(0.0) { acc, instance in
            acc + (registry.building(instance.definitionID)?.moraleEffect ?? 0) * Double(instance.count)
        }
        let moraleTarget = min(100, max(0, 50 + buildingMorale))
        s.stats.morale += (moraleTarget - s.stats.morale) * 0.1
        s.stats = s.stats.clamped()

        // 6. Individual colonists: needs, mood, skilled work, morale pull.
        s = PawnEngine.advanceOneTick(s)

        return s
    }

    static func recomputeGlobalStats(_ state: WorldState, registry: GameDataRegistry) -> GlobalStats {
        var g = state.globalStats
        guard !state.settlements.isEmpty else { return g.clamped() }

        let count = Double(state.settlements.count)
        let avgStability = state.settlements.map(\.stats.stability).reduce(0, +) / count
        let avgMorale = state.settlements.map(\.stats.morale).reduce(0, +) / count

        // Stability tracks the average settlement stability.
        g.stability = avgStability

        // Research/influence outputs = gross production this tick.
        var knowledge = 0.0
        var influence = 0.0
        for settlement in state.settlements {
            for instance in settlement.buildings {
                guard let def = registry.building(instance.definitionID) else { continue }
                knowledge += def.production[.knowledge] * Double(instance.count)
                influence += def.production[.influence] * Double(instance.count)
            }
        }
        g.knowledgeOutput = knowledge
        g.influenceOutput = influence

        // Prosperity drifts toward average morale.
        g.prosperity += (avgMorale - g.prosperity) * 0.05

        // Threat decays gently toward a low baseline (events spike it back up).
        g.threatLevel += (10 - g.threatLevel) * 0.02

        return g.clamped()
    }
}
