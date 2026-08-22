import Foundation

/// The social machinery of a settlement, run once a year: wages and the wealth
/// classes they create, the Gini coefficient, uprisings when inequality curdles,
/// strikes under rationing, elections, and the assembly that puts motions before
/// the leader — the player.
///
/// Deterministic: every roll comes from a seed derived from
/// `(mapSeed, settlement.id, year)`.
public enum SocietyEngine {
    /// Assembly sits every six years; the leader is chosen every twelve.
    public static let councilIntervalYears = 6
    public static let electionIntervalYears = 12

    /// Yearly wage by trade — skilled work pays more.
    static func wage(for work: WorkKind) -> Double {
        switch work {
        // A crafter's day ends in something you can hold, and is paid like it.
        case .crafting: return 3.6
        case .mining, .healing: return 3.5
        case .research: return 3.2
        // A cook feeds the whole town out of what the fields sent in — skilled
        // work, and paid a shade under the bench.
        case .cooking: return 3.2
        case .farming, .logging, .hunting, .building, .trade: return 3.0
        // Standing a watch is paid work, a little under a trade.
        case .garrison: return 2.8
        case .foraging, .scouting: return 2.5
        case .priest: return 2.0
        case .idle: return 1.0
        }
    }

    /// Inequality at which the poor start looking at the granaries of the rich.
    static let revoltGiniThreshold = 0.5
    static let revoltMoodThreshold = 55.0
    static let revoltChance = 0.3
    /// Share of the wealthy's estates a mob redistributes.
    static let revoltLootFraction = 0.3
    /// Rationing plus misery for long enough and the gatherers down tools.
    static let strikeMoraleThreshold = 38.0
    static let strikeChance = 0.3
    static let strikeTicks = 30

    /// Advances a whole year of social life for every settlement. Called by
    /// `TickEngine` on the year boundary.
    public static func advanceYear(_ state: WorldState, registry: GameDataRegistry) -> WorldState {
        var s = state
        let year = s.year(registry.config)
        for index in s.settlements.indices {
            var rng = SeededRNG(seed: societySeed(mapSeed: s.mapSeed,
                                                  settlementID: s.settlements[index].id,
                                                  year: year))
            s.settlements[index] = expireLaws(s.settlements[index], tick: s.tick)
            s.settlements[index] = payWages(s.settlements[index], registry: registry)
            s.settlements[index] = recomputeClasses(s.settlements[index])
            s.settlements[index] = revolt(s.settlements[index], rng: &rng)
            s.settlements[index] = strike(s.settlements[index], registry: registry, rng: &rng)
            if year % electionIntervalYears == 0 || leader(of: s.settlements[index]) == nil {
                s.settlements[index] = electLeader(s.settlements[index], registry: registry, rng: &rng)
            }
        }
        // The assembly only tables one motion at a time, and only when the
        // leader has answered the last one.
        if year > 0, year % councilIntervalYears == 0, s.pendingLawProposal == nil,
           let capital = s.settlements.first {
            var rng = SeededRNG(seed: societySeed(mapSeed: s.mapSeed,
                                                  settlementID: capital.id, year: year) ^ 0xC0_11_C1_10)
            if let proposal = convene(s, settlement: capital, registry: registry, rng: &rng) {
                s.pendingLawProposal = proposal
            }
        }
        // Faith, the neighbours, and the chronicle close the year.
        s = FaithEngine.advanceYear(s, registry: registry)
        s = DiplomacyEngine.advanceYear(s, registry: registry)
        s = ChronicleEngine.record(s, registry: registry)
        return s
    }

    // MARK: - Laws in force

    /// The combined standing effect of every law currently in force.
    public static func modifiers(_ settlement: Settlement, registry: GameDataRegistry) -> LawModifiers {
        settlement.laws.reduce(LawModifiers()) { acc, instance in
            guard let def = registry.law(instance.definitionID) else { return acc }
            return acc.combined(with: def.modifiers)
        }
    }

    public static func hasLaw(_ settlement: Settlement, _ id: String) -> Bool {
        settlement.laws.contains { $0.definitionID == id }
    }

    static func expireLaws(_ settlement: Settlement, tick: Int) -> Settlement {
        var s = settlement
        s.laws.removeAll { $0.expiresTick <= tick }
        return s
    }

    // MARK: - Wages & classes

