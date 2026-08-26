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

            // What the war has cost, while there is one. A tally in the place
            // the war is declared: the panel used to say WAR and then nothing —
            // no beginning, no length, no butcher's bill.
            if let war = tribe.war { warLine(war) }

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
    ///
    /// **They wrap, and they carry their words.** This was an `HStack` of
    /// icon-and-number tiles at `minWidth: 40` plus 16pt of padding — 56pt
    /// apiece, and a people you are at odds with offers eight of them. That is
    /// 504pt of buttons in the ~346pt an iPhone leaves inside the card, so the
    /// row did not merely look cramped: **the last verbs were off the edge of
    /// the screen**, and which ones depended on the standing. Keks: *"je těžké
    /// tam něco vydolovat i když je to docela důležité."* A `FlowRow` wraps
    /// instead of clipping, and once a verb has room it may as well say what it
    /// is — a gift and a demand for tribute were previously two grey glyphs
    /// with a number under each.
    private func actions(_ tribe: Tribe) -> some View {
        FlowRow(spacing: 8) {
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
            // The verb the screen never had. A neighbour dispute that can only
            // ever be waited out is a dispute with one party in it.
            if tribe.war == nil, tribe.standing < 0 {
                action(AppStrings.declareWar, icon: "flag.2.crossed.fill", cost: 0,
                       enabled: true, tint: Theme.danger) {
                    game.declareWar(on: tribe.id)
                }
            }
        }
        .padding(.top, 2)
    }

    /// The war's own line: since when, how often they have come, and what it
    /// has cost both sides.
    private func warLine(_ war: WarState) -> some View {
        let years = war.years(now: game.world.tick, ticksPerYear: game.ticksPerYear)
        var parts: [String] = []
        parts.append(cs ? "válka \(years). rokem" : "at war, year \(years + 1)")
        if war.raids > 0 {
            parts.append(cs ? "\(war.raids) nájezdů, \(war.repelled) odraženo"
                            : "\(war.raids) raids, \(war.repelled) turned back")
        }
        if war.colonistsLost > 0 {
            parts.append(cs ? "\(war.colonistsLost) padlých" : "\(war.colonistsLost) fallen")
        }
        if war.lootLost > 1 {
            parts.append(cs ? "\(Int(war.lootLost)) jídla odneseno"
                            : "\(Int(war.lootLost)) food carried off")
        }
        return HStack(spacing: 6) {
            Image(systemName: "flag.2.crossed.fill").font(.caption2)
            Text(parts.joined(separator: " · ")).font(.caption2)
        }
        .foregroundStyle(Theme.danger)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.danger.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// One act, as a chip that says what it is and what it costs.
    ///
    /// A free act shows no price at all — a `0` beside "Call them home" reads
    /// as a cost that has not been worked out yet rather than as no cost.
    private func action(
        _ label: String, icon: String, cost: Double, enabled: Bool,
        tint: Color = Theme.accent, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption2)
                Text(label)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if cost > 0 {
                    Text("\(Int(cost))")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Theme.ink.opacity(0.35), in: Capsule())
                }
            }
            .fixedSize()
            .padding(.vertical, 7).padding(.horizontal, 10)
            .background((enabled ? tint : Theme.textDim).opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .foregroundStyle(enabled ? tint : Theme.textDim)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(cost > 0
                            ? "\(label), \(Int(cost)) \(cs ? "vlivu" : "influence")"
                            : label)
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
