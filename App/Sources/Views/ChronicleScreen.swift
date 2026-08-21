import SwiftUI
import Charts
import EndlessFrontierCore

/// The annals: what the world has become, read out of a century of yearly
/// records — the population curve, the drift of the people's character, the
/// price of inequality — and the events that shaped it.
struct ChronicleScreen: View {
    @Bindable var game: GameViewModel

    private var cs: Bool { AppStrings.language == .cs }
    private var records: [WorldRecord] { game.world.records }

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if records.count < 2 {
                        empty
                    } else {
                        annals
                        lives
                        insights
                        populationChart
                        spiritChart
                        geneChart
                        storesChart
                        deathsChart
                    }
                    faithCard
                    eventLog
                }
                .padding(20)
            }
        }
        .foregroundStyle(Theme.text)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppStrings.tabChronicle)
                .font(.system(.largeTitle, design: .serif).weight(.bold))
            Text(cs ? "Letopisy tvého lidu." : "The annals of your people.")
                .font(.subheadline).foregroundStyle(Theme.textDim)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(Theme.textDim)
            Text(cs ? "Dějiny se teprve píší. Vrať se za pár let."
                    : "History is still being written. Come back in a few years.")
                .font(.callout).foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30)
    }

    // MARK: - Insights

    private var insights: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: cs ? "Poznatky" : "Insights")
            ForEach(game.insights) { insight in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkle").font(.caption2).foregroundStyle(Theme.accent)
                    Text(insight.text.resolve(AppStrings.language))
                        .font(.callout).foregroundStyle(Theme.text)
                }
            }
        }
        .frontierCard()
    }

    // MARK: - The annals

    /// The history, in chapters, written out. Newest age first: a player
    /// opening the book wants the age they are living in, not the founding.
    ///
    /// The prose comes from Layer 3 through `NarratorProtocol`. What ships is
    /// `StubNarrator`, which needs no model and no network — so this reads the
    /// same on a plane as it does at home, which is the rule.
    private var annals: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: cs ? "Letopisy" : "Annals")
            ForEach(game.chapters.reversed()) { chapter in
                chapterCard(chapter)
            }
        }
    }

    private func chapterCard(_ chapter: ChapterSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(chapter.firstYear)–\(chapter.lastYear)")
                    .font(.system(.title3, design: .serif).weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text(chapter.era.displayName.resolve(AppStrings.language))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textDim)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            Text(game.annal(chapter))
                .font(.system(.callout, design: .serif))
                .lineSpacing(3)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                chapterStat("person.2.fill",
                            "\(chapter.populationFirst) → \(chapter.populationLast)")
                if chapter.deathCount > 0 {
                    chapterStat("moon.zzz.fill", "\(chapter.deathCount)")
                }
                if !chapter.events.isEmpty {
                    chapterStat("bolt.fill", "\(chapter.events.count)")
                }
            }
        }
        .frontierCard()
    }

    private func chapterStat(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption2)
            Text(value).font(.caption.monospacedDigit())
        }
        .foregroundStyle(Theme.textDim)
    }

    // MARK: - The people

    /// **Who the annals remember.** A chronicle of a civilisation with no names
    /// in it is a spreadsheet; these are the founders and the elders, newest
    /// death first, with the living at the top of the list where they belong.
    @ViewBuilder
    private var lives: some View {
        let figures = game.world.figures.sorted { a, b in
            if a.isAlive != b.isAlive { return a.isAlive }
            return (a.diedYear ?? 0) > (b.diedYear ?? 0)
        }
        if !figures.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: cs ? "Životy" : "Lives")
                ForEach(figures.prefix(12)) { figure in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: figure.isAlive ? "figure.stand" : "leaf")
                            .font(.caption2)
                            .foregroundStyle(figure.isAlive ? Theme.accent : Theme.textDim)
                        Text(figure.name)
                            .font(.system(.subheadline, design: .serif).weight(.semibold))
                        Text(figure.standing.label.resolve(AppStrings.language))
                            .font(.caption2).foregroundStyle(Theme.textDim)
                        Spacer()
                        Text(span(figure))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.textDim)
                    }
                }
                if figures.count > 12 {
                    Text(cs ? "…a dalších \(figures.count - 12)"
                            : "…and \(figures.count - 12) more")
                        .font(.caption2).foregroundStyle(Theme.textDim)
                }
            }
            .frontierCard()
        }
    }

    /// "12–84" for somebody buried, "12–" for somebody still walking about.
    private func span(_ figure: ChronicleFigure) -> String {
        guard let died = figure.diedYear else { return "\(figure.bornYear)–" }
        return "\(figure.bornYear)–\(died)"
    }

    // MARK: - Charts

    private var populationChart: some View {
        chartCard(cs ? "Populace" : "Population") {
            Chart(records) { r in
                AreaMark(x: .value("Year", r.year), y: .value("Population", r.population))
                    .foregroundStyle(.linearGradient(
                        colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Year", r.year), y: .value("Population", r.population))
                    .foregroundStyle(Theme.accent)
                    .interpolationMethod(.monotone)
            }
        }
    }

    private var spiritChart: some View {
        chartCard(cs ? "Nálada a nerovnost" : "Spirit & inequality") {
            Chart {
                ForEach(records) { r in
                    LineMark(x: .value("Year", r.year), y: .value("Value", r.morale),
                             series: .value("s", "morale"))
                        .foregroundStyle(Theme.good)
                        .interpolationMethod(.monotone)
                }
                ForEach(records) { r in
                    // Gini is 0…1; scale it onto the same 0…100 axis.
                    LineMark(x: .value("Year", r.year), y: .value("Value", r.gini * 100),
                             series: .value("s", "gini"))
                        .foregroundStyle(Theme.danger)
                        .interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: 0...100)
        } legend: {
            HStack(spacing: 14) {
                legendDot(Theme.good, cs ? "Morálka" : "Morale")
                legendDot(Theme.danger, cs ? "Nerovnost (Gini ×100)" : "Inequality (Gini ×100)")
            }
        }
    }

    private var geneChart: some View {
        chartCard(cs ? "Vlohy lidu — přirozený výběr" : "Disposition — natural selection") {
            Chart {
                geneSeries(cs ? "Píle" : "Diligence", Theme.accent, \.industry)
                geneSeries(cs ? "Plodnost" : "Fertility", Theme.good, \.fertility)
                geneSeries(cs ? "Družnost" : "Sociability", Theme.bone, \.sociability)
                geneSeries(cs ? "Odvaha" : "Courage", Theme.danger, \.courage)
            }
            .chartYScale(domain: 0...1)
        } legend: {
            HStack(spacing: 12) {
                legendDot(Theme.accent, cs ? "Píle" : "Dilig.")
                legendDot(Theme.good, cs ? "Plodnost" : "Fert.")
                legendDot(Theme.bone, cs ? "Družnost" : "Soc.")
                legendDot(Theme.danger, cs ? "Odvaha" : "Cour.")
            }
        }
    }

    @ChartContentBuilder
    private func geneSeries(_ name: String, _ color: Color, _ key: KeyPath<WorldRecord, Double>) -> some ChartContent {
        ForEach(records) { r in
            LineMark(x: .value("Year", r.year), y: .value("Gene", r[keyPath: key]),
                     series: .value("s", name))
                .foregroundStyle(color)
                .interpolationMethod(.monotone)
        }
    }

    /// What the colony had, year by year. `food` and `materials` have been in
    /// every `WorldRecord` since the chronicle existed and nothing ever drew
    /// them — which meant the one question a player asks about their own
    /// history ("were we ever this short before?") had no answer on this
    /// screen.
    private var storesChart: some View {
        chartCard(cs ? "Zásoby" : "Stores") {
            Chart {
                ForEach(records) { r in
                    LineMark(x: .value("Year", r.year), y: .value("Value", r.food),
                             series: .value("s", "food"))
                        .foregroundStyle(Theme.good)
                        .interpolationMethod(.monotone)
                }
                ForEach(records) { r in
                    LineMark(x: .value("Year", r.year), y: .value("Value", r.materials),
                             series: .value("s", "materials"))
                        .foregroundStyle(Theme.accent)
                        .interpolationMethod(.monotone)
                }
            }
        } legend: {
            HStack(spacing: 14) {
                legendDot(Theme.good, cs ? "Jídlo" : "Food")
                legendDot(Theme.accent, cs ? "Materiál" : "Materials")
            }
        }
    }

    private var deathsChart: some View {
        let deaths = records.last?.deaths ?? [:]
        let entries = deaths.sorted { $0.value > $1.value }
        return Group {
            if entries.isEmpty {
                EmptyView()
            } else {
                chartCard(cs ? "Úmrtí dle příčin" : "Deaths by cause") {
                    Chart(entries, id: \.key) { cause, count in
                        BarMark(x: .value("Cause", causeName(cause)),
                                y: .value("Count", count))
                            .foregroundStyle(Theme.boneDim)
                            .cornerRadius(3)
                    }
                }
            }
        }
    }

    private func causeName(_ raw: String) -> String {
        guard cs else { return raw.replacingOccurrences(of: "_", with: " ") }
        switch raw {
        case "starvation": return "hlad"
        case "sickness": return "nemoc"
        case "old_age": return "stáří"
        case "beast": return "zvěř"
        case "battle": return "boj"
        default: return raw
        }
    }

    @ViewBuilder
    private func chartCard<C: View, L: View>(
        _ title: String, @ViewBuilder chart: () -> C, @ViewBuilder legend: () -> L
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title)
            chart()
                .frame(height: 140)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
            legend()
        }
        .frontierCard()
    }

    @ViewBuilder
    private func chartCard<C: View>(_ title: String, @ViewBuilder chart: () -> C) -> some View {
        chartCard(title, chart: chart, legend: { EmptyView() })
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2).foregroundStyle(Theme.textDim)
        }
    }

    // MARK: - Faith

    @ViewBuilder
    private var faithCard: some View {
        if let settlement = game.selectedSettlement,
           let cultID = settlement.faith.cultID,
           let cult = game.registry.cult(cultID) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionHeader(title: cs ? "Víra" : "Faith")
                    Spacer()
                    Text("\(Int(settlement.faith.faith))")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                Text(cult.name.resolve(AppStrings.language))
                    .font(.system(.title3, design: .serif).weight(.semibold))
                Text(verbatim: "„\(cult.creed.resolve(AppStrings.language))“")
                    .font(.callout).italic().foregroundStyle(Theme.textDim)
                StatBar(label: cs ? "Zbožnost" : "Devotion",
                        value: settlement.faith.faith, tint: Theme.accent)
                if settlement.faith.rites > 0 {
                    Text("\(cs ? "Velkých obřadů" : "Great rites"): \(settlement.faith.rites)")
                        .font(.caption).foregroundStyle(Theme.textDim)
                }
            }
            .frontierCard()
        } else if game.selectedSettlement?.faith.prophetStirring == true {
            Label(cs ? "Do osady přišel prorok a káže o bozích — lid žádá chrám."
                     : "A prophet walks among the people, preaching for a temple.",
                  systemImage: "flame.fill")
                .font(.callout).foregroundStyle(Theme.accent)
                .frontierCard()
        }
    }

    // MARK: - Events

    private var eventLog: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: cs ? "Události" : "Events")
            if game.world.eventHistory.isEmpty {
                Text(cs ? "Zatím se nic nezapsalo." : "Nothing recorded yet.")
                    .font(.callout).foregroundStyle(Theme.textDim)
            } else {
                ForEach(game.world.eventHistory.reversed().prefix(40)) { event in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(Season.year(tick: event.tick, ticksPerYear: game.ticksPerYear))")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 30, alignment: .trailing)
                        Rectangle().fill(tint(event.type)).frame(width: 2)
                        Text(eventName(event.templateID))
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frontierCard()
    }

    private func eventName(_ id: String) -> String {
        game.registry.events.first { $0.id == id }?.name.resolve(AppStrings.language)
            ?? id.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func tint(_ type: EventType) -> Color {
        switch type {
        case .disaster, .threat: return Theme.danger
        case .opportunity: return Theme.good
        case .quest: return Theme.accent
        case .flavor: return Theme.boneFaint
        }
    }
}
