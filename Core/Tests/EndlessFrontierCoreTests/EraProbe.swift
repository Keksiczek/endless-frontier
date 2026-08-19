import Testing
import Foundation
@testable import EndlessFrontierCore

/// **How far up the ladder a colony can actually climb, and what stops it.**
///
/// The question nobody had asked. There are six eras; roughly thirty events,
/// half the tech tree and a hundred items are gated on the top three, and no
/// measurement anywhere says whether a colony left alone ever *reaches* them.
/// Content behind an unreachable gate is content behind glass — the same shape
/// as rule 47, one system up — and the cost of finding out is one probe.
///
/// Off by default like `GrowthProbe` and `DangerProbe`, and for the same
/// reason: it measures rather than asserts.
///
/// ```
/// EF_PROBE=1 swift test --package-path Core --filter EraProbe
/// ```
@Suite("Eras, measured", .enabled(
    if: ProcessInfo.processInfo.environment["EF_PROBE"] != nil,
    "a measuring instrument — set EF_PROBE=1 to run it"))
struct EraProbe {

    /// Every milestone of an era, with what the world currently has against
    /// what it needs — so a blocked era says *which* wall it is standing at.
    private func standing(
        _ era: Era, in state: WorldState, registry: GameDataRegistry
    ) -> [(name: String, have: String, need: String, met: Bool)] {
        guard let definition = registry.eraDefinition(era) else { return [] }
        return definition.milestones.map { milestone in
            let met = EraEngine.isSatisfied(milestone, in: state)
            switch milestone {
            case let .techResearched(id):
                return (id, state.researchedTechs.contains(id) ? "yes" : "no", "yes", met)
            case let .globalStat(stat, min):
                let have = WorldQuery.globalValue(stat, in: state)
                return (stat, String(format: "%.0f", have),
                        String(format: "%.0f", min), met)
            case let .settlementCount(min):
                return ("settlements", "\(state.settlements.count)", "\(min)", met)
            case let .populationTotal(min):
                return ("population", "\(state.totalPopulation)",
                        String(format: "%.0f", min), met)
            }
        }
    }

    @Test("How far a colony left alone gets, and what it is standing at")
    func theLadder() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        let ticksPerYear = max(1, registry.config.ticksPerYear)
        // Five hundred years. Long past any session anybody will play, so a
        // wall found here is a wall, not impatience.
        let years = 500
        let step = 300
        var reached: [Era: Int] = [.earlySettlement: 0]

        print("""

        ── eras ──────────────────────────────────────────────────────
        a tick is \(Int(registry.config.realSecondsPerTick))s · a year is \
        \(ticksPerYear) ticks · running \(years) years
        year   era                pop   prosp  techs  settlements
        """)

        for step in stride(from: step, through: years * ticksPerYear, by: step) {
            let before = state.era
            state = TickEngine.advance(state, ticks: 300, registry: registry).state
            if state.era != before, reached[state.era] == nil {
                reached[state.era] = state.tick / ticksPerYear
            }
            guard step % (ticksPerYear * 25) < 300 else { continue }
            print(String(
                format: "%5d   %-16s %5d   %5.0f  %5d  %5d",
                state.tick / ticksPerYear,
                (state.era.rawValue as NSString).utf8String!,
                state.totalPopulation,
                WorldQuery.globalValue("prosperity", in: state),
                state.researchedTechs.count,
                state.settlements.count))
        }

        print("\n── how far it got ───────────────────────────────────────────")
        for era in Era.allCases {
            if let year = reached[era] {
                print(String(format: "  %-18s reached in year %d",
                             (era.rawValue as NSString).utf8String!, year))
            } else {
                print(String(format: "  %-18s NEVER",
                             (era.rawValue as NSString).utf8String!))
            }
        }

        // The wall it is standing at, spelled out.
        if let next = state.era.next {
            print("\n── what stops it becoming \(next.rawValue) ──────────────────")
            for m in standing(next, in: state, registry: registry) {
                print(String(format: "  %-14s have %-6s need %-6s  %@",
                             (m.name as NSString).utf8String!,
                             (m.have as NSString).utf8String!,
                             (m.need as NSString).utf8String!,
                             m.met ? "met" : "← BLOCKED"))
            }
        } else {
            print("\n  the colony reached the last era.")
        }

        // …and every era above, so one run says how much of the ladder is
        // reachable rather than only the next rung.
        print("\n── every era it did not reach ───────────────────────────────")
        for era in Era.allCases where reached[era] == nil {
            let walls = standing(era, in: state, registry: registry)
                .filter { !$0.met }
                .map { "\($0.name) \($0.have)/\($0.need)" }
                .joined(separator: ", ")
            print("  \(era.rawValue): \(walls.isEmpty ? "milestones met — blocked below" : walls)")
        }

        print("""

        ── the content behind it ────────────────────────────────────
        events gated at or above the highest unreached era, techs left \
        unresearched, and buildings never unlocked are content the player \
        cannot see. Numbers below.
        """)
        let unreached = Set(Era.allCases.filter { reached[$0] == nil })
        let lockedEvents = registry.events.count { event in
            !event.era.isEmpty && event.era.allSatisfy { unreached.contains($0) }
        }
        let lockedTechs = registry.techs.values.count { !state.researchedTechs.contains($0.id) }
        let lockedBuildings = registry.buildings.values.count { unreached.contains($0.era) }
        print("  events unreachable:    \(lockedEvents) of \(registry.events.count)")
        print("  techs unresearched:    \(lockedTechs) of \(registry.techs.count)")
        print("  buildings never built: \(lockedBuildings) of \(registry.buildings.count)")
        print("──────────────────────────────────────────────────────────────\n")
    }
}
