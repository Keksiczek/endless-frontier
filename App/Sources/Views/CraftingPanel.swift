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
    /// Which recipe groups the player has opened.
    ///
    /// Empty to start, so four hundred recipes arrive as **four lines with
    /// counts on them** rather than as four hundred rows. Keks: *"ten crafting
    /// třeba rozbalovací."* The search and the affordability filter were both
    /// added to make this list survivable and neither of them helps somebody
    /// who does not yet know what they are looking for — a closed group does,
    /// because it says how much is behind it before you commit to scrolling it.
    @State private var openGroups: Set<String> = []

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
                    lyingOut
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
                    craftableToggle
                    let groups = game.recipeGroups
                    if groups.isEmpty {
                        Text(game.onlyCraftable
                             ? (cs ? "Nic z toho teď nejde vyrobit — přepni filtr."
                                   : "None of it can be made right now — clear the filter.")
                             : (cs ? "Nic takového se tu nedělá."
                                   : "Nothing here is made of that."))
                            .font(.caption)
                            .foregroundStyle(Theme.textDim)
                    }
                    // A search has already narrowed things to what was asked
                    // for; making somebody open the answer to their own
                    // question is one tap of pure ceremony.
                    let searching = !game.recipeSearch.trimmingCharacters(in: .whitespaces).isEmpty
                    ForEach(groups, id: \.title) { group in
                        let open = searching || openGroups.contains(group.title)
                        GroupHeader(title: group.title, count: group.recipes.count,
                                    open: open, locked: searching) {
                            withAnimation(.snappy(duration: 0.22)) {
                                if openGroups.contains(group.title) {
                                    openGroups.remove(group.title)
                                } else {
                                    openGroups.insert(group.title)
                                }
                            }
                        }
                        if open {
                            ForEach(group.recipes) { recipe in
                                row(recipe)
                            }
                        }
                    }
                }
            }
            .frontierCard()
        }
    }

    /// **The one control that makes three hundred recipes usable.** Sorting
    /// affordable-first puts the actionable ones at the top of *each* group,
    /// which still means scrolling past every group's tail to find the next.
    private var craftableToggle: some View {
        Button {
            game.onlyCraftable.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: game.onlyCraftable
                      ? "checkmark.circle.fill" : "circle")
                    .font(.caption2)
                Text(cs ? "Jen co teď jde vyrobit" : "Only what can be made now")
                    .font(.caption)
                Spacer(minLength: 0)
            }
            .foregroundStyle(game.onlyCraftable ? Theme.accent : Theme.textDim)
            .padding(.vertical, 7).padding(.horizontal, 10)
            .background(game.onlyCraftable ? Theme.accent.opacity(0.12) : Theme.surfaceInset,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
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
    ///
    /// It is the fold, so the whole line is the target rather than the chevron:
    /// a 10pt glyph is not something to ask a thumb for. `locked` is a search
    /// holding the group open — the chevron goes quiet rather than lying about
    /// being tappable.
    private struct GroupHeader: View {
        let title: String
        let count: Int
        let open: Bool
        var locked: Bool = false
        let toggle: () -> Void

        var body: some View {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(open ? 0 : -90))
                        .foregroundStyle(locked ? Theme.textDim.opacity(0.35) : Theme.accent)
                        .frame(width: 10)
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
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(locked)
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

    /// **What is felled and cut and still lying where it fell.**
    ///
    /// `HaulEngine.waiting` counts it and its doc comment says it is "for the
    /// objective and the ledger to read" — no objective read it and there was
    /// no ledger. A player looking at a store that will not grow has no way to
    /// tell a colony that is producing nothing from one that is producing
    /// plenty and carrying none of it in, and those want opposite answers.
    ///
    /// No threshold on it: the number is shown when it is not zero, because
    /// what counts as too much depends on the size of the colony and nobody
    /// has measured that (rule 23).
    @ViewBuilder
    private var lyingOut: some View {
        if let settlement = game.selectedSettlement {
            let out = HaulEngine.waiting(settlement)
            if out > 0 {
                Label(cs ? "\(out) leží venku, čeká na odnesení"
                         : "\(out) lying out, waiting to be carried in",
                      systemImage: "shippingbox")
                    .font(.caption2)
                    .foregroundStyle(Theme.textDim)
            }
        }
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
            // **Whether you can make it, said in a colour rather than in four
            // per cent of opacity.** The dot beside it is the output's rarity —
            // two different facts that looked like one grey circle.
            Capsule()
                .fill(ready ? Theme.good : Theme.danger.opacity(0.55))
                .frame(width: 3)
            if let rarity = game.recipeOutputRarity(recipe) {
                Circle().fill(rarity.color).frame(width: 10, height: 10)
                    .opacity(ready ? 1 : 0.4)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name.resolve(AppStrings.language))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ready ? Theme.text : Theme.textDim)
                // On its own line rather than beside the name: a chip in the
                // title row squeezes it, and "Forge Hand Mortar" came out over
                // two lines to make room for the thing telling you it was worth
                // making. Same squeeze this session already fixed in
                // `TribesPanel` — a row that reflows to fit an ornament has the
                // ornament in the wrong place.
                upgradeChip(recipe)
                // **What the thing actually is.** A hundred and sixteen weapons
                // whose damage runs 1 to 42, and the row said the name, a
                // rarity dot and what it was made of — the same information
                // about a bone spear and a steel halberd. That is why the list
                // read as enormous rather than merely long.
                if let gear = game.gearLine(recipe) {
                    Label(gear, systemImage: gearIcon(recipe))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(ready ? Theme.accent : Theme.textDim)
                }
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

    /// **The one mark that collapses a long list into a short decision.**
    ///
    /// Better than the best of its kind anybody here is carrying — which is the
    /// only question a player is really asking of a weapon list. Everything
    /// below it is a thing the colony would make and put straight in a
    /// cupboard, and there is no need to say so about two hundred rows: the
    /// absence of the chip is the answer.
    @ViewBuilder
    private func upgradeChip(_ recipe: RecipeDefinition) -> some View {
        if game.isUpgrade(recipe) == true {
            Text(cs ? "lepší než co nosíme" : "beats what we carry")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.good.opacity(0.18), in: Capsule())
                .foregroundStyle(Theme.good)
        }
    }

    /// A weapon, a coat, or something that simply does a thing — a good with a
    /// mood bonus is not armour and should not wear a shield.
    private func gearIcon(_ recipe: RecipeDefinition) -> String {
        switch game.recipeWears(recipe) {
        case .weapon: return "burst.fill"
        case .armor:  return "shield.lefthalf.filled"
        default:      return "sparkles"
        }
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
        // **Short first, and the satisfied stores not at all.**
        //
        // Every row carried a `600/14` chip for the materials it costs, on a
        // colony holding six hundred materials — the same satisfied number
        // repeated down three hundred rows, competing for the eye with the one
        // ingredient that is actually missing. A store you have enough of is
        // not news; a shelf you are three short of is the whole row.
        let short = recipe.materials.filter { game.materialCount($0.key) < $0.value }
        let held = recipe.materials.filter { game.materialCount($0.key) >= $0.value }
        let shortResources = ResourceType.allCases.filter {
            recipe.resourceCost[$0] > 0
                && Int(game.selectedSettlement?.storage[$0] ?? 0) < Int(recipe.resourceCost[$0])
        }
        return FlowRow(spacing: 6) {
            ForEach(short.sorted { $0.key < $1.key }, id: \.key) { material, needed in
                Text("\(game.itemName(material)) \(game.materialCount(material))/\(needed)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.danger)
            }
            ForEach(shortResources, id: \.self) { resource in
                Label("\(Int(game.selectedSettlement?.storage[resource] ?? 0))/\(Int(recipe.resourceCost[resource]))",
                      systemImage: resource.symbolName)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.danger)
            }
            ForEach(held.sorted { $0.key < $1.key }, id: \.key) { material, needed in
                Text("\(game.itemName(material)) \(game.materialCount(material))/\(needed)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textDim)
            }
        }
    }
}

// `FlowRow` used to live here, because the material lists were the only thing
// that needed to wrap. It is in `Components.swift` now: the diplomacy verbs
// need it too, and a shared layout owned by whichever panel happened to want
// it first is how a second panel ends up with its own copy.
