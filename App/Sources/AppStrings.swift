import Foundation
import EndlessFrontierCore

/// Lightweight bilingual (Czech + English) UI strings for the V2 shell.
///
/// A deliberate stop-gap: it mirrors `LocalizedText`'s en/cs shape and picks by
/// the device locale, so it can be swapped for a String Catalog later without
/// touching call sites. Content translation (events, buildings…) lands in a
/// later phase; this covers the new living-world chrome.
enum AppStrings {
    /// The player's explicit choice of language, if they've made one.
    ///
    /// The game ships bilingual but picked purely by device locale, so a Czech
    /// player on an English phone got an English world and no way to say
    /// otherwise — the translated content was there and unreachable.
    static let overrideKey = "settings.language"

    static var language: GameLanguage {
        if let raw = UserDefaults.standard.string(forKey: overrideKey),
           let chosen = GameLanguage(rawValue: raw) {
            return chosen
        }
        return GameLanguage.matching(.current)
    }

    /// `nil` means "follow the device".
    static var languageOverride: GameLanguage? {
        get {
            UserDefaults.standard.string(forKey: overrideKey).flatMap(GameLanguage.init(rawValue:))
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: overrideKey)
            } else {
                UserDefaults.standard.removeObject(forKey: overrideKey)
            }
        }
    }

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
    static var layout: String { s("Layout", "Plán osady") }
    static var newColony: String { s("New world", "Nový svět") }

    // Diplomacy — what the Leader's standing buys
    static var sendGift: String { s("Send a gift", "Poslat dar") }
    static var demandTribute: String { s("Demand tribute", "Žádat tribut") }
    static var proposePact: String { s("Propose a pact", "Nabídnout spojenectví") }
    static var pactNeedsTrust: String {
        s("They must trust you first", "Musí ti nejdřív věřit")
    }
    static var spendStanding: String { s("Spend standing", "Utratit vliv") }
    static var spendStandingBlurb: String {
        s("Overrule the assembly quietly, at the price of political capital rather than morale.",
          "Přehlasuj sněm potichu — zaplatíš politickým kapitálem místo morálky.")
    }
    static var decisionDeadline: String { s("The moment passes in", "Okamžik pomine za") }
    static var years: String { s("yrs", "let") }
    static var child: String { s("Child", "Dítě") }
    static var objectiveHint: String { s("Opens where you can act on this", "Otevře místo, kde s tím jde něco udělat") }

    // Language
    static var languageTitle: String { s("Language", "Jazyk") }
    static var languageSystem: String { s("Follow the device", "Podle zařízení") }
    static var languageBlurb: String {
        s("Content ships in Czech and English. Restart the screen to see it change everywhere.",
          "Obsah je česky i anglicky. Změna se všude projeví po přepnutí obrazovky.")
    }
    static func languageName(_ language: GameLanguage) -> String {
        switch language {
        case .en: return s("English", "Angličtina")
        case .cs: return s("Czech", "Čeština")
        }
    }

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
