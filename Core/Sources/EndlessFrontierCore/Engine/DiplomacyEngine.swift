import Foundation

/// Neighbours, and what happens between you.
///
/// Tribes are *emergent*: when a settlement grows miserable or overcrowded, a
/// band of colonists walks out and founds its own hearth. From then on there is
/// someone to trade with, marry into, quarrel with, and go to war against — and
/// somewhere for your unhappy to defect to.
///
/// Runs once a year, deterministically from `(mapSeed, tribe.id, year)`.
public enum DiplomacyEngine {
    // Secession
    /// Below this morale, colonists start talking about leaving.
    static let secessionMoraleThreshold = 42.0
    static let secessionChance = 0.18
    /// Inequality past which the colony's poorest start looking at the horizon.
    /// Set just under `SocietyEngine.revoltGiniThreshold` (0.5): people leave
    /// before they riot.
    static let secessionGiniThreshold = 0.45
    static let secessionGrievanceChance = 0.14
    static let secessionMinAdults = 12
    static let settlersPerSecession = 6
    /// A crowded settlement sheds colonists even when content.
    static let overcrowdingFactor = 1.05
    static let overcrowdingChance = 0.25
    /// At most this many neighbouring peoples — the map stays legible.
    static let maxTribes = 3

    // Yearly life of a tribe
    static let tribeGrowthPerYear = 0.03
    static let tribeMaxPopulation = 140.0

    // Diplomacy rolls
    static let tradeChance = 0.35
    static let exchangeChance = 0.25
    static let marriageChance = 0.12
    static let disputeChance = 0.30
    static let warChance = 0.45
    static let peaceChance = 0.18
    static let defectionChance = 0.30

    /// A whole year of neighbours: who leaves, who grows, and what passes
    /// between you. Called from `SocietyEngine`'s year.
    public static func advanceYear(_ state: WorldState, registry: GameDataRegistry) -> WorldState {
        var s = state
        let year = s.year(registry.config)

        s = secede(s, registry: registry, year: year)

        for index in s.tribes.indices {
            var rng = SeededRNG(seed: tribeSeed(mapSeed: s.mapSeed,
                                                tribeID: s.tribes[index].id, year: year))
            // They live their own lives.
            s.tribes[index].population = min(
                tribeMaxPopulation,
                s.tribes[index].population * (1 + tribeGrowthPerYear))
            s.tribes[index].stores += s.tribes[index].population * 0.4
            s.tribes[index].grudge *= 0.98

            s = drift(s, tribeIndex: index, registry: registry, rng: &rng)
            s = resolveRelations(s, tribeIndex: index, registry: registry, rng: &rng)
        }
        return s
    }

    // MARK: - Secession

