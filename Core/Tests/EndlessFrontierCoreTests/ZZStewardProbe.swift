import Testing
import Foundation
@testable import EndlessFrontierCore

/// What the colony does when **the council runs it** — as distinct from
/// `BalanceHarnessTests`, which layers a hand-rolled policy on top and, because
/// `StewardEngine` acts only in the gaps, silently suppresses the autopilot the
/// game actually ships. That harness measures a player nobody is.
///
/// This probe drives nothing. `TickEngine.advance` already calls
/// `StewardEngine.advanceOneTick` every tick, so an untouched world *is* the
/// shipped game left alone for two hundred years.
@Suite("steward", .enabled(if: ProcessInfo.processInfo.environment["EF_DIAG"] != nil, "diag"))
struct ZZStewardProbe {
    /// Energy is the suspect: demand scales with **people**
    /// (`domesticEnergyDemand` = population x rate x era multiplier) while
    /// supply scales with **buildings**, and the valley caps buildings. So the
    /// columns to read together are `pop`, `Edem` and `Emake`.
    @Test("the council alone, two centuries")
    func councilAlone() throws {
        let registry = try GameDataRegistry.bundled()
        let config = registry.config

        for seed: UInt64 in [2025, 4242] {
            var state = GameWorldFactory.newGame(registry: registry, seed: seed)
            print("\n=== seed \(seed) — council alone ===")
            print("year  pop  era              food shelf cook farm lying Edem Emake  bldg plot/want  mats timbr able town/able  picks")

            for step in 1...20 {
                state = TickEngine.advance(state, ticks: 600, registry: registry).state
                guard let s = state.settlements.first else { break }

                let demand = ResourceLoop.domesticEnergyDemand(
                    population: s.population, era: state.era, config: config)
                let made = s.buildings.reduce(0.0) { acc, b in
                    acc + (registry.building(b.definitionID)?.production[.energy] ?? 0)
                        * Double(b.count)
                }
                let plots = FarmEngine.plotsStanding(s)
                let want = FarmEngine.plotsWanted(for: s.population)
                let food = s.storage[ResourceType.food]
                let energy = s.storage[ResourceType.energy]

                // What the council can actually reach for, and what it picks.
                // Guessing at the clause ordering from the outside was wrong
                // once already: `Emake` stayed flat at one windmill while demand
                // outgrew it, and deleting the clause I suspected changed the
                // trace by not one digit. So ask the engine instead.
                let buildable = StewardEngine.buildableHere(s, in: state, registry: registry)
                let pick = StewardEngine.nextBuilding(for: s, in: state, registry: registry)
                let timber = CraftingEngine.materialCounts(s)["timber_bundle"] ?? 0

                // The food chain, link by link. `plots` against `want` already
                // says the ground is not short — twice over — and the larder
                // still empties in a decade, so the answer is between the two.
                //
                // `shelf` is raw crop waiting to be cooked; `cooks` is who can
                // cook it. Full shelf + empty larder = the kitchen. Empty shelf
                // + standing crop = reaping or hauling. Guessing at this from
                // the outside has been wrong twice.
                let shelf = CookingEngine.foodstuffs(registry)
                    .reduce(0) { $0 + s.stockpile[$1, default: 0] }
                let cooks = s.pawns.count { $0.assignedWork == .cooking }
                let farmers = s.pawns.count { $0.assignedWork == .farming }
                // Goods reaped and lying where they fell. If this climbs while
                // the shelf stays empty, nobody is carrying the harvest in.
                let lying = s.localMap?.piles.reduce(0) { $0 + $1.amount } ?? 0
                let towns = state.settlements.count
                let foundable = ExpansionEngine.foundableRegions(state).count

                _ = energy
                print(String(format: "%4d %4d  %-15@ %5d %5d %4d %4d %4d %5.1f %5.1f %5d %4d/%-4d %6d %5d %4d %4d/%-4d  %@",
                             step * 10,
                             s.pawns.count,
                             state.era.rawValue as NSString,
                             Int(food.rounded()),
                             shelf, cooks, farmers, lying,
                             demand, made,
                             s.buildings.reduce(0) { $0 + $1.count },
                             plots, want,
                             Int(s.storage[ResourceType.materials].rounded()),
                             timber,
                             buildable.count,
                             towns, foundable,
                             (pick ?? "—") as NSString))
            }
        }
        print("")
    }
}
