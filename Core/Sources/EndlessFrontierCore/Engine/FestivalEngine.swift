import Foundation

/// Midsummer: the fires are lit, the stores are opened, and the colony spends
/// one night being a village rather than a workforce.
///
/// **Why this exists.** Measured twice, seed 4242: the colony peaks near seventy
/// around its eightieth year and decays to twenty-nine by its two hundredth,
/// with every store pinned at its cap. Nothing is short of anything. The column
/// that says why is `fert` in `GrowthProbe.theCurve` — couples with *both*
/// partners still inside the fertile window — which runs nine to twelve while
/// the colony grows and **one to four for the whole second century**. The
/// founders age out together and the bonds that would replace them form too
/// slowly to catch it.
///
/// And the reason they form too slowly is in `SocialEngine.encounter`: a
/// meeting is two colonists drawn **uniformly from everybody**. In a young
/// colony most people are unattached adults, so most meetings are courtships.
/// In an old one they are two married elders, or a child and a grandmother, and
/// the handful of young people who could still start a family spend their lives
/// not being drawn next to each other. Rule 6's shape again, and it is not a
/// number that fixes it — no rate on a uniform draw finds a needle in a
/// haystack. What fixes it is *a night when everybody is in the same place*.
///
/// So the festival is not a bonus. It is the one time in the year the colony
/// stops drawing meetings at random: the unattached stand around one fire, and
/// they meet the people nearest their own age, which is what a village does.
///
/// It also feeds into the birth rate the honest way rather than by touching it:
/// the feast lifts `Pawn.moodShift`, the mood formula reads that, and
/// `PopulationEngine.conceive` multiplies by mood. No new path, no special case.
///
/// Deterministic: every roll comes from `(mapSeed, settlement.id, tick)`, and
/// who dances with whom is decided by sorted age rather than by drawing.
public enum FestivalEngine {

    /// Food eaten per colonist at the feast.
    ///
    /// A colonist eats `foodPerPersonPerTick × ticksPerYear` in a year — six, at
    /// the shipped numbers — so this is about three months' rations spent in one
    /// night. Enough that a lean year is a lean festival and the player can feel
    /// the choice they never had to make; not so much that a colony one bad
    /// harvest from trouble is finished by its own party.
    public static let feastPerHead = 1.5

    /// The most of the larder a feast may ever take. A festival must not be a
    /// way for a colony to starve itself — the fires burn lower instead.
    static let mostOfTheLarder = 0.35

    /// How many new faces an unattached colonist meets at the fire.
    static let meetingsAtTheFire = 3

    /// What one of those meetings is worth against a chat by the well
    /// (`SocialEngine.strengthPerChat`, 7).
    ///
    /// Deliberately more than double: a courtship that takes a couple of years
    /// of chance meetings takes two or three midsummers, which is the pace a
    /// village actually marries at and — more to the point — a pace that does
    /// not depend on how big the colony has grown.
    static let strengthAtTheFire = 16.0

    /// The night does some of the work a long friendship otherwise has to
    /// (`SocialEngine.weddingMinStrength`, 45), and does it more readily
    /// (`weddingChance`, 0.22).
    static let weddingMinStrengthAtTheFire = 30.0
    static let weddingChanceAtTheFire = 0.45

    /// What a full feast does to everybody, and how long it sits with them.
    /// `moodShift` fades over a season (`PawnEngine.moodShiftDecay`), so
    /// midsummer is felt into the autumn and gone by the winter.
    static let festivalMood = 9.0
    static let festivalRecreation = 20.0
    static let festivalMorale = 4.0
    /// Below this share of a proper feast, it is a thin night and the colony
    /// knows it.
    static let leanBelow = 0.5

    /// Whether this tick is midsummer.
    ///
    /// Deliberately **not** the turn of the year, which already carries wages,
    /// classes, elections and the assembly (`SocietyEngine.advanceYear`). A
    /// festival that lands on the same tick as the tax collector is a line in a
    /// pile of lines.
    public static func isFestivalTick(_ tick: Int, ticksPerYear: Int) -> Bool {
        guard ticksPerYear >= 4 else { return false }
        let ofYear = ((tick % ticksPerYear) + ticksPerYear) % ticksPerYear
        return ofYear == ticksPerYear / 2
    }

    public static func advanceOneTick(
        _ state: WorldState, registry: GameDataRegistry
    ) -> WorldState {
        let ticksPerYear = max(1, registry.config.ticksPerYear)
        guard isFestivalTick(state.tick, ticksPerYear: ticksPerYear) else { return state }
        var s = state
        for index in s.settlements.indices {
            s.settlements[index] = hold(
                s.settlements[index], tick: s.tick, ticksPerYear: ticksPerYear,
                mapSeed: s.mapSeed, language: s.language)
        }
        return s
    }

