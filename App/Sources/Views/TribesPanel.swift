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

            actions(tribe)
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// What the Leader can actually *do* about a neighbour.
    ///
    /// The peoples traded, married, raided and took in defectors entirely on
    /// their own, and you could only read about it afterwards. These are the
    /// acts that spend the standing administration charges you for.
    private func actions(_ tribe: Tribe) -> some View {
        HStack(spacing: 8) {
            action(AppStrings.sendGift, icon: "gift.fill", cost: game.giftCost,
                   enabled: game.canAfford(influence: game.giftCost)) {
                game.sendGift(to: tribe.id)
            }
            action(AppStrings.demandTribute, icon: "hand.raised.fill", cost: game.demandCost,
                   enabled: game.canAfford(influence: game.demandCost), tint: Theme.danger) {
                game.demandTribute(from: tribe.id)
            }
            if tribe.status != .allied {
                action(AppStrings.proposePact, icon: "hands.clap.fill", cost: game.pactCost,
                       enabled: game.canProposePact(to: tribe), tint: Theme.good) {
                    game.proposePact(with: tribe.id)
                }
                .help(tribe.standing < 45 ? AppStrings.pactNeedsTrust : "")
            }
            // The one act that leaves something behind. A gift is spent the
            // moment it is given; a road is on the map next year, shortens the
            // journey both ways, and can be torn up by the people it was built
            // for. Absent only when the way already runs all the way to them.
            if let cost = game.roadCost(toward: tribe) {
                action(AppStrings.buildRoadToward, icon: "road.lanes", cost: cost,
                       enabled: game.canBuildRoad(toward: tribe)) {
                    game.buildRoad(toward: tribe.id)
                }
            }
            // An embassy: a named colonist who is *there* and not here. The
            // button becomes the way to call them home once it stands, because
            // the post is a state rather than an act.
            if let posted = game.envoy(toward: tribe) {
                action(AppStrings.recallEnvoy, icon: "person.fill.checkmark", cost: 0,
                       enabled: true, tint: Theme.textDim) {
                    game.recallEnvoy(from: tribe.id)
                }
                .help(posted.name)
            } else {
                action(AppStrings.sendEnvoy, icon: "person.line.dotted.person",
                       cost: game.envoyCost, enabled: game.canSendEnvoy(to: tribe)) {
                    game.sendEnvoy(to: tribe.id)
                }
            }
            // Buying peace. Only offered to a people with something against
            // us — paying somebody who already likes you is a button with no
            // question behind it.
            if game.tribute(to: tribe) > 0 {
                action(AppStrings.stopTribute, icon: "hand.raised.slash", cost: 0,
                       enabled: true, tint: Theme.danger) {
                    game.stopTribute(to: tribe.id)
                }
            } else if tribe.grudge > 40 {
                action(AppStrings.offerTribute, icon: "shippingbox.fill",
                       cost: game.tributeOffer, enabled: true, tint: Theme.textDim) {
                    game.offerTribute(to: tribe.id)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private func action(
        _ label: String, icon: String, cost: Double, enabled: Bool,
        tint: Color = Theme.accent, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.caption)
                Text("\(Int(cost))")
                    .font(.caption2.monospacedDigit().weight(.semibold))
            }
            .frame(minWidth: 40)
            .padding(.vertical, 6).padding(.horizontal, 8)
            .background((enabled ? tint : Theme.textDim).opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .foregroundStyle(enabled ? tint : Theme.textDim)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("\(label), \(Int(cost)) \(cs ? "vlivu" : "influence")")
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
