import SwiftUI
import EndlessFrontierCore

/// **What is lying on this floor.**
///
/// A store's goods are drawn out of the colony's own stockpile and, until now,
/// answered nothing at all: you could see the grain, count the sacks by eye and
/// not ask what any of it was. Keks: *"ať aspoň můžu danou věc vybrat, pokud
/// tam leží, stejně tak s itemy."*
///
/// It names the kind, what the heap is actually made of — the item ids the
/// colony holds, biggest first — and how much of each. Nothing here writes:
/// tapping a heap asks a question (rule 1).
struct HeapCard: View {
    let kind: SettlementInterior.Goods
    let building: String
    /// What the colony holds of this kind, biggest first: (name, count).
    let holdings: [(name: String, count: Int)]
    let onClose: () -> Void

    private var cs: Bool { AppStrings.language == .cs }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.bone)
                    Text(cs ? "leží v \(building)" : "on the floor of the \(building)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textDim)
                }
                .buttonStyle(.plain)
            }
            if holdings.isEmpty {
                Text(cs ? "Nic, co by se dalo spočítat." : "Nothing worth counting.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(holdings.prefix(5), id: \.name) { line in
                        HStack {
                            Text(line.name)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.bone.opacity(0.9))
                            Spacer()
                            Text("\(line.count)")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surfaceRaised))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.bone.opacity(0.12)))
    }

    private var title: String {
        switch kind {
        case .timber: return cs ? "Dřevo" : "Timber"
        case .stone:  return cs ? "Kámen" : "Stone"
        case .ore:    return cs ? "Ruda a kov" : "Ore and metal"
        case .hide:   return cs ? "Kůže" : "Hides"
        case .cloth:  return cs ? "Látka" : "Cloth"
        case .grain:  return cs ? "Zásoby" : "Stores"
        }
    }
}
