import SwiftUI

@main
struct EndlessFrontierApp: App {
    @State private var game = GameViewModel.bootstrapped()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(game: game)
                .preferredColorScheme(.dark)
                .task { game.openSession() }
                .onChange(of: scenePhase) { _, phase in
                    // Re-tick when returning to the foreground.
                    if phase == .active { game.openSession() }
                }
        }
    }
}
