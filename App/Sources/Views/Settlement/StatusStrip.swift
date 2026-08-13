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
                    .accessibilityElement(children: .combine)
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
                tensionPip
            }
            resourcePills
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
        // …and what kind of *year* it is having, which is a different thing and
        // the one the colony talks about. Read off the year alone, so a cold
        // fortnight is not announced as a hard year.
        if let year = game.climate.yearLabel()?.resolve(AppStrings.language) {
            Text(year)
                .font(.caption2.italic())
                .foregroundStyle(Theme.accent.opacity(0.9))
        }
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
