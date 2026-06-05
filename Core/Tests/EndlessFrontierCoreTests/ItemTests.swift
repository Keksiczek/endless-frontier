import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("RPG items & buffs")
struct ItemTests {
    private func reg() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    @Test("Shipped item library loads across rarities and slots")
    func bundledItems() throws {
        let r = try reg()
        #expect(r.items.count >= 16)
        #expect(r.items.values.contains { $0.rarity == .legendary })
        #expect(r.items.values.contains { $0.slot == .equipment })
        #expect(r.items.values.contains { $0.slot == .artifact })
    }

    @Test("Equipment grants a skill bonus to its carrier")
    func equipmentSkillBonus() throws {
        let r = try reg()
        var pawn = Pawn(name: "Miner", skills: [.mining: 5], assignedWork: .mining)
        pawn.equipment[.weapon] = ItemInstance(definitionID: "masterwork_pick")   // mining +6
        #expect(ItemEngine.skillBonus(pawn, work: .mining, registry: r) == 6)
    }

    @Test("An equipped colonist out-produces an unequipped one")
    func equipmentBoostsOutput() throws {
        let r = try reg()
        func miner(equipped: Bool) -> Settlement {
            var pawn = Pawn(name: "M", skills: [.mining: 5],
                            needs: PawnNeeds(hunger: 100, rest: 100, recreation: 100),
                            assignedWork: .mining)
            if equipped { pawn.equipment[.weapon] = ItemInstance(definitionID: "masterwork_pick") }
            return Settlement(name: "C", kind: .capital, population: 1, pawns: [pawn],
                              storage: [.food: 500], storageCapacity: 9999)
        }
        let plain = PawnEngine.advanceOneTick(miner(equipped: false), registry: r)
        let buffed = PawnEngine.advanceOneTick(miner(equipped: true), registry: r)
        #expect(buffed.storage[.materials] > plain.storage[.materials])
    }

    @Test("Colony artifacts add passive production and defense")
    func artifactColonyBuffs() throws {
        let r = try reg()
        let settlement = Settlement(name: "Vault", kind: .capital, population: 5,
                                    storage: [.food: 200], storageCapacity: 9999,
                                    inventory: [ItemInstance(definitionID: "harvest_idol"),
                                                ItemInstance(definitionID: "beacon_stone")])
        #expect(ItemEngine.colonyProduction(settlement, registry: r)[.food] == 3)
        #expect(ItemEngine.colonyDefenseBonus(settlement, registry: r) == 18)
    }

    @Test("Equip and unequip move an item between pawn and inventory")
    func equipUnequip() throws {
        let r = try reg()
        let item = ItemInstance(definitionID: "sturdy_axe")
        let pawn = Pawn(name: "Jo")
        let capital = Settlement(name: "C", kind: .capital, population: 1, pawns: [pawn], inventory: [item])
        let world = WorldState(settlements: [capital])

        let equipped = GameEngine.equipItem(world, settlementID: capital.id, pawnID: pawn.id,
                                             itemID: item.id, registry: r)
        #expect(equipped.settlements[0].pawns[0].equipment[.weapon] != nil)   // axe → weapon slot
        #expect(equipped.settlements[0].inventory.isEmpty)

        let unequipped = GameEngine.unequipItem(equipped, settlementID: capital.id, pawnID: pawn.id, slot: .weapon)
        #expect(unequipped.settlements[0].pawns[0].equipment[.weapon] == nil)
        #expect(unequipped.settlements[0].inventory.count == 1)
    }

    @Test("Delving a dungeon yields an item into the colony inventory")
    func dungeonDropsItem() throws {
        let r = try reg()
        let region = Region(name: "Vault", coord: HexCoord(3, 0), kind: .dungeon, biomeID: "mountains",
                            hazardLevel: 8, explorationState: .fullyExplored)
        let capital = Settlement(name: "C", kind: .capital, population: 1,
                                 pawns: [Pawn(name: "Scout", health: 100)],
                                 storage: [:], storageCapacity: 9999)
        let world = WorldState(mapSeed: 5, settlements: [capital], regions: [region])

        let (after, outcome) = SiteEngine.interact(world, regionID: region.id, registry: r)!
        #expect(outcome.itemFound != nil)
        #expect(after.settlements[0].inventory.count == 1)
    }

    @Test("Item drops are deterministic")
    func dropDeterministic() throws {
        let r = try reg()
        let region = Region(name: "Vault", coord: HexCoord(3, 0), kind: .ruins, biomeID: "plains",
                            hazardLevel: 6, explorationState: .fullyExplored)
        let capital = Settlement(name: "C", kind: .capital, population: 1, storage: [:], storageCapacity: 9999)
        let world = WorldState(mapSeed: 9, settlements: [capital], regions: [region])
        let a = SiteEngine.interact(world, regionID: region.id, registry: r)!.0
        let b = SiteEngine.interact(world, regionID: region.id, registry: r)!.0
        #expect(a == b)
    }
}
