import Foundation
import Testing
@testable import EndlessFrontierCore

/// Settlement specialisations reshape production: a sharp edge in one direction
/// with a standing-stat consequence. `balanced` must stay a no-op so older
/// behaviour and saves are preserved.
@Suite("Settlement specialisations")
struct SpecializationTests {
    private func reg() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    /// One settlement (no colonists, so production is unconfounded by upkeep),
    /// stocked with the given buildings and specialisation.
    private func world(spec: SettlementSpecialization, buildings: [String]) -> WorldState {
        let bld = buildings.map { BuildingInstance(definitionID: $0, count: 1) }
        let s = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-5eceda7ce01f")!, name: "S", kind: .capital, pawns: [],
                           buildings: bld, storage: Resources(), storageCapacity: .uniform(99999),
                           specialization: spec)
        return WorldState(settlements: [s])
    }

    /// How much crop is standing in the settlement's fields after `ticks`.
    ///
    /// Measured at the **plots**, not at `storage[.food]`, because that is where
    /// a settlement's bent now applies. Food used to come out of
    /// `production[.food]` on the farm building, so multiplying that number was
    /// the whole of specialisation; a farm is a place that owns ground now
    /// (`FarmEngine`), and what an agricultural town is better at is *growing*.
    /// Reading the granary here would measure the cook instead — and this world
    /// deliberately has no colonists, so nobody reaps and nobody cooks.
    private func standingCrop(
        after ticks: Int, spec: SettlementSpecialization, registry: GameDataRegistry
    ) -> Double {
        var w = world(spec: spec, buildings: ["farm_basic", "farm_basic"])
        // Plots need ground to stand on: a layout, and a map to put it on.
        w.settlements[0].colony = ColonyBuilder.seededLayout(
            for: w.settlements[0].buildings, registry: registry)
        w.settlements[0].localMap = LocalMapGenerator.generate(
            mapSeed: 11, regionID: w.settlements[0].id, biome: registry.biome("plains"))
        w.settlements[0] = FarmEngine.reconcile(w.settlements[0], registry: registry)
        #expect(!w.settlements[0].localMap!.crops.isEmpty, "two farms have to have fields")
        for _ in 0..<ticks { w = ResourceLoop.advanceOneTick(w, registry: registry) }
        return w.settlements[0].localMap!.crops.reduce(0) { $0 + $1.growth }
    }

    @Test("Agricultural grows its crops faster than balanced")
    func agriculturalBoostsFood() throws {
        let r = try reg()
        let balanced = standingCrop(after: 10, spec: .balanced, registry: r)
        let agricultural = standingCrop(after: 10, spec: .agricultural, registry: r)
        #expect(agricultural > balanced)
    }

    @Test("Industrial runs dirtier than balanced")
    func industrialRaisesPollution() throws {
        let r = try reg()
        // quarry produces materials and some pollution; the flat adds more.
        var balanced = world(spec: .balanced, buildings: ["quarry"])
        var industrial = world(spec: .industrial, buildings: ["quarry"])
        for _ in 0..<20 {
            balanced = ResourceLoop.advanceOneTick(balanced, registry: r)
            industrial = ResourceLoop.advanceOneTick(industrial, registry: r)
        }
        #expect(industrial.settlements[0].stats.pollution > balanced.settlements[0].stats.pollution)
        #expect(industrial.settlements[0].storage[.materials] > balanced.settlements[0].storage[.materials])
    }

    @Test("Fortified settlements hold a higher standing defense")
    func fortifiedRaisesDefense() throws {
        let r = try reg()
        var balanced = world(spec: .balanced, buildings: [])
        var fortified = world(spec: .fortified, buildings: [])
        for _ in 0..<30 {
            balanced = ResourceLoop.advanceOneTick(balanced, registry: r)
            fortified = ResourceLoop.advanceOneTick(fortified, registry: r)
        }
        #expect(fortified.settlements[0].stats.defense > balanced.settlements[0].stats.defense)
    }

    @Test("Scholarly settlements raise global knowledge output")
    func scholarlyBoostsKnowledge() throws {
        let r = try reg()
        let balanced = ResourceLoop.advanceOneTick(world(spec: .balanced, buildings: ["library"]), registry: r)
        let scholarly = ResourceLoop.advanceOneTick(world(spec: .scholarly, buildings: ["library"]), registry: r)
        #expect(scholarly.globalStats.knowledgeOutput > balanced.globalStats.knowledgeOutput)
    }

    @Test("A mercantile source ships more down a trade route")
    func mercantileBoostsTradeThroughput() throws {
        func delivered(sourceSpec: SettlementSpecialization) -> Double {
            let source = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-c1b765057783")!, name: "Src", kind: .capital,                                     storage: [.food: 1000], storageCapacity: .uniform(99999), specialization: sourceSpec)
            let dest = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-b8ab6a014f51")!, name: "Dst", kind: .city,                                   storage: Resources(), storageCapacity: .uniform(99999))
            var w = WorldState(settlements: [source, dest])
            w.tradeRoutes = [TradeRoute(fromID: source.id, toID: dest.id, resource: .food, amountPerTick: 10)]
            let after = MultiCityEngine.applyTradeRoutes(w)
            return after.settlements[1].storage[.food]
        }
        #expect(delivered(sourceSpec: .mercantile) > delivered(sourceSpec: .balanced))
    }

    @Test("Balanced leaves the economy identical to an unspecialised settlement")
    func balancedIsANoOp() throws {
        let r = try reg()
        // A settlement constructed without naming a specialisation defaults to
        // balanced and must tick identically to an explicitly-balanced one.
        let implicit = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-a795a6871ea9")!, name: "S", kind: .capital,                                   buildings: [BuildingInstance(definitionID: "farm_basic")],
                                  storageCapacity: .uniform(99999))
        let explicitBalanced = world(spec: .balanced, buildings: ["farm_basic"])
        var a = WorldState(settlements: [implicit])
        var b = explicitBalanced
        for _ in 0..<15 {
            a = ResourceLoop.advanceOneTick(a, registry: r)
            b = ResourceLoop.advanceOneTick(b, registry: r)
        }
        #expect(a.settlements[0].storage[.food] == b.settlements[0].storage[.food])
    }

    @Test("Switching specialisation costs stability; re-confirming the same one does not")
    func switchingCostsStability() throws {
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-aad09d117bc3")!, name: "S", kind: .capital, specialization: .balanced)
        s.stats.stability = 80
        let w = WorldState(settlements: [s])
        let switched = GameEngine.setSpecialization(w, settlementID: s.id, specialization: .industrial)
        #expect(switched.settlements[0].stats.stability < 80)
        // Re-confirming the same specialisation is a no-op for stability.
        let again = GameEngine.setSpecialization(switched, settlementID: s.id, specialization: .industrial)
        #expect(again.settlements[0].stats.stability == switched.settlements[0].stats.stability)
    }

    @Test("Specialisation survives a save round-trip")
    func roundTrips() throws {
        let original = world(spec: .industrial, buildings: ["quarry"])
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(WorldState.self, from: data)
        #expect(restored.settlements[0].specialization == .industrial)
    }

    @Test("Pre-specialisation saves decode to balanced")
    func legacySaveDefaultsToBalanced() throws {
        // Encode a settlement, then strip the specialisation key to simulate a
        // save written before the field existed.
        let s = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-4912fee66873")!, name: "Old", kind: .capital, specialization: .scholarly)
        let data = try JSONEncoder().encode(s)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "specialization")
        let stripped = try JSONSerialization.data(withJSONObject: json)
        let restored = try JSONDecoder().decode(Settlement.self, from: stripped)
        #expect(restored.specialization == .balanced)
    }
}
