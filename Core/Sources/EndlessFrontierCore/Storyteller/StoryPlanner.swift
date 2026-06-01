import Foundation

/// The result of one planner cycle.
public struct PlannerResult: Sendable, Equatable {
    public var state: WorldState
    public var fired: [HistoricalEvent]

    public init(state: WorldState, fired: [HistoricalEvent]) {
        self.state = state
        self.fired = fired
    }
}

/// The storyteller. Each cycle it computes tension, filters eligible event
/// templates, weights them by tension band, selects up to one major event and
/// several minor flavor events, and applies their base effects.
///
/// Fully deterministic: randomness flows through a `SeededRNG` derived from
/// `WorldState.rngSeed`, which is advanced and written back.
public enum StoryPlanner {
    public static func run(_ state: WorldState, registry: GameDataRegistry) -> PlannerResult {
        var s = state
        let config = registry.config
        var rng = SeededRNG(seed: s.rngSeed)
        var fired: [HistoricalEvent] = []

        let tension = TensionCalculator.calculate(s, config: config)
        let band = tensionBand(for: tension, config: config)

        let eligible = registry.events.filter { isEligible($0, in: s) }

        // --- Major event slot ---
        let majorTypes: Set<EventType> = tension > 40
            ? [.disaster, .threat, .opportunity]
            : [.opportunity, .quest]
        let majorCandidates = eligible.filter { majorTypes.contains($0.type) }
        for _ in 0..<config.maxMajorEventsPerCycle {
            guard let picked = pick(from: majorCandidates, band: band, excluding: firedIDs(fired), rng: &rng) else { break }
            s = fire(picked, in: s, registry: registry, fired: &fired)
        }

        // --- Minor flavor slot(s) ---
        let flavorCandidates = eligible.filter { $0.type == .flavor }
        for _ in 0..<config.maxMinorEventsPerCycle {
            guard let picked = pick(from: flavorCandidates, band: band, excluding: firedIDs(fired), rng: &rng) else { break }
            s = fire(picked, in: s, registry: registry, fired: &fired)
        }

        s.rngSeed = rng.state
        return PlannerResult(state: s, fired: fired)
    }

    // MARK: - Eligibility

    static func isEligible(_ template: EventTemplate, in state: WorldState) -> Bool {
        guard template.allows(era: state.era) else { return false }
        if let lastFired = state.eventCooldowns[template.id],
           state.tick - lastFired < template.cooldownTicks {
            return false
        }
        return WorldQuery.allSatisfied(template.conditions, in: state)
    }

    // MARK: - Selection

    static func tensionBand(for tension: Double, config: WorldConfig) -> TensionBand {
        config.tensionBands.first { tension <= $0.maxTension } ?? config.tensionBands.last ?? TensionBand(
            maxTension: 100, disasterWeight: 1, opportunityWeight: 1, flavorWeight: 1
        )
    }

    static func multiplier(for type: EventType, band: TensionBand) -> Double {
        switch type {
        case .disaster, .threat: return band.disasterWeight
        case .opportunity, .quest: return band.opportunityWeight
        case .flavor: return band.flavorWeight
        }
    }

    private static func firedIDs(_ fired: [HistoricalEvent]) -> Set<String> {
        Set(fired.map(\.templateID))
    }

    static func pick(
        from candidates: [EventTemplate],
        band: TensionBand,
        excluding: Set<String>,
        rng: inout SeededRNG
    ) -> EventTemplate? {
        let pool = candidates.filter { !excluding.contains($0.id) }
        guard !pool.isEmpty else { return nil }
        let weights = pool.map { $0.weight * multiplier(for: $0.type, band: band) }
        guard let index = rng.weightedIndex(weights) else { return nil }
        return pool[index]
    }

    private static func fire(
        _ template: EventTemplate,
        in state: WorldState,
        registry: GameDataRegistry,
        fired: inout [HistoricalEvent]
    ) -> WorldState {
        var s = EffectApplier.apply(template.effects, to: state, registry: registry)
        let record = HistoricalEvent(templateID: template.id, type: template.type, tick: s.tick)
        s.eventHistory.append(record)
        s.eventCooldowns[template.id] = s.tick
        fired.append(record)
        return s
    }
}