    /// Pays a year's wages: trade, diligence, and whatever the tithe takes.
    static func payWages(_ settlement: Settlement, registry: GameDataRegistry) -> Settlement {
        var s = settlement
        let ticksPerYear = registry.config.ticksPerYear
        let tax = modifiers(s, registry: registry).wageTaxFraction
        var treasury = 0.0
        for i in s.pawns.indices where s.pawns[i].isAdult(ticksPerYear: ticksPerYear) {
            let earned = 1 + wage(for: s.pawns[i].assignedWork) + s.pawns[i].genes.industry * 2.5
            let taken = earned * tax
            treasury += taken
            s.pawns[i].wealth += earned - taken
            // A year of living: colonists spend on comfort, which lifts the mood.
            let spend = min(s.pawns[i].wealth, 1.5)
            s.pawns[i].wealth -= spend
            s.pawns[i].mood = min(100, s.pawns[i].mood + spend * 0.9)
        }
        if treasury > 0 {
            s.storage[.influence] = min(s.storageCapacity[.influence], s.storage[.influence] + treasury * 0.1)
        }
        return s
    }

    /// Recomputes the Gini coefficient and the class boundaries.
    static func recomputeClasses(_ settlement: Settlement) -> Settlement {
        var s = settlement
        let wealths = s.pawns.map(\.wealth).sorted()
        guard wealths.count >= 2 else { return s }
        s.society.gini = gini(wealths)
        s.society.poorCeiling = wealths[Int(Double(wealths.count) * 0.4)]
        s.society.wealthyFloor = wealths[min(wealths.count - 1, Int(Double(wealths.count) * 0.85))]
        return s
    }

    /// The Gini coefficient of a sorted wealth list.
    static func gini(_ sorted: [Double]) -> Double {
        guard sorted.count >= 2 else { return 0 }
        var numerator = 0.0
        var sum = 0.0
        for (i, w) in sorted.enumerated() {
            numerator += (2 * Double(i + 1) - Double(sorted.count) - 1) * w
            sum += w
        }
        return sum > 0 ? max(0, min(1, numerator / (Double(sorted.count) * sum))) : 0
    }

    // MARK: - Unrest

    /// When inequality is stark and the poor are miserable, a mob loots the
    /// granaries of the wealthy and shares out the spoils.
    static func revolt(_ settlement: Settlement, rng: inout SeededRNG) -> Settlement {
        var s = settlement
        guard s.pawns.count > 12, s.society.gini > revoltGiniThreshold else { return s }
        let poorIndices = s.pawns.indices.filter { s.society.wealthClass(of: s.pawns[$0].wealth) == .poor }
        let richIndices = s.pawns.indices.filter { s.society.wealthClass(of: s.pawns[$0].wealth) == .wealthy }
        guard !poorIndices.isEmpty, !richIndices.isEmpty else { return s }

        let poorMood = poorIndices.reduce(0.0) { $0 + s.pawns[$1].mood } / Double(poorIndices.count)
        guard poorMood < revoltMoodThreshold, rng.nextUnit() < revoltChance else { return s }

        var loot = 0.0
        for i in richIndices {
            loot += s.pawns[i].wealth * revoltLootFraction
            s.pawns[i].wealth *= (1 - revoltLootFraction)
            s.pawns[i].mood = max(0, s.pawns[i].mood - 12)
        }
        let share = loot / Double(poorIndices.count)
        for i in poorIndices {
            s.pawns[i].wealth += share
            s.pawns[i].mood = min(100, s.pawns[i].mood + 10)
        }
        s.society.revolts += 1
        s.stats.stability = max(0, s.stats.stability - 12)
        s.stats = s.stats.clamped()
        // A leader of the propertied class can be swept away by the mob.
        if let leaderID = s.leaderID,
           let leader = s.pawns.first(where: { $0.id == leaderID }),
           s.society.wealthClass(of: leader.wealth) == .wealthy,
           rng.nextUnit() < 0.4 {
            s.leaderID = nil
        }
        return s
    }

    /// Rationing plus a miserable year and the gatherers stop working.
    static func strike(_ settlement: Settlement, registry: GameDataRegistry, rng: inout SeededRNG) -> Settlement {
        var s = settlement
        guard hasLaw(s, "rationing"), s.pawns.count > 8, s.strikeTicksRemaining == 0,
              s.stats.morale < strikeMoraleThreshold, rng.nextUnit() < strikeChance else { return s }
        s.strikeTicksRemaining = strikeTicks
        return s
    }

    // MARK: - Leadership

    public static func leader(of settlement: Settlement) -> Pawn? {
        guard let id = settlement.leaderID else { return nil }
        return settlement.pawns.first { $0.id == id }
    }

