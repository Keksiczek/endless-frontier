import Testing
import Foundation
@testable import EndlessFrontierCore

/// A measuring instrument, not a guard rail.
///
/// Two readings of the same system disagree, which is the whole reason this
/// exists. The council diag showed **knowledge banked at 120 against a cap that
/// reaches ten thousand**, which reads as "research income is nearly zero";
/// Keks, playing, says the opposite — *"přijde mi že zkoumají docela rychle a
/// mají to během pár desítek let z většiny za sebou."*
///
/// Both can be true: a bank that stays empty is what a *fast* spender looks
/// like. So this prints the flow rather than the level — what comes in per
/// year, what a tech costs, how much of the tree is done, and how long each one
/// took — because a rate and a stock are different questions (rule 16) and
/// nobody has looked at the rate.
///
/// ```
/// EF_PROBE=1 swift test --package-path Core --filter ResearchProbe
/// ```
@Suite("Research, measured", .enabled(
    if: ProcessInfo.processInfo.environment["EF_PROBE"] != nil,
    "a measuring instrument — set EF_PROBE=1 to run it"))
struct ResearchProbe {

    @Test("Two centuries of a colony studying")
    func theTree() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        let ticksPerYear = max(1, registry.config.ticksPerYear)
        let total = registry.techs.count

        // When each tech was finished, so "most of it in a few decades" is a
        // number rather than an impression.
        var finishedYear: [String: Int] = [:]
        var lastCount = 0
        var bankedLastYear = 0.0
        var incomeSamples: [(year: Int, perYear: Double)] = []

        print("""

        ── research ───────────────────────────────────────────────────
        \(total) techs in the tree. `in` is knowledge banked across the
        colony per year; `cost` is what the *current* study is priced at.

        year | era              | done | banked | in/yr | cost | studying
        """)

        for step in 0..<240 {
            state = BalanceHarness.autoPlay(state, registry: registry)
            let before = banked(state)
            state = TickEngine.advance(state, ticks: 50, registry: registry).state
            let year = state.tick / ticksPerYear

            if state.researchedTechs.count > lastCount {
                for id in state.researchedTechs where finishedYear[id] == nil {
                    finishedYear[id] = year
                }
                lastCount = state.researchedTechs.count
            }

            // What came in over those fifty ticks, scaled to a year. Spending
            // is subtracted by the engine, so this is the *net* the bank saw
            // plus whatever research drew out of it.
            let after = banked(state)
            let drawn = max(0, state.researchProgress)
            _ = drawn
            let perYear = (after - before) / (50.0 / Double(ticksPerYear))
            incomeSamples.append((year, perYear))
            bankedLastYear = after

            if step % 12 == 0 {
                let studying = state.activeResearch ?? "—"
                let price = state.activeResearch.flatMap { registry.tech($0) }
                    .map { TechEngine.cost(of: $0, in: state, config: registry.config) } ?? 0
                print(String(format: "%4d | %-16@ | %3d/%d | %6d | %5.0f | %4d | %@",
                             year, state.era.rawValue,
                             state.researchedTechs.count, total,
                             Int(after), perYear, Int(price), studying))
            }
        }

        // How the tree filled: the decade each tech landed in.
        var byDecade: [Int: Int] = [:]
        for (_, year) in finishedYear { byDecade[year / 10 * 10, default: 0] += 1 }
        let filled = byDecade.keys.sorted().map { "\($0)s:\(byDecade[$0] ?? 0)" }

        // …and what is left, cheapest first — the honest answer to "is any of
        // it still out of reach".
        let remaining = registry.techs.values
            .filter { !state.researchedTechs.contains($0.id) }
            .map { (id: $0.id, cost: TechEngine.cost(of: $0, in: state, config: registry.config)) }
            .sorted { $0.cost < $1.cost }

        print("""
        ───────────────────────────────────────────────────────────────
        finished by decade  \(filled.joined(separator: " "))
        done                \(state.researchedTechs.count)/\(total) \
        (\(Int(Double(state.researchedTechs.count) / Double(max(1, total)) * 100)) %)
        banked now          \(Int(bankedLastYear))
        income per year     min \(Int(incomeSamples.map(\.perYear).min() ?? 0)), \
        max \(Int(incomeSamples.map(\.perYear).max() ?? 0))
        still to study      \(remaining.count) — cheapest \
        \(remaining.prefix(3).map { "\($0.id) \(Int($0.cost))" }.joined(separator: ", "))
        colony              \(state.settlements.first?.pawns.count ?? 0) souls, \
        \(state.settlements.first?.pawns.count { $0.assignedWork == .research } ?? 0) scholars
        ───────────────────────────────────────────────────────────────

        """)
    }

    /// Knowledge banked across every settlement — the stock research draws on.
    private func banked(_ state: WorldState) -> Double {
        state.settlements.reduce(0) { $0 + $1.storage[.knowledge] }
    }
}
