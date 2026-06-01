import Foundation

/// Drives the world forward N ticks. Each tick: resource loop → tick++ →
/// research → era check → (every `plannerInterval` ticks) storyteller.
public enum TickEngine {
    /// Advances `ticks` simulation steps. Returns the new state and every
    /// event that fired (for the "while you were away" summary).
    public static func advance(
        _ state: WorldState,
        ticks: Int,
        registry: GameDataRegistry
    ) -> PlannerResult {
        var s = state
        var fired: [HistoricalEvent] = []
        guard ticks > 0 else { return PlannerResult(state: s, fired: fired) }

        let interval = max(1, registry.config.plannerInterval)
        for _ in 0..<ticks {
            s = ResourceLoop.advanceOneTick(s, registry: registry)
            s.tick += 1
            s = TechEngine.advanceResearch(s, registry: registry)
            s = EraEngine.checkAdvancement(s, registry: registry)
            if s.tick % interval == 0 {
                let result = StoryPlanner.run(s, registry: registry)
                s = result.state
                fired.append(contentsOf: result.fired)
            }
        }
        return PlannerResult(state: s, fired: fired)
    }

    /// Number of ticks that have elapsed in real time, capped at the offline
    /// maximum. Never negative.
    public static func ticksElapsed(since last: Date, until now: Date, config: WorldConfig) -> Int {
        let seconds = max(0, now.timeIntervalSince(last))
        guard config.realSecondsPerTick > 0 else { return 0 }
        let raw = Int(seconds / config.realSecondsPerTick)
        return min(raw, config.maxOfflineTicks)
    }
}
