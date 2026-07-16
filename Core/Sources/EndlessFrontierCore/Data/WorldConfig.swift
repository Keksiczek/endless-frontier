import Foundation

/// A tension band: while tension is `<= maxTension`, event weights of each
/// type are scaled by the corresponding multiplier.
public struct TensionBand: Codable, Sendable, Equatable {
    public let maxTension: Double
    public let disasterWeight: Double
    public let opportunityWeight: Double
    public let flavorWeight: Double

    public init(maxTension: Double, disasterWeight: Double, opportunityWeight: Double, flavorWeight: Double) {
        self.maxTension = maxTension
        self.disasterWeight = disasterWeight
        self.opportunityWeight = opportunityWeight
        self.flavorWeight = flavorWeight
    }
}

/// Tuning constants for the whole simulation. Loaded from `world-config.json`.
/// All values have code defaults so a partial or missing file still works.
public struct WorldConfig: Codable, Sendable, Equatable {
    // Tick timing
    public var realSecondsPerTick: Double
    public var maxOfflineTicks: Int
    public var plannerInterval: Int

    // Calendar: year length and per-season yield multipliers, indexed by
    // `Season.rawValue` (spring, summer, autumn, winter).
    public var ticksPerYear: Int
    public var seasonFoodYield: [Double]
    public var seasonMaterialsYield: [Double]

    // Tension coefficients
    public var threatMultiplier: Double
    public var prosperityDampener: Double
    /// The prosperity a colony is "meant" to sit at. Prosperity is measured as
    /// a departure from here, so wealth soothes and misery bites — rather than
    /// a healthy colony's standing prosperity zeroing tension outright.
    public var prosperityNeutral: Double
    public var disasterSpikeDecayTicks: Int
    public var disasterSpikePerEvent: Double
    public var boomDampenerTicks: Int
    public var boomDampenerPerEvent: Double
    public var deficitSpikePerResource: Double
    public var eraRampPerEra: Double
    /// Population at which scale pressure starts (a hamlet attracts nobody).
    public var scalePressureBasePopulation: Double
    /// Tension added per doubling of population beyond the base.
    public var scalePressurePerDoubling: Double
    /// Ceiling on scale pressure, so a megacity is dangerous, not doomed.
    public var scalePressureCap: Double

    // Resources
    public var foodPerPersonPerTick: Double
    public var defaultStorageCapacity: Double
    /// Share of a building's materials cost charged per tick as maintenance,
    /// when it doesn't declare an explicit `upkeep`. This is the dial that
    /// decides whether a mature colony's economy has any tension in it: too low
    /// and the stores just pin at the cap, too high and nothing can be built.
    public var upkeepRateOfCost: Double
    /// Power drawn per colonist per tick, before the era multiplier.
    public var energyPerPersonPerTick: Double
    /// How electrically each era lives, indexed by `Era.index`. Zero in the
    /// early eras, where there is no generation to be had — billing a colony
    /// for power it cannot possibly make would only bankrupt it.
    public var eraEnergyDemand: [Double]
    /// Influence drawn per colonist per tick beyond `selfGoverningPopulation`.
    public var influencePerPersonPerTick: Double
    /// Influence drawn per tick for each settlement held.
    public var influencePerSettlement: Double
    /// A settlement below this size governs itself by talking, and costs no
    /// political capital — which also keeps a young colony out of an influence
    /// debt it has no trade post to pay off.
    public var selfGoverningPopulation: Double
    /// What each completion multiplies a repeatable tech's cost by, so endless
    /// research keeps absorbing a growing colony's growing output.
    public var repeatableTechCostGrowth: Double

    // Stability thresholds
    public var collapseThreshold: Double
    public var warningThreshold: Double
    public var mercyEventThreshold: Double

    // Events
    public var maxMajorEventsPerCycle: Int
    public var maxMinorEventsPerCycle: Int
    /// Chance per cycle that a major event fires at zero tension.
    public var majorEventChance: Double
    /// Added to `majorEventChance` at maximum tension — drama clusters when
    /// things are already going wrong.
    public var majorEventTensionBoost: Double
    /// Chance per cycle that a flavour event fires.
    public var minorEventChance: Double
    public var tensionBands: [TensionBand]

