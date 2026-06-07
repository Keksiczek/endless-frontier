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

    /// Registered migrations. Empty at schema v1 — add an entry keyed by the
    /// old version the first time a field's meaning changes (and bump
    /// `WorldState.currentSchemaVersion`).
    public static let steps: [Int: Step] = [:]

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
