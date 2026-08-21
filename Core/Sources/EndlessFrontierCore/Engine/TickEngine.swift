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
            // The inside of the tick first: what people are physically doing —
            // marches, shifts, fights — resolved on the action grid. Then the
            // civilisation's own systems settle the tick around them.
            for step in 0..<WorldClock.actionStepsPerTick {
                s.actionStep = step
                s = ActionLoop.advanceStep(
                    s, clock: WorldClock(tick: s.tick, step: step), registry: registry)
            }
            s.actionStep = 0

            s = ResourceLoop.advanceOneTick(s, registry: registry)
            s = MultiCityEngine.advanceOneTick(s, registry: registry)
            // One of your towns keeping another alive: a cart loaded and sent,
            // rather than an accountant's entry moving goods nobody carried.
            s = SupplyEngine.advanceOneTick(s, registry: registry)
            // The ways between places: traffic beats a track, weather takes
            // one back. Before the caravans move, so a road laid this tick is
            // one they can already use.
            s = RoadEngine.advanceOneTick(s, registry: registry)
            let caravanStep = CaravanEngine.advanceOneTick(s, registry: registry)
            s = caravanStep.state
            fired.append(contentsOf: caravanStep.fired)
            // The world beyond the valley, arriving: traders, envoys and the
            // people somebody else's bad winter turned out. Same diplomacy,
            // walking in over your own ground.
            s = VisitorEngine.advanceOneTick(s, registry: registry, mapSeed: s.mapSeed)
            // …and the ones who came to take the place and are still here. They
            // eat every tick; whether they come round is asked on a cadence.
            s = CaptiveEngine.advanceOneTick(s, registry: registry, mapSeed: s.mapSeed)
            s.tick += 1
            let scheduled = ScheduledEffectEngine.advanceOneTick(s, registry: registry)
            s = scheduled.state
            fired.append(contentsOf: scheduled.fired)
            let exploration = ExplorationEngine.advanceOneTick(s, registry: registry)
            s = exploration.state
            fired.append(contentsOf: exploration.fired)
            // The benches. After the day's gathering, so what came in this tick
            // is on the shelf for the crafters to reach for.
            s = CraftingEngine.advanceOneTick(s, registry: registry)
            // The yard: what is kept, what wears out, and who is on it.
            // Every one of the four seams reads `Settlement.conveyances`, and
            // until this line nothing in a running game ever ticked it — carts
            // never wore, fuel was never burned, and a dead horse stayed a
            // mount. Built, tested, and reachable from nowhere but the tests.
            for index in s.settlements.indices {
                s.settlements[index] = StableEngine.advanceOneTick(
                    s.settlements[index], in: s, registry: registry)
                s.settlements[index] = StableEngine.assignRiders(
                    s.settlements[index], registry: registry)
            }
            // …and the council, deciding what to study, stock and raise when
            // nobody is telling it. Without this the world does not advance at
            // all on its own: research, construction and the bench were every
            // one of them reachable only from the UI.
            s = StewardEngine.advanceOneTick(s, registry: registry)
            s = TechEngine.advanceResearch(s, registry: registry)
            s = EraEngine.checkAdvancement(s, registry: registry)
            s = QuestEngine.advance(s, registry: registry)
            // A year has turned: wages, classes, unrest, elections, the assembly.
            let ticksPerYear = max(1, registry.config.ticksPerYear)
            if s.tick % ticksPerYear == 0 {
                s = SocietyEngine.advanceYear(s, registry: registry)
            }
            // Midsummer — deliberately half a year from the turn above, so the
            // one night the colony is a village is not buried under wages,
            // classes and an election.
            s = FestivalEngine.advanceOneTick(s, registry: registry)
            // …and the colony handing itself on: who came of age today, and the
            // old standing at the elbow of the young.
            s = GenerationEngine.advanceOneTick(s, registry: registry)
            if s.tick % interval == 0 {
                // Decisions the Leader let slide time out before new ones are
                // offered, so a full queue is always a live one.
                s = StoryPlanner.expireDecisions(s, registry: registry).state
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