    /// Malcontents (or the surplus of a crowded town) walk out and found a
    /// people of their own.
    static func secede(_ state: WorldState, registry: GameDataRegistry, year: Int) -> WorldState {
        guard state.tribes.count < maxTribes,
              let capitalIndex = state.settlements.indices.first else { return state }
        var s = state
        let ticksPerYear = registry.config.ticksPerYear
        let capital = s.settlements[capitalIndex]

        let adults = capital.pawns.filter { $0.isAdult(ticksPerYear: ticksPerYear) }
        guard adults.count >= secessionMinAdults else { return s }

        var rng = SeededRNG(seed: tribeSeed(mapSeed: s.mapSeed, tribeID: capital.id, year: year)
                            ^ 0x5E_CE_55_10)
        let capacity = ResourceLoop.housingCapacity(capital, registry: registry)
        let crowded = capacity > 0 && capital.population > capacity * overcrowdingFactor
        let miserable = capital.stats.morale < secessionMoraleThreshold
        // The trigger that actually happens. Measured over 250 years: neither
        // of the two above ever fired — a working colony's morale sits at
        // 70–86, and `PopulationEngine.headroomFactor` damps births to nothing
        // as the huts fill, so population can't reach 105% of capacity at all.
        // Inequality, meanwhile, is everywhere: Gini reached 0.588 and sat over
        // the revolt threshold in 197 of 300 samples, with 1,328 of 3,322
        // colonists poor. A colony can be prosperous, content and well-housed
        // and still be one its poorest have no reason to stay in.
        let poor = adults.filter { capital.society.wealthClass(of: $0.wealth) == .poor }
        let aggrieved = capital.society.gini > secessionGiniThreshold
            && poor.count >= secessionMinAdults / 2

        let roll = rng.nextUnit()
        let leaves = (aggrieved && roll < secessionGrievanceChance)
            || (miserable && roll < secessionChance)
            || (crowded && roll < overcrowdingChance)
        guard leaves else { return s }

        // The settlers: those with least to lose go first. The rich have no
        // reason to walk into the wilderness.
        let ordered: [Pawn]
        if aggrieved {
            ordered = poor.sorted { $0.wealth != $1.wealth ? $0.wealth < $1.wealth
                                                           : $0.id.uuidString < $1.id.uuidString }
        } else if miserable {
            ordered = adults.sorted { $0.mood < $1.mood }
        } else {
            ordered = adults.sorted { $0.id.uuidString < $1.id.uuidString }
        }
        let settlers = Array(ordered.prefix(settlersPerSecession))
        guard settlers.count >= 4 else { return s }

        let departing = Set(settlers.map(\.id))
        s.settlements[capitalIndex].pawns.removeAll { departing.contains($0.id) }

        // Their character is the average of those who left — which is why an
        // angry secession founds an angry people.
        let n = Double(settlers.count)
        let genes = Genes(
            industry: settlers.reduce(0) { $0 + $1.genes.industry } / n,
            fertility: settlers.reduce(0) { $0 + $1.genes.fertility } / n,
            sociability: settlers.reduce(0) { $0 + $1.genes.sociability } / n,
            courage: settlers.reduce(0) { $0 + $1.genes.courage } / n)

        let founder = settlers[0].name
        let story: LocalizedText
        if aggrieved {
            story = LocalizedText(values: [
                .en: "Those who owned nothing followed \(founder) out, to build somewhere their work was their own.",
                .cs: "Ti, kdo neměli nic, odešli s \(founder) — postavit si místo, kde jim jejich práce bude patřit."])
        } else if miserable {
            story = LocalizedText(values: [
                .en: "Malcontents walked out under \(founder) and founded a hearth of their own.",
                .cs: "Nespokojenci odešli v čele s \(founder) a založili vlastní osadu."])
        } else {
            story = LocalizedText(values: [
                .en: "Colonists set out past the horizon under \(founder), seeking room to breathe.",
                .cs: "Kolonisté vyrazili za obzor v čele s \(founder) — hledali místo k životu."])
        }

        // Leaving in anger poisons the well from the first day. A people who
        // left over injustice remember who kept the wealth.
        let opening: Double
        if aggrieved {
            opening = -35 + rng.nextUnit() * 20
        } else if miserable {
            opening = -30 + rng.nextUnit() * 20
        } else {
            opening = -5 + rng.nextUnit() * 25
        }

        s.tribes.append(Tribe(
            id: rng.nextUUID(),
            name: "\(founder)ov lid",
            regionID: s.settlements[capitalIndex].regionID,
            foundedTick: s.tick,
            originStory: story,
            population: n,
            genes: genes,
            cultID: s.settlements[capitalIndex].faith.cultID,
            defense: 8 + rng.nextUnit() * 8,
            stores: 40,
            standing: opening))
        // Losing your poorest to the wilderness is a judgement on the colony,
        // and the ones left behind know it.
        let moraleCost = aggrieved ? 6.0 : (miserable ? 4.0 : 0)
        s.settlements[capitalIndex].stats.morale = max(
            0, s.settlements[capitalIndex].stats.morale - moraleCost)
        return s
    }

    // MARK: - How well you get on

    /// Relations drift toward how compatible the two peoples actually are:
    /// alike in character, alike in faith, and not treading on each other.
    static func drift(
        _ state: WorldState, tribeIndex: Int,
        registry: GameDataRegistry, rng: inout SeededRNG
    ) -> WorldState {
        var s = state
        guard let capital = s.settlements.first, !capital.pawns.isEmpty else { return s }

        let ours = meanGenes(capital.pawns)
        let theirs = s.tribes[tribeIndex].genes
        var compatibility = 45
            - abs(ours.courage - theirs.courage) * 50
            - abs(ours.sociability - theirs.sociability) * 30

        // A shared faith binds; a rival one divides.
        if let ourCult = capital.faith.cultID, let theirCult = s.tribes[tribeIndex].cultID {
            compatibility += (ourCult == theirCult) ? 12 : -12
        }
        compatibility -= s.tribes[tribeIndex].grudge

        let standing = s.tribes[tribeIndex].standing
        s.tribes[tribeIndex].standing = clamp(
            standing + (compatibility - standing) * 0.12 + (rng.nextUnit() * 8 - 4))
        return s
    }

