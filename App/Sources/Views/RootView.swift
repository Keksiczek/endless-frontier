import SwiftUI

/// V2 navigation: the living Settlement is home, with the World map, the
/// Council, the Chronicle and the Science tree alongside. Adding a tab is a
/// single entry here, so the shell grows with the game.
struct RootView: View {
    @Bindable var game: GameViewModel

    var body: some View {
        // The selection is bound so the game can point at things: an objective
        // that says "pick a research project" can put you on the Science tab
        // rather than leaving you to go and find it.
        TabView(selection: $game.tab) {
            SettlementScreen(game: game)
                .tabItem { Label(AppStrings.tabSettlement, systemImage: "house.lodge.fill") }
                .tag(GameViewModel.Tab.settlement)

            WorldMapScreen(game: game)
                .tabItem { Label(AppStrings.tabWorld, systemImage: "map.fill") }
                .tag(GameViewModel.Tab.world)

            CouncilScreen(game: game)
                .tabItem { Label(AppStrings.tabCouncil, systemImage: "person.3.fill") }
                // A motion awaiting your word shouldn't be missable.
                .badge(game.pendingProposal == nil ? 0 : 1)
                .tag(GameViewModel.Tab.council)

            ChronicleScreen(game: game)
                .tabItem { Label(AppStrings.tabChronicle, systemImage: "book.fill") }
                .tag(GameViewModel.Tab.chronicle)

            TechTreeView(game: game)
                .tabItem { Label(AppStrings.tabScience, systemImage: "lightbulb.fill") }
                .tag(GameViewModel.Tab.science)
        }
        .tint(Theme.accent)
    }
}
