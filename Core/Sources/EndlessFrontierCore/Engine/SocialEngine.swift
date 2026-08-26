import Foundation

/// The colonists' life together: chance meetings that become friendships,
/// hard words that become rivalries, weddings, and grief when a bond is cut.
///
/// Social life works through *needs*, not by writing mood directly — a good
/// chat tops up recreation, a quarrel drains it — because `PawnEngine`
/// recomputes mood from needs every tick, so only needs persist. The visible
/// result: sociable colonists stay happier, the friendless sink, and the
/// journal reads like a village actually lives here.
///
/// Deterministic: every roll comes from `(mapSeed, settlement.id, tick)`.
public enum SocialEngine {
    /// How often colonists cross paths: one encounter per this many colonists
    /// per tick (at least one for any inhabited settlement).
    ///
    /// **Two, not ten**, and this is rule 6 in the social layer. Encounters grow
    /// with the *population* while the pairs who could meet grow with its
    /// square, so a bigger colony means any given two people meet less often —
    /// while `decayPerTick` eats their bond at the same rate regardless. At one
    /// encounter per ten colonists a friendship in a village of seventeen
    /// gained about two points a meeting and met every two and a third years:
    /// **forty-five years to reach the wedding threshold**, which is to say
    /// never. Measured consequence, once children came from marriages: five
    /// couples, all of them the original founders, no one born after year
    /// twenty ever married, and the colony gone by year 130.
    ///
    /// At two, a courtship is a couple of years and it *stays* a couple of
    /// years as the town grows, which is what the rule asks: the rate has to be
    /// able to reach the threshold from every size the thing can be.
    static let colonistsPerEncounter = 2
    // What an encounter does to the recreation need.
    static let chatRecreation = 3.0
    static let quarrelRecreation = -6.0
    static let weddingRecreation = 22.0
    static let griefRecreation = -28.0
    // Bond dynamics.
    static let strengthPerChat = 7.0
    /// **How much two colonists' sociability moves a bond along.**
    ///
    /// Sociability used to touch one thing only — how likely a meeting was to
    /// end in a quarrel — and `GeneProbe` measured what that is worth: the
    /// selection differential on sociability wandered around zero for two
    /// hundred years while the colony's mean crawled back to 0.5.
    ///
    /// Children come out of bonds now (`PopulationEngine.conceive`), so how
    /// fast a bond grows *is* how many children a colonist has. That makes this
    /// the one place sociability can be a disposition rather than a decoration:
    /// two people who are easy company are close sooner, wed sooner, and have
    /// more of their fertile years in front of them when they do.
    ///
    /// At a pair mean of 0.5 the factor is exactly 1, so the average colony's
    /// courtship — and every growth number measured against it — is unchanged.
    static let sociabilityBondPull = 0.8
    static let strengthPerQuarrel = 9.0
    static let decayPerTick = 0.035        // ≈ 2 points a year at 60 t/y
    static let forgottenThreshold = 3.0    // bonds below this are dropped
    static let closeFriendStrength = 50.0  // when the journal calls it friendship
    static let maxRelationsPerPawn = 5
    // Quarrels and weddings.
    static let baseQuarrelChance = 0.16
    /// How readily two close friends with free hearts marry, per meeting.
    ///
    /// Raised from 0.10 when children stopped coming from a birth rate and
    /// started coming from marriages (`PopulationEngine.conceive`). At a tenth
    /// a village of thirteen made roughly one couple a decade, which is not a
    /// colony — it is a bachelor camp that dies of old age, measured, in a
    /// hundred and thirty years. Weddings *are* the growth curve now, so they
    /// have to happen at the rate a colony's future depends on.
    static let weddingChance = 0.22
    static let weddingMinStrength = 45.0
    // **No age-gap rule.** Two people who are close enough to marry, marry.
    //
    // There used to be one — no wedding across more than fourteen years — and
    // it was doing a job that belongs somewhere else. The thing it was really
    // guarding against is a couple who cannot have children, and
    // `PopulationEngine.fertilityAt` says that far better: fertility now tapers
    // with age, per person, so an older pair simply have few children rather
    // than being forbidden a marriage. Two rules for one fact, and the blunter
    // one was also the one that stopped people marrying at all.
    // Grief only strikes for bonds that meant something.
    static let griefMinStrength = 35.0
    // How much of colonist chatter makes the journal — most of it stays
    // between the two of them, or the diary would drown in small talk.
    static let chatJournalChance = 0.02
    // Both cut by five when `colonistsPerEncounter` went from ten to two: five
    // times the meetings at the same journal odds is five times the small talk,
    // and the page filled with "so-and-so chatted" until a **wedding** was
    // pushed out of the buffer inside six hundred ticks. Caught by the test
    // that asks whether a wedding makes the diary — which is the right thing to
    // have been asking.
    // And even less of the quarrelling. A friendship breaking always earns a
    // line, but a routine spat only rarely — otherwise the page fills with
    // "so-and-so quarrelled" and drowns out births, deaths, raids and roofs.
    static let quarrelJournalChance = 0.012

