import SwiftUI
import EndlessFrontierCore

/// The settings sheet. Small on purpose: this is a game you mostly watch, so
/// the only thing here is the one irreversible act — starting over — plus where
/// you are in the world you already have.
struct SettingsView: View {
    @Bindable var game: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingNewGame = false

    private var cs: Bool { AppStrings.language == .cs }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    thisWorld
                    newGameCard
                }
                .padding(16)
            }
            .background(Theme.surface)
            .navigationTitle(AppStrings.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.done) { dismiss() }
                }
            }
        }
        .foregroundStyle(Theme.text)
    }

    private var thisWorld: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: cs ? "Tento svět" : "This world")
            row(cs ? "Éra" : "Era", AppStrings.eraTitle(game.world.era))
            row(AppStrings.year, "\(game.year)")
            row(cs ? "Obyvatel" : "Population", "\(Int(game.world.totalPopulation))")
            row(cs ? "Osad" : "Settlements", "\(game.settlements.count)")
            row(cs ? "Semínko" : "Seed", "\(game.world.mapSeed)")
        }
        .frontierCard()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.callout).foregroundStyle(Theme.textDim)
            Spacer()
            Text(value).font(.callout.monospacedDigit()).foregroundStyle(Theme.text)
        }
        .accessibilityElement(children: .combine)
    }

    private var newGameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: AppStrings.newColony)
            Text(AppStrings.startNewGameBlurb)
                .font(.caption)
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
            Button(role: .destructive) {
                confirmingNewGame = true
            } label: {
                Label(AppStrings.startNewGame, systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.danger)
        }
        .frontierCard()
        // A world can be weeks old — this asks before it's gone.
        .confirmationDialog(AppStrings.startNewGame, isPresented: $confirmingNewGame,
                            titleVisibility: .visible) {
            Button(AppStrings.startNewGameConfirm, role: .destructive) {
                game.startNewGame()
                dismiss()
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.startNewGameBlurb)
        }
    }
}
