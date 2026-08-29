import Testing
import Foundation
@testable import EndlessFrontierCore

/// **Where the iron goes.**
///
/// Carried from `BACKLOG.md` §20.7 and open ever since: on a measured run
/// `iron_ore` stood at **309 in year 90 and 1 in year 200**, against seventeen
/// miners who never stopped working. Three explanations fit that shape and they
/// want telling apart before anything is tuned (rule 72):
///
/// 1. **The seam ran out.** Deposits are finite and nothing replaces them —
///    the shape `ef-materials-exhausted` describes, where every extracted
///    material fell to zero and only the fields regrew.
/// 2. **The benches ate it.** Smelting is a standing order and a standing order
///    never finishes; the ore reaches the shelf and leaves it the same tick.
/// 3. **Nobody was mining.** Seventeen miners *assigned* is not seventeen
///    miners at a face — rule 9c's shape, where the trade exists and the work
///    does not reach it.
///
/// This prints the distribution rather than asserting one of them. Run with
///
/// ```
/// EF_PROBE=1 swift test --package-path Core --filter OreProbe
/// ```
@Suite("Iron, measured", .enabled(
    if: ProcessInfo.processInfo.environment["EF_PROBE"] != nil,
    "a measuring instrument — set EF_PROBE=1 to run it"))
struct OreProbe {

    @Test("Where the iron goes, over two centuries")
    func theSeam() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        let ticksPerYear = registry.config.ticksPerYear

        let onOre = registry.recipes.values.filter {
            $0.materials["iron_ore"] != nil || $0.materials["iron_ingot"] != nil
        }
        print("""

        ── iron ──────────────────────────────────────────────────────
        recipes eating ore or ingots: \(onOre.count) of \(registry.recipes.count)
        year   ore  ingot  miners  atFace  seams  left  orders
        """)

        for year in stride(from: 10, through: 200, by: 10) {
            state = TickEngine.advance(state, ticks: ticksPerYear * 10, registry: registry).state
            guard let town = state.settlements.first else { break }
            let miners = town.pawns.filter { $0.assignedWork == .mining }.count
            // **Assigned is not at work** (rule 9c): who is actually standing at
            // a face this tick, out of who is nominally a miner.
            let atFace = town.pawns.filter { $0.assignedWork == .mining && $0.currentJob != nil }.count
            let seams = town.localMap?.nodes.filter { $0.kind == .ironOre } ?? []
            let left = seams.reduce(0.0) { $0 + $1.amount }
            let orders = town.craftOrders.filter {
                registry.recipes[$0.recipeID]?.materials["iron_ore"] != nil
                    || registry.recipes[$0.recipeID]?.materials["iron_ingot"] != nil
            }.count
            print(String(
                format: "%4d %6d %6d %7d %7d %6d %5.0f %7d",
                year, town.stockpile["iron_ore"] ?? 0, town.stockpile["iron_ingot"] ?? 0,
                miners, atFace, seams.count, left, orders))
        }
        print("──────────────────────────────────────────────────────────────\n")
    }
}
