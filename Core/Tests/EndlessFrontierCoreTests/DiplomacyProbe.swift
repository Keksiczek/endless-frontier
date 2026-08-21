import Testing
import Foundation
@testable import EndlessFrontierCore

/// **What the neighbours actually do, over two centuries.**
///
/// `docs/NEIGHBOURS.md` puts this first on purpose. Today cost four rounds of
/// tuning a road system that was already correct, because the numbers came
/// after the changes instead of before them (rule 68), and the diplomacy layer
/// has the same shape of risk: a `standing` that drifts to a compatibility
/// nobody can move, a `grudge` that decays faster than anything can build it,
/// a war chance nothing ever reaches. §8.5 already caught one of exactly that
/// kind — two hundred years, six peoples, and every one of the twenty-six
/// fights in the run was wolves.
///
/// So this prints the shape of the relationship rather than asserting anything
/// about it: where standings sit, whether grudge goes anywhere, how many wars
/// and raids there were, and — the column the new verbs will live or die by —
/// **how far standing actually moves on its own**. A verb that adds five to a
/// number that swings forty by itself is a verb nobody will feel.
///
/// ```
/// EF_PROBE=1 swift test --package-path Core --filter DiplomacyProbe
/// ```
@Suite("The neighbours, measured", .enabled(
    if: ProcessInfo.processInfo.environment["EF_PROBE"] != nil,
    "a measuring instrument — set EF_PROBE=1 to run it"))
struct DiplomacyProbe {

    @Test("Two hundred years of living next door to somebody")
    func theNeighbours() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)

        // Standings move slowly and a snapshot every twenty years hides how far
        // they travelled in between. The band each people has *ever* occupied
        // is what says whether a verb worth five points would be felt at all.
        var lowest: [UUID: Double] = [:]
        var highest: [UUID: Double] = [:]
        var worstGrudge: [UUID: Double] = [:]
        var wars = 0
        var fights = Set<UUID>()

        print("""

        ── neighbours ────────────────────────────────────────────────
        year  met  │ standing: worst  best  mean │ grudge: worst mean │ wars  fights
        """)

        for step in 1...20 {
            for _ in 0..<10 {
                state = BalanceHarness.autoPlay(state, registry: registry)
                state = TickEngine.advance(state, ticks: 60, registry: registry).state
                for tribe in state.tribes where tribe.discovered {
                    lowest[tribe.id] = min(lowest[tribe.id] ?? tribe.standing, tribe.standing)
                    highest[tribe.id] = max(highest[tribe.id] ?? tribe.standing, tribe.standing)
                    worstGrudge[tribe.id] = max(worstGrudge[tribe.id] ?? 0, tribe.grudge)
                }
                wars = max(wars, state.tribes.reduce(0) { $0 + $1.wars })
                if let log = state.settlements.first?.lastBattle { fights.insert(log.id) }
            }
            let met = state.tribes.filter(\.discovered)
            guard !met.isEmpty else {
                print(String(format: "%4d    0  │ ", step * 10) + "nobody has been met yet")
                continue
            }
            let standings = met.map(\.standing)
            let grudges = met.map(\.grudge)
            print(String(
                format: "%4d %4d  │ %14.0f %5.0f %5.0f │ %13.0f %4.0f │ %4d %6d",
                step * 10, met.count,
                standings.min() ?? 0, standings.max() ?? 0,
                standings.reduce(0, +) / Double(standings.count),
                grudges.max() ?? 0, grudges.reduce(0, +) / Double(grudges.count),
                wars, fights.count))
        }

        // **The band, which is the number the new verbs are sized against.**
        // A people whose standing has only ever moved between 58 and 64 is one
        // no gift, embassy or road will ever noticeably shift — and that is the
        // §8.5 fault ("nothing could make a people angry that was not angry
        // already") wearing a friendlier face.
        print("\n  people                 standing seen        grudge peak")
        for tribe in state.tribes.filter(\.discovered).sorted(by: { $0.name < $1.name }) {
            // Padded in Swift rather than by the formatter: `%@`/`%s` and a
            // Swift String do not mix, and the first cut printed "0š1SÝ".
            let name = tribe.name.padding(toLength: 22, withPad: " ", startingAt: 0)
            print("  " + name + String(
                format: " %5.0f … %-5.0f (%3.0f)   %5.0f",
                lowest[tribe.id] ?? 0, highest[tribe.id] ?? 0,
                (highest[tribe.id] ?? 0) - (lowest[tribe.id] ?? 0),
                worstGrudge[tribe.id] ?? 0))
        }
        print("──────────────────────────────────────────────────────────────\n")

        #expect(!state.tribes.filter(\.discovered).isEmpty,
                "two hundred years and the colony never met anybody — the probe measured nothing")
    }
}
