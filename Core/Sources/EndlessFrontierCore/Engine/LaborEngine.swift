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
    /// A temple needs tending — but only once one stands.
    static let priestShare = 0.04

    /// Puts every idle adult in the settlement to work, each filling whatever
    /// role is furthest below its quota at that moment.
    public static func assignIdleAdults(_ settlement: Settlement, registry: GameDataRegistry) -> Settlement {
        let adultAgeTicks = Pawn.adultAgeYears * registry.config.ticksPerYear
        // Cheap early-out for the common case (nobody idle): most ticks nothing
        // needs assigning, and this runs every tick on offline catch-up.
        guard settlement.pawns.contains(where: { $0.assignedWork == .idle && $0.age >= adultAgeTicks })
        else { return settlement }

        var adultCount = 0
        var counts: [WorkKind: Int] = [:]
        var idleIndices: [Int] = []
        for (i, pawn) in settlement.pawns.enumerated() where pawn.age >= adultAgeTicks {
            adultCount += 1
            if pawn.assignedWork == .idle {
                idleIndices.append(i)
            } else {
                counts[pawn.assignedWork, default: 0] += 1
            }
        }
        guard !idleIndices.isEmpty else { return settlement }

        var s = settlement
        let adultCountD = Double(adultCount)

        // A temple in the settlement opens the priesthood as a trade.
        let hasTemple = settlement.faith.hasTemple
        // Builders are only a trade while something is actually being raised.
        let hasConstruction = !settlement.constructions.isEmpty
        // Ground left to chart keeps one pair of boots on the job.
        let needsScouts = !(settlement.localMap?.isFullyCharted ?? true)

        for index in idleIndices {
            let best = neediestRole(counts: counts, adultCount: adultCountD,
                                    population: adultCount, hasTemple: hasTemple,
                                    hasConstruction: hasConstruction,
                                    needsScouts: needsScouts)
            s.pawns[index].assignedWork = best
            counts[best, default: 0] += 1
        }
        return s
    }

    /// The role furthest below its quota right now.
    ///
    /// `needsScouts` is a floor, not a quota: scouting's 0.05 share is the
    /// smallest on the table, so at founding size it loses every comparison and
    /// the colony charts nothing for decades. While there is fog left, the first
    /// idle pair of hands walks out — after that the ordinary deficit maths
    /// resumes and scouting has to earn its second body like anything else.
    static func neediestRole(
        counts: [WorkKind: Int], adultCount: Double, population: Int,
        hasTemple: Bool = false, hasConstruction: Bool = true,
        needsScouts: Bool = false
    ) -> WorkKind {
        if needsScouts, counts[.scouting, default: 0] == 0 { return .scouting }

        var table = quotas
        if hasTemple { table.append((.priest, priestShare)) }

        var best: WorkKind = .farming
        var bestDeficit = -Double.infinity
        for (work, share) in table {
            if work == .healing, population < healingMinPopulation { continue }
            if work == .building, !hasConstruction { continue }
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