    // Exploration & expansion
    public var baseExpeditionTicks: Int
    public var ticksPerHazard: Int
    public var expeditionFoodCost: Double
    public var expeditionMaterialsCost: Double
    public var cityUpgradePopulation: Double
    public var cityUpgradeStability: Double
    public var isolationStabilityPenalty: Double

    public static let `default` = WorldConfig(
        realSecondsPerTick: 60,
        maxOfflineTicks: 43_200,
        plannerInterval: 30,
        ticksPerYear: 60,
        seasonFoodYield: [1.0, 1.5, 0.8, 0.3],
        seasonMaterialsYield: [1.0, 1.2, 0.9, 0.7],
        threatMultiplier: 0.4,
        prosperityDampener: 0.2,
        prosperityNeutral: 50,
        disasterSpikeDecayTicks: 30,
        disasterSpikePerEvent: 8,
        boomDampenerTicks: 20,
        boomDampenerPerEvent: 3,
        deficitSpikePerResource: 8,
        eraRampPerEra: 5,
        scalePressureBasePopulation: 30,
        scalePressurePerDoubling: 4,
        scalePressureCap: 25,
        foodPerPersonPerTick: 0.1,
        defaultStorageCapacity: 500,
        upkeepRateOfCost: 0.03,
        energyPerPersonPerTick: 0.05,
        eraEnergyDemand: [0, 0, 0.3, 1.0, 2.0, 3.5],
        influencePerPersonPerTick: 0.18,
        influencePerSettlement: 3,
        selfGoverningPopulation: 100,
        repeatableTechCostGrowth: 1.35,
        collapseThreshold: 10,
        warningThreshold: 20,
        mercyEventThreshold: 10,
        maxMajorEventsPerCycle: 1,
        maxMinorEventsPerCycle: 1,
        majorEventChance: 0.08,
        majorEventTensionBoost: 0.25,
        minorEventChance: 0.05,
        tensionBands: [
            TensionBand(maxTension: 30, disasterWeight: 0.5, opportunityWeight: 1.5, flavorWeight: 2.0),
            TensionBand(maxTension: 60, disasterWeight: 1.0, opportunityWeight: 1.0, flavorWeight: 1.0),
            TensionBand(maxTension: 80, disasterWeight: 1.8, opportunityWeight: 0.6, flavorWeight: 0.5),
            TensionBand(maxTension: 100, disasterWeight: 3.0, opportunityWeight: 0.3, flavorWeight: 0.1)
        ],
        baseExpeditionTicks: 50,
        ticksPerHazard: 10,
        expeditionFoodCost: 30,
        expeditionMaterialsCost: 15,
        cityUpgradePopulation: 80,
        cityUpgradeStability: 50,
        isolationStabilityPenalty: 0.5
    )

