import Foundation
import EndlessFrontierCore

/// Lightweight bilingual (Czech + English) UI strings for the V2 shell.
///
/// A deliberate stop-gap: it mirrors `LocalizedText`'s en/cs shape and picks by
/// the device locale, so it can be swapped for a String Catalog later without
/// touching call sites. Content translation (events, buildings…) lands in a
/// later phase; this covers the new living-world chrome.
enum AppStrings {
    static var language: GameLanguage { GameLanguage.matching(.current) }

    private static func s(_ en: String, _ cs: String) -> String {
        language == .cs ? cs : en
    }

    // Tabs
    static var tabSettlement: String { s("Settlement", "Osada") }
    static var tabWorld: String { s("World", "Svět") }
    static var tabCouncil: String { s("Council", "Sněm") }
    static var tabChronicle: String { s("Chronicle", "Kronika") }
    static var tabScience: String { s("Science", "Věda") }

    // Living world
    static var year: String { s("Year", "Rok") }
    static var tension: String { s("Tension", "Napětí") }
    static var colonists: String { s("Colonists", "Obyvatelé") }
    static var details: String { s("Details", "Detaily") }
    static var newColony: String { s("New world", "Nový svět") }

    // Settings
    static var settings: String { s("Settings", "Nastavení") }
    static var done: String { s("Done", "Hotovo") }
    static var cancel: String { s("Cancel", "Zrušit") }
    static var startNewGame: String { s("Start a new world", "Založit nový svět") }
    static var startNewGameBlurb: String {
        s("Abandons this world and founds another under a fresh sky. What has happened here cannot be recovered.",
          "Opustíš tento svět a založíš jiný pod novou oblohou. Co se tu stalo, už nepůjde vrátit.")
    }
    static var startNewGameConfirm: String { s("Abandon this world", "Opustit tento svět") }
    static var about: String { s("About", "O hře") }

    static func seasonName(_ season: Season) -> String {
        switch season {
        case .spring: return s("Spring", "Jaro")
        case .summer: return s("Summer", "Léto")
        case .autumn: return s("Autumn", "Podzim")
        case .winter: return s("Winter", "Zima")
        }
    }

    static func roleName(_ work: WorkKind) -> String {
        switch work {
        case .farming:  return s("Farmer", "Zemědělec")
        case .logging:  return s("Woodcutter", "Dřevorubec")
        case .mining:   return s("Miner", "Horník")
        case .foraging: return s("Forager", "Bylinkář")
        case .hunting:  return s("Hunter", "Lovec")
        case .research: return s("Scholar", "Učenec")
        case .healing:  return s("Healer", "Léčitel")
        case .trade:    return s("Trader", "Obchodník")
        case .priest:   return s("Priest", "Kněz")
        case .building: return s("Builder", "Stavitel")
        case .scouting: return s("Scout", "Zvěd")
        case .idle:     return s("Idle", "Bez práce")
        }
    }

    /// Wealth-class label for a colonist's standing.
    static func wealthClassName(_ cls: WealthClass) -> String {
        switch cls {
        case .poor:    return s("Poor", "Chudina")
        case .middle:  return s("Middle", "Střední vrstva")
        case .wealthy: return s("Wealthy", "Zámožní")
        }
    }

    // Era, capitalised words from the raw enum.
    static func eraTitle(_ era: Era) -> String {
        let en = era.rawValue.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
        guard language == .cs else { return en }
        switch era {
        case .earlySettlement: return "Raná osada"
        case .ancient:         return "Starověk"
        case .medieval:        return "Středověk"
        case .earlyIndustrial: return "Raná industrializace"
        case .modern:          return "Moderní doba"
        case .nearFuture:      return "Blízká budoucnost"
        }
    }
}
