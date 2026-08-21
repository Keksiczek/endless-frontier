import Foundation

/// One year of a civilisation, recorded. The chronicle keeps these so the player
/// can see the shape of their history — population curves, the drift of the
/// people's character, the price of inequality.
public struct WorldRecord: Codable, Sendable, Equatable, Identifiable {
    public let year: Int
    public let population: Int
    public let food: Double
    public let materials: Double
    public let morale: Double
    public let stability: Double
    public let gini: Double
    public let faith: Double
    /// Population-average genes — this is where natural selection becomes visible.
    public let industry: Double
    public let fertility: Double
    public let sociability: Double
    public let courage: Double
    public let deaths: [String: Int]
    public let era: Era

    public var id: Int { year }

    public init(
        year: Int, population: Int, food: Double, materials: Double,
        morale: Double, stability: Double, gini: Double, faith: Double,
        industry: Double, fertility: Double, sociability: Double, courage: Double,
        deaths: [String: Int], era: Era
    ) {
        self.year = year
        self.population = population
        self.food = food
        self.materials = materials
        self.morale = morale
        self.stability = stability
        self.gini = gini
        self.faith = faith
        self.industry = industry
        self.fertility = fertility
        self.sociability = sociability
        self.courage = courage
        self.deaths = deaths
        self.era = era
    }
}

/// A generated observation about the world's history — the "insights" panel.
public struct Insight: Sendable, Equatable, Identifiable {
    public let id: String
    public let text: LocalizedText

    public init(id: String, text: LocalizedText) {
        self.id = id
        self.text = text
    }
}

/// Takes a snapshot of the world each year and reads trends out of the record.
public enum ChronicleEngine {
    /// How many yearly records to keep. Two centuries of history is plenty and
    /// keeps saves small.
    public static let maxRecords = 200

    /// Records the year just ended. Called from the year boundary.
    public static func record(_ state: WorldState, registry: GameDataRegistry) -> WorldState {
        var s = state
        let year = s.year(registry.config)
        guard s.records.last?.year != year else { return s }

        let pawns = s.settlements.flatMap(\.pawns)
        let count = max(1, pawns.count)
        let settlements = max(1, s.settlements.count)

        var deaths: [String: Int] = [:]
        for settlement in s.settlements {
            for (cause, n) in settlement.deathTallies {
                deaths[cause, default: 0] += n
            }
        }

        s.records.append(WorldRecord(
            year: year,
            population: pawns.count,
            food: s.settlements.reduce(0) { $0 + $1.storage[.food] },
            materials: s.settlements.reduce(0) { $0 + $1.storage[.materials] },
            morale: s.settlements.reduce(0) { $0 + $1.stats.morale } / Double(settlements),
            stability: s.globalStats.stability,
            gini: s.settlements.first?.society.gini ?? 0,
            faith: s.settlements.first?.faith.faith ?? 0,
            industry: pawns.reduce(0) { $0 + $1.genes.industry } / Double(count),
            fertility: pawns.reduce(0) { $0 + $1.genes.fertility } / Double(count),
            sociability: pawns.reduce(0) { $0 + $1.genes.sociability } / Double(count),
            courage: pawns.reduce(0) { $0 + $1.genes.courage } / Double(count),
            deaths: deaths,
            era: s.era))

        if s.records.count > maxRecords {
            s.records.removeFirst(s.records.count - maxRecords)
        }
        s.figures = remember(s, year: year, ticksPerYear: registry.config.ticksPerYear)
        return s
    }

    // MARK: - The people the annals remember

    /// How old somebody has to get before the chronicle notices them.
    ///
    /// `PopulationEngine.baseLifespanYears` is sixty and genes stretch it to
    /// about seventy-eight, so this is genuinely the far end of a life rather
    /// than a number that would enrol half the colony.
    public static let rememberedAge = 72
    /// How many named people the annals keep. Two centuries of history at a
    /// few remarkable lives a decade.
    public static let maxFigures = 90

    /// **Who the chronicle keeps, updated once a year.**
    ///
    /// Derived rather than plumbed. `PopulationEngine` runs per settlement and
    /// never sees `WorldState`, so recording a death where it happens would
    /// mean threading a world through the life cycle; instead the year boundary
    /// — which already walks every settlement — notices that somebody it was
    /// keeping is no longer among the living and writes the year down. What is
    /// lost is the cause of death, which `WorldRecord.deaths` already tallies;
    /// what is kept is a name, a span, and why they were noticed.
    static func remember(
        _ state: WorldState, year: Int, ticksPerYear: Int
    ) -> [ChronicleFigure] {
        let pawns = state.settlements.flatMap(\.pawns)
        let living = Set(pawns.map(\.id))
        var figures = state.figures

        for index in figures.indices where figures[index].isAlive
            && !living.contains(figures[index].id) {
            figures[index].diedYear = year
        }

        let known = Set(figures.map(\.id))
        // In id order, so a year that notices three people notices them in the
        // same order on every replay — `pawns` reorders as colonists die.
        let newly = pawns
            .filter { !known.contains($0.id)
                && $0.ageYears(ticksPerYear: ticksPerYear) >= rememberedAge }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        for pawn in newly {
            let age = pawn.ageYears(ticksPerYear: ticksPerYear)
            figures.append(ChronicleFigure(id: pawn.id, name: pawn.name,
                                           bornYear: year - age, standing: .elder))
        }

        // Over the cap, the dead go first and the oldest of those before the
        // rest: somebody still walking about is not yet history.
        if figures.count > maxFigures {
            let over = figures.count - maxFigures
            var dropped = 0
            figures.removeAll { figure in
                guard dropped < over, !figure.isAlive else { return false }
                dropped += 1
                return true
            }
            if figures.count > maxFigures {
                figures.removeFirst(figures.count - maxFigures)
            }
        }
        return figures
    }

