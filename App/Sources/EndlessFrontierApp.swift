import SwiftUI

@main
struct EndlessFrontierApp: App {
    @State private var game = GameViewModel.bootstrapped()
    @Environment(\.scenePhase) private var scenePhase
    /// When the current session began, so notification permission is asked for
    /// only after the player has actually played rather than on cold launch.
    @State private var sessionStart = Date()

    var body: some Scene {
        WindowGroup {
            RootView(game: game)
                .preferredColorScheme(.dark)
                .task {
                    await game.openSession()
                    game.startLiveLoop()
                }
                .onChange(of: scenePhase) { _, phase in
                    // Re-tick when returning to the foreground. A long absence
                    // is simulated off the main actor so the UI never freezes.
                    // While the app is up, the live loop keeps ticks landing.
                    switch phase {
                    case .active:
                        sessionStart = Date()
                        // Whatever was queued was written for a world that has
                        // moved on, and nothing should be waiting for someone
                        // who is already looking at it.
                        NotificationScheduler.clearAll()
                        Task { await game.openSession() }
                        game.startLiveLoop()
                    default:
                        game.stopLiveLoop()
                        // Leaving: ask to be let in if the session earned it,
                        // then lay out what the colony has to say next.
                        let length = Date().timeIntervalSince(sessionStart)
                        let world = game.world
                        let registry = game.registry
                        Task {
                            await NotificationScheduler.requestPermissionIfEarned(
                                sessionLength: length)
                            await NotificationScheduler.scheduleOnLeaving(
                                world, registry: registry)
                        }
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
