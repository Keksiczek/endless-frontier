import SwiftUI
import EndlessFrontierCore

/// Forge gear from recovered materials. Only currently-craftable recipes show.
struct CraftingPanel: View {
    @Bindable var game: GameViewModel

    var body: some View {
        let recipes = game.availableRecipes
        if recipes.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: craftingTitle)
                ForEach(recipes) { recipe in
                    row(recipe)
                }
            }
            .frontierCard()
        }
    }

    private func row(_ recipe: RecipeDefinition) -> some View {
        HStack(spacing: 12) {
            if let rarity = game.recipeOutputRarity(recipe) {
                Circle().fill(rarity.color).frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(game.recipeOutputName(recipe)).font(.subheadline.weight(.semibold))
                Text(cost(recipe)).font(.caption).foregroundStyle(Theme.textDim)
            }
            Spacer(minLength: 0)
            Button("Forge") { game.craft(recipe.id) }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.accent.opacity(0.18), in: Capsule())
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Crafting draws on the selected settlement's materials; name it when the
    /// player runs more than one settlement.
    private var craftingTitle: String {
        if game.settlements.count > 1, let settlement = game.selectedSettlement {
            return "Crafting — \(settlement.name)"
        }
        return "Crafting"
    }

    private func cost(_ recipe: RecipeDefinition) -> String {
        var parts = recipe.materials.sorted { $0.key < $1.key }.map { "\($0.value)× \(game.itemName($0.key))" }
        parts += ResourceType.allCases
            .filter { recipe.resourceCost[$0] > 0 }
            .map { "\(Int(recipe.resourceCost[$0])) \($0.displayName.lowercased())" }
        return parts.joined(separator: ", ")
    }
}
