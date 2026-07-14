import SwiftUI
import EndlessFrontierCore

/// The neighbours: peoples who grew out of your own settlement when colonists
/// walked out. Shows where you stand with each, and the history between you.
struct TribesPanel: View {
    @Bindable var game: GameViewModel

    private var cs: Bool { AppStrings.language == .cs }

    var body: some View {
        if !game.world.tribes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: cs ? "Sousedé" : "Neighbours")
                ForEach(game.world.tribes) { tribe in
                    tribeCard(tribe)
                }
            }
            .frontierCard()
        }
    }

    private func tribeCard(_ tribe: Tribe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tribe.name)
                        .font(.system(.headline, design: .serif))
                    Text("\(Int(tribe.population)) \(cs ? "duší" : "souls")")
                        .font(.caption).foregroundStyle(Theme.textDim)
                }
                Spacer()
                statusPill(tribe.status)
            }

            standingBar(tribe.standing)

            Text(tribe.originStory.resolve(AppStrings.language))
                .font(.caption).italic().foregroundStyle(Theme.textDim)

            let history = historyLine(tribe)
            if !history.isEmpty {
                Text(history)
                    .font(.caption2).foregroundStyle(Theme.textDim)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Relations run −100…100; the bar fills from the middle so hostility reads
    /// as clearly as friendship.
    private func standingBar(_ standing: Double) -> some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let extent = CGFloat(abs(standing) / 100) * half
            ZStack(alignment: .center) {
                Capsule().fill(Theme.surface)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if standing < 0 {
                        Capsule().fill(Theme.danger.opacity(0.8))
                            .frame(width: extent)
                    }
                    if standing >= 0 {
                        Capsule().fill(Theme.good.opacity(0.8))
                            .frame(width: extent)
                            .offset(x: extent / 2)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: geo.size.width, alignment: standing < 0 ? .center : .center)
                Rectangle().fill(Theme.boneFaint).frame(width: 1)
            }
        }
        .frame(height: 6)
    }

    private func statusPill(_ status: DiplomaticStanding) -> some View {
        Text(statusName(status))
            .font(.caption2.weight(.bold)).tracking(0.8)
            .foregroundStyle(statusTint(status))
            .padding(.vertical, 4).padding(.horizontal, 8)
            .background(statusTint(status).opacity(0.14), in: Capsule())
    }

    private func statusName(_ status: DiplomaticStanding) -> String {
        switch status {
        case .allied:   return cs ? "SPOJENCI" : "ALLIED"
        case .friendly: return cs ? "PŘÁTELSKÉ" : "FRIENDLY"
        case .neutral:  return cs ? "NEUTRÁLNÍ" : "NEUTRAL"
        case .tense:    return cs ? "NAPJATÉ" : "TENSE"
        case .war:      return cs ? "VÁLKA" : "WAR"
        }
    }

    private func statusTint(_ status: DiplomaticStanding) -> Color {
        switch status {
        case .allied, .friendly: return Theme.good
        case .neutral: return Theme.textDim
        case .tense: return Theme.accent
        case .war: return Theme.danger
        }
    }

    /// Wars fought, marriages made, colonists lost to them.
    private func historyLine(_ tribe: Tribe) -> String {
        var parts: [String] = []
        if tribe.married { parts.append(cs ? "sňatek rodů" : "houses joined by marriage") }
        if tribe.wars > 0 { parts.append("\(cs ? "válek" : "wars"): \(tribe.wars)") }
        if tribe.defections > 0 {
            parts.append("\(cs ? "přeběhlíků" : "defectors"): \(tribe.defections)")
        }
        return parts.joined(separator: " · ")
    }
}
