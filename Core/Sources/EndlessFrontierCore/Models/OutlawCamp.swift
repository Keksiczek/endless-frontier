import Foundation

/// **A raid with somewhere to come from.**
///
/// Keks: *"k banditům napiš, aby byli víc různorodí — třeba chodili ze
/// základen na mapě, co nejsou žádná frakce."*
///
/// `BanditEngine` conjured a warband out of nothing, sized off how full your
/// granary was, named it off a per-era list and forgot it existed the moment
/// the fighting stopped. Nothing about the raid existed before it arrived or
/// after it left, which is why a raid was an interruption rather than an
/// event: **there was nobody to have a war with.**
///
/// A camp is a place. It sits on a hex, it has a strength of its own that
/// grows while nobody troubles it, it keeps what it takes — and a colony can
/// go and burn it out and get that back. That is the loop the old bandits had
/// no half of.
///
/// **And it is deliberately not a `Tribe`.** No standing, no grudge, no
/// marriage alliance, nothing to negotiate. The moment a camp can be bought
/// off for good it is a neighbour with a worse hat, and the one thing that
/// made outlaws worth having — that you cannot make peace with them — is gone.
public struct OutlawCamp: Codable, Sendable, Identifiable, Equatable {

    /// **What kind of people they are**, which is the whole of their variety.
    ///
    /// Not a name list: a name is a label on the same warband. What a camp
    /// *is* decides how many of them come, what they carry, how fast they
    /// recover from a beating and what it costs to walk in and clear them out.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// Soldiers who walked away from somebody's levy. Few, and they fight
        /// with the arms of the age they deserted from — a step ahead of what
        /// a village has.
        case deserters
        /// People the country pushed out. Many, hungry, badly armed; they come
        /// for the granary rather than for a fight, and they come back.
        case starving
        /// A robbers' hold: a fence, a lookout and a season's plunder behind
        /// it. Neither the biggest nor the best armed, and the hardest to be
        /// rid of.
        case hold

        /// How the age they fight in reads for *their* weapons, in eras of
        /// shift. `SiegeEngine.raiderArms` already turns an era into a
        /// projectile, a range and a calibre — a camp only has to say which
        /// age it is armed out of.
        public var armsShift: Int {
            switch self {
            case .deserters: return 1
            case .starving: return -1
            case .hold: return 0
            }
        }

        /// How many bodies the same strength is drawn as, against the ordinary
        /// reckoning. A starving band is a crowd of people who cannot fight; a
        /// handful of deserters is worth watching.
        public var bodyShare: Double {
            switch self {
            case .deserters: return 0.7
            case .starving: return 1.6
            case .hold: return 1
            }
        }

        /// What a colony's party has to get past to burn them out. Only the
        /// hold has built anything.
        public var walls: Double {
            switch self {
            case .deserters: return 6
            case .starving: return 0
            case .hold: return 22
            }
        }

        /// What they gather to themselves in a year nobody troubles them.
        ///
        /// Read as a **rate against the colony's own growth**, not as a number
        /// on its own (rule 34): a colony adds people every year, so a camp
        /// that does not grow is a camp that is irrelevant by year forty.
        public var growthPerYear: Double {
            switch self {
            case .deserters: return 1.6
            case .starving: return 3.2
            case .hold: return 2.4
            }
        }

        /// What a camp of this kind is worth the day it is found.
        public var foundingStrength: Double {
            switch self {
            case .deserters: return 26
            case .starving: return 20
            case .hold: return 30
            }
        }

        public var label: LocalizedText {
            switch self {
            case .deserters: return LocalizedText(values: [
                .en: "Deserters", .cs: "Zběhové"])
            case .starving: return LocalizedText(values: [
                .en: "A starving band", .cs: "Hladová banda"])
            case .hold: return LocalizedText(values: [
                .en: "A robbers' hold", .cs: "Lupičské hnízdo"])
            }
        }

        /// What the camp looks like from the ridge above it, said once.
        public var blurb: LocalizedText {
            switch self {
            case .deserters: return LocalizedText(values: [
                .en: "Soldiers who walked away from somebody's war, and kept the arms.",
                .cs: "Vojáci, co odešli z něčí války — a zbraně si nechali."])
            case .starving: return LocalizedText(values: [
                .en: "More of them than you expected, and not one of them fed.",
                .cs: "Je jich víc, než bys čekal, a najedený není ani jeden."])
            case .hold: return LocalizedText(values: [
                .en: "A fence, a lookout, and a season's plunder behind both.",
                .cs: "Palisáda, hlídka a za nimi kořist za celou sezónu."])
            }
        }
    }

    public let id: UUID
    /// The hex they live on. Not a settlement and not a tribe's home — a place
    /// on the map with people in it who belong to nobody.
    public let regionID: UUID
    public var kind: Kind
    public var name: LocalizedText
    /// **Their own strength**, grown over time.
    ///
    /// The old band was sized off `temptation` — how full your stores were —
    /// which is why a band of four attacked a colony of sixty-eight and was
    /// over in six seconds. The stores decide whether they *bother coming*;
    /// what arrives is the camp.
    public var strength: Double
    public let foundedTick: Int
    /// When they last came down the road. Raids cost a camp its strength, so
    /// a camp that has just been out is a camp worth ignoring for a while.
    public var lastRaidTick: Int?
    /// What they have carried off. A colony that burns them out gets it back —
    /// which is what turns "a raid happened" into "a raid happened, and we
    /// know where they went".
    public var loot: Resources
    /// Beaten, and lying low until this tick. Not destroyed: a camp that is
    /// left alone fills up again, and a country with no outlaws left in it is
    /// a country with nothing to do in it.
    public var brokenUntil: Int?

    public init(
        id: UUID,
        regionID: UUID,
        kind: Kind,
        name: LocalizedText,
        strength: Double,
        foundedTick: Int = 0,
        lastRaidTick: Int? = nil,
        loot: Resources = Resources(),
        brokenUntil: Int? = nil
    ) {
        self.id = id
        self.regionID = regionID
        self.kind = kind
        self.name = name
        self.strength = strength
        self.foundedTick = foundedTick
        self.lastRaidTick = lastRaidTick
        self.loot = loot
        self.brokenUntil = brokenUntil
    }

    /// Whether anybody is home. A broken camp is still on the map — that is
    /// the point of it — but it neither raids nor grows while it is lying low.
    public func isActive(at tick: Int) -> Bool {
        guard let until = brokenUntil else { return true }
        return tick >= until
    }

    /// The age their weapons come out of, given the age the world is in.
    public func armsEra(in era: Era) -> Era {
        let all = Era.allCases
        guard let index = all.firstIndex(of: era) else { return era }
        let shifted = min(all.count - 1, max(0, index + kind.armsShift))
        return all[shifted]
    }

    /// How many of them are drawn on the field for the strength they bring.
    public func drawn(for strength: Double) -> Int {
        let ordinary = Double(BattleResolver.drawnStrength(strength))
        return min(14, max(1, Int((ordinary * kind.bodyShare).rounded())))
    }
}
