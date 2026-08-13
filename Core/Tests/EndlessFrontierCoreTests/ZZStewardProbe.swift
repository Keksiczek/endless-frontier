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
            print("year  pop  era              food energy  Edem Emake  bldg plot/want cap morale")

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

                print(String(format: "%4d %4d  %-15@ %5d %6d %5.1f %5.1f %5d %4d/%-4d %4d %6.0f",
                             step * 10,
                             s.pawns.count,
                             state.era.rawValue as NSString,
                             Int(food.rounded()),
                             Int(energy.rounded()),
                             demand, made,
                             s.buildings.reduce(0) { $0 + $1.count },
                             plots, want,
                             Int(ResourceLoop.housingCapacity(s, registry: registry).rounded()),
                             s.stats.morale))
            }
        }
        print("")
    }
}
