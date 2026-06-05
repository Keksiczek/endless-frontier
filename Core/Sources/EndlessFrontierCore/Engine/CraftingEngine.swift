import Foundation

/// Turns materials (and resources) into gear at a chosen settlement. Materials
/// are item drops from sites; recipes may require a building and/or a tech.
/// All checks and consumption are scoped to one settlement — passing
/// `settlementID == nil` falls back to the capital, preserving older callers.
public enum CraftingEngine {
    /// Recipes the player can craft right now at the given settlement
    /// (materials, resources and requirements all satisfied there).
    public static func availableRecipes(
        _ state: WorldState,
        settlementID: UUID? = nil,
        registry: GameDataRegistry
    ) -> [RecipeDefinition] {
        registry.recipes.values
            .filter { canCraft($0, in: state, settlementID: settlementID, registry: registry) }
            .sorted { $0.id < $1.id }
    }

    public static func canCraft(
        _ recipe: RecipeDefinition,
        in state: WorldState,
        settlementID: UUID? = nil,
        registry: GameDataRegistry
    ) -> Bool {
        guard let index = targetIndex(state, settlementID) else { return false }
        let settlement = state.settlements[index]
        // Materials on hand.
        let counts = materialCounts(settlement)
        for (materialID, needed) in recipe.materials where (counts[materialID] ?? 0) < needed {
            return false
        }
        // Resources on hand.
        for resource in ResourceType.allCases where settlement.storage[resource] < recipe.resourceCost[resource] {
            return false
        }
        // Building requirement.
        if let building = recipe.requiresBuilding,
           !settlement.buildings.contains(where: { $0.definitionID == building }) {
            return false
        }
        // Tech requirement (tech is researched world-wide).
        if let tech = recipe.requiresTech, !state.researchedTechs.contains(tech) {
            return false
        }
        return true
    }

    /// Crafts a recipe at the given settlement: consumes its materials +
    /// resources, adds the output item to its inventory. Returns unchanged
    /// state if it can't be crafted there.
    public static func craft(
        _ state: WorldState,
        recipeID: String,
        settlementID: UUID? = nil,
        registry: GameDataRegistry
    ) -> WorldState {
        guard let recipe = registry.recipes[recipeID],
              let index = targetIndex(state, settlementID),
              canCraft(recipe, in: state, settlementID: settlementID, registry: registry) else {
            return state
        }
        var s = state

        // Consume materials.
        for (materialID, needed) in recipe.materials {
            var removed = 0
            s.settlements[index].inventory.removeAll { instance in
                guard removed < needed, instance.definitionID == materialID else { return false }
                removed += 1
                return true
            }
        }
        // Consume resources.
        for resource in ResourceType.allCases where recipe.resourceCost[resource] > 0 {
            s.settlements[index].storage[resource] =
                s.settlements[index].storage[resource] - recipe.resourceCost[resource]
        }
        // Produce the output (deterministic id).
        var rng = SeededRNG(seed: craftSeed(state: s, recipeID: recipeID, settlementIndex: index))
        s.settlements[index].inventory.append(ItemInstance(id: rng.nextUUID(), definitionID: recipe.outputItemID))
        return s
    }

    static func materialCounts(_ settlement: Settlement) -> [String: Int] {
        settlement.inventory.reduce(into: [:]) { counts, instance in
            counts[instance.definitionID, default: 0] += 1
        }
    }

    /// Resolves the settlement a craft acts on: the named one if given and
    /// present, otherwise the capital, otherwise the first settlement.
    static func targetIndex(_ state: WorldState, _ settlementID: UUID?) -> Int? {
        if let settlementID, let i = state.settlements.firstIndex(where: { $0.id == settlementID }) {
            return i
        }
        return state.settlements.firstIndex(where: { $0.kind == .capital })
            ?? state.settlements.indices.first
    }

    private static func craftSeed(state: WorldState, recipeID: String, settlementIndex: Int) -> UInt64 {
        var h: UInt64 = state.mapSeed &* 0x9E37_79B9_7F4A_7C15
        for byte in recipeID.utf8 { h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3 }
        h = (h ^ UInt64(bitPattern: Int64(state.tick)))
        h = (h ^ UInt64(state.settlements[settlementIndex].inventory.count))
        h = h &+ UInt64(settlementIndex) &* 0x9E37_79B9_7F4A_7C15
        return h ^ (h >> 29)
    }
}
