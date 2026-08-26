import Testing
import Foundation
@testable import EndlessFrontierCore

/// **Where the wood goes.**
///
/// A hundred and twenty-three of the four hundred and eleven recipes consume
/// raw `wood` — thirty per cent of the book, and by a distance the most
/// contested material in the game. On Keks's save at year 155 every one of the
/// eight standing orders read *"Short of materials"*, every weapon recipe past
/// the stone age wanted `Wood 0/1`, and the shelf held **zero**.
///
/// The suspicion this was built to test: the council's two standing orders
/// (`Saw Timber`, 3 wood; `Burn Charcoal`, 4 wood) take every scrap as it
/// lands, and `CraftingEngine.yieldsTheBench` cannot stop them because it
/// gates on the *stock of their output* — and a timber bundle is consumed by
/// construction as fast as it is made, so that stock never reaches
/// `standingOrderStock` and the order never stands aside.
///
/// Measures rather than asserts. Run with
///
/// ```
/// EF_PROBE=1 swift test --package-path Core --filter WoodProbe
/// ```
@Suite("Wood, measured", .enabled(
    if: ProcessInfo.processInfo.environment["EF_PROBE"] != nil,
    "a measuring instrument — set EF_PROBE=1 to run it"))
struct WoodProbe {

    @Test("Where the wood goes, over two centuries")
    func theChain() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)

        // How many recipes are competing for it, and who the standing eaters are.
        let onWood = registry.recipes.values.filter { $0.materials["wood"] != nil }
        print("""

        ── wood ──────────────────────────────────────────────────────
        recipes consuming raw wood: \(onWood.count) of \(registry.recipes.count)
        ceiling \(FloraEngine.woodCeiling) · seed stand \(FloraEngine.seedStand) \
        · thin below \(Int(Double(FloraEngine.woodCeiling) * FloraEngine.windBorneBelow)) \
        · a pass every \(LaborEngine.staffingInterval * 5) ticks
        year   pop  loggers  trees  bear  sap  spare  piles   wood  timber  charcoal  orders  blocked  builds
        """)

        for step in 1...20 {
            state = TickEngine.advance(state, ticks: 600, registry: registry).state
            guard let s = state.settlements.first else { break }
            let year = step * 600 / max(1, registry.config.ticksPerYear)
            let loggers = s.pawns.count { $0.assignedWork == .logging }
            let trees = s.localMap?.trees.count ?? 0
            // The three numbers `fell` and `reseeded` actually read.
            let bearing = s.localMap?.trees.count { $0.growth >= FloraEngine.bearingGrowth } ?? 0
            let saplings = trees - bearing
            let spare = max(0, bearing - FloraEngine.seedStand)
            // What is felled and still lying where it fell.
            let piles = HaulEngine.waiting(s)
            let counts = CraftingEngine.materialCounts(s)
            let orders = s.craftOrders.count
            // Orders the bench cannot start for want of an input — the number
            // the player sees as "Short of materials" down the whole panel.
            let blocked = s.craftOrders.count { order in
                guard let recipe = registry.recipes[order.recipeID] else { return false }
                return !CraftingEngine.hasMaterials(recipe, at: s)
            }
            print(String(
                format: "%4d %5d %8d %6d %5d %4d %6d %6d %6d %7d %9d %7d %8d %7d",
                year, s.pawns.count, loggers, trees, bearing, saplings, spare, piles,
                counts["wood"] ?? 0, counts["timber_bundle"] ?? 0,
                counts["charcoal"] ?? 0, orders, blocked, s.buildings.count))
        }

        // …and what the bench was actually holding at the end, so the shape of
        // the shortage is visible rather than inferred.
        if let s = state.settlements.first {
            let counts = CraftingEngine.materialCounts(s)
            let held = counts.filter { $0.value > 0 }.sorted { $0.value > $1.value }
            print("\nheld at the end, most first:")
            print("  " + held.prefix(18).map { "\($0.key) \($0.value)" }.joined(separator: "  ·  "))
            print("\nstanding orders:")
            for order in s.craftOrders {
                guard let recipe = registry.recipes[order.recipeID] else { continue }
                let short = recipe.materials.filter { (counts[$0.key] ?? 0) < $0.value }
                print("  \(recipe.name.resolve(.en)) — made \(order.made), "
                      + "wants \(recipe.materials), short of \(short.keys.sorted())")
            }
        }
    }
}
