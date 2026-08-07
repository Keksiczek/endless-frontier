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
        year   pop  adult  pairs  wed  fert  preg  chance   food   deaths
        """)

        for step in 1...20 {
            state = TickEngine.advance(state, ticks: 600, registry: registry).state
            guard let s = state.settlements.first else { break }
            let beds = ResourceLoop.housingCapacity(s, registry: registry)
            let homes = s.colony?.placements.filter {
                !$0.underConstruction
                    && (registry.building($0.definitionID)?.housing ?? 0) > 0
            }.count ?? 0
            let deaths = s.deathTallies.sorted { $0.key < $1.key }
                .map { "\($0.key.prefix(5)):\($0.value)" }.joined(separator: " ")
            let ticksPerYear = registry.config.ticksPerYear
            let adults = s.pawns.count { $0.isAdult(ticksPerYear: ticksPerYear) }
            let couples = s.relationships.count { $0.kind == .partner }
            // Pairs of unmarried adults close enough to be on their way.
            let courting = s.relationships.count {
                $0.kind == .friend && $0.strength >= SocialEngine.weddingMinStrength
            }
            _ = homes; _ = beds
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
            print(String(format: "%4d %5d %5d %6d %5d %5d %5d %8.5f %6d   %@",
                         step * 10, s.pawns.count, adults, couples, courting,
                         fertilePairs, pregnant, best, Int(s.storage[.food]), deaths))
        }
        print("──────────────────────────────────────────────────────────────\n")
    }
}
