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

    /// **The base odds per check.** Everything else multiplies it.
    ///
    /// Measured 2026-08-25 over two centuries: eight raids from the camps
    /// against thirty-three from peoples and forty-three from the wild — a
    /// place on the map with strength that grows and loot that fattens it
    /// visited a colony **once every twenty-one years**. Doubled, with the
    /// ceiling on `temptation` lifted below, which together bring a rich,
    /// poorly watched colony to a raid every four or five years and leave a
    /// well-guarded one at one every twenty (`DangerProbe.raidCadence`).
    ///
    /// **Left where it was**, in the end. The measurement named a saturated
    /// multiplier, not a small chance, and the two want opposite fixes — doubling
    /// this as well would have been two changes against one measurement
    /// (rule 72), and it is the ceiling below that was doing the damage.
    static let baseChance = 0.010
    /// A colony smaller than this is not worth the walk.
    static let minimumPopulation = 12
    /// How full the stores have to be before anybody notices.
    static let noticedAtShare = 0.35
    /// **What is worth the walk, in sacks rather than in shelf-space.**
    ///
    /// The share of capacity was the only measure of a colony's wealth, and a
    /// share of a capacity is a measure of the colony's *buildings*: measured
    /// over two centuries, a colony sitting on **6 280 food** had granaries
    /// for 44 300, so it read as 14 % full and no outlaw ever noticed it —
    /// **one raid from a camp in two hundred years**, and the raids the player
    /// did see were tribes and wolves. A warband does not count your shelves.
    /// Below this a colony genuinely has nothing worth carrying home.
    static let worthTheWalk = 400.0
    /// …and how much *above* that doubles the interest.
    ///
    /// Widening this was tried and reverted: it is calibrated against the small
    /// full shed — nine hundred sacks behind a thousand of shelf — and a wider
    /// divisor quietly told the outlaws to ignore a hamlet's whole winter
    /// store. The number that was wrong is the ceiling below.
    static let hardToRefuse = 800.0
    /// The most the *fullness* reading may multiply the odds by.
    ///
    /// **Kept for the share, dropped for the haul**, and the difference is the
    /// whole fix. `share` asks "how full is it for its size", which is a ratio
    /// and wants a ceiling. `haul` asks "how much is actually in there", which
    /// is the thing that grows all game — and capping it at three meant a
    /// colony was maximally tempting from about two thousand sacks onward.
    /// Measured: temptation sat at 3.000 at the tenth percentile, the fiftieth
    /// and the ninetieth, over two hundred years. A threat that does not scale
    /// with what it threatens is scenery (rule 12), and a number that reads the
    /// same at every percentile is not measuring anything (rule 54).
    ///
    /// The haul is bounded where it belongs instead — at the odds, which are
    /// capped per check in `OutlawCampEngine.advanceOneTick`, so a fabulously
    /// rich colony is raided often and never continuously.
    static let wealthCeiling = 3.0
    /// A watched colony is a colony they go around: at this many spears per
    /// hundred people, the odds are roughly halved.
    static let garrisonHalfPoint = 6.0
    /// What a band is worth, per point of the grain that drew it.
    static let strengthPerShare = 26.0
    /// …and never less than this, or a band arrives that a shepherd sees off.
    static let minimumStrength = 14.0

    /// **The old path: a band out of nowhere.**
    ///
    /// Kept, and kept *only* as the fallback. `OutlawCampEngine` owns raids
    /// now, because a raid should come from a place — but a world with no
    /// camps left in it (an old save, or a country whose camps have all been
    /// burned out) must still not be free to rob.
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
        return raid(s, registry: registry, tick: tick, era: era, lure: lure, rng: &rng)
    }

    /// The warband itself, once something has decided they are coming.
    ///
    /// Split out so `OutlawCampEngine` can fall back to it without repeating
    /// the roll: whether they come is one question and who they are is
    /// another, and conflating the two is how the band's *size* ended up
    /// read off the granary.
    static func raid(
        _ settlement: Settlement, registry: GameDataRegistry, tick: Int,
        era: Era, lure: Double, rng: inout SeededRNG
    ) -> Settlement {
        var s = settlement
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
        let stores = settlement.storage[.food] + settlement.storage[.materials]
        // **Two readings, and the louder one wins.**
        //
        // *Full for its size* is the question a village asks — a hamlet with
        // its one shed brimming is worth robbing. *How much is actually in
        // there* is the question a town asks, and it is the one the old
        // formula could not ask at all, because building another warehouse
        // made the same grain read as less of it.
        let full = stores / capacity
        let share = full > noticedAtShare
            ? min(wealthCeiling, (full - noticedAtShare) / (1 - noticedAtShare) * wealthCeiling)
            : 0
        let haul = max(0, (stores - worthTheWalk) / hardToRefuse)
        return max(share, haul)
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
