import Foundation

/// The narrator that ships: no model, no network, no `Date()`.
///
/// It writes a chapter of the annals out of the snapshot's numbers and nothing
/// else, which makes it deterministic — the same history reads the same way on
/// every replay and in every language. Where it wants variety it draws from a
/// seed built out of `(mapSeed, firstYear)`, both of which are stable for the
/// life of a world.
///
/// This is the *floor*, not a placeholder. A model-backed narrator is allowed
/// to be better; it is not allowed to be required.
public struct StubNarrator: NarratorProtocol {
    /// The world's map seed, so two worlds telling the same numbers still tell
    /// them in different words.
    public let mapSeed: UInt64

    public init(mapSeed: UInt64 = 0) {
        self.mapSeed = mapSeed
    }

    public var isAvailable: Bool { true }

    public func narrate(_ chapter: ChapterSnapshot, language: GameLanguage) async -> String? {
        annal(chapter, language: language)
    }

    /// The synchronous form. The stub has no reason to be `async` and the
    /// tests and the chronicle screen have every reason not to be.
    public func annal(_ chapter: ChapterSnapshot, language: GameLanguage) -> String {
        var rng = SeededRNG(seed: seed(for: chapter))
        var lines: [String] = []
        lines.append(people(chapter, language, &rng))
        if let died = dead(chapter, language) { lines.append(died) }
        if let drift = changed(chapter, language) { lines.append(drift) }
        if let mood = state(chapter, language) { lines.append(mood) }
        if let lean = hunger(chapter, language) { lines.append(lean) }
        if let seen = remembered(chapter, language) { lines.append(seen) }
        return lines.joined(separator: " ")
    }

    // MARK: - The sentences

    /// How many there were, at both ends of the chapter.
    private func people(
        _ c: ChapterSnapshot, _ lang: GameLanguage, _ rng: inout SeededRNG
    ) -> String {
        let cs = lang == .cs
        let grew = c.populationLast > Int(Double(c.populationFirst) * 1.1)
        let fell = c.populationLast < Int(Double(c.populationFirst) * 0.9)
        // Two ways of opening, so a long history does not read as a form
        // letter. Drawn from the chapter's own seed, so it is the same two
        // hundred years later and on another device.
        // …and the plain form always, for a chapter too short for the other
        // one to count years in (Czech counts 2–4 differently from 5 and up).
        let plain = rng.nextUnit() < 0.5 || c.years < 5
        let when = cs
            ? (plain ? "Mezi lety \(c.firstYear) a \(c.lastYear)" : "Za \(c.years) let do roku \(c.lastYear)")
            : (plain ? "Between the years \(c.firstYear) and \(c.lastYear)" : "In the \(c.years) years to \(c.lastYear)")
        var out: String
        if grew {
            out = cs
                ? "\(when) vzrostla osada z \(c.populationFirst) \(souls(c.populationFirst)) na \(c.populationLast)."
                : "\(when) the settlement grew from \(c.populationFirst) souls to \(c.populationLast)."
        } else if fell {
            out = cs
                ? "\(when) osady ubylo — z \(c.populationFirst) \(souls(c.populationFirst)) na \(c.populationLast)."
                : "\(when) the settlement dwindled from \(c.populationFirst) souls to \(c.populationLast)."
        } else {
            out = cs
                ? "\(when) se osada držela kolem \(c.populationLast) \(souls(c.populationLast))."
                : "\(when) the settlement held at about \(c.populationLast) souls."
        }
        // A peak the ends do not show is the whole story of a chapter that
        // rose and then lost it again.
        if c.populationPeak > Int(Double(max(c.populationFirst, c.populationLast)) * 1.15) {
            out += cs
                ? " Nejvíc jich bylo v roce \(c.peakYear) — \(c.populationPeak)."
                : " It stood at its largest in \(c.peakYear): \(c.populationPeak) of them."
        }
        return out
    }

    /// What the years cost, and what took them.
    private func dead(_ c: ChapterSnapshot, _ lang: GameLanguage) -> String? {
        let total = c.deathCount
        guard total > 0 else { return nil }
        let cs = lang == .cs
        var out = cs
            ? "Pohřbili za tu dobu \(total) \(csPeople(total))."
            : "\(total) were buried in those years."
        if let worst = c.deaths.max(by: { $0.value < $1.value }),
           Double(worst.value) > Double(total) * 0.35 {
            out += " " + Self.commonestEnd(worst.key).resolve(lang)
        }
        return out
    }

    /// Whether the people themselves changed.
    private func changed(_ c: ChapterSnapshot, _ lang: GameLanguage) -> String? {
        guard let drift = c.largestDrift, abs(drift.shift) >= 0.02 else { return nil }
        let cs = lang == .cs
        let name = Self.traitName(drift.trait).resolve(lang)
        let rose = drift.shift > 0
        // Every one of the four Czech names is feminine, so one pair of verbs
        // covers them all.
        if cs {
            let verb = rose ? "stoupla" : "klesla"
            return "Lid se za tu dobu proměnil: \(name) \(verb) z \(number(drift.from, cs: true)) na \(number(drift.to, cs: true))."
        }
        let verb = rose ? "rose" : "fell"
        return "The people themselves changed: \(name) \(verb) from \(number(drift.from, cs: false)) to \(number(drift.to, cs: false))."
    }

