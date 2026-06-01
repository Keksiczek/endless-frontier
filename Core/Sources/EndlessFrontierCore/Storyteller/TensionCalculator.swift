import Foundation

/// Computes the storyteller's tension value (0–100) from world state and the
/// recent event history. Pure and deterministic.
public enum TensionCalculator {
    public static let baseTension: Double = 10

    public static func calculate(_ state: WorldState, config: WorldConfig) -> Double {
        let stats = state.globalStats

        let threat = stats.threatLevel * config.threatMultiplier
        let prosperity = stats.prosperity * config.prosperityDampener
        let disasterSpike = disasterSpike(state, config: config)
        let boomDampener = boomDampener(state, config: config)
        let deficitSpike = Double(depletedResourceCount(state)) * config.deficitSpikePerResource
        let eraRamp = Double(state.era.index) * config.eraRampPerEra

        let raw = baseTension
            + threat
            - prosperity
            + disasterSpike
            - boomDampener
            + deficitSpike
            + eraRamp
        return min(max(raw, 0), 100)
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

    /// Number of core resources fully depleted (zero total) across settlements.
    static func depletedResourceCount(_ state: WorldState) -> Int {
        guard !state.settlements.isEmpty else { return 0 }
        return ResourceType.allCases.filter { resource in
            state.settlements.reduce(0) { $0 + $1.storage[resource] } <= 0
        }.count
    }
}
