import Foundation

/// A building being raised — construction takes hands and time now, instead of
/// a structure blinking into existence the moment it is paid for.
///
/// The cost is paid when the project is queued (materials go to the site);
/// colonists assigned to `.building` work push `progress` toward `required`
/// each tick, and the building only joins the settlement's economy ledger when
/// the roof goes on.
public struct ConstructionProject: Codable, Sendable, Equatable, Identifiable {
    /// Monotonic per-settlement sequence (see `Settlement.constructionSequence`)
    /// — deterministic, unlike a random UUID.
    public let id: Int
    public let definitionID: String
    /// Where it stands on the colony grid, when placed there; `nil` for a
    /// quick-build from the construction panel.
    public let placementID: UUID?
    public let startedTick: Int
    /// Work points accumulated so far.
    public var progress: Double
    /// Work points needed to finish.
    public let required: Double

    public init(
        id: Int,
        definitionID: String,
        placementID: UUID? = nil,
        startedTick: Int,
        progress: Double = 0,
        required: Double
    ) {
        self.id = id
        self.definitionID = definitionID
        self.placementID = placementID
        self.startedTick = startedTick
        self.progress = progress
        self.required = required
    }

    /// Completion fraction, 0…1.
    public var fraction: Double {
        required > 0 ? min(1, progress / required) : 1
    }
}
