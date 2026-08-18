import Foundation

/// What one kind of ground looks like.
///
/// The same move `motions.json` made for bodies, made for the earth they stand
/// on. Twelve ground covers had their colours, their grain and how much of it
/// they take written as literals across four `switch`es in `SettlementGround`,
/// so a thirteenth country meant four new `case`s in the renderer — and the
/// renderer is the one place in this repository where adding content is
/// supposed to be adding JSON.
///
/// **The mark stays in Swift, the numbers come out.** A blade of grass, a
/// pebble, a wind ripple and a dried crack are drawing routines; they are not
/// numbers and pretending otherwise would produce a data file full of
/// coordinates nobody can read. So `texture` names one of the marks the
/// renderer already knows how to draw, exactly the way a building's `look`
/// names a glyph. New country comes from a new *combination* — this colour,
/// that grain, this much of it — which is where the variety actually lives.
///
/// The season is deliberately **not** here: it multiplies every cover the same
/// way (`SettlementGround.seasonal`), so putting a per-cover copy of it in the
/// data would be twelve chances to disagree about one rule.
public struct GroundDefinition: Codable, Sendable, Identifiable, Equatable {

    /// The `GroundCover` this describes, by its raw value.
    public let id: String
    public let name: LocalizedText

    /// The raw earth, before the season passes over it. 0…1 each.
    public let red: Double
    public let green: Double
    public let blue: Double

    /// Which grain the renderer scatters over it — `blades`, `pebbles`,
    /// `ripples`, `crack`, `glint`, `reed`, `frond`, `sprig`, `stipple`,
    /// `chips`, `driedCrack`. A name the renderer does not know draws no
    /// grain, which reads as smooth ground rather than as a mistake.
    public let texture: String

    /// How much of the grain shows. Growing ground takes more than bare
    /// ground: a fern bed is texture all the way down, clay is nearly smooth.
    public let textureAlpha: Double

    public let description: LocalizedText

    public init(
        id: String,
        name: LocalizedText,
        red: Double,
        green: Double,
        blue: Double,
        texture: String,
        textureAlpha: Double = 0.30,
        description: LocalizedText = ""
    ) {
        self.id = id
        self.name = name
        self.red = red
        self.green = green
        self.blue = blue
        self.texture = texture
        self.textureAlpha = textureAlpha
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, red, green, blue, texture, description
        case textureAlpha = "texture_alpha"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(LocalizedText.self, forKey: .name)
        red = try c.decode(Double.self, forKey: .red)
        green = try c.decode(Double.self, forKey: .green)
        blue = try c.decode(Double.self, forKey: .blue)
        texture = try c.decodeIfPresent(String.self, forKey: .texture) ?? "stipple"
        textureAlpha = try c.decodeIfPresent(Double.self, forKey: .textureAlpha) ?? 0.30
        description = try c.decodeIfPresent(LocalizedText.self, forKey: .description) ?? ""
    }

    /// Ground with nothing said about it: a plain mid earth. Never nil, for
    /// the same reason `MotionDefinition.standing` is — a missing entry has to
    /// read as ordinary dirt, not as a hole in the world.
    public static let plain = GroundDefinition(
        id: "plain",
        name: LocalizedText(values: [.en: "Bare earth", .cs: "Holá zem"]),
        red: 0.21, green: 0.21, blue: 0.18, texture: "pebbles"
    )
}
