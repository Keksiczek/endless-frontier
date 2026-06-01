import SwiftUI
import EndlessFrontierCore

struct DashboardView: View {
    @Bindable var game: GameViewModel

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 10)]

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if let error = game.loadError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Theme.danger)
                            .frontierCard()
                    }
                    resourcesSection
                    if let capital = game.capital {
                        settlementSection(capital)
                    }
                    eraSection
                    ColonistsPanel(game: game)
                    TechBuildPanel(game: game)
                }
                .padding(20)
            }
        }
        .foregroundStyle(Theme.text)
        .sheet(isPresented: summaryBinding) {
            WhileAwayView(events: game.lastSessionEvents, registry: game.registry) {
                game.dismissSessionSummary()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Endless Frontier")
                        .font(.system(.largeTitle, design: .serif).weight(.bold))
                    Text(eraTitle(game.world.era))
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("TICK")
                        .font(.caption2.weight(.bold)).tracking(1.5)
                        .foregroundStyle(Theme.textDim)
                    Text("\(game.world.tick)")
                        .font(.title3.monospacedDigit().weight(.semibold))
                }
            }
            StatBar(label: "Tension", value: game.tension, tint: tensionColor(game.tension))
        }
        .frontierCard()
    }

    // MARK: - Resources

    private var resourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Resources")
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ResourceType.allCases, id: \.self) { type in
                    ResourceChip(
                        type: type,
                        amount: game.capital?.storage[type] ?? 0,
                        capacity: game.capital?.storageCapacity ?? 0
                    )
                }
            }
        }
    }

    // MARK: - Settlement

    private func settlementSection(_ settlement: Settlement) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: settlement.name)
                Spacer()
                Label("\(Int(settlement.population.rounded()))", systemImage: "person.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textDim)
            }
            StatBar(label: "Stability", value: settlement.stats.stability, tint: Theme.good)
            StatBar(label: "Morale", value: settlement.stats.morale, tint: Theme.accent)
            StatBar(label: "Prosperity", value: game.world.globalStats.prosperity, tint: Theme.good)
            StatBar(label: "Threat", value: game.world.globalStats.threatLevel, tint: Theme.danger)
        }
        .frontierCard()
    }

    // MARK: - Era progress

    private var eraSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Era Progress")
                Spacer()
                if let next = game.world.era.next {
                    Text("Next: \(eraTitle(next))")
                        .font(.caption).foregroundStyle(Theme.textDim)
                } else {
                    Text("Final era").font(.caption).foregroundStyle(Theme.textDim)
                }
            }
            StatBar(label: "Milestones", value: game.eraProgress * 100, tint: Theme.accent)
        }
        .frontierCard()
    }

    // MARK: - Helpers

    private var summaryBinding: Binding<Bool> {
        Binding(
            get: { !game.lastSessionEvents.isEmpty },
            set: { if !$0 { game.dismissSessionSummary() } }
        )
    }

    private func tensionColor(_ value: Double) -> Color {
        switch value {
        case ..<40: return Theme.good
        case ..<70: return Theme.accent
        default: return Theme.danger
        }
    }

    private func eraTitle(_ era: Era) -> String {
        era.rawValue
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
