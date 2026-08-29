import Foundation
import EndlessFrontierCore

/// **The bench, as a list a person can use.**
///
/// Three hundred-odd recipes grouped by what comes out of them, folded to one
/// row per thing, sorted by what the colony can act on, searched, and compared
/// against what a colonist is already wearing.
///
/// Lifted out of `GameViewModel` on 2026-08-29, which was 2,534 lines against a
/// stated maximum of 800. §20.4 looked at that file and left it deliberately:
/// splitting a class across files puts its methods in extensions, and `world`
/// is `private(set)` — *file* scope for the setter — so every **mutating**
/// method that moved would force the setter open, and that one modifier is what
/// keeps a view from writing the simulation (rule 1).
///
/// Everything here only ever **reads**, which is why this part could go and the
/// bench's orders (place, cancel, pause) stayed behind. The rule that came out
/// of it: a file splits along what it writes, never along what it is about.
extension GameViewModel {
    var availableRecipes: [RecipeDefinition] {
        CraftingEngine.availableRecipes(world, settlementID: selectedSettlement?.id, registry: registry)
    }


    func recipeOutputRarity(_ recipe: RecipeDefinition) -> ItemRarity? {
        registry.item(recipe.outputItemID)?.rarity
    }

    func itemName(_ id: String) -> String {
        registry.item(id)?.name.resolve(AppStrings.language) ?? id
    }

    /// What the settlement holds of a material, counting both the stockpile and
    /// any loose instances (loot, or a save from before the stockpile existed).
    func materialCount(_ id: String) -> Int {
        guard let s = selectedSettlement else { return 0 }
        return (s.stockpile[id] ?? 0) + s.inventory.count { $0.definitionID == id }
    }

    /// The materials on hand, named and ordered for display. Raw goods first —
    /// they are what the colony's own work produces — then everything made.
    var stockpileEntries: [(id: String, name: String, count: Int, isRaw: Bool)] {
        guard let s = selectedSettlement else { return [] }
        let raw = Set(LocalResourceKind.allCases.compactMap(\.rawMaterialID))
            .union([ResourceLoop.hideItemID])
        var counts = s.stockpile
        for instance in s.inventory where registry.item(instance.definitionID)?.slot == .material {
            counts[instance.definitionID, default: 0] += 1
        }
        return counts
            .filter { $0.value > 0 }
            .map { (id: $0.key, name: itemName($0.key), count: $0.value, isRaw: raw.contains($0.key)) }
            .sorted {
                if $0.isRaw != $1.isRaw { return $0.isRaw }
                return $0.name < $1.name
            }
    }

    /// Recipes this settlement is *equipped* to make — its building and tech
    /// gates are satisfied — whether or not the materials are on hand.
    ///
    /// The panel used to list only what could be crafted right now, so a player
    /// short one ingot saw nothing at all and had no way to learn what the
    /// workshop was for. Showing the shortfall is the whole point.
    var recipesHere: [RecipeDefinition] {
        guard let s = selectedSettlement else { return [] }
        return registry.recipes.values
            .filter { recipe in
                if let building = recipe.requiresBuilding,
                   !s.buildings.contains(where: { $0.definitionID == building }) { return false }
                if let tech = recipe.requiresTech, !world.researchedTechs.contains(tech) { return false }
                return true
            }
            .sorted { $0.name.resolve(AppStrings.language) < $1.name.resolve(AppStrings.language) }
    }

    /// **The bench, in an order a person can use.**
    ///
    /// Three hundred and eleven recipes in one flat alphabetical list is a
    /// wall: the thing you want is never near the top, and nothing tells you
    /// which of them you could make right now. So:
    ///
    /// - **grouped by what comes out** — arms, armour, trinkets, materials —
    ///   because a player opens this panel wanting a *kind* of thing;
    /// - **what you can afford first** inside each group, since a recipe you
    ///   can act on is worth more than one you cannot;
    /// - and a **search** that, while it is in use, collapses the groups into
    ///   one flat list worst-first. Grouping is for browsing, and a search is
    ///   not browsing — the same reasoning as the colonists panel (§9.8).
    /// Show only what the colony could put on the bench this moment.
    ///
    var recipeGroups: [(title: String, recipes: [RecipeDefinition])] {
        let query = recipeSearch.trimmingCharacters(in: .whitespaces).lowercased()
        let all = onlyCraftable ? recipesHere.filter(canCraft) : recipesHere
        guard query.isEmpty else {
            let hits = all.filter { recipe in
                recipe.name.resolve(AppStrings.language).lowercased().contains(query)
                    || recipe.outputItemID.contains(query)
                    || recipe.materials.keys.contains { $0.contains(query) }
            }
            return hits.isEmpty ? [] : [(searchTitle, byAffordability(hits))]
        }
        var buckets: [(String, [RecipeDefinition])] = []
        for group in RecipeGroup.allCases {
            let members = all.filter { group.contains($0, registry: registry) }
            guard !members.isEmpty else { continue }
            buckets.append((group.title, byAffordability(oneRoutePerThing(members))))
        }
        return buckets
    }

