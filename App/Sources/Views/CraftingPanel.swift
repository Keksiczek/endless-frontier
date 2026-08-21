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
                // What is on the bench comes before what could be: an order in
                // progress is the thing the player is waiting on.
                if !game.craftOrders.isEmpty {
                    SectionHeader(title: cs ? "Na ponku" : "On the bench")
                    ForEach(game.craftOrders) { order in
                        orderRow(order)
                    }
                    crafterLine
                }
                if !recipes.isEmpty {
                    SectionHeader(title: cs ? "Výroba" : "Crafting")
                    // Three hundred and eleven recipes is a wall without this.
                    // See `GameViewModel.recipeGroups`.
                    search
                    let groups = game.recipeGroups
                    if groups.isEmpty {
                        Text(cs ? "Nic takového se tu nedělá."
                                : "Nothing here is made of that.")
                            .font(.caption)
                            .foregroundStyle(Theme.textDim)
                    }
                    ForEach(groups, id: \.title) { group in
                        GroupHeader(title: group.title, count: group.recipes.count)
                        ForEach(group.recipes) { recipe in
                            row(recipe)
                        }
                    }
                }
            }
            .frontierCard()
        }
    }

    /// A field, and a way out of it. Never a magnifying glass on its own — a
    /// search you cannot see the contents of is one you forget you typed in.
    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption2)
                .foregroundStyle(Theme.textDim)
            TextField(cs ? "Hledat recept nebo surovinu" : "Search a recipe or material",
                      text: $game.recipeSearch)
                .font(.caption)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !game.recipeSearch.isEmpty {
                Button {
                    game.recipeSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.textDim)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(cs ? "Zrušit hledání" : "Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.ink.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
    }

    /// Quieter than a `SectionHeader` — these sit *inside* Crafting rather
    /// than beside it, and a second full-weight header would read as a peer.
    private struct GroupHeader: View {
        let title: String
        let count: Int

        var body: some View {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .kerning(0.8)
                    .foregroundStyle(Theme.textDim)
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textDim.opacity(0.7))
                Rectangle()
                    .fill(Theme.textDim.opacity(0.18))
                    .frame(height: 1)
            }
            .padding(.top, 2)
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

    // MARK: - The bench

    /// One thing the colony is making, and how far it has got.
    private func orderRow(_ order: CraftOrder) -> some View {
        let recipe = game.recipe(order.recipeID)
        let fraction = game.craftFraction(order)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe?.name.resolve(AppStrings.language) ?? order.recipeID)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(order.paused ? Theme.textDim : Theme.text)
                    Text(countLine(order))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.textDim)
                }
                Spacer(minLength: 0)
                Button {
                    game.setCraftPaused(order.id, paused: !order.paused)
                } label: {
                    Image(systemName: order.paused ? "play.fill" : "pause.fill")
                        .font(.caption)
                        .frame(width: 30, height: 26)
                        .background(Theme.surfaceInset, in: Capsule())
                        .foregroundStyle(Theme.textDim)
                }
                .buttonStyle(.plain)
                Button {
                    game.cancelCraftOrder(order.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .frame(width: 30, height: 26)
                        .background(Theme.surfaceInset, in: Capsule())
                        .foregroundStyle(Theme.danger)
                }
                .buttonStyle(.plain)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceInset)
                    Capsule().fill(order.paused ? Theme.textDim : Theme.accent)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 4)
            if let blocked = game.craftBlockedReason(order) {
                Label(blocked, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(Theme.danger)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(Theme.surfaceInset.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func countLine(_ order: CraftOrder) -> String {
        guard let wanted = order.wanted else {
            return (cs ? "trvale · hotovo " : "standing order · made ") + "\(order.made)"
        }
        return "\(order.made)/\(wanted)"
    }

    /// Who is actually at the bench. Crafting is work now, and work with nobody
    /// doing it goes nowhere — so the panel says so rather than showing a bar
    /// that never moves.
    @ViewBuilder
    private var crafterLine: some View {
        let hands = game.crafterCount
        Label(
            hands > 0
                ? (cs ? "\(hands) u ponku" : "\(hands) at the bench")
                : (cs ? "Nikdo u ponku — nic se nevyrábí"
                      : "Nobody at the bench — nothing is being made"),
            systemImage: hands > 0 ? "hammer.fill" : "exclamationmark.triangle.fill")
            .font(.caption2)
            .foregroundStyle(hands > 0 ? Theme.textDim : Theme.danger)
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
                Label(game.craftTimeLabel(recipe), systemImage: "hourglass")
                    .font(.caption2).foregroundStyle(Theme.textDim)
            }
            Spacer(minLength: 0)
            // Ordering, not conjuring. The old button made the thing appear out
            // of the stockpile the instant it was pressed, made by nobody; this
            // puts it on a bench for somebody to walk to and work at.
            VStack(spacing: 4) {
                orderButton(recipe, count: 1, label: "+1")
                orderButton(recipe, count: nil,
                            label: cs ? "trvale" : "keep")
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(ready ? 1 : 0.75)
    }

    private func orderButton(_ recipe: RecipeDefinition, count: Int?, label: String) -> some View {
        Button(label) { game.placeCraftOrder(recipe.id, count: count) }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.accent.opacity(0.18), in: Capsule())
            .foregroundStyle(Theme.accent)
            .buttonStyle(.plain)
            .disabled(game.craftOrders.count >= CraftingEngine.maxOrders)
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
