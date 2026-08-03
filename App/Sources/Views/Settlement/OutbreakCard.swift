import SwiftUI
import EndlessFrontierCore

/// A sickness going through the colony, and the one order you have against it.
///
/// This sits where the siege card sits, for the same reason: it is happening
/// now, it is happening to you, and it has a clock on it. A raid outranks it —
/// you cannot shut the gates against a warband already inside them — but
/// nothing else does.
///
/// One decision, deliberately. Shutting the gates cuts the spread hard and
/// costs the work of everybody staying in, which is a real trade a player can
/// weigh in a second: how many people are sick, how much grain is in the
/// granary, and how long the winter has left.
struct OutbreakCard: View {
    let outbreak: Outbreak
    let plague: PlagueDefinition
    let population: Int
    /// Names of the worst-off carriers, so it is happening to *people*.
    let worst: [String]
    let onQuarantine: (Bool) -> Void

    private var cs: Bool { AppStrings.language == .cs }

    private var share: Double {
        guard population > 0 else { return 0 }
        return min(1, Double(outbreak.infected.count) / Double(population))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            spread
            gates
            if !worst.isEmpty { theSick }
        }
        .padding(16)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.danger.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "allergens.fill")
                .font(.caption).foregroundStyle(Theme.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text((cs ? "Nemoc" : "Sickness").uppercased())
                    .font(.caption2.weight(.bold)).tracking(1.2)
                    .foregroundStyle(Theme.danger)
                Text(plague.name.resolve(AppStrings.language))
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(outbreak.infected.count)")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.text)
                Text(cs ? "nemocných" : "sick")
                    .font(.caption2).foregroundStyle(Theme.textDim)
            }
        }
    }

    /// How much of the colony has it, and what it has cost so far.
    private var spread: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(cs ? "Rozšíření" : "How far it has got")
                    .font(.caption2).foregroundStyle(Theme.textDim)
                Spacer()
                if outbreak.deaths > 0 {
                    Text(cs ? "\(outbreak.deaths) pohřbených" : "\(outbreak.deaths) buried")
                        .font(.caption2.monospacedDigit()).foregroundStyle(Theme.danger)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceInset)
                    // Who has already had it, behind who has it now: a colony
                    // that has been through it is nearly out the other side,
                    // and the bar should say so.
                    Capsule().fill(Theme.good.opacity(0.35))
                        .frame(width: geo.size.width * recoveredShare)
                    Capsule().fill(Theme.danger)
                        .frame(width: geo.size.width * share)
                }
            }
            .frame(height: 6)
            .animation(.easeOut(duration: 0.4), value: share)
            Text(plague.description.resolve(AppStrings.language))
                .font(.caption2).foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var recoveredShare: Double {
        guard population > 0 else { return 0 }
        return min(1, Double(outbreak.recovered.count) / Double(population))
    }

    /// The decision.
    private var gates: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                onQuarantine(!outbreak.quarantined)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: outbreak.quarantined
                          ? "lock.fill" : "lock.open")
                        .font(.caption)
                    Text(outbreak.quarantined
                         ? (cs ? "Brány zavřené" : "The gates are shut")
                         : (cs ? "Zavřít brány" : "Shut the gates"))
                        .font(.caption.weight(.semibold))
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(outbreak.quarantined ? Theme.accent.opacity(0.22) : Theme.surfaceInset,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .foregroundStyle(outbreak.quarantined ? Theme.accent : Theme.text)
            }
            .buttonStyle(.plain)
            Text(outbreak.quarantined
                 ? (cs
                    ? "Nikdo nechodí ven. Nemoc se skoro nešíří — a práce stojí z poloviny."
                    : "Nobody goes out. It barely spreads — and half the work stops.")
                 : (cs
                    ? "Osada žije dál. Nemoc jde s ní."
                    : "The colony carries on, and so does the sickness."))
                .font(.caption2).foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// It is happening to people, and here are their names.
    private var theSick: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text((cs ? "Nejhůř na tom" : "Worst off").uppercased())
                .font(.caption2.weight(.bold)).tracking(1)
                .foregroundStyle(Theme.textDim)
            Text(worst.joined(separator: ", "))
                .font(.caption2).foregroundStyle(Theme.text.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
