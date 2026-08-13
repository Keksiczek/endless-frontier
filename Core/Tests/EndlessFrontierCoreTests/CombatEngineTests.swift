import Foundation
import Testing
@testable import EndlessFrontierCore

/// Arms have class and weight now: bows volley before the walls, blades hold
/// them, armor blunts what lands, and a scythe is no longer a sword.
@Suite("Combat engine")
struct CombatEngineTests {
    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private func fighter(_ n: Int, weapon: String? = nil, armor: String? = nil) -> Pawn {
        var pawn = Pawn(
            id: UUID(uuidString: String(format: "EEEEEEEE-0000-0000-0000-%012d", n))!,
            name: "F\(n)", assignedWork: .farming)
        if let weapon { pawn.equipment[.weapon] = ItemInstance(definitionID: weapon) }
        if let armor { pawn.equipment[.armor] = ItemInstance(definitionID: armor) }
        return pawn
    }

    @Test("Weapons decode with their combat profiles from items.json")
    func weaponsDecode() throws {
        let reg = try registry()
        #expect(reg.item("iron_sword")?.combat?.kind == .melee)
        #expect(reg.item("hunting_bow")?.combat?.kind == .ranged)
        #expect((reg.item("marksman_rifle")?.combat?.damage ?? 0) > (reg.item("hunting_bow")?.combat?.damage ?? 0))
        // A tool still counts for something — but far less than a true blade.
        let axe = reg.item("sturdy_axe")?.combat?.damage ?? 0
        let sword = reg.item("iron_sword")?.combat?.damage ?? 0
        #expect(axe > 0 && axe < sword)
    }

    @Test("Militia splits by weapon class, and arms outweigh bare hands")
    func militiaSplit() throws {
        let reg = try registry()
        let unarmed = CombatEngine.militia([fighter(1)], registry: reg)
        let sworded = CombatEngine.militia([fighter(2, weapon: "iron_sword")], registry: reg)
        let bowed = CombatEngine.militia([fighter(3, weapon: "hunting_bow")], registry: reg)

        #expect(unarmed.ranged == 0 && unarmed.melee > 0)
        #expect(sworded.melee > unarmed.melee)
        #expect(bowed.ranged > 0)
        #expect(CombatEngine.rangedCount([fighter(3, weapon: "hunting_bow"), fighter(4)],
                                         registry: reg) == 1)
    }

    @Test("Armor halves a wound; a weapon no longer does")
    func armorBlunts() {
        #expect(CombatEngine.woundMultiplier(fighter(1, armor: "leather_garb")) == 0.5)
        #expect(CombatEngine.woundMultiplier(fighter(2, weapon: "iron_sword")) == 1.0)
    }

    @Test("Archers on the wall turn a raid that unarmed defenders lose")
    func rangedDefendersRepelRaids() throws {
        let reg = try registry()
        func raidOutcome(weapon: String?) -> (food: Double, journal: String) {
            let pawns = (0..<8).map { fighter($0, weapon: weapon) }
            let capital = Settlement(
                id: UUID(uuidString: "EEEEEEEE-1111-0000-0000-000000000001")!,
                name: "C", kind: .capital, pawns: pawns,
                storage: [.food: 400], storageCapacity: .uniform(999),
                stats: SettlementStats(defense: 0))   // walls out of the equation
            var world = WorldState(settlements: [capital])
            world.tribes = [Tribe(
                id: UUID(uuidString: "EEEEEEEE-2222-0000-0000-000000000001")!,
                name: "Raiders", foundedTick: 0, originStory: LocalizedText("They left."),
                population: 60,
                genes: Genes(industry: 0.5, fertility: 0.5, sociability: 0.2, courage: 0.9),
                standing: -80)]
            var rng = SeededRNG(seed: 99)
            let opened = DiplomacyEngine.raid(world, tribeIndex: 0, capitalIndex: 0,
                                              registry: reg, rng: &rng)
            // The raid opens a siege now; it is decided once the action clock
            // has carried it to the end.
            let after = SiegeTestSupport.fightItOut(opened, registry: reg)
            let line = after.settlements[0].journal.entries.last?.text.resolve(.en) ?? ""
            return (after.settlements[0].storage[.food], line)
        }
        let unarmed = raidOutcome(weapon: nil)
        let crossbows = raidOutcome(weapon: "crossbow")
        #expect(crossbows.food > unarmed.food)          // less loot got away
        #expect(!crossbows.journal.isEmpty)             // and the day was recorded
    }

    @Test("Raiders bleed for attacking a defended wall")
    func raidersTakeLosses() throws {
        let reg = try registry()
        let pawns = (0..<10).map { fighter($0, weapon: "crossbow") }
        let capital = Settlement(
            id: UUID(uuidString: "EEEEEEEE-1111-0000-0000-000000000002")!,
            name: "C", kind: .capital, pawns: pawns,
            storage: [.food: 400], storageCapacity: .uniform(999))
        var world = WorldState(settlements: [capital])
        world.tribes = [Tribe(
            id: UUID(uuidString: "EEEEEEEE-2222-0000-0000-000000000002")!,
            name: "Raiders", foundedTick: 0, originStory: LocalizedText("They left."),
            population: 40, genes: Genes(), standing: -80)]
        var rng = SeededRNG(seed: 5)
        let opened = DiplomacyEngine.raid(world, tribeIndex: 0, capitalIndex: 0,
                                          registry: reg, rng: &rng)
        // What the attempt cost them is known when the fighting stops, not
        // when it was declared.
        let after = SiegeTestSupport.fightItOut(opened, registry: reg)
        #expect(after.tribes[0].population < 40)
    }

    @Test("Ranged hunters push predator pressure below the unarmed baseline")
    func rangedHuntersSuppressPredators() throws {
        let reg = try registry()
        func pressureAfterYears(weapon: String?) -> Double {
            var pawns = (0..<6).map { fighter($0, weapon: weapon) }
            for i in pawns.indices { pawns[i].assignedWork = .hunting; pawns[i].age = 30 * 60 }
            var s = Settlement(
                id: UUID(uuidString: "EEEEEEEE-3333-0000-0000-000000000001")!,
                name: "C", kind: .capital, pawns: pawns,
                storage: [.food: 400], storageCapacity: .uniform(999))
            s.localMap = LocalMapGenerator.generate(
                mapSeed: 3, regionID: UUID(uuidString: "EEEEEEEE-3333-0000-0000-000000000002")!,
                biome: nil)
            for tick in 0..<600 {
                s = WildlifeEngine.advanceOneTick(s, registry: reg, tick: tick,
                                                  era: .earlySettlement, mapSeed: 3)
            }
            return s.localMap?.wildlife.predatorPressure ?? 0
        }
        #expect(pressureAfterYears(weapon: "longbow") < pressureAfterYears(weapon: nil))
    }
}
