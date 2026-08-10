import Testing
import Foundation
@testable import EndlessFrontierCore

/// How a colony *grows*, printed as a curve.
///
/// Off by default like `DangerProbe`, and for the same reason: it measures
/// rather than asserts. Run it while tuning the shape of a colony's life with
///
/// ```
/// EF_PROBE=1 swift test --package-path Core --filter GrowthProbe
/// ```
@Suite("Growth, measured", .enabled(
    if: ProcessInfo.processInfo.environment["EF_PROBE"] != nil,
    "a measuring instrument — set EF_PROBE=1 to run it"))
struct GrowthProbe {

    @Test("The shape of a colony's first two centuries")
    func theCurve() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        let founding = state.settlements[0].pawns.count

        print("""

        ── growth ────────────────────────────────────────────────────
        founded with  \(founding)   ·   a tick is \(Int(registry.config.realSecondsPerTick))s \
        ·   a year is \(registry.config.ticksPerYear) ticks \
        (\(String(format: "%.1f", Double(registry.config.ticksPerYear)
                  * registry.config.realSecondsPerTick / 3600))h real)
        year   pop  adult  pairs  wed  fert  preg  chance   food  came   deaths
        """)

        for step in 1...20 {
            state = TickEngine.advance(state, ticks: 600, registry: registry).state
            guard let s = state.settlements.first else { break }
            // The roofs are `theChain`'s column now, along with the headroom
            // they buy — this table is the couples behind the curve.
            let deaths = s.deathTallies.sorted { $0.key < $1.key }
                .map { "\($0.key.prefix(5)):\($0.value)" }.joined(separator: " ")
            let ticksPerYear = registry.config.ticksPerYear
            let adults = s.pawns.count { $0.isAdult(ticksPerYear: ticksPerYear) }
            let couples = s.relationships.count { $0.kind == .partner }
            // Pairs of unmarried adults close enough to be on their way.
            let courting = s.relationships.count {
                $0.kind == .friend && $0.strength >= SocialEngine.weddingMinStrength
            }
            // Couples where **both** are inside the fertile window — the thing
            // that actually decides whether a colony has a future.
            let fertilePairs = s.relationships.count { bond in
                guard bond.kind == .partner else { return false }
                return [bond.a, bond.b].allSatisfy { id in
                    guard let p = s.pawns.first(where: { $0.id == id }) else { return false }
                    let y = p.ageYears(ticksPerYear: ticksPerYear)
                    return y >= PopulationEngine.fertileMinYears
                        && y <= PopulationEngine.fertileMaxYears
                }
            }
            let pregnant = s.pawns.count { $0.pregnancyTicksRemaining > 0 }
            // The best chance any one couple actually has this tick, so a zero
            // says "the roll never fires" rather than "the roll never happens".
            var best = 0.0
            let cap = ResourceLoop.housingCapacity(s, registry: registry)
            let headroom = PopulationEngine.headroomFactor(
                population: s.population, capacity: cap)
            for bond in s.relationships where bond.kind == .partner {
                guard let p1 = s.pawns.first(where: { $0.id == bond.a }),
                      let p2 = s.pawns.first(where: { $0.id == bond.b }) else { continue }
                let able = [p1, p2].map {
                    PopulationEngine.fertilityAt(
                        years: Double($0.ageYears(ticksPerYear: ticksPerYear)),
                        genes: $0.genes)
                }
                let readiness = min(1, (bond.strength - PopulationEngine.readyStrength)
                                    / (PopulationEngine.settledStrength
                                       - PopulationEngine.readyStrength))
                guard readiness > 0, let least = able.min() else { continue }
                let mood = min(1.4, max(0.3, (p1.mood + p2.mood) / 140))
                best = max(best, 1 / (PopulationEngine.yearsToConceive * Double(ticksPerYear))
                           * readiness * least * (able[0] + able[1]) / 2 * mood * headroom)
            }
            // People the world sent, cumulative. A closed founding party is a
            // loop with no input from outside itself, and §11.10 measured what
            // that costs — so this column is the one that decides whether the
            // curve has a future at all.
            let came = s.journal.entries.count { $0.kind == .arrival }
            print(String(format: "%4d %5d %5d %6d %5d %5d %5d %8.5f %6d %5d   %@",
                         step * 10, s.pawns.count, adults, couples, courting,
                         fertilePairs, pregnant, best, Int(s.storage[.food]), came, deaths))
        }
        print("──────────────────────────────────────────────────────────────\n")
    }

    /// Where the food chain actually breaks, link by link.
    ///
    /// The curve above says a colony starved; it does not say *which* link
    /// failed, and the four candidates want opposite fixes. Ground under crop,
    /// hands to reap it, sacks on the shelf, and somebody to cook them are
    /// four different colonies in trouble, and a single `food` column cannot
    /// tell them apart.
    @Test("Where the food chain breaks")
    func theChain() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)

        print("""

        ── the food chain ─────────────────────────────────────────────
        year   pop  adult  farm  cook  plots want   shelf   food  hungry  beds  want  headroom  mats  built  site
        """)

        for step in 1...20 {
            state = TickEngine.advance(state, ticks: 600, registry: registry).state
            guard let s = state.settlements.first else { break }
            let ticksPerYear = registry.config.ticksPerYear
            let adults = s.pawns.count { $0.isAdult(ticksPerYear: ticksPerYear) }
            let census = { (work: WorkKind) in
                s.pawns.count { $0.assignedWork == work
                    && $0.isAdult(ticksPerYear: ticksPerYear) && !$0.isAway }
            }
            let plots = FarmEngine.plotsStanding(s)
            let shelf = CookingEngine.foodstuffs(registry)
                .reduce(0) { $0 + s.stockpile[$1, default: 0] }
            let hungry = s.pawns.count { $0.needs.hunger < ErrandEngine.hungryBelow }
            // What the roofs allow, and what that does to a couple's chances.
            // Rule 19: size comes from housing, so a colony pinned against its
            // beds has its birth rate multiplied by something near zero however
            // healthy every other column looks.
            let beds = ResourceLoop.housingCapacity(s, registry: registry)
            let headroom = PopulationEngine.headroomFactor(
                population: s.population, capacity: beds)
            // Why the beds are what they are. `beds < want` and nothing on the
            // stocks means the council wanted a roof and could not have one —
            // which is a different colony from one that has all it needs, and
            // the two look identical in the `beds` column alone.
            let built = s.buildings.reduce(0) { $0 + $1.count }
            print(String(format:
                "%4d %5d %5d %5d %5d %6d %4d %7d %6d %6d %6d %5d %9.3f %5d %6d %5d",
                         step * 10, s.pawns.count, adults,
                         census(.farming), census(.cooking),
                         plots, FarmEngine.plotsWanted(for: s.population),
                         shelf, Int(s.storage[.food]), hungry, Int(beds),
                         Int(StewardEngine.bedsWanted(for: s.population)), headroom,
                         Int(s.storage[.materials]), built, s.constructions.count))
        }
        print("──────────────────────────────────────────────────────────────\n")
    }
}
