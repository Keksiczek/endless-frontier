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
