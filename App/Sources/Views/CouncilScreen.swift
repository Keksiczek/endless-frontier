import SwiftUI
import EndlessFrontierCore

/// A read-only look at the settlement's society: who does what, and how wealth
/// is spread. Elections, laws and votes arrive in the society phase — this is
/// the window that will grow into the council chamber.
struct CouncilScreen: View {
    @Bindable var game: GameViewModel

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if let settlement = game.selectedSettlement, !settlement.pawns.isEmpty {
                        elder(settlement)
                        roleDistribution(settlement)
                        wealthClasses(settlement)
                    } else {
                        Text(AppStrings.language == .cs ? "Zatím zde nikdo nežije." : "No one lives here yet.")
                            .foregroundStyle(Theme.textDim)
                    }
                    comingSoon
                }
                .padding(20)
            }
        }
        .foregroundStyle(Theme.text)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppStrings.tabCouncil)
                .font(.system(.largeTitle, design: .serif).weight(.bold))
            Text(AppStrings.language == .cs
                 ? "Obraz společnosti tvé osady."
                 : "The shape of your settlement's society.")
                .font(.subheadline).foregroundStyle(Theme.textDim)
        }
    }

    // The eldest adult stands in for the leader until elections exist.
    private func elder(_ settlement: Settlement) -> some View {
        let elder = settlement.pawns.max { $0.age < $1.age }
        return HStack(spacing: 12) {
            Image(systemName: "crown.fill").font(.title3).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppStrings.language == .cs ? "Stařešina" : "Elder")
                    .font(.caption).foregroundStyle(Theme.textDim)
                Text(elder?.name ?? "—")
                    .font(.headline)
            }
            Spacer()
            if let elder {
                Text("\(elder.ageYears(ticksPerYear: game.ticksPerYear)) \(AppStrings.language == .cs ? "let" : "yrs")")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textDim)
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
            SectionHeader(title: AppStrings.language == .cs ? "Řemesla" : "Trades")
            ForEach(ordered, id: \.key) { work, count in
                CountBar(label: AppStrings.roleName(work), count: count, total: maxCount,
                         tint: Theme.roleShade(work))
            }
        }
        .frontierCard()
    }

    private func wealthClasses(_ settlement: Settlement) -> some View {
        let split = Society.classSplit(settlement.pawns)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: AppStrings.language == .cs ? "Vrstvy" : "Classes")
            ForEach(WealthClass.allCases, id: \.self) { cls in
                CountBar(label: AppStrings.wealthClassName(cls), count: split[cls] ?? 0,
                         total: settlement.pawns.count, tint: classTint(cls))
            }
        }
        .frontierCard()
    }

    private var comingSoon: some View {
        HStack(spacing: 10) {
            Image(systemName: "hammer.fill").foregroundStyle(Theme.textDim)
            Text(AppStrings.language == .cs
                 ? "Volby vůdců, zákony a hlasování sněmu přijdou v další fázi."
                 : "Elections, laws and council votes arrive in the next phase.")
                .font(.caption).foregroundStyle(Theme.textDim)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func classTint(_ cls: WealthClass) -> Color {
        switch cls {
        case .poor: return Theme.boneDim
        case .middle: return Theme.good
        case .wealthy: return Theme.accent
        }
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

/// Presentation-side society maths (until the society engine lands).
enum Society {
    /// Splits colonists into poor / middle / wealthy by wealth quantiles,
    /// mirroring the civilisation sim's 40th/85th-percentile bands.
    static func classSplit(_ pawns: [Pawn]) -> [WealthClass: Int] {
        guard !pawns.isEmpty else { return [:] }
        let sorted = pawns.map(\.wealth).sorted()
        let q40 = sorted[Int(Double(sorted.count) * 0.4)]
        let q85 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.85))]
        var split: [WealthClass: Int] = [.poor: 0, .middle: 0, .wealthy: 0]
        for w in pawns.map(\.wealth) {
            if w < q40 { split[.poor, default: 0] += 1 }
            else if w < q85 { split[.middle, default: 0] += 1 }
            else { split[.wealthy, default: 0] += 1 }
        }
        return split
    }
}
