import SwiftUI
import EndlessFrontierCore

/// Switches which settlement the colony panels (stats, colonists, gear) show.
/// Only appears once you have more than one settlement.
struct SettlementPicker: View {
    @Bindable var game: GameViewModel

    var body: some View {
        if game.settlements.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(game.settlements) { settlement in
                        chip(settlement)
                    }
                }
            }
        }
    }

    private func chip(_ settlement: Settlement) -> some View {
        let selected = (game.selectedSettlement?.id == settlement.id)
        return Button {
            game.selectSettlement(settlement.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon(settlement.kind))
                Text(settlement.name).font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(selected ? Theme.accent.opacity(0.22) : Theme.surfaceInset,
                        in: Capsule())
            .foregroundStyle(selected ? Theme.accent : Theme.textDim)
        }
        .buttonStyle(.plain)
    }

    private func icon(_ kind: SettlementKind) -> String {
        switch kind {
        case .capital: return "crown.fill"
        case .city: return "building.2.fill"
        case .outpost: return "house.lodge.fill"
        }
    }
}