    public init(
        realSecondsPerTick: Double,
        maxOfflineTicks: Int,
        plannerInterval: Int,
        ticksPerYear: Int,
        seasonFoodYield: [Double],
        seasonMaterialsYield: [Double],
        threatMultiplier: Double,
        prosperityDampener: Double,
        prosperityNeutral: Double = 50,
        disasterSpikeDecayTicks: Int,
        disasterSpikePerEvent: Double,
        boomDampenerTicks: Int,
        boomDampenerPerEvent: Double,
        deficitSpikePerResource: Double,
        eraRampPerEra: Double,
        scalePressureBasePopulation: Double = 30,
        scalePressurePerDoubling: Double = 4,
        scalePressureCap: Double = 25,
        foodPerPersonPerTick: Double,
        defaultStorageCapacity: Double,
        upkeepRateOfCost: Double = 0.03,
        energyPerPersonPerTick: Double = 0.05,
        eraEnergyDemand: [Double] = [0, 0, 0.3, 1.0, 2.0, 3.5],
        influencePerPersonPerTick: Double = 0.18,
        influencePerSettlement: Double = 3,
        selfGoverningPopulation: Double = 100,
        repeatableTechCostGrowth: Double = 1.35,
        collapseThreshold: Double,
        warningThreshold: Double,
        mercyEventThreshold: Double,
        maxMajorEventsPerCycle: Int,
        maxMinorEventsPerCycle: Int,
        majorEventChance: Double = 0.08,
        majorEventTensionBoost: Double = 0.25,
        minorEventChance: Double = 0.05,
        tensionBands: [TensionBand],
        baseExpeditionTicks: Int,
        ticksPerHazard: Int,
        expeditionFoodCost: Double,
        expeditionMaterialsCost: Double,
        cityUpgradePopulation: Double,
        cityUpgradeStability: Double,
        isolationStabilityPenalty: Double
    ) {
        self.realSecondsPerTick = realSecondsPerTick
        self.maxOfflineTicks = maxOfflineTicks
        self.plannerInterval = plannerInterval
        self.ticksPerYear = ticksPerYear
        self.seasonFoodYield = seasonFoodYield
        self.seasonMaterialsYield = seasonMaterialsYield
        self.threatMultiplier = threatMultiplier
        self.prosperityDampener = prosperityDampener
        self.prosperityNeutral = prosperityNeutral
        self.disasterSpikeDecayTicks = disasterSpikeDecayTicks
        self.disasterSpikePerEvent = disasterSpikePerEvent
        self.boomDampenerTicks = boomDampenerTicks
        self.boomDampenerPerEvent = boomDampenerPerEvent
        self.deficitSpikePerResource = deficitSpikePerResource
        self.eraRampPerEra = eraRampPerEra
        self.scalePressureBasePopulation = scalePressureBasePopulation
        self.scalePressurePerDoubling = scalePressurePerDoubling
        self.scalePressureCap = scalePressureCap
        self.foodPerPersonPerTick = foodPerPersonPerTick
        self.defaultStorageCapacity = defaultStorageCapacity
        self.upkeepRateOfCost = upkeepRateOfCost
        self.energyPerPersonPerTick = energyPerPersonPerTick
        self.eraEnergyDemand = eraEnergyDemand
        self.influencePerPersonPerTick = influencePerPersonPerTick
        self.influencePerSettlement = influencePerSettlement
        self.selfGoverningPopulation = selfGoverningPopulation
        self.repeatableTechCostGrowth = repeatableTechCostGrowth
        self.collapseThreshold = collapseThreshold
        self.warningThreshold = warningThreshold
        self.mercyEventThreshold = mercyEventThreshold
        self.maxMajorEventsPerCycle = maxMajorEventsPerCycle
        self.maxMinorEventsPerCycle = maxMinorEventsPerCycle
        self.majorEventChance = majorEventChance
        self.majorEventTensionBoost = majorEventTensionBoost
        self.minorEventChance = minorEventChance
        self.tensionBands = tensionBands
        self.baseExpeditionTicks = baseExpeditionTicks
        self.ticksPerHazard = ticksPerHazard
        self.expeditionFoodCost = expeditionFoodCost
        self.expeditionMaterialsCost = expeditionMaterialsCost
        self.cityUpgradePopulation = cityUpgradePopulation
        self.cityUpgradeStability = cityUpgradeStability
        self.isolationStabilityPenalty = isolationStabilityPenalty
    }

    /// The seasonal multiplier applied to gross production of `resource` at
    /// `tick`. Food and materials follow the calendar; everything else is
    /// season-agnostic. Malformed tables (≠ 4 entries) are treated as neutral.
    public func seasonYieldMultiplier(for resource: ResourceType, tick: Int) -> Double {
        let table: [Double]
        switch resource {
        case .food: table = seasonFoodYield
        case .materials: table = seasonMaterialsYield
        default: return 1
        }
        guard table.count == 4 else { return 1 }
        return table[Season(tick: tick, ticksPerYear: ticksPerYear).rawValue]
    }

    // Custom decoding: every field falls back to the default when absent,
    // so the JSON file can be partial during balance iteration.
    private enum CodingKeys: String, CodingKey {
        case tick, tension, resources, stability, events, exploration, calendar
    }
    private enum ExplorationKeys: String, CodingKey {
        case baseExpeditionTicks, ticksPerHazard, expeditionFoodCost,
             expeditionMaterialsCost, cityUpgradePopulation, cityUpgradeStability,
             isolationStabilityPenalty
    }
    private enum TickKeys: String, CodingKey {
        case realSecondsPerTick, maxOfflineTicks, plannerInterval
    }
    private enum CalendarKeys: String, CodingKey {
        case ticksPerYear, seasonFoodYield, seasonMaterialsYield
    }
    private enum TensionKeys: String, CodingKey {
        case threatMultiplier, prosperityDampener, prosperityNeutral,
             disasterSpikeDecayTicks, disasterSpikePerEvent, boomDampenerTicks,
             boomDampenerPerEvent, deficitSpikePerResource, eraRampPerEra,
             scalePressureBasePopulation, scalePressurePerDoubling, scalePressureCap
    }
    private enum ResourceKeys: String, CodingKey {
        case foodPerPersonPerTick, defaultStorageCapacity, upkeepRateOfCost,
             energyPerPersonPerTick, eraEnergyDemand, influencePerPersonPerTick,
             influencePerSettlement, selfGoverningPopulation, repeatableTechCostGrowth
    }
    private enum StabilityKeys: String, CodingKey {
        case collapseThreshold, warningThreshold, mercyEventThreshold
    }
    private enum EventKeys: String, CodingKey {
        case maxMajorEventsPerCycle, maxMinorEventsPerCycle, majorEventChance,
             majorEventTensionBoost, minorEventChance, tensionBands
    }

