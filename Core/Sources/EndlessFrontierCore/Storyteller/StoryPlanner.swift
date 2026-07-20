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
        //
        // Every major kind is always in the pool; how likely each is to be
        // *picked* is the tension band's job (`disasterWeight` runs 0.5 when
        // calm to 3.0 when dire). This used to be a hard gate — below tension
        // 40 the pool was opportunities only — which, since tension never in
        // practice reached 40, meant no disaster or threat template could ever
        // fire. Half the event book was unreachable. The band already expresses
        // "calm ⇒ disasters are rare"; a wall on top of it only made them
        // impossible.
        let majorCandidates = eligible.filter { $0.type != .flavor }
        for _ in 0..<config.maxMajorEventsPerCycle {
            guard rng.nextUnit() < majorChance(tension: tension, config: config) else { break }
            guard let picked = pick(from: majorCandidates, band: band, excluding: firedIDs(fired), rng: &rng) else { break }
            s = fire(picked, in: s, registry: registry, fired: &fired)
        }

        // --- Minor flavor slot(s) ---
        let flavorCandidates = eligible.filter { $0.type == .flavor }
        for _ in 0..<config.maxMinorEventsPerCycle {
            guard rng.nextUnit() < config.minorEventChance else { break }
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

    /// How likely a major event is this cycle, rising with tension.
    ///
    /// The planner used to fire its full quota *every* cycle whenever any
    /// candidate was off cooldown — there was no "nothing happens" outcome at
    /// all, which is why 1,418 ticks produced over a hundred events and the
    /// same few flavour templates repeated forever. Quiet is now the default,
    /// and a colony in trouble is what makes the storyteller speak up.
    static func majorChance(tension: Double, config: WorldConfig) -> Double {
        let t = min(max(tension, 0), 100) / 100
        return min(1, config.majorEventChance + t * config.majorEventTensionBoost)
    }

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
        let (next, record) = fireTemplate(template, in: state, registry: registry)
        fired.append(record)
        return next
    }

    /// The result of letting decisions go unanswered.
    public struct ExpiryResult: Sendable, Equatable {
        public var state: WorldState
        /// Template ids whose moment passed this cycle.
        public var expired: [String]
    }

    /// Retires decisions the Leader never answered.
    ///
    /// `PendingEvent.tick` was written down and then read by nothing at all: a
    /// decision waited in the queue forever, and the only way one ever left
    /// unanswered was a seventh silently shoving it off the six-cap. A choice
    /// with no deadline isn't a decision — it's a suggestion. Now the moment
    /// passes on its own, and a colony that looked to you and heard nothing
    /// feels it.
    ///
    /// The choice's effects are deliberately *not* applied: the point isn't to
    /// pick for the player, it's that the chance was there and is now gone.
    public static func expireDecisions(_ state: WorldState, registry: GameDataRegistry) -> ExpiryResult {
        var s = state
        var expired: [String] = []
        for pending in s.pendingEvents {
            let deadline = registry.events.first { $0.id == pending.templateID }?.decisionTicks
                ?? registry.config.decisionDeadlineTicks
            guard s.tick - pending.tick > deadline else { continue }
            expired.append(pending.templateID)
        }
        guard !expired.isEmpty else { return ExpiryResult(state: s, expired: []) }

        s.pendingEvents.removeAll { expired.contains($0.templateID) }
        let penalty = registry.config.indecisionMoralePenalty * Double(expired.count)
        for index in s.settlements.indices {
            s.settlements[index].stats.morale = max(0, s.settlements[index].stats.morale - penalty)
        }
        return ExpiryResult(state: s, expired: expired)
    }

    /// How many decisions may stack up waiting for the player. Catching up on a
    /// month offline can fire the same event dozens of times; the Leader should
    /// come back to a handful of decisions, not a hundred.
    public static let maxPendingEvents = 6

    /// Fires a single template: applies its base effects, records it in
    /// history, sets its cooldown, and — when the event offers the player a
    /// choice — queues it for a decision. Shared by the planner and the
    /// scheduled-effect engine (delayed `trigger_event`).
    public static func fireTemplate(
        _ template: EventTemplate,
        in state: WorldState,
        registry: GameDataRegistry
    ) -> (WorldState, HistoricalEvent) {
        var s = EffectApplier.apply(template.effects, to: state, registry: registry)
        let record = HistoricalEvent(templateID: template.id, type: template.type, tick: s.tick)
        s.eventHistory.append(record)
        s.eventCooldowns[template.id] = s.tick
        if !template.choices.isEmpty {
            s = queue(template.id, in: s)
        }
        return (s, record)
    }

    /// Queues an event for the player's decision. The same event re-firing
    /// refreshes the existing entry instead of duplicating it, and the queue is
    /// capped — the oldest decision falls off if the player lets them pile up.
    static func queue(_ templateID: String, in state: WorldState) -> WorldState {
        var s = state
        s.pendingEvents.removeAll { $0.templateID == templateID }
        s.pendingEvents.append(PendingEvent(templateID: templateID, tick: s.tick))
        if s.pendingEvents.count > maxPendingEvents {
            s.pendingEvents.removeFirst(s.pendingEvents.count - maxPendingEvents)
        }
        return s
    }
}
