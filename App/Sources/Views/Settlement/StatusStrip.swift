import SwiftUI
import EndlessFrontierCore

/// The slim always-visible header above the living world: where we are in
/// history (era · year · season), how tense things are, and the capital's
/// stores at a glance.
struct StatusStrip: View {
    @Bindable var game: GameViewModel

    /// One sheet, chosen — not two stacked on the same view, which SwiftUI
    /// resolves by honouring one and quietly dropping the other.
    /// Following a store joins this enum rather than adding a second `.sheet`:
    /// the warning above is load-bearing, and a resource carries which one.
    private enum Sheet: Identifiable {
        case diagnostics
        case settings
        /// Which store the player asked to follow. The bar used to state five
        /// numbers and let you follow none of them (§11.24).
        case store(ResourceType)

        var id: String {
            switch self {
            case .diagnostics: return "diagnostics"
            case .settings: return "settings"
            case .store(let resource): return "store-\(resource.rawValue)"
            }
        }
    }
    @State private var sheet: Sheet?

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(AppStrings.eraTitle(game.world.era))
                        .font(.system(.headline, design: .serif).weight(.semibold))
                        .foregroundStyle(Theme.text)
                    HStack(spacing: 4) {
                        Text("\(AppStrings.year) \(game.year) ·")
                        Image(systemName: seasonSymbol)
                            .font(.caption2)
                        Text(AppStrings.seasonName(game.season))
                        thermometer
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
                    .accessibilityElement(children: .combine)
                    yearMood
                    clock
                }
                Spacer()
                Button {
                    sheet = .diagnostics
                } label: {
                    Image(systemName: "stethoscope")
                        .font(.callout)
                        .foregroundStyle(Theme.textDim)
                }
                .accessibilityLabel(AppStrings.language == .cs ? "Diagnostika" : "Diagnostics")
                Button {
                    sheet = .settings
                } label: {
                    Image(systemName: "gearshape")
                        .font(.callout)
                        .foregroundStyle(Theme.textDim)
                }
                .accessibilityLabel(AppStrings.settings)
                pauseButton
                tensionPip
            }
            resourcePills
            pauseBanner
            warBanner
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .diagnostics:
                DiagnosticsView(game: game)
                    .presentationBackground(Theme.surface)
            case .settings:
                SettingsView(game: game)
                    .presentationBackground(Theme.surface)
            case .store(let resource):
                storeSheet(resource)
                    .presentationBackground(Theme.surface)
                    .presentationDetents([.medium])
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.boneFaint.opacity(0.3)).frame(height: 1)
        }
    }

    /// **A war, on the screen the player actually lives on.**
    ///
    /// A war used to be readable in exactly one place — the diplomacy list, six
    /// taps away — while the colony it was being fought against showed nothing
    /// at all. Keks: *"války mi neprojdou propojené nikde, je nevidím, jen v
    /// diplomacii."* This is the line that connects them: who, since when, how
    /// many times they have come, and how many of those the wall turned back.
    @ViewBuilder
    private var warBanner: some View {
        let wars = game.warringTribes
        if !wars.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "flag.2.crossed.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                VStack(alignment: .leading, spacing: 1) {
                    Text(wars.map(\.name).joined(separator: " · "))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.danger)
                    if let war = wars.first?.war {
                        Text(warLine(war))
                            .font(.caption2)
                            .foregroundStyle(Theme.textDim)
                    }
                }
                Spacer()
                Text(AppStrings.language == .cs ? "VÁLKA" : "AT WAR")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.danger, in: Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
        }
    }

    private func warLine(_ war: WarState) -> String {
        let cs = AppStrings.language == .cs
        let years = war.years(now: game.world.tick, ticksPerYear: game.ticksPerYear)
        var parts: [String] = []
        parts.append(cs ? "\(years). rok" : "year \(years + 1)")
        if war.raids > 0 {
            parts.append(cs ? "\(war.raids) nájezdů" : "\(war.raids) raids")
            parts.append(cs ? "\(war.repelled) odraženo" : "\(war.repelled) turned back")
        }
        if war.colonistsLost > 0 {
            parts.append(cs ? "\(war.colonistsLost) padlých" : "\(war.colonistsLost) fallen")
        }
        return parts.joined(separator: " · ")
    }

    /// The chain behind one store, asked of the Core so the card and the
    /// simulation cannot disagree (rule 18).
    @ViewBuilder
    private func storeSheet(_ resource: ResourceType) -> some View {
        if let settlement = game.selectedSettlement {
            ScrollView {
                StoreBreakdownCard(
                    resource: resource,
                    stages: StoreBreakdown.of(resource, in: settlement,
                                              registry: game.registry),
                    capacity: settlement.storageCapacity[resource],
                    onClose: { sheet = nil })
                .padding(16)
            }
        }
    }

    /// The season, as a symbol that is actually in the font.
    ///
    /// Three of the four seasons were typographic ornaments (`❀ ❦ ❄`) and
    /// summer was `☀`, which the system's text face does not carry — so half
    /// the year the header read "Year 121 · ⍰ Summer". A symbol the platform
    /// guarantees beats a pretty character that renders on the machine it was
    /// written on.
    private var seasonSymbol: String {
        switch game.season {
        case .spring: return "camera.macro"
        case .summer: return "sun.max.fill"
        case .autumn: return "leaf.fill"
        case .winter: return "snowflake"
        }
    }

    /// What it is actually like outside, next to the season that causes it.
    ///
    /// A season alone cannot tell you why the colony is freezing: the same
    /// January is −22 on the plains and −35 on the tundra, and until the biome
    /// carried a temperature the two were the same day. Coloured by how far it
    /// is from the band a clothed person is comfortable in, so a glance says
    /// "this is a dangerous day" without reading the number.
    @ViewBuilder
    private var thermometer: some View {
        let degrees = game.temperature
        let tint: Color = degrees < ComfortEngine.comfortLow ? Theme.frost
            : (degrees > ComfortEngine.comfortHigh ? Theme.danger : Theme.textDim)
        Text("· \(Int(degrees.rounded()))°")
            .font(.caption.monospacedDigit())
            .foregroundStyle(tint)
        // What kind of country this is…
        if let word = game.climate.label?.resolve(AppStrings.language) {
            Text(word)
                .font(.caption2)
                .foregroundStyle(tint.opacity(0.85))
        }
    }

    /// **What kind of *year* it is having** — a different fact from the day's
    /// weather, and the one the colony talks about.
    ///
    /// On its own line because it is the longest thing the header ever says:
    /// *"rok, na který se nezapomíná"* is twenty-seven characters, and sharing
    /// the season's row it pushed the whole line over an iPhone's width, broke
    /// it, and left the clock's "N odpočívá" hanging off the end of a row it
    /// was never part of. A header that reflows to fit an ornament has the
    /// ornament in the wrong place — the same lesson `TribesPanel` and the
    /// crafting row both paid for.
    @ViewBuilder
    private var yearMood: some View {
        if let year = game.climate.yearLabel()?.resolve(AppStrings.language) {
            Text(year)
                .font(.caption2.italic())
                .foregroundStyle(Theme.accent.opacity(0.9))
                .lineLimit(1)
        }
    }

    /// **The hour, and what the town is doing in it.**
    ///
    /// The drawn day has always been there — five real minutes, a schedule that
    /// puts people to bed, a sun that sets — and there was nowhere on the screen
    /// that said so. Keks, watching a night: *"klidně i hodiny k tomu, ať je
    /// přehled co se děje a lidé dělají."*
    ///
    /// Its own `TimelineView` at one tick a second: a clock that only moves
    /// every minute of drawn time still has to be *asked*, and the strip is
    /// outside the canvas's animation timeline. One second is far below the
    /// rate anything here changes at and costs a text layout.
    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let time = DayClock.time(at: timeline.date)
            // The valley's sound is handed over on the same beat the clock
            // reads: once a second is far more often than weather changes, and
            // the generator glides between mixes rather than stepping.
            let _ = AudioEngine.shared.apply(game.soundscape(at: time))
            // A raid is not background music.
            let _ = AudioEngine.shared.duckMusic(game.selectedSettlement?.siege != nil)
            let phase = DayClock.phase(at: time, season: game.season)
            let doing = game.selectedSettlement.map {
                DayClock.doing($0, at: time, season: game.season,
                               language: AppStrings.language)
            } ?? []
            // **Two of them, or one, or neither — whichever fits on the row.**
            //
            // At midday the colony is at two things at once ("107 at work · 83
            // resting"), and on a 402pt phone that line is wider than the
            // header: `at work` broke onto a second line and left `· 83
            // resting` hanging beside it, misaligned, on a row it was never
            // part of. `doing` is ordered worst-news-first, so the thing to
            // drop when the row is short is the *last* one.
            ViewThatFits(in: .horizontal) {
                clockRow(time: time, phase: phase, doing: Array(doing.prefix(2)))
                clockRow(time: time, phase: phase, doing: Array(doing.prefix(1)))
                clockRow(time: time, phase: phase, doing: [])
            }
            .foregroundStyle(phase == .night ? Theme.frost.opacity(0.9) : Theme.textDim)
            .accessibilityElement(children: .combine)
        }
    }

    /// One line of the day: the hour, what part of it this is, and what the
    /// colony is at. Built as a function so `ViewThatFits` can offer the same
    /// row with fewer things on it rather than letting SwiftUI wrap it.
    private func clockRow(time: Double, phase: DayClock.Phase,
                          doing: [(count: Int, what: String)]) -> some View {
        HStack(spacing: 4) {
            // At night the symbol is the **moon it actually is** — the phase
            // decides how dark the valley goes, so it is worth being able to
            // read it rather than inferring it from the ground.
            Image(systemName: phase == .night
                  ? MoonPhase.phase(at: time).symbol : phase.symbol)
                .font(.caption2)
            Text(DayClock.clockText(at: time))
                .font(.caption.monospacedDigit())
            Text(phase == .night
                 ? MoonPhase.phase(at: time).name(AppStrings.language)
                 : (AppStrings.language == .cs ? phase.czech : phase.english))
                .font(.caption2)
            // What the colony is at, worst-news-first as `doing` orders it:
            // a fight before a shift, a shift before a nap.
            if let first = doing.first {
                Text("· \(first.count) \(first.what)")
                    .font(.caption2)
            }
            if doing.count > 1 {
                Text("· \(doing[1].count) \(doing[1].what)")
                    .font(.caption2)
                    .foregroundStyle(Theme.textDim.opacity(0.75))
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var tensionPip: some View {
        let t = game.tension
        let tint: Color = t < 40 ? Theme.good : (t < 70 ? Theme.accent : Theme.danger)
        return HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg").font(.caption2)
            Text("\(Int(t.rounded()))")
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.vertical, 5)
        .padding(.horizontal, 9)
        .background(tint.opacity(0.12), in: Capsule())
        .accessibilityLabel("\(AppStrings.tension) \(Int(t.rounded()))")
    }

    /// **Stopping the world.** The game had no pause at all: a decision card
    /// arrived and the colony carried on around it, so reading the three
    /// choices meant the moment had already moved on. Keks: *"věci se dějí ale
    /// ty si řekneš u těch eventů ok stalo se, nijak neovlivním."*
    private var pauseButton: some View {
        Button {
            game.setPaused(!game.isPaused)
        } label: {
            Image(systemName: game.isPaused ? "play.fill" : "pause.fill")
                .font(.callout)
                .foregroundStyle(game.isPaused ? Theme.accent : Theme.textDim)
        }
        .accessibilityLabel(game.isPaused
                            ? (AppStrings.language == .cs ? "Pokračovat" : "Resume")
                            : (AppStrings.language == .cs ? "Pozastavit" : "Pause"))
    }

    /// Why the world is standing still, and the way out of it.
    ///
    /// A pause the player did not ask for has to say what it is waiting on, or
    /// it reads as the game having frozen — which is the complaint this whole
    /// feature came from, pointing the other way.
    @ViewBuilder
    private var pauseBanner: some View {
        if let headline = game.pauseHeadline {
            HStack(spacing: 8) {
                Image(systemName: "pause.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                Text(headline)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 0)
                Button {
                    game.setPaused(false)
                } label: {
                    Text(AppStrings.language == .cs ? "Pokračovat" : "Resume")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Theme.accent.opacity(0.2), in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.accent.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var resourcePills: some View {
        HStack(spacing: 8) {
            ForEach(ResourceType.allCases, id: \.self) { type in
                Button {
                    sheet = .store(type)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: type.symbolName).font(.caption2)
                            .foregroundStyle(Theme.accent)
                        Text("\(Int((game.selectedSettlement?.storage[type] ?? 0).rounded()))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.text)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(type.displayName) \(Int((game.selectedSettlement?.storage[type] ?? 0).rounded()))")
                .accessibilityHint(AppStrings.language == .cs
                                   ? "Ukáže, odkud se bere"
                                   : "Shows where it comes from")
            }
        }
    }
}