    /// Reads the record and says something true about it. Pure — the same
    /// history always yields the same observations.
    public static func insights(_ state: WorldState, registry: GameDataRegistry) -> [Insight] {
        let records = state.records
        guard records.count >= 5, let last = records.last else {
            return [Insight(id: "gathering", text: LocalizedText(values: [
                .en: "Too little history yet. Give it a few years.",
                .cs: "Zatím příliš málo dějin. Dej tomu pár let."
            ]))]
        }
        var out: [Insight] = []
        let span = min(records.count - 1, 60)
        let then = records[records.count - 1 - span]

        // Natural selection: which disposition has drifted the most?
        let drifts: [(String, String, String, Double)] = [
            ("industry", "diligence", "píle", last.industry - then.industry),
            ("fertility", "fertility", "plodnost", last.fertility - then.fertility),
            ("sociability", "sociability", "družnost", last.sociability - then.sociability),
            ("courage", "courage", "courage", last.courage - then.courage)
        ]
        if let biggest = drifts.max(by: { abs($0.3) < abs($1.3) }), abs(biggest.3) > 0.03 {
            let sign = biggest.3 > 0 ? "+" : ""
            let csName = biggest.0 == "courage" ? "odvaha" : biggest.2
            out.append(Insight(id: "selection", text: LocalizedText(values: [
                .en: "Natural selection: \(biggest.1) has shifted \(sign)\(format(biggest.3)) over \(span) years.",
                .cs: "Přirozený výběr: \(csName) se za \(span) let posunula o \(sign)\(format(biggest.3))."
            ])))
        }

        // Population trend.
        if last.population > Int(Double(then.population) * 1.4) {
            out.append(Insight(id: "growth", text: LocalizedText(values: [
                .en: "The people are multiplying — \(then.population) souls became \(last.population).",
                .cs: "Lid se množí — z \(then.population) duší je \(last.population)."
            ])))
        } else if last.population < Int(Double(then.population) * 0.75) {
            out.append(Insight(id: "decline", text: LocalizedText(values: [
                .en: "The settlement is dwindling — \(then.population) souls are now \(last.population).",
                .cs: "Osada chřadne — z \(then.population) duší zbylo \(last.population)."
            ])))
        }

        // Inequality.
        if last.gini > 0.45 {
            out.append(Insight(id: "inequality", text: LocalizedText(values: [
                .en: "Inequality is high (Gini \(format(last.gini))) — wealth pools with the few, and they vote twice.",
                .cs: "Nerovnost je vysoká (Gini \(format(last.gini))) — bohatství se hromadí u hrstky, a ta má dvojí hlas."
            ])))
        }

        // The commonest end.
        if let worst = totalDeaths(last).max(by: { $0.value < $1.value }), worst.value > 0 {
            out.append(Insight(id: "deaths", text: LocalizedText(values: [
                .en: "Most lives end from \(englishCause(worst.key)) (\(worst.value)×).",
                .cs: "Nejčastější příčina smrti: \(czechCause(worst.key)) (\(worst.value)×)."
            ])))
        }

        // Faith.
        if last.faith > 70, let cultID = state.settlements.first?.faith.cultID,
           let cult = registry.cult(cultID) {
            out.append(Insight(id: "faith", text: LocalizedText(values: [
                .en: "Devotion to the \(cult.name.resolve(.en)) runs deep — comfort in every disaster.",
                .cs: "Víra ve \(cult.name.resolve(.cs)) je silná — útěcha v každé pohromě."
            ])))
        }

        // Uprisings.
        let revolts = state.settlements.reduce(0) { $0 + $1.society.revolts }
        if revolts > 0 {
            out.append(Insight(id: "revolts", text: LocalizedText(values: [
                .en: "\(revolts) uprising(s) have shaken the granaries. Inequality has consequences.",
                .cs: "Proběhlo \(revolts) vzpour chudiny — nerovnost má následky."
            ])))
        }

        return out
    }

    static func totalDeaths(_ record: WorldRecord) -> [String: Int] { record.deaths }

    private static func format(_ v: Double) -> String { String(format: "%.2f", v) }

    private static func englishCause(_ raw: String) -> String {
        switch raw {
        case "starvation": return "hunger"
        case "sickness": return "sickness"
        case "old_age": return "old age"
        case "beast": return "beasts"
        case "battle": return "battle"
        default: return raw
        }
    }

    private static func czechCause(_ raw: String) -> String {
        switch raw {
        case "starvation": return "hlad"
        case "sickness": return "nemoc"
        case "old_age": return "stáří"
        case "beast": return "zvěř"
        case "battle": return "boj"
        default: return raw
        }
    }
}
