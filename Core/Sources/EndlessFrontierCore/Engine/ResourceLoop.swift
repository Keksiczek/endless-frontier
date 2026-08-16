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
            // `sleepers`, not `housing`: the ledger and the beds are one number
            // now. See `BuildingDefinition.sleepers`.
            acc + Double(registry.building(instance.definitionID)?.sleepers ?? 0)
                * Double(instance.count)
        }
    }

    /// How much a settlement can stockpile (base + storage buildings), derived
    /// the same way housing is. Capacity used to be a flat 500 for every
    /// settlement in every era, so stores filled in the first years and stayed
    /// pinned at the cap forever — nothing was ever scarce, and so no choice
    /// ever cost anything. Deepening the stores is now something you build.
    ///
    /// **Typed as of 2026-08-13** — see `BuildingDefinition.storage`. The base
    /// applies to every resource (a colony can always keep *something* of
    /// anything); past that, a store is only as deep as the buildings that hold
    /// **that** good. A granary no longer deepens the archive.
    public static func storageCapacity(
        _ settlement: Settlement, registry: GameDataRegistry
    ) -> Resources {
        var capacity = Resources.uniform(registry.config.defaultStorageCapacity)
        for instance in settlement.buildings {
            guard let def = registry.building(instance.definitionID) else { continue }
            for resource in ResourceType.allCases {
                capacity[resource] += def.storage[resource] * Double(instance.count)
            }
        }
        return capacity
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
    ///
    /// (Defined below `staffingFactors` — see `upkeep(for:config:)`.)

    /// What an unmanned building still yields. Not zero: a mill with no miller
    /// still turns for a while, and a hard floor would make one bad winter of
    /// deaths collapse a colony outright rather than merely set it back.
    public static let unstaffedFloor: Double = 0.4

    /// How well each kind of building is actually manned, as a production
    /// multiplier in `unstaffedFloor…1`.
    ///
    /// `LaborEngine.staffBuildings` keeps the rosters honest; this is what makes
    /// them *matter*. Output came from building counts alone, so an empty
    /// workshop produced exactly as much as a full one and the entire labour
    /// economy was decoration — you could lose half the colony and the ledger
    /// would not notice.
    ///
    /// A settlement with no grid laid out is taken as fully manned, so outposts
    /// and anything predating the colony layer are unaffected. Buildings that
    /// employ nobody (huts, granaries) never appear here and keep a factor of 1.
    public static func staffingFactors(
        _ settlement: Settlement, registry: GameDataRegistry
    ) -> [String: Double] {
        guard let colony = settlement.colony, !colony.placements.isEmpty else { return [:] }
        var seats: [String: (filled: Int, total: Int)] = [:]
        // How sound the buildings of each kind are, alongside how well manned.
        // A workshop with the roof off produces less than one with it on, and a
        // derelict one produces nothing — which is what makes keeping a town up
        // a claim on the colony rather than a cosmetic number.
        var soundness: [String: (sum: Double, count: Double)] = [:]
        for placement in colony.placements where !placement.underConstruction {
            guard let def = registry.building(placement.definitionID) else { continue }
            var state = soundness[placement.definitionID] ?? (sum: 0, count: 0)
            state.sum += BuildingEngine.output(placement.condition)
            state.count += 1
            soundness[placement.definitionID] = state
            guard def.workers > 0 else { continue }
            var entry = seats[placement.definitionID] ?? (filled: 0, total: 0)
            // Nobody is at a bench in a building that has fallen in.
            entry.filled += BuildingEngine.isWorking(placement)
                ? min(def.workers, placement.assignedPawnIDs.count) : 0
            entry.total += def.workers
            seats[placement.definitionID] = entry
        }
        var factors = seats.mapValues { entry -> Double in
            guard entry.total > 0 else { return 1 }
            let manned = Double(entry.filled) / Double(entry.total)
            return unstaffedFloor + (1 - unstaffedFloor) * manned
        }
        // …and how sound they are, which applies to every building, including
        // the ones nobody works in.
        for (id, state) in soundness where state.count > 0 {
            factors[id] = (factors[id] ?? 1) * (state.sum / state.count)
        }
        return factors
    }

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
                              settlementCount: settlementCount, language: state.language,
                              // Where this colony actually stands. A tundra
                              // valley in January is not a coastal one.
                              climate: Climate.of($0, in: state, registry: registry))
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
        settlementCount: Int = 1,
        language: GameLanguage = .cs,
        climate: Climate = .temperate
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
        //    And it matters who is standing at the bench: a workshop with
        //    nobody posted to it runs at `unstaffedFloor`, not at full tilt.
        let staffing = staffingFactors(s, registry: registry)
        var net = Resources()
        for instance in s.buildings {
            guard let def = registry.building(instance.definitionID) else { continue }
            let count = Double(instance.count)
            let maintenance = upkeep(for: def, config: config)
            let manned = staffing[instance.definitionID] ?? 1
            for resource in ResourceType.allCases {
                let produced = def.production[resource]
                    * profile.productionMultiplier(resource)
                    * config.seasonYieldMultiplier(for: resource, tick: tick)
                    * manned
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
        // …and whatever is chained at the gate. A wolf that stayed is worth
        // several spears, which is why gentling one is worth a season.
        let kennel = TamingEngine.bonuses(s)
        let defenseTarget = buildingDefense + ItemEngine.colonyDefenseBonus(s, registry: registry)
            + profile.defenseFlat + laws.defenseFlat + kennel.defense
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

        // 8. Put any idle adults (new arrivals, those who came of age) to work,
        //    then seat them at a building that wants their trade — a trade
        //    without an address is how workshops came to stand empty.
        s = LaborEngine.assignIdleAdults(s, registry: registry)
        // Seating people is done on a cadence, not every tick. A post changing
        // within ten minutes of game time is imperceptible, and the pass copies
        // the colony's placements — on the widened 18×18 grid, paying that
        // every tick made offline catch-up superlinear as a colony filled up.
        if tick % BuildingEngine.interval == 0 {
            // The town weathers, and the masons put it back. A building that
            // nobody keeps up stops working and stops sheltering anyone, which
            // is what makes the mason's trade outlive the building of the
            // thing.
            s = BuildingEngine.weather(s, registry: registry, tick: tick, climate: climate)
            s = BuildingEngine.repair(s, registry: registry)
            // …and what people are holding wears out with it. Same cadence and
            // for the same reason: this walks every colonist (rule 4).
            s = ItemEngine.wearTools(s, registry: registry, tick: tick)
        }
        if tick % LaborEngine.staffingInterval == 0 {
            // The colony's standing orders, moving one person at a time. Before
            // this, a policy set on a town of sixty changed nothing until sixty
            // people happened to fall idle — which is never.
            s = LaborEngine.rebalance(s, registry: registry)
            s = LaborEngine.staffBuildings(s, registry: registry)
            // And a roof over their head, held until it comes down. A colonist
            // with no bed sleeps badly and shows it — which is how a colony
            // that has outgrown its houses asks for another one.
            s = HouseholdEngine.assignHomes(s, registry: registry)
        }
        // …and each of them a concrete piece of work: which tree, which
        // outcrop, which scaffold. A trade says what a colonist does; a job
        // says what they are doing.
        if tick % JobBoard.interval == 0 {
            s = JobBoard.assign(s, registry: registry)
        }

        // 8b. Raise what's being built: sites draft hands, progress accrues,
        //     and a finished roof joins the economy ledger above.
        s = ConstructionEngine.advanceOneTick(s, registry: registry, tick: tick)

        // 9. Individual colonists: needs, mood, skilled work, morale pull.
        //    Gathering work is scaled by how full the local deposits & herd are;
        //    a strike stops the gatherers altogether.
        var factors = gatheringFactors(s.localMap, registry: registry)
        if s.strikeTicksRemaining > 0 {
            for work in [WorkKind.farming, .logging, .mining, .foraging, .hunting] {
                factors[work] = 0
            }
        }
        // Shutting the gates against a sickness costs the work of everybody
        // staying in. That is the decision — it is not a free save, and it is
        // the reason the quarantine order is worth putting in front of a player
        // rather than doing for them.
        let shut = PlagueEngine.workFactor(s)
        if shut < 1 {
            for work in WorkKind.allCases { factors[work] = (factors[work] ?? 1) * shut }
        }
        // 8c. Their own business — a need past its threshold sending somebody
        //     to the granary or to a fire — has moved to `ActionLoop`, which
        //     runs eight times inside this tick and *before* it. So a meal
        //     eaten on any step of this tick is already a mood by the time the
        //     pawn tick reads it, which is the ordering that clause wanted and
        //     could not have while a walk cost whole ticks (`WalkPace`).
        s = PawnEngine.advanceOneTick(s, registry: registry, tick: tick,
                                      gatheringFactors: factors, laws: laws,
                                      climate: climate)
        // 9b. Bleeding, mending, and the healers doing the mending. After the
        //     pawns' own tick so a wound taken this minute is bleeding by the
        //     next one — and so the healer's trade finally has something to do.
        s = MedicineEngine.advanceOneTick(s, registry: registry, tick: tick)
        // 9b-ii. And the one threat that gets worse as the colony gets better.
        //        After the healers, so a sickness tended this minute is a
        //        sickness passing rather than one deepening.
        s = PlagueEngine.advanceOneTick(
            s, registry: registry, tick: tick, era: era,
            season: Season(tick: tick, ticksPerYear: config.ticksPerYear), mapSeed: mapSeed)
        // 9b-iii. …and the people a full granary attracts who belong to nobody.
        s = BanditEngine.advanceOneTick(
            s, registry: registry, tick: tick, era: era, mapSeed: mapSeed)
        // 9c. The farmyard: hunters gentle what they can, and the beasts the
        //     colony already keeps eat, work and occasionally leave.
        s = TamingEngine.advanceOneTick(s, registry: registry, tick: tick, mapSeed: mapSeed)
        s = TamingEngine.keepAnimals(s, registry: registry, tick: tick, mapSeed: mapSeed)

        // 10. Deposits deplete under the harvest and regrow with the seasons —
        //     faster where the woods are protected by law.
        s = evolveDeposits(s, registry: registry, tick: tick, config: config,
                           mapSeed: mapSeed,
                           regrowthMultiplier: laws.depositRegrowthMultiplier)
        // 10a. And somebody carries it in. A felled trunk and a broken block
        //      are heaps on the ground until they are — but the haulers walk in
        //      `ActionLoop` now, eight times inside this tick, because a load
        //      has to *move* and a colony is not a week across.

        // 10a-ii. The harvest, and then the kitchens — in that order, and both
        //      *after* the haulers, so a sack carried in this tick can be
        //      cooked this tick rather than sitting a whole cadence in a colony
        //      that is hungry now.
        //
        //      This is the food chain that replaced a farmer's skill turning
        //      into meals wherever they stood: plots ripen and are reaped
        //      (`FarmEngine`), the grain is carried in like timber, and a cook
        //      turns it into what the colony actually eats (`CookingEngine`).
        s = FarmEngine.advanceOneTick(s, registry: registry, tick: tick,
                                      climate: climate, mapSeed: mapSeed)
        s = CookingEngine.advanceOneTick(s, registry: registry, tick: tick)
        // What there is no roof for goes over. On the staffing cadence rather
        // than every tick: it walks the whole shelf, and a colony one sack over
        // its granary for ten minutes of game time is not a story (rule 4).
        if tick % LaborEngine.staffingInterval == 0 {
            s = CookingEngine.spoil(s, registry: registry, tick: tick)
        }

        // 10b. Scouts chart the valley.
        s = chartGround(s, tick: tick, mapSeed: mapSeed, config: config)

        // 10c. Parties out at the valley's landmarks are advanced by
        //      `ActionLoop`, on the finer grid — not here.

        // 10d. The day's work also comes home as *things*: timber, ore, clay,
        //      hides — the raw end of the crafting tree.
        s = extractRawMaterials(s, tick: tick, config: config, factors: factors)

        // 11. Wildlife: the herd grows and is culled; predators may strike.
        s = WildlifeEngine.advanceOneTick(s, registry: registry, tick: tick, era: era,
                                          mapSeed: mapSeed, climate: climate)

        // 11b. Village life: chats, quarrels, weddings — bonds that feed the
        //      recreation need and fill the journal.
        s = SocialEngine.advanceOneTick(s, registry: registry, tick: tick, mapSeed: mapSeed)

        // 12. The life cycle: aging, deaths, pregnancies and births — family
        //     support puts more children in the cradles.
        s = PopulationEngine.advanceOneTick(s, registry: registry, tick: tick, mapSeed: mapSeed,
                                            birthRateMultiplier: laws.birthRateMultiplier,
                                            language: language)

        return s
    }

    /// How full each local deposit kind is, as a gathering-efficiency factor.
    /// A brimming forest yields at full rate; a nearly-exhausted one still
    /// yields something (colonists range farther), so it's a soft floor.
    static let depositFloorFactor: Double = 0.35
    /// Harvest a single assigned worker pulls from a deposit each tick.
    static let harvestPerWorker: Double = 0.45
    /// How many whole units of timber a felled trunk leaves at the stump.
    static let timberPerTree = 4
    /// Fraction of a node's capacity it regrows each tick (before seasonality).
    static let depositRegrowthFraction: Double = 0.0009

    /// Per-work gathering-efficiency factors: each deposit-backed work scaled
    /// by how full its pool is *and* by what the country is good for, plus
    /// hunting scaled by the herd. Fed to `PawnEngine` so a depleted resource
    /// pulls its workers' output down.
    ///
    /// The fullness term is deliberately *relative* (amount ÷ capacity), which
    /// means richer ground alone changes only how long a seam lasts, never what
    /// a day's work is worth. So biome affinity has to land here too, or a
    /// mountain's `materials: 1.5` still buys the colony nothing: the miner
    /// swings the same pick for the same stone, just for longer. Standing
    /// somewhere has to pay differently from standing somewhere else.
    static func gatheringFactors(
        _ localMap: LocalMap?, registry: GameDataRegistry = GameDataRegistry()
    ) -> [WorkKind: Double] {
        guard let localMap else { return [:] }
        let biome = registry.biome(localMap.biomeID)
        // Pool by *work*, not by deposit kind. Mining now covers plain rock,
        // iron seams and clay beds, so keying by kind wrote `factors[.mining]`
        // three times over and whichever entry happened to come last out of the
        // dictionary won — a silently wrong number, and one that could differ
        // between two runs of the same seed.
        var poolByWork: [WorkKind: (amount: Double, capacity: Double)] = [:]
        for node in localMap.nodes {
            var entry = poolByWork[node.kind.work] ?? (0, 0)
            entry.amount += node.amount
            entry.capacity += node.capacity
            poolByWork[node.kind.work] = entry
        }
        var factors: [WorkKind: Double] = [:]
        for (work, entry) in poolByWork {
            let fraction = entry.capacity > 0 ? entry.amount / entry.capacity : 1
            let fullness = depositFloorFactor + (1 - depositFloorFactor) * fraction
            factors[work] = fullness * LocalMapGenerator.affinity(biome, for: work.resource)
        }
        factors[.hunting] = WildlifeEngine.huntingFactor(localMap.wildlife)
        return factors
    }

    /// How far a scout walks from the heart before turning back, and how often
    /// one of them comes back with new ground.
    static let scoutRangeStep: Double = 0.012
    static let scoutTicksPerReveal = 12
    /// The circle the generator reveals at founding — where the frontier starts.
    static let scoutBaseReach: Double = 0.28
    /// How wide a swathe one returning scout adds to the map.
    static let scoutRevealRadius: Double = 0.07
    /// The furthest a scout will range unbidden. A map corner is 0.707 from the
    /// heart, so this must clear `0.707 - scoutRevealRadius` or the corners stay
    /// black forever no matter how long you scout — which is exactly what the
    /// old cap of 0.62 did.
    static let scoutMaxReach: Double = 0.80

    /// Scouts push the fog back a little at a time.
    ///
    /// `LocalMap.reveal` was called exactly once in the whole life of a world —
    /// by the generator, radius 0.28 around the heart — and never again, so the
    /// valley a colony lived in for centuries was a circle baked at birth.
    /// Meanwhile `WorkKind.scouting` is documented "reveals the fog of war" and
    /// `LaborEngine` staffs it with 5% of every colony's adults: at 79 souls,
    /// four people had a job whose only purpose no code performed.
    ///
    /// They now walk outward from the heart, so the known valley grows with how
    /// many you send and how long you leave them at it. Deterministic like the
    /// rest of the sim: where a scout looks comes from `(mapSeed, settlement,
    /// tick)`, never from the frame clock — the canvas's wandering colonists
    /// are presentation and must stay out of this.
    ///
    /// Two things used to keep the fog frozen in practice. Reach was derived
    /// from the *absolute world tick*, so it measured how old the world was
    /// rather than how far anyone had walked — a colony founded late started
    /// with the run of its valley, and the founding one crawled. And the reach
    /// cap of 0.62 could not carry a scout to a corner, so a map could never be
    /// charted however long you worked at it. Reach now grows from accumulated
    /// scout-steps held on the map itself, and the cap clears the corners.
    static func chartGround(
        _ settlement: Settlement, tick: Int, mapSeed: UInt64, config: WorldConfig
    ) -> Settlement {
        guard tick % scoutTicksPerReveal == 0, var map = settlement.localMap else { return settlement }
        // A charted valley is charted. Most of a long game is spent here, and
        // scanning the grid for dark cells that cannot exist is pure waste on
        // every offline catch-up.
        guard !map.isFullyCharted || map.scoutFocus != nil else { return settlement }
        let ticksPerYear = max(1, config.ticksPerYear)
        // A standing order that says nobody scouts means nobody scouts, from
        // the tick it is given.
        //
        // `LaborEngine` already refuses to *assign* anybody to a trade the
        // policy has switched off, and that was taken to be enough. It is not:
        // a colony is founded with Nadia already on the job
        // (`GameWorldFactory`), so a player who forbids scouting on day one had
        // a scout walking out anyway until the labour engine got round to
        // moving her. It charted ground, and how much depended on which tick
        // the reassignment happened to land — which is to say, on nothing the
        // player did. The order is read *here*, where the work is done, so it
        // takes effect immediately and does not depend on somebody else's
        // cadence.
        guard settlement.policy.stance(.scouting) != .off else { return settlement }
        let scouts = settlement.pawns.filter {
            $0.assignedWork == .scouting && $0.isAdult(ticksPerYear: ticksPerYear)
                && !$0.isBroken && !$0.isAway
        }.count
        guard scouts > 0 else { return settlement }

        var s = settlement
        var rng = SeededRNG(seed: societyLikeSeed(mapSeed: mapSeed, settlementID: s.id, tick: tick))
        // Every scout on the job this step is a step walked. The frontier moves
        // outward with the work, rather than re-treading home.
        map.scoutProgress += Double(scouts)
        let reach = min(scoutMaxReach, scoutBaseReach + map.scoutProgress * scoutRangeStep)
        let knownBefore = Set(map.pois.filter(\.discovered).map(\.id))
        for _ in 0..<scouts {
            let point: LocalPoint
            if let focus = map.scoutFocus {
                // Told where to go, they go — even past the range they'd wander
                // to on their own. Ordering the walk is the whole point.
                point = jitter(focus, by: scoutRevealRadius * 0.5, rng: &rng)
            } else if let frontier = map.unchartedCell(within: reach, rng: &rng) {
                point = frontier
            } else {
                break   // nothing left within reach worth walking to
            }
            map.reveal(around: point, radius: scoutRevealRadius)
        }
        s.localMap = map
        // Walking into a point of interest is a *find*: the discovery pays out
        // and the journal remembers the day. Before this, `reveal` flipped the
        // flag silently and the promised one-off reward never existed at all.
        for poi in map.pois where poi.discovered && !knownBefore.contains(poi.id) {
            s = grantPOIDiscovery(s, poi: poi, tick: tick)
        }
        return s
    }

    // MARK: - Raw materials

    /// How many worker-ticks of a trade it takes to bank one raw material.
    /// A whole unit of timber is a day's felling, not a swing of the axe.
    static let workerTicksPerRawUnit: Double = 14
    /// The item a hunter's day yields, alongside the meat.
    public static let hideItemID = "hide"
    /// …and the meat itself, which for two years was a word in this comment and
    /// nothing else: hunting banked a hide and put `.food` in the granary out of
    /// the hunter's skill, so the animal became a number and the leather became
    /// a thing. Now the carcass is the point and the hide is what is left over.
    public static let meatItemID = "meat"
    /// Meat against hide, per hunter-tick. Nobody goes out for leather.
    static let meatPerHide: Double = 2.0
    /// What a forager brings back besides the healer's herbs. Small — a basket
    /// of berries is a nice evening, not a granary — but it is the one wild food
    /// a colony has before it has ploughed anything, which is what keeps the
    /// first winter survivable.
    public static let berriesItemID = "berries"
    static let berriesPerForagerTick: Double = 0.8

    /// Banks the concrete goods the colony's labour actually produces.
    ///
    /// Gathering used to dissolve entirely into the abstract `materials` pool
    /// while `recipes.json` asked for `iron_ingot` and `timber_bundle` that
    /// nothing produced — so the crafting tree could only ever be fed by
    /// random loot. Now a logger's week is a stack of wood, a miner's is ore
    /// or clay depending on what this valley holds, and a hunter brings hides
    /// home with the meat.
    ///
    /// Deliberately *additive*: the abstract economy is untouched, so nothing
    /// that was balanced against it moves. This is the same work, also counted
    /// in things you can put on a forge.
    static func extractRawMaterials(
        _ settlement: Settlement, tick: Int, config: WorldConfig, factors: [WorkKind: Double]
    ) -> Settlement {
        guard let map = settlement.localMap, !map.nodes.isEmpty else { return settlement }
        let ticksPerYear = max(1, config.ticksPerYear)
        // How much of each kind of ground this valley holds. A trade that works
        // several kinds splits its week between them *in proportion* — four iron
        // seams and one quarry is ore country, and should come home as ore.
        // Splitting evenly by kind made a mountain yield exactly what a plain
        // with a single seam did, which quietly undid the point of putting ore
        // in the mountains at all.
        var capacityByKind: [LocalResourceKind: Double] = [:]
        for node in map.nodes {
            capacityByKind[node.kind, default: 0] += node.capacity
        }
        let present = Set(capacityByKind.keys)

        // Worker-ticks earned this tick, per raw material.
        var earned: [String: Double] = [:]
        for pawn in settlement.pawns
        where pawn.isAdult(ticksPerYear: ticksPerYear) && !pawn.isBroken && !pawn.isAway {
            let work = pawn.assignedWork
            let effort = factors[work] ?? 1
            guard effort > 0 else { continue }
            if work == .hunting {
                earned[hideItemID, default: 0] += effort
                earned[meatItemID, default: 0] += effort * meatPerHide
                continue
            }
            if work == .foraging {
                earned[berriesItemID, default: 0] += effort * berriesPerForagerTick
                // …and on to the herb beds below, which is the other half of
                // what a forager's day is.
            }
            // Timber and stone are not earned by the week any more: they are
            // *carried in*. A felled trunk leaves wood at the stump and a
            // broken block leaves stone at the face, and `HaulEngine` banks
            // them when somebody walks them home — so granting them here as
            // well would pay the colony twice for the same tree.
            let worked = work.harvestedDeposits
                .filter(present.contains)
                .filter { !HaulEngine.isHauled($0) }
            guard !worked.isEmpty else { continue }
            let total = worked.reduce(0.0) { $0 + (capacityByKind[$1] ?? 0) }
            guard total > 0 else { continue }
            for deposit in worked {
                guard let id = deposit.rawMaterialID else { continue }
                earned[id, default: 0] += effort * (capacityByKind[deposit] ?? 0) / total
            }
        }
        guard !earned.isEmpty else { return settlement }

        var s = settlement
        for (id, effort) in earned {
            let progress = s.rawProgress[id, default: 0] + effort
            let units = Int(progress / workerTicksPerRawUnit)
            if units > 0 {
                s.stockpile[id, default: 0] += units
            }
            // Carry the remainder, so slow work still arrives eventually
            // rather than being rounded away every tick.
            s.rawProgress[id] = progress - Double(units) * workerTicksPerRawUnit
        }
        return s
    }

    /// A point near `point`, kept on the map. Scouts sent to a spot fan out
    /// around it rather than all standing on the same stone.
    static func jitter(_ point: LocalPoint, by spread: Double, rng: inout SeededRNG) -> LocalPoint {
        let angle = rng.nextUnit() * 2 * .pi
        let radius = rng.nextUnit() * spread
        return LocalPoint(
            x: min(1, max(0, point.x + cos(angle) * radius)),
            y: min(1, max(0, point.y + sin(angle) * radius)))
    }

    /// The one-off reward a freshly discovered point of interest grants.
    static func grantPOIDiscovery(_ settlement: Settlement, poi: LocalPOI, tick: Int) -> Settlement {
        var s = settlement
        func deposit(_ resource: ResourceType, _ amount: Double) {
            s.storage[resource] = min(s.storageCapacity[resource], s.storage[resource] + amount)
        }
        switch poi.kind {
        case .ruins:
            deposit(.knowledge, 18)
        case .cave:
            deposit(.materials, 25)
        case .spring:
            for i in s.pawns.indices {
                s.pawns[i].health = min(100, s.pawns[i].health + 8)
            }
        case .treasure:
            deposit(.materials, 15)
            deposit(.influence, 12)
        case .shrine:
            for i in s.pawns.indices {
                s.pawns[i].needs.recreation = min(100, s.pawns[i].needs.recreation + 5)
            }
            if s.faith.cultID != nil {
                s.faith.faith = min(100, s.faith.faith + 5)
            }
        case .wreck:
            deposit(.materials, 30)
        case .orchard:
            deposit(.food, 20)
        case .hermit:
            // He gives nothing on the doorstep. Come back and sit down.
            deposit(.knowledge, 6)
        case .watchtower:
            deposit(.influence, 8)
        case .saltPan:
            deposit(.food, 14)
        case .barrow:
            // Finding a grave is not the same as opening one.
            deposit(.influence, 6)
        case .starfall:
            deposit(.knowledge, 20)
            s.stats.morale = min(100, s.stats.morale + 3)
        }
        s.journal.append(tick: tick, kind: .discovery, text: poi.kind.discoveryText)
        return s
    }

    /// A per-settlement, per-tick seed. Mirrors `SocietyEngine.societySeed`'s
    /// shape so scouting stays reproducible for a given world.
    static func societyLikeSeed(mapSeed: UInt64, settlementID: UUID, tick: Int) -> UInt64 {
        var h: UInt64 = mapSeed &* 0x9E37_79B9_7F4A_7C15
        let b = settlementID.uuid
        h ^= UInt64(b.0) << 56 | UInt64(b.1) << 48 | UInt64(b.2) << 40 | UInt64(b.3) << 32
            | UInt64(b.4) << 24 | UInt64(b.5) << 16 | UInt64(b.6) << 8 | UInt64(b.7)
        h &+= UInt64(bitPattern: Int64(tick)) &* 0xD1B5_4A32_D192_ED03
        return h ^ 0x5C0_07_5EED
    }

    /// Depletes deposits by what the settlement's gatherers pulled this tick,
    /// then regrows every node toward its capacity at a season-scaled rate.
    static func evolveDeposits(
        _ settlement: Settlement,
        registry: GameDataRegistry,
        tick: Int,
        config: WorldConfig,
        mapSeed: UInt64 = 0,
        regrowthMultiplier: Double = 1
    ) -> Settlement {
        guard var map = settlement.localMap, !map.nodes.isEmpty else { return settlement }
        let ticksPerYear = config.ticksPerYear

        // Demand per deposit kind from the workers assigned to harvest it.
        // A trade that works several kinds of ground (a miner: plain rock, an
        // iron seam, a clay bed) spreads its pull across whichever of them this
        // valley actually holds, so an ore-less map simply digs more stone
        // rather than quietly depleting a seam that isn't there.
        let present = Set(map.nodes.map(\.kind))
        var demand: [LocalResourceKind: Double] = [:]
        for pawn in settlement.pawns
        where pawn.isAdult(ticksPerYear: ticksPerYear) && !pawn.isBroken && !pawn.isAway {
            let worked = pawn.assignedWork.harvestedDeposits.filter(present.contains)
            guard !worked.isEmpty else { continue }
            let resource = pawn.assignedWork.resource ?? .food
            let season = config.seasonYieldMultiplier(for: resource, tick: tick)
            let each = harvestPerWorker * season / Double(worked.count)
            for deposit in worked {
                demand[deposit, default: 0] += each
            }
        }

        // The wood and the rock are worked as *things*: the axe goes into real
        // trees and the pick into real outcrops, and the deposit's number is
        // recomputed from what is left standing. Everything else (fields, herb
        // patches) keeps the old proportional arithmetic.
        //
        // `harvestPerWorker` is a deposit-units-per-tick demand, so it converts
        // to whole workers at the face by the same measure.
        // Where the work leaves goods on the ground for somebody to carry in.
        var dropped: [(itemID: String, amount: Int, at: LocalPoint)] = []
        let timberDemand = demand[.forest, default: 0]
        if timberDemand > 0, !map.trees.isEmpty {
            let cut = FloraEngine.fell(map, loggers: max(1, Int(timberDemand / harvestPerWorker)))
            map = cut.map
            for stump in cut.stumps {
                dropped.append((itemID: "wood", amount: timberPerTree, at: stump))
            }
        }
        let stoneDemand = demand[.stone, default: 0]
            + demand[.ironOre, default: 0] + demand[.clay, default: 0]
        if stoneDemand > 0, !map.rocks.isEmpty {
            let cut = FloraEngine.quarry(map, miners: max(1, Int(stoneDemand / harvestPerWorker)))
            map = cut.map
            // What the pick broke out is lying at the outcrop, exactly as
            // timber lies at the stump. Taking only `.map` here — which is what
            // this line did — consumed the rock and produced nothing, so the
            // one route to clay in the game, and the only route to stone or ore
            // on a map with no massif, went into the void.
            for take in cut.broken {
                guard let item = take.kind.rawMaterialID else { continue }
                // A tick's work is a fraction of a unit for hard rock, so the
                // partial takes are banked against the outcrop and dropped as
                // whole goods once they add up to something carryable.
                let owed = map.quarryCredit[item, default: 0] + take.amount
                let whole = Int(owed)
                map.quarryCredit[item] = owed - Double(whole)
                if whole > 0 {
                    dropped.append((itemID: item, amount: whole, at: take.at))
                }
            }
        }
        // And into the hillside itself. A mountain is worked at the face, block
        // by block, and what comes out of it is on top of what the outcrops
        // give — going *into* rock is the reason to settle under a mountain.
        var hewn: [LocalResourceKind: Double] = [:]
        if stoneDemand > 0, map.stone.usesBlocks, !map.stone.isEmpty {
            let miners = max(1, Int(stoneDemand / harvestPerWorker))
            let dug = StoneEngine.mine(map.stone, miners: miners)
            map.stone = dug.field
            // The hole a block leaves is ground the colony can now see through,
            // and a heap of stone at the face for somebody to carry in.
            for index in dug.broken {
                map.exploredCells.insert(index)
                if let item = map.stone.kind(of: index).deposit.rawMaterialID {
                    dropped.append((itemID: item, amount: StoneEngine.itemsPerBlock,
                                    at: StoneField.centre(of: index)))
                }
            }
            hewn = dug.yield
        }

        // Deplete proportionally across the nodes of each kind.
        for kind in Set(map.nodes.map(\.kind)) {
            // A kind backed by real things is depleted by working those things,
            // not by subtracting from the number that describes them.
            guard !FloraEngine.isEntityBacked(kind, in: map) else { continue }
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

        // Regrow toward capacity, faster in the growing seasons. A wood regrows
        // by its trees ageing and a quarry does not regrow at all, so neither
        // gets the blanket creep-back that used to refill everything.
        for i in map.nodes.indices where !FloraEngine.isEntityBacked(map.nodes[i].kind, in: map) {
            let resource: ResourceType = map.nodes[i].kind == .field ? .food : .materials
            let season = config.seasonYieldMultiplier(for: resource, tick: tick)
            let regrow = map.nodes[i].capacity * depositRegrowthFraction * season * regrowthMultiplier
            map.nodes[i].amount = min(map.nodes[i].capacity, map.nodes[i].amount + regrow)
        }

        // And the deposits now read what is standing on them.
        map = FloraEngine.syncDeposits(map)

        var s = settlement
        s.localMap = map
        // What came out of the mountain, as materials. The *goods* it also
        // yielded are lying at the face in `dropped`, waiting to be carried.
        for (_, amount) in hewn {
            s.storage[.materials] = min(s.storageCapacity[.materials], s.storage[.materials] + amount)
        }
        // And the heaps themselves. A felled trunk and a broken block are
        // things on the ground now: the timber is at the stump and the stone at
        // the face until somebody walks out and brings them in.
        if !dropped.isEmpty {
            var rng = SeededRNG(seed: societyLikeSeed(mapSeed: mapSeed, settlementID: s.id,
                                                      tick: tick) ^ 0x48_41_55_4C)
            var withPiles = s.localMap ?? map
            for drop in dropped {
                withPiles = HaulEngine.drop(withPiles, itemID: drop.itemID,
                                            amount: drop.amount, at: drop.at,
                                            tick: tick, rng: &rng)
            }
            s.localMap = withPiles
        }
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
