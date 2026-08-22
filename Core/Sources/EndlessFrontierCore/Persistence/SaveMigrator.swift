import Foundation

/// Upgrades a decoded `WorldState` from an older `schemaVersion` to the current
/// one by applying ordered migration steps.
///
/// The resilient `WorldState` decoder already tolerates *added* fields (missing
/// keys fall back to defaults). This migrator is for the harder case the
/// decoder can't handle: when a field's *meaning* changes (a rename, a unit
/// change, a re-scoped value). Register a step keyed by the version it upgrades
/// *from*; `migrate` runs the chain and stamps the new version.
public enum SaveMigrator {
    /// A migration transforms a state at version `key` into version `key + 1`.
    public typealias Step = @Sendable (WorldState) -> WorldState

    /// Registered migrations, keyed by the version they upgrade *from*.
    public static let steps: [Int: Step] = [
        // **2 → 3: put the water on the map.**
        //
        // `Region.river` is derived from the same elevation and moisture fields
        // the biomes come from, and it is written where every other derived
        // field is written: at generation, in `MapGenerator.region(at:...)`. So
        // a world that already existed had `nil` on every hex and would have
        // had it for ever — no rivers, no bridges, and no way to tell "this
        // country is dry" from "this save predates water".
        //
        // Safe to recompute rather than to guess, because the course is a pure
        // function of `(mapSeed, coord)`: filling it in gives exactly the map
        // the generator would have drawn for this seed, which is the same map a
        // newly explored hex on the frontier will get.
        2: { state in
            var s = state
            for index in s.regions.indices {
                s.regions[index].river = MapGenerator.river(
                    at: s.regions[index].coord, mapSeed: s.mapSeed)
            }
            return s
        }
    ]

    /// Brings `state` up to `target`, applying each registered step in order.
    /// A save already at (or ahead of) the target is returned untouched, so a
    /// newer save opened by an older build is left forward-compatibly intact.
    public static func migrate(
        _ state: WorldState,
        to target: Int = WorldState.currentSchemaVersion,
        steps: [Int: Step] = SaveMigrator.steps
    ) -> WorldState {
        guard state.schemaVersion < target else { return state }
        var s = state
        var version = s.schemaVersion
        while version < target {
            if let step = steps[version] { s = step(s) }
            version += 1
            s.schemaVersion = version
        }
        return s
    }
}