    /// Where a chat happens — journal flavour.
    static let chatSpots: [LocalizedText] = [
        LocalizedText(values: [.en: "by the well", .cs: "u studny"]),
        LocalizedText(values: [.en: "on the green", .cs: "na návsi"]),
        LocalizedText(values: [.en: "down by the river", .cs: "dole u řeky"]),
        LocalizedText(values: [.en: "over the evening fire", .cs: "u večerního ohně"]),
        LocalizedText(values: [.en: "at the granary door", .cs: "před sýpkou"]),
    ]

    /// One tick of village life: encounters, bond decay, housekeeping.
    public static func advanceOneTick(
        _ settlement: Settlement,
        registry: GameDataRegistry,
        tick: Int,
        mapSeed: UInt64
    ) -> Settlement {
        guard settlement.pawns.count >= 2 else { return settlement }
        var s = settlement
        var rng = SeededRNG(seed: socialSeed(mapSeed: mapSeed, settlementID: s.id, tick: tick))
        let ticksPerYear = max(1, registry.config.ticksPerYear)

        // 1. Bonds fade unless life refreshes them; the forgotten are dropped.
        for i in s.relationships.indices {
            // A marriage doesn't quietly evaporate.
            if s.relationships[i].kind != .partner {
                s.relationships[i].strength -= decayPerTick
            }
        }
        s.relationships.removeAll { $0.kind != .partner && $0.strength < forgottenThreshold }

        // 2. Chance meetings.
        let encounters = max(1, s.pawns.count / colonistsPerEncounter)
        for _ in 0..<encounters {
            s = encounter(s, rng: &rng, tick: tick, ticksPerYear: ticksPerYear)
        }

        // 3. Housekeeping: bonds to colonists who died or walked out.
        let living = Set(s.pawns.map(\.id))
        s.relationships.removeAll { !living.contains($0.a) || !living.contains($0.b) }

        return s
    }

    /// Two colonists cross paths: they chat, quarrel — or, if the bond is
    /// strong and both hearts free, wed.
    static func encounter(
        _ settlement: Settlement, rng: inout SeededRNG, tick: Int, ticksPerYear: Int
    ) -> Settlement {
        var s = settlement
        let count = s.pawns.count
        guard count >= 2 else { return s }

        let ai = Int(rng.next() % UInt64(count))
        var bi = Int(rng.next() % UInt64(count - 1))
        if bi >= ai { bi += 1 }
        let first = s.pawns[ai]
        let second = s.pawns[bi]

        // How the meeting goes: rivals and the unsociable clash more.
        let existing = s.relationships.firstIndex { $0.joins(first.id, second.id) }
        let sociability = (first.genes.sociability + second.genes.sociability) / 2
        var quarrelChance = baseQuarrelChance * (1.4 - sociability)
        if let e = existing, s.relationships[e].kind == .rival {
            quarrelChance = max(quarrelChance, 0.5)
        }

        if rng.nextUnit() < quarrelChance {
            return quarrel(s, first: first, second: second, at: (ai, bi),
                           existing: existing, rng: &rng, tick: tick)
        }

        // A good chat.
        adjustRecreation(&s, at: ai, by: chatRecreation)
        adjustRecreation(&s, at: bi, by: chatRecreation)

        if let e = existing {
            let before = s.relationships[e].strength
            if s.relationships[e].kind == .rival {
                // Warm words wear a grudge down instead of feeding a bond.
                s.relationships[e].strength -= strengthPerChat
                if s.relationships[e].strength <= 0 {
                    s.relationships.remove(at: e)
                }
            } else {
                s.relationships[e].strength = min(100, before + strengthPerChat
                                                  * bondPull(first.genes, second.genes))
                // The moment two colonists become proper friends is worth a line.
                if before < closeFriendStrength, s.relationships[e].strength >= closeFriendStrength {
                    s.journal.append(tick: tick, kind: .social, text: LocalizedText(values: [
                        .en: "\(first.name) and \(second.name) have become fast friends.",
                        .cs: "\(first.name) a \(second.name) se skamarádili."
                    ]), subject: .pawn(first.id))
                }
                // …and old friends may become something more.
                if s.relationships[e].kind == .friend {
                    s = maybeWed(s, first: first, second: second, at: (ai, bi), bondIndex: e,
                                 rng: &rng, tick: tick, ticksPerYear: ticksPerYear)
                }
            }
        } else if s.bondCount(of: first.id) < maxRelationsPerPawn,
                  s.bondCount(of: second.id) < maxRelationsPerPawn {
            s.relationships.append(Relationship(
                between: first.id, and: second.id, kind: .friend,
                strength: strengthPerChat * bondPull(first.genes, second.genes) + 4))
        }

        // A sliver of chatter reaches the diary — enough to hear the village.
        if rng.nextUnit() < chatJournalChance {
            let spot = chatSpots[Int(rng.next() % UInt64(chatSpots.count))]
            s.journal.append(tick: tick, kind: .social, text: LocalizedText(values: [
                .en: "\(first.name) and \(second.name) shared stories \(spot.resolve(.en)).",
                .cs: "\(first.name) a \(second.name) si povídali \(spot.resolve(.cs))."
            ]), subject: .pawn(first.id))
        }
        return s
    }

