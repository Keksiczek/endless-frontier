import Foundation

/// High-level façade the app talks to. Wraps the deterministic engines and
/// player actions. All methods are pure: they take a state and return a new
/// one, so the UI layer can drive persistence and observation as it sees fit.
public enum GameEngine {
    // MARK: - Session lifecycle

    /// Opens a session: advances the world by the real time elapsed since the
    /// last session (capped), then stamps `lastRealTimestamp = now`.
    public static func openSession(
        _ state: WorldState,
        now: Date,
        registry: GameDataRegistry
    ) -> PlannerResult {
        let ticks = TickEngine.ticksElapsed(since: state.lastRealTimestamp, until: now, config: registry.config)
        var result = TickEngine.advance(state, ticks: ticks, registry: registry)
        result.state.lastRealTimestamp = now
        return result
    }

    // MARK: - Player actions

    /// Queues a tech for research (validates prerequisites).
    public static func setResearch(
        _ state: WorldState,
        techID: String,
        registry: GameDataRegistry
    ) -> WorldState {
        TechEngine.setResearch(state, techID: techID, registry: registry)
    }

    /// Constructs one building in a settlement if it is unlocked and the
    /// capital can pay the cost. Returns unchanged state on failure.
    public static func build(
        _ state: WorldState,
        settlementID: UUID,
        buildingID: String,
        registry: GameDataRegistry
    ) -> WorldState {
        guard let def = registry.building(buildingID),
              state.unlockedBuildings.contains(buildingID) || def.era == .earlySettlement,
              let settlementIndex = state.settlements.firstIndex(where: { $0.id == settlementID }),
              let paid = EffectApplier.payCost(def.cost, from: state) else {
            return state
        }
        var s = paid
        if let existing = s.settlements[settlementIndex].buildings.firstIndex(where: { $0.definitionID == buildingID }) {
            s.settlements[settlementIndex].buildings[existing].count += 1
        } else {
            s.settlements[settlementIndex].buildings.append(BuildingInstance(definitionID: buildingID, count: 1))
        }
        return s
    }

    /// Reassigns a colonist to a different kind of work.
    public static func assignWork(
        _ state: WorldState,
        settlementID: UUID,
        pawnID: UUID,
        work: WorkKind
    ) -> WorldState {
        guard let si = state.settlements.firstIndex(where: { $0.id == settlementID }),
              let pi = state.settlements[si].pawns.firstIndex(where: { $0.id == pawnID }) else {
            return state
        }
        var s = state
        s.settlements[si].pawns[pi].assignedWork = work
        return s
    }

    /// Interacts with the special site (ruins/dungeon/anomaly) in a region.
    /// Returns the new state and the outcome, or unchanged state + `nil`.
    public static func interactWithSite(
        _ state: WorldState,
        regionID: UUID,
        registry: GameDataRegistry
    ) -> (WorldState, SiteOutcome?) {
        if let (newState, outcome) = SiteEngine.interact(state, regionID: regionID, registry: registry) {
            return (newState, outcome)
        }
        return (state, nil)
    }

    /// Founds an outpost in a fully-explored, unsettled region.
    public static func foundOutpost(
        _ state: WorldState,
        regionID: UUID,
        name: String,
        registry: GameDataRegistry
    ) -> WorldState {
        ExpansionEngine.foundOutpost(state, regionID: regionID, name: name, registry: registry)
    }

    /// Establishes a standing trade route between two settlements.
    public static func addTradeRoute(
        _ state: WorldState,
        from: UUID,
        to: UUID,
        resource: ResourceType,
        amountPerTick: Double
    ) -> WorldState {
        guard state.settlements.contains(where: { $0.id == from }),
              state.settlements.contains(where: { $0.id == to }),
              from != to else { return state }
        var s = state
        s.tradeRoutes.append(TradeRoute(fromID: from, toID: to, resource: resource, amountPerTick: amountPerTick))
        return s
    }

    /// Sends an expedition to an unknown region (cost + duration applied).
    public static func startExpedition(
        _ state: WorldState,
        targetRegionID: UUID,
        registry: GameDataRegistry
    ) -> WorldState {
        ExplorationEngine.startExpedition(state, targetRegionID: targetRegionID, registry: registry)
    }

    /// Resolves a player choice on an event: pays the choice cost (if any) and
    /// applies the choice's effects. Returns unchanged state when the choice
    /// can't be found or afforded.
    public static func resolveChoice(
        _ state: WorldState,
        eventID: String,
        choiceID: String,
        registry: GameDataRegistry
    ) -> WorldState {
        guard let template = registry.events.first(where: { $0.id == eventID }),
              let choice = template.choices.first(where: { $0.id == choiceID }) else {
            return state
        }
        guard let paid = EffectApplier.payCost(choice.cost, from: state) else {
            return state
        }
        return EffectApplier.apply(choice.effects, to: paid, registry: registry)
    }
}
