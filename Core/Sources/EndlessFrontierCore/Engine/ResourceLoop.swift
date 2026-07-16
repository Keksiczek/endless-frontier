import Foundation

/// The deterministic per-tick economic update: production, consumption,
/// population dynamics, morale drift, and recomputation of global stats.
public enum ResourceLoop {
    /// Base shelter every settlement has before any housing is built.
    public static let baseHousing: Double = 30
    /// Pollution above this level begins to drag morale down.
    public static let pollutionMoraleThreshold: Double = 40
    /// Morale lost each tick a colony's grid can't meet its demand.
    public static let brownoutMoralePenalty: Double = 0.8
    /// Stability lost each tick a realm has no political capital left to
    /// govern with. Deliberately sharper than a brownout: the colony carries on
    /// in the dark, but an ungoverned realm comes apart.
    public static let ungovernedStabilityPenalty: Double = 1.2
    /// The stability a joyless colony tends toward, and how much its
    /// colonists' contentment lifts that. Morale 80 → a target near 70.
    public static let stabilityFloor: Double = 30
    public static let stabilityFromMorale: Double = 0.5
    /// How fast stability closes on its target. A fifth of morale's pace: a
    /// realm is shaken in a moment and settles over years.
    public static let stabilityRecoveryRate: Double = 0.02
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

    /// How much a settlement can stockpile (base + storage buildings), derived
    /// the same way housing is. Capacity used to be a flat 500 for every
    /// settlement in every era, so stores filled in the first years and stayed
    /// pinned at the cap forever — nothing was ever scarce, and so no choice
    /// ever cost anything. Deepening the stores is now something you build.
    public static func storageCapacity(_ settlement: Settlement, registry: GameDataRegistry) -> Double {
        registry.config.defaultStorageCapacity + settlement.buildings.reduce(0.0) { acc, instance in
            acc + (registry.building(instance.definitionID)?.storage ?? 0) * Double(instance.count)
        }
    }

    /// The power the colonists themselves draw each tick — light, heat, and
    /// everything an age plugs in.
    ///
    /// Energy pinned at the storage cap because the only thing drawing it was
    /// other buildings, and generation outran them several times over. A sink
    /// only bites when it scales with something *other* than buildings, which
    /// is exactly why food — eaten by people — was the one that always worked.
    /// Demand is zero in the early eras: no generation exists before the
    /// windmill, so charging for power would bankrupt a colony that has no way
    /// to answer.
    public static func domesticEnergyDemand(
        population: Double, era: Era, config: WorldConfig
    ) -> Double {
        guard era.index < config.eraEnergyDemand.count else { return 0 }
        return population * config.energyPerPersonPerTick * config.eraEnergyDemand[era.index]
    }

    /// What it costs in political capital to hold this many people, in this
    /// many places, together.
    ///
    /// Nothing consumed influence at all. As the Leader's standing it should be
    /// spent governing: a village settles its own business by talking, but a
    /// civilisation needs administration, and when that runs dry the realm
    /// frays — which is already how tribes break away (`DiplomacyEngine`).
    /// The per-settlement fee applies from the *second* town onward: the seat
    /// of power governs itself, but every other place needs someone sent to
    /// hold it. Charging it from the first town would bill a lone village that
    /// the population threshold is meant to exempt — and exempting it entirely
    /// would let a realm dodge administration forever by staying a scatter of
    /// hamlets, each just under the threshold.
    public static func administrationCost(
        population: Double, settlements: Int, config: WorldConfig
    ) -> Double {
        let governed = max(0, population - config.selfGoverningPopulation)
        let outposts = Double(max(0, settlements - 1))
        return governed * config.influencePerPersonPerTick
            + outposts * config.influencePerSettlement
    }

    /// What one instance of a building costs per tick to keep standing.
    ///
    /// Nothing consumed materials or influence at all — they were spent once at
    /// build time and never again — so every stockpile bar food ran to the cap
    /// and stayed pinned there, which is what made a mature colony's economy
    /// meaningless.
    ///
    /// Upkeep is a standing fraction of *what the building cost to raise*, in
    /// the same resources it cost. That keeps it honest with no hand-authoring
    /// across 46 entries: an arcology is a burden a hut is not, and a research
    /// campus that cost knowledge keeps drawing knowledge, which gives the
    /// knowledge stockpile a sink that outlives the tech tree. `upkeep` in the
    /// JSON overrides this outright (for a monument that needs nothing).
    ///
    /// The hand-authored `consumption` field stays separate: that's the
    /// building's *operating* draw (a factory's energy), not its maintenance.
    public static func upkeep(for def: BuildingDefinition, config: WorldConfig) -> Resources {
        if let explicit = def.upkeep { return explicit }
        var derived = Resources()
        for resource in ResourceType.allCases {
            derived[resource] = def.cost[resource] * config.upkeepRateOfCost
        }
        return derived
    }

