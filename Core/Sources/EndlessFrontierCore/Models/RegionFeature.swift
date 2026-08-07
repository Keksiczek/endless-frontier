import Foundation

/// What the land at a hex actually *is* — the thing that makes it a place
/// rather than a tile of the right colour.
///
/// Keks: *"ty biomy nebo mapy by mohly samy o sobě být POI — kráterové jezero,
/// průsmyk, třeba atd; celkově to nějak poskládat, aby mapa světa dávala větší
/// smysl."* A region that is only ever "forest" is a colour with a hazard
/// number; a region that is **the pass** is somewhere you remember, and
/// somewhere that has a reason to be where it is.
///
/// Every one of these is **read off the ground**, not rolled: `MapGenerator`
/// already samples how high, how wet and how warm each hex is, so a saddle
/// between two ranges, a wet hollow ringed by higher ground, or a green hex in
/// a dry country are all shapes the fields already describe. That is the whole
/// design — Keks again: *"vše budou jen věci v simulaci, která bude mít nějaké
/// podmínky, takže by to nemělo být tak hard."* Nothing is authored per hex,
/// and a feature can never contradict the country around it, because it *is*
/// the country around it.
///
/// The region keeps its own forged name as well (`Region.name`), so two crater
/// lakes are still two distinct places — the no-collision naming this map has
/// always had is untouched.
public enum RegionFeature: String, Codable, Sendable, CaseIterable {
    /// A dip through high country — the way through a range.
    case pass
    /// A wet hollow with higher ground all round it.
    case craterLake = "crater_lake"
    /// Green in the middle of a dry country.
    case oasis
    /// High ground that goes on flat.
    case plateau
    /// A hex the land falls away from on both sides.
    case gorge
    /// Standing water and reeds, low and soaked.
    case fen
    /// A peak that stands above everything near it.
    case peak
    /// Land reaching out into the low ground.
    case headland

    public var displayName: LocalizedText {
        switch self {
        case .pass:       return LocalizedText(values: [.en: "The Pass", .cs: "Průsmyk"])
        case .craterLake: return LocalizedText(values: [.en: "Crater Lake", .cs: "Kráterové jezero"])
        case .oasis:      return LocalizedText(values: [.en: "The Oasis", .cs: "Oáza"])
        case .plateau:    return LocalizedText(values: [.en: "The Plateau", .cs: "Náhorní plošina"])
        case .gorge:      return LocalizedText(values: [.en: "The Gorge", .cs: "Rokle"])
        case .fen:        return LocalizedText(values: [.en: "The Fen", .cs: "Slatina"])
        case .peak:       return LocalizedText(values: [.en: "The Peak", .cs: "Štít"])
        case .headland:   return LocalizedText(values: [.en: "The Headland", .cs: "Ostroh"])
        }
    }

    /// A line about what being *here* means, which is what turns a label into a
    /// reason to care where you settle.
    public var note: LocalizedText {
        switch self {
        case .pass:
            return LocalizedText(values: [
                .en: "Everything that crosses the range crosses here.",
                .cs: "Všechno, co přechází hory, přechází tudy."])
        case .craterLake:
            return LocalizedText(values: [
                .en: "Water with a wall around it.",
                .cs: "Voda a kolem dokola stěna."])
        case .oasis:
            return LocalizedText(values: [
                .en: "Green, with a great deal of nothing around it.",
                .cs: "Zeleň a kolem ní spousta ničeho."])
        case .plateau:
            return LocalizedText(values: [
                .en: "High, level, and you can see anyone coming.",
                .cs: "Vysoko, rovina — a je vidět každého, kdo jde."])
        case .gorge:
            return LocalizedText(values: [
                .en: "The ground opens. Getting across is the day's work.",
                .cs: "Země se otevírá. Dostat se přes ni je práce na celý den."])
        case .fen:
            return LocalizedText(values: [
                .en: "Standing water, reeds, and bad footing.",
                .cs: "Stojatá voda, rákosí a mizerná půda pod nohama."])
        case .peak:
            return LocalizedText(values: [
                .en: "It stands over everything for a long way.",
                .cs: "Ční nad vším široko daleko."])
        case .headland:
            return LocalizedText(values: [
                .en: "Land running out into the low country.",
                .cs: "Země vybíhající do nížiny."])
        }
    }
}
