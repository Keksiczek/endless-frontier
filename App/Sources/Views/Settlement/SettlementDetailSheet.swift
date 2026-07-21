import SwiftUI
import EndlessFrontierCore

/// The swipe-up control drawer for the settlement: everything the player steers,
/// composed from the existing panels so the living canvas stays uncluttered.
struct SettlementDetailSheet: View {
    @Bindable var game: GameViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if game.settlements.count > 1 {
                    SettlementPicker(game: game)
                }
                // The overview stays open; everything the player *steers* folds
                // into named sections, so the drawer reads as a tidy list you
                // open a piece of — not one endless stack where trade hides at
                // the very bottom.
                if let settlement = game.selectedSettlement {
                    statsCard(settlement)
                }
                DrawerSection(label("Construction", "Stavba"), systemImage: "hammer.fill") {
                    ConstructionPanel(game: game)
                }
                DrawerSection(label("Colonists", "Osadníci"), systemImage: "person.2.fill") {
                    ColonistsPanel(game: game)
                }
                DrawerSection(label("Trade", "Obchod"), systemImage: "cart.fill") {
                    TradePanel(game: game)
                }
                DrawerSection(label("Crafting", "Výroba"), systemImage: "hammer.fill") {
                    CraftingPanel(game: game)
                }
                DrawerSection(label("Items", "Předměty"), systemImage: "bag.fill") {
                    ItemsPanel(game: game)
                }
                DrawerSection(label("Quests", "Úkoly"), systemImage: "scroll.fill") {
                    QuestsPanel(game: game)
                }
                DrawerSection(label("Objectives", "Cíle"), systemImage: "target") {
                    // Following an objective leaves this sheet behind — it's
                    // covering the tab the player is being sent to.
                    ObjectivesPanel(game: game) { destination in
                        game.tab = destination
                        dismiss()
                    }
                }
                DrawerSection(label("Journal", "Deník"), systemImage: "book.fill") {
                    JournalPanel(game: game)
                }
                DrawerSection(label("Research & building", "Věda a stavby"), systemImage: "lightbulb.fill") {
                    TechBuildPanel(game: game)
                }
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

/// A titled, tappable section of the settlement drawer that folds its panel
/// away until you want it. Collapsed by default, so a long-running colony's
/// controls read as a short list of names — construction, colonists, trade —
/// rather than one endless scroll with everything stacked under everything.
private struct DrawerSection<Content: View>: View {
    let title: String
    let systemImage: String
    @State private var open: Bool
    @ViewBuilder let content: () -> Content

    init(_ title: String, systemImage: String, open: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self._open = State(initialValue: open)
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { open.toggle() }
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: systemImage)
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24)
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textDim)
                        .rotationEffect(.degrees(open ? 0 : -90))
                }
                .padding(.vertical, 13)
                .padding(.horizontal, 15)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
