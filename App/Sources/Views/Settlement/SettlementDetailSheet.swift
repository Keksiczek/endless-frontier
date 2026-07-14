import SwiftUI
import EndlessFrontierCore

/// The swipe-up control drawer for the settlement: everything the player steers,
/// composed from the existing panels so the living canvas stays uncluttered.
struct SettlementDetailSheet: View {
    @Bindable var game: GameViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if game.settlements.count > 1 {
                    SettlementPicker(game: game)
                }
                if let settlement = game.selectedSettlement {
                    statsCard(settlement)
                }
                ObjectivesPanel(game: game)
                QuestsPanel(game: game)
                ColonistsPanel(game: game)
                ItemsPanel(game: game)
                CraftingPanel(game: game)
                TradePanel(game: game)
                TechBuildPanel(game: game)
            }
            .padding(20)
        }
        .background(Theme.surface)
        .foregroundStyle(Theme.text)
    }

    private func statsCard(_ settlement: Settlement) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: settlement.name)
                Spacer()
                Label("\(settlement.pawns.count)/\(game.housingCapacity(settlement))",
                      systemImage: "person.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textDim)
            }
            specialization(settlement)
            StatBar(label: label("Stability", "Stabilita"), value: settlement.stats.stability, tint: Theme.good)
            StatBar(label: label("Morale", "Morálka"), value: settlement.stats.morale, tint: Theme.accent)
            StatBar(label: label("Defense", "Obrana"), value: settlement.stats.defense, tint: Theme.good)
            StatBar(label: label("Prosperity", "Prosperita"), value: game.world.globalStats.prosperity, tint: Theme.good)
            StatBar(label: label("Threat", "Hrozba"), value: game.world.globalStats.threatLevel, tint: Theme.danger)
            eraProgress
        }
        .frontierCard()
    }

    private func specialization(_ settlement: Settlement) -> some View {
        HStack {
            Text(label("Specialisation", "Zaměření"))
                .font(.caption.weight(.medium)).foregroundStyle(Theme.textDim)
            Spacer()
            Menu {
                ForEach(SettlementSpecialization.allCases, id: \.self) { spec in
                    Button {
                        game.setSpecialization(spec)
                    } label: {
                        Label(spec.displayName, systemImage: settlement.specialization == spec ? "checkmark" : "")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(settlement.specialization.displayName).font(.caption.weight(.semibold))
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var eraProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label("Era progress", "Postup érou"))
                    .font(.caption.weight(.medium)).foregroundStyle(Theme.textDim)
                Spacer()
                if let next = game.world.era.next {
                    Text("\(label("Next", "Další")): \(AppStrings.eraTitle(next))")
                        .font(.caption2).foregroundStyle(Theme.textDim)
                }
            }
            StatBar(label: label("Milestones", "Milníky"), value: game.eraProgress * 100, tint: Theme.accent)
        }
    }

    private func label(_ en: String, _ cs: String) -> String {
        AppStrings.language == .cs ? cs : en
    }
}
