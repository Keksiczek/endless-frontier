import Foundation

/// Assigns idle adults to work by filling the settlement's biggest labour
/// gaps — the emergent role economy from the civilisation sim. Only *idle*
/// adults are auto-assigned, so a player's manual `assignWork` choices and
/// specialists stick, while children who come of age get put to work.
public enum LaborEngine {
    /// Target share of the adult workforce for each kind of work. Deficits
    /// against these drive assignment. (Tuning; can move to config later.)
    static let quotas: [(work: WorkKind, share: Double)] = [
        // Farming was 0.26 when a farmer's skill *was* the colony's food. It is
        // reaping work now (`FarmEngine`), bounded by how many plots are ripe
        // rather than by how many hands are in the field, so a quarter of the
        // town standing in the furrows was a quarter of the town idle. What
        // came off it went to cooking, which is the new half of the same job.
        (.farming, 0.20),
        // Somebody has to actually make dinner. Not conditional the way
        // `.crafting` and `.garrison` are — those are trades with no work until
        // the colony asks for some, and everybody eats every day.
        (.cooking, 0.07),
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
    /// The trades a colony cannot do without, and the fewest hands each wants
    /// **before any share applies**.
    ///
    /// A share is a fine way to divide a town and a useless way to divide a
    /// village. The table above was written when a colony was eighty people;
    /// cooking's 0.07 is a person and a half in a town of twenty adults and
    /// **half a person in a hamlet of seven** — and half a person is not a small
    /// kitchen, it is no kitchen at all. `rebalance` moves nobody for a gap
    /// worth less than half a body, so any share under `0.5 / adults` can never
    /// be filled once the colony is past having idle hands, which is every
    /// colony past its first decade (rule 17). The trades that fails are exactly
    /// the ones at the bottom of the table, and two of them are how people eat.
    ///
    /// A floor is what a colony actually does: somebody cooks and somebody works
    /// the ground, whatever the arithmetic says, because everybody eats every
    /// day. Below the floor the trade outranks any ordinary deficit; at or above
    /// it the shares take over again and nothing else changes. A trade standing
    /// *at* its floor is also never a surplus, so the colony cannot solve its
    /// missing cook by taking its last farmer.
    ///
    /// Standing orders still win: a player who sets cooking to `.off` gets a
    /// colony that eats raw off the shelf (`ErrandEngine.rawFoodValue`), which
    /// is a valve that already exists and is theirs to open.
    static let floors: [(work: WorkKind, hands: Int)] = [
        (.farming, 1),
        (.cooking, 1),
    ]

    /// The fewest hands a trade wants before its share means anything.
    static func floor(_ work: WorkKind) -> Int {
        floors.first { $0.work == work }?.hands ?? 0
    }

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

    /// **Whether the mason's trade has anything to do.**
    ///
    /// This used to read `!settlement.constructions.isEmpty` — building work was
    /// *raising* something and nothing else — and it is the reason a fifty-year
    /// colony was found with thirty-three of its fifty-five buildings derelict,
    /// six empty dwellings, thirty-four colonists sleeping rough beside them,
    /// four thousand materials in store and thirteen adults idle. The last
    /// scaffold had come down decades earlier, so the trade closed, so nobody
    /// swung a hammer at anything ever again.
    ///
    /// `BuildingEngine.repair` never stopped asking for masons — it just took
    /// `max(1, 0)` and did what one notional pair of hands could, which is about
    /// a fifth of what a town that size sheds to the weather. Wear is charged
    /// **per building** and the repair budget is charged per colony, so this got
    /// worse the more the colony built (rule 14, from the other side).
    ///
    /// A roof that leaks is work. Cheap enough for the staffing interval.
    static func hasBuildingWork(_ settlement: Settlement) -> Bool {
        !settlement.constructions.isEmpty || BuildingEngine.needsRepair(settlement)
    }

    /// How many roofs one mason can keep ahead of the weather.
    ///
    /// **Measured, not chosen** (rule 23). A worn town left to itself with hands
    /// and materials breaks even at about *ten* buildings to the mason and falls
    /// apart past it: fifty-five roofs and four masons went 0.40 → 0.06 in forty
    /// years, which is the save this was found in. Six leaves margin, so a hard
    /// winter — 2.6× the wear of a summer — costs ground that the next summer
    /// puts back instead of starting a slide that nothing ever stops.
    static let roofsPerMason = 6

    /// The share the mason's trade is worth at its idlest: a town in good repair
    /// still wants a few hands who know how a wall goes up.
    static let baseBuildingShare = 0.09
    /// …and the most of a town that may ever be on scaffolds. A colony that has
    /// let everything go mends itself slowly rather than putting everybody on
    /// the roofs and starving under them.
    static let maxBuildingShare = 0.25

    /// **What share of the town its own upkeep is asking for.**
    ///
    /// `floors` exists because a share is a useless way to divide a *village*.
    /// This exists because a share is a useless way to size a job whose size is
    /// set by something other than people: how much mending a colony needs is
    /// decided by how many roofs it owns. A flat 9 % is the right answer at
    /// exactly one ratio of roofs to townsfolk — and the ratio the game actually
    /// grows into (roughly a building per adult) sits just the wrong side of it,
    /// so a colony that was keeping up at forty buildings is losing at fifty-five
    /// and has no way to notice.
    ///
    /// This is rule 14 answered rather than merely named: wear is charged per
    /// building, so the hands that undo it are counted per building too.
    ///
    /// It rides in the quota table rather than in `floors` on purpose. A floor
    /// outranks every ordinary deficit, so a mason floor big enough to matter
    /// would take the colony's last cook the first hard winter; a share is
    /// renormalised against the rest of the table, which means masonry takes a
    /// bigger slice of the same town instead of the whole town.
    static func masonShare(_ settlement: Settlement, adultCount: Int) -> Double {
        let wanting = BuildingEngine.countNeedingRepair(settlement)
        guard wanting > 0, adultCount > 0 else { return baseBuildingShare }
        let wanted = Double(wanting) / Double(roofsPerMason) / Double(adultCount)
        return min(maxBuildingShare, max(baseBuildingShare, wanted))
    }

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
        // Builders are a trade while there is building work — a scaffold to
        // raise **or** a roof to mend. See `hasBuildingWork`.
        let hasBuildWork = hasBuildingWork(settlement)
        // …and how much of a trade depends on how many roofs are asking.
        let masons = masonShare(settlement, adultCount: adultCount)
        // …and crafters only while there is something on the bench to make.
        let hasCraftWork = settlement.craftOrders.contains { !$0.paused }
        // Ground left to chart keeps one pair of boots on the job.
        let needsScouts = !(settlement.localMap?.isFullyCharted ?? true)

        for index in idleIndices {
            let best = neediestRole(counts: counts, adultCount: adultCountD,
                                    population: adultCount, hasTemple: hasTemple,
                                    hasBuildWork: hasBuildWork,
                                    needsScouts: needsScouts, hasWalls: hasWalls,
                                    hasCraftWork: hasCraftWork,
                                    masonShare: masons,
                                    policy: settlement.policy,
                                    fullness: poolFullness(settlement.localMap))
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
        // Runs whether or not the player has set a policy.
        //
        // It used to return here on an empty `policy.trades`, which read as
        // "no orders, nothing to do" and is wrong: `quotaTable` falls back to
        // the engine's own shares, and those are the colony's standing orders
        // whether anybody typed them or not. With the guard in place a town
        // where nobody is idle — which is every town past its first decade —
        // could never move a single person, so a trade the colony had *no
        // members of at all* stayed at zero for ever. That is what happened
        // the moment cooking was added: a colony with a cookhouse, a full
        // shelf and not one cook, for six hundred ticks and counting. Rule 9c,
        // from the side nobody had tested.
        let adultAgeTicks = Pawn.adultAgeYears * registry.config.ticksPerYear

        var counts: [WorkKind: Int] = [:]
        var adultCount = 0
        for pawn in settlement.pawns
        where pawn.age >= adultAgeTicks && !pawn.isAway && pawn.assignedWork != .idle {
            adultCount += 1
            counts[pawn.assignedWork, default: 0] += 1
        }
        // Two: one to move and one to move them from. It used to be four, which
        // switched the slow hand off for exactly the colonies that cannot spare
        // a missing cook — a hamlet of three that buries its last one has no
        // idle hands to reassign and no rebalance to do it either, so the trade
        // stays at zero for ever (rule 17).
        guard adultCount >= 2 else { return settlement }

        let hasTemple = settlement.faith.hasTemple
        let hasWalls = settlement.colony?.placements.contains {
            !$0.underConstruction
                && (registry.building($0.definitionID)?.defense ?? 0) > 0
        } ?? false
        let hasBuildWork = hasBuildingWork(settlement)
        let hasCraftWork = settlement.craftOrders.contains { !$0.paused }
        let table = quotaTable(hasTemple: hasTemple, hasWalls: hasWalls,
                               hasCraftWork: hasCraftWork,
                               masonShare: masonShare(settlement, adultCount: adultCount),
                               policy: policy,
                               fullness: poolFullness(settlement.localMap))

        var overWork: WorkKind?, overBy = 0.0
        var underWork: WorkKind?, underBy = 0.0

        // A trade below its floor is a gap whatever its share is worth, and it
        // is answered before the table is consulted. Same shape as the eviction
        // below, from the other side: "somebody cooks" has to mean somebody, not
        // "somebody once the rest of the table is fed".
        var filling = false
        for (work, hands) in floors
        where counts[work, default: 0] < hands && policy.stance(work) != .off {
            let short = 1 + Double(hands - counts[work, default: 0]) / Double(adultCount)
            if short > underBy { underBy = short; underWork = work; filling = true }
        }

        // Now the trade with the biggest surplus to answer it with. A trade
        // standing at its floor is never a surplus, however far over its share
        // the arithmetic puts it — otherwise a colony of three answers "nobody
        // cooks" by taking its only farmer, and then answers "nobody farms" by
        // taking the cook back.
        func offer(_ work: WorkKind, surplus: Double) {
            guard counts[work, default: 0] > floor(work), surplus > overBy else { return }
            overBy = surplus; overWork = work
        }
        for (work, share) in table {
            let idleTrade = (work == .healing && adultCount < healingMinPopulation)
                || (work == .building && !hasBuildWork)
                || (work == .crafting && !hasCraftWork)
            let current = Double(counts[work, default: 0]) / Double(adultCount)
            let gap = share - current
            if !idleTrade, gap > underBy { underBy = gap; underWork = work }
            offer(work, surplus: idleTrade ? (filling ? current : 0) : -gap)
        }
        // A colony that cannot feed itself may also draft the trades that have
        // no work in them at all — the masons who finished the last scaffold,
        // the priest with no temple, the watch with no wall. They are invisible
        // to the table, so without this a village whose only spare hands were
        // theirs could not staff a kitchen with them and starved holding them.
        // Only while a floor is short: outside that, parking a trade until its
        // work comes back is right, and draining the masons after every project
        // would make the next one slow to man.
        //
        // Walked in the trades' own order, never the dictionary's: `counts` is a
        // `Dictionary` and Swift does not keep its iteration order stable
        // between runs, so two trades tied on surplus would hand the colonist to
        // whichever came out first — a different colony from the same seed.
        let held = counts.keys.sorted { $0.rawValue < $1.rawValue }
        if filling {
            for work in held where !table.contains(where: { $0.work == work }) {
                offer(work, surplus: Double(counts[work] ?? 0) / Double(adultCount))
            }
        }
        // A trade the orders switched off is a surplus however small it is, and
        // it empties whether or not anywhere else is short — "nobody" has to
        // mean nobody, not "nobody once the rest of the table is satisfied".
        var evicting = false
        for work in held where policy.stance(work) == .off && (counts[work] ?? 0) > 0 {
            // Outranks any gap, and any floor: switching a trade off is the
            // player saying so, and that is theirs to say.
            let surplus = 1 + Double(counts[work] ?? 0) / Double(adultCount)
            if surplus > overBy { overBy = surplus; overWork = work; evicting = true }
        }
        // Move only when the mismatch is worth a person — otherwise a colony
        // whose quotas can never divide evenly shuffles someone every cadence
        // for ever.
        let onePerson = 1.0 / Double(adultCount)
        guard let from = overWork, let to = underWork, from != to,
              evicting || filling
                || (overBy >= onePerson * 0.5 && underBy >= onePerson * 0.5)
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
        hasTemple: Bool = false, hasBuildWork: Bool = true,
        needsScouts: Bool = false, hasWalls: Bool = false,
        hasCraftWork: Bool = false, masonShare: Double? = nil,
        policy: ColonyPolicy = ColonyPolicy(),
        /// What is left in the ground, per work — see `quotaTable`. Empty means
        /// "not asked", and then the table stands as it always did.
        fullness: [WorkKind: Double] = [:]
    ) -> WorkKind {
        // Scouting's floor still applies — unless the orders say nobody scouts.
        if needsScouts, counts[.scouting, default: 0] == 0,
           policy.stance(.scouting) != .off { return .scouting }

        // …and so do the floors under the trades a colony cannot do without,
        // which come before any share at all. See `floors`.
        for (work, hands) in floors
        where counts[work, default: 0] < hands && policy.stance(work) != .off {
            return work
        }

        let table = quotaTable(hasTemple: hasTemple, hasWalls: hasWalls,
                               hasCraftWork: hasCraftWork, masonShare: masonShare,
                               policy: policy, fullness: fullness)
        var best: WorkKind?
        var bestDeficit = -Double.infinity
        for (work, share) in table {
            if work == .healing, population < healingMinPopulation { continue }
            if work == .building, !hasBuildWork { continue }
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
    /// **How much is left in the ground a trade works.** 1 is untouched, 0 is
    /// worked out. Keyed by the *work*, because mining covers plain rock, iron
    /// and clay and a miner does not care which of them is left.
    static func poolFullness(_ map: LocalMap?) -> [WorkKind: Double] {
        guard let map else { return [:] }
        var pool: [WorkKind: (amount: Double, capacity: Double)] = [:]
        for node in map.nodes {
            var entry = pool[node.kind.work] ?? (0, 0)
            entry.amount += node.amount
            entry.capacity += node.capacity
            pool[node.kind.work] = entry
        }
        return pool.compactMapValues { $0.capacity > 0 ? $0.amount / $0.capacity : nil }
    }

    /// What a trade keeps even when its ground is bare — somebody has to be
    /// there to notice when a new seam is opened or a claim is cleared.
    static let workedOutShare = 0.15

    static func quotaTable(
        hasTemple: Bool, hasWalls: Bool, hasCraftWork: Bool = false,
        masonShare: Double? = nil,
        policy: ColonyPolicy,
        /// **What is left in the ground**, per work (`poolFullness`).
        ///
        /// Measured 2026-08-29 (`OreProbe`): a plains colony has **one** iron
        /// seam by design, it is empty by year thirty, and the colony went on
        /// posting miners at it — fourteen of them at year two hundred, with
        /// nobody ever at a face. A trade whose ground is worked out is a trade
        /// standing idle in the colony's own ledger, and the hands belong
        /// somewhere else until there is something to dig.
        fullness: [WorkKind: Double] = [:]
    ) -> [(work: WorkKind, share: Double)] {
        var table = quotas
        for i in table.indices {
            guard let left = fullness[table[i].work] else { continue }
            table[i].share *= max(workedOutShare, min(1, left))
        }
        // What the town's own roofs are asking for, if anybody worked it out.
        // Left alone the base share stands, so nothing that does not care about
        // upkeep sees a different table than it used to.
        if let masonShare, let i = table.firstIndex(where: { $0.work == .building }) {
            table[i].share = masonShare
        }
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