    /// The assembly picks a leader: charisma (sociability) and nerve (courage)
    /// carry the day, with standing worth a thumb on the scale.
    static func electLeader(
        _ settlement: Settlement, registry: GameDataRegistry, rng: inout SeededRNG
    ) -> Settlement {
        var s = settlement
        let ticksPerYear = registry.config.ticksPerYear
        let candidates = s.pawns.indices.filter {
            let years = s.pawns[$0].ageYears(ticksPerYear: ticksPerYear)
            return years >= Pawn.adultAgeYears && years < 58
        }
        guard !candidates.isEmpty else {
            s.leaderID = nil
            return s
        }
        var bestIndex = candidates[0]
        var bestScore = -Double.infinity
        for i in candidates {
            let standing = Double(s.society.wealthClass(of: s.pawns[i].wealth).votes) * 0.08
            let score = s.pawns[i].genes.sociability * 0.5
                + s.pawns[i].genes.courage * 0.3
                + standing + rng.nextUnit() * 0.25
            if score > bestScore {
                bestScore = score
                bestIndex = i
            }
        }
        s.leaderID = s.pawns[bestIndex].id
        return s
    }

    // MARK: - The assembly

    /// The council debates and votes on one eligible motion. The result becomes
    /// a proposal for the leader to ratify or veto.
    static func convene(
        _ state: WorldState, settlement: Settlement,
        registry: GameDataRegistry, rng: inout SeededRNG
    ) -> LawProposal? {
        let ticksPerYear = registry.config.ticksPerYear
        let eligible = registry.laws.values
            .filter { !hasLaw(settlement, $0.id) }
            .filter { $0.conditions.allSatisfy { WorldQuery.evaluate($0, in: state) } }
            .sorted { $0.id < $1.id }
        guard !eligible.isEmpty else { return nil }

        let weights = eligible.map(\.weight)
        guard let pick = rng.weightedIndex(weights) else { return nil }
        let law = eligible[pick]

        // Every adult weighs it for themselves, on what they are, what they do,
        // what they know and how their own life is going — see `AssemblyEngine`.
        return AssemblyEngine.vote(on: law, in: settlement, state: state,
                                   registry: registry, rng: &rng)
    }

    /// Morale cost of overruling the assembly, either way.
    public static let defianceMoralePenalty: Double = 8

    /// The leader's answer. Ratifying enacts the law (and fires its one-off
    /// effects); vetoing shelves it. Going against the assembly's vote costs
    /// the leader standing with the people.
    public static func resolveProposal(
        _ state: WorldState, approve: Bool, spendInfluence: Bool = false,
        registry: GameDataRegistry
    ) -> WorldState {
        guard let proposal = state.pendingLawProposal,
              let law = registry.law(proposal.definitionID),
              let index = state.settlements.firstIndex(where: { $0.id == proposal.settlementID })
        else { return state }

        var s = state
        s.pendingLawProposal = nil

        // Overruling the assembly — ratifying what it rejected, or vetoing what
        // it wanted — is what leadership costs. A Leader with standing to burn
        // can spend it instead and have the colony swallow the decision quietly.
        if approve != proposal.councilApproves {
            if spendInfluence, let paid = GameEngine.spendInfluence(s, amount: registry.config.overruleInfluenceCost) {
                s = paid
            } else {
                s.settlements[index].stats.morale = max(
                    0, s.settlements[index].stats.morale - defianceMoralePenalty)
            }
        }

        guard approve else { return s }

        let expires = s.tick + law.durationYears * registry.config.ticksPerYear
        s.settlements[index].laws.append(
            LawInstance(definitionID: law.id, enactedTick: s.tick, expiresTick: expires))
        return EffectApplier.apply(law.effects, to: s, registry: registry)
    }

    static func societySeed(mapSeed: UInt64, settlementID: UUID, year: Int) -> UInt64 {
        var h: UInt64 = mapSeed &* 0xD1B5_4A32_D192_ED03
        let b = settlementID.uuid
        let hi = UInt64(b.0) << 56 | UInt64(b.1) << 48 | UInt64(b.2) << 40 | UInt64(b.3) << 32
            | UInt64(b.4) << 24 | UInt64(b.5) << 16 | UInt64(b.6) << 8 | UInt64(b.7)
        h ^= hi
        h = (h ^ UInt64(bitPattern: Int64(year))) &* 0x0100_0000_01B3
        return h ^ (h >> 31)
    }
}
