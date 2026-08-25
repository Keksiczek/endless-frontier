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
    /// The one act toward a people that leaves something on the map.
    static var buildRoadToward: String { s("Build a road", "Postavit cestu") }
    /// An embassy — a colonist who goes to live among them and speak for us.
    static var sendEnvoy: String { s("Send an envoy", "Vyslat vyslance") }
    static var recallEnvoy: String { s("Call them home", "Povolat zpět") }
    /// Buying peace: a yearly payment, and the cost of stopping it.
    static var offerTribute: String { s("Offer tribute", "Nabídnout tribut") }
    static var declareWar: String { s("Declare war", "Vyhlásit válku") }
    /// Why a study whose prerequisites are all met is still shut: the colony
    /// does not live in a century that could attempt it yet.
    static func notThisAge(_ era: String) -> String {
        s("Not in this age — belongs to the \(era)",
          "Ne v této době — patří do doby: \(era)")
    }
    static var stopTribute: String { s("Stop paying", "Přestat platit") }
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
    static var needsYou: String { s("Needs you", "Potřebují tě") }
    static var objectiveHint: String { s("Opens where you can act on this", "Otevře místo, kde s tím jde něco udělat") }
    static var cannotAffordExpedition: String {
        s("— the stores can't cover it", "— na to zásoby nestačí")
    }
    static var expeditionAlreadyOut: String {
        s("An expedition is already out. Only one may travel at a time.",
          "Jedna výprava je už na cestě. Víc jich naráz nevyrazí.")
    }

    // Panels that were shipping English-only until 2026-08-13. Found by
    // `UIStringsTests`, which walks the source rather than trusting this file to
    // be complete — the content JSON has been audited for years and the chrome
    // in Swift never was.
    static var mood: String { s("Mood", "Nálada") }
    static var perTick: String { s("/tick", "/tik") }
    static var tick: String { s("Tick", "Tik") }
    static var knowledgeUnit: String { s("knowledge", "znalostí") }
    static var needsPrefix: String { s("Needs:", "Potřebuje:") }
    static var noActiveResearch: String { s("No active research", "Nic se nezkoumá") }
    static var researchUnlocksBuildings: String {
        s("Research unlocks new buildings.", "Výzkum odemyká nové budovy.")
    }
    static var questsCompleted: String { s("completed", "hotovo") }
    static var questsEmpty: String {
        s("New quests await as your colony grows.",
          "Jak kolonie roste, přibývají nové úkoly.")
    }
    static var itemsEmpty: String {
        s("Delve ruins and dungeons on the World map to recover relics and gear.",
          "Prohledej ruiny a kobky na mapě světa a přines relikvie a výstroj.")
    }
    static var itemMaterial: String { s("Material", "Materiál") }
    static var itemActive: String { s("Active", "Nasazeno") }
    static var itemEquip: String { s("Equip", "Nasadit") }
    static var caravanBlurb: String {
        s("A one-off escorted shipment. Guards travel with the goods, can be ambushed, and settle at the destination.",
          "Jednorázová zásilka s doprovodem. Stráže jdou se zbožím, můžou padnout do léčky a v cíli se usadí.")
    }
    static var exploreAdjacentFirst: String {
        s("Explore an adjacent region first.", "Nejdřív prozkoumej sousední kraj.")
    }
    static func expeditionUnderWay(ticksLeft: Int) -> String {
        s("Expedition under way — \(ticksLeft) ticks left",
          "Výprava je na cestě — zbývá \(ticksLeft) tiků")
    }

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
        case .garrison: return s("Garrison", "Posádka")
        case .crafting: return s("Crafter", "Řemeslník")
        case .cooking:  return s("Cook", "Kuchař")
        }
    }

    /// How relations with a neighbouring people read on a pill or map card.
    static func standingName(_ status: DiplomaticStanding) -> String {
        switch status {
        case .allied:   return s("Allied", "Spojenci")
        case .friendly: return s("Friendly", "Přátelské")
        case .neutral:  return s("Neutral", "Neutrální")
        case .tense:    return s("Tense", "Napjaté")
        case .war:      return s("War", "Válka")
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

    /// **What somebody would actually say if you asked them why.**
    ///
    /// `AssemblyEngine` records the term that moved a colonist furthest from
    /// the middle; this turns that into a sentence. Direction matters — a
    /// woodcutter for a hewing law and a woodcutter against a forest law are
    /// the same *reason* and opposite sentences — and so does standing, which
    /// is the one reason that names a group rather than a person.
    ///
    /// Czech carries no gender here on purpose: a pawn has no sex in the
    /// model, so anything in the past tense ("byl"/"byla") would be a guess.
    /// Present tense and verbless phrases agree with everybody.
    static func voteReason(_ reason: VoteReason, forIt: Bool, wealth: WealthClass) -> String {
        switch reason {
        case .nature:
            return forIt ? s("It suits the kind of person they are", "Má to v povaze")
                         : s("It goes against their grain", "Příčí se to jeho povaze")
        case .trade:
            return forIt ? s("It would be good for their trade", "Prospěje to řemeslu")
                         : s("It would hurt their trade", "Ublíží to řemeslu")
        case .standing:
            let group: String
            switch wealth {
            case .poor:    group = s("the poor", "chudině")
            case .middle:  group = s("the middling sort", "střední vrstvě")
            case .wealthy: group = s("the wealthy", "zámožným")
            }
            let payers: String
            switch wealth {
            case .poor:    payers = s("The poor", "Chudina")
            case .middle:  payers = s("The middling sort", "Střední vrstva")
            case .wealthy: payers = s("The wealthy", "Zámožní")
            }
            return forIt ? s("It favours \(group)", "Nahrává to \(group)")
                         : s("\(payers) would pay for it", "\(payers) na to doplatí")
        case .experience:
            return forIt ? s("Years in the trade say it is worth it",
                             "Za ta léta v řemesle ví, že to stojí za to")
                         : s("Years in the trade say otherwise",
                             "Za ta léta v řemesle ví své")
        case .hardship:
            return forIt ? s("Things could hardly be worse", "Hůř už být nemůže")
                         : s("Life is hard enough already", "Život je tvrdý i bez toho")
        case .household:
            return s("Their household votes this way", "Doma to tak vidí")
        case .leader:
            return s("They lead here, and they stand by it",
                     "Vede tuhle osadu a stojí si za tím")
        case .undecided:
            return s("Nothing much moved them", "Nic zvláštního nepřevážilo")
        }
    }

    /// How many adults were in the room — which the tally cannot say, because
    /// a vote is weighted by class.
    static func turnout(_ adults: Int) -> String {
        s("\(adults) adults in the room", "\(adults) dospělých v sále")
    }

    /// Taking back a mark on a thing (`Designation`).
    static var liftTheOrder: String { s("Never mind", "Zrušit příkaz") }

    static var whoSpoke: String { s("Who spoke", "Kdo mluvil") }
    static var showEverybody: String { s("All of them", "Všichni") }
    static var showFewer: String { s("Fewer", "Méně") }

    // Era. The names live in the Core now — a chapter heading in the annals is
    // content, and content is not kept in two places.
    static func eraTitle(_ era: Era) -> String {
        era.displayName.resolve(language)
    }
}
