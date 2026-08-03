import Foundation

/// What a party actually meets when it gets there.
///
/// A visit to a ruin used to be: walk out for a few ticks, roll once against
/// `hazardChance`, add some resources, walk home. The walk was real and the
/// *place* was a number — so an expedition felt instant however long it took,
/// because nothing happened in the middle of it. There was nothing to find, no
/// reason it might fail, and nobody it happened to.
///
/// A site is a handful of **things**, each in a place: something guarding it,
/// something waiting to be sprung, and something worth carrying home. The party
/// walks between them on the action clock, one step at a time, exactly as a
/// siege is fought — and comes back with what it managed to open rather than
/// with what the table said the place was worth.
public struct SiteEncounter: Codable, Sendable, Equatable {

    /// One thing at the place.
    public struct Thing: Codable, Sendable, Equatable, Identifiable {
        public enum Kind: String, Codable, Sendable {
            /// Something alive, and in the way.
            case guardian
            /// The place itself: a floor that gives, a shaft, bad air.
            case trap
            /// A chest, a hoard, a seam — the reason anyone came.
            case cache
        }

        /// Small and stable, so a site costs a few bytes on disk rather than a
        /// pile of UUIDs.
        public let id: Int
        public let kind: Kind
        /// Where it is, in local-map coordinates near the place itself.
        public var at: LocalPoint
        /// A guardian's remaining fight; a trap's bite; a cache's worth.
        public var strength: Double
        /// Killed, sprung, or emptied.
        public var done: Bool
        /// What a cache holds, by item id. Nothing for the other kinds.
        public let itemID: String?
        /// What to call it, in both languages.
        public let label: LocalizedText

        public init(id: Int, kind: Kind, at: LocalPoint, strength: Double,
                    done: Bool = false, itemID: String? = nil,
                    label: LocalizedText = LocalizedText("")) {
            self.id = id
            self.kind = kind
            self.at = at
            self.strength = strength
            self.done = done
            self.itemID = itemID
            self.label = label
        }
    }

    /// One thing that happened, in the order it happened.
    ///
    /// The party comes home with a *story*, not a number: who opened what, who
    /// went through a floor, what was living in there. Written as it happens so
    /// the canvas can show it while the party is still out.
    public struct Beat: Codable, Sendable, Equatable, Identifiable {
        public enum Kind: String, Codable, Sendable {
            case arrived, opened, sprung, fought, killed, driven, cleared, left
        }
        public let id: Int
        public let kind: Kind
        public let pawnID: UUID?
        public let pawnName: String?
        public let thingLabel: LocalizedText?
        public let amount: Double

        public init(id: Int, kind: Kind, pawnID: UUID? = nil, pawnName: String? = nil,
                    thingLabel: LocalizedText? = nil, amount: Double = 0) {
            self.id = id
            self.kind = kind
            self.pawnID = pawnID
            self.pawnName = pawnName
            self.thingLabel = thingLabel
            self.amount = amount
        }
    }

    public var things: [Thing]
    /// Where each member of the party is standing, right now.
    public var places: [UUID: LocalPoint]
    /// Who each member is working on, so the canvas can draw the pairing and
    /// the next step does not re-decide it from scratch.
    public var marks: [UUID: Int]
    public var beats: [Beat]
    /// What has actually been picked up, by item id.
    public var loot: [String: Int]
    /// The last absolute action step this site was carried to — the same
    /// once-only guarantee a siege has.
    public var advancedTo: Int
    public var seed: UInt64

    public init(things: [Thing] = [], places: [UUID: LocalPoint] = [:],
                marks: [UUID: Int] = [:], beats: [Beat] = [], loot: [String: Int] = [:],
                advancedTo: Int = 0, seed: UInt64 = 0) {
        self.things = things
        self.places = places
        self.marks = marks
        self.beats = beats
        self.loot = loot
        self.advancedTo = advancedTo
        self.seed = seed
    }

    // MARK: - Reading it

    /// Everything still to be dealt with.
    public var remaining: [Thing] { things.filter { !$0.done } }
    /// Whether there is anything left alive in here.
    public var isGuarded: Bool {
        things.contains { $0.kind == .guardian && !$0.done }
    }
    /// The place has given up everything it holds.
    public var isCleared: Bool { remaining.isEmpty }
    /// How much of it has been dealt with, 0…1 — what a progress ring reads.
    public var progress: Double {
        guard !things.isEmpty else { return 1 }
        return Double(things.count - remaining.count) / Double(things.count)
    }

    /// Everything a **cache** at this place still holds, so the outcome can say
    /// what was left behind as well as what came back.
    public var unopenedCaches: Int {
        things.count { $0.kind == .cache && !$0.done }
    }

    private enum CodingKeys: String, CodingKey {
        case things, places, marks, beats, loot, advancedTo, seed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        things = try c.decodeIfPresent([Thing].self, forKey: .things) ?? []
        places = try c.decodeIfPresent([UUID: LocalPoint].self, forKey: .places) ?? [:]
        marks = try c.decodeIfPresent([UUID: Int].self, forKey: .marks) ?? [:]
        beats = try c.decodeIfPresent([Beat].self, forKey: .beats) ?? []
        loot = try c.decodeIfPresent([String: Int].self, forKey: .loot) ?? [:]
        advancedTo = try c.decodeIfPresent(Int.self, forKey: .advancedTo) ?? 0
        seed = try c.decodeIfPresent(UInt64.self, forKey: .seed) ?? 0
    }
}