    /// Trade, marriage, disputes, war, defections and fragile peace.
    static func resolveRelations(
        _ state: WorldState, tribeIndex: Int,
        registry: GameDataRegistry, rng: inout SeededRNG
    ) -> WorldState {
        var s = state
        guard let capitalIndex = s.settlements.indices.first else { return s }
        let standing = s.tribes[tribeIndex].standing

        // Trade: grain moves to whoever needs it, and both get richer for it.
        if standing > 30, rng.nextUnit() < tradeChance, s.tribes[tribeIndex].stores > 30 {
            let traded = 20.0
            s.tribes[tribeIndex].stores -= traded
            deposit(&s, capitalIndex, .food, traded)
            deposit(&s, capitalIndex, .influence, 4)
            s.tribes[tribeIndex].standing = clamp(standing + 3)
        }

        // Scholars trade what they know.
        if standing > 55, rng.nextUnit() < exchangeChance {
            deposit(&s, capitalIndex, .knowledge, 12)
            s.tribes[tribeIndex].standing = clamp(s.tribes[tribeIndex].standing + 2)
        }

        // A marriage of the two leading houses seals the peace.
        if standing > 70, !s.tribes[tribeIndex].married,
           s.settlements[capitalIndex].leaderID != nil, rng.nextUnit() < marriageChance {
            s.tribes[tribeIndex].married = true
            s.tribes[tribeIndex].standing = clamp(standing + 15)
            for i in s.settlements[capitalIndex].pawns.indices {
                s.settlements[capitalIndex].pawns[i].mood = min(
                    100, s.settlements[capitalIndex].pawns[i].mood + 6)
            }
        }

        // Quarrels over hunting grounds.
        if standing < -15, rng.nextUnit() < disputeChance {
            s.tribes[tribeIndex].standing = clamp(standing - 4)
            s.tribes[tribeIndex].grudge += 3
            s.settlements[capitalIndex].stats.morale = max(
                0, s.settlements[capitalIndex].stats.morale - 2)
        }

        // War: they fall on the granaries. Walls and militia blunt the blow.
        if standing < -45, rng.nextUnit() < warChance,
           s.tribes[tribeIndex].population > 6, s.settlements[capitalIndex].pawns.count > 6 {
            s = raid(s, tribeIndex: tribeIndex, capitalIndex: capitalIndex, rng: &rng)
        }

        // Or the leaders find a fragile peace.
        if s.tribes[tribeIndex].standing < -45, rng.nextUnit() < peaceChance {
            s.tribes[tribeIndex].standing = -5
            s.tribes[tribeIndex].grudge *= 0.5
        }

        // Defection: when the neighbours look happier, someone slips away.
        if s.tribes[tribeIndex].standing > 20,
           s.settlements[capitalIndex].stats.morale < 45,
           rng.nextUnit() < defectionChance,
           s.settlements[capitalIndex].pawns.count > 8 {
            let ticksPerYear = registry.config.ticksPerYear
            if let leaver = s.settlements[capitalIndex].pawns.indices
                .filter({ s.settlements[capitalIndex].pawns[$0].isAdult(ticksPerYear: ticksPerYear) })
                .min(by: { s.settlements[capitalIndex].pawns[$0].mood
                         < s.settlements[capitalIndex].pawns[$1].mood }) {
                s.settlements[capitalIndex].pawns.remove(at: leaver)
                s.tribes[tribeIndex].population += 1
                s.tribes[tribeIndex].defections += 1
            }
        }
        return s
    }

