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
    /// **Both languages.** These were plain `String`s written in English in
    /// `ObjectivesEngine`, and `ObjectivesPanel` printed them straight — so the
    /// one panel in the game whose entire job is *"what should I do next"* met
    /// a Czech player in English. It shipped that way for months because the
    /// bilingual guard walks `GameData`, and none of this is content: it is
    /// Swift string literals in an engine, which no test was looking at.
    public let title: LocalizedText
    public let detail: LocalizedText
    /// Completion in `0...1` when measurable, else `nil`.
    public let progress: Double?
    public let category: Category
    /// Lower sorts first.
    public let priority: Int

    public init(
        id: String,
        title: LocalizedText,
        detail: LocalizedText,
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
