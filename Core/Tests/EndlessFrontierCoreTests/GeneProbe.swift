import Testing
import Foundation
@testable import EndlessFrontierCore

/// Whether the people **change**, printed as two centuries of drift.
///
/// Off by default like the other probes, and for the same reason: it measures
/// rather than asserts.
///
/// ```
/// EF_PROBE=1 swift test --package-path Core --filter GeneProbe
/// ```
///
/// The chronicle carries "natural selection" as one of its generated insights,
/// and the insight has nothing to say while the colony's mean sits at 0.5
/// forever. The arithmetic says why before any run: `Genes.blended` is the
/// midpoint of both parents, which halves the variance every generation, and
/// `Genes.mutated` is mean-zero, which adds spread and no direction. A mean
/// only moves if a gene decides **who survives and who has children**.
///
/// So the columns are aimed at exactly that, and not at the mean alone:
///
///   `mean`   the colony's average, the number the chronicle reports
///   `sd`     how much people differ from each other — the raw material
///            selection has to work with. Below ~0.05 there is nothing to select
///   `kid−ad` the mean of everyone under ten, less the mean of the adults.
///            **This is the selection differential.** A gene that decides who
///            has children shows up here as a persistent sign, generation after
///            generation; a neutral gene wanders around zero
@Suite("Genes, measured", .enabled(
    if: ProcessInfo.processInfo.environment["EF_PROBE"] != nil,
    "a measuring instrument — set EF_PROBE=1 to run it"))
struct GeneProbe {

    /// Mean and standard deviation of one gene over a group.
    static func stat(_ pawns: [Pawn], _ pick: KeyPath<Genes, Double>) -> (mean: Double, sd: Double) {
        guard !pawns.isEmpty else { return (0, 0) }
        let values = pawns.map { $0.genes[keyPath: pick] }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return (mean, variance.squareRoot())
    }

    static var traits: [(String, KeyPath<Genes, Double>)] { [
        ("industry", \.industry),
        ("fertility", \.fertility),
        ("sociability", \.sociability),
        ("courage", \.courage)
    ] }

    @Test("The drift of a people over two centuries")
    func theDrift() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        let ticksPerYear = registry.config.ticksPerYear
        let founders = state.settlements[0].pawns

        print("""

        ── genes ──────────────────────────────────────────────────────
        founded with \(founders.count); their means \
        \(GeneProbe.traits.map { String(format: "%@ %.3f", $0.0,
                                        GeneProbe.stat(founders, $0.1).mean) }
            .joined(separator: "  "))

        year   pop  gen |  industry            |  fertility           \
        |  sociability         |  courage
                            mean    sd   kid−ad    mean    sd   kid−ad \
           mean    sd   kid−ad    mean    sd   kid−ad
        """)

        for step in 1...20 {
            state = TickEngine.advance(state, ticks: 600, registry: registry).state
            guard let s = state.settlements.first else { break }
            let kids = s.pawns.filter { $0.ageYears(ticksPerYear: ticksPerYear) < 10 }
            let adults = s.pawns.filter { $0.isAdult(ticksPerYear: ticksPerYear) }
            // Generations elapsed, at roughly a quarter-century each — the unit
            // selection actually works in.
            let generations = Double(step * 10) / 25

            var row = String(format: "%4d %5d %4.1f |", step * 10, s.pawns.count, generations)
            for (_, pick) in GeneProbe.traits {
                let all = GeneProbe.stat(s.pawns, pick)
                let kid = GeneProbe.stat(kids, pick).mean
                let adult = GeneProbe.stat(adults, pick).mean
                let differential = kids.isEmpty || adults.isEmpty ? 0 : kid - adult
                row += String(format: " %6.3f %5.3f %+7.4f |", all.mean, all.sd, differential)
            }
            print(row)
        }
        print("──────────────────────────────────────────────────────────────\n")
    }

    /// What a colonist dies of, and **how old they are when it happens**.
    ///
    /// The whole question of whether a gene can be selected for is the question
    /// of whether it acts before the fertile window closes. `lifespanYears`
    /// grants courage ten years and industry eight — on top of a base of sixty,
    /// against a window that shuts between forty and fifty-two. If almost every
    /// death is old age, then those two genes are invisible to selection by
    /// construction, however large their coefficients look.
    @Test("What kills a colonist, and at what age")
    func theEnd() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)

        print("""

        ── how lives end ──────────────────────────────────────────────
        year   pop   born  came  died  |  causes (cumulative)
        """)

        for step in 1...20 {
            state = TickEngine.advance(state, ticks: 600, registry: registry).state
            guard let s = state.settlements.first else { break }
            let died = s.deathTallies.values.reduce(0, +)
            // Off the tallies, not off the journal: `ColonyLog` is a
            // hundred-and-forty-entry ring, so counting `.birth` entries in it
            // undercounts the moment the colony outlives its own diary — and
            // **`came` is the column that decides whether immigration can be
            // moving the gene pool at all**. It read zero from the journal in
            // every run, which is exactly what "nobody came" looks like.
            let causes = s.deathTallies.sorted { $0.value > $1.value }
                .map { "\($0.key):\($0.value)" }.joined(separator: " ")
            print(String(format: "%4d %5d %6d %5d %5d  |  %@",
                         step * 10, s.pawns.count, s.birthTally, s.arrivalTally,
                         died, causes))
        }

        // The fertile window against the lifespan, for the record — the two
        // numbers whose ordering decides whether a lifespan gene is selectable
        // at all.
        let dullest = Genes(industry: 0, fertility: 0, sociability: 0, courage: 0)
        let keenest = Genes(industry: 1, fertility: 1, sociability: 1, courage: 1)
        print("""

        lifespan  \(String(format: "%.0f", PopulationEngine.lifespanYears(dullest)))\
        …\(String(format: "%.0f", PopulationEngine.lifespanYears(keenest))) years
        fertile until  \(String(format: "%.0f", PopulationEngine.lastFertileYear(dullest)))\
        …\(String(format: "%.0f", PopulationEngine.lastFertileYear(keenest))) years
        ──────────────────────────────────────────────────────────────

        """)
    }
}
