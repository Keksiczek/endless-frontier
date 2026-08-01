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
    /// Hands at the bench — but only while the colony has actually been asked
    /// to make something. Same shape as `.building`, and for the same reason:
    /// a trade with no work in it is people standing in an empty room.
    static let craftingShare = 0.08
    /// Walls and barracks need manning — but only once something is built to
    /// man. Until this existed, the four defensive buildings employed people on
    /// paper and no colonist could ever hold the post: their trade was
    /// unknowable, so nobody was ever seated at them.
    static let garrisonShare = 0.06
    /// How often posts are reconciled with trades, in ticks. Cheap enough to do
    /// often, too expensive to do every tick on a full grid.
    public static let staffingInterval = 10

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
        // So do walls, for the watch.
        let hasWalls = settlement.colony?.placements.contains {
            !$0.underConstruction
                && (registry.building($0.definitionID)?.defense ?? 0) > 0
        } ?? false
        // Builders are only a trade while something is actually being raised.
        let hasConstruction = !settlement.constructions.isEmpty
        // …and crafters only while there is something on the bench to make.
        let hasCraftWork = settlement.craftOrders.contains { !$0.paused }
        // Ground left to chart keeps one pair of boots on the job.
        let needsScouts = !(settlement.localMap?.isFullyCharted ?? true)

        for index in idleIndices {
            let best = neediestRole(counts: counts, adultCount: adultCountD,
                                    population: adultCount, hasTemple: hasTemple,
                                    hasConstruction: hasConstruction,
                                    needsScouts: needsScouts, hasWalls: hasWalls,
                                    hasCraftWork: hasCraftWork,
                                    policy: settlement.policy)
            s.pawns[index].assignedWork = best
            counts[best, default: 0] += 1
        }
        return s
    }

    /// Moves the colony one person at a time toward its standing orders.
    ///
    /// `assignIdleAdults` only ever touches the idle, which is right — it must
    /// not undo a trade the player set by hand. But it also means a policy set
    /// on a town of sixty changes nothing until sixty people happen to fall
    /// idle, which is never. So the orders need a slow hand of their own: on
    /// the staffing cadence, find the trade furthest *over* its weighted quota
    /// and the one furthest *under* it, and move exactly one colonist across.
    ///
    /// One at a time on purpose. A colony re-sorted wholesale the tick after a
    /// slider moves is a spreadsheet; a colony that visibly drifts toward what
    /// you asked for over the next few seasons is a place. It also keeps the
    /// pass O(pawns) with no allocation per trade.
    ///
    /// Deterministic: the colonist moved is the least skilled at the trade
    /// being left, ties broken by id, never by chance.
    public static func rebalance(
        _ settlement: Settlement, registry: GameDataRegistry
    ) -> Settlement {
        let policy = settlement.policy
        guard !policy.trades.isEmpty else { return settlement }
        let adultAgeTicks = Pawn.adultAgeYears * registry.config.ticksPerYear

        var counts: [WorkKind: Int] = [:]
        var adultCount = 0
        for pawn in settlement.pawns
        where pawn.age >= adultAgeTicks && !pawn.isAway && pawn.assignedWork != .idle {
            adultCount += 1
            counts[pawn.assignedWork, default: 0] += 1
        }
        guard adultCount >= 4 else { return settlement }

        let hasTemple = settlement.faith.hasTemple
        let hasWalls = settlement.colony?.placements.contains {
            !$0.underConstruction
                && (registry.building($0.definitionID)?.defense ?? 0) > 0
        } ?? false
        let hasConstruction = !settlement.constructions.isEmpty
        let hasCraftWork = settlement.craftOrders.contains { !$0.paused }
        let table = quotaTable(hasTemple: hasTemple, hasWalls: hasWalls,
                               hasCraftWork: hasCraftWork, policy: policy)

        // The trade with the biggest surplus, and the one with the biggest gap.
        var overWork: WorkKind?, overBy = 0.0
        var underWork: WorkKind?, underBy = 0.0
        for (work, share) in table {
            if work == .healing, adultCount < healingMinPopulation { continue }
            if work == .building, !hasConstruction { continue }
            if work == .crafting, !hasCraftWork { continue }
            let current = Double(counts[work, default: 0]) / Double(adultCount)
            let gap = share - current
            if gap > underBy { underBy = gap; underWork = work }
            if -gap > overBy { overBy = -gap; overWork = work }
        }
        // A trade the orders switched off is a surplus however small it is, and
        // it empties whether or not anywhere else is short — "nobody" has to
        // mean nobody, not "nobody once the rest of the table is satisfied".
        var evicting = false
        for (work, count) in counts where policy.stance(work) == .off && count > 0 {
            let surplus = 1 + Double(count) / Double(adultCount)   // outranks any gap
            if surplus > overBy { overBy = surplus; overWork = work; evicting = true }
        }
        // Move only when the mismatch is worth a person — otherwise a colony
        // whose quotas can never divide evenly shuffles someone every cadence
        // for ever.
        let onePerson = 1.0 / Double(adultCount)
        guard let from = overWork, let to = underWork, from != to,
              evicting || (overBy >= onePerson * 0.5 && underBy >= onePerson * 0.5)
        else { return settlement }

        var pick: Int?
        for (i, pawn) in settlement.pawns.enumerated()
        where pawn.assignedWork == from && pawn.age >= adultAgeTicks && !pawn.isAway {
            guard let best = pick else { pick = i; continue }
            let a = settlement.pawns[best]
            if pawn.skill(from) < a.skill(from)
                || (pawn.skill(from) == a.skill(from)
                    && pawn.id.uuidString < a.id.uuidString) {
                pick = i
            }
        }
        guard let index = pick else { return settlement }
        var s = settlement
        s.pawns[index].assignedWork = to
        return s
    }

    /// Keeps the colony's *posts* in step with its trades.
    ///
    /// `assignedWork` is a colonist's trade; a post is the building they ply it
    /// in (`BuildingPlacement.assignedPawnIDs`). Until now the two only met at
    /// founding — `ColonyBuilder.autoAssign` ran once over the first colonists
    /// and never again — so everyone born after it, come of age, or moved to a
    /// new trade held a trade with no address. A century in, a colony's
    /// workshops stood empty on paper while the town was full of smiths.
    ///
    /// Deterministic: placements and pawns are walked in stored order, so the
    /// same world always fills the same benches in the same order. Linear in
    /// (pawns + placements) — offline catch-up replays tens of thousands of
    /// ticks through here, so it must never scan the roster per bench.
    ///
    /// Note this is bookkeeping and presentation, not yet economics:
    /// `ResourceLoop` still produces from building *counts*, not from who is
    /// stood at the bench. Making the post pay is the next slice.
    public static func staffBuildings(
        _ settlement: Settlement, registry: GameDataRegistry
    ) -> Settlement {
        guard let map = settlement.colony, !map.placements.isEmpty else { return settlement }
        let adultAgeTicks = Pawn.adultAgeYears * registry.config.ticksPerYear

        // Who may hold a post, and at what trade. Children, the away and the
        // untrained hold none.
        var trade: [UUID: WorkKind] = [:]
        for pawn in settlement.pawns
        where pawn.age >= adultAgeTicks && !pawn.isAway && pawn.assignedWork != .idle {
            trade[pawn.id] = pawn.assignedWork
        }

        var placements = map.placements
        var changed = false
        var posted: Set<UUID> = []

        // 1. Vacate what no longer fits — the colonist left, changed trade, or
        //    the roof went back to being a building site.
        for i in placements.indices {
            let def = registry.building(placements[i].definitionID)
            let wanted = def.map(ColonyBuilder.workKind(for:)) ?? .idle
            let room = (placements[i].underConstruction || wanted == .idle) ? 0 : (def?.workers ?? 0)
            var kept: [UUID] = []
            kept.reserveCapacity(min(room, placements[i].assignedPawnIDs.count))
            for id in placements[i].assignedPawnIDs
            where kept.count < room && trade[id] == wanted && !posted.contains(id) {
                kept.append(id)
                posted.insert(id)
            }
            if kept.count != placements[i].assignedPawnIDs.count {
                placements[i].assignedPawnIDs = kept
                changed = true
            }
        }

        // 2. Fill the empty benches. Colonists without a post are bucketed by
        //    trade once, so this stays one pass rather than a scan per bench.
        var free: [WorkKind: [UUID]] = [:]
        for pawn in settlement.pawns where !posted.contains(pawn.id) {
            guard let t = trade[pawn.id] else { continue }
            free[t, default: []].append(pawn.id)
        }
        guard !free.isEmpty else {
            guard changed else { return settlement }
            var s = settlement
            s.colony?.placements = placements
            return s
        }

        for i in placements.indices {
            guard !placements[i].underConstruction,
                  let def = registry.building(placements[i].definitionID),
                  def.workers > 0 else { continue }
            let wanted = ColonyBuilder.workKind(for: def)
            guard wanted != .idle, placements[i].assignedPawnIDs.count < def.workers else { continue }
            while placements[i].assignedPawnIDs.count < def.workers,
                  let id = free[wanted]?.popLast() {
                placements[i].assignedPawnIDs.append(id)
                changed = true
            }
        }

        guard changed else { return settlement }
        var s = settlement
        s.colony?.placements = placements
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
        needsScouts: Bool = false, hasWalls: Bool = false,
        hasCraftWork: Bool = false,
        policy: ColonyPolicy = ColonyPolicy()
    ) -> WorkKind {
        // Scouting's floor still applies — unless the orders say nobody scouts.
        if needsScouts, counts[.scouting, default: 0] == 0,
           policy.stance(.scouting) != .off { return .scouting }

        let table = quotaTable(hasTemple: hasTemple, hasWalls: hasWalls,
                               hasCraftWork: hasCraftWork, policy: policy)
        var best: WorkKind?
        var bestDeficit = -Double.infinity
        for (work, share) in table {
            if work == .healing, population < healingMinPopulation { continue }
            if work == .building, !hasConstruction { continue }
            if work == .crafting, !hasCraftWork { continue }
            let current = Double(counts[work, default: 0]) / adultCount
            let deficit = share - current
            if deficit > bestDeficit {
                bestDeficit = deficit
                best = work
            }
        }
        // Orders that switch off every trade still have to put people
        // somewhere: a colonist with nowhere to be is a colonist who starves.
        return best ?? .farming
    }

    /// The quota table the colony is actually working to: the engine's own
    /// shares scaled by the standing orders, renormalised so the shares still
    /// sum to what they did.
    ///
    /// Renormalising is the whole trick. Multiplying a share by 2.8 and leaving
    /// it there makes a `.priority` trade look permanently starved next to
    /// everything else, so the assigner posts *every* new adult to it for ever
    /// — "priority" would have meant "only". Scaling the set back to its
    /// original total means a priority trade takes a bigger slice of the same
    /// town rather than the whole town.
    static func quotaTable(
        hasTemple: Bool, hasWalls: Bool, hasCraftWork: Bool = false,
        policy: ColonyPolicy
    ) -> [(work: WorkKind, share: Double)] {
        var table = quotas
        if hasTemple { table.append((.priest, priestShare)) }
        if hasWalls { table.append((.garrison, garrisonShare)) }
        if hasCraftWork { table.append((.crafting, craftingShare)) }
        guard !policy.trades.isEmpty else { return table }

        let total = table.reduce(0) { $0 + $1.share }
        var weighted = table.compactMap { entry -> (work: WorkKind, share: Double)? in
            let weight = policy.stance(entry.work).weight
            guard weight > 0 else { return nil }        // `.off` leaves the table
            return (entry.work, entry.share * weight)
        }
        let weightedTotal = weighted.reduce(0) { $0 + $1.share }
        guard weightedTotal > 0 else { return table }   // everything switched off
        let scale = total / weightedTotal
        for i in weighted.indices { weighted[i].share *= scale }
        return weighted
    }
}