    /// How it felt to live there.
    private func state(_ c: ChapterSnapshot, _ lang: GameLanguage) -> String? {
        let cs = lang == .cs
        if c.giniLast > 0.45 {
            return cs
                ? "Bohatství se slilo k hrstce — Gini \(number(c.giniLast, cs: true))."
                : "Wealth had pooled with the few — a Gini of \(number(c.giniLast, cs: false))."
        }
        if c.faithLast > 60 {
            return cs ? "Víra byla ke konci hluboká." : "Faith ran deep by the end of it."
        }
        if c.moraleMean < 40 {
            return cs ? "Byl to bezútěšný věk." : "It was a joyless age."
        }
        if c.moraleMean > 68 {
            return cs ? "Nálada přitom držela vysoko." : "Spirits held high through it."
        }
        return nil
    }

    /// The year the stores were thinnest.
    private func hunger(_ c: ChapterSnapshot, _ lang: GameLanguage) -> String? {
        guard c.leanestFood < 25 else { return nil }
        return lang == .cs
            ? "V roce \(c.leanestYear) byly sýpky skoro prázdné."
            : "In \(c.leanestYear) the granaries stood all but empty."
    }

    /// What the years are remembered for. A colon and a list, on purpose: an
    /// event's name is a noun in whatever case its own language wants, and a
    /// sentence that tries to govern it will decline it wrongly half the time.
    private func remembered(_ c: ChapterSnapshot, _ lang: GameLanguage) -> String? {
        let worth = c.events.filter { $0.type == .disaster || $0.type == .threat }
        let chosen = (worth.isEmpty ? c.events : worth).prefix(3)
        guard !chosen.isEmpty else { return nil }
        let names = chosen.map { $0.name.resolve(lang) }.joined(separator: ", ")
        return lang == .cs
            ? "Co se z těch let pamatuje: \(names)."
            : "Remembered from those years: \(names)."
    }

    // MARK: - Words

    /// A stable seed for this chapter of this world.
    private func seed(for c: ChapterSnapshot) -> UInt64 {
        var h = mapSeed &* 0x9E37_79B9_7F4A_7C15
        h ^= UInt64(bitPattern: Int64(c.firstYear))
        return (h ^ (h >> 27)) &* 0x0100_0000_01B3
    }

    /// `duše` / `duše` / `duší` — Czech counts in three.
    private func souls(_ n: Int) -> String {
        n == 1 ? "duše" : (n >= 2 && n <= 4 ? "duše" : "duší")
    }

    private func csPeople(_ n: Int) -> String {
        n == 1 ? "člověka" : (n >= 2 && n <= 4 ? "lidi" : "lidí")
    }

    /// Czech writes the decimal with a comma.
    private func number(_ v: Double, cs: Bool) -> String {
        let s = String(format: "%.2f", v)
        return cs ? s.replacingOccurrences(of: ".", with: ",") : s
    }

    /// The commonest end, as a whole clause — the Czech verb has to agree with
    /// the cause's gender, so the clause is the unit that gets translated
    /// rather than the noun.
    static func commonestEnd(_ cause: String) -> LocalizedText {
        switch cause {
        case "starvation":
            return LocalizedText(values: [.en: "Hunger took most of them.",
                                          .cs: "Nejvíc jich vzal hlad."])
        case "sickness":
            return LocalizedText(values: [.en: "Sickness took most of them.",
                                          .cs: "Nejvíc jich vzala nemoc."])
        case "old_age":
            return LocalizedText(values: [.en: "Most of them died of old age.",
                                          .cs: "Většina z nich sešla stářím."])
        case "beast":
            return LocalizedText(values: [.en: "Beasts killed most of them.",
                                          .cs: "Nejvíc jich roztrhala zvěř."])
        case "battle":
            return LocalizedText(values: [.en: "Most of them fell in battle.",
                                          .cs: "Nejvíc jich padlo v boji."])
        case "accident":
            return LocalizedText(values: [.en: "Most of them died in accidents.",
                                          .cs: "Nejvíc jich vzalo neštěstí."])
        default:
            return LocalizedText(values: [.en: "Most of them died of \(cause).",
                                          .cs: "Většina z nich zemřela na \(cause)."])
        }
    }

    /// What a disposition is called, in the player's language.
    static func traitName(_ trait: String) -> LocalizedText {
        switch trait {
        case "industry":
            return LocalizedText(values: [.en: "diligence", .cs: "píle"])
        case "fertility":
            return LocalizedText(values: [.en: "fertility", .cs: "plodnost"])
        case "sociability":
            return LocalizedText(values: [.en: "sociability", .cs: "družnost"])
        case "courage":
            return LocalizedText(values: [.en: "courage", .cs: "odvaha"])
        default:
            return LocalizedText(trait)
        }
    }
}
