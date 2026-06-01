import Foundation

/// Era milestone checking and advancement.
public enum EraEngine {
    /// Advances the era while the *next* era's milestones are all satisfied.
    /// Can advance multiple eras in one call (rare, but correct).
    public static func checkAdvancement(_ state: WorldState, registry: GameDataRegistry) -> WorldState {
        var s = state
        while let nextEra = s.era.next,
              let definition = registry.eraDefinition(nextEra),
              definition.milestones.allSatisfy({ isSatisfied($0, in: s) }) {
            s.era = nextEra
        }
        return s
    }

    /// `true` if the world currently meets a single era milestone.
    public static func isSatisfied(_ milestone: EraMilestone, in state: WorldState) -> Bool {
        switch milestone {
        case let .techResearched(id):
            return state.researchedTechs.contains(id)
        case let .globalStat(stat, min):
            return WorldQuery.globalValue(stat, in: state) >= min
        case let .settlementCount(min):
            return state.settlements.count >= min
        case let .populationTotal(min):
            return state.totalPopulation >= min
        }
    }

    /// Progress toward the next era as a fraction `[0, 1]` (count of satisfied
    /// milestones / total). Returns 1 at the final era.
    public static func progressToNextEra(_ state: WorldState, registry: GameDataRegistry) -> Double {
        guard let nextEra = state.era.next,
              let definition = registry.eraDefinition(nextEra),
              !definition.milestones.isEmpty else {
            return 1
        }
        let met = definition.milestones.filter { isSatisfied($0, in: state) }.count
        return Double(met) / Double(definition.milestones.count)
    }
}
