import Foundation

/// One small moment in a settlement's day — a birth, a finished roof, two
/// colonists talking by the well. The journal is what makes the colony feel
/// *inhabited*: the simulation was always doing these things, but silently.
public struct ColonyLogEntry: Codable, Sendable, Equatable, Identifiable {
    /// What kind of moment this is — the UI picks an icon and tint by it.
    public enum Kind: String, Codable, Sendable {
        case social        // chats, quarrels, new friendships, weddings
        case work          // notable labour moments
        case construction  // sites opened and roofs raised
        case birth
        case death
        case arrival       // migrants, defectors in
        case departure     // secessions, defectors out
        case discovery     // POIs, first contact
        case danger        // raids, beasts, disasters
        case faith
    }

    /// Monotonic per-settlement sequence — stable identity for SwiftUI lists.
    public let id: Int
    public let tick: Int
    public let kind: Kind
    public let text: LocalizedText

    public init(id: Int, tick: Int, kind: Kind, text: LocalizedText) {
        self.id = id
        self.tick = tick
        self.kind = kind
        self.text = text
    }
}

/// A capped, append-only ring of the settlement's recent moments. Engines
/// append as life happens; the UI reads it as the colony's living diary and
/// surfaces fresh entries as toasts.
public struct ColonyLog: Codable, Sendable, Equatable {
    /// How much history is kept. Enough for several in-game years of moments
    /// without growing the save unboundedly.
    public static let capacity = 140

    public private(set) var entries: [ColonyLogEntry]
    /// The id the next appended entry receives. Monotonic even as old entries
    /// fall off the front, so ids never repeat within a settlement.
    public private(set) var nextID: Int

    public init(entries: [ColonyLogEntry] = [], nextID: Int = 0) {
        self.entries = entries
        self.nextID = max(nextID, (entries.map(\.id).max() ?? -1) + 1)
    }

    /// Appends a moment, trimming the oldest past `capacity`.
    public mutating func append(tick: Int, kind: ColonyLogEntry.Kind, text: LocalizedText) {
        entries.append(ColonyLogEntry(id: nextID, tick: tick, kind: kind, text: text))
        nextID += 1
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }

    /// Entries newer than a given id (exclusive) — what a live session shows
    /// as toasts after a tick lands.
    public func entries(after id: Int) -> [ColonyLogEntry] {
        entries.filter { $0.id > id }
    }
}