    public init(from decoder: Decoder) throws {
        let d = WorldConfig.default
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let tick = try? c.nestedContainer(keyedBy: TickKeys.self, forKey: .tick)
        realSecondsPerTick = (try? tick?.decodeIfPresent(Double.self, forKey: .realSecondsPerTick)) ?? d.realSecondsPerTick
        maxOfflineTicks = (try? tick?.decodeIfPresent(Int.self, forKey: .maxOfflineTicks)) ?? d.maxOfflineTicks
        plannerInterval = (try? tick?.decodeIfPresent(Int.self, forKey: .plannerInterval)) ?? d.plannerInterval

        let calendar = try? c.nestedContainer(keyedBy: CalendarKeys.self, forKey: .calendar)
        ticksPerYear = (try? calendar?.decodeIfPresent(Int.self, forKey: .ticksPerYear)) ?? d.ticksPerYear
        seasonFoodYield = (try? calendar?.decodeIfPresent([Double].self, forKey: .seasonFoodYield)) ?? d.seasonFoodYield
        seasonMaterialsYield = (try? calendar?.decodeIfPresent([Double].self, forKey: .seasonMaterialsYield)) ?? d.seasonMaterialsYield

        let tension = try? c.nestedContainer(keyedBy: TensionKeys.self, forKey: .tension)
        threatMultiplier = (try? tension?.decodeIfPresent(Double.self, forKey: .threatMultiplier)) ?? d.threatMultiplier
        prosperityDampener = (try? tension?.decodeIfPresent(Double.self, forKey: .prosperityDampener)) ?? d.prosperityDampener
        prosperityNeutral = (try? tension?.decodeIfPresent(Double.self, forKey: .prosperityNeutral)) ?? d.prosperityNeutral
        disasterSpikeDecayTicks = (try? tension?.decodeIfPresent(Int.self, forKey: .disasterSpikeDecayTicks)) ?? d.disasterSpikeDecayTicks
        disasterSpikePerEvent = (try? tension?.decodeIfPresent(Double.self, forKey: .disasterSpikePerEvent)) ?? d.disasterSpikePerEvent
        boomDampenerTicks = (try? tension?.decodeIfPresent(Int.self, forKey: .boomDampenerTicks)) ?? d.boomDampenerTicks
        boomDampenerPerEvent = (try? tension?.decodeIfPresent(Double.self, forKey: .boomDampenerPerEvent)) ?? d.boomDampenerPerEvent
        deficitSpikePerResource = (try? tension?.decodeIfPresent(Double.self, forKey: .deficitSpikePerResource)) ?? d.deficitSpikePerResource
        eraRampPerEra = (try? tension?.decodeIfPresent(Double.self, forKey: .eraRampPerEra)) ?? d.eraRampPerEra
        scalePressureBasePopulation = (try? tension?.decodeIfPresent(Double.self, forKey: .scalePressureBasePopulation)) ?? d.scalePressureBasePopulation
        scalePressurePerDoubling = (try? tension?.decodeIfPresent(Double.self, forKey: .scalePressurePerDoubling)) ?? d.scalePressurePerDoubling
        scalePressureCap = (try? tension?.decodeIfPresent(Double.self, forKey: .scalePressureCap)) ?? d.scalePressureCap

        let res = try? c.nestedContainer(keyedBy: ResourceKeys.self, forKey: .resources)
        foodPerPersonPerTick = (try? res?.decodeIfPresent(Double.self, forKey: .foodPerPersonPerTick)) ?? d.foodPerPersonPerTick
        defaultStorageCapacity = (try? res?.decodeIfPresent(Double.self, forKey: .defaultStorageCapacity)) ?? d.defaultStorageCapacity
        upkeepRateOfCost = (try? res?.decodeIfPresent(Double.self, forKey: .upkeepRateOfCost)) ?? d.upkeepRateOfCost
        energyPerPersonPerTick = (try? res?.decodeIfPresent(Double.self, forKey: .energyPerPersonPerTick)) ?? d.energyPerPersonPerTick
        eraEnergyDemand = (try? res?.decodeIfPresent([Double].self, forKey: .eraEnergyDemand)) ?? d.eraEnergyDemand
        influencePerPersonPerTick = (try? res?.decodeIfPresent(Double.self, forKey: .influencePerPersonPerTick)) ?? d.influencePerPersonPerTick
        influencePerSettlement = (try? res?.decodeIfPresent(Double.self, forKey: .influencePerSettlement)) ?? d.influencePerSettlement
        selfGoverningPopulation = (try? res?.decodeIfPresent(Double.self, forKey: .selfGoverningPopulation)) ?? d.selfGoverningPopulation
        repeatableTechCostGrowth = (try? res?.decodeIfPresent(Double.self, forKey: .repeatableTechCostGrowth)) ?? d.repeatableTechCostGrowth

        let stab = try? c.nestedContainer(keyedBy: StabilityKeys.self, forKey: .stability)
        collapseThreshold = (try? stab?.decodeIfPresent(Double.self, forKey: .collapseThreshold)) ?? d.collapseThreshold
        warningThreshold = (try? stab?.decodeIfPresent(Double.self, forKey: .warningThreshold)) ?? d.warningThreshold
        mercyEventThreshold = (try? stab?.decodeIfPresent(Double.self, forKey: .mercyEventThreshold)) ?? d.mercyEventThreshold

        let ev = try? c.nestedContainer(keyedBy: EventKeys.self, forKey: .events)
        maxMajorEventsPerCycle = (try? ev?.decodeIfPresent(Int.self, forKey: .maxMajorEventsPerCycle)) ?? d.maxMajorEventsPerCycle
        maxMinorEventsPerCycle = (try? ev?.decodeIfPresent(Int.self, forKey: .maxMinorEventsPerCycle)) ?? d.maxMinorEventsPerCycle
        majorEventChance = (try? ev?.decodeIfPresent(Double.self, forKey: .majorEventChance)) ?? d.majorEventChance
        majorEventTensionBoost = (try? ev?.decodeIfPresent(Double.self, forKey: .majorEventTensionBoost)) ?? d.majorEventTensionBoost
        minorEventChance = (try? ev?.decodeIfPresent(Double.self, forKey: .minorEventChance)) ?? d.minorEventChance
        tensionBands = (try? ev?.decodeIfPresent([TensionBand].self, forKey: .tensionBands)) ?? d.tensionBands

        let exp = try? c.nestedContainer(keyedBy: ExplorationKeys.self, forKey: .exploration)
        baseExpeditionTicks = (try? exp?.decodeIfPresent(Int.self, forKey: .baseExpeditionTicks)) ?? d.baseExpeditionTicks
        ticksPerHazard = (try? exp?.decodeIfPresent(Int.self, forKey: .ticksPerHazard)) ?? d.ticksPerHazard
        expeditionFoodCost = (try? exp?.decodeIfPresent(Double.self, forKey: .expeditionFoodCost)) ?? d.expeditionFoodCost
        expeditionMaterialsCost = (try? exp?.decodeIfPresent(Double.self, forKey: .expeditionMaterialsCost)) ?? d.expeditionMaterialsCost
        cityUpgradePopulation = (try? exp?.decodeIfPresent(Double.self, forKey: .cityUpgradePopulation)) ?? d.cityUpgradePopulation
        cityUpgradeStability = (try? exp?.decodeIfPresent(Double.self, forKey: .cityUpgradeStability)) ?? d.cityUpgradeStability
        isolationStabilityPenalty = (try? exp?.decodeIfPresent(Double.self, forKey: .isolationStabilityPenalty)) ?? d.isolationStabilityPenalty
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        var tick = c.nestedContainer(keyedBy: TickKeys.self, forKey: .tick)
        try tick.encode(realSecondsPerTick, forKey: .realSecondsPerTick)
        try tick.encode(maxOfflineTicks, forKey: .maxOfflineTicks)
        try tick.encode(plannerInterval, forKey: .plannerInterval)

        var calendar = c.nestedContainer(keyedBy: CalendarKeys.self, forKey: .calendar)
        try calendar.encode(ticksPerYear, forKey: .ticksPerYear)
        try calendar.encode(seasonFoodYield, forKey: .seasonFoodYield)
        try calendar.encode(seasonMaterialsYield, forKey: .seasonMaterialsYield)

        var tension = c.nestedContainer(keyedBy: TensionKeys.self, forKey: .tension)
        try tension.encode(threatMultiplier, forKey: .threatMultiplier)
        try tension.encode(prosperityDampener, forKey: .prosperityDampener)
        try tension.encode(prosperityNeutral, forKey: .prosperityNeutral)
        try tension.encode(disasterSpikeDecayTicks, forKey: .disasterSpikeDecayTicks)
        try tension.encode(disasterSpikePerEvent, forKey: .disasterSpikePerEvent)
        try tension.encode(boomDampenerTicks, forKey: .boomDampenerTicks)
        try tension.encode(boomDampenerPerEvent, forKey: .boomDampenerPerEvent)
        try tension.encode(deficitSpikePerResource, forKey: .deficitSpikePerResource)
        try tension.encode(eraRampPerEra, forKey: .eraRampPerEra)
        try tension.encode(scalePressureBasePopulation, forKey: .scalePressureBasePopulation)
        try tension.encode(scalePressurePerDoubling, forKey: .scalePressurePerDoubling)
        try tension.encode(scalePressureCap, forKey: .scalePressureCap)

        var res = c.nestedContainer(keyedBy: ResourceKeys.self, forKey: .resources)
        try res.encode(foodPerPersonPerTick, forKey: .foodPerPersonPerTick)
        try res.encode(defaultStorageCapacity, forKey: .defaultStorageCapacity)
        try res.encode(upkeepRateOfCost, forKey: .upkeepRateOfCost)
        try res.encode(energyPerPersonPerTick, forKey: .energyPerPersonPerTick)
        try res.encode(eraEnergyDemand, forKey: .eraEnergyDemand)
        try res.encode(influencePerPersonPerTick, forKey: .influencePerPersonPerTick)
        try res.encode(influencePerSettlement, forKey: .influencePerSettlement)
        try res.encode(selfGoverningPopulation, forKey: .selfGoverningPopulation)
        try res.encode(repeatableTechCostGrowth, forKey: .repeatableTechCostGrowth)

        var stab = c.nestedContainer(keyedBy: StabilityKeys.self, forKey: .stability)
        try stab.encode(collapseThreshold, forKey: .collapseThreshold)
        try stab.encode(warningThreshold, forKey: .warningThreshold)
        try stab.encode(mercyEventThreshold, forKey: .mercyEventThreshold)

        var ev = c.nestedContainer(keyedBy: EventKeys.self, forKey: .events)
        try ev.encode(maxMajorEventsPerCycle, forKey: .maxMajorEventsPerCycle)
        try ev.encode(maxMinorEventsPerCycle, forKey: .maxMinorEventsPerCycle)
        try ev.encode(majorEventChance, forKey: .majorEventChance)
        try ev.encode(majorEventTensionBoost, forKey: .majorEventTensionBoost)
        try ev.encode(minorEventChance, forKey: .minorEventChance)
        try ev.encode(tensionBands, forKey: .tensionBands)

        var exp = c.nestedContainer(keyedBy: ExplorationKeys.self, forKey: .exploration)
        try exp.encode(baseExpeditionTicks, forKey: .baseExpeditionTicks)
        try exp.encode(ticksPerHazard, forKey: .ticksPerHazard)
        try exp.encode(expeditionFoodCost, forKey: .expeditionFoodCost)
        try exp.encode(expeditionMaterialsCost, forKey: .expeditionMaterialsCost)
        try exp.encode(cityUpgradePopulation, forKey: .cityUpgradePopulation)
        try exp.encode(cityUpgradeStability, forKey: .cityUpgradeStability)
        try exp.encode(isolationStabilityPenalty, forKey: .isolationStabilityPenalty)
    }
}
