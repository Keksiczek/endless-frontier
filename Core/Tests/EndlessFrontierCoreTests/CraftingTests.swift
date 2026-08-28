import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Crafting")
struct CraftingTests {
    private func reg() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private func capital(materials: [String], buildings: [String] = [], resources: Resources = [.materials: 100]) -> WorldState {
        let inv = materials.map { ItemInstance(definitionID: $0) }
        let bld = buildings.map { BuildingInstance(definitionID: $0, count: 1) }
        let c = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-7b233e2c671d")!, name: "C", kind: .capital, pawns: Fixtures.pawns(5), buildings: bld,
                           storage: resources, storageCapacity: .uniform(9999), inventory: inv)
        return WorldState(settlements: [c])
    }

    @Test("Recipes load from data")
    func bundledRecipes() throws {
        #expect(try reg().recipes.count >= 6)
    }

    @Test("A no-building recipe crafts when materials and resources suffice")
    func basicCraft() throws {
        let r = try reg()
        // Chainmail used to be the sample here, and it was the sample because
        // it was the bug: mail out of two ingots with no bench and no study.
        // A leather garb is what a colony with no workshop can honestly make.
        let world = capital(materials: ["leather", "leather"])   // 2 leather + 10 materials
        #expect(CraftingEngine.canCraft(r.recipes["craft_leather_garb"]!, in: world, registry: r))
        let after = BenchTestSupport.craft(world, recipeID: "craft_leather_garb", registry: r)
        // Materials consumed, output added.
        #expect(!after.settlements[0].inventory.contains { $0.definitionID == "leather" })
        #expect(after.settlements[0].inventory.contains { $0.definitionID == "leather_garb" })
        #expect(after.settlements[0].storage[.materials] == 90)   // 100 - 10
    }

    @Test("Crafting fails without the required materials")
    func missingMaterials() throws {
        let r = try reg()
        let world = capital(materials: ["leather"])   // only 1, needs 2
        #expect(!CraftingEngine.canCraft(r.recipes["craft_leather_garb"]!, in: world, registry: r))
        let after = BenchTestSupport.craft(world, recipeID: "craft_leather_garb", registry: r)
        // Nothing is made, and nothing is spent. The whole state is no longer
        // identical — an order *does* go on the bench, and stays there waiting
        // for the second ingot, which is the point of a queue.
        #expect(after.settlements[0].inventory == world.settlements[0].inventory)
        #expect(after.settlements[0].storage == world.settlements[0].storage)
        #expect(after.settlements[0].craftOrders.count == 1,
                "the order waits for the iron rather than vanishing")
    }

    /// **The bench comes from the recipe, not from this test.** It used to name
    /// `workshop` and `craft_iron_scythe` in the same breath, so the day the
    /// scythe moved to the `smithy` — where iron belongs, since the bloomery
    /// wins it in the first age — the test failed for a change that was right.
    /// A fixture that hardcodes what the content says is a fixture that has to
    /// be edited every time the content is (rule 89).
    @Test("A recipe with a bench cannot be made without it")
    func buildingRequirement() throws {
        let r = try reg()
        let recipe = try #require(r.recipes["craft_iron_scythe"])
        let bench = try #require(recipe.requiresBuilding)
        let stock = ["iron_ingot", "iron_ingot", "timber_bundle"]

        let without = capital(materials: stock)
        #expect(!CraftingEngine.canCraft(recipe, in: without, registry: r))

        let with = capital(materials: stock, buildings: [bench])
        #expect(CraftingEngine.canCraft(recipe, in: with, registry: r))
        let after = BenchTestSupport.craft(with, recipeID: recipe.id, registry: r)
        #expect(after.settlements[0].inventory.contains { $0.definitionID == recipe.outputItemID })
    }

    @Test("availableRecipes lists only craftable recipes")
    func available() throws {
        let r = try reg()
        // Leather garb is stitched from leather, not from a bundle of timber.
        let world = capital(materials: ["leather", "leather"])
        let ids = Set(CraftingEngine.availableRecipes(world, registry: r).map(\.id))
        #expect(ids.contains("craft_leather_garb"))
        #expect(!ids.contains("craft_warden_plate"))   // needs rare materials + workshop + tech
    }

    @Test("Crafting is deterministic")
    func deterministic() throws {
        let r = try reg()
        let world = capital(materials: ["leather", "leather"])
        let a = BenchTestSupport.craft(world, recipeID: "craft_leather_garb", registry: r)
        let b = BenchTestSupport.craft(world, recipeID: "craft_leather_garb", registry: r)
        #expect(a == b)
    }

    @Test("Every recipe output and material references a real item")
    func recipeIntegrity() throws {
        let r = try reg()
        for recipe in r.recipes.values {
            #expect(r.item(recipe.outputItemID) != nil, "Recipe \(recipe.id) outputs missing item")
            for materialID in recipe.materials.keys {
                #expect(r.item(materialID)?.slot == .material, "Recipe \(recipe.id) needs non-material \(materialID)")
            }
        }
    }
}
