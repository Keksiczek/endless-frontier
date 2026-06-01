import SwiftUI

/// Top-level navigation: the Colony dashboard and the World map.
struct RootView: View {
    @Bindable var game: GameViewModel

    var body: some View {
        TabView {
            DashboardView(game: game)
                .tabItem { Label("Colony", systemImage: "house.fill") }

            WorldMapScreen(game: game)
                .tabItem { Label("World", systemImage: "map.fill") }
        }
        .tint(Theme.accent)
    }
}
