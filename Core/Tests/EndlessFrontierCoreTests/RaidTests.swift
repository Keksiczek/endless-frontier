import Testing
import Foundation
@testable import EndlessFrontierCore

@Suite("Raids & defense")
struct RaidTests {
    private func capitalWorld(defense: Double, materials: Double = 100, pawns: [Pawn] = []) -> WorldState {
        var capital = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-d77439b698b1")!, name: "C", kind: .capital,                                  pawns: pawns, storage: [.materials: materials, .food: 100],
                                 storageCapacity: .uniform(999))
        capital.stats.defense = defense
        return WorldState(settlements: [capital])
    }

    @Test("A well-defended raid is repelled with a morale lift, no losses")
    func repelled() {
        var world = capitalWorld(defense: 30)
        world.globalStats.threatLevel = 60
        let after = EffectApplier.apply([.raid(strength: 25)], to: world, registry: Fixtures.registry())
        #expect(after.settlements[0].storage[.materials] == 100)   // nothing lost
        #expect(after.settlements[0].stats.morale > world.settlements[0].stats.morale)
        #expect(after.globalStats.threatLevel < 60)
    }

    @Test("An undefended raid costs resources, stability and wounds a colonist")
    func overrun() {
        let world = capitalWorld(defense: 0, materials: 100, pawns: [Pawn(name: "Guard", health: 100)])
        let after = EffectApplier.apply([.raid(strength: 25)], to: world, registry: Fixtures.registry())
        #expect(after.settlements[0].storage[.materials] < 100)
        #expect(after.settlements[0].stats.stability < 60)
        #expect((after.settlements[0].pawns.first?.health ?? 100) < 100)
    }

    @Test("Defensive buildings raise a settlement's defense over time")
    func buildingsGrantDefense() throws {
        let reg = try GameDataRegistry.bundled()
        var settlement = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-47f2bc92ebfc")!, name: "Fort", kind: .capital, pawns: Fixtures.pawns(10),
                                    buildings: [BuildingInstance(definitionID: "palisade", count: 2)],
                                    storage: [.food: 200], storageCapacity: .uniform(999))
        settlement.stats.defense = 0
        var world = WorldState(settlements: [settlement])
        world = TickEngine.advance(world, ticks: 80, registry: reg).state
        // Two palisades provide 24 defense; settlement should approach it.
        #expect(world.settlements[0].stats.defense > 15)
    }

    @Test("Raid is deterministic")
    func deterministic() {
        let world = capitalWorld(defense: 5, pawns: [Pawn(name: "A", health: 80)])
        let a = EffectApplier.apply([.raid(strength: 30)], to: world, registry: Fixtures.registry())
        let b = EffectApplier.apply([.raid(strength: 30)], to: world, registry: Fixtures.registry())
        #expect(a == b)
    }

    @Test("An overrun raid leaves a battle log the canvas and report can read")
    func overrunLeavesLog() {
        let world = capitalWorld(defense: 0, materials: 100, pawns: [Pawn(name: "Guard", health: 100)])
        let after = EffectApplier.apply([.raid(strength: 25)], to: world, registry: Fixtures.registry())
        let log = after.settlements[0].lastBattle
        #expect(log != nil)
        #expect(log?.repelled == false)
        #expect((log?.moments.contains { $0.kind == .charge }) == true)
        #expect((log?.moments.contains { $0.kind == .clash }) == true)
    }

    @Test("A repelled raid is recorded as held")
    func repelledLeavesLog() {
        var world = capitalWorld(defense: 40)
        world.globalStats.threatLevel = 60
        let after = EffectApplier.apply([.raid(strength: 20)], to: world, registry: Fixtures.registry())
        #expect(after.settlements[0].lastBattle?.repelled == true)
    }

    @Test("Shipped data includes the raid event and defensive buildings")
    func bundledData() throws {
        let reg = try GameDataRegistry.bundled()
        #expect(reg.events.contains { $0.id == "raider_warband" })
        #expect((reg.building("palisade")?.defense ?? 0) > 0)
        #expect((reg.building("barracks")?.defense ?? 0) > 0)
    }
}
