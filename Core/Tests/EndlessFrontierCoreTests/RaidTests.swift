import Testing
import Foundation
@testable import EndlessFrontierCore

@Suite("Raids & defense")
struct RaidTests {
    private func capitalWorld(defense: Double, materials: Double = 100,
                              food: Double = 100, pawns: [Pawn] = []) -> WorldState {
        var capital = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-d77439b698b1")!, name: "C", kind: .capital,                                  pawns: pawns, storage: [.materials: materials, .food: food],
                                 storageCapacity: .uniform(999))
        capital.stats.defense = defense
        return WorldState(settlements: [capital])
    }

    /// A colonist with something in their hands. An unarmed colony does not
    /// hold a wall, whatever `stats.defense` says — which is the point of the
    /// change these tests follow.
    private func armed(_ name: String) -> Pawn {
        var p = Pawn(name: name, assignedWork: .garrison, health: 100)
        p.equipment[EquipmentSlot.weapon] = ItemInstance(definitionID: "sturdy_axe")
        return p
    }

    /// **Fight the raid out.**
    ///
    /// A storyteller raid used to be resolved by the effect itself, so a test
    /// could apply it and read the wreckage on the next line. It opens a
    /// `Siege` now, exactly as every other raid does — the effect is the
    /// warband arriving and the fight is action steps. `ActionLoop` walks those
    /// on the world clock; a test walks them here.
    private func fought(_ world: WorldState, registry: GameDataRegistry) -> WorldState {
        var w = world
        guard let siege = w.settlements[0].siege else { return w }
        w.settlements[0] = SiegeEngine.advance(
            w.settlements[0], to: siege.openedAt + siege.steps + 2, registry: registry)
        w.settlements[0] = SiegeEngine.conclude(w.settlements[0], registry: registry)
        return w
    }

    /// **A wall with nobody behind it is not a defence.** This used to be a
    /// colony of *no people* with `stats.defense: 30`, and the old resolution
    /// compared two numbers and turned the raid away. A raid is a siege now, and
    /// a siege is fought by a line — so the fixture musters one, which is what
    /// "well defended" means in a game where a colony is its colonists.
    @Test("A well-defended raid is repelled and the stores are not touched")
    func repelled() throws {
        var world = capitalWorld(defense: 30,
                                 pawns: (0..<10).map { armed("Guard \($0)") })
        world.globalStats.threatLevel = 60
        // The shipped book, because an axe is only an axe where one is defined
        // — the fixture registry has no combat profile to weigh.
        let reg = try GameDataRegistry.bundled()
        let after = fought(EffectApplier.apply([.raid(strength: 25)], to: world, registry: reg),
                           registry: reg)
        #expect(after.settlements[0].lastBattle?.repelled == true)
        #expect(after.settlements[0].storage[.food] == 100)        // nothing carried off
        #expect(after.globalStats.threatLevel < 60)
    }

    @Test("An undefended raid costs resources, stability and wounds a colonist")
    func overrun() {
        let reg = Fixtures.registry()
        let world = capitalWorld(defense: 0, materials: 100,
                                 pawns: [Pawn(name: "Guard", health: 100)])
        let after = fought(EffectApplier.apply([.raid(strength: 25)], to: world, registry: reg),
                           registry: reg)
        // What a warband that gets in carries away is what it can reach: the
        // **food** off the shelves, step by step (`plunderPerStep`).
        #expect(after.settlements[0].storage[.food] < 100)
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
        let reg = Fixtures.registry()
        let world = capitalWorld(defense: 0, materials: 100,
                                 pawns: [Pawn(name: "Guard", health: 100)])
        let after = fought(EffectApplier.apply([.raid(strength: 25)], to: world, registry: reg),
                           registry: reg)
        let log = after.settlements[0].lastBattle
        #expect(log != nil)
        #expect(log?.repelled == false)
        #expect((log?.moments.contains { $0.kind == .charge }) == true)
        #expect((log?.moments.contains { $0.kind == .clash }) == true)
    }

    @Test("A repelled raid is recorded as held")
    func repelledLeavesLog() throws {
        var world = capitalWorld(defense: 40,
                                 pawns: (0..<10).map { armed("Guard \($0)") })
        world.globalStats.threatLevel = 60
        let reg = try GameDataRegistry.bundled()
        let after = fought(EffectApplier.apply([.raid(strength: 20)], to: world, registry: reg),
                           registry: reg)
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
