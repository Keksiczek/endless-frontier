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
    @State private var caravanCargo: Double = 25
    @State private var escort: Int = 1

    var body: some View {
        if game.settlements.count > 1 {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Trade Routes")
                    ForEach(game.tradeRoutes) { route in
                        routeRow(route)
                    }
                    creator
                }
                caravanSection
            }
            .frontierCard()
        }
    }

    // MARK: - Caravans

    private var caravanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Caravans")
            Text("A one-off escorted shipment. Guards travel with the goods, can be ambushed, and settle at the destination.")
                .font(.caption2)
                .foregroundStyle(Theme.textDim)
            ForEach(game.caravans) { caravan in
                caravanRow(caravan)
            }
            caravanDispatcher
        }
    }

    private func caravanRow(_ caravan: Caravan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: caravan.resource.symbolName).foregroundStyle(Theme.accent).frame(width: 20)
                Text("\(game.settlementName(caravan.originID)) → \(game.settlementName(caravan.destinationID))")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Label("\(caravan.guards.count)", systemImage: "shield.lefthalf.filled")
                    .font(.caption2).foregroundStyle(Theme.textDim)
                Text("\(Int(caravan.cargo))").font(.caption.monospacedDigit()).foregroundStyle(Theme.textDim)
            }
            HStack(spacing: 8) {
                ProgressView(value: caravan.progress).tint(statusTint(caravan.status))
                Text(statusLabel(caravan.status))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusTint(caravan.status))
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var caravanDispatcher: some View {
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
                Stepper("\(Int(caravanCargo)) cargo", value: $caravanCargo, in: 5...500, step: 5)
                    .font(.caption)
            }
            HStack {
                Stepper("\(escort) escort", value: $escort, in: 1...maxEscort)
                    .font(.caption)
                Spacer()
                Button("Send") {
                    if let f = resolvedFrom, let t = resolvedTo, f != t {
                        game.dispatchCaravan(from: f, to: t, resource: resource, amount: caravanCargo, guards: escort)
                    }
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(canSend ? Theme.accent.opacity(0.18) : Theme.surfaceInset, in: Capsule())
                .foregroundStyle(canSend ? Theme.accent : Theme.textDim)
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
        }
    }

    private var maxEscort: Int {
        max(1, resolvedFrom.map(game.availableEscort) ?? 1)
    }

    private var canSend: Bool {
        guard let f = resolvedFrom, let t = resolvedTo else { return false }
        return game.canDispatchCaravan(from: f, to: t, resource: resource, amount: caravanCargo, guards: escort)
    }

    private func statusTint(_ status: CaravanStatus) -> Color {
        switch status {
        case .traveling: return Theme.accent
        case .skirmished: return Theme.good
        case .raided: return Theme.danger
        }
    }

    private func statusLabel(_ status: CaravanStatus) -> String {
        switch status {
        case .traveling: return "On the road"
        case .skirmished: return "Ambush repelled"
        case .raided: return "Raided!"
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
