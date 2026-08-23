import SwiftUI
import EndlessFrontierCore

/// **Who you are holding, and how far round they have come.**
///
/// `CaptiveEngine` has kept prisoners — a whole `Pawn` each, with a name, an
/// age, a trade and a `trust` that walks from *out the gate the first dark
/// night* to *one of us* — since it was written, and the game said nothing
/// about them until the day one joined the colony. This is the card behind a
/// tap on one of them.
///
/// There is deliberately **no button on it.** What happens to a prisoner is
/// decided by how the colony lives — fed, in good heart, with something to
/// believe in — not by a menu, and inventing an "execute / release" choice
/// here would be a new mechanic rather than a window onto the one that exists.
struct CaptiveCard: View {
    let captive: Captive
    let ticksPerYear: Int
    /// How long they have been held, in years.
    let heldYears: Int
    var onClose: () -> Void

    private var cs: Bool { AppStrings.language == .cs }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(spacing: 10) {
                vital(icon: "figure.stand", label: cs ? "Řemeslo" : "Trade",
                      text: AppStrings.roleName(captive.pawn.assignedWork))
                vital(icon: "hourglass", label: cs ? "Držen" : "Held",
                      text: "\(heldYears) \(cs ? "let" : "yrs")")
                vital(icon: "heart.fill", label: cs ? "Zdraví" : "Health",
                      text: "\(Int(captive.pawn.health))")
            }
            trustBar
            Text(mood)
                .font(.caption)
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: 360)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(tint.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(captive.pawn.name)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(captive.takenFrom.isEmpty
                     ? (cs ? "zajatec" : "a prisoner")
                     : (cs ? "zajat od: \(captive.takenFrom)"
                           : "taken from \(captive.takenFrom)"))
                    .font(.caption)
                    .foregroundStyle(Theme.textDim)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.textDim)
            }
            .buttonStyle(.plain)
        }
    }

    /// −1 out the gate, +1 one of us — the only number about a prisoner that
    /// decides anything.
    private var trustBar: some View {
        let share = min(1, max(0, (captive.trust + 1) / 2))
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(cs ? "DŮVĚRA" : "TRUST")
                    .font(.caption2.weight(.bold)).tracking(1.1)
                    .foregroundStyle(Theme.textDim)
                Spacer()
                Text(standing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceInset)
                    Capsule().fill(tint.opacity(0.85))
                        .frame(width: geo.size.width * share)
                }
            }
            .frame(height: 6)
        }
    }

    private func vital(icon: String, label: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption2).foregroundStyle(Theme.textDim)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundStyle(Theme.textDim)
                Text(text).font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tint: Color {
        switch captive.trust {
        case ..<(-0.3): return Theme.danger
        case ..<0.3: return Theme.textDim
        default: return Theme.good
        }
    }

    private var standing: String {
        switch captive.trust {
        case ..<(-0.6): return cs ? "hledá skulinu" : "looking for a gap"
        case ..<(-0.2): return cs ? "nepřátelský" : "hostile"
        case ..<0.2: return cs ? "ostražitý" : "wary"
        case ..<0.6: return cs ? "obměkčuje se" : "coming round"
        default: return cs ? "skoro jeden z nás" : "almost one of us"
        }
    }

    /// What decides it, said plainly — because the answer to "what do I do
    /// about this" is *run the colony well*, and the card should say so.
    private var mood: String {
        cs
        ? "Jestli zůstane, rozhoduje to, jaké je tu k žití: nasycení lidé, dobrá nálada a víra, do které se dá patřit."
        : "Whether they stay is decided by what this place is like to live in: full bellies, good heart, and something to belong to."
    }
}
