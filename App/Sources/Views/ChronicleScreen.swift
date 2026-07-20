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
                        insights
                        populationChart
                        spiritChart
                        geneChart
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