    public static func advanceOneTick(_ state: WorldState, registry: GameDataRegistry) -> WorldState {
        var s = state
        let config = registry.config
        let settlementCount = s.settlements.count
        s.settlements = s.settlements.map {
            advanceSettlement($0, registry: registry, config: config,
                              tick: state.tick, mapSeed: state.mapSeed, era: state.era,
                              settlementCount: settlementCount)
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
        era: Era = .earlySettlement,
        settlementCount: Int = 1
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
        //    Upkeep is charged alongside operating consumption: a standing
        //    colony costs materials to keep standing, which is what stops the
        //    stores from simply filling and pinning at the cap forever.
        var net = Resources()
        for instance in s.buildings {
            guard let def = registry.building(instance.definitionID) else { continue }
            let count = Double(instance.count)
            let maintenance = upkeep(for: def, config: config)
            for resource in ResourceType.allCases {
                let produced = def.production[resource]
                    * profile.productionMultiplier(resource)
                    * config.seasonYieldMultiplier(for: resource, tick: tick)
                let consumed = def.consumption[resource] + maintenance[resource]
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

        // 1e. What the colonists themselves draw, as distinct from what their
        //     buildings burn: power to live by, and the political capital it
        //     takes to govern them. These scale with *population*, not with the
        //     building count — which is the whole reason they bite where a
        //     building-scaled cost never could.
        let energyDemand = domesticEnergyDemand(
            population: s.population, era: era, config: config)
        let administration = administrationCost(
            population: s.population, settlements: settlementCount, config: config)
        net[.energy] = net[.energy] - energyDemand
        net[.influence] = net[.influence] - administration

        // 2. Apply building net production to storage. Food upkeep happens in
        //    `PawnEngine` — every inhabitant is a pawn and eats real meals.
        //    Capacity is re-derived from the standing buildings first, so a
        //    save written before granaries granted storage simply picks up its
        //    real capacity here rather than needing a migration.
        s.storageCapacity = storageCapacity(s, registry: registry)
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
        // A grid that can't answer its demand means a colony living in the
        // dark; a treasury that can't pay its administration means a realm
        // nobody is holding together — which is what `SocietyEngine` and
        // `DiplomacyEngine` read when deciding on revolt and secession.
        if energyDemand > 0, s.storage[.energy] <= 0 {
            s.stats.morale -= brownoutMoralePenalty
        }
        if administration > 0, s.storage[.influence] <= 0 {
            s.stats.stability -= ungovernedStabilityPenalty
        }

        // 5. Morale drifts gently toward a building-driven target.
        let buildingMorale = s.buildings.reduce(0.0) { acc, instance in
            acc + (registry.building(instance.definitionID)?.moraleEffect ?? 0) * Double(instance.count)
        }
        let moraleTarget = min(100, max(0, 50 + buildingMorale
                                        + ItemEngine.colonyMoraleBonus(s, registry: registry)
                                        + ColonyBonus.adjacencyMorale(s, registry: registry)
                                        + laws.moraleFlat
                                        + FaithEngine.moraleBonus(s, registry: registry)))
        s.stats.morale += (moraleTarget - s.stats.morale) * 0.1

        // 5b. Stability drifts toward what the colonists' contentment can
        //     sustain. Every other write to stability in the engine is a
        //     subtraction — an uprising, isolation, a specialisation switch —
        //     and nothing ever put it back, so a realm could only ratchet down
        //     to zero and stay there forever. Recovery is deliberately far
        //     slower than the shocks: a wound heals over years, and a realm
        //     that has run out of anyone to govern it still loses ground faster
        //     than contentment can win it back.
        let stabilityTarget = min(100, max(0, stabilityFloor + s.stats.morale * stabilityFromMorale))
        s.stats.stability += (stabilityTarget - s.stats.stability) * stabilityRecoveryRate

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
        // Standing research bonuses ride on top of the building total. They
        // have to be re-added here: this assignment is what used to silently
        // erase every `modifier` effect in techs.json the tick after it landed.
        g.knowledgeOutput = knowledge + (state.statModifiers["knowledgeOutput"] ?? 0)
        g.influenceOutput = influence + (state.statModifiers["influenceOutput"] ?? 0)

        // Prosperity drifts toward average morale.
        g.prosperity += (avgMorale - g.prosperity) * 0.05

        // Threat decays toward a baseline that climbs with each era, so a
        // long-lived civilization faces rising danger (events still spike it).
        let threatBaseline = baseThreat + Double(state.era.index) * eraThreatRampPerEra
        g.threatLevel += (threatBaseline - g.threatLevel) * 0.02

        return g.clamped()
    }
}
