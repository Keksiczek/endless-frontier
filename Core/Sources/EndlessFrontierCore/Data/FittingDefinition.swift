import Foundation

/// **A thing that stands in a room**, as data rather than as a `switch`.
///
/// The third time this move has been made — `FloraDefinition` for trees,
/// `AnimalDefinition` for beasts, and now the furniture. Keks has asked twice:
/// *"budovy mají nudné interiéry, pořád stejné … vesnice má hodně technologií
/// a je moderní až v budoucnosti, canvas vypadá stejně."* He is describing one
/// fault exactly: which fittings a building gets was a `switch` over the
/// twenty-odd building shapes, with no notion of **when**, so a medieval
/// workshop and a near-future assembly plant were furnished from the same two
/// lines and shared their crates.
///
/// **`shape` is the drawable declaration.** `SettlementInterior.Fitting` is the
/// twenty-one pieces of drawing that exist — a bed, a hearth, an anvil, a
/// console — and an entry names one. A generated fitting is a real object in a
/// real room on the day it ships, and there is no fallback that quietly draws a
/// crate.
///
/// What makes two entries sharing a shape look unlike each other is `tint` and
/// `scale`: a plank cot and a sprung bed are both `bed`, and one is small and
/// wooden while the other is larger and cloth. That is deliberately a *small*
/// amount of variation — the alternative is twenty-one more drawings, and the
/// thing the room actually needs is that its furniture belongs to its age.
public struct FittingDefinition: Codable, Sendable, Identifiable, Equatable {

    /// Whether somebody stands and works at this, or it is simply *in* the room.
    ///
    /// A station gets a place in the ring the workers are seated round
    /// (`SettlementInterior.slots`); clutter is scattered against the walls. It
    /// is the difference between an anvil and a stack of crates.
    public enum Role: String, Codable, Sendable, CaseIterable {
        case station
        case clutter
    }

    /// What the piece is made of, which is all the colour it gets. Read against
    /// the room's own palette, so a wooden bench in a smithy and a wooden bench
    /// in a hut are the same wood as the walls around them.
    public enum Tint: String, Codable, Sendable, CaseIterable {
        case wood
        case cloth
        case metal
        case stone
        /// Something lit — a fire, a screen, a furnace mouth.
        case glow
    }

    public let id: String
    public let name: LocalizedText
    /// Which of the drawings this is. A closed set: `SettlementInterior.Fitting`.
    public let shape: String
    public let role: Role
    public let tint: Tint
    /// How big it is drawn against the ordinary piece of its shape, 0.5…1.8.
    public let scale: Double
    /// The building shapes it belongs in — `SettlementRenderer.BuildingGlyph`
    /// names. A fitting in no room stands nowhere, which the content check
    /// treats as a fault.
    public let rooms: [String]
    /// The ages it belongs to, by `Era` id. **This is the whole point.** A
    /// fitting with no era named is timeless — a bed is a bed — and one that
    /// names them is how a workshop stops looking like a workshop from four
    /// ages ago. Empty means every age.
    public let eras: [String]
    public let description: LocalizedText

    public init(
        id: String,
        name: LocalizedText,
        shape: String,
        role: Role = .clutter,
        tint: Tint = .wood,
        scale: Double = 1,
        rooms: [String] = [],
        eras: [String] = [],
        description: LocalizedText = LocalizedText("")
    ) {
        self.id = id
        self.name = name
        self.shape = shape
        self.role = role
        self.tint = tint
        self.scale = min(1.8, max(0.5, scale))
        self.rooms = rooms
        self.eras = eras
        self.description = description
    }

    /// Whether this belongs in a given room in a given age.
    public func belongs(inRoom room: String, era: Era) -> Bool {
        guard rooms.contains(room) else { return false }
        return eras.isEmpty || eras.contains(era.rawValue)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, shape, role, tint, scale, rooms, eras, description
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(LocalizedText.self, forKey: .name)
        shape = try c.decode(String.self, forKey: .shape)
        role = try c.decodeIfPresent(Role.self, forKey: .role) ?? .clutter
        tint = try c.decodeIfPresent(Tint.self, forKey: .tint) ?? .wood
        scale = min(1.8, max(0.5, try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1))
        rooms = try c.decodeIfPresent([String].self, forKey: .rooms) ?? []
        eras = try c.decodeIfPresent([String].self, forKey: .eras) ?? []
        description = try c.decodeIfPresent(LocalizedText.self, forKey: .description) ?? ""
    }
}
