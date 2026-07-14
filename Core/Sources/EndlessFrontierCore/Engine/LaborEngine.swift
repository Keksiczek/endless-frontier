import Foundation

/// Assigns idle adults to work by filling the settlement's biggest labour
/// gaps — the emergent role economy from the civilisation sim. Only *idle*
/// adults are auto-assigned, so a player's manual `assignWork` choices and
/// specialists stick, while children who come of age get put to work.
public enum LaborEngine {
    /// Target share of the adult workforce for each kind of work. Deficits
    /// against these drive assignment. (Tuning; can move to config later.)
    static let quotas: [(work: WorkKind, share: Double)] = [
        (.farming, 0.26),
        (.logging, 0.12),
        (.mining, 0.10),
        (.building, 0.09),
        (.research, 0.10),
        (.hunting, 0.07),
        (.foraging, 0.06),
        (.scouting, 0.05),
        (.trade, 0.05),
        (.healing, 0.05),
    ]
    /// Healing only becomes a staffed role once a settlement is large enough
    /// to spare the hands.
    static let healingMinPopulation = 16

    /// Puts every idle adult in the settlement to work, each filling whatever
    /// role is furthest below its quota at that moment.
    public static func assignIdleAdults(_ settlement: Settlement, registry: GameDataRegistry) -> Settlement {
        let ticksPerYear = registry.config.ticksPerYear
        let adults = settlement.pawns.filter { $0.isAdult(ticksPerYear: ticksPerYear) }
        guard !adults.isEmpty else { return settlement }

        let idleIndices = settlement.pawns.indices.filter {
            settlement.pawns[$0].assignedWork == .idle
                && settlement.pawns[$0].isAdult(ticksPerYear: ticksPerYear)
        }
        guard !idleIndices.isEmpty else { return settlement }

        var s = settlement
        let adultCount = Double(adults.count)
        // Live tally of who does what, updated as we place each worker.
        var counts: [WorkKind: Int] = [:]
        for pawn in s.pawns where pawn.assignedWork != .idle {
            counts[pawn.assignedWork, default: 0] += 1
        }

        for index in idleIndices {
            let best = neediestRole(counts: counts, adultCount: adultCount, population: adults.count)
            s.pawns[index].assignedWork = best
            counts[best, default: 0] += 1
        }
        return s
    }

    /// The role furthest below its quota right now.
    static func neediestRole(counts: [WorkKind: Int], adultCount: Double, population: Int) -> WorkKind {
        var best: WorkKind = .farming
        var bestDeficit = -Double.infinity
        for (work, share) in quotas {
            if work == .healing, population < healingMinPopulation { continue }
            let current = Double(counts[work, default: 0]) / adultCount
            let deficit = share - current
            if deficit > bestDeficit {
                bestDeficit = deficit
                best = work
            }
        }
        return best
    }
}
