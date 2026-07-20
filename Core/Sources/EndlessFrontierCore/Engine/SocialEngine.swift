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
    // How often colonists cross paths: one encounter per this many colonists
    // per tick (at least one for any inhabited settlement).
    static let colonistsPerEncounter = 10
    // What an encounter does to the recreation need.
    static let chatRecreation = 3.0
    static let quarrelRecreation = -6.0
    static let weddingRecreation = 22.0
    static let griefRecreation = -28.0
    // Bond dynamics.
    static let strengthPerChat = 7.0
    static let strengthPerQuarrel = 9.0
    static let decayPerTick = 0.035        // ≈ 2 points a year at 60 t/y
    static let forgottenThreshold = 3.0    // bonds below this are dropped
    static let closeFriendStrength = 50.0  // when the journal calls it friendship
    static let maxRelationsPerPawn = 5
    // Quarrels and weddings.
    static let baseQuarrelChance = 0.16
    static let weddingChance = 0.10
    static let weddingMinStrength = 45.0
    static let weddingMaxAgeGapYears = 14
    // Grief only strikes for bonds that meant something.
    static let griefMinStrength = 35.0
    // How much of colonist chatter makes the journal — most of it stays
    // between the two of them, or the diary would drown in small talk.
    static let chatJournalChance = 0.10

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
        let existing = s.relationships.firstIndex {
            $0.involves(first.id) && $0.involves(second.id)
        }
        let sociability = (first.genes.sociability + second.genes.sociability) / 2
        var quarrelChance = baseQuarrelChance * (1.4 - sociability)
        if let e = existing, s.relationships[e].kind == .rival {
            quarrelChance = max(quarrelChance, 0.5)
        }

        if rng.nextUnit() < quarrelChance {
            return quarrel(s, first: first, second: second,
                           existing: existing, rng: &rng, tick: tick)
        }

        // A good chat.
        adjustRecreation(&s, first.id, by: chatRecreation)
        adjustRecreation(&s, second.id, by: chatRecreation)

        if let e = existing {
            let before = s.relationships[e].strength
            if s.relationships[e].kind == .rival {
                // Warm words wear a grudge down instead of feeding a bond.
                s.relationships[e].strength -= strengthPerChat
                if s.relationships[e].strength <= 0 {
                    s.relationships.remove(at: e)
                }
            } else {
                s.relationships[e].strength = min(100, before + strengthPerChat)
                // The moment two colonists become proper friends is worth a line.
                if before < closeFriendStrength, s.relationships[e].strength >= closeFriendStrength {
                    s.journal.append(tick: tick, kind: .social, text: LocalizedText(values: [
                        .en: "\(first.name) and \(second.name) have become fast friends.",
                        .cs: "\(first.name) a \(second.name) se skamarádili."
                    ]))
                }
                // …and old friends may become something more.
                if s.relationships[e].kind == .friend {
                    s = maybeWed(s, first: first, second: second, bondIndex: e,
                                 rng: &rng, tick: tick, ticksPerYear: ticksPerYear)
                }
            }
        } else if s.relationships(of: first.id).count < maxRelationsPerPawn,
                  s.relationships(of: second.id).count < maxRelationsPerPawn {
            s.relationships.append(Relationship(
                between: first.id, and: second.id, kind: .friend, strength: strengthPerChat + 4))
        }

        // A sliver of chatter reaches the diary — enough to hear the village.
        if rng.nextUnit() < chatJournalChance {
            let spot = chatSpots[Int(rng.next() % UInt64(chatSpots.count))]
            s.journal.append(tick: tick, kind: .social, text: LocalizedText(values: [
                .en: "\(first.name) and \(second.name) shared stories \(spot.resolve(.en)).",
                .cs: "\(first.name) a \(second.name) si povídali \(spot.resolve(.cs))."
            ]))
        }
        return s
    }

    /// Hard words: recreation drains, and the bond curdles toward rivalry.
    static func quarrel(
        _ settlement: Settlement, first: Pawn, second: Pawn,
        existing: Int?, rng: inout SeededRNG, tick: Int
    ) -> Settlement {
        var s = settlement
        adjustRecreation(&s, first.id, by: quarrelRecreation)
        adjustRecreation(&s, second.id, by: quarrelRecreation)

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
                }
            case .partner:
                // Married couples quarrel too; the marriage holds.
                break
            }
        } else if s.relationships(of: first.id).count < maxRelationsPerPawn,
                  s.relationships(of: second.id).count < maxRelationsPerPawn {
            // A new grudge is still a bond — it competes for the same few
            // slots a colonist's head has room for.
            s.relationships.append(Relationship(
                between: first.id, and: second.id, kind: .rival, strength: strengthPerQuarrel))
        }

        s.journal.append(tick: tick, kind: .social, text: LocalizedText(values: [
            .en: "\(first.name) and \(second.name) quarrelled — hard words carried across the green.",
            .cs: "\(first.name) a \(second.name) se pohádali — ostrá slova bylo slyšet přes náves."
        ]))
        return s
    }

    /// Close friends, both adult and unattached, may wed.
    static func maybeWed(
        _ settlement: Settlement, first: Pawn, second: Pawn, bondIndex: Int,
        rng: inout SeededRNG, tick: Int, ticksPerYear: Int
    ) -> Settlement {
        var s = settlement
        let adultAgeTicks = Pawn.adultAgeYears * ticksPerYear
        guard s.relationships[bondIndex].strength >= weddingMinStrength,
              first.age >= adultAgeTicks, second.age >= adultAgeTicks,
              abs(first.age - second.age) <= weddingMaxAgeGapYears * ticksPerYear,
              s.partnerID(of: first.id) == nil, s.partnerID(of: second.id) == nil,
              rng.nextUnit() < weddingChance else { return s }

        s.relationships[bondIndex] = Relationship(
            between: first.id, and: second.id, kind: .partner,
            strength: max(s.relationships[bondIndex].strength, 70))
        adjustRecreation(&s, first.id, by: weddingRecreation)
        adjustRecreation(&s, second.id, by: weddingRecreation)
        // The whole settlement celebrates a little.
        for i in s.pawns.indices {
            s.pawns[i].needs.recreation = min(100, s.pawns[i].needs.recreation + 2)
        }
        s.journal.append(tick: tick, kind: .social, text: LocalizedText(values: [
            .en: "\(first.name) and \(second.name) were wed — the whole settlement celebrated into the night.",
            .cs: "\(first.name) a \(second.name) měli svatbu — celá osada slavila dlouho do noci."
        ]))
        return s
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
        settlement.pawns[i].needs.recreation = min(100, max(0, settlement.pawns[i].needs.recreation + delta))
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
