import Foundation

/// Outlaws: a raid that belongs to nobody.
///
/// Every fight in the game came from one of two places — a *people* who had
/// come to hate you, or the wild. Both are relationships: a tribe can be traded
/// with, married into and made peace with, and wolves are a pressure you can
/// hunt down. There was nothing in the world that simply *wanted your grain*,
/// which meant a colony with good neighbours and a quiet wood had no enemies at
/// all, however rich it got.
///
/// Bandits are the third kind, and they are drawn by exactly the thing a
/// prosperous colony cannot hide: a full granary, a road to it, and not enough
/// people watching. They cannot be negotiated with — there is no standing to
/// mend and no tribe to charge for the attempt — so the only answers are a wall,
/// a garrison, and not leaving that much grain lying about.
public enum BanditEngine {

    /// Checked on this cadence, in ticks (rule 4).
    public static let interval = 20

    /// The base odds per check. Everything else multiplies it.
    static let baseChance = 0.010
    /// A colony smaller than this is not worth the walk.
    static let minimumPopulation = 12
    /// How full the stores have to be before anybody notices.
    static let noticedAtShare = 0.35
    /// The most the stores may multiply the odds by.
    static let wealthCeiling = 3.0
    /// A watched colony is a colony they go around: at this many spears per
    /// hundred people, the odds are roughly halved.
    static let garrisonHalfPoint = 6.0
    /// What a band is worth, per point of the grain that drew it.
    static let strengthPerShare = 26.0
    /// …and never less than this, or a band arrives that a shepherd sees off.
    static let minimumStrength = 14.0

    public static func advanceOneTick(
        _ settlement: Settlement, registry: GameDataRegistry, tick: Int,
        era: Era, mapSeed: UInt64
    ) -> Settlement {
        guard tick % interval == 0, settlement.siege == nil,
              settlement.pawns.count >= minimumPopulation else { return settlement }
        var s = settlement
        var rng = SeededRNG(seed: seed(mapSeed: mapSeed, settlementID: s.id, tick: tick))

        let lure = temptation(s)
        guard lure > 0 else { return s }
        let odds = baseChance * lure * (1 - watchfulness(s, registry: registry))
        guard rng.nextUnit() < min(0.4, odds) else { return s }

        let strength = max(minimumStrength, lure * strengthPerShare)
        let band = name(era: era, rng: &rng)
        s = SiegeEngine.begin(
            s,
            attackerStrength: strength,
            attackerName: band.resolve(.en),
            attackerLabel: band,
            // Deliberately no tribe: nobody is charged for this when it ends,
            // because nobody sent them. That is what makes outlaws different
            // from a war — there is no relationship to be worse afterwards.
            attackerTribeID: nil,
            fortification: s.stats.defense,
            tick: tick, registry: registry, seed: rng.next())
        s.journal.append(tick: tick, kind: .danger, text: LocalizedText(values: [
            .en: "\(band.resolve(.en)) are on the granary road. Nobody sent them.",
            .cs: "\(band.resolve(.cs)) jsou na cestě k sýpce. Nikdo je neposlal."]))
        return s
    }

    // MARK: - Why they come

    /// How much there is worth taking, as a multiple of the base odds.
    ///
    /// The stores, not the population: bandits are drawn by a full granary the
    /// way wolves are drawn by a herd. A colony that keeps its stores shallow
    /// is genuinely less worth robbing, which turns "should I build another
    /// granary" into a question with two sides.
    static func temptation(_ settlement: Settlement) -> Double {
        // The two stores a raider can carry off. Typed capacity means this is
        // now the roof over food and goods, not over political capital.
        let capacity = max(1, settlement.storageCapacity[.food]
                              + settlement.storageCapacity[.materials])
        let full = (settlement.storage[.food] + settlement.storage[.materials]) / capacity
        guard full > noticedAtShare else { return 0 }
        return min(wealthCeiling, (full - noticedAtShare) / (1 - noticedAtShare) * wealthCeiling)
    }

    /// How well watched the place is, 0…1 — how much of the odds a garrison
    /// takes away. A share, never a subtraction: a well-guarded colony should
    /// be a poor target, never an impossible one.
    static func watchfulness(_ settlement: Settlement, registry: GameDataRegistry) -> Double {
        let spears = Double(settlement.pawns.count { $0.assignedWork == .garrison })
        let people = Double(max(1, settlement.pawns.count))
        let perHundred = spears / people * 100
        let wall = max(0, settlement.stats.defense) / 120
        let watched = perHundred / (perHundred + garrisonHalfPoint)
        return min(0.85, watched * 0.7 + min(0.3, wall))
    }

    // MARK: - Who they are

    /// Bands are named for the age they are robbing in — a colony being held up
    /// by "deserters from the levy" is a different world from one meeting
    /// "wreckers off the rail line".
    static func name(era: Era, rng: inout SeededRNG) -> LocalizedText {
        let options: [LocalizedText]
        switch era {
        case .earlySettlement, .ancient:
            options = [
                LocalizedText(values: [.en: "Broken men", .cs: "Zlomení muži"]),
                LocalizedText(values: [.en: "Outcasts of the river road",
                                       .cs: "Vyvrhelové od říční cesty"]),
                LocalizedText(values: [.en: "A band with no people",
                                       .cs: "Banda bez kmene"]),
            ]
        case .medieval:
            options = [
                LocalizedText(values: [.en: "Deserters from somebody's levy",
                                       .cs: "Zběhové z něčí hotovosti"]),
                LocalizedText(values: [.en: "The forest company", .cs: "Lesní kumpanie"]),
                LocalizedText(values: [.en: "Brigands", .cs: "Lapkové"]),
            ]
        case .earlyIndustrial, .modern:
            options = [
                LocalizedText(values: [.en: "Wreckers off the line", .cs: "Trhači od trati"]),
                LocalizedText(values: [.en: "A hungry crew", .cs: "Hladová parta"]),
                LocalizedText(values: [.en: "Road agents", .cs: "Silniční agenti"]),
            ]
        case .nearFuture:
            options = [
                LocalizedText(values: [.en: "Scavengers", .cs: "Mrchožrouti"]),
                LocalizedText(values: [.en: "The unlisted", .cs: "Neevidovaní"]),
            ]
        }
        return options[Int(rng.nextUnit() * Double(options.count)) % options.count]
    }

    /// From the id's bytes, never `hashValue` — Swift seeds its hasher per
    /// process and a hash-derived seed replays differently on every launch.
    static func seed(mapSeed: UInt64, settlementID: UUID, tick: Int) -> UInt64 {
        var h = mapSeed &* 0xCBF2_9CE4_8422_2325
        let b = settlementID.uuid
        h ^= UInt64(b.8) << 56 | UInt64(b.9) << 48 | UInt64(b.10) << 40 | UInt64(b.11) << 32
            | UInt64(b.12) << 24 | UInt64(b.13) << 16 | UInt64(b.14) << 8 | UInt64(b.15)
        h = (h ^ UInt64(bitPattern: Int64(tick))) &* 0x9E37_79B9_7F4A_7C15
        return (h ^ (h >> 31)) | 1
    }
}
