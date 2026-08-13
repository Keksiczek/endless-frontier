import Foundation
import Testing
@testable import EndlessFrontierCore

/// Building and crafting are scoped to the *selected* settlement, not always
/// the capital: each settlement pays from and stocks its own storage.
@Suite("Per-settlement build & craft")
struct SettlementScopeTests {
    private func reg() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    /// A capital + one outpost, each with independently chosen stock.
    private func twoSettlements(
        capitalMaterials: Double,
        outpostMaterials: Double,
        capitalInventory: [String] = [],
        outpostInventory: [String] = []
    ) -> WorldState {
        let capital = Settlement(
            name: "Capital", kind: .capital, pawns: Fixtures.pawns(8),
            storage: [.materials: capitalMaterials], storageCapacity: .uniform(9999),
            inventory: capitalInventory.map { ItemInstance(definitionID: $0) }
        )
        let outpost = Settlement(
            name: "Frontier Post", kind: .outpost, pawns: Fixtures.pawns(4),
            storage: [.materials: outpostMaterials], storageCapacity: .uniform(9999),
            inventory: outpostInventory.map { ItemInstance(definitionID: $0) }
        )
        return WorldState(settlements: [capital, outpost])
    }

    // MARK: - Build

    @Test("Building in an outpost pays from the outpost's own storage")
    func buildPaysFromTargetSettlement() throws {
        let r = try reg()
        let world = twoSettlements(capitalMaterials: 0, outpostMaterials: 100)
        let outpostID = world.settlements[1].id

        // Paying opens a construction site in the outpost; the roof comes
        // later. The price is read from the content rather than written down
        // here — a dwelling's cost moved when its capacity stopped being a
        // number of its own and became the ground it covers.
        let price = try #require(r.building("hut")).cost[.materials]
        let after = GameEngine.build(world, settlementID: outpostID, buildingID: "hut", registry: r)

        #expect(after.settlements[1].constructions.contains { $0.definitionID == "hut" })
        #expect(after.settlements[1].storage[.materials] == 100 - price)
        #expect(after.settlements[0].storage[.materials] == 0)    // capital untouched
        #expect(after.settlements[0].constructions.isEmpty)
    }

    @Test("Building fails when the target settlement can't afford it, even if the capital can")
    func buildBlockedByPoorOutpost() throws {
        let r = try reg()
        let price = try #require(r.building("hut")).cost[.materials]
        let world = twoSettlements(capitalMaterials: 1000, outpostMaterials: price - 1)
        let outpostID = world.settlements[1].id

        let after = GameEngine.build(world, settlementID: outpostID, buildingID: "hut", registry: r)
        #expect(after == world)   // unchanged: the outpost is a coin short
    }

    // MARK: - Craft

    @Test("Crafting consumes the selected settlement's materials, not the capital's")
    func craftConsumesTargetSettlement() throws {
        let r = try reg()
        // Only the outpost holds the iron; chainmail needs 2 iron + 25 materials.
        let world = twoSettlements(
            capitalMaterials: 0, outpostMaterials: 100,
            outpostInventory: ["iron_ingot", "iron_ingot"]
        )
        let outpostID = world.settlements[1].id

        #expect(CraftingEngine.canCraft(r.recipes["craft_chainmail"]!, in: world,
                                        settlementID: outpostID, registry: r))
        let after = BenchTestSupport.craft(world, recipeID: "craft_chainmail",
                                     settlementID: outpostID, registry: r)

        #expect(after.settlements[1].inventory.contains { $0.definitionID == "chainmail" })
        #expect(!after.settlements[1].inventory.contains { $0.definitionID == "iron_ingot" })
        #expect(after.settlements[1].storage[.materials] == 75)   // 100 - 25
        #expect(after.settlements[0].inventory.isEmpty)           // capital untouched
    }

    @Test("availableRecipes reflect the queried settlement's stock")
    func availableRecipesAreSettlementScoped() throws {
        let r = try reg()
        let world = twoSettlements(
            capitalMaterials: 100, outpostMaterials: 100,
            outpostInventory: ["iron_ingot", "iron_ingot"]
        )
        let capitalID = world.settlements[0].id
        let outpostID = world.settlements[1].id

        let outpostIDs = Set(CraftingEngine.availableRecipes(world, settlementID: outpostID, registry: r).map(\.id))
        let capitalIDs = Set(CraftingEngine.availableRecipes(world, settlementID: capitalID, registry: r).map(\.id))

        #expect(outpostIDs.contains("craft_chainmail"))   // outpost has the iron
        #expect(!capitalIDs.contains("craft_chainmail"))  // capital has none
    }

    @Test("Crafting at different settlements yields distinct item ids")
    func craftIDsDifferAcrossSettlements() throws {
        let r = try reg()
        let world = twoSettlements(
            capitalMaterials: 100, outpostMaterials: 100,
            capitalInventory: ["iron_ingot", "iron_ingot"],
            outpostInventory: ["iron_ingot", "iron_ingot"]
        )
        let capitalID = world.settlements[0].id
        let outpostID = world.settlements[1].id

        let a = BenchTestSupport.craft(world, recipeID: "craft_chainmail", settlementID: capitalID, registry: r)
        let b = BenchTestSupport.craft(world, recipeID: "craft_chainmail", settlementID: outpostID, registry: r)
        let aID = a.settlements[0].inventory.first { $0.definitionID == "chainmail" }?.id
        let bID = b.settlements[1].inventory.first { $0.definitionID == "chainmail" }?.id
        #expect(aID != nil && bID != nil)
        #expect(aID != bID)   // settlement index folds into the deterministic seed
    }
}
