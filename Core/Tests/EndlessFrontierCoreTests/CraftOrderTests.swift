import Testing
import Foundation
@testable import EndlessFrontierCore

/// Making things, as work somebody does rather than a button somebody presses.
///
/// Crafting used to be instant, free of labour, and performed by nobody: a
/// recipe named a workshop, the colony had to *have* a workshop, and no
/// colonist could ever be a person who worked in one — there was no such trade.
/// These pin the parts of that which can break back silently.
@Suite("The bench")
struct CraftOrderTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    /// A colony with a workshop, iron on the shelf, and hands to use it.
    /// Fixed ids: per-entity randomness is seeded from them (CLAUDE.md rule 3).
    private func workshop(
        crafters: Int = 3, skill: Int = 0, iron: Int = 20, timber: Int = 20,
        materials: Double = 8000
    ) throws -> Settlement {
        var s = Settlement(
            id: UUID(uuidString: "C4AF7000-0000-0000-0000-000000000001")!,
            name: "Bench",
            buildings: [BuildingInstance(
                id: UUID(uuidString: "C4AF7000-1111-0000-0000-000000000001")!,
                definitionID: "workshop")],
            storage: [.food: 500, .materials: materials], storageCapacity: 20_000)
        let ticksPerYear = try registry().config.ticksPerYear
        for i in 0..<crafters {
            var p = Pawn(
                id: UUID(uuidString: String(format: "C4AF7000-0000-0000-0000-%012d", i + 10))!,
                name: "Smith \(i)", assignedWork: .crafting)
            p.age = 30 * ticksPerYear
            p.skills[.crafting] = skill
            s.pawns.append(p)
        }
        s.stockpile["iron_ingot"] = iron
        s.stockpile["timber_bundle"] = timber
        s.stockpile["ancient_alloy"] = 20
        return s
    }

    private func work(
        _ settlement: Settlement, ticks: Int, researched: Set<String> = []
    ) throws -> Settlement {
        let reg = try registry()
        var s = settlement
        for tick in 0..<ticks {
            s = CraftingEngine.advanceOneTick(
                s, tick: tick, researched: researched, registry: reg)
        }
        return s
    }

    // MARK: - It is reachable at all

    /// The reachability that matters (rule 6). Everything else here is detail:
    /// if a colony with the shop, the stuff and the hands cannot finish one
    /// thing in a season of work, crafting does not exist.
    @Test("A colony with a shop, materials and hands actually makes something")
    func craftingIsReachable() throws {
        var s = try workshop()
        s = CraftingEngine.place(s, recipeID: "craft_iron_scythe", count: 1,
                                 tick: 0, registry: try registry())
        #expect(s.craftOrders.count == 1)

        let after = try work(s, ticks: 120)
        #expect(after.inventory.contains { $0.definitionID == "iron_scythe" },
                "three smiths worked a bench for a season and made nothing")
        #expect(after.craftOrders.isEmpty, "a finished order leaves the queue")
    }

    @Test("Making a thing spends what it is made of")
    func craftingSpendsMaterials() throws {
        var s = try workshop()
        s = CraftingEngine.place(s, recipeID: "craft_iron_scythe", count: 1,
                                 tick: 0, registry: try registry())
        let after = try work(s, ticks: 120)
        #expect((after.stockpile["iron_ingot"] ?? 0) == 18)
        #expect((after.stockpile["timber_bundle"] ?? 0) == 19)
    }

    /// The whole point of the change: it is *work*, and work takes people and
    /// time. A bench with nobody at it produces nothing for ever.
    @Test("A bench with nobody at it makes nothing")
    func noHandsNoGoods() throws {
        var s = try workshop(crafters: 0)
        s = CraftingEngine.place(s, recipeID: "craft_iron_scythe", count: 1,
                                 tick: 0, registry: try registry())
        let after = try work(s, ticks: 300)
        #expect(after.inventory.isEmpty)
        #expect(after.craftOrders.count == 1, "the order is still waiting for hands")
    }

    @Test("More hands and better hands finish sooner")
    func handsAndSkillMatter() throws {
        func progress(crafters: Int, skill: Int) throws -> Double {
            var s = try workshop(crafters: crafters, skill: skill)
            s = CraftingEngine.place(s, recipeID: "craft_plate_armor", count: 4,
                                     tick: 0, registry: try registry())
            let after = try work(s, ticks: 40)
            let order = after.craftOrders.first
            return Double(order?.made ?? 4) + (order?.progress ?? 0) / 100
        }
        #expect(try progress(crafters: 6, skill: 0) > progress(crafters: 2, skill: 0))
        #expect(try progress(crafters: 3, skill: 20) > progress(crafters: 3, skill: 0))
    }

    // MARK: - It cannot make things out of nothing

    @Test("An empty shelf stops the bench rather than conjuring stock")
    func emptyShelfStops() throws {
        var s = try workshop(iron: 2, timber: 1)
        s = CraftingEngine.place(s, recipeID: "craft_iron_scythe", count: 5,
                                 tick: 0, registry: try registry())
        let after = try work(s, ticks: 400)
        let made = after.inventory.count { $0.definitionID == "iron_scythe" }
        #expect(made == 1, "one scythe's worth of iron made exactly one scythe")
        #expect((after.stockpile["iron_ingot"] ?? 0) == 0)
    }

    /// Part-finished work must not spin up for ever while the shelves are bare,
    /// or the moment one ingot arrives the colony pops out five swords.
    @Test("Work banked against an empty shelf is capped, not hoarded")
    func progressDoesNotHoard() throws {
        var s = try workshop(iron: 0, timber: 0)
        s = CraftingEngine.place(s, recipeID: "craft_iron_scythe", count: 5,
                                 tick: 0, registry: try registry())
        var starved = try work(s, ticks: 400)
        let reg = try registry()
        let cost = try #require(reg.recipes["craft_iron_scythe"]).workPerUnit
        #expect((starved.craftOrders.first?.progress ?? 0) <= cost + 0.001)

        // The iron arrives; the colony gets one, not the whole order at once.
        starved.stockpile["iron_ingot"] = 2
        starved.stockpile["timber_bundle"] = 1
        let after = CraftingEngine.advanceOneTick(
            starved, tick: 500, researched: [], registry: reg)
        #expect(after.inventory.count { $0.definitionID == "iron_scythe" } <= 1)
    }

    @Test("A shop the colony has not built stops the order")
    func missingShopStops() throws {
        var s = try workshop()
        s.buildings = []
        s = CraftingEngine.place(s, recipeID: "craft_iron_scythe", count: 1,
                                 tick: 0, registry: try registry())
        let after = try work(s, ticks: 300)
        #expect(after.inventory.isEmpty)
        #expect(after.craftOrders.count == 1)
    }

    /// An order that cannot be worked must not block the ones behind it — a
    /// colony waiting on iron should still be making its arrows.
    @Test("A stuck order does not jam the queue behind it")
    func stuckOrderDoesNotBlock() throws {
        let reg = try registry()
        var s = try workshop(iron: 0, timber: 20)
        // Something impossible first…
        s = CraftingEngine.place(s, recipeID: "craft_iron_scythe", count: 1,
                                 tick: 0, registry: reg)
        // …and something the colony can actually make behind it.
        s = CraftingEngine.place(s, recipeID: "craft_leather_garb", count: 1,
                                 tick: 1, registry: reg)
        s.stockpile["leather"] = 6

        let after = try work(s, ticks: 200)
        #expect(after.inventory.contains { $0.definitionID == "leather_garb" },
                "the second order waited behind an order that could never run")
    }

    // MARK: - Orders are the player's lever

    @Test("A standing order never finishes and keeps making them")
    func standingOrderRepeats() throws {
        var s = try workshop(iron: 40, timber: 40)
        s = CraftingEngine.place(s, recipeID: "craft_iron_scythe", count: nil,
                                 tick: 0, registry: try registry())
        let after = try work(s, ticks: 400)
        #expect(after.craftOrders.count == 1, "a standing order stays on the bench")
        #expect(after.inventory.count { $0.definitionID == "iron_scythe" } > 1)
    }

    @Test("A paused order is set aside without losing its work")
    func pausingKeepsProgress() throws {
        let reg = try registry()
        var s = try workshop()
        s = CraftingEngine.place(s, recipeID: "craft_plate_armor", count: 2,
                                 tick: 0, registry: reg)
        s = try work(s, ticks: 10)
        let banked = try #require(s.craftOrders.first).progress
        #expect(banked > 0)

        let id = try #require(s.craftOrders.first).id
        s = CraftingEngine.setPaused(s, orderID: id, paused: true)
        s = try work(s, ticks: 40)
        #expect(abs((s.craftOrders.first?.progress ?? 0) - banked) < 0.001,
                "a paused order neither advances nor forgets")

        s = CraftingEngine.setPaused(s, orderID: id, paused: false)
        s = try work(s, ticks: 10)
        #expect((s.craftOrders.first?.progress ?? 0) > banked
                || (s.craftOrders.first?.made ?? 0) > 0)
    }

    @Test("An order can be taken off the bench")
    func cancelling() throws {
        var s = try workshop()
        s = CraftingEngine.place(s, recipeID: "craft_iron_scythe", count: 3,
                                 tick: 0, registry: try registry())
        let id = try #require(s.craftOrders.first).id
        s = CraftingEngine.cancel(s, orderID: id)
        #expect(s.craftOrders.isEmpty)
    }

    @Test("The bench holds only so many orders")
    func queueIsBounded() throws {
        let reg = try registry()
        var s = try workshop()
        for i in 0..<(CraftingEngine.maxOrders + 5) {
            s = CraftingEngine.place(s, recipeID: "craft_iron_scythe", count: 1,
                                     tick: i, registry: reg)
        }
        #expect(s.craftOrders.count == CraftingEngine.maxOrders)
    }

    // MARK: - The colony staffs it

    /// The other half of the reachability: a colony told to make something has
    /// to actually put somebody on it, or the order sits there for ever while
    /// everybody farms.
    @Test("A colony asked to make something posts somebody to the bench")
    func craftersGetStaffed() throws {
        let reg = try registry()
        var s = try workshop(crafters: 0)
        for i in 0..<12 {
            var p = Pawn(
                id: UUID(uuidString: String(format: "C4AF7000-2222-0000-0000-%012d", i))!,
                name: "Hand \(i)", assignedWork: .idle)
            p.age = 30 * reg.config.ticksPerYear
            s.pawns.append(p)
        }
        s = CraftingEngine.place(s, recipeID: "craft_iron_scythe", count: 2,
                                 tick: 0, registry: reg)
        s = LaborEngine.assignIdleAdults(s, registry: reg)
        #expect(s.pawns.contains { $0.assignedWork == .crafting },
                "the colony was asked for a scythe and nobody went to the bench")
    }

    @Test("With nothing on the bench, nobody is posted to it")
    func noOrdersNoCrafters() throws {
        let reg = try registry()
        var s = try workshop(crafters: 0)
        for i in 0..<12 {
            var p = Pawn(
                id: UUID(uuidString: String(format: "C4AF7000-3333-0000-0000-%012d", i))!,
                name: "Hand \(i)", assignedWork: .idle)
            p.age = 30 * reg.config.ticksPerYear
            s.pawns.append(p)
        }
        s = LaborEngine.assignIdleAdults(s, registry: reg)
        #expect(!s.pawns.contains { $0.assignedWork == .crafting },
                "people standing in an empty workshop")
    }

    // MARK: - Determinism and saves

    @Test("The same bench with the same orders makes the same things")
    func craftingIsDeterministic() throws {
        func run() throws -> Settlement {
            var s = try workshop()
            s = CraftingEngine.place(s, recipeID: "craft_iron_scythe", count: 2,
                                     tick: 0, registry: try registry())
            return try work(s, ticks: 200)
        }
        let a = try run(), b = try run()
        #expect(a.inventory.map(\.id) == b.inventory.map(\.id))
        #expect(a.stockpile == b.stockpile)
    }

    @Test("A half-made order survives being written to disk")
    func ordersRoundTrip() throws {
        var s = try workshop()
        s = CraftingEngine.place(s, recipeID: "craft_plate_armor", count: 3,
                                 tick: 0, registry: try registry())
        s = try work(s, ticks: 12)

        let back = try JSONDecoder().decode(
            Settlement.self, from: try JSONEncoder().encode(s))
        let before = try #require(s.craftOrders.first)
        let after = try #require(back.craftOrders.first)
        #expect(after.recipeID == before.recipeID)
        #expect(after.wanted == before.wanted)
        #expect(abs(after.progress - before.progress) < 1e-9)
    }

    @Test("A save written before the bench existed still loads")
    func oldSavesLoad() throws {
        let s = try workshop()
        var object = try #require(try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(s)) as? [String: Any])
        object.removeValue(forKey: "craftOrders")
        let back = try JSONDecoder().decode(
            Settlement.self,
            from: try JSONSerialization.data(withJSONObject: object))
        #expect(back.craftOrders.isEmpty)
    }

    // MARK: - What things cost

    /// Twenty-nine recipes ship with no stated work cost, because crafting had
    /// none. Every one of them has to come out with a sane one, or some corner
    /// of the tree is either instant or unreachable.
    @Test("Every recipe costs a sane amount of work")
    func everyRecipeHasACost() throws {
        let reg = try registry()
        #expect(!reg.recipes.isEmpty)
        for recipe in reg.recipes.values {
            let cost = recipe.workPerUnit
            #expect(cost >= 6, "\(recipe.id) is free")
            #expect(cost <= 400, "\(recipe.id) costs \(cost) — nobody will ever finish it")
        }
    }

    @Test("A thing made of more, and made in a shop, takes longer")
    func costFollowsTheRecipe() throws {
        let simple = RecipeDefinition(
            id: "a", name: "a", outputItemID: "x", materials: ["leather": 1])
        let rich = RecipeDefinition(
            id: "b", name: "b", outputItemID: "x", materials: ["iron_ingot": 4])
        let shopped = RecipeDefinition(
            id: "c", name: "c", outputItemID: "x", materials: ["leather": 1],
            requiresBuilding: "workshop")
        #expect(rich.workPerUnit > simple.workPerUnit)
        #expect(shopped.workPerUnit > simple.workPerUnit)

        // And content may say so outright.
        let stated = RecipeDefinition(
            id: "d", name: "d", outputItemID: "x", materials: ["leather": 9],
            workTicks: 12)
        #expect(stated.workPerUnit == 12)
    }
}
