import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Housing & population cap")
struct HousingTests {
    private func settlement(pop: Int, huts: Int, morale: Double = 80, fertility: Double = 0.5) -> Settlement {
        let pawns = (0..<pop).map { i in
            Pawn(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0001-%012d", i + 1))!,
                name: "Villager \(i + 1)",
                genes: Genes(fertility: fertility)
            )
        }
        return Settlement(name: "Town", kind: .capital, pawns: pawns,
                          buildings: huts > 0 ? [BuildingInstance(definitionID: "hut", count: huts)] : [],
                          storage: [.food: 500], storageCapacity: 999,
                          stats: SettlementStats(morale: morale))
    }

    @Test("Housing capacity is base plus building housing")
    func capacity() throws {
        let reg = try GameDataRegistry.bundled()
        let cap = ResourceLoop.housingCapacity(settlement(pop: 0, huts: 2), registry: reg)
        #expect(cap == ResourceLoop.baseHousing + 60)   // 2 huts * 30
    }

    @Test("Population grows through births when there is housing headroom")
    func growsWithRoom() throws {
        let reg = try GameDataRegistry.bundled()
        // Very fertile founders + two years of ticks → at least one birth.
        var world = WorldState(settlements: [settlement(pop: 10, huts: 1, fertility: 1.0)])
        world = TickEngine.advance(world, ticks: 200, registry: reg).state
        #expect(world.settlements[0].population > 10)
        #expect(world.settlements[0].pawns.contains { $0.age < 200 })   // an actual newborn
    }

    @Test("No conceptions once population reaches housing capacity")
    func cappedAtCapacity() throws {
        let reg = try GameDataRegistry.bundled()
        let cap = Int(ResourceLoop.baseHousing) + 30   // base + 1 hut = 60
        var world = WorldState(settlements: [settlement(pop: cap, huts: 1, fertility: 1.0)])
        world = TickEngine.advance(world, ticks: 100, registry: reg).state
        #expect(world.settlements[0].population <= Double(cap))
    }

    @Test("Crowding surfaces a build-housing objective")
    func crowdedObjective() throws {
        let reg = try GameDataRegistry.bundled()
        // 58 of 60 capacity → ≥ 85% full.
        let world = WorldState(settlements: [settlement(pop: 58, huts: 1)])
        #expect(ObjectivesEngine.current(world, registry: reg, limit: 20).contains { $0.id == "build_housing" })
    }

    @Test("Shipped housing buildings provide housing")
    func bundledHousing() throws {
        let reg = try GameDataRegistry.bundled()
        #expect((reg.building("hut")?.housing ?? 0) > 0)
        #expect((reg.building("longhouse")?.housing ?? 0) > 0)
    }
}
