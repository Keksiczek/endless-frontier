import SwiftUI
import EndlessFrontierCore

/// The council chamber: the motion awaiting your word, the leader the assembly
/// chose, the laws in force, and the shape of the society beneath them.
///
/// This is where being the Leader means something — the assembly votes, but you
/// ratify or veto, and overruling them costs you standing.
struct CouncilScreen: View {
    @Bindable var game: GameViewModel

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let proposal = game.pendingProposal {
                        MotionCard(game: game, proposal: proposal)
                    }
                    if let settlement = game.selectedSettlement, !settlement.pawns.isEmpty {
                        leaderCard(settlement)
                        lawsCard(settlement)
                        // How the town is run day to day, above the reports on
                        // how it turned out: the assembly's laws are what the
                        // colony votes for, this is what the Leader decides.
                        StandingOrdersPanel(game: game, settlement: settlement)
                        inequalityCard(settlement)
                        roleDistribution(settlement)
                    } else {
                        Text(cs ? "Zatím zde nikdo nežije." : "No one lives here yet.")
                            .foregroundStyle(Theme.textDim)
                    }
                }
                .padding(20)
            }
        }
        .foregroundStyle(Theme.text)
    }

    private var cs: Bool { AppStrings.language == .cs }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppStrings.tabCouncil)
                .font(.system(.largeTitle, design: .serif).weight(.bold))
            Text(cs ? "Sněm zasedá každých šest let. Poslední slovo máš ty."
                    : "The assembly sits every six years. The last word is yours.")
                .font(.subheadline).foregroundStyle(Theme.textDim)
        }
    }

    // MARK: - Leader

    private func leaderCard(_ settlement: Settlement) -> some View {
        let leader = SocietyEngine.leader(of: settlement)
        return HStack(spacing: 12) {
            Image(systemName: "crown.fill").font(.title3).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(cs ? "Zvolený vůdce" : "Elected leader")
                    .font(.caption).foregroundStyle(Theme.textDim)
                Text(leader?.name ?? (cs ? "Sněm nikoho nezvolil" : "No one elected"))
                    .font(.headline)
            }
            Spacer()
            if let leader {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(AppStrings.roleName(leader.assignedWork))
                        .font(.caption).foregroundStyle(Theme.textDim)
                    Text("\(leader.ageYears(ticksPerYear: game.ticksPerYear)) \(cs ? "let" : "yrs")")
                        .font(.subheadline.monospacedDigit())
                }
            }
        }
        .frontierCard()
    }

    // MARK: - Laws

    private func lawsCard(_ settlement: Settlement) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: cs ? "Platná usnesení" : "Laws in force")
            if settlement.laws.isEmpty {
                Text(cs ? "Sněm zatím nic neschválil." : "The assembly has passed nothing yet.")
                    .font(.callout).foregroundStyle(Theme.textDim)
            } else {
                ForEach(settlement.laws) { law in
                    if let def = game.registry.law(law.definitionID) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(def.name.resolve(AppStrings.language))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(cs ? "do roku" : "until year") \(year(law.expiresTick))")
                                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.textDim)
                            }
                            Text(def.summary.resolve(AppStrings.language))
                                .font(.caption).foregroundStyle(Theme.textDim)
                        }
                        .padding(.vertical, 8).padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surfaceInset,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .frontierCard()
    }

    private func year(_ tick: Int) -> Int {
        Season.year(tick: tick, ticksPerYear: game.ticksPerYear)
    }

    // MARK: - Society

    private func inequalityCard(_ settlement: Settlement) -> some View {
        let split = Dictionary(grouping: settlement.pawns) {
            settlement.society.wealthClass(of: $0.wealth)
        }.mapValues(\.count)
        let gini = settlement.society.gini
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: cs ? "Vrstvy" : "Classes")
                Spacer()
                Text("Gini \(String(format: "%.2f", gini))")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(gini > 0.5 ? Theme.danger : Theme.textDim)
            }
            ForEach(WealthClass.allCases, id: \.self) { cls in
                CountBar(label: AppStrings.wealthClassName(cls), count: split[cls] ?? 0,
                         total: settlement.pawns.count, tint: classTint(cls))
            }
            if gini > 0.5 {
                Label(cs ? "Nerovnost je vysoká — chudina může povstat."
                         : "Inequality is stark — the poor may rise.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(Theme.danger)
            }
            if settlement.society.revolts > 0 {
                Text("\(cs ? "Vzpour" : "Uprisings"): \(settlement.society.revolts)")
                    .font(.caption).foregroundStyle(Theme.textDim)
            }
            if settlement.strikeTicksRemaining > 0 {
                Label(cs ? "Stávka! Sběrači složili nářadí." : "Strike! The gatherers have downed tools.",
                      systemImage: "hand.raised.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.danger)
            }
        }
        .frontierCard()
    }

    private func roleDistribution(_ settlement: Settlement) -> some View {
        let counts = Dictionary(grouping: settlement.pawns.filter { $0.assignedWork != .idle },
                                by: \.assignedWork).mapValues(\.count)
        let ordered = counts.sorted { $0.value > $1.value }
        let maxCount = ordered.first?.value ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: cs ? "Řemesla" : "Trades")
            ForEach(ordered, id: \.key) { work, count in
                CountBar(label: AppStrings.roleName(work), count: count, total: maxCount,
                         tint: Theme.roleShade(work))
            }
        }
        .frontierCard()
    }

    private func classTint(_ cls: WealthClass) -> Color {
        switch cls {
        case .poor: return Theme.boneDim
        case .middle: return Theme.good
        case .wealthy: return Theme.accent
        }
    }
}

