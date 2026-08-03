import SwiftUI
import EndlessFrontierCore

/// The thing you hold while a raid is happening to you.
///
/// A colony is run by standing orders — that is the whole design of the town
/// screen, and a battle should not suddenly demand that sixty people be told
/// what to do one at a time. So this is deliberately small: one posture for the
/// whole line, and the roster of who is standing in it so you can pull somebody
/// bleeding out of the way.
///
/// It is also honest about the clock. The fight advances whether or not this
/// card is on screen; nothing here decides anything, it only writes an order
/// onto the siege the simulation is already fighting.
struct SiegeCommandCard: View {
    let siege: Siege
    /// The people in the line, resolved to who they are.
    let defenders: [Defender]
    let onPosture: (Siege.Posture) -> Void
    let onToggle: (UUID, Bool) -> Void

    struct Defender: Identifiable {
        let id: UUID
        let name: String
        /// 0…1 of their full health.
        let condition: Double
        let holding: Bool
    }

    private var cs: Bool { AppStrings.language == .cs }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            pressure
            postures
            handHint
            if !defenders.isEmpty { roster }
        }
        .padding(16)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.danger.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(Theme.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text((cs ? "Nájezd" : "Under attack").uppercased())
                    .font(.caption2.weight(.bold)).tracking(1.2)
                    .foregroundStyle(Theme.danger)
                Text(siege.attackerLabel?.resolve(AppStrings.language) ?? siege.attackerName)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            Text("\(siege.standing.count)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.text)
            Image(systemName: "person.2.fill")
                .font(.caption2).foregroundStyle(Theme.textDim)
        }
    }

    /// How much of the assault is left, as a bar that empties — the one number
    /// that says whether the posture you chose is working.
    private var pressure: some View {
        let left = siege.openingStrength > 0
            ? max(0, min(1, siege.strength / siege.openingStrength)) : 0
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(cs ? "Síla útoku" : "The assault")
                    .font(.caption2).foregroundStyle(Theme.textDim)
                Spacer()
                Text("\(Int(left * 100)) %")
                    .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textDim)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceInset)
                    Capsule().fill(Theme.danger)
                        .frame(width: geo.size.width * left)
                }
            }
            .frame(height: 6)
            .animation(.easeOut(duration: 0.4), value: left)
        }
    }

    private var postures: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Siege.Posture.allCases, id: \.self) { posture in
                    Button {
                        onPosture(posture)
                    } label: {
                        Text(posture.label.resolve(AppStrings.language))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                siege.posture == posture
                                    ? Theme.accent.opacity(0.22) : Theme.surfaceInset,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundStyle(siege.posture == posture ? Theme.accent : Theme.textDim)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(siege.posture.note.resolve(AppStrings.language))
                .font(.caption2)
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The one thing the player cannot discover by looking: that a tap on the
    /// canvas is now an order.
    ///
    /// The posture steers the whole line, which is right for a game run by
    /// standing orders. But a colonist has a *place* on the field now, so "I go
    /// somewhere and do something" is a thing the simulation can carry out, and
    /// nothing on screen would otherwise say so.
    private var handHint: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "hand.tap")
                .font(.caption2).foregroundStyle(Theme.accent.opacity(0.85))
            Text(cs
                 ? "Klepni na osadníka, pak na zem nebo na nepřítele — půjde tam."
                 : "Tap a colonist, then the ground or an enemy — they will go.")
                .font(.caption2)
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Who is at the wall, and a tap to take them out of it. The line is who
    /// is *taking* the blows as well as who is dealing them, so pulling the
    /// weakest out moves the next-weakest into the worst place — which is the
    /// decision, not a free save.
    private var roster: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(cs ? "V řadě" : "In the line")
                .font(.caption2.weight(.bold)).tracking(1)
                .foregroundStyle(Theme.textDim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(defenders) { defender in
                        Button {
                            onToggle(defender.id, !defender.holding)
                        } label: {
                            VStack(spacing: 3) {
                                Text(defender.name)
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                                Capsule()
                                    .fill(defender.condition < 0.4 ? Theme.danger : Theme.good)
                                    .frame(width: 34 * max(0.08, defender.condition), height: 3)
                                    .frame(width: 34, alignment: .leading)
                                    .background(Capsule().fill(Theme.surfaceInset))
                            }
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(defender.holding ? Theme.surfaceInset : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(defender.holding
                                                  ? Theme.boneFaint.opacity(0.4)
                                                  : Theme.textDim.opacity(0.25),
                                                  lineWidth: 1))
                            .foregroundStyle(defender.holding ? Theme.text : Theme.textDim)
                            .opacity(defender.holding ? 1 : 0.55)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(label(for: defender)))
                    }
                }
            }
        }
    }

    private func label(for defender: Defender) -> String {
        let where_ = defender.holding
            ? (cs ? "v řadě" : "in the line")
            : (cs ? "stažen z řady" : "pulled out of the line")
        return "\(defender.name), \(where_)"
    }
}
