import SwiftUI
import EndlessFrontierCore

/// How a town of sixty is actually run.
///
/// Every lever the game had was per-person: this colonist's trade, that party's
/// roster, and a famine you answered by opening sixty inspectors one after
/// another. The pawn screen is for *looking at somebody* — how they are, what
/// they carry, who they sleep beside. This is for running the place.
///
/// Three standing orders, and each of them is a decision with a cost:
///
/// - **Trades.** A weight per kind of work. The colony drifts toward it one
///   person at a time over the following seasons rather than re-sorting itself
///   the instant a slider moves — a town that reshuffles on a tap is a
///   spreadsheet, one that visibly changes its mind over a decade is a place.
/// - **Rations.** Short rations stretch the granary and everybody knows it.
/// - **The roster.** Whether an expedition may take hands off the trades you
///   said matter.
struct StandingOrdersPanel: View {
    @Bindable var game: GameViewModel
    let settlement: Settlement

    private var cs: Bool { AppStrings.language == .cs }
    private var policy: ColonyPolicy { settlement.policy }

    /// The trades worth showing an order for: the ones the labour engine
    /// actually staffs. `idle` is not a trade and nobody should be able to
    /// order people into it.
    private static let orderable: [WorkKind] = [
        .farming, .logging, .mining, .building, .research, .hunting,
        .foraging, .scouting, .trade, .healing, .priest, .garrison
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            rationCard
            rosterCard
            tradesCard
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(cs ? "Stálé pokyny" : "Standing orders")
                    .font(.system(.title2, design: .serif).weight(.bold))
                if !policy.isDefault {
                    Text(cs ? "platí" : "in force")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Theme.accent.opacity(0.20), in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
            }
            Text(cs
                 ? "Osada se jimi řídí sama. Nastavíš je jednou a lidé se k nim postupně posunou."
                 : "The colony runs itself by these. Set them once; people drift toward them over the seasons.")
                .font(.footnote).foregroundStyle(Theme.textDim)
        }
    }

    // MARK: - Rations

    private var rationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: cs ? "Dávky" : "Rations")
                Spacer()
                Text(cs ? "zásoby na ~\(game.foodDaysRemaining(settlement)) tahů"
                        : "~\(game.foodDaysRemaining(settlement)) ticks of food")
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.textDim)
            }
            Picker("", selection: Binding(
                get: { policy.ration },
                set: { game.setRation($0) })) {
                    ForEach(ColonyPolicy.Ration.allCases, id: \.self) { ration in
                        Text(ration.label.resolve(AppStrings.language == .cs ? .cs : .en))
                            .tag(ration)
                    }
                }
                .pickerStyle(.segmented)
            Text(policy.ration.detail.resolve(AppStrings.language == .cs ? .cs : .en))
                .font(.footnote).foregroundStyle(Theme.textDim)
            if policy.ration.moodEffect < 0 {
                Label(cs ? "Nálada klesá o \(Int(-policy.ration.moodEffect)) u každého"
                         : "\(Int(-policy.ration.moodEffect)) mood on everybody",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(Theme.danger)
            }
        }
        .frontierCard()
    }

    // MARK: - The roster

    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: cs ? "Kdo smí na výpravu" : "Who may go out")
            Picker("", selection: Binding(
                get: { policy.roster },
                set: { game.setRoster($0) })) {
                    ForEach(ColonyPolicy.Roster.allCases, id: \.self) { roster in
                        Text(roster.label.resolve(AppStrings.language == .cs ? .cs : .en))
                            .tag(roster)
                    }
                }
                .pickerStyle(.segmented)
            Text(rosterDetail).font(.footnote).foregroundStyle(Theme.textDim)
        }
        .frontierCard()
    }

    private var rosterDetail: String {
        switch policy.roster {
        case .anyone:
            return cs ? "Vyrazí ten, kdo se na to nejlíp hodí, ať dělá cokoli."
                      : "Whoever is best suited goes, whatever trade they hold."
        case .spareHands:
            let names = policy.protectedTrades
                .sorted { $0.rawValue < $1.rawValue }
                .map { AppStrings.roleName($0) }
            guard !names.isEmpty else {
                return cs ? "Zatím žádné řemeslo nemá přednost — chová se to jako „kdokoli“."
                          : "No trade has priority yet, so this behaves like “anyone”."
            }
            return cs ? "Přednostní řemesla zůstávají na místě: \(names.joined(separator: ", "))."
                      : "Priority trades stay at their posts: \(names.joined(separator: ", "))."
        case .nobody:
            return cs ? "Osada nikoho neposílá. Místa v kraji zůstanou nedotčená."
                      : "The colony sends nobody. The places out there stay untouched."
        }
    }

    // MARK: - Trades

    private var tradesCard: some View {
        let counts = Dictionary(grouping: settlement.pawns.filter { $0.assignedWork != .idle },
                                by: \.assignedWork).mapValues(\.count)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                SectionHeader(title: cs ? "Řemesla" : "Trades")
                Spacer()
                if !policy.trades.isEmpty {
                    Button(cs ? "Zrušit vše" : "Clear all") {
                        var cleared = policy
                        cleared.trades = [:]
                        game.setPolicy(cleared)
                    }
                    .font(.caption).buttonStyle(.plain).foregroundStyle(Theme.accent)
                }
            }
            ForEach(Self.orderable, id: \.self) { work in
                TradeOrderRow(
                    work: work,
                    held: counts[work] ?? 0,
                    stance: policy.stance(work),
                    onChange: { game.setTrade(work, to: $0) })
                if work != Self.orderable.last { Divider().overlay(Theme.boneFaint.opacity(0.3)) }
            }
        }
        .frontierCard()
    }
}

/// One trade, how many hold it now, and the standing order for it.
private struct TradeOrderRow: View {
    let work: WorkKind
    let held: Int
    let stance: ColonyPolicy.TradeStance
    let onChange: (ColonyPolicy.TradeStance) -> Void

    private var cs: Bool { AppStrings.language == .cs }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.roleShade(work)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(AppStrings.roleName(work)).font(.subheadline)
                Text(cs ? "\(held) teď" : "\(held) now")
                    .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textDim)
            }
            Spacer(minLength: 8)
            Menu {
                ForEach(ColonyPolicy.TradeStance.allCases, id: \.self) { option in
                    Button {
                        onChange(option)
                    } label: {
                        if option == stance {
                            Label(option.label.resolve(cs ? .cs : .en), systemImage: "checkmark")
                        } else {
                            Text(option.label.resolve(cs ? .cs : .en))
                        }
                    }
                }
            } label: {
                Text(stance.label.resolve(cs ? .cs : .en))
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(tint.opacity(0.18), in: Capsule())
                    .foregroundStyle(tint)
            }
            .accessibilityLabel(cs ? "Pokyn pro \(AppStrings.roleName(work))"
                                   : "Standing order for \(AppStrings.roleName(work))")
        }
        .padding(.vertical, 5)
    }

    private var tint: Color {
        switch stance {
        case .off: return Theme.danger
        case .low: return Theme.textDim
        case .normal: return Theme.boneDim
        case .high, .priority: return Theme.accent
        }
    }
}
