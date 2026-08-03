import SwiftUI
import EndlessFrontierCore

/// What somebody is carrying, and the one tap that changes it.
///
/// Equipping used to be **item-first**: you opened the Items panel, found the
/// sword, and picked a name out of a menu listing every colonist in the town.
/// At sixty people that menu is a wall, and it is the wrong way round anyway —
/// you decide about a *person* ("this one is going to the wall, give them
/// something"), not about a sword. There was no way at all to equip from the
/// person's own card; the only thing their card could do was take a thing off.
///
/// Three slots, each a button: filled ones offer what is on the shelf plus
/// *take it off*, empty ones offer what is on the shelf. The store is filtered
/// to what actually fits the slot, so nothing in the list is a wrong answer.
struct EquipmentStrip: View {
    let pawn: Pawn
    /// Everything the settlement has spare, already resolved to its definition.
    let store: [(instance: ItemInstance, definition: ItemDefinition)]
    let onEquip: (UUID) -> Void
    let onUnequip: (EquipmentSlot) -> Void
    /// Compact drops the header — for a row in a long list.
    var compact = false

    private var cs: Bool { AppStrings.language == .cs }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !compact {
                Text((cs ? "Výbava" : "Kit").uppercased())
                    .font(.caption2.weight(.bold)).tracking(1)
                    .foregroundStyle(Theme.textDim)
            }
            HStack(spacing: 6) {
                ForEach(EquipmentSlot.allCases, id: \.self) { slot in
                    slotButton(slot)
                }
            }
        }
    }

    private func slotButton(_ slot: EquipmentSlot) -> some View {
        let worn = pawn.equipment[slot]
        let fits = store.filter { $0.definition.equipSlot == slot }
        return Menu {
            if worn != nil {
                Button(role: .destructive) { onUnequip(slot) } label: {
                    Label(cs ? "Sundat" : "Take it off", systemImage: "arrow.down.circle")
                }
            }
            if fits.isEmpty {
                Text(cs ? "Ve skladu nic takového není" : "Nothing in the stores fits")
            } else {
                ForEach(fits, id: \.instance.id) { entry in
                    Button {
                        onEquip(entry.instance.id)
                    } label: {
                        Label(label(for: entry), systemImage: icon(slot))
                    }
                }
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon(slot))
                    .font(.caption)
                Text(wornName(worn) ?? name(slot))
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(worn == nil ? Theme.surfaceInset : Theme.accent.opacity(0.16),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(fits.isEmpty && worn == nil
                                  ? Color.clear : Theme.accent.opacity(0.35), lineWidth: 1))
            .foregroundStyle(worn == nil ? Theme.textDim : tint(worn))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name(slot))
    }

    // MARK: - Words

    private func wornName(_ instance: ItemInstance?) -> String? {
        guard let instance,
              let definition = store.first(where: { $0.instance.id == instance.id })?.definition
                ?? wornDefinition(instance) else { return nil }
        return definition.name.resolve(AppStrings.language)
    }

    /// What is on somebody is *not* in the stores, so its definition has to come
    /// from the lookup the caller hands in rather than from the shelf.
    var definitionOf: (ItemInstance) -> ItemDefinition? = { _ in nil }
    private func wornDefinition(_ instance: ItemInstance) -> ItemDefinition? {
        definitionOf(instance)
    }

    private func label(for entry: (instance: ItemInstance, definition: ItemDefinition)) -> String {
        let quality = entry.instance.quality
        let name = entry.definition.name.resolve(AppStrings.language)
        guard quality != .plain else { return name }
        return "\(name) · \(quality.label.resolve(AppStrings.language))"
    }

    private func tint(_ instance: ItemInstance?) -> Color {
        guard let instance, let def = wornDefinition(instance) else { return Theme.accent }
        return def.rarity.color
    }

    private func name(_ slot: EquipmentSlot) -> String {
        switch slot {
        case .weapon:  return cs ? "Zbraň" : "Weapon"
        case .armor:   return cs ? "Zbroj" : "Armour"
        case .trinket: return cs ? "Drobnost" : "Trinket"
        }
    }

    private func icon(_ slot: EquipmentSlot) -> String {
        switch slot {
        case .weapon:  return "figure.fencing"
        case .armor:   return "shield.lefthalf.filled"
        case .trinket: return "sparkles"
        }
    }
}