    /// How readily these two grow close, out of what they were born with.
    /// See `sociabilityBondPull` — 1 at the middle of the distribution.
    static func bondPull(_ a: Genes, _ b: Genes) -> Double {
        let mean = (a.sociability + b.sociability) / 2
        return max(0.25, 1 + (mean - 0.5) * sociabilityBondPull)
    }

    /// Hard words: recreation drains, and the bond curdles toward rivalry.
    static func quarrel(
        _ settlement: Settlement, first: Pawn, second: Pawn, at rows: (Int, Int),
        existing: Int?, rng: inout SeededRNG, tick: Int
    ) -> Settlement {
        var s = settlement
        adjustRecreation(&s, at: rows.0, by: quarrelRecreation)
        adjustRecreation(&s, at: rows.1, by: quarrelRecreation)

        var friendshipBroke = false
        if let e = existing {
            switch s.relationships[e].kind {
            case .rival:
                s.relationships[e].strength = min(100, s.relationships[e].strength + strengthPerQuarrel)
            case .friend:
                // A quarrel between friends wounds the friendship; a deep one
                // survives it, a shallow one flips to rivalry.
                s.relationships[e].strength -= strengthPerQuarrel * 2
                if s.relationships[e].strength <= 0 {
                    s.relationships[e] = Relationship(
                        between: first.id, and: second.id, kind: .rival, strength: strengthPerQuarrel)
                    friendshipBroke = true
                }
            case .partner:
                // Married couples quarrel too; the marriage holds.
                break
            }
        } else if s.bondCount(of: first.id) < maxRelationsPerPawn,
                  s.bondCount(of: second.id) < maxRelationsPerPawn {
            // A new grudge is still a bond — it competes for the same few
            // slots a colonist's head has room for.
            s.relationships.append(Relationship(
                between: first.id, and: second.id, kind: .rival, strength: strengthPerQuarrel))
        }

        // A friendship curdling into a grudge is a real turn in a life and
        // always earns a line. A routine spat does not — like small talk, only
        // a sliver reaches the diary, so the page stays about what mattered.
        if friendshipBroke {
            s.journal.append(tick: tick, kind: .social, text: LocalizedText(values: [
                .en: "\(first.name) and \(second.name) fell out — a friendship soured into a grudge.",
                .cs: "\(first.name) a \(second.name) se rozkmotřili — z přátelství se stala zášť."
            ]), subject: .pawn(first.id))
        } else if rng.nextUnit() < quarrelJournalChance {
            s.journal.append(tick: tick, kind: .social, text: LocalizedText(values: [
                .en: "\(first.name) and \(second.name) quarrelled — hard words carried across the green.",
                .cs: "\(first.name) a \(second.name) se pohádali — ostrá slova bylo slyšet přes náves."
            ]), subject: .pawn(first.id))
        }
        return s
    }

    /// Close friends, both adult and unattached, may wed.
    static func maybeWed(
        _ settlement: Settlement, first: Pawn, second: Pawn, at rows: (Int, Int),
        bondIndex: Int, rng: inout SeededRNG, tick: Int, ticksPerYear: Int
    ) -> Settlement {
        var s = settlement
        let adultAgeTicks = Pawn.adultAgeYears * ticksPerYear
        guard s.relationships[bondIndex].strength >= weddingMinStrength,
              first.age >= adultAgeTicks, second.age >= adultAgeTicks,
              s.partnerID(of: first.id) == nil, s.partnerID(of: second.id) == nil,
              rng.nextUnit() < weddingChance else { return s }

        s.relationships[bondIndex] = Relationship(
            between: first.id, and: second.id, kind: .partner,
            strength: max(s.relationships[bondIndex].strength, 70))
        adjustRecreation(&s, at: rows.0, by: weddingRecreation)
        adjustRecreation(&s, at: rows.1, by: weddingRecreation)
        // The whole settlement celebrates a little.
        for i in s.pawns.indices {
            s.pawns[i].needs.recreation = min(100, s.pawns[i].needs.recreation + 2)
        }
        s.journal.append(tick: tick, kind: .social, text: LocalizedText(values: [
            .en: "\(first.name) and \(second.name) were wed — the whole settlement celebrated into the night.",
            .cs: "\(first.name) a \(second.name) měli svatbu — celá osada slavila dlouho do noci."
        ]), subject: .pawn(first.id))
        return s
    }

