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
