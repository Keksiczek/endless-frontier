import SwiftUI
import UserNotifications
import EndlessFrontierCore

/// The settings sheet. Small on purpose: this is a game you mostly watch, so
/// the only thing here is the one irreversible act — starting over — plus where
/// you are in the world you already have.
struct SettingsView: View {
    @Bindable var game: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingNewGame = false
    @State private var language: GameLanguage? = AppStrings.languageOverride
    /// What iOS currently thinks about letting the colony reach you.
    @State private var notifications: UNAuthorizationStatus = .notDetermined

    private var cs: Bool { AppStrings.language == .cs }

    /// **Sound.** Every noise the game makes is generated — filtered noise for
    /// wind and rain, partials for a bell — so there is nothing to download and
    /// nothing to keep in sync with a licence file. The one thing a player
    /// needs from Settings is how loud it is and whether it happens at all.
    @AppStorage("audio.enabled") private var audioEnabled = true
    @AppStorage("audio.volume") private var audioVolume = 0.7

    private var soundCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: cs ? "Zvuk" : "Sound")
            Toggle(isOn: $audioEnabled) {
                Text(cs ? "Zvuky osady" : "Colony sound")
                    .font(.callout)
                    .foregroundStyle(Theme.text)
            }
            .tint(Theme.accent)
            .onChange(of: audioEnabled) { _, on in AudioEngine.shared.enabled = on }
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.caption2).foregroundStyle(Theme.textDim)
                Slider(value: $audioVolume, in: 0...1)
                    .tint(Theme.accent)
                    .disabled(!audioEnabled)
                    .onChange(of: audioVolume) { _, level in AudioEngine.shared.volume = level }
                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption2).foregroundStyle(Theme.textDim)
            }
            Text(cs
                 ? "Vítr, déšť, cvrčci, oheň a ruch vsi se řídí ročním obdobím, počasím a tím, kolik lidí je vzhůru. Hra respektuje vypínač zvuku a nepřeruší, co posloucháš."
                 : "Wind, rain, crickets, fire and the murmur of the village follow the season, the sky and how many people are up. The game respects the silent switch and will not stop what you are already listening to.")
                .font(.caption).foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frontierCard()
    }

    /// The game's content is bilingual but was chosen purely by device locale,
    /// so a Czech player on an English phone had no way to reach the Czech —
    /// it was written, shipped, and unreachable.
    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: AppStrings.languageTitle)
            Picker(AppStrings.languageTitle, selection: $language) {
                Text(AppStrings.languageSystem).tag(GameLanguage?.none)
                ForEach(GameLanguage.allCases, id: \.self) { option in
                    Text(AppStrings.languageName(option)).tag(GameLanguage?.some(option))
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: language) { _, chosen in AppStrings.languageOverride = chosen }
            Text(AppStrings.languageBlurb)
                .font(.caption).foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frontierCard()
    }

    /// Whether the colony can reach the player, and what to do about it.
    ///
    /// Notifications were "arranged for" invisibly: the permission was asked
    /// for at a moment the player never saw, and if iOS had ever recorded a
    /// refusal — which it does silently and for ever — nothing would arrive and
    /// there was no way to find that out from inside the game. A permission you
    /// cannot see the state of is a permission you cannot debug.
    private var notificationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: cs ? "Zprávy z osady" : "Word from the colony")
            HStack(spacing: 8) {
                Image(systemName: notificationIcon)
                    .foregroundStyle(notificationTint)
                Text(notificationStatus)
                    .font(.callout)
                    .foregroundStyle(Theme.text)
            }
            Text(notificationBlurb)
                .font(.caption).foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            switch notifications {
            case .notDetermined:
                Button(cs ? "Povolit zprávy" : "Allow messages") {
                    Task {
                        _ = try? await UNUserNotificationCenter.current()
                            .requestAuthorization(options: [.alert, .sound, .badge])
                        await refreshNotificationStatus()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            case .denied:
                Button(cs ? "Otevřít Nastavení" : "Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.bordered)
            default:
                EmptyView()
            }
        }
        .frontierCard()
        .task { await refreshNotificationStatus() }
    }

    private func refreshNotificationStatus() async {
        notifications = await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus
    }

    private var notificationStatus: String {
        switch notifications {
        case .authorized, .provisional, .ephemeral:
            return cs ? "Zapnuté" : "On"
        case .denied:
            return cs ? "Zakázané v Nastavení" : "Refused in Settings"
        default:
            return cs ? "Zatím nepovolené" : "Not asked yet"
        }
    }

    private var notificationIcon: String {
        switch notifications {
        case .authorized, .provisional, .ephemeral: return "bell.fill"
        case .denied: return "bell.slash.fill"
        default: return "bell.badge"
        }
    }

    private var notificationTint: Color {
        switch notifications {
        case .authorized, .provisional, .ephemeral: return Theme.good
        case .denied: return Theme.danger
        default: return Theme.accent
        }
    }

    private var notificationBlurb: String {
        switch notifications {
        case .authorized, .provisional, .ephemeral:
            return cs
                ? "Osada ti dá vědět, když bude na tobě rozhodnutí nebo když půjde do tuhého. Nanejvýš třikrát za jednu nepřítomnost."
                : "The colony will tell you when a decision is waiting or something is going wrong. At most three times per absence."
        case .denied:
            return cs
                ? "iOS to má zakázané. Zapnout to jde jen v Nastavení — hra se znovu zeptat nesmí."
                : "iOS has this refused. Only Settings can turn it back on — the game is not allowed to ask again."
        default:
            return cs
                ? "Hra se ještě neptala. Bez povolení nepřijde nic."
                : "The game has not asked yet. Nothing arrives without it."
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    soundCard
                    languageCard
                    notificationCard
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