    /// A raid resolved against the settlement's defenses. Loot leaves the
    /// granary; if the walls are overrun, colonists fall.
    static func raid(
        _ state: WorldState, tribeIndex: Int, capitalIndex: Int, rng: inout SeededRNG
    ) -> WorldState {
        var s = state
        let strength = s.tribes[tribeIndex].population * 0.5
            + s.tribes[tribeIndex].genes.courage * 20
        let defense = s.settlements[capitalIndex].stats.defense
            + EffectApplier.militiaDefense(s.settlements[capitalIndex].pawns)

        // Loot: a well-defended granary keeps most of its grain.
        let breach = max(0, strength - defense)
        let lootFraction = min(0.35, 0.08 + breach / 200)
        let loot = s.settlements[capitalIndex].storage[.food] * lootFraction
        s.settlements[capitalIndex].storage[.food] -= loot
        s.tribes[tribeIndex].stores += loot

        // Casualties only when the defense is genuinely overrun.
        if breach > 10 {
            let woundCount = min(3, Int(breach / 15))
            var deaths = 0
            for _ in 0..<woundCount {
                guard let victim = s.settlements[capitalIndex].pawns.indices
                    .filter({ s.settlements[capitalIndex].pawns[$0].health > 0 })
                    .min(by: { s.settlements[capitalIndex].pawns[$0].health
                             < s.settlements[capitalIndex].pawns[$1].health }) else { break }
                let armored = s.settlements[capitalIndex].pawns[victim].equipment[.weapon] != nil ? 0.5 : 1.0
                s.settlements[capitalIndex].pawns[victim].health = max(
                    0, s.settlements[capitalIndex].pawns[victim].health - breach * armored)
                if s.settlements[capitalIndex].pawns[victim].health <= 0 { deaths += 1 }
            }
            if deaths > 0 {
                s.settlements[capitalIndex].pawns.removeAll { $0.health <= 0 }
                s.settlements[capitalIndex].deathTallies[
                    PawnDeathCause.battle.rawValue, default: 0] += deaths
            }
            // The raiders take losses of their own.
            s.tribes[tribeIndex].population = max(
                4, s.tribes[tribeIndex].population - Double(rng.next() % 3))
        }

        s.settlements[capitalIndex].stats.morale = max(
            0, s.settlements[capitalIndex].stats.morale - 6)
        s.settlements[capitalIndex].stats.stability = max(
            0, s.settlements[capitalIndex].stats.stability - 5)
        s.globalStats = s.globalStats.applying(delta: 6, to: "threatLevel")
        s.tribes[tribeIndex].wars += 1
        s.tribes[tribeIndex].grudge += 6
        s.tribes[tribeIndex].standing = clamp(s.tribes[tribeIndex].standing - 8)
        return s
    }

    // MARK: - Helpers

    /// Adds a resource to a settlement without ever overfilling its stores.
    static func deposit(
        _ s: inout WorldState, _ index: Int, _ resource: ResourceType, _ amount: Double
    ) {
        s.settlements[index].storage[resource] = min(
            s.settlements[index].storageCapacity,
            s.settlements[index].storage[resource] + amount)
    }

    static func meanGenes(_ pawns: [Pawn]) -> Genes {
        let n = Double(max(1, pawns.count))
        return Genes(
            industry: pawns.reduce(0) { $0 + $1.genes.industry } / n,
            fertility: pawns.reduce(0) { $0 + $1.genes.fertility } / n,
            sociability: pawns.reduce(0) { $0 + $1.genes.sociability } / n,
            courage: pawns.reduce(0) { $0 + $1.genes.courage } / n)
    }

    static func clamp(_ v: Double) -> Double { min(100, max(-100, v)) }

    static func tribeSeed(mapSeed: UInt64, tribeID: UUID, year: Int) -> UInt64 {
        var h: UInt64 = mapSeed &* 0x9E37_79B9_7F4A_7C15
        let b = tribeID.uuid
        let hi = UInt64(b.0) << 56 | UInt64(b.1) << 48 | UInt64(b.2) << 40 | UInt64(b.3) << 32
            | UInt64(b.4) << 24 | UInt64(b.5) << 16 | UInt64(b.6) << 8 | UInt64(b.7)
        h ^= hi
        h = (h ^ UInt64(bitPattern: Int64(year))) &* 0x0100_0000_01B3
        return h ^ (h >> 19)
    }
}
