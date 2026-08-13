import SwiftUI
import EndlessFrontierCore

/// Caravans between settlements: move a resource each tick, and keep outposts
/// connected to the capital (an unconnected settlement loses stability).
struct TradePanel: View {
    @Bindable var game: GameViewModel

    @State private var fromID: UUID?
    @State private var toID: UUID?
    @State private var resource: ResourceType = .food
    /// When set, the route carries goods off the stockpile instead of a
    /// resource out of storage.
    @State private var materialID: String?
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
            Text(AppStrings.caravanBlurb)
                .font(.caption2)
                .foregroundStyle(Theme.textDim)
            ForEach(game.caravans) { caravan in
                caravanRow(caravan)
            }
            caravanDispatcher
        }
    }

    /// What happened on the road. A fight out in the country is recorded like
    /// any other battle, but it belongs to the caravan rather than to a
    /// settlement — so it has nowhere to be drawn but here, next to the wagons
    /// it happened to.
    private func ambush(_ battle: BattleLog) -> some View {
        let cs = AppStrings.language == .cs
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: battle.repelled ? "shield.fill" : "burst.fill")
                    .font(.caption2)
                    .foregroundStyle(battle.repelled ? Theme.good : Theme.danger)
                Text(battle.repelled
                     ? (cs ? "Doprovod přepad odrazil" : "The escort beat them off")
                     : (cs ? "Přepadeni na cestě" : "Ambushed on the road"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(battle.repelled ? Theme.good : Theme.danger)
            }
            // The beats, in the order they happened — the same record the
            // settlement canvas animates, read here as a line.
            Text(battle.moments.compactMap { beat(in: $0, cs: cs) }.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func beat(in moment: BattleMoment, cs: Bool) -> String? {
        switch moment.kind {
        case .volley: return cs ? "salva" : "volley"
        case .charge: return cs ? "nápor" : "charge"
        case .clash: return cs ? "střet" : "clash"
        case .repelled: return nil          // already in the headline
        case .plunder: return cs ? "ztraceno \(Int(moment.amount))" : "\(Int(moment.amount)) lost"
        case .wound: return (moment.pawnName ?? "?") + (cs ? " zraněn" : " wounded")
        case .death: return (moment.pawnName ?? "?") + (cs ? " padl" : " killed")
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
            if let battle = caravan.lastBattle { ambush(battle) }
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
                    Section(AppStrings.language == .cs ? "Zdroje" : "Resources") {
                        ForEach(ResourceType.allCases, id: \.self) { r in
                            Button(r.displayName) { resource = r; materialID = nil }
                        }
                    }
                    // Goods move off the stockpile, not out of storage — this is
                    // the only way ore ever reaches a colony that has none.
                    Section(AppStrings.language == .cs ? "Suroviny" : "Materials") {
                        ForEach(game.tradableMaterials, id: \.id) { material in
                            Button(material.name) { materialID = material.id }
                        }
                    }
                } label: {
                    chip(label: materialID.map { game.itemName($0) } ?? resource.displayName,
                         icon: materialID == nil ? resource.symbolName : "shippingbox.fill")
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
            Image(systemName: route.carriesMaterial ? "shippingbox.fill" : route.resource.symbolName)
                .foregroundStyle(route.carriesMaterial ? Theme.good : Theme.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(game.settlementName(route.fromID)) → \(game.settlementName(route.toID))")
                    .font(.subheadline.weight(.medium))
                Text(game.routeCargoName(route))
                    .font(.caption2).foregroundStyle(Theme.textDim)
            }
            Spacer()
            Text("\(Int(route.amountPerTick))\(AppStrings.perTick)").font(.caption.monospacedDigit()).foregroundStyle(Theme.textDim)
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
                    Section(AppStrings.language == .cs ? "Zdroje" : "Resources") {
                        ForEach(ResourceType.allCases, id: \.self) { r in
                            Button(r.displayName) { resource = r; materialID = nil }
                        }
                    }
                    // Goods move off the stockpile, not out of storage — this is
                    // the only way ore ever reaches a colony that has none.
                    Section(AppStrings.language == .cs ? "Suroviny" : "Materials") {
                        ForEach(game.tradableMaterials, id: \.id) { material in
                            Button(material.name) { materialID = material.id }
                        }
                    }
                } label: {
                    chip(label: materialID.map { game.itemName($0) } ?? resource.displayName,
                         icon: materialID == nil ? resource.symbolName : "shippingbox.fill")
                }
                Stepper("\(Int(amount))/tick", value: $amount, in: 1...50, step: 1)
                    .font(.caption)
                Spacer()
                Button(AppStrings.language == .cs ? "Přidat" : "Add") {
                    guard let f = resolvedFrom, let t = resolvedTo, f != t else { return }
                    if let materialID {
                        game.addMaterialRoute(from: f, to: t, materialID: materialID, units: amount)
                    } else {
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