    /// Drops the weakest bond a colonist is carrying, if their head is full.
    ///
    /// `maxRelationsPerPawn` is five, and a sociable colonist is always at it —
    /// which means every system that tries to *give* somebody a new bond does
    /// nothing for exactly the people it exists for. Ordinary meetings can
    /// afford to shrug and try again tomorrow; a midsummer fire and a coming of
    /// age happen once, so they make room instead. You stop thinking about
    /// somebody you met at last year's fire. A partner is never pushed out.
    ///
    /// Order-stable: ties are broken by the bond's id, never by array order.
    static func makeRoom(_ s: inout Settlement, for pawn: UUID) {
        guard s.relationships(of: pawn).count >= maxRelationsPerPawn else { return }
        let droppable = s.relationships.indices.filter {
            s.relationships[$0].involves(pawn) && s.relationships[$0].kind != .partner
        }
        guard let weakest = droppable.min(by: {
            s.relationships[$0].strength == s.relationships[$1].strength
                ? s.relationships[$0].id < s.relationships[$1].id
                : s.relationships[$0].strength < s.relationships[$1].strength
        }) else { return }
        s.relationships.remove(at: weakest)
    }

    /// Grief for the dead: those who loved them feel the loss, and their bonds
    /// are laid to rest with them. Called by `PopulationEngine` on each death.
    static func mourn(
        _ settlement: Settlement, dead: Pawn, tick: Int
    ) -> Settlement {
        var s = settlement
        for bond in s.relationships where bond.involves(dead.id) {
            guard bond.kind == .partner || bond.strength >= griefMinStrength,
                  bond.kind != .rival,
                  let survivorID = bond.other(than: dead.id),
                  let si = s.pawns.firstIndex(where: { $0.id == survivorID }) else { continue }
            s.pawns[si].needs.recreation = max(0, s.pawns[si].needs.recreation + griefRecreation)
            s.journal.append(tick: tick, kind: .death, text: LocalizedText(values: [
                .en: "\(s.pawns[si].name) mourns \(dead.name).",
                .cs: "\(s.pawns[si].name) truchlí pro \(dead.name)."
            ]))
        }
        s.relationships.removeAll { $0.involves(dead.id) }
        return s
    }

    /// Fixed-point-free helper: nudges one colonist's recreation need.
    static func adjustRecreation(_ settlement: inout Settlement, _ pawnID: UUID, by delta: Double) {
        guard let i = settlement.pawns.firstIndex(where: { $0.id == pawnID }) else { return }
        adjustRecreation(&settlement, at: i, by: delta)
    }

    /// The same, for a caller that already knows where the colonist stands.
    ///
    /// `encounter` draws its two people **by index** and then handed their ids
    /// to a linear search that found the row it had just come from — four scans
    /// of the roster per meeting, and meetings scale with the population
    /// (§11.23). Nothing inside an encounter removes a colonist, so the index
    /// the draw produced is still good when the blows and the chatter land.
    static func adjustRecreation(_ settlement: inout Settlement, at index: Int, by delta: Double) {
        guard settlement.pawns.indices.contains(index) else { return }
        settlement.pawns[index].needs.recreation =
            min(100, max(0, settlement.pawns[index].needs.recreation + delta))
    }

    static func socialSeed(mapSeed: UInt64, settlementID: UUID, tick: Int) -> UInt64 {
        var h: UInt64 = mapSeed &* 0x9E37_79B9_7F4A_7C15
        let b = settlementID.uuid
        let hi = UInt64(b.8) << 56 | UInt64(b.9) << 48 | UInt64(b.10) << 40 | UInt64(b.11) << 32
            | UInt64(b.12) << 24 | UInt64(b.13) << 16 | UInt64(b.14) << 8 | UInt64(b.15)
        h ^= hi
        h = (h ^ UInt64(bitPattern: Int64(tick))) &* 0x0100_0000_01B3
        return (h ^ (h >> 27)) &+ 0x50C1_A11F
    }
}
