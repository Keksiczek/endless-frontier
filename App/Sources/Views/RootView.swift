import SwiftUI

/// V2 navigation: the living Settlement is home, with the World map, the
/// Council, the Chronicle and the Science tree alongside. Adding a tab is a
/// single entry here, so the shell grows with the game.
struct RootView: View {
    @Bindable var game: GameViewModel

    var body: some View {
        TabView {
            SettlementScreen(game: game)
                .tabItem { Label(AppStrings.tabSettlement, systemImage: "house.lodge.fill") }

            WorldMapScreen(game: game)
                .tabItem { Label(AppStrings.tabWorld, systemImage: "map.fill") }

            CouncilScreen(game: game)
                .tabItem { Label(AppStrings.tabCouncil, systemImage: "person.3.fill") }
                // A motion awaiting your word shouldn't be missable.
                .badge(game.pendingProposal == nil ? 0 : 1)

            ChronicleScreen(game: game)
                .tabItem { Label(AppStrings.tabChronicle, systemImage: "book.fill") }

            TechTreeView(game: game)
                .tabItem { Label(AppStrings.tabScience, systemImage: "lightbulb.fill") }
        }
        .tint(Theme.accent)
    }
}
