import Foundation
@testable import EndlessFrontierCore

/// Makes one of something, the way the colony now does.
///
/// Crafting used to be a call: `GameEngine.craft(world, recipeID:)` consumed the
/// stockpile and produced the item on the spot, made by nobody. It is work at a
/// bench now, so a test that wants a finished sword has to put the order on the
/// bench, make sure somebody is standing at it, and let the ticks run.
///
/// Everything about *what* a craft costs and produces is unchanged — that is
/// exactly what these tests are still checking. Only the route changed.
enum BenchTestSupport {

    /// Places an order, seats a crafter if the colony has none, and works ticks
    /// until it comes off the bench (or `ticks` run out).
    static func craft(
        _ state: WorldState, recipeID: String, count: Int = 1,
        settlementID: UUID? = nil, registry: GameDataRegistry, ticks: Int = 600
    ) -> WorldState {
        guard let index = CraftingEngine.targetIndex(state, settlementID) else { return state }
        var s = state
        s.settlements[index] = seatCrafter(s.settlements[index], registry: registry)
        s.settlements[index] = CraftingEngine.place(
            s.settlements[index], recipeID: recipeID, count: count,
            tick: s.tick, registry: registry)
        for _ in 0..<ticks {
            s.settlements[index] = CraftingEngine.advanceOneTick(
                s.settlements[index], tick: s.tick,
                researched: s.researchedTechs, registry: registry)
            if s.settlements[index].craftOrders.isEmpty { break }
        }
        return s
    }

    /// A colony with nobody at the bench makes nothing, which is the point of
    /// the change — so a test that wants a thing made gets one hand for free.
    static func seatCrafter(
        _ settlement: Settlement, registry: GameDataRegistry
    ) -> Settlement {
        guard !settlement.pawns.contains(where: { $0.assignedWork == .crafting })
        else { return settlement }
        var s = settlement
        let adult = Pawn.adultAgeYears * registry.config.ticksPerYear
        // Somebody already here, if anybody is; otherwise a smith walks in.
        if let index = s.pawns.firstIndex(where: { $0.age >= adult && !$0.isBroken }) {
            s.pawns[index].assignedWork = .crafting
            return s
        }
        var smith = Pawn(
            id: UUID(uuidString: "B0BE0000-0000-0000-0000-00000000BEEF")!,
            name: "Bench-hand", assignedWork: .crafting)
        smith.age = 30 * registry.config.ticksPerYear
        s.pawns.append(smith)
        return s
    }
}
