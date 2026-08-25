import Foundation
import EndlessFrontierCore

/// The shipping content, for tests that build a registry of their own.
///
/// A room is furnished out of `fittings.json` for the century the town is
/// living in (`FittingDefinition`), so a registry with no fittings in it lays
/// out an **empty room** — no benches, no beds, no stations. Every app test
/// that made its own two-building registry therefore started asking about a
/// room with nothing in it the moment fittings became data, and a colonist
/// posted to a workshop with no bench falls back to a seeded spot on the floor,
/// which is not a seat and not stable between calls.
enum TestBook {
    static let fittings: [FittingDefinition] = {
        guard let bundled = try? GameDataRegistry.bundled() else { return [] }
        return Array(bundled.fittings.values)
    }()
}
