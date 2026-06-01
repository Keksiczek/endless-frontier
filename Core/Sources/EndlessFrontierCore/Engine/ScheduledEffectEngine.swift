import Foundation

/// Processes the `WorldState.scheduledEffects` queue once per tick: applies
/// resource drips and fires delayed events. Runs inside the tick loop after
/// the resource loop, using the post-increment tick value.
public enum ScheduledEffectEngine {
    public static func advanceOneTick(_ state: WorldState, registry: GameDataRegistry) -> PlannerResult {
        var s = state
        var fired: [HistoricalEvent] = []
        var surviving: [ScheduledEffect] = []

        for effect in s.scheduledEffects {
            switch effect.kind {
            case let .resource(resource, perTick, scope):
                EffectApplier.applyResourceDelta(&s, resource: resource, delta: perTick, scope: scope)
                let remaining = effect.ticksRemaining - 1
                if remaining > 0 {
                    surviving.append(ScheduledEffect(kind: effect.kind, ticksRemaining: remaining))
                }

            case let .triggerEvent(eventID):
                if s.tick >= effect.firesAtTick {
                    if let template = registry.events.first(where: { $0.id == eventID }) {
                        let (next, record) = StoryPlanner.fireTemplate(template, in: s, registry: registry)
                        s = next
                        fired.append(record)
                    }
                    // If the template is unknown, drop the scheduled effect.
                } else {
                    surviving.append(effect)
                }
            }
        }

        s.scheduledEffects = surviving
        return PlannerResult(state: s, fired: fired)
    }
}
