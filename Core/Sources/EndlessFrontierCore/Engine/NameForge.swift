import Foundation

/// Builds names — of colonists, settlements, tribes and places — in the
/// world's own language. A world is created Czech or English (see
/// `WorldState.language`) and everything *generated* from then on speaks it:
/// newborns, outposts, seceded peoples, freshly charted regions.
///
/// Names are built from syllable/morpheme pools, never picked off a short
/// list, so a chronicle spanning centuries doesn't repeat itself. Everything
/// is deterministic: the same rng state yields the same name.
public enum NameForge {
    // MARK: - Colonists

    /// Czech-flavoured syllables — the voice this game grew out of.
    static let csFirstSyllables = [
        "Bo", "Ra", "Mi", "Ve", "Da", "Ka", "Ly", "No",
        "Ta", "Zi", "Ja", "Ol", "Bře", "Sva", "Mla"
    ]
    static let csLastSyllables = [
        "ren", "mil", "slav", "na", "rek", "va", "dan", "mír",
        "ta", "goj", "run", "děj", "ša", "na", "dor"
    ]

    /// Old-English-flavoured syllables for an English world: Aldric, Eawyn,
    /// Wulfred, Hildgar — names that sound like they were carved somewhere.
    static let enFirstSyllables = [
        "Al", "Ed", "Ro", "Wil", "Har", "God", "Os", "Ael",
        "Bri", "Dun", "Ea", "Hild", "Leo", "Wulf", "Cen"
    ]
    static let enLastSyllables = [
        "ric", "win", "mund", "gar", "fred", "ith", "red", "stan",
        "wald", "helm", "ward", "er", "a", "wyn", "noth"
    ]

    /// How often a name takes a third syllable.
    static let longNameChance = 0.25

    /// A colonist's name in the world's language.
    public static func colonistName(language: GameLanguage, using rng: inout SeededRNG) -> String {
        let firsts = language == .cs ? csFirstSyllables : enFirstSyllables
        let lasts = language == .cs ? csLastSyllables : enLastSyllables
        let first = firsts[Int(rng.next() % UInt64(firsts.count))]
        let last = lasts[Int(rng.next() % UInt64(lasts.count))]
        guard rng.nextUnit() < longNameChance else { return first + last }
        let middle = firsts[Int(rng.next() % UInt64(firsts.count))]
        return first + middle.lowercased() + last
    }

    // MARK: - Settlements

    static let csSettlementStems = [
        "Kamen", "Jelen", "Popel", "Dub", "Vrb", "Havran", "Bystř",
        "Sokol", "Bor", "Jasan", "Medvěd", "Stříbr", "Hloh", "Blat", "Světl"
    ]
    static let csSettlementSuffixes = [
        "ov", "ín", "ová", "iště", "any", "ovice", "ovka", "ůvky", "no", "ovec"
    ]
    static let enSettlementStems = [
        "Stone", "Deer", "Ash", "Oak", "Willow", "Raven", "Brook",
        "Falcon", "Pine", "Elm", "Bear", "Silver", "Thorn", "Marsh", "Bright"
    ]
    static let enSettlementSuffixes = [
        "ford", "stead", "hollow", "field", "haven", "gate", "worth", "croft", "wick", "mead"
    ]

    /// A settlement's name — used for founded outposts, so every new hearth
    /// has a real name instead of "Outpost 3".
    public static func settlementName(language: GameLanguage, using rng: inout SeededRNG) -> String {
        let stems = language == .cs ? csSettlementStems : enSettlementStems
        let suffixes = language == .cs ? csSettlementSuffixes : enSettlementSuffixes
        let stem = stems[Int(rng.next() % UInt64(stems.count))]
        let suffix = suffixes[Int(rng.next() % UInt64(suffixes.count))]
        return stem + suffix
    }

    /// The first settlement's name.
    public static func capitalName(language: GameLanguage) -> String {
        language == .cs ? "První světlo" : "First Light"
    }

    // MARK: - Tribes

    /// The name a seceding people takes from the colonist who led them out.
    public static func tribeName(founder: String, language: GameLanguage) -> String {
        language == .cs ? "\(founder)ův lid" : "\(founder)'s Folk"
    }

    // MARK: - Regions

    // Same pool sizes in both languages (25 × 20 × 10), so the bijection that
    // guarantees no two hexes share a name holds identically for either.
    static let csRegionStems = [
        "Mlh", "Šer", "Bouř", "Popel", "Sol", "Vys", "Čern", "Mraz",
        "Trn", "Želez", "Bled", "Rud", "Větr", "Vran", "Bahn", "Studen",
        "Blat", "Havran", "Hloh", "Jestřáb", "Kamen", "Jelen", "Vlč", "Sychr", "Tich"
    ]
    static let csRegionSuffixes = [
        "ov", "ova", "ín", "ava", "iště", "ovice", "any", "ovka", "enec", "in",
        "aň", "oves", "olín", "ůvka", "atín", "ovsko", "ovna", "ice", "áň", "ovec"
    ]
    static let csRegionEpithets = [
        "", "Horní ", "Dolní ", "Přední ", "Zadní ",
        "Severní ", "Jižní ", "Západní ", "Východní ", "Poslední "
    ]

    static let enRegionStems = [
        "Dusk", "Grey", "Storm", "Ash", "Salt", "High", "Black", "Cold",
        "Ember", "Mist", "Thorn", "Iron", "Pale", "Red", "Wind", "Hag",
        "Bracken", "Lorn", "Mire", "Cald", "Fen", "Bram", "Sunder", "Rook", "Hollow"
    ]
    static let enRegionSuffixes = [
        "water", "watch", "fall", "mere", "moor", "vale", "flats", "spring",
        "hills", "fen", "march", "crag", "wood", "hollow", "stone", "fell",
        "marsh", "reach", "grave", "barrow"
    ]
    static let enRegionEpithets = [
        "", "Upper ", "Lower ", "Far ", "Old ", "New ", "Little ", "Great ",
        "Outer ", "Deep "
    ]

    /// A region name for a bijection index (see `MapGenerator.name`). The
    /// index space must be `regionNameSpace` for the no-collision guarantee.
    public static let regionNameSpace = 25 * 20 * 10

    public static func regionName(index: Int, language: GameLanguage) -> String {
        let stems = language == .cs ? csRegionStems : enRegionStems
        let suffixes = language == .cs ? csRegionSuffixes : enRegionSuffixes
        let epithets = language == .cs ? csRegionEpithets : enRegionEpithets
        let stem = stems[index % stems.count]
        let suffix = suffixes[(index / stems.count) % suffixes.count]
        let epithet = epithets[(index / (stems.count * suffixes.count)) % epithets.count]
        return epithet + stem + suffix
    }

    /// The homeland's display name.
    public static func homelandName(language: GameLanguage) -> String {
        language == .cs ? "Domovina" : "Homeland"
    }
}
