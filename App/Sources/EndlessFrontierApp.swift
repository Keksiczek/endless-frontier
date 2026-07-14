import SwiftUI

@main
struct EndlessFrontierApp: App {
    @State private var game = GameViewModel.bootstrapped()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(game: game)
                .preferredColorScheme(.dark)
                .task { await game.openSession() }
                .onChange(of: scenePhase) { _, phase in
                    // Re-tick when returning to the foreground. A long absence
                    // is simulated off the main actor so the UI never freezes.
                    if phase == .active {
                        Task { await game.openSession() }
                    }
                }
                .overlay {
                    if game.isCatchingUp { CatchUpOverlay() }
                }
        }
    }
}

/// Shown while a long absence is being simulated — the years pass without you.
private struct CatchUpOverlay: View {
    var body: some View {
        ZStack {
            Theme.ink.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().tint(Theme.accent)
                Text(AppStrings.language == .cs
                     ? "Roky ubíhaly i bez tebe…"
                     : "The years passed without you…")
                    .font(.system(.callout, design: .serif))
                    .foregroundStyle(Theme.text)
            }
        }
        .transition(.opacity)
    }
}
