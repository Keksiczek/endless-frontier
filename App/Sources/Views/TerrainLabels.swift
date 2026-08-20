import Foundation
import EndlessFrontierCore

/// Player-facing names for what stands in the landscape — shared by the
/// settlement canvas, the survey view and the zoom labels, so "co je co" has
/// one answer everywhere.
extension LocalResourceKind {
    var displayLabel: String {
        let cs = AppStrings.language == .cs
        switch self {
        case .field: return cs ? "Úrodná půda" : "Fertile ground"
        case .forest: return cs ? "Les" : "Forest"
        case .stone: return cs ? "Ložisko kamene" : "Stone deposit"
        case .herbs: return cs ? "Byliny" : "Herbs"
        case .ironOre: return cs ? "Žíla železné rudy" : "Iron seam"
        case .clay: return cs ? "Jílovna" : "Clay pit"
        case .coal: return cs ? "Uhelná sloj" : "Coal seam"
        case .oilSeep: return cs ? "Ropný vývěr" : "Oil seep"
        }
    }
}

extension LocalPOIKind {
    var displayLabel: String {
        let cs = AppStrings.language == .cs
        switch self {
        case .ruins: return cs ? "Prastaré zříceniny" : "Ancient ruins"
        case .cave: return cs ? "Hluboká jeskyně" : "A deep cave"
        case .spring: return cs ? "Léčivý pramen" : "A healing spring"
        case .treasure: return cs ? "Zakopaná skrýš" : "A buried cache"
        case .shrine: return cs ? "Zapomenutá svatyně" : "A forgotten shrine"
        case .wreck: return cs ? "Vrak karavany" : "A wrecked caravan"
        case .orchard: return cs ? "Zplanělý sad" : "A wild orchard"
        case .hermit: return cs ? "Poustevna" : "A hermit's hut"
        case .watchtower: return cs ? "Strážní věž" : "A ruined watchtower"
        case .saltPan: return cs ? "Solisko" : "A salt pan"
        case .barrow: return cs ? "Mohyla" : "A burial mound"
        case .starfall: return cs ? "Spadlá hvězda" : "A fallen star"
        }
    }
}
