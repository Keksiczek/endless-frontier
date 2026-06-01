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

    // Tension coefficients
    public var threatMultiplier: Double
    public var prosperityDampener: Double
    public var disasterSpikeDecayTicks: Int
    public var disasterSpikePerEvent: Double
    public var boomDampenerTicks: Int
    public var boomDampenerPerEvent: Double
    public var deficitSpikePerResource: Double
    public var eraRampPerEra: Double

    // Resources
    public var foodPerPersonPerTick: Double
    public var defaultStorageCapacity: Double

    // Stability thresholds
    public var collapseThreshold: Double
    public var warningThreshold: Double
    public var mercyEventThreshold: Double

    // Events
    public var maxMajorEventsPerCycle: Int
    public var maxMinorEventsPerCycle: Int
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
        plannerInterval: 10,
        threatMultiplier: 0.4,
        prosperityDampener: 0.2,
        disasterSpikeDecayTicks: 30,
        disasterSpikePerEvent: 8,
        boomDampenerTicks: 20,
        boomDampenerPerEvent: 3,
        deficitSpikePerResource: 8,
        eraRampPerEra: 5,
        foodPerPersonPerTick: 0.1,
        defaultStorageCapacity: 500,
        collapseThreshold: 10,
        warningThreshold: 20,
        mercyEventThreshold: 10,
        maxMajorEventsPerCycle: 1,
        maxMinorEventsPerCycle: 3,
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
        threatMultiplier: Double,
        prosperityDampener: Double,
        disasterSpikeDecayTicks: Int,
        disasterSpikePerEvent: Double,
        boomDampenerTicks: Int,
        boomDampenerPerEvent: Double,
        deficitSpikePerResource: Double,
        eraRampPerEra: Double,
        foodPerPersonPerTick: Double,
        defaultStorageCapacity: Double,
        collapseThreshold: Double,
        warningThreshold: Double,
        mercyEventThreshold: Double,
        maxMajorEventsPerCycle: Int,
        maxMinorEventsPerCycle: Int,
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
        self.threatMultiplier = threatMultiplier
        self.prosperityDampener = prosperityDampener
        self.disasterSpikeDecayTicks = disasterSpikeDecayTicks
        self.disasterSpikePerEvent = disasterSpikePerEvent
        self.boomDampenerTicks = boomDampenerTicks
        self.boomDampenerPerEvent = boomDampenerPerEvent
        self.deficitSpikePerResource = deficitSpikePerResource
        self.eraRampPerEra = eraRampPerEra
        self.foodPerPersonPerTick = foodPerPersonPerTick
        self.defaultStorageCapacity = defaultStorageCapacity
        self.collapseThreshold = collapseThreshold
        self.warningThreshold = warningThreshold
        self.mercyEventThreshold = mercyEventThreshold
        self.maxMajorEventsPerCycle = maxMajorEventsPerCycle
        self.maxMinorEventsPerCycle = maxMinorEventsPerCycle
        self.tensionBands = tensionBands
        self.baseExpeditionTicks = baseExpeditionTicks
        self.ticksPerHazard = ticksPerHazard
        self.expeditionFoodCost = expeditionFoodCost
        self.expeditionMaterialsCost = expeditionMaterialsCost
        self.cityUpgradePopulation = cityUpgradePopulation
        self.cityUpgradeStability = cityUpgradeStability
        self.isolationStabilityPenalty = isolationStabilityPenalty
    }

    // Custom decoding: every field falls back to the default when absent,
    // so the JSON file can be partial during balance iteration.
    private enum CodingKeys: String, CodingKey {
        case tick, tension, resources, stability, events, exploration
    }
    private enum ExplorationKeys: String, CodingKey {
        case baseExpeditionTicks, ticksPerHazard, expeditionFoodCost,
             expeditionMaterialsCost, cityUpgradePopulation, cityUpgradeStability,
             isolationStabilityPenalty
    }
    private enum TickKeys: String, CodingKey {
        case realSecondsPerTick, maxOfflineTicks, plannerInterval
    }
    private enum TensionKeys: String, CodingKey {
        case threatMultiplier, prosperityDampener, disasterSpikeDecayTicks,
             disasterSpikePerEvent, boomDampenerTicks, boomDampenerPerEvent,
             deficitSpikePerResource, eraRampPerEra
    }
    private enum ResourceKeys: String, CodingKey {
        case foodPerPersonPerTick, defaultStorageCapacity
    }
    private enum StabilityKeys: String, CodingKey {
        case collapseThreshold, warningThreshold, mercyEventThreshold
    }
    private enum EventKeys: String, CodingKey {
        case maxMajorEventsPerCycle, maxMinorEventsPerCycle, tensionBands
    }

    public init(from decoder: Decoder) throws {
        let d = WorldConfig.default
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let tick = try? c.nestedContainer(keyedBy: TickKeys.self, forKey: .tick)
        realSecondsPerTick = (try? tick?.decodeIfPresent(Double.self, forKey: .realSecondsPerTick)) ?? d.realSecondsPerTick
        maxOfflineTicks = (try? tick?.decodeIfPresent(Int.self, forKey: .maxOfflineTicks)) ?? d.maxOfflineTicks
        plannerInterval = (try? tick?.decodeIfPresent(Int.self, forKey: .plannerInterval)) ?? d.plannerInterval

        let tension = try? c.nestedContainer(keyedBy: TensionKeys.self, forKey: .tension)
        threatMultiplier = (try? tension?.decodeIfPresent(Double.self, forKey: .threatMultiplier)) ?? d.threatMultiplier
        prosperityDampener = (try? tension?.decodeIfPresent(Double.self, forKey: .prosperityDampener)) ?? d.prosperityDampener
        disasterSpikeDecayTicks = (try? tension?.decodeIfPresent(Int.self, forKey: .disasterSpikeDecayTicks)) ?? d.disasterSpikeDecayTicks
        disasterSpikePerEvent = (try? tension?.decodeIfPresent(Double.self, forKey: .disasterSpikePerEvent)) ?? d.disasterSpikePerEvent
        boomDampenerTicks = (try? tension?.decodeIfPresent(Int.self, forKey: .boomDampenerTicks)) ?? d.boomDampenerTicks
        boomDampenerPerEvent = (try? tension?.decodeIfPresent(Double.self, forKey: .boomDampenerPerEvent)) ?? d.boomDampenerPerEvent
        deficitSpikePerResource = (try? tension?.decodeIfPresent(Double.self, forKey: .deficitSpikePerResource)) ?? d.deficitSpikePerResource
        eraRampPerEra = (try? tension?.decodeIfPresent(Double.self, forKey: .eraRampPerEra)) ?? d.eraRampPerEra

        let res = try? c.nestedContainer(keyedBy: ResourceKeys.self, forKey: .resources)
        foodPerPersonPerTick = (try? res?.decodeIfPresent(Double.self, forKey: .foodPerPersonPerTick)) ?? d.foodPerPersonPerTick
        defaultStorageCapacity = (try? res?.decodeIfPresent(Double.self, forKey: .defaultStorageCapacity)) ?? d.defaultStorageCapacity

        let stab = try? c.nestedContainer(keyedBy: StabilityKeys.self, forKey: .stability)
        collapseThreshold = (try? stab?.decodeIfPresent(Double.self, forKey: .collapseThreshold)) ?? d.collapseThreshold
        warningThreshold = (try? stab?.decodeIfPresent(Double.self, forKey: .warningThreshold)) ?? d.warningThreshold
        mercyEventThreshold = (try? stab?.decodeIfPresent(Double.self, forKey: .mercyEventThreshold)) ?? d.mercyEventThreshold

        let ev = try? c.nestedContainer(keyedBy: EventKeys.self, forKey: .events)
        maxMajorEventsPerCycle = (try? ev?.decodeIfPresent(Int.self, forKey: .maxMajorEventsPerCycle)) ?? d.maxMajorEventsPerCycle
        maxMinorEventsPerCycle = (try? ev?.decodeIfPresent(Int.self, forKey: .maxMinorEventsPerCycle)) ?? d.maxMinorEventsPerCycle
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

        var tension = c.nestedContainer(keyedBy: TensionKeys.self, forKey: .tension)
        try tension.encode(threatMultiplier, forKey: .threatMultiplier)
        try tension.encode(prosperityDampener, forKey: .prosperityDampener)
        try tension.encode(disasterSpikeDecayTicks, forKey: .disasterSpikeDecayTicks)
        try tension.encode(disasterSpikePerEvent, forKey: .disasterSpikePerEvent)
        try tension.encode(boomDampenerTicks, forKey: .boomDampenerTicks)
        try tension.encode(boomDampenerPerEvent, forKey: .boomDampenerPerEvent)
        try tension.encode(deficitSpikePerResource, forKey: .deficitSpikePerResource)
        try tension.encode(eraRampPerEra, forKey: .eraRampPerEra)

        var res = c.nestedContainer(keyedBy: ResourceKeys.self, forKey: .resources)
        try res.encode(foodPerPersonPerTick, forKey: .foodPerPersonPerTick)
        try res.encode(defaultStorageCapacity, forKey: .defaultStorageCapacity)

        var stab = c.nestedContainer(keyedBy: StabilityKeys.self, forKey: .stability)
        try stab.encode(collapseThreshold, forKey: .collapseThreshold)
        try stab.encode(warningThreshold, forKey: .warningThreshold)
        try stab.encode(mercyEventThreshold, forKey: .mercyEventThreshold)

        var ev = c.nestedContainer(keyedBy: EventKeys.self, forKey: .events)
        try ev.encode(maxMajorEventsPerCycle, forKey: .maxMajorEventsPerCycle)
        try ev.encode(maxMinorEventsPerCycle, forKey: .maxMinorEventsPerCycle)
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
