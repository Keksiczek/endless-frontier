import SwiftUI
import EndlessFrontierCore

/// The settlement's stores and what its workshops can make of them.
///
/// This used to list only recipes that could be crafted *right now* and showed
/// nothing of what the colony held — so a player one ingot short saw an empty
/// panel and no way to learn why. Meanwhile the colony had begun producing
/// wood, ore, clay and hides every tick with nowhere to see any of it. The pile
/// comes first here, and a recipe you cannot afford still shows, saying which
/// ingredient is short.
struct CraftingPanel: View {
    @Bindable var game: GameViewModel

    private var cs: Bool { AppStrings.language == .cs }

    var body: some View {
        let recipes = game.recipesHere
        let pile = game.stockpileEntries
        if recipes.isEmpty && pile.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if !pile.isEmpty {
                    SectionHeader(title: storesTitle)
                    stores(pile)
                }
                if !recipes.isEmpty {
                    SectionHeader(title: cs ? "Výroba" : "Crafting")
                    ForEach(recipes) { recipe in
                        row(recipe)
                    }
                }
            }
            .frontierCard()
        }
    }

    // MARK: - The pile

    /// Everything on hand, raw goods first. A flow layout so a long list of
    /// materials wraps instead of squeezing.
    private func stores(_ pile: [(id: String, name: String, count: Int, isRaw: Bool)]) -> some View {
        FlowRow(spacing: 6) {
            ForEach(pile, id: \.id) { entry in
                HStack(spacing: 5) {
                    Text(entry.name)
                        .font(.caption2)
                        .foregroundStyle(Theme.textDim)
                    Text("\(entry.count)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(entry.isRaw ? Theme.good : Theme.accent)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.surfaceInset, in: Capsule())
            }
        }
    }

    private var storesTitle: String {
        if game.settlements.count > 1, let settlement = game.selectedSettlement {
            return (cs ? "Sklad — " : "Stores — ") + settlement.name
        }
        return cs ? "Sklad" : "Stores"
    }

    // MARK: - Recipes

    private func row(_ recipe: RecipeDefinition) -> some View {
        let ready = game.canCraft(recipe)
        return HStack(spacing: 12) {
            if let rarity = game.recipeOutputRarity(recipe) {
                Circle().fill(rarity.color).frame(width: 10, height: 10)
                    .opacity(ready ? 1 : 0.4)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name.resolve(AppStrings.language))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ready ? Theme.text : Theme.textDim)
                ingredients(recipe)
            }
            Spacer(minLength: 0)
            Button(cs ? "Vyrobit" : "Forge") { game.craft(recipe.id) }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background((ready ? Theme.accent : Theme.textDim).opacity(0.18), in: Capsule())
                .foregroundStyle(ready ? Theme.accent : Theme.textDim)
                .buttonStyle(.plain)
                .disabled(!ready)
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(ready ? 1 : 0.75)
    }

    /// Each ingredient as held-of-needed, so a blocked recipe names what is
    /// short rather than just refusing.
    private func ingredients(_ recipe: RecipeDefinition) -> some View {
        FlowRow(spacing: 6) {
            ForEach(recipe.materials.sorted { $0.key < $1.key }, id: \.key) { material, needed in
                let held = game.materialCount(material)
                Text("\(game.itemName(material)) \(held)/\(needed)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(held >= needed ? Theme.textDim : Theme.danger)
            }
            ForEach(ResourceType.allCases.filter { recipe.resourceCost[$0] > 0 }, id: \.self) { resource in
                let needed = Int(recipe.resourceCost[resource])
                let held = Int(game.selectedSettlement?.storage[resource] ?? 0)
                Label("\(held)/\(needed)", systemImage: resource.symbolName)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(held >= needed ? Theme.textDim : Theme.danger)
            }
        }
    }
}

/// A wrapping row — SwiftUI has no flow layout before iOS 16's `Layout`, and
/// the material lists here are exactly the case an `HStack` handles badly.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
