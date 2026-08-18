import Foundation

/// The colour of one thing standing on the ground: a crop, a tree, a rock, a
/// landform.
///
/// The third bank, and the last of the obvious ones. `motions.json` took the
/// bodies out of `SettlementFigures`, `ground.json` took the earth out of
/// `SettlementGround`, and this takes everything standing on it out of the four
/// files that each held its own little palette — `SettlementCrops`,
/// `SettlementFlora`, `SettlementStone`, `SettlementLandforms`.
///
/// **One bank rather than four**, because underneath they were the same
/// question asked four times: what colour is this named thing, and which
/// routine draws it. Four JSON files holding three entries each would be four
/// places to look and four chances to drift.
///
/// The *shape* stays in Swift, for the third time and the same reason: a pine
/// is a drawing routine, an oak is a different one, and a data file describing
/// them in coordinates would be unreadable and unwritable. What is here is the
/// palette — which is where the seasons, the biomes and the eye actually live.
public struct SceneryDefinition: Codable, Sendable, Identifiable, Equatable {

    /// Matches the raw value of whatever enum names this thing — `CropSpecies`,
    /// `TreeSpecies`, `RockKind`, `LandformKind`.
    public let id: String
    public let name: LocalizedText

    public let red: Double
    public let green: Double
    public let blue: Double

    /// What it turns in autumn, if it turns at all.
    ///
    /// This is the whole of why an autumn wood reads as an autumn wood: the
    /// broadleaves turn *around* the evergreens rather than the canopy changing
    /// all at once. An entry with no autumn colour keeps its own through the
    /// year, which is what a spruce, a rock and a furrow all do.
    public let autumnRed: Double?
    public let autumnGreen: Double?
    public let autumnBlue: Double?

    public let description: LocalizedText

    public init(
        id: String,
        name: LocalizedText,
        red: Double,
        green: Double,
        blue: Double,
        autumnRed: Double? = nil,
        autumnGreen: Double? = nil,
        autumnBlue: Double? = nil,
        description: LocalizedText = ""
    ) {
        self.id = id
        self.name = name
        self.red = red
        self.green = green
        self.blue = blue
        self.autumnRed = autumnRed
        self.autumnGreen = autumnGreen
        self.autumnBlue = autumnBlue
        self.description = description
    }

    /// The colour to draw it in this season — its own, unless it turns.
    public func colour(in season: Season) -> (r: Double, g: Double, b: Double) {
        guard season == .autumn,
              let r = autumnRed, let g = autumnGreen, let b = autumnBlue else {
            return (red, green, blue)
        }
        return (r, g, b)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, red, green, blue, description
        case autumnRed = "autumn_red"
        case autumnGreen = "autumn_green"
        case autumnBlue = "autumn_blue"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(LocalizedText.self, forKey: .name)
        red = try c.decode(Double.self, forKey: .red)
        green = try c.decode(Double.self, forKey: .green)
        blue = try c.decode(Double.self, forKey: .blue)
        autumnRed = try c.decodeIfPresent(Double.self, forKey: .autumnRed)
        autumnGreen = try c.decodeIfPresent(Double.self, forKey: .autumnGreen)
        autumnBlue = try c.decodeIfPresent(Double.self, forKey: .autumnBlue)
        description = try c.decodeIfPresent(LocalizedText.self, forKey: .description) ?? ""
    }

    /// Something the bank has nothing to say about: a mid green, so a missing
    /// entry reads as a plant rather than as a hole.
    public static let plain = SceneryDefinition(
        id: "plain",
        name: LocalizedText(values: [.en: "Growth", .cs: "Porost"]),
        red: 0.34, green: 0.46, blue: 0.28
    )
}
