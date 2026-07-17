import Testing
import Foundation
@testable import EndlessFrontierCore

/// Reported from a real game: "I sent an expedition somewhere and nothing
/// happened, even after ticks." Nothing *did* happen — the colony was down to 3
/// materials and an expedition costs fifteen, so `startExpedition` returned the
/// state unchanged and the tap fell into a hole. The engine is right to refuse;
/// the sin is refusing in silence, with the button still lit.
@Suite("An expedition you cannot afford must say so")
struct ExpeditionAffordabilityTests {
    private func world(food: Double, materials: Double) -> WorldState {
        let region = Region(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C0")!,
            name: "Beyond", coord: HexCoord(1, 0), kind: .wilderness,
            biomeID: "plains", hazardLevel: 1, explorationState: .unknown)
        let home = Region(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!,
            name: "Home", coord: HexCoord(0, 0), kind: .wilderness,
            biomeID: "plains", hazardLevel: 0, explorationState: .fullyExplored)
        var state = Fixtures.world(food: food, materials: materials)
        state.regions = [home, region]
        return state
    }

    private var target: UUID { UUID(uuidString: "00000000-0000-0000-0000-0000000000C0")! }

    @Test("A colony that can pay reports it can, and the expedition leaves")
    func affordableExpeditionLeaves() {
        let reg = Fixtures.registry(config: .default)
        let rich = world(food: 500, materials: 500)
        #expect(ExplorationEngine.canAfford(expeditionTo: rich.regions[1], in: rich, registry: reg))

        let after = ExplorationEngine.startExpedition(rich, targetRegionID: target, registry: reg)
        #expect(after.activeExpedition?.targetRegionID == target)
    }

    /// The exact state from the report: a granary full of food and a woodpile
    /// down to nothing.
    @Test("A colony that cannot pay reports that, rather than failing silently")
    func brokeColonyIsHonest() {
        let reg = Fixtures.registry(config: .default)
        let broke = world(food: 750, materials: 3)
        #expect(!ExplorationEngine.canAfford(expeditionTo: broke.regions[1], in: broke, registry: reg),
                "the UI has to be able to ask *before* the player taps into silence")

        let after = ExplorationEngine.startExpedition(broke, targetRegionID: target, registry: reg)
        #expect(after.activeExpedition == nil, "and the engine still refuses")
    }

    @Test("What it costs is something the game can be asked")
    func costIsAnswerable() {
        let reg = Fixtures.registry(config: .default)
        let state = world(food: 500, materials: 500)
        let cost = ExplorationEngine.expeditionCost(to: state.regions[1], config: reg.config)
        #expect(cost[.materials] > 0)
        #expect(cost[.food] > 0)
    }

    @Test("A dearer, more dangerous region costs more")
    func hazardCostsMore() {
        let reg = Fixtures.registry(config: .default)
        var state = world(food: 500, materials: 500)
        let safe = ExplorationEngine.expeditionCost(to: state.regions[1], config: reg.config)
        state.regions[1].hazardLevel = 8
        let deep = ExplorationEngine.expeditionCost(to: state.regions[1], config: reg.config)
        #expect(deep[.materials] > safe[.materials])
    }
}
