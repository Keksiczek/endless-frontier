import SwiftUI
import EndlessFrontierCore

/// Caravans between settlements: move a resource each tick, and keep outposts
/// connected to the capital (an unconnected settlement loses stability).
struct TradePanel: View {
    @Bindable var game: GameViewModel

    @State private var fromID: UUID?
    @State private var toID: UUID?
    @State private var resource: ResourceType = .food
    @State private var amount: Double = 5

    var body: some View {
        if game.settlements.count > 1 {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Trade Routes")
                ForEach(game.tradeRoutes) { route in
                    routeRow(route)
                }
                creator
            }
            .frontierCard()
        }
    }

    private func routeRow(_ route: TradeRoute) -> some View {
        HStack(spacing: 10) {
            Image(systemName: route.resource.symbolName).foregroundStyle(Theme.accent).frame(width: 20)
            Text("\(game.settlementName(route.fromID)) → \(game.settlementName(route.toID))")
                .font(.subheadline.weight(.medium))
            Spacer()
            Text("\(Int(route.amountPerTick))/tick").font(.caption.monospacedDigit()).foregroundStyle(Theme.textDim)
            Button {
                game.removeTradeRoute(route.id)
            } label: {
                Image(systemName: "trash").font(.caption).foregroundStyle(Theme.danger)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var creator: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                settlementMenu(title: "From", selection: $fromID)
                Image(systemName: "arrow.right").foregroundStyle(Theme.textDim)
                settlementMenu(title: "To", selection: $toID)
            }
            HStack {
                Menu {
                    ForEach(ResourceType.allCases, id: \.self) { r in
                        Button(r.displayName) { resource = r }
                    }
                } label: {
                    chip(label: resource.displayName, icon: resource.symbolName)
                }
                Stepper("\(Int(amount))/tick", value: $amount, in: 1...50, step: 1)
                    .font(.caption)
                Spacer()
                Button("Add") {
                    if let f = resolvedFrom, let t = resolvedTo, f != t {
                        game.addTradeRoute(from: f, to: t, resource: resource, amount: amount)
                    }
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.accent.opacity(0.18), in: Capsule())
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
                .disabled(resolvedFrom == nil || resolvedTo == nil || resolvedFrom == resolvedTo)
            }
        }
    }

    private var resolvedFrom: UUID? { fromID ?? game.settlements.first?.id }
    private var resolvedTo: UUID? { toID ?? game.settlements.dropFirst().first?.id }

    private func settlementMenu(title: String, selection: Binding<UUID?>) -> some View {
        let currentID = selection.wrappedValue ?? (title == "From" ? resolvedFrom : resolvedTo)
        return Menu {
            ForEach(game.settlements) { s in
                Button(s.name) { selection.wrappedValue = s.id }
            }
        } label: {
            chip(label: currentID.map(game.settlementName) ?? title, icon: "building.2.fill")
        }
    }

    private func chip(label: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(label).font(.caption.weight(.medium))
            Image(systemName: "chevron.up.chevron.down").font(.caption2)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.surfaceInset, in: Capsule())
        .foregroundStyle(Theme.text)
    }
}
