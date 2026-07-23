import SwiftUI
import EndlessFrontierCore

/// The offer that appears when the player reaches into the dark: send the
/// scouts *there*, rather than waiting for them to wander that way.
///
/// The fog moves on its own — scouts walk at the nearest unknown ground every
/// outing — but "on its own" is not the same as "yours". This is the lever that
/// makes the edge of the map something the player can point at.
struct ScoutOrderCard: View {
    let scouts: Int
    var onSend: () -> Void
    var onClose: () -> Void

    private var cs: Bool { AppStrings.language == .cs }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cs ? "Neprozkoumaná půda" : "Uncharted ground")
                        .font(.system(.subheadline, design: .serif).weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(scouts > 0 ? Theme.textDim : Theme.danger)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.textDim)
                }
                .accessibilityLabel(cs ? "Zavřít" : "Close")
            }
            Button(action: onSend) {
                Label(cs ? "Poslat zvědy sem" : "Send scouts here", systemImage: "figure.walk.motion")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(scouts == 0)
        }
        .padding(16)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }

    /// An order needs someone to carry it — say so plainly when nobody is on
    /// the job, rather than letting the button fail silently.
    private var statusLine: String {
        guard scouts > 0 else {
            return cs ? "Nikdo nemá průzkum na starosti" : "Nobody is assigned to scouting"
        }
        return cs
            ? "\(scouts) \(scouts == 1 ? "zvěd vyrazí" : scouts < 5 ? "zvědové vyrazí" : "zvědů vyrazí") tímto směrem"
            : "\(scouts) scout\(scouts == 1 ? "" : "s") will head that way"
    }
}
