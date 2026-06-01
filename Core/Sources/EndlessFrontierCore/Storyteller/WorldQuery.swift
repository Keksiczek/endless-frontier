import Foundation

/// Read-only resolution of stat paths and evaluation of event conditions
/// against a `WorldState`. Pure, no mutation.
public enum WorldQuery {
    /// Resolves a `global.<name>` stat. Names matching a global stat field
    /// return that field; names matching a `ResourceType` return the summed
    /// storage of that resource across all settlements.
    public static func globalValue(_ stat: String, in state: WorldState) -> Double {
        switch stat {
        case "prosperity": return state.globalStats.prosperity
        case "stability": return state.globalStats.stability
        case "threatLevel": return state.globalStats.threatLevel
        case "knowledgeOutput": return state.globalStats.knowledgeOutput
        case "influenceOutput": return state.globalStats.influenceOutput
        default:
            if let resource = ResourceType(rawValue: stat) {
                return state.settlements.reduce(0) { $0 + $1.storage[resource] }
            }
            return 0
        }
    }

    /// Resolves a settlement-scoped stat or resource for one settlement.
    public static func settlementValue(_ stat: String, _ settlement: Settlement) -> Double {
        switch stat {
        case "stability": return settlement.stats.stability
        case "morale": return settlement.stats.morale
        case "growth": return settlement.stats.growth
        case "defense": return settlement.stats.defense
        case "pollution": return settlement.stats.pollution
        default:
            if let resource = ResourceType(rawValue: stat) {
                return settlement.storage[resource]
            }
            return 0
        }
    }

    public static func evaluate(_ condition: EventCondition, in state: WorldState) -> Bool {
        switch condition {
        case let .statMin(path, min):
            return compare(path, in: state) { $0 >= min }
        case let .statMax(path, max):
            return compare(path, in: state) { $0 <= max }
        case let .worldFlag(flag, present):
            return (state.worldFlags[flag] ?? false) == present
        case let .techResearched(id):
            return state.researchedTechs.contains(id)
        case let .settlementCountMin(min):
            return state.settlements.count >= min
        }
    }

    /// `true` if every condition is satisfied (empty list = always true).
    public static func allSatisfied(_ conditions: [EventCondition], in state: WorldState) -> Bool {
        conditions.allSatisfy { evaluate($0, in: state) }
    }

    private static func compare(
        _ path: StatPath,
        in state: WorldState,
        _ test: (Double) -> Bool
    ) -> Bool {
        switch path.target {
        case .global:
            return test(globalValue(path.stat, in: state))
        case .settlementAll:
            return !state.settlements.isEmpty
                && state.settlements.allSatisfy { test(settlementValue(path.stat, $0)) }
        case .settlementAny, .settlementClosest:
            return state.settlements.contains { test(settlementValue(path.stat, $0)) }
        }
    }
}