/// The motion on the table: what the assembly voted, and the leader's answer.
private struct MotionCard: View {
    @Bindable var game: GameViewModel
    let proposal: LawProposal
    @State private var spendStanding = false

    private var cs: Bool { AppStrings.language == .cs }

    /// Spending standing only means anything when you're going against the
    /// council — agreeing with them costs nothing either way.
    @ViewBuilder
    private var standingToggle: some View {
        let affordable = game.canAfford(influence: game.overruleCost)
        Toggle(isOn: $spendStanding) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(AppStrings.spendStanding) · \(Int(game.overruleCost))")
                    .font(.caption.weight(.semibold))
                Text(AppStrings.spendStandingBlurb)
                    .font(.caption2).foregroundStyle(Theme.textDim)
            }
        }
        .toggleStyle(.switch)
        .tint(Theme.accent)
        .disabled(!affordable)
        .opacity(affordable ? 1 : 0.5)
        .onChange(of: affordable) { _, canPay in
            if !canPay { spendStanding = false }
        }
    }

    var body: some View {
        let def = game.registry.law(proposal.definitionID)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.square.fill").foregroundStyle(Theme.accent)
                Text(cs ? "Sněm žádá tvé slovo" : "The assembly awaits your word")
                    .font(.caption.weight(.bold)).tracking(1.2)
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(def?.name.resolve(AppStrings.language) ?? proposal.definitionID)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                if let summary = def?.summary.resolve(AppStrings.language) {
                    Text(summary).font(.callout).foregroundStyle(Theme.textDim)
                }
            }
            voteTally
            HStack(spacing: 10) {
                Button {
                    game.resolveProposal(approve: false, spendInfluence: spendStanding)
                } label: {
                    Label(cs ? "Vetovat" : "Veto", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.danger)

                Button {
                    game.resolveProposal(approve: true, spendInfluence: spendStanding)
                } label: {
                    Label(cs ? "Schválit" : "Ratify", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            standingToggle
            Text(warning)
                .font(.caption2).foregroundStyle(Theme.textDim)
        }
        .frontierCard()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1)
        )
    }

    /// The vote as a bar — for on the left, against on the right.
    private var voteTally: some View {
        let total = max(1, proposal.votesFor + proposal.votesAgainst)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("\(cs ? "PRO" : "FOR") \(proposal.votesFor)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.good)
                Spacer()
                Text("\(proposal.votesAgainst) \(cs ? "PROTI" : "AGAINST")")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.danger)
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Capsule().fill(Theme.good)
                        .frame(width: geo.size.width * CGFloat(proposal.votesFor) / CGFloat(total))
                    Capsule().fill(Theme.danger.opacity(0.7))
                }
            }
            .frame(height: 6)
        }
    }

    private var warning: String {
        if proposal.councilApproves {
            return cs ? "Sněm je pro. Veto proti jeho vůli tě bude stát přízeň lidu."
                      : "The assembly is in favour. Vetoing against them will cost you standing."
        }
        return cs ? "Sněm je proti. Schválit navzdory jeho vůli tě bude stát přízeň lidu."
                  : "The assembly is against. Ratifying anyway will cost you standing."
    }
}

/// A label with a count and a proportional bar.
struct CountBar: View {
    let label: String
    let count: Int
    let total: Int
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.caption).foregroundStyle(Theme.text)
                .frame(width: 96, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceInset)
                    Capsule().fill(tint.opacity(0.8))
                        .frame(width: geo.size.width * CGFloat(total > 0 ? Double(count) / Double(total) : 0))
                }
            }
            .frame(height: 6)
            Text("\(count)").font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(Theme.textDim).frame(width: 28, alignment: .trailing)
        }
    }
}
