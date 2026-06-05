import Foundation

/// A suggested goal surfaced to the player, derived from world state. The
/// objectives list keeps an open-ended game directed — there is always a clear
/// next thing to pursue.
public struct Objective: Sendable, Equatable, Identifiable {
    public enum Category: String, Sendable, Equatable {
        case colonists   // urgent welfare
        case era         // progress toward the next era
        case research
        case sites       // investigate ruins/dungeons/anomalies
        case explore
        case expand
    }

    public let id: String
    public let title: String
    public let detail: String
    /// Completion in `0...1` when measurable, else `nil`.
    public let progress: Double?
    public let category: Category
    /// Lower sorts first.
    public let priority: Int

    public init(
        id: String,
        title: String,
        detail: String,
        progress: Double? = nil,
        category: Category,
        priority: Int
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.progress = progress
        self.category = category
        self.priority = priority
    }
}
