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

    // How well two peoples can *possibly* get on, and the thresholds that live
    // under that ceiling. These have to be read together: relations only ever
    // drift toward `compatibility`, so any gate set above what compatibility
    // can reach is not a rare event — it's an impossible one. Measured before
    // this: 0 marriages, 0 wars and 0 defections across 250 years, with the
    // three standing tribes parked at 45/50/56 — exactly the old ceiling.
    /// The most two peoples can like each other before faith is counted.
    static let baseCompatibility = 62.0
    /// What a shared (or rival) faith is worth on top.
    static let faithAffinity = 16.0
    /// …so relations top out near `baseCompatibility + faithAffinity` = 78.

    /// Scholars start sharing once they're on good terms.
    static let exchangeStanding = 40.0
    /// Two houses join only when the peoples genuinely trust each other. It has
    /// to clear `baseCompatibility` *without* counting faith: a shared cult is
    /// worth 16 but is entirely optional — a colony may never raise a temple,
    /// and two faithless peoples must still be able to marry. Setting this
    /// against the with-faith ceiling is how the old value (70, against a
    /// ceiling of 57) came to be unreachable in the first place.
    static let marriageStanding = 55.0
    /// Quarrels start here.
    static let disputeStanding = -15.0
    /// And spill into raids here. An angry secession opens around −35, so this
    /// has to sit above that for a grudge to ever turn into a war.
    static let warStanding = -30.0

    /// **What an embassy is worth, each year it stands.**
    ///
    /// A rate rather than a payment, because `DiplomacyProbe` measured
    /// standings swinging over bands of fifty-eight to a hundred and fifty-five
    /// points: any single sum is noise against that, and a verb is felt when it
    /// accrues. Three a year is a quiet thing at five years and decisive at
    /// fifty — which is the difference between an embassy and a gift, stated in
    /// the only place the game can state it.
    static let envoyStandingPerYear = 3.0
    /// …and how much of a grievance living among somebody works off.
    static let envoyGrudgePerYear = 1.5

    /// **The most a colony may promise a people in a year**, in materials.
    ///
    /// A ceiling so the verb cannot be used to buy every neighbour off at once
    /// — peace has to be chosen, and choosing it for one people is choosing not
    /// to for another.
    public static let tributeMostPerYear = 120.0
    /// How much grievance a full year's tribute works off, at the ceiling.
    /// Scaled by what is actually paid, so half a tribute buys half a peace.
    static let tributeGrudgeRelief = 14.0
    /// …and what breaking the arrangement costs.
    ///
    /// **With what it would have been.** A colony that pays for twenty years
    /// and stops has not merely gone back to where it started: it has taught a
    /// people to expect something and then taken it away, which is worse than
    /// never having offered. Without this the verb is free to abandon, and a
    /// promise nobody can break is not a promise.
    static let tributeBrokenGrudge = 25.0
    /// Colonists only look over the fence at a people they don't fear.
    static let defectionStanding = 20.0
    /// Morale below which a colonist might leave regardless of wealth.
    static let defectionMorale = 55.0
    /// …or, whatever the average morale says, inequality at which those with
    /// nothing start leaving for a neighbour who might share. Mirrors
    /// `secessionGiniThreshold`: the poor leave, whether to found a people or
    /// to join one.
    static let defectionGiniThreshold = 0.45

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

            // A people you have never met has no relations to move: native
            // tribes live on quietly beyond the fog until first contact.
            guard s.tribes[index].discovered else { continue }
            // Somebody of ours has lived among them for another year. Applied
            // before the drift, so what the embassy earns is what the drift
            // then works from rather than an adjustment tacked on after it.
            s = envoyYear(s, tribeIndex: index)
            s = collectTribute(s, tribeIndex: index)
            s = drift(s, tribeIndex: index, registry: registry, rng: &rng)
            s = resolveRelations(s, tribeIndex: index, registry: registry, rng: &rng)
        }
        // …and once, of the colony: whether anybody has had enough of it.
        // Seeded from the capital's own id — never a fresh `UUID()`, even on
        // the impossible path, because that is how determinism dies quietly.
        if let capital = s.settlements.first {
            var leaving = SeededRNG(seed: tribeSeed(mapSeed: s.mapSeed,
                                                    tribeID: capital.id, year: year))
            s = maybeSomebodyLeaves(s, registry: registry, rng: &leaving)
        }
        return s
    }

    /// A year of an embassy standing. Nothing at all when nobody is posted —
    /// which is most peoples, most of the time.
    static func envoyYear(_ state: WorldState, tribeIndex: Int) -> WorldState {
        let tribeID = state.tribes[tribeIndex].id
        guard state.settlements.contains(where: { settlement in
            settlement.pawns.contains { $0.envoyToTribeID == tribeID }
        }) else { return state }
        var s = state
        s.tribes[tribeIndex].standing = clamp(
            s.tribes[tribeIndex].standing + envoyStandingPerYear)
        resent(&s.tribes[tribeIndex], by: -envoyGrudgePerYear)
        return s
    }

    /// A year of tribute: what we send, what it buys, and what it costs to stop.
    ///
    /// Paid out of the capital's materials. **A colony that cannot pay is a
    /// colony that has broken the arrangement**, which is deliberately the same
    /// thing as choosing to stop — a people on the receiving end cannot tell
    /// "we would not" from "we could not", and the game should not pretend they
    /// can.
    static func collectTribute(_ state: WorldState, tribeIndex: Int) -> WorldState {
        let owed = state.tribes[tribeIndex].tributePerYear
        guard owed > 0, let capital = state.settlements.indices.first else { return state }
        var s = state

        guard s.settlements[capital].storage[.materials] >= owed else {
            // The promise is broken, and the arrangement with it.
            s.tribes[tribeIndex].tributePerYear = 0
            resent(&s.tribes[tribeIndex], by: tributeBrokenGrudge)
            s.tribes[tribeIndex].standing = clamp(s.tribes[tribeIndex].standing - 10)
            let them = s.tribes[tribeIndex].name
            s.settlements[capital].journal.append(
                tick: s.tick, kind: .danger,
                text: LocalizedText(values: [
                    .en: "There was nothing in the store to send \(them). They will have noticed.",
                    .cs: "Ve skladu nebylo co poslat \(them). Jistě si toho všimli."]))
            return s
        }

        s.settlements[capital].storage[.materials] -= owed
        s.tribes[tribeIndex].stores += owed * 0.6
        // Scaled by what is actually paid: half a tribute buys half a peace.
        let share = min(1, owed / tributeMostPerYear)
        resent(&s.tribes[tribeIndex], by: -tributeGrudgeRelief * share)
        return s
    }

    // MARK: - Secession

    /// Malcontents (or the surplus of a crowded town) walk out and found a
    /// people of their own.
    static func secede(_ state: WorldState, registry: GameDataRegistry, year: Int) -> WorldState {
        // The cap is on *emergent* tribes — peoples born of your own
        // malcontents. Natives seeded at world creation don't use up the
        // discontent's room to leave.
        guard state.tribes.filter({ !$0.isNative }).count < maxTribes,
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
        //
        // **And of those, the bold go first.** Walking out of the only roof you
        // have ever known, into country nobody has mapped, is the one thing in
        // this game that plainly asks for courage — and it is the only place
        // courage can decide anything, because `GeneProbe` measured a colony
        // where 142 of 143 deaths in two centuries were old age. Until the
        // world is dangerous (see `DangerProbe`), a lifespan gene acts entirely
        // after the last child is born and selection cannot see it at all.
        //
        // So the colony gets steadier as its boldest keep leaving, and the
        // peoples out in the hills are founded by them — which is already how
        // a seceding band's character is worked out, three lines below.
        let ordered: [Pawn]
        if aggrieved {
            ordered = poor.sorted { $0.wealth != $1.wealth ? $0.wealth < $1.wealth
                                                           : boldestFirst($0, $1) }
        } else if miserable {
            ordered = adults.sorted { $0.mood != $1.mood ? $0.mood < $1.mood
                                                         : boldestFirst($0, $1) }
        } else {
            ordered = adults.sorted { boldestFirst($0, $1) }
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
            name: NameForge.tribeName(founder: founder, language: s.language),
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

    /// How much a grudge can ever weigh, so a hated colony is at war rather
    /// than at war with arithmetic.
    static let grudgeCeiling = 110.0

    /// **The one way a grudge goes up.**
    ///
    /// `grudgeCeiling` was applied at exactly one of the three places anger is
    /// added — the crowding clause — while a raid (+6) and a quarrel (+3) walked
    /// straight past it. `DiplomacyProbe` showed what that does: every one of
    /// five peoples sitting at **119**, the same number to the point, because
    /// they all reach the cap by crowding and then step over it.
    ///
    /// A ceiling enforced in one of three places is not a ceiling, and a number
    /// every neighbour is pinned to carries no information: it stops
    /// distinguishing a people you have wronged from one you have not. That is
    /// §8.5 inverted — then nothing could make anybody angry, now everything
    /// makes everybody as angry as it is possible to be.
    static func resent(_ tribe: inout Tribe, by amount: Double) {
        tribe.grudge = min(grudgeCeiling, max(0, tribe.grudge + amount))
    }

    /// **Anger that comes from nothing but the size of you.**
    ///
    /// This had a *lower* ceiling of its own for one measurement, on the
    /// reasoning that being big is a grievance and not the same grievance as
    /// being raided, so growth alone should carry a people to resentful and no
    /// further. It reads well and it gutted the game: `DiplomacyProbe` went
    /// from **67 wars in two hundred years to 2**, and from 92 fights to 53.
    ///
    /// The chain is crowding → grudge → `drift` pulls standing down →
    /// `standing < warStanding` → war, so a cap on crowding's grudge is a cap
    /// on how far standing can ever fall, and §8.5's whole finding was that a
    /// world where nothing can make a people angry has nothing in it. Reverted.
    ///
    /// The fault that measurement *did* find is real and is fixed elsewhere:
    /// `grudgeCeiling` was enforced at one of the three places anger is added,
    /// so every people overshot to exactly 119. A ceiling honoured in one place
    /// out of three is not a ceiling — that is what `resent` is for.
    ///
    /// If the saturation is worth attacking again, attack the **relief** rather
    /// than the source: trade and marriage take three off a grudge that grows
    /// by eight a year, and §8.5 claimed they "work it off". They do not.
    static func resentCrowding(_ tribe: inout Tribe, by amount: Double) {
        resent(&tribe, by: amount)
    }
    /// How many times the tribe's own numbers the colony may reach before the
    /// people who were here first start to mind.
    static let crowdingRatio = 1.6
    /// …and what each further multiple of them costs, per year.
    static let crowdingGrudgePerYear = 4.0

    /// The friction of being the bigger neighbour.
    ///
    /// Grudge used to have exactly one source — a quarrel over hunting grounds,
    /// gated on standing already being below −15 — while standing drifts toward
    /// a compatibility of 62 or better. So the only thing that could make a
    /// people angry required them to be angry already, and a measured two
    /// hundred years came out as six tribes parked at 0/0/0/+75/+80/+82 and
    /// **not one raid in the whole run**. Every fight in the game was wolves.
    ///
    /// That is rule 6 wearing a diplomat's coat: a threshold no rate aimed at
    /// it can reach. The fix is a source of friction that does not require
    /// hostility to exist, and the honest one is already in the world — land,
    /// game and water are finite, and a colony that outgrows its neighbours is
    /// taking somebody's share of them. Trade and marriage still work it off
    /// (`resolveRelations`), so this is a pressure to manage rather than a
    /// countdown to a war you cannot avoid.
    static func crowding(_ state: WorldState, tribeIndex: Int) -> Double {
        let theirs = max(4, state.tribes[tribeIndex].population)
        let ours = Double(state.settlements.reduce(0) { $0 + $1.pawns.count })
        let times = ours / theirs
        guard times > crowdingRatio else { return 0 }
        return min(crowdingGrudgePerYear * 2, (times - crowdingRatio) * crowdingGrudgePerYear)
    }

    /// Relations drift toward how compatible the two peoples actually are:
    /// alike in character, alike in faith, and not treading on each other.
    static func drift(
        _ state: WorldState, tribeIndex: Int,
        registry: GameDataRegistry, rng: inout SeededRNG
    ) -> WorldState {
        var s = state
        guard let capital = s.settlements.first, !capital.pawns.isEmpty else { return s }

        // What being a big, growing neighbour costs you, banked before anything
        // else is weighed. See `crowding`.
        resentCrowding(&s.tribes[tribeIndex], by: crowding(s, tribeIndex: tribeIndex))

        let ours = meanGenes(capital.pawns)
        let theirs = s.tribes[tribeIndex].genes
        var compatibility = baseCompatibility
            - abs(ours.courage - theirs.courage) * 50
            - abs(ours.sociability - theirs.sociability) * 30

        // A shared faith binds; a rival one divides.
        if let ourCult = capital.faith.cultID, let theirCult = s.tribes[tribeIndex].cultID {
            compatibility += (ourCult == theirCult) ? faithAffinity : -faithAffinity
        }
        // A marriage is a standing bond, not a one-off bump: the two houses
        // stay tied whatever else passes between them.
        if s.tribes[tribeIndex].married { compatibility += 10 }
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
            // Trading with the people you are crowding is how you live with
            // them. Grudge is a pressure to manage, not a countdown.
            s.tribes[tribeIndex].grudge = max(0, s.tribes[tribeIndex].grudge - 3)
        }

        // Scholars trade what they know.
        if standing > exchangeStanding, rng.nextUnit() < exchangeChance {
            deposit(&s, capitalIndex, .knowledge, 12)
            s.tribes[tribeIndex].standing = clamp(s.tribes[tribeIndex].standing + 2)
        }

        // A marriage of the two leading houses seals the peace.
        if standing > marriageStanding, !s.tribes[tribeIndex].married,
           s.settlements[capitalIndex].leaderID != nil, rng.nextUnit() < marriageChance {
            s.tribes[tribeIndex].married = true
            s.tribes[tribeIndex].standing = clamp(standing + 15)
            s.tribes[tribeIndex].grudge *= 0.4
            for i in s.settlements[capitalIndex].pawns.indices {
                s.settlements[capitalIndex].pawns[i].mood = min(
                    100, s.settlements[capitalIndex].pawns[i].mood + 6)
            }
        }

        // Quarrels over hunting grounds.
        if standing < disputeStanding, rng.nextUnit() < disputeChance {
            s.tribes[tribeIndex].standing = clamp(standing - 4)
            resent(&s.tribes[tribeIndex], by: 3)
            s.settlements[capitalIndex].stats.morale = max(
                0, s.settlements[capitalIndex].stats.morale - 2)
        }

        // War: they fall on the granaries. Walls and militia blunt the blow.
        if standing < warStanding, rng.nextUnit() < warChance,
           s.tribes[tribeIndex].population > 6, s.settlements[capitalIndex].pawns.count > 6 {
            s = raid(s, tribeIndex: tribeIndex, capitalIndex: capitalIndex,
                     registry: registry, rng: &rng)
        }

        // Or the leaders find a fragile peace.
        if s.tribes[tribeIndex].standing < warStanding, rng.nextUnit() < peaceChance {
            s.tribes[tribeIndex].standing = -5
            s.tribes[tribeIndex].grudge *= 0.5
        }

        return s
    }

    /// Defection: someone slips away to a people who might treat them better.
    ///
    /// This used to need average morale under 45 — the very condition that made
    /// secession unreachable, since a working colony sits at 70–86. But an
    /// average is exactly the wrong instrument: a colony can be content *on the
    /// whole* and still be one its poorest have no reason to stay in. So
    /// inequality drives it too, and the one who leaves is the one with least,
    /// not merely the saddest.
    ///
    /// **Asked once a year of the colony, not once a year of every neighbour.**
    /// It lived inside the per-tribe loop, so the rate was `0.30 × however many
    /// peoples you had met` — a number with nothing bounding it but the size of
    /// the map. The moment the council started charting regions on its own the
    /// colony met six peoples instead of one, and a town that was content, fed,
    /// housed and at 90 morale bled from fifty souls to thirty with no deaths
    /// but old age. Emigration is a fact about *the place people are leaving*;
    /// which neighbour they go to is a detail, and it is settled here by taking
    /// whoever stands highest with them.
    ///
    /// That is the recurring shape from the other side: not a rate too small to
    /// reach its threshold, but a rate multiplied by an entity count nobody
    /// capped.
    static func maybeSomebodyLeaves(
        _ state: WorldState, registry: GameDataRegistry, rng: inout SeededRNG
    ) -> WorldState {
        var s = state
        guard let capitalIndex = s.settlements.indices.first else { return s }
        let capital = s.settlements[capitalIndex]
        guard capital.pawns.count > 8 else { return s }

        let unequal = capital.society.gini > defectionGiniThreshold
        guard capital.stats.morale < defectionMorale || unequal else { return s }
        guard rng.nextUnit() < defectionChance else { return s }
        // Somewhere to go: the people they get on with best, ties on id.
        guard let tribeIndex = s.tribes.indices
            .filter({ s.tribes[$0].discovered && s.tribes[$0].standing > defectionStanding })
            .max(by: { a, b in
                s.tribes[a].standing == s.tribes[b].standing
                    ? s.tribes[a].id.uuidString > s.tribes[b].id.uuidString
                    : s.tribes[a].standing < s.tribes[b].standing
            })
        else { return s }

        let ticksPerYear = registry.config.ticksPerYear
        let candidates = capital.pawns.indices.filter {
            capital.pawns[$0].isAdult(ticksPerYear: ticksPerYear)
        }
        let leaver = unequal
            ? candidates.min(by: { capital.pawns[$0].wealth < capital.pawns[$1].wealth })
            : candidates.min(by: { capital.pawns[$0].mood < capital.pawns[$1].mood })
        guard let leaver else { return s }
        s.settlements[capitalIndex].pawns.remove(at: leaver)
        s.tribes[tribeIndex].population += 1
        s.tribes[tribeIndex].defections += 1
        return s
    }

    /// A raid resolved against the settlement's defenses, in two beats: the
    /// **volley** — ranged militia thins the raiders before they reach the
    /// walls — then the **clash**, melee against what remains. Loot leaves the
    /// granary; if the walls are overrun, colonists fall (armor blunts the
    /// blow); the raiders bleed for every fighter on the wall. The journal
    /// remembers the day either way.
    static func raid(
        _ state: WorldState, tribeIndex: Int, capitalIndex: Int,
        registry: GameDataRegistry, rng: inout SeededRNG
    ) -> WorldState {
        var s = state
        let raiderName = s.tribes[tribeIndex].name
        let strength = s.tribes[tribeIndex].population * 0.5
            + s.tribes[tribeIndex].genes.courage * 20

        // The raid **opens** rather than resolving.
        //
        // It used to be settled here, inside this one tick: eight rounds of
        // arithmetic between two frames, and the `BattleLog` the canvas played
        // afterwards was a recording of something already over. That is the
        // whole reason a raid could be watched and never fought.
        //
        // A siege is the same fight with its middle left open, so the player
        // can stand in it and give orders. Nobody has to: if the app is shut,
        // `ActionLoop` walks the world clock over the top of the siege and the
        // rest is fought exactly as it would have been — see `SiegeEngine`.
        s.settlements[capitalIndex] = SiegeEngine.begin(
            s.settlements[capitalIndex],
            attackerStrength: strength,
            attackerName: raiderName,
            attackerTribeID: s.tribes[tribeIndex].id,
            fortification: s.settlements[capitalIndex].stats.defense,
            tick: s.tick,
            registry: registry,
            seed: rng.next(),
            // They come in from where they live. The world map has always
            // known; the valley used to roll a die.
            approachBearing: Bearing.angle(
                fromRegion: s.settlements[capitalIndex].regionID,
                towardRegion: s.tribes[tribeIndex].regionID, in: s))

        // What the attempt costs the raiders is known when it ends, not now,
        // so only the standing consequences of *declaring* it land here.
        s.settlements[capitalIndex].journal.append(
            tick: s.tick, kind: .danger,
            text: LocalizedText(values: [
                .en: "\(raiderName) are coming over the ground — to arms.",
                .cs: "\(raiderName) táhnou přes pláň — do zbraně."]))

        s.settlements[capitalIndex].stats.morale = max(
            0, s.settlements[capitalIndex].stats.morale - 6)
        s.settlements[capitalIndex].stats.stability = max(
            0, s.settlements[capitalIndex].stats.stability - 5)
        s.globalStats = s.globalStats.applying(delta: 6, to: "threatLevel")
        s.tribes[tribeIndex].wars += 1
        resent(&s.tribes[tribeIndex], by: 6)
        s.tribes[tribeIndex].standing = clamp(s.tribes[tribeIndex].standing - 8)
        // …and they wreck the road on their way in. A chokepoint is only worth
        // holding if losing it costs something, and this is what makes the
        // colony's own network a thing war can take away.
        s = RoadEngine.cut(s, from: s.tribes[tribeIndex].regionID,
                           to: s.settlements[capitalIndex].id)
        return s
    }

    // MARK: - Helpers

    /// Adds a resource to a settlement without ever overfilling its stores.
    static func deposit(
        _ s: inout WorldState, _ index: Int, _ resource: ResourceType, _ amount: Double
    ) {
        s.settlements[index].storage[resource] = min(
            s.settlements[index].storageCapacity[resource],
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

    /// Who walks out first, all else equal: the boldest, and on a tie the same
    /// colonist every replay. Never the array's own order — `pawns` reorders as
    /// people die, and a choice that depends on it is not deterministic.
    static func boldestFirst(_ a: Pawn, _ b: Pawn) -> Bool {
        a.genes.courage != b.genes.courage
            ? a.genes.courage > b.genes.courage
            : a.id.uuidString < b.id.uuidString
    }

}
