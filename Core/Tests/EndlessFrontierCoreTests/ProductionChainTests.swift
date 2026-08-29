import Testing
import Foundation
@testable import EndlessFrontierCore

/// Reported from a real game: the resources should be logical, recipes should
/// rest on them, and it should have some depth.
///
/// What was actually there: 23 recipes and 48 items sitting on top of nothing.
/// `iron_ingot` and `timber_bundle` were required by nine recipes and produced
/// by none — obtainable only as a random loot roll — so the whole steel →
/// circuits → fusion chain above them could not be reached by playing. Mean-
/// while colonists felled trees and broke stone every tick and all of it
/// dissolved into one abstract `materials` pool.
///
/// The guard test here is `everyRecipeMaterialHasASource`: it is the one that
/// would have caught the original bug, and it fails the moment someone authors
/// a recipe whose ingredients nothing can supply.
@Suite("The crafting tree has a root")
struct ProductionChainTests {
    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    /// Materials the ground itself yields — the only legitimate way into the
    /// tree that isn't a recipe.
    private var gathered: Set<String> {
        Set(LocalResourceKind.allCases.compactMap(\.rawMaterialID))
            .union([ResourceLoop.hideItemID])
    }

    @Test("Every material a recipe asks for can be gathered, crafted, or found")
    func everyRecipeMaterialHasASource() throws {
        let reg = try registry()
        let produced = Set(reg.recipes.values.map(\.outputItemID))
        let lootable = Set(SiteEngine.lootPool(registry: reg).map(\.id))

        for recipe in reg.recipes.values {
            for material in recipe.materials.keys {
                #expect(reg.item(material) != nil,
                        "\(recipe.id) asks for '\(material)', which is not an item at all")
                #expect(produced.contains(material) || gathered.contains(material)
                        || lootable.contains(material),
                        "\(recipe.id) asks for '\(material)' and nothing in the game produces it")
            }
        }
    }

    @Test("Every recipe's building gate is a building that exists")
    func buildingGatesAreReal() throws {
        let reg = try registry()
        for recipe in reg.recipes.values {
            guard let gate = recipe.requiresBuilding else { continue }
            #expect(reg.building(gate) != nil,
                    "\(recipe.id) is gated behind '\(gate)', which is not a building")
        }
    }

    /// Walks the tree from bare ground upward. Everything reachable should be
    /// reachable *by working*, not by waiting for a lucky drop.
    @Test("The tree can be climbed from raw ground")
    func treeIsClimbable() throws {
        let reg = try registry()
        var have = gathered
        var changed = true
        while changed {
            changed = false
            for recipe in reg.recipes.values
            where !have.contains(recipe.outputItemID)
                && Set(recipe.materials.keys).isSubset(of: have) {
                have.insert(recipe.outputItemID)
                changed = true
            }
        }
        // The base tier the old game could not reach at all.
        #expect(have.contains("timber_bundle"))
        #expect(have.contains("iron_ingot"))
        #expect(have.contains("charcoal"))
        // And the chain that stood on it.
        #expect(have.contains("steel_ingot"))
        #expect(have.contains("circuit_board"))
    }

    @Test("The root of the tree is reachable with a founding colony's buildings")
    func rootNeedsNoTechTree() throws {
        let reg = try registry()
        let saw = try #require(reg.recipes["saw_timber"])
        let gate = try #require(saw.requiresBuilding)
        // `lumberyard` is a starter building, so the first plank does not wait
        // on a tech or a construction project.
        #expect(gate == "lumberyard")
        #expect(saw.requiresTech == nil)
        #expect(Set(saw.materials.keys).isSubset(of: gathered))
    }

    // MARK: - Loot stays treasure

    @Test("Ordinary materials are not treasure")
    func lootHoldsNoClay() throws {
        let reg = try registry()
        let pool = Set(SiteEngine.lootPool(registry: reg).map(\.id))
        for id in gathered {
            #expect(!pool.contains(id),
                    "'\(id)' is dug out of the ground — a buried cache full of it is not a find")
        }
        #expect(!pool.contains("charcoal"), "a crafted material is not treasure either")
        #expect(!pool.isEmpty)
    }

    @Test("The materials no one can make are exactly what makes a ruin worth robbing")
    func lootKeepsTheRareAlloys() throws {
        let reg = try registry()
        let pool = Set(SiteEngine.lootPool(registry: reg).map(\.id))
        #expect(pool.contains("ancient_alloy"))
        #expect(pool.contains("spirit_essence"))
    }

    // MARK: - Extraction

    private func colony(biome: String, workers: [WorkKind: Int]) throws -> Settlement {
        let reg = try registry()
        var s = Settlement(id: UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000001")!,
                           name: "Pit", storage: [.food: 900], storageCapacity: .uniform(2000))
        var index = 0
        for (work, count) in workers.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            for _ in 0..<count {
                var p = Pawn(id: UUID(uuidString: String(format: "EEEEEEEE-0000-0000-0000-%012d", index))!,
                             name: "Hand \(index)", assignedWork: work)
                p.age = 25 * reg.config.ticksPerYear
                s.pawns.append(p)
                index += 1
            }
        }
        s.localMap = LocalMapGenerator.generate(mapSeed: 5, regionID: s.id, biome: reg.biome(biome), registry: reg)
        return s
    }

    /// The whole route from work to storehouse.
    ///
    /// Timber and stone stopped being earned by the week when hauling arrived:
    /// a felled trunk leaves wood at the stump and a broken block leaves stone
    /// at the face, and it is only in the colony's hands once somebody has
    /// carried it in. So the test walks the same three steps the game does —
    /// work the ground, drop what it yields, carry it home — instead of asking
    /// one of them in isolation and believing its answer.
    private func work(_ settlement: Settlement, ticks: Int) throws -> Settlement {
        let reg = try registry()
        var s = settlement
        let factors = ResourceLoop.gatheringFactors(s.localMap, registry: reg)
        for tick in 0..<ticks {
            s = ResourceLoop.extractRawMaterials(s, tick: tick, config: reg.config, factors: factors)
            s = ResourceLoop.evolveDeposits(s, registry: reg, tick: tick, config: reg.config,
                                            mapSeed: 5)
            // Hauling is an action-step thing (`WalkPace`), so the tick holds
            // eight of them — the same shape `TickEngine` runs, rather than one
            // carrying step per harvest and a chain that looks bottlenecked
            // only because the harness measured it in the wrong unit.
            for step in 0..<WorldClock.actionStepsPerTick {
                s = HaulEngine.advanceStep(
                    s, registry: reg, clock: WorldClock(tick: tick, step: step))
            }
        }
        return s
    }

    @Test("A logging crew comes home with wood")
    func loggersBankWood() throws {
        let after = try work(colony(biome: "forest", workers: [.logging: 4]), ticks: 60)
        #expect((after.stockpile["wood"] ?? 0) > 0)
    }

    @Test("Hunters bring hides home with the meat")
    func huntersBankHides() throws {
        let after = try work(colony(biome: "plains", workers: [.hunting: 4]), ticks: 60)
        #expect((after.stockpile[ResourceLoop.hideItemID] ?? 0) > 0)
    }

    @Test("Colonists away on an expedition mine nothing")
    func awayHandsExtractNothing() throws {
        var camp = try colony(biome: "mountains", workers: [.mining: 4])
        let trip = UUID()
        for i in camp.pawns.indices { camp.pawns[i].expeditionID = trip }
        let after = try work(camp, ticks: 60)
        #expect(after.stockpile.isEmpty, "people out at the ruins are not also down the mine")
    }

    /// Slow work must still arrive. One logger takes many ticks to bring a
    /// trunk down and more to walk it home — but it has to get there, or a
    /// small colony would bank nothing, ever.
    @Test("A lone logger's timber lies at the stump before it reaches the store")
    func timberIsCarriedNotConjured() throws {
        let early = try work(colony(biome: "forest", workers: [.logging: 1]), ticks: 3)
        #expect((early.stockpile["wood"] ?? 0) == 0, "nobody has carried anything yet")

        let later = try work(colony(biome: "forest", workers: [.logging: 1]), ticks: 200)
        let carried = later.stockpile["wood"] ?? 0
        let lying = later.localMap?.piles.filter { $0.itemID == "wood" }
            .reduce(0) { $0 + $1.amount } ?? 0
        #expect(carried + lying > 0, "a logger worked for two hundred ticks and felled nothing")
        #expect(carried > 0, "and somebody should have walked at least one load home")
    }

    // MARK: - The land decides what you can make

    @Test("Ore country yields ore; the coast does not")
    func oreIsBiomeGated() throws {
        let hills = try work(colony(biome: "mountains", workers: [.mining: 4]), ticks: 400)
        let shore = try work(colony(biome: "coast", workers: [.mining: 4]), ticks: 400)
        #expect((hills.stockpile["iron_ore"] ?? 0) > 0)
        #expect((shore.stockpile["iron_ore"] ?? 0) == 0,
                "a coastal colony has to trade or expand for its iron")
        #expect((shore.stockpile["clay"] ?? 0) > 0, "but it has clay beds instead")
    }

    /// The one that got away for a long time, and the reason the test above
    /// could fail while the *land* was perfectly correct.
    ///
    /// Timber falls at the stump and hewn stone falls at the face, but the
    /// third and commonest kind of working — a pick into an **outcrop** — took
    /// only the map back from `FloraEngine.quarry` and dropped its yield on the
    /// floor. Nothing anywhere turned a worked outcrop into goods. So on any
    /// valley with no massif in it (every coast, most plains) four miners could
    /// grind nine clay banks to nothing over four hundred ticks and bank not
    /// one unit of anything.
    ///
    /// Named for the reachability, not the behaviour (rule 6): what must hold
    /// is that rock which is consumed *arrives*.
    @Test("Rock that is worked away comes back as goods")
    func quarriedRockIsNotLost() throws {
        let start = try colony(biome: "coast", workers: [.mining: 4])
        let before = start.localMap?.rocks.reduce(0) { $0 + $1.amount } ?? 0
        #expect(before > 0, "a coastal valley has outcrops to work")

        let after = try work(start, ticks: 400)
        let left = after.localMap?.rocks.reduce(0) { $0 + $1.amount } ?? 0
        #expect(left < before, "four miners worked the rock for four hundred ticks")

        let carried = after.stockpile.values.reduce(0, +)
        let lying = after.localMap?.piles.reduce(0) { $0 + $1.amount } ?? 0
        #expect(carried + lying > 0,
                "the rock came out of the ground and nothing came of it")
    }

    /// Hard rock is *slow*, not free and not impossible. A tick at a granite
    /// face yields less than half a unit; flooring that every tick pays
    /// nothing for ever, and rounding it up pays four times over.
    @Test("A part-broken outcrop is banked, not rounded away")
    func partialTakesAccumulate() throws {
        let hills = try work(colony(biome: "mountains", workers: [.mining: 1]), ticks: 400)
        let carried = hills.stockpile.values.reduce(0, +)
        let lying = hills.localMap?.piles.reduce(0) { $0 + $1.amount } ?? 0
        #expect(carried + lying > 0, "one miner on hard rock still gets somewhere")
    }

    // MARK: - Crafting from the pile

    @Test("A craft spends the stockpile and banks what it makes")
    func craftingUsesTheStockpile() throws {
        let reg = try registry()
        var s = Settlement(id: UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000009")!,
                           name: "Mill", buildings: [BuildingInstance(definitionID: "lumberyard")],
                           storage: [.materials: 500], storageCapacity: .uniform(2000))
        s.stockpile["wood"] = 6
        var world = WorldState(tick: 0, settlements: [s])

        world = BenchTestSupport.craft(world, recipeID: "saw_timber",
                                     settlementID: s.id, registry: reg)
        #expect(world.settlements[0].stockpile["wood"] == 3, "three logs went into the saw")
        #expect(world.settlements[0].stockpile["timber_bundle"] == 1)
        #expect(world.settlements[0].inventory.isEmpty,
                "a material is a count on the pile, not a thing with an id")
    }

    @Test("Gear still arrives as a thing a colonist can wear")
    func craftedGearIsAnInstance() throws {
        let reg = try registry()
        var s = Settlement(id: UUID(uuidString: "EEEEEEEE-0000-0000-0000-00000000000A")!,
                           name: "Forge", buildings: [BuildingInstance(definitionID: "workshop")],
                           storage: [.materials: 500], storageCapacity: .uniform(2000))
        s.stockpile["iron_ingot"] = 2
        var world = WorldState(tick: 0, settlements: [s])
        // This is a test about a *thing* arriving in the inventory, not about
        // the ladder: the colony has read whatever the sword asks for. The book
        // was gated by chain depth on 2026-08-29 and a fixture that says "a
        // workshop" and means "and nothing to learn" fails for a change that is
        // right (rule 109).
        world.researchedTechs = Set([reg.recipes["craft_iron_sword"]?.requiresTech].compactMap { $0 })
        world = BenchTestSupport.craft(world, recipeID: "craft_iron_sword",
                                     settlementID: s.id, registry: reg)
        #expect(world.settlements[0].inventory.contains { $0.definitionID == "iron_sword" })
        #expect((world.settlements[0].stockpile["iron_ingot"] ?? 0) == 0)
    }

    /// Materials used to be loot instances only. A save from before the
    /// stockpile still keeps its ingots in `inventory`, and a craft must spend
    /// them rather than pretending the player has nothing.
    @Test("Materials held the old way still count and are still spent")
    func legacyInventoryMaterialsStillWork() throws {
        let reg = try registry()
        var s = Settlement(id: UUID(uuidString: "EEEEEEEE-0000-0000-0000-00000000000B")!,
                           name: "Old", buildings: [BuildingInstance(definitionID: "workshop")],
                           storage: [.materials: 500], storageCapacity: .uniform(2000))
        s.inventory = [ItemInstance(id: UUID(), definitionID: "iron_ingot"),
                       ItemInstance(id: UUID(), definitionID: "iron_ingot")]
        var world = WorldState(tick: 0, settlements: [s])
        world.researchedTechs = Set([reg.recipes["craft_iron_sword"]?.requiresTech].compactMap { $0 })
        #expect(CraftingEngine.canCraft(reg.recipes["craft_iron_sword"]!, in: world,
                                        settlementID: s.id, registry: reg))
        world = BenchTestSupport.craft(world, recipeID: "craft_iron_sword",
                                     settlementID: s.id, registry: reg)
        #expect(!world.settlements[0].inventory.contains { $0.definitionID == "iron_ingot" })
        #expect(world.settlements[0].inventory.contains { $0.definitionID == "iron_sword" })
    }

    @Test("The stockpile survives a save")
    func stockpileRoundTrips() throws {
        var s = Settlement(id: UUID(uuidString: "EEEEEEEE-0000-0000-0000-00000000000C")!, name: "Store")
        s.stockpile = ["wood": 12, "iron_ore": 3]
        s.rawProgress = ["wood": 4.5]
        let data = try JSONEncoder().encode(WorldState(tick: 0, settlements: [s]))
        let back = try JSONDecoder().decode(WorldState.self, from: data)
        #expect(back.settlements[0].stockpile == s.stockpile)
        #expect(back.settlements[0].rawProgress == s.rawProgress)
    }

    @Test("A settlement saved before the stockpile existed loads with an empty one")
    func legacySettlementDecodes() throws {
        let s = Settlement(id: UUID(uuidString: "EEEEEEEE-0000-0000-0000-00000000000D")!, name: "Old")
        let encoded = try JSONEncoder().encode(s)
        var fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        fields.removeValue(forKey: "stockpile")
        fields.removeValue(forKey: "rawProgress")
        let legacy = try JSONSerialization.data(withJSONObject: fields)
        let restored = try JSONDecoder().decode(Settlement.self, from: legacy)
        #expect(restored.stockpile.isEmpty)
        #expect(restored.rawProgress.isEmpty)
    }

    // MARK: - The chain has to line up in time, not just in the data

    /// The earliest era a material can be made in: zero for anything dug out of
    /// the ground, otherwise the earliest era of any recipe that produces it,
    /// gated by the building that recipe needs.
    private func earliestEra(registry reg: GameDataRegistry) -> [String: Int] {
        var era: [String: Int] = [:]
        for id in gathered { era[id] = 0 }
        // A material you can only rob from a ruin gates on exploration, not on
        // the calendar — treat it as available from the start, or everything
        // built on top of it reads as unreachable forever.
        for id in SiteEngine.lootPool(registry: reg).map(\.id) where era[id] == nil {
            if reg.item(id)?.slot == .material { era[id] = 0 }
        }
        var changed = true
        while changed {
            changed = false
            for recipe in reg.recipes.values {
                let ingredientEra = recipe.materials.keys.map { era[$0] ?? Int.max }.max() ?? 0
                guard ingredientEra != Int.max else { continue }
                let gate = recipe.requiresBuilding.flatMap { reg.building($0)?.era.index } ?? 0
                let at = max(ingredientEra, gate)
                if at < era[recipe.outputItemID] ?? Int.max {
                    era[recipe.outputItemID] = at
                    changed = true
                }
            }
        }
        return era
    }

    /// The bug this pins: `smelt_iron` hung on the foundry (early industrial)
    /// while the gear that needs ingots is medieval, so iron stayed loot-only
    /// for two whole eras — the exact problem the chain was built to fix, just
    /// moved later where it was harder to notice. Having a *source* is not the
    /// same as having one in time.
    @Test("No recipe asks for a material its era cannot yet produce")
    func ingredientsArriveInTime() throws {
        let reg = try registry()
        let era = earliestEra(registry: reg)
        let lootOnly = Set(SiteEngine.lootPool(registry: reg).map(\.id))

        for recipe in reg.recipes.values {
            let gate = recipe.requiresBuilding.flatMap { reg.building($0)?.era.index } ?? 0
            for material in recipe.materials.keys {
                // Materials you can only rob from a ruin are exempt: they gate
                // on exploration, not on the calendar.
                guard !lootOnly.contains(material) else { continue }
                guard let available = era[material] else {
                    Issue.record("\(recipe.id) needs '\(material)', which nothing produces")
                    continue
                }
                #expect(available <= gate,
                        "\(recipe.id) is buildable in era \(gate) but '\(material)' cannot be made before era \(available)")
            }
        }
    }

    @Test("Iron is workable in the era its gear belongs to")
    func ironArrivesWithItsGear() throws {
        let reg = try registry()
        let era = earliestEra(registry: reg)
        let ingot = try #require(era["iron_ingot"])
        let sword = try #require(reg.recipes["craft_iron_sword"])
        let gate = try #require(sword.requiresBuilding.flatMap { reg.building($0)?.era.index })
        #expect(ingot <= gate, "you cannot forge a sword two eras before you can smelt the iron")
    }

    /// Buildings consume goods now, so the same trap applies to them.
    @Test("No building asks for a material its era cannot yet produce")
    func buildingCostsArriveInTime() throws {
        let reg = try registry()
        let era = earliestEra(registry: reg)
        for building in reg.buildings.values {
            for (material, _) in building.materialCost {
                guard let available = era[material] else {
                    Issue.record("\(building.id) costs '\(material)', which nothing produces")
                    continue
                }
                #expect(available <= building.era.index,
                        "\(building.id) is an era-\(building.era.index) building but '\(material)' cannot be made before era \(available)")
            }
        }
    }
}