    /// **One row per thing you can make**, not one per way of making it.
    ///
    /// Measured over the shipped book: 240 of the 420 recipes make something
    /// another recipe already makes — 107 items have two or more routes, and 79
    /// of those have them in the *same age*, so the panel showed "Sew Hide
    /// Vest" directly above "Stitch Hide Vest" and left the player to work out
    /// they were the same garment. Folding on the output takes the first age's
    /// list from 212 rows to 151 and the whole book from 420 to 287, and it
    /// throws no content away: the route shown is simply the one the colony
    /// would actually take.
    ///
    /// Deliberately not applied to a search. Somebody typing a recipe's name
    /// is asking for that recipe, and a fold that answers with its sibling is
    /// a search that lies.
    private func oneRoutePerThing(_ recipes: [RecipeDefinition]) -> [RecipeDefinition] {
        var best: [String: RecipeDefinition] = [:]
        for recipe in recipes {
            guard let standing = best[recipe.outputItemID] else {
                best[recipe.outputItemID] = recipe
                continue
            }
            if prefer(recipe, over: standing) { best[recipe.outputItemID] = recipe }
        }
        return Array(best.values)
    }

    /// Which of two ways to the same thing the bench should be offered.
    ///
    /// What the colony can do now beats what it cannot; after that the cheaper
    /// one, counted in everything it spends. The id breaks the tie so the row
    /// does not swap under a thumb when a hauler drops off an ingot.
    private func prefer(_ a: RecipeDefinition, over b: RecipeDefinition) -> Bool {
        let (ca, cb) = (canCraft(a), canCraft(b))
        if ca != cb { return ca }
        let (pa, pb) = (price(of: a), price(of: b))
        if pa != pb { return pa < pb }
        return a.id < b.id
    }

    /// Everything a recipe spends, in one number — materials off the shelf
    /// count for more than the generic cost, because they are the half a colony
    /// actually runs out of.
    private func price(of recipe: RecipeDefinition) -> Double {
        // `allCases` rather than the dictionary's own order: a sum walked in a
        // hash order rounds differently on a replay, and a row that swaps for
        // that reason is rule 85 in a list (`AssemblyEngine` paid for it once).
        let spent = ResourceType.allCases.reduce(0.0) { $0 + recipe.resourceCost[$1] }
        return spent + 5 * Double(recipe.materials.values.reduce(0, +))
    }

    /// How many ways the colony knows to make this thing right now. One is the
    /// ordinary answer and the row says nothing; more, and the row says so, or
    /// the fold above would look like missing content.
    func waysToMake(_ recipe: RecipeDefinition) -> Int {
        recipesHere.count { $0.outputItemID == recipe.outputItemID }
    }

    private var searchTitle: String {
        AppStrings.language == .cs ? "Nalezeno" : "Found"
    }

    /// Affordable first, then alphabetically. Stable, so the list does not
    /// reshuffle under a thumb every time a hauler drops off an ingot.
    /// Affordable first, then **best first** — not alphabetical.
    ///
    /// Alphabetical order is the right answer for a list you are scanning for a
    /// name you already know, and the wrong one for a hundred and sixteen
    /// weapons whose damage runs 1 to 42. Nobody hunts for "Bone Spear"; they
    /// want the best thing they can make right now, and sorted by worth that is
    /// the first row. `QuartermasterEngine.worth` is the game's own ranking —
    /// the same one the quartermaster hands gear out by — so the panel and the
    /// colony agree about what is good.
    ///
    /// Ties fall back to the name, so the order is still stable and still
    /// readable for the goods and materials that have no worth to speak of.
    private func byAffordability(_ recipes: [RecipeDefinition]) -> [RecipeDefinition] {
        recipes.sorted { a, b in
            let (ca, cb) = (canCraft(a), canCraft(b))
            if ca != cb { return ca }
            let (wa, wb) = (worth(of: a), worth(of: b))
            if wa != wb { return wa > wb }
            return a.name.resolve(AppStrings.language) < b.name.resolve(AppStrings.language)
        }
    }

    /// What the game reckons a recipe's output is worth.
    func worth(of recipe: RecipeDefinition) -> Double {
        guard let item = registry.item(recipe.outputItemID) else { return 0 }
        return QuartermasterEngine.worth(of: item)
    }

    /// **The best of this kind anybody here is already carrying.**
    ///
    /// The one fact that collapses a hundred and sixteen weapons into the three
    /// that matter: a recipe worth less than this is a thing the colony would
    /// make and immediately put in a cupboard.
    func bestCarriedWorth(_ slot: EquipmentSlot) -> Double {
        guard let settlement = selectedSettlement else { return 0 }
        return settlement.pawns.reduce(0.0) { best, pawn in
            guard let piece = pawn.equipment[slot],
                  let item = registry.item(piece.definitionID) else { return best }
            return max(best, QuartermasterEngine.worth(of: item))
        }
    }

