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
    //
    // **Why this is not one pattern with three word banks.**
    //
    // It was, and Keks, looking at his phone: *"názvy map jsou skoro stejné,
    // nudné, v okolí mám to samé."* Two faults compounded:
    //
    // 1. **Every name had the same shape.** *Epithet + stem + suffix*, always,
    //    so a hundred hexes of Duskwood, Brackenwood, Haghollow read as one
    //    name with the middle swapped. Rhythm is most of what makes a list of
    //    names feel like a list of *places*, and there was only ever one.
    // 2. **Neighbours shared their parts.** The name index was `hexIndex +
    //    seed`, and `hexIndex` walks in small steps, so the epithet — which
    //    changes once every `stems × suffixes` indices — was the *same word*
    //    across a whole quarter of the map. Hence "Far" on everything in
    //    reach. Scrambling the index by a unit modulo the space keeps the
    //    mapping a bijection (so no two hexes can collide) while putting
    //    neighbouring hexes in completely different parts of it.
    //
    // The pools are the same size in both languages, so the bijection holds
    // identically for either.

    /// How many *shapes* a name can take. Not a word bank: a shape is the
    /// grammar of the name, which is what stops a map reading as one word with
    /// the middle swapped.
    public static let regionShapes = 4
    /// Words in the first slot (a stem in English, an adjective in Czech).
    public static let regionFirsts = 32
    /// Words in the second slot (a suffix in English, a noun in Czech).
    public static let regionSeconds = 32

    static let csRegionStems = [
        "Mlh", "Šer", "Bouř", "Popel", "Sol", "Vys", "Čern", "Mraz",
        "Trn", "Želez", "Bled", "Rud", "Větr", "Vran", "Bahn", "Studen",
        "Blat", "Havran", "Hloh", "Jestřáb", "Kamen", "Jelen", "Vlč", "Sychr",
        "Tich", "Bor", "Lip", "Skal", "Bystr", "Osik", "Kalu", "Doub"
    ]
    static let csRegionSuffixes = [
        "ov", "ova", "ín", "ava", "iště", "ovice", "any", "ovka",
        "enec", "in", "aň", "oves", "olín", "ůvka", "atín", "ovsko",
        "ovna", "ice", "áň", "ovec", "ovany", "ovišť", "ná", "ovín",
        "íkov", "ánky", "ůvky", "árna", "ovsk", "ovy", "ěnice", "ohrad"
    ]
    /// Czech adjectives that do **not** inflect for gender — the soft `-í`
    /// forms — so a generated pair can never be ungrammatical whichever noun
    /// it lands on. This is the whole reason the Czech bank is what it is:
    /// "Vlčí důl", "Vlčí skála" and "Vlčí sedlo" are all correct.
    static let csRegionAdjectives = [
        "Vlčí", "Havraní", "Jelení", "Soví", "Liščí", "Medvědí", "Rysí", "Zaječí",
        "Krkavčí", "Jestřábí", "Kozí", "Ovčí", "Rybí", "Bažantí", "Býčí", "Psí",
        "Volčí", "Sokolí", "Hadí", "Bobří", "Kančí", "Losí", "Vydří", "Jezevčí",
        "Kuní", "Tetřeví", "Čapí", "Vraní", "Netopýří", "Žabí", "Srnčí", "Kobylí"
    ]
    static let csRegionNouns = [
        "důl", "skála", "sedlo", "brod", "mokřad", "stráň", "úval", "hvozd",
        "pláň", "rokle", "jezero", "vrch", "slať", "les", "potok", "svah",
        "louka", "sráz", "průsmyk", "tůň", "bažina", "hřeben", "kotlina", "step",
        "písčina", "úbočí", "paseka", "haluz", "výspa", "mez", "žleb", "ostroh"
    ]
    /// **Only the invariant `-í` forms.** A generated epithet has to sit in
    /// front of a noun whose gender it never sees, and "Malé Tichovka" or
    /// "Nové losí sráz" is what happens when it tries: *Tichovka* is feminine
    /// and *sráz* masculine, and the generator has no way to know. Soft
    /// adjectives are the same word for all three genders, so every pairing
    /// the space can produce is grammatical Czech.
    static let csRegionEpithets = [
        "Horní ", "Dolní ", "Přední ", "Zadní ", "Severní ", "Jižní ",
        "Západní ", "Východní ", "Poslední ", "Prostřední ", "Vnější ", "Vnitřní "
    ]

    static let enRegionStems = [
        "Dusk", "Grey", "Storm", "Ash", "Salt", "High", "Black", "Cold",
        "Ember", "Mist", "Thorn", "Iron", "Pale", "Red", "Wind", "Hag",
        "Bracken", "Lorn", "Mire", "Cald", "Fen", "Bram", "Sunder", "Rook",
        "Hollow", "Elder", "Frost", "Glass", "Harrow", "Quill", "Marrow", "Whin"
    ]
    static let enRegionSuffixes = [
        "water", "watch", "fall", "mere", "moor", "vale", "flats", "spring",
        "hills", "fen", "march", "crag", "wood", "hollow", "stone", "fell",
        "marsh", "reach", "grave", "barrow", "ridge", "dell", "holt", "combe",
        "garth", "wick", "beck", "tarn", "scar", "ness", "shaw", "thwaite"
    ]
    /// The same second element as a word of its own, for the shapes that space
    /// the name out. Kept apart from the suffixes because a compound ending is
    /// not always a noun you can stand on its own ("‑wick", "‑thwaite").
    static let enRegionNouns = [
        "Water", "Watch", "Falls", "Mere", "Moor", "Vale", "Flats", "Spring",
        "Hills", "Fen", "March", "Crag", "Wood", "Hollow", "Stone", "Fell",
        "Marsh", "Reach", "Grave", "Barrow", "Ridge", "Dell", "Holt", "Combe",
        "Garth", "Green", "Beck", "Tarn", "Scar", "Ness", "Shaw", "Moss"
    ]
    /// English needs the adjective slot too, so both languages decompose the
    /// index the same way.
    static let enRegionAdjectives = [
        "Wolf", "Raven", "Hart", "Owl", "Fox", "Bear", "Lynx", "Hare",
        "Crow", "Hawk", "Goat", "Sheep", "Fish", "Heron", "Bull", "Hound",
        "Kite", "Falcon", "Adder", "Beaver", "Boar", "Elk", "Otter", "Badger",
        "Marten", "Grouse", "Stork", "Rook", "Bat", "Toad", "Roe", "Mare"
    ]
    static let enRegionEpithets = [
        "Upper ", "Lower ", "Far ", "Old ", "New ", "Little ",
        "Great ", "Outer ", "Deep ", "Nether ", "Broad ", "Long "
    ]

    /// A region name for a bijection index (see `MapGenerator.name`). The
    /// index space must be `regionNameSpace` for the no-collision guarantee.
    public static let regionNameSpace = regionShapes * regionFirsts * regionSeconds

    /// A unit modulo `regionNameSpace` — coprime with it, so multiplying by it
    /// permutes the space without ever mapping two indices onto one. Its job
    /// is to make **adjacent hexes land far apart**: the map's own index walks
    /// in ones, and every part of a name is a digit of it.
    static let regionScatter = 1_733

    public static func regionName(index: Int, language: GameLanguage) -> String {
        let space = regionNameSpace
        let scattered = (index % space) &* regionScatter % space
        let first = scattered % regionFirsts
        let second = (scattered / regionFirsts) % regionSeconds
        let shape = (scattered / (regionFirsts * regionSeconds)) % regionShapes
        // Derived from the pair rather than being a digit of its own: the name
        // is already unique without it, and giving it a digit would have made
        // the space four times bigger for four times less variety per hex.
        let epithets = language == .cs ? csRegionEpithets : enRegionEpithets
        let epithet = epithets[(first &+ second &* 5) % epithets.count]

        switch language {
        case .cs:
            let stem = csRegionStems[first], suffix = csRegionSuffixes[second]
            let adjective = csRegionAdjectives[first], noun = csRegionNouns[second]
            switch shape {
            case 0: return stem + suffix                        // Mlhovice
            case 1: return epithet + stem + suffix              // Horní Mlhovice
            case 2: return "\(adjective) \(noun)"               // Vlčí důl
            // "Horní Vlčí důl": the epithet, then the name proper. Czech
            // capitalises the first word of a place and the proper part of it,
            // and lowercasing the adjective here read as a description rather
            // than a name.
            default: return "\(epithet)\(adjective) \(noun)"
            }
        case .en:
            let stem = enRegionStems[first], suffix = enRegionSuffixes[second]
            let adjective = enRegionAdjectives[first], noun = enRegionNouns[second]
            switch shape {
            case 0: return stem + suffix                        // Duskwood
            case 1: return epithet + stem + suffix              // Far Duskwood
            case 2: return "\(adjective) \(noun)"               // Wolf Crag
            default: return "\(epithet)\(adjective) \(noun)"    // Old Wolf Crag
            }
        }
    }

    /// The homeland's display name.
    public static func homelandName(language: GameLanguage) -> String {
        language == .cs ? "Domovina" : "Homeland"
    }
}
