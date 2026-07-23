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
        }
    }
}
