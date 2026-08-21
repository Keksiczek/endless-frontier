import Foundation

/// Heritable dispositions on a 0…1 scale. Children inherit their parent's
/// genes with a small mutation, so selection pressure (who survives long
/// enough to raise children) visibly shifts a settlement's character over
/// generations — the "natural selection" the chronicle can report on.
public struct Genes: Codable, Sendable, Equatable {
    /// Work output and building speed.
    public var industry: Double
    /// Chance of conceiving a child.
    public var fertility: Double
    /// Social cohesion — happiness and council behaviour.
    public var sociability: Double
    /// Bravery — defense, exploration and disease resistance.
    public var courage: Double

    public init(
        industry: Double = 0.5,
        fertility: Double = 0.5,
        sociability: Double = 0.5,
        courage: Double = 0.5
    ) {
        self.industry = industry
        self.fertility = fertility
        self.sociability = sociability
        self.courage = courage
    }

    /// A founder's genes: mid-range with individual variation.
    public static func founder(using rng: inout SeededRNG) -> Genes {
        Genes(
            industry: 0.3 + rng.nextUnit() * 0.4,
            fertility: 0.3 + rng.nextUnit() * 0.4,
            sociability: 0.3 + rng.nextUnit() * 0.4,
            courage: 0.3 + rng.nextUnit() * 0.4
        )
    }

    /// Both lines, before the drift.
    ///
    /// A child used to be a mutated copy of whichever parent carried it, so the
    /// other one contributed nothing at all — two people had a baby and only one
    /// of them was in it. The midpoint is the plainest honest answer, and it
    /// makes the chronicle's gene drift a story about the colony rather than
    /// about a single bloodline.
    public func blended(with other: Genes) -> Genes {
        Genes(
            industry: (industry + other.industry) / 2,
            fertility: (fertility + other.fertility) / 2,
            sociability: (sociability + other.sociability) / 2,
            courage: (courage + other.courage) / 2
        )
    }

    /// How much one person differs from the people they come from.
    ///
    /// Wider than a child's drift from its parents, because a stranger off the
    /// road is not anybody's child — they are one draw out of a whole folk.
    public static let stockSpread = 0.13

    /// **One person out of a people.**
    ///
    /// Every newcomer used to be rolled fresh from `founder`, whose mean is
    /// exactly 0.5 — so a colony's gene pool was quietly reset toward the
    /// middle every time somebody walked up the road, and `GeneProbe` duly
    /// measured all four dispositions converging on 0.5 over two centuries no
    /// matter what selection did. Immigration was a stronger force than
    /// anything the world could select for, and it pulled in one direction
    /// only.
    ///
    /// A wanderer comes from **somewhere**, and that somewhere has a character
    /// of its own — `Tribe.genes` has existed since a seceding band first
    /// carried the average of those who left. Drawing from it closes the loop:
    /// the world's gene pool becomes a real system rather than a leak.
    public static func drawn(from stock: Genes, using rng: inout SeededRNG) -> Genes {
        stock.mutated(using: &rng, spread: stockSpread)
    }

    /// The average of a group — what a people's character is made of.
    public static func mean(of genes: [Genes]) -> Genes? {
        guard !genes.isEmpty else { return nil }
        let n = Double(genes.count)
        return Genes(
            industry: genes.reduce(0) { $0 + $1.industry } / n,
            fertility: genes.reduce(0) { $0 + $1.fertility } / n,
            sociability: genes.reduce(0) { $0 + $1.sociability } / n,
            courage: genes.reduce(0) { $0 + $1.courage } / n)
    }

    /// The genes a child inherits: each trait drifts by up to ±`spread`.
    public func mutated(using rng: inout SeededRNG, spread: Double = 0.09) -> Genes {
        func drift(_ value: Double) -> Double {
            min(1, max(0, value + (rng.nextUnit() * 2 - 1) * spread))
        }
        return Genes(
            industry: drift(industry),
            fertility: drift(fertility),
            sociability: drift(sociability),
            courage: drift(courage)
        )
    }
}
