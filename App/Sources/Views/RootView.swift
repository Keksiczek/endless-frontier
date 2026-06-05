import SwiftUI

/// Top-level navigation: the Colony dashboard and the World map.
struct RootView: View {
    @Bindable var game: GameViewModel

    var body: some View {
        TabView {
            DashboardView(game: game)
                .tabItem { Label("Colony", systemImage: "house.fill") }

            ColonyMapScreen(game: game)
                .tabItem { Label("Base", systemImage: "square.grid.3x3.fill") }

            WorldMapScreen(game: game)
                .tabItem { Label("World", systemImage: "map.fill") }

            TechTreeView(game: game)
                .tabItem { Label("Tech", systemImage: "lightbulb.fill") }
        }
        .tint(Theme.accent)
    }
}
