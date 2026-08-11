import Testing
import Foundation
@testable import EndlessFrontierCore

@Suite("diag", .enabled(if: ProcessInfo.processInfo.environment["EF_DIAG"] != nil, "diag"))
struct ZZDiagProbe {
    /// Where the colony gets to, and who it ever meets.
    @Test("how far the world gets")
    func reach() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        print("\nyear  pop  era              towns  foundable  peoples  met  wars  prosp  unlocked  buildable")
        for step in 1...20 {
            state = TickEngine.advance(state, ticks: 600, registry: registry).state
            guard let s = state.settlements.first else { break }
            let foundable = ExpansionEngine.foundableRegions(state).count
            let met = state.tribes.count { $0.discovered }
            let wars = state.tribes.count { $0.status == .war }
            let buildable = StewardEngine.buildableHere(s, in: state, registry: registry).count
            print(String(format: "%4d %4d  %-15@ %5d %10d %8d %4d %5d %6.1f %9d %10d",
                         step * 10, s.pawns.count, state.era.rawValue as NSString,
                         state.settlements.count, foundable,
                         state.tribes.count, met, wars,
                         state.globalStats.prosperity,
                         state.unlockedBuildings.count, buildable))
        }
        print("")
    }
}