    /// One settlement's midsummer.
    static func hold(
        _ settlement: Settlement, tick: Int, ticksPerYear: Int,
        mapSeed: UInt64, language: GameLanguage = .en
    ) -> Settlement {
        guard settlement.pawns.count >= 2 else { return settlement }
        var s = settlement
        var rng = SeededRNG(seed: festivalSeed(mapSeed: mapSeed, settlementID: s.id, tick: tick))

        // 1. The feast. Pay what the larder can stand, and no more.
        let wanted = feastPerHead * Double(s.pawns.count)
        let affordable = min(wanted, max(0, s.storage[.food]) * mostOfTheLarder)
        guard wanted > 0 else { return s }
        let lavishness = min(1, affordable / wanted)
        s.storage[.food] = max(0, s.storage[.food] - affordable)

        // A colony with nothing to put on the table does not hold a feast, and
        // that is its own kind of year.
        guard lavishness > 0.05 else {
            s.stats.morale = max(0, s.stats.morale - festivalMorale)
            s.note(tick: tick, kind: .social, text: LocalizedText(values: [
                .en: "Midsummer came and there was nothing to put on the table. The fires were lit anyway, and everyone went home early.",
                .cs: "Přišel slunovrat a nebylo co dát na stůl. Ohně se přesto zapálily a všichni šli brzy domů."]))
            return s
        }

        // 2. Everybody eats, and it sits with them into the autumn.
        for i in s.pawns.indices {
            s.pawns[i].needs.recreation = min(100, s.pawns[i].needs.recreation
                                              + festivalRecreation * lavishness)
            s.pawns[i].moodShift = min(PawnEngine.moodShiftLimit,
                                       s.pawns[i].moodShift + festivalMood * lavishness)
        }
        s.stats.morale = min(100, s.stats.morale + festivalMorale * lavishness)

        // 3. The fire. Who is standing at it, and who they end up beside.
        let matches = whoMeetsWhom(s, ticksPerYear: ticksPerYear)
        for (first, second) in matches {
            s = met(s, first: first, second: second,
                    worth: strengthAtTheFire * lavishness, tick: tick)
        }

        // 4. …and what comes of it. Separate pass, so a bond made tonight can
        //    be the one that is spoken for tonight.
        s = courtships(s, rng: &rng, tick: tick, ticksPerYear: ticksPerYear)

        s.note(tick: tick, kind: .social, text: lavishness < leanBelow
            ? LocalizedText(values: [
                .en: "A thin midsummer: the fires burned low and the tables were bare, but the young of the colony stood at them all the same.",
                .cs: "Hubený slunovrat: ohně dohořívaly a stoly byly prázdné, ale mladí z osady u nich stejně stáli."])
            : LocalizedText(values: [
                .en: "Midsummer. The stores were opened, the fires burned till dawn, and nobody worked a stroke.",
                .cs: "Slunovrat. Sýpky se otevřely, ohně hořely do rána a nikdo nehnul prstem."]))
        return s
    }

    /// Who stands next to whom at the fire.
    ///
    /// **Nearest in age, and this is the whole mechanism.** The colony's problem
    /// is not that people do not meet — it is that the two people who could
    /// still start a family are drawn next to each other about as often as any
    /// other pair, and in an ageing colony that is almost never. Sorting the
    /// unattached by age and letting each meet their neighbours in that order
    /// puts the twenty-somethings in front of each other without any rule about
    /// who *may* marry: `SocialEngine` deleted its age-gap bar on purpose, and
    /// this does not bring it back. A weighting is not a bar — a forty-year-old
    /// with nobody their own age left simply meets whoever is nearest.
    ///
    /// Pure and order-stable: no dictionary iteration, no randomness, ties
    /// broken by id.
    static func whoMeetsWhom(
        _ settlement: Settlement, ticksPerYear: Int
    ) -> [(Pawn, Pawn)] {
        let adultAge = Pawn.adultAgeYears * ticksPerYear
        let free = settlement.pawns
            .filter {
                $0.age >= adultAge && !$0.isBroken && $0.health > 0
                    && settlement.partnerID(of: $0.id) == nil
            }
            .sorted { $0.age == $1.age ? $0.id.uuidString < $1.id.uuidString : $0.age < $1.age }
        guard free.count >= 2 else { return [] }

        var out: [(Pawn, Pawn)] = []
        var seen = Set<String>()
        for (i, one) in free.enumerated() {
            // Their neighbours in age, on both sides, nearest first.
            var offsets: [Int] = []
            var step = 1
            while offsets.count < meetingsAtTheFire * 2, step <= free.count {
                offsets.append(step)
                offsets.append(-step)
                step += 1
            }
            var made = 0
            for offset in offsets where made < meetingsAtTheFire {
                let j = i + offset
                guard j >= 0, j < free.count else { continue }
                let other = free[j]
                let key = one.id.uuidString < other.id.uuidString
                    ? "\(one.id.uuidString)~\(other.id.uuidString)"
                    : "\(other.id.uuidString)~\(one.id.uuidString)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                out.append((one, other))
                made += 1
            }
        }
        return out
    }

