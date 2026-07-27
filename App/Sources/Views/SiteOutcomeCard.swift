import SwiftUI
import EndlessFrontierCore

/// What an expedition found, shown over the ground it found it on.
///
/// This used to be a bare `.alert("Site Explored")` with a Continue button and
/// a paragraph of text — hardcoded English, no picture, and no connection to
/// the place. The living survey of a region (`RegionCanvasView`) was already
/// built and already reachable from the world map; the outcome just never used
/// it. Now exploring a site opens the survey of that country with this card
/// over it, so a find is somewhere you look at rather than a dialog you dismiss.
struct SiteOutcomeCard: View {
    let outcome: SiteOutcome
    var onClose: () -> Void

    private var cs: Bool { AppStrings.language == .cs }
    private func s(_ en: String, _ cz: String) -> String { cs ? cz : en }

    private var title: String {
        if outcome.died { return s("They did not all come back", "Ne všichni se vrátili") }
        if outcome.casualtyName != nil { return s("A hard find", "Draze zaplacený nález") }
        return s("The expedition found something", "Výprava něco našla")
    }

    private var tint: Color {
        outcome.died ? Theme.danger
            : (outcome.casualtyName != nil ? Theme.accent : Theme.good)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: outcome.died ? "exclamationmark.triangle.fill" : "sparkle.magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text(outcome.regionName)
                        .font(.caption2)
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
            }

            Text(outcome.narrative)
                .font(.caption)
                .foregroundStyle(Theme.text.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            // What it actually came to, rather than only how it read.
            let haul = ResourceType.allCases.filter { outcome.rewards[$0] > 0 }
            if !haul.isEmpty || outcome.itemFound != nil {
                HStack(spacing: 10) {
                    ForEach(haul, id: \.self) { resource in
                        Label("\(Int(outcome.rewards[resource]))",
                              systemImage: resource.symbolName)
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.good)
                    }
                    if let item = outcome.itemFound {
                        Label(item, systemImage: "shippingbox.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                    }
                }
            }
            if let casualty = outcome.casualtyName {
                Label(outcome.died
                      ? s("\(casualty) did not come home.", "\(casualty) se nevrátil.")
                      : s("\(casualty) was hurt.", "\(casualty) je zraněný."),
                      systemImage: "cross.case.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.danger)
            }
            if outcome.threatGain > 0 {
                Label(s("Something out there took notice.",
                        "Něco tam venku si toho všimlo."),
                      systemImage: "eye.trianglebadge.exclamationmark.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.danger)
            }

            Button(action: onClose) {
                Text(s("Close", "Zavřít"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(Theme.boneFaint.opacity(0.35), lineWidth: 1))
    }
}
