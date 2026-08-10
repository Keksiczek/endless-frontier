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

    /// What this moment happened *to*, when the engine knows.
    ///
    /// The Core says **who or what**; it deliberately does not say *where*,
    /// because where a colonist is standing is presentation and belongs to
    /// `AgentMotion` (rule: the simulation never holds a screen position). That
    /// is enough for the canvas to point the camera at it — which is the whole
    /// reason this exists: a wildfire, a raid or a death was a line of text and
    /// a number, and finding the place it happened meant panning the valley
    /// looking for something that had already stopped moving.
    public enum Subject: Codable, Sendable, Equatable, Hashable {
        case pawn(UUID)
        /// A `ColonyMap.Placement` id — the lot, not the definition, so the
        /// camera lands on the barn that burned and not on barns in general.
        case building(UUID)
        /// Somewhere on the local map with nothing standing on it: where the
        /// warband is coming from, where the lightning struck.
        case place(LocalPoint)
    }

    /// Monotonic per-settlement sequence — stable identity for SwiftUI lists.
    public let id: Int
    public let tick: Int
    public let kind: Kind
    public let text: LocalizedText
    /// Who or what it happened to, if the engine knew. Optional on purpose:
    /// most of the colony's day is nobody in particular.
    public let subject: Subject?

    public init(id: Int, tick: Int, kind: Kind, text: LocalizedText,
                subject: Subject? = nil) {
        self.id = id
        self.tick = tick
        self.kind = kind
        self.text = text
        self.subject = subject
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
    ///
    /// `subject` defaults to nobody so the hundred existing call sites are
    /// unchanged; pass it wherever the engine already has the colonist or the
    /// lot in its hand, and the canvas can take the player there.
    public mutating func append(tick: Int, kind: ColonyLogEntry.Kind, text: LocalizedText,
                                subject: ColonyLogEntry.Subject? = nil) {
        entries.append(ColonyLogEntry(id: nextID, tick: tick, kind: kind, text: text,
                                      subject: subject))
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
