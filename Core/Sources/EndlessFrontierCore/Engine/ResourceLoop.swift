import Foundation

/// The deterministic per-tick economic update: production, consumption,
/// population dynamics, morale drift, and recomputation of global stats.
public enum ResourceLoop {
    /// Base shelter every settlement has before any housing is built.
    public static let baseHousing: Double = 30
    /// Pollution above this level begins to drag morale down.
    public static let pollutionMoraleThreshold: Double = 40
    /// Baseline the threat level decays toward in the founding era.
    public static let baseThreat: Double = 10
    /// Extra threat baseline per era advanced — later eras are more dangerous,
    /// so raids and defense actually engage as a long-lived civilization grows.
    public static let eraThreatRampPerEra: Double = 6

    /// How many colonists a settlement can house (base + housing buildings).
    public static func housingCapacity(_ settlement: Settlement, registry: GameDataRegistry) -> Double {
        baseHousing + settlement.buildings.reduce(0.0) { acc, instance in
            acc + (registry.building(instance.definitionID)?.housing ?? 0) * Double(instance.count)
        }
    }

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
        let profile = s.specialization.profile

        // 1. Net production/consumption from buildings. A settlement's
        //    specialisation multiplies its gross production (not consumption),
        //    so e.g. an agricultural town grows far more food than it would
        //    balanced, at the cost of whatever it down-weights.
        var net = Resources()
        for instance in s.buildings {
            guard let def = registry.building(instance.definitionID) else { continue }
            let count = Double(instance.count)
            for resource in ResourceType.allCases {
                let produced = def.production[resource] * profile.productionMultiplier(resource)
                let consumed = def.consumption[resource]
                net[resource] = net[resource] + (produced - consumed) * count
            }
        }

        // 1b. Colony artifacts add passive production.
        let artifactProduction = ItemEngine.colonyProduction(s, registry: registry)
        for resource in ResourceType.allCases {
            net[resource] = net[resource] + artifactProduction[resource]
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

        // 4. Population dynamics — growth is capped by available housing.
        let capacity = housingCapacity(s, registry: registry)
        if starving {
            s.population = max(0, s.population * 0.99)
            s.stats.morale -= 1
        } else {
            let headroom = capacity > 0 ? max(0, 1 - s.population / capacity) : 0
            var growthFactor = (s.stats.morale - 50) / 5000   // ±1%/tick at morale extremes
            if growthFactor > 0 { growthFactor *= headroom }  // positive growth needs room
            s.population = max(0, s.population + s.population * growthFactor)
            if capacity > 0, s.population > capacity {
                s.stats.morale -= 0.5                          // overcrowding
            }
        }

        // 5. Morale drifts gently toward a building-driven target.
        let buildingMorale = s.buildings.reduce(0.0) { acc, instance in
            acc + (registry.building(instance.definitionID)?.moraleEffect ?? 0) * Double(instance.count)
        }
        let moraleTarget = min(100, max(0, 50 + buildingMorale + ItemEngine.colonyMoraleBonus(s, registry: registry)))
        s.stats.morale += (moraleTarget - s.stats.morale) * 0.1

        // 6. Defense drifts toward fortifications (buildings + artifacts).
        let buildingDefense = s.buildings.reduce(0.0) { acc, instance in
            acc + (registry.building(instance.definitionID)?.defense ?? 0) * Double(instance.count)
        }
        let defenseTarget = buildingDefense + ItemEngine.colonyDefenseBonus(s, registry: registry) + profile.defenseFlat
        s.stats.defense += (defenseTarget - s.stats.defense) * 0.15

        // 7. Pollution drifts toward what industry emits; heavy pollution hurts
        //    morale — the price of industrial production.
        let buildingPollution = s.buildings.reduce(0.0) { acc, instance in
            acc + (registry.building(instance.definitionID)?.pollution ?? 0) * Double(instance.count)
        }
        let pollutionTarget = buildingPollution + profile.pollutionFlat
        s.stats.pollution += (pollutionTarget - s.stats.pollution) * 0.1
        if s.stats.pollution > pollutionMoraleThreshold {
            s.stats.morale -= (s.stats.pollution - pollutionMoraleThreshold) * 0.02
        }
        s.stats = s.stats.clamped()

        // 8. Individual colonists: needs, mood, skilled work, morale pull.
        s = PawnEngine.advanceOneTick(s, registry: registry)

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
            let profile = settlement.specialization.profile
            for instance in settlement.buildings {
                guard let def = registry.building(instance.definitionID) else { continue }
                let count = Double(instance.count)
                knowledge += def.production[.knowledge] * profile.productionMultiplier(.knowledge) * count
                influence += def.production[.influence] * profile.productionMultiplier(.influence) * count
            }
        }
        g.knowledgeOutput = knowledge
        g.influenceOutput = influence

        // Prosperity drifts toward average morale.
        g.prosperity += (avgMorale - g.prosperity) * 0.05

        // Threat decays toward a baseline that climbs with each era, so a
        // long-lived civilization faces rising danger (events still spike it).
        let threatBaseline = baseThreat + Double(state.era.index) * eraThreatRampPerEra
        g.threatLevel += (threatBaseline - g.threatLevel) * 0.02

        return g.clamped()
    }
}
