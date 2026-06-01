import Foundation

/// A deterministic, seedable pseudo-random generator (SplitMix64).
///
/// The simulation must be reproducible: given the same `WorldState.rngSeed`
/// and the same inputs, the world evolves identically. All randomness in the
/// engine flows through this type — never call `Int.random` / `Bool.random`
/// with the system generator inside engine code.
public struct SeededRNG: RandomNumberGenerator {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A `Double` in `[0, 1)`.
    public mutating func nextUnit() -> Double {
        // Use the top 53 bits for full double precision.
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// A deterministic `UUID` drawn from the generator — used to give
    /// runtime-generated entities (e.g. recruited colonists) stable ids so
    /// persisted state stays reproducible for a given seed.
    public mutating func nextUUID() -> UUID {
        let hi = next()
        let lo = next()
        return UUID(uuid: (
            UInt8(truncatingIfNeeded: hi >> 56), UInt8(truncatingIfNeeded: hi >> 48),
            UInt8(truncatingIfNeeded: hi >> 40), UInt8(truncatingIfNeeded: hi >> 32),
            UInt8(truncatingIfNeeded: hi >> 24), UInt8(truncatingIfNeeded: hi >> 16),
            UInt8(truncatingIfNeeded: hi >> 8), UInt8(truncatingIfNeeded: hi),
            UInt8(truncatingIfNeeded: lo >> 56), UInt8(truncatingIfNeeded: lo >> 48),
            UInt8(truncatingIfNeeded: lo >> 40), UInt8(truncatingIfNeeded: lo >> 32),
            UInt8(truncatingIfNeeded: lo >> 24), UInt8(truncatingIfNeeded: lo >> 16),
            UInt8(truncatingIfNeeded: lo >> 8), UInt8(truncatingIfNeeded: lo)
        ))
    }

    /// Weighted choice. Returns the index selected proportionally to
    /// `weights`, or `nil` if the list is empty or all weights are zero.
    public mutating func weightedIndex(_ weights: [Double]) -> Int? {
        let total = weights.reduce(0, +)
        guard total > 0 else { return nil }
        var roll = nextUnit() * total
        for (index, weight) in weights.enumerated() {
            roll -= weight
            if roll < 0 { return index }
        }
        return weights.indices.last
    }
}