    /// Which slot the recipe's output goes into, if any.
    func recipeWears(_ recipe: RecipeDefinition) -> EquipmentSlot? {
        registry.item(recipe.outputItemID)?.equipSlot
    }

    /// Whether making this would actually arm somebody better than they are
    /// armed now. Nil when the recipe makes something nobody wears.
    func isUpgrade(_ recipe: RecipeDefinition) -> Bool? {
        guard let item = registry.item(recipe.outputItemID),
              let slot = item.equipSlot else { return nil }
        return QuartermasterEngine.worth(of: item) > bestCarriedWorth(slot)
    }

    /// What a piece of gear actually does, in one short line — damage and class
    /// for arms, what it is made of and how much of a person is inside it for
    /// armour. The row showed a name, a rarity dot and an ingredient list, and
    /// none of the three says whether the thing is any good.
    /// …**and why it sorts where it does.** The list is ordered by
    /// `QuartermasterEngine.worth`, which counts a skill bonus at three damage
    /// apiece — so a hunting bow at 5 outranks a bronze spear at 6, and without
    /// the bonus on the line that order looks arbitrary. A number the player
    /// can see beside an order they cannot explain is worse than neither.
    func gearLine(_ recipe: RecipeDefinition) -> String? {
        guard let item = registry.item(recipe.outputItemID) else { return nil }
        let cs = AppStrings.language == .cs
        var parts: [String] = []
        if let combat = item.combat, item.equipSlot == .weapon {
            let kind = combat.kind == .ranged ? (cs ? "střelná" : "ranged")
                                              : (cs ? "na blízko" : "melee")
            parts.append("\(Int(combat.damage)) \(cs ? "zranění" : "damage") · \(kind)")
        } else if let armour = item.armour {
            parts.append(armourMaterialName(armour.material))
            parts.append(coverageName(armour.coverage))
            if armour.helm { parts.append(cs ? "s přilbou" : "with a helm") }
        }
        let effects = ItemFormatting.summary(item)
        if !effects.isEmpty { parts.append(effects) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func armourMaterialName(_ material: ArmourProfile.Material) -> String {
        let cs = AppStrings.language == .cs
        switch material {
        case .cloth:     return cs ? "látka" : "cloth"
        case .hide:      return cs ? "kůže" : "hide"
        case .leather:   return cs ? "vydělaná kůže" : "leather"
        case .wood:      return cs ? "dřevo" : "wood"
        case .bone:      return cs ? "kost" : "bone"
        case .bronze:    return cs ? "bronz" : "bronze"
        case .mail:      return cs ? "kroužky" : "mail"
        case .plate:     return cs ? "plát" : "plate"
        case .composite: return cs ? "kompozit" : "composite"
        case .powered:   return cs ? "poháněná" : "powered"
        }
    }

    private func coverageName(_ coverage: ArmourProfile.Coverage) -> String {
        let cs = AppStrings.language == .cs
        switch coverage {
        case .torso:     return cs ? "trup" : "torso"
        case .torsoArms: return cs ? "trup a paže" : "torso and arms"
        case .full:      return cs ? "celé tělo" : "head to foot"
        case .head:      return cs ? "hlava" : "head"
        case .mantle:    return cs ? "plášť" : "a mantle"
        }
    }

    /// What a recipe makes, as one of the four things a player comes here for.
    /// Read off the *output item*, so a recipe cannot end up in a group that
    /// disagrees with what it produces.
    enum RecipeGroup: CaseIterable {
        case arms, armour, goods, materials

        func contains(_ recipe: RecipeDefinition, registry: GameDataRegistry) -> Bool {
            guard let item = registry.item(recipe.outputItemID) else { return self == .goods }
            switch self {
            case .arms:      return item.equipSlot == .weapon
            case .armour:    return item.equipSlot == .armor
            case .materials: return item.slot == .material
            case .goods:     return item.equipSlot != .weapon && item.equipSlot != .armor
                                  && item.slot != .material
            }
        }

        var title: String {
            let cs = AppStrings.language == .cs
            switch self {
            case .arms:      return cs ? "Zbraně" : "Arms"
            case .armour:    return cs ? "Zbroj" : "Armour"
            case .goods:     return cs ? "Zboží" : "Goods"
            case .materials: return cs ? "Materiál" : "Materials"
            }
        }
    }

    /// Whether everything a recipe needs is on hand at the selected settlement.
    func canCraft(_ recipe: RecipeDefinition) -> Bool {
        CraftingEngine.canCraft(recipe, in: world,
                                settlementID: selectedSettlement?.id, registry: registry)
    }
}
