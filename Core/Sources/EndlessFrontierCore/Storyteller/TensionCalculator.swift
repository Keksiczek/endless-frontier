import Foundation

/// Computes the storyteller's tension value (0–100) from world state and the
/// recent event history. Pure and deterministic.
public enum TensionCalculator {
    public static let baseTension: Double = 10

    public static func calculate(_ state: WorldState, config: WorldConfig) -> Double {
        let stats = state.globalStats

        let threat = stats.threatLevel * config.threatMultiplier
        let comfort = comfort(prosperity: stats.prosperity, config: config)
        let disasterSpike = disasterSpike(state, config: config)
        let boomDampener = boomDampener(state, config: config)
        let deficitSpike = Double(shortageCount(state, config: config)) * config.deficitSpikePerResource
        let eraRamp = Double(state.era.index) * config.eraRampPerEra
        let scale = scalePressure(population: state.totalPopulation, config: config)

        let raw = baseTension
            + threat
            - comfort
            + disasterSpike
            - boomDampener
            + deficitSpike
            + eraRamp
            + scale
        return min(max(raw, 0), 100)
    }

    /// How much the colony's prosperity soothes (or, below neutral, sharpens)
    /// tension — measured as a *departure from a neutral midpoint*.
    ///
    /// Prosperity chases average morale, so a healthy colony sits near 80
    /// permanently. Taken as an absolute (`prosperity × 0.2 ≈ 16`) it dwarfed
    /// base + threat (≈ 14) and clamped tension to exactly zero, forever: the
    /// calm then selected the flavour-heavy band, whose events fed the boom
    /// dampener, which drove tension lower still. Measuring against neutral
    /// keeps prosperity a *dial* rather than an off-switch, and lets a
    /// miserable colony read as genuinely tense.
    static func comfort(prosperity: Double, config: WorldConfig) -> Double {
        (prosperity - config.prosperityNeutral) * config.prosperityDampener
    }

    /// The upward pressure a growing civilisation puts on itself: a large, rich
    /// settlement is a target and a logistical strain in a way a hamlet is not.
    /// Doubling the population adds a fixed amount, so pressure keeps rising
    /// across orders of magnitude without ever running away — this is what stops
    /// a mature colony from being permanently, terminally safe.
    static func scalePressure(population: Double, config: WorldConfig) -> Double {
        let base = max(1, config.scalePressureBasePopulation)
        guard population > base else { return 0 }
        let doublings = log2(population / base)
        return min(config.scalePressureCap, doublings * config.scalePressurePerDoubling)
    }

    /// Recent disasters/threats contribute decaying tension.
    static func disasterSpike(_ state: WorldState, config: WorldConfig) -> Double {
        let window = Double(config.disasterSpikeDecayTicks)
        guard window > 0 else { return 0 }
        var sum = 0.0
        for event in state.eventHistory where event.type == .disaster || event.type == .threat {
            let age = Double(state.tick - event.tick)
            guard age >= 0, age < window else { continue }
            sum += (1 - age / window)
        }
        return sum * config.disasterSpikePerEvent
    }

    /// Recent opportunities/flavor dampen tension.
    static func boomDampener(_ state: WorldState, config: WorldConfig) -> Double {
        let window = config.boomDampenerTicks
        guard window > 0 else { return 0 }
        let count = state.eventHistory.filter {
            ($0.type == .opportunity || $0.type == .flavor) && (state.tick - $0.tick) < window && (state.tick - $0.tick) >= 0
        }.count
        return Double(count) * config.boomDampenerPerEvent
    }

    /// How many core resources the civilisation is running short of — measured
    /// against what it can hold, not against zero.
    ///
    /// This used to count only stores at *exactly* zero, which was moot while
    /// every resource pinned at the storage cap and never moved. Now that each
    /// one has a sink that draws it down, a granary scraped to its last sacks
    /// should worry the storyteller *before* it is finally, actually empty —
    /// which is when it's already too late to be a story about anything.
    public static func shortageCount(_ state: WorldState, config: WorldConfig) -> Int {
        guard !state.settlements.isEmpty else { return 0 }
        let capacity = state.settlements.reduce(0) { $0 + $1.storageCapacity }
        guard capacity > 0 else { return 0 }
        return ResourceType.allCases.filter { resource in
            let held = state.settlements.reduce(0) { $0 + $1.storage[resource] }
            return held / capacity <= config.shortageFraction
        }.count
    }
}
