import Foundation

/// Turns materials (and resources) into gear at the capital. Materials are
/// item drops from sites; recipes may require a building and/or a tech.
public enum CraftingEngine {
    /// Recipes the player can craft right now (materials, resources and
    /// requirements all satisfied at the capital).
    public static func availableRecipes(_ state: WorldState, registry: GameDataRegistry) -> [RecipeDefinition] {
        registry.recipes.values
            .filter { canCraft($0, in: state, registry: registry) }
            .sorted { $0.id < $1.id }
    }

    public static func canCraft(_ recipe: RecipeDefinition, in state: WorldState, registry: GameDataRegistry) -> Bool {
        guard let capital = state.settlements.first(where: { $0.kind == .capital }) ?? state.settlements.first else {
            return false
        }
        // Materials on hand.
        let counts = materialCounts(capital)
        for (materialID, needed) in recipe.materials where (counts[materialID] ?? 0) < needed {
            return false
        }
        // Resources on hand.
        for resource in ResourceType.allCases where capital.storage[resource] < recipe.resourceCost[resource] {
            return false
        }
        // Building requirement.
        if let building = recipe.requiresBuilding,
           !capital.buildings.contains(where: { $0.definitionID == building }) {
            return false
        }
        // Tech requirement.
        if let tech = recipe.requiresTech, !state.researchedTechs.contains(tech) {
            return false
        }
        return true
    }

    /// Crafts a recipe: consumes materials + resources, adds the output item to
    /// the capital inventory. Returns unchanged state if it can't be crafted.
    public static func craft(_ state: WorldState, recipeID: String, registry: GameDataRegistry) -> WorldState {
        guard let recipe = registry.recipes[recipeID],
              canCraft(recipe, in: state, registry: registry),
              let capital = state.settlements.firstIndex(where: { $0.kind == .capital })
                ?? state.settlements.indices.first else {
            return state
        }
        var s = state

        // Consume materials.
        for (materialID, needed) in recipe.materials {
            var removed = 0
            s.settlements[capital].inventory.removeAll { instance in
                guard removed < needed, instance.definitionID == materialID else { return false }
                removed += 1
                return true
            }
        }
        // Consume resources.
        for resource in ResourceType.allCases where recipe.resourceCost[resource] > 0 {
            s.settlements[capital].storage[resource] =
                s.settlements[capital].storage[resource] - recipe.resourceCost[resource]
        }
        // Produce the output (deterministic id).
        var rng = SeededRNG(seed: craftSeed(state: s, recipeID: recipeID))
        s.settlements[capital].inventory.append(ItemInstance(id: rng.nextUUID(), definitionID: recipe.outputItemID))
        return s
    }

    static func materialCounts(_ settlement: Settlement) -> [String: Int] {
        settlement.inventory.reduce(into: [:]) { counts, instance in
            counts[instance.definitionID, default: 0] += 1
        }
    }

    private static func craftSeed(state: WorldState, recipeID: String) -> UInt64 {
        var h: UInt64 = state.mapSeed &* 0x9E37_79B9_7F4A_7C15
        for byte in recipeID.utf8 { h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3 }
        h = (h ^ UInt64(bitPattern: Int64(state.tick)))
        h = (h ^ UInt64(state.settlements.first?.inventory.count ?? 0))
        return h ^ (h >> 29)
    }
}
