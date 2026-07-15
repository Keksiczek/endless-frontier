import SwiftUI
import EndlessFrontierCore

/// The slim always-visible header above the living world: where we are in
/// history (era · year · season), how tense things are, and the capital's
/// stores at a glance.
struct StatusStrip: View {
    @Bindable var game: GameViewModel
    @State private var showDiagnostics = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(AppStrings.eraTitle(game.world.era))
                        .font(.system(.headline, design: .serif).weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text("\(AppStrings.year) \(game.year) · \(seasonLabel)")
                        .font(.caption)
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
                Button {
                    showDiagnostics = true
                } label: {
                    Image(systemName: "stethoscope")
                        .font(.callout)
                        .foregroundStyle(Theme.textDim)
                }
                .accessibilityLabel(AppStrings.language == .cs ? "Diagnostika" : "Diagnostics")
                tensionPip
            }
            resourcePills
        }
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsView(game: game)
                .presentationBackground(Theme.surface)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.boneFaint.opacity(0.3)).frame(height: 1)
        }
    }

    private var seasonLabel: String {
        "\(seasonGlyph) \(AppStrings.seasonName(game.season))"
    }

    private var seasonGlyph: String {
        switch game.season {
        case .spring: return "❀"
        case .summer: return "☀"
        case .autumn: return "❦"
        case .winter: return "❄"
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
                .accessibilityLabel("\(type.displayName) \(Int((game.selectedSettlement?.storage[type] ?? 0).rounded()))")
            }
        }
    }
}
