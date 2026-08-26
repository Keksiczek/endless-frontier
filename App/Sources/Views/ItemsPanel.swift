import SwiftUI
import EndlessFrontierCore

extension ItemRarity {
    var color: Color {
        switch self {
        case .common: return Color(white: 0.7)
        case .uncommon: return Color(red: 0.45, green: 0.78, blue: 0.45)
        case .rare: return Color(red: 0.36, green: 0.62, blue: 0.95)
        case .epic: return Color(red: 0.70, green: 0.45, blue: 0.95)
        case .legendary: return Color(red: 0.96, green: 0.66, blue: 0.26)
        }
    }
}

/// Summarises an item's effects as a short readable line.
///
/// **Every line of this was English**, on every item in the game and every row
/// of the crafting panel — `work.rawValue.capitalized` puts an enum case, in
/// English, in the middle of a Czech sentence. The bilingual guard walks
/// `GameData` and this is Swift in a view (rule 91).
enum ItemFormatting {
    static func summary(_ def: ItemDefinition) -> String {
        def.effects.map(line).joined(separator: ", ")
    }

    private static var cs: Bool { AppStrings.language == .cs }

    private static func line(_ effect: ItemEffect) -> String {
        switch effect {
        case let .skillBonus(work, amount):
            return "+\(amount) \(AppStrings.workName(work))"
        case let .moodBonus(amount):
            return "+\(Int(amount)) \(cs ? "nálada" : "mood")"
        case let .healthRegen(amount):
            return "+\(amount.formatted()) \(cs ? "zdraví za takt" : "health a tick")"
        case let .colonyProduction(resource, perTick):
            return cs ? "osadě +\(perTick.formatted()) \(resource.displayName) za takt"
                      : "colony +\(perTick.formatted()) \(resource.displayName) a tick"
        case let .colonyDefense(amount):
            return cs ? "osadě +\(Int(amount)) obrany" : "colony +\(Int(amount)) defence"
        case let .colonyMorale(amount):
            return cs ? "osadě +\(Int(amount)) morálky" : "colony +\(Int(amount)) morale"
        }
    }
}

/// The colony's recovered items: artifacts buff the colony passively;
/// equipment can be assigned to a colonist.
struct ItemsPanel: View {
    @Bindable var game: GameViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Relics & Gear")
            if game.viewedInventory.isEmpty {
                Text(AppStrings.itemsEmpty)
                    .font(.caption).foregroundStyle(Theme.textDim)
            } else {
                ForEach(game.viewedInventory) { instance in
                    if let def = game.itemDefinition(instance) {
                        row(instance, def)
                    }
                }
            }
        }
        .frontierCard()
    }

    private func row(_ instance: ItemInstance, _ def: ItemDefinition) -> some View {
        HStack(spacing: 12) {
            Circle().fill(def.rarity.color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(def.name.resolve(AppStrings.language)).font(.subheadline.weight(.semibold))
                    Text(def.rarity.rawValue.capitalized)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(def.rarity.color)
                    // How well *this one* was made. Rarity says what kind of
                    // thing it is; quality says whose hands it came out of.
                    if instance.quality != .plain {
                        Text(instance.quality.label.resolve(AppStrings.language))
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.qualityTint(instance.quality).opacity(0.18),
                                        in: Capsule())
                            .foregroundStyle(Theme.qualityTint(instance.quality))
                    }
                }
                Text(ItemFormatting.summary(def)).font(.caption).foregroundStyle(Theme.textDim)
            }
            Spacer(minLength: 0)
            trailing(instance, def)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func trailing(_ instance: ItemInstance, _ def: ItemDefinition) -> some View {
        switch def.slot {
        case .material:
            Text(AppStrings.itemMaterial)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.surface, in: Capsule())
                .foregroundStyle(Theme.textDim)
        case .artifact:
            Text(AppStrings.itemActive)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.good.opacity(0.18), in: Capsule())
                .foregroundStyle(Theme.good)
        case .equipment:
            Menu {
                ForEach(game.viewedPawns) { pawn in
                    Button(pawn.name) { game.equip(instance.id, toPawn: pawn.id) }
                }
            } label: {
                Text(AppStrings.itemEquip)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.accent.opacity(0.18), in: Capsule())
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}
