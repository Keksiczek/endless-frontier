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
        s.settlements = s.settlements.map {
            advanceSettlement($0, registry: registry, config: config,
                              tick: state.tick, mapSeed: state.mapSeed, era: state.era)
        }
        s.globalStats = recomputeGlobalStats(s, registry: registry)
        return s
    }

    static func advanceSettlement(
        _ settlement: Settlement,
        registry: GameDataRegistry,
        config: WorldConfig,
        tick: Int = 0,
        mapSeed: UInt64 = 0,
        era: Era = .earlySettlement
    ) -> Settlement {
        var s = settlement
        let profile = s.specialization.profile
        // Everything the settlement's laws currently do.
        let laws = SocietyEngine.modifiers(s, registry: registry)
        if s.strikeTicksRemaining > 0 { s.strikeTicksRemaining -= 1 }

        // 1. Net production/consumption from buildings. A settlement's
        //    specialisation multiplies its gross production (not consumption),
        //    so e.g. an agricultural town grows far more food than it would
        //    balanced, at the cost of whatever it down-weights.
        var net = Resources()
        for instance in s.buildings {
            guard let def = registry.building(instance.definitionID) else { continue }
            let count = Double(instance.count)
            for resource in ResourceType.allCases {
                let produced = def.production[resource]
                    * profile.productionMultiplier(resource)
                    * config.seasonYieldMultiplier(for: resource, tick: tick)
                let consumed = def.consumption[resource]
                net[resource] = net[resource] + (produced - consumed) * count
            }
        }

        // 1b. Colony artifacts add passive production.
        let artifactProduction = ItemEngine.colonyProduction(s, registry: registry)
        for resource in ResourceType.allCases {
            net[resource] = net[resource] + artifactProduction[resource]
        }

        // 1c. Layout synergies: buildings placed next to complementary
        //     neighbours on the colony grid produce a little extra.
        let adjacencyProduction = ColonyBonus.adjacencyProduction(s, registry: registry)
        for resource in ResourceType.allCases {
            net[resource] = net[resource] + adjacencyProduction[resource]
        }

        // 1d. Standing laws: a trade road or a tithe brings in influence.
        net[.influence] = net[.influence] + laws.influencePerTick

        // 2. Apply building net production to storage. Food upkeep happens in
        //    `PawnEngine` — every inhabitant is a pawn and eats real meals.
        var storage = s.storage
        for resource in ResourceType.allCases {
            storage[resource] = storage[resource] + net[resource]
        }
        s.storage = storage.clamped(lower: 0, upper: s.storageCapacity)

        // 3. Population pressure: an empty larder and overcrowding both wear
        //    on morale. Growth itself is births (`PopulationEngine`).
        let capacity = housingCapacity(s, registry: registry)
        if s.storage[.food] <= 0 {
            s.stats.morale -= 1
        }
        if capacity > 0, s.population > capacity {
            s.stats.morale -= 0.5                              // overcrowding
        }

        // 5. Morale drifts gently toward a building-driven target.
        let buildingMorale = s.buildings.reduce(0.0) { acc, instance in
            acc + (registry.building(instance.definitionID)?.moraleEffect ?? 0) * Double(instance.count)
        }
        let moraleTarget = min(100, max(0, 50 + buildingMorale
                                        + ItemEngine.colonyMoraleBonus(s, registry: registry)
                                        + ColonyBonus.adjacencyMorale(s, registry: registry)
                                        + laws.moraleFlat))
        s.stats.morale += (moraleTarget - s.stats.morale) * 0.1

        // 6. Defense drifts toward fortifications (buildings + artifacts).
        let buildingDefense = s.buildings.reduce(0.0) { acc, instance in
            acc + (registry.building(instance.definitionID)?.defense ?? 0) * Double(instance.count)
        }
        let defenseTarget = buildingDefense + ItemEngine.colonyDefenseBonus(s, registry: registry)
            + profile.defenseFlat + laws.defenseFlat
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

        // 8. Put any idle adults (new arrivals, those who came of age) to work.
        s = LaborEngine.assignIdleAdults(s, registry: registry)

        // 9. Individual colonists: needs, mood, skilled work, morale pull.
        //    Gathering work is scaled by how full the local deposits & herd are;
        //    a strike stops the gatherers altogether.
        var factors = gatheringFactors(s.localMap)
        if s.strikeTicksRemaining > 0 {
            for work in [WorkKind.farming, .logging, .mining, .foraging, .hunting] {
                factors[work] = 0
            }
        }
        s = PawnEngine.advanceOneTick(s, registry: registry, tick: tick,
                                      gatheringFactors: factors, laws: laws)

        // 10. Deposits deplete under the harvest and regrow with the seasons —
        //     faster where the woods are protected by law.
        s = evolveDeposits(s, registry: registry, tick: tick, config: config,
                           regrowthMultiplier: laws.depositRegrowthMultiplier)

        // 11. Wildlife: the herd grows and is culled; predators may strike.
        s = WildlifeEngine.advanceOneTick(s, registry: registry, tick: tick, era: era, mapSeed: mapSeed)

        // 12. The life cycle: aging, deaths, pregnancies and births — family
        //     support puts more children in the cradles.
        s = PopulationEngine.advanceOneTick(s, registry: registry, tick: tick, mapSeed: mapSeed,
                                            birthRateMultiplier: laws.birthRateMultiplier)

        return s
    }

    /// How full each local deposit kind is, as a gathering-efficiency factor.
    /// A brimming forest yields at full rate; a nearly-exhausted one still
    /// yields something (colonists range farther), so it's a soft floor.
    static let depositFloorFactor: Double = 0.35
    /// Harvest a single assigned worker pulls from a deposit each tick.
    static let harvestPerWorker: Double = 0.45
    /// Fraction of a node's capacity it regrows each tick (before seasonality).
    static let depositRegrowthFraction: Double = 0.0009

    /// Per-work gathering-efficiency factors: each deposit-backed work scaled
    /// by how full its pool is, plus hunting scaled by the herd. Fed to
    /// `PawnEngine` so a depleted resource pulls its workers' output down.
    static func gatheringFactors(_ localMap: LocalMap?) -> [WorkKind: Double] {
        guard let localMap else { return [:] }
        var poolByKind: [LocalResourceKind: (amount: Double, capacity: Double)] = [:]
        for node in localMap.nodes {
            var entry = poolByKind[node.kind] ?? (0, 0)
            entry.amount += node.amount
            entry.capacity += node.capacity
            poolByKind[node.kind] = entry
        }
        var factors: [WorkKind: Double] = [:]
        for (kind, entry) in poolByKind {
            let fraction = entry.capacity > 0 ? entry.amount / entry.capacity : 1
            factors[kind.work] = depositFloorFactor + (1 - depositFloorFactor) * fraction
        }
        factors[.hunting] = WildlifeEngine.huntingFactor(localMap.wildlife)
        return factors
    }

    /// Depletes deposits by what the settlement's gatherers pulled this tick,
    /// then regrows every node toward its capacity at a season-scaled rate.
    static func evolveDeposits(
        _ settlement: Settlement,
        registry: GameDataRegistry,
        tick: Int,
        config: WorldConfig,
        regrowthMultiplier: Double = 1
    ) -> Settlement {
        guard var map = settlement.localMap, !map.nodes.isEmpty else { return settlement }
        let ticksPerYear = config.ticksPerYear

        // Demand per deposit kind from the workers assigned to harvest it.
        var demand: [LocalResourceKind: Double] = [:]
        for pawn in settlement.pawns where pawn.isAdult(ticksPerYear: ticksPerYear) && !pawn.isBroken {
            if let deposit = pawn.assignedWork.harvestedDeposit {
                let resource = pawn.assignedWork.resource ?? .food
                let season = config.seasonYieldMultiplier(for: resource, tick: tick)
                demand[deposit, default: 0] += harvestPerWorker * season
            }
        }

        // Deplete proportionally across the nodes of each kind.
        for kind in Set(map.nodes.map(\.kind)) {
            let want = demand[kind, default: 0]
            guard want > 0 else { continue }
            let indices = map.nodes.indices.filter { map.nodes[$0].kind == kind }
            let available = indices.reduce(0.0) { $0 + map.nodes[$1].amount }
            guard available > 0 else { continue }
            let taken = min(want, available)
            for i in indices {
                let share = map.nodes[i].amount / available
                map.nodes[i].amount = max(0, map.nodes[i].amount - taken * share)
            }
        }

        // Regrow toward capacity, faster in the growing seasons.
        for i in map.nodes.indices {
            let resource: ResourceType = map.nodes[i].kind == .field ? .food : .materials
            let season = config.seasonYieldMultiplier(for: resource, tick: tick)
            let regrow = map.nodes[i].capacity * depositRegrowthFraction * season * regrowthMultiplier
            map.nodes[i].amount = min(map.nodes[i].capacity, map.nodes[i].amount + regrow)
        }

        var s = settlement
        s.localMap = map
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