    /// Two people spend an evening together.
    ///
    /// The head-full rule (`SocialEngine.maxRelationsPerPawn`) would otherwise
    /// make the festival do nothing for exactly the colonists it exists for —
    /// a sociable one is always full — so a new bond made at the fire pushes out
    /// the weakest bond they were already carrying. You stop thinking about
    /// somebody you met at last year's fire. Partners are never pushed out.
    static func met(
        _ settlement: Settlement, first: Pawn, second: Pawn, worth: Double, tick: Int
    ) -> Settlement {
        var s = settlement
        if let e = s.relationships.firstIndex(where: {
            $0.involves(first.id) && $0.involves(second.id)
        }) {
            switch s.relationships[e].kind {
            case .partner:
                return s
            case .rival:
                // A night of it wears a grudge down; it does not become a
                // courtship on the spot.
                s.relationships[e].strength -= worth
                if s.relationships[e].strength <= 0 { s.relationships.remove(at: e) }
                return s
            case .friend:
                let before = s.relationships[e].strength
                s.relationships[e].strength = min(100, before + worth)
                if before < SocialEngine.closeFriendStrength,
                   s.relationships[e].strength >= SocialEngine.closeFriendStrength {
                    s.note(tick: tick, kind: .social, text: LocalizedText(values: [
                        .en: "\(first.name) and \(second.name) were inseparable at the fire.",
                        .cs: "\(first.name) a \(second.name) se u ohně nehnuli od sebe."]),
                                     subject: .pawn(first.id),
                                     keptBy: [first.id, second.id])
                }
                return s
            }
        }
        SocialEngine.makeRoom(&s, for: first.id)
        SocialEngine.makeRoom(&s, for: second.id)
        s.relationships.append(Relationship(
            between: first.id, and: second.id, kind: .friend, strength: worth))
        return s
    }

    /// What the night makes of the bonds standing at the end of it.
    static func courtships(
        _ settlement: Settlement, rng: inout SeededRNG, tick: Int, ticksPerYear: Int
    ) -> Settlement {
        var s = settlement
        let adultAge = Pawn.adultAgeYears * ticksPerYear
        // A stable order to walk them in — `relationships` is an array, but the
        // *set* of candidates changes as couples are made, so sorting by id
        // keeps a replay identical.
        let candidates = s.relationships
            .filter { $0.kind == .friend && $0.strength >= weddingMinStrengthAtTheFire }
            .sorted { $0.id < $1.id }
            .map(\.id)

        for id in candidates {
            guard let e = s.relationships.firstIndex(where: { $0.id == id }),
                  s.relationships[e].kind == .friend,
                  let ai = s.pawns.firstIndex(where: { $0.id == s.relationships[e].a }),
                  let bi = s.pawns.firstIndex(where: { $0.id == s.relationships[e].b })
            else { continue }
            let first = s.pawns[ai], second = s.pawns[bi]
            guard first.age >= adultAge, second.age >= adultAge,
                  s.partnerID(of: first.id) == nil, s.partnerID(of: second.id) == nil,
                  rng.nextUnit() < weddingChanceAtTheFire else { continue }

            s.relationships[e] = Relationship(
                between: first.id, and: second.id, kind: .partner,
                strength: max(s.relationships[e].strength, 70))
            for i in [ai, bi] {
                s.pawns[i].needs.recreation = min(100, s.pawns[i].needs.recreation
                                                  + SocialEngine.weddingRecreation)
            }
            s.note(tick: tick, kind: .social, text: LocalizedText(values: [
                .en: "\(first.name) and \(second.name) were promised to each other before the midsummer fire.",
                .cs: "\(first.name) a \(second.name) si dali slovo před slunovratovým ohněm."]),
                             subject: .pawn(first.id), keptBy: [first.id, second.id])
        }
        return s
    }

    /// The same derivation `SocialEngine` uses, salted so midsummer's rolls are
    /// not the same rolls the ordinary day would have made on this tick.
    static func festivalSeed(mapSeed: UInt64, settlementID: UUID, tick: Int) -> UInt64 {
        SocialEngine.socialSeed(mapSeed: mapSeed, settlementID: settlementID, tick: tick)
            ^ 0xF3_57_1A_10_5E_ED_01
    }
}
