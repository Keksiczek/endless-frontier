import SwiftUI

@main
struct EndlessFrontierApp: App {
    @State private var game = GameViewModel.bootstrapped()
    @Environment(\.scenePhase) private var scenePhase
    /// When the current session began, so notification permission is asked for
    /// only after the player has actually played rather than on cold launch.
    @State private var sessionStart = Date()
    /// Ticks once a minute, so the permission ask and the queued messages are
    /// revisited while the player is still in front of the game.
    @State private var notificationTick = 0

    var body: some Scene {
        WindowGroup {
            RootView(game: game)
                .preferredColorScheme(.dark)
                .task {
                    await game.openSession()
                    game.startLiveLoop()
                    // Whatever the player left it at last time.
                    AudioEngine.shared.enabled =
                        UserDefaults.standard.object(forKey: "audio.enabled") as? Bool ?? true
                    AudioEngine.shared.volume =
                        UserDefaults.standard.object(forKey: "audio.volume") as? Double ?? 0.7
                    AudioEngine.shared.musicVolume =
                        UserDefaults.standard.object(forKey: "audio.musicVolume") as? Double ?? 0.45
                    AudioEngine.shared.musicEnabled =
                        UserDefaults.standard.object(forKey: "audio.music") as? Bool ?? true
                    AudioEngine.shared.start()
                }
                .task(id: notificationTick) {
                    // The permission sheet has to go up while the game is on
                    // screen — iOS will not present it for a backgrounded app,
                    // which is why asking on the way out meant it was never
                    // shown and nothing was ever queued. So: play for a while,
                    // then get asked, then have the queue armed while you are
                    // still here. Both are best-effort and silent.
                    let played = Date().timeIntervalSince(sessionStart)
                    await NotificationScheduler.requestPermissionIfEarned(sessionLength: played)
                    await NotificationScheduler.arm(game.world, registry: game.registry)
                }
                .onChange(of: scenePhase) { _, phase in
                    // Re-tick when returning to the foreground. A long absence
                    // is simulated off the main actor so the UI never freezes.
                    // While the app is up, the live loop keeps ticks landing.
                    switch phase {
                    case .active:
                        sessionStart = Date()
                        // Nothing already delivered should still be sitting
                        // there for someone who is looking at the game.
                        NotificationScheduler.clearDelivered()
                        Task { await game.openSession() }
                        game.startLiveLoop()
                        AudioEngine.shared.start()
                    default:
                        game.stopLiveLoop()
                        // A game in the background makes no noise, whatever the
                        // audio session would otherwise allow.
                        AudioEngine.shared.stop()
                        // The queue is already armed from the foreground; this
                        // is only a top-up with the state as it stands right
                        // now, and it is fine if the system cuts it short.
                        let world = game.world
                        let registry = game.registry
                        Task { await NotificationScheduler.arm(world, registry: registry) }
                    }
                }
                .task {
                    // A slow heartbeat, so the ask lands once the session has
                    // earned it and the queue never describes a world an hour
                    // out of date.
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(60))
                        notificationTick += 1
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
