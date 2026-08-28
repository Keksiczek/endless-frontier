import Foundation

/// **How one building is put together**, so it can be told from the others.
///
/// Measured 2026-08-27: 62 buildings share 30 `look` values and 51 of them
/// share theirs with something else — five different works all draw as `plant`.
/// And yet `StructureVariant`'s axes separate all 62 with no collisions at all.
/// So the buildings looking alike was never a data problem and there is nothing
/// to disambiguate: the drawing simply does not spend the difference it is
/// already handed (rule 107). This is where the difference goes.
///
/// The same move `flora.json` and `ground.json` made, made for roofs: **the
/// parts stay in Swift, the composition comes out**. A charcoal heap and a
/// hitching rail are drawing routines and would be nonsense as coordinates in
/// a data file; which building has one is exactly the kind of thing that
/// belongs in JSON, and a new building is then a new *combination* rather than
/// a new routine (rule 92).
///
/// See `docs/RENDER_25D.md`. Nothing here reaches the simulation: `standing` is
/// a drawing number, cover keeps its own model in `Cover.Stature`, and a taller
/// drawing must never change a fight.
public struct StructureDefinition: Codable, Sendable, Identifiable, Equatable {

    /// The building id this describes — a key into `buildings.json`.
    public let id: String

    /// **How high the walls stand, in map units**, before the roof.
    ///
    /// The one thing a plan view could never say. A hut is about 0.9, a
    /// longhouse 1.1, a granary 1.8, a watchtower 3.4. In the same units
    /// `LocalPoint` is in, so a building one grid tile tall has the height of
    /// one grid tile and nothing has to be converted.
    public let standing: Double

    /// How the top is closed off: `gable`, `sawtooth`, `flat`, `barrel`,
    /// `stepped`. The set `StructureVariant.Roofline` already draws.
    public let roof: String

    /// What the wall face is made of — `open`, `thatch`, `daub`, `timber`,
    /// `stone`, `brick`, `panel`, `glass`, `sheet`. `open` is a roof on posts
    /// with no wall at all: a work lean-to, a market row.
    public let fabric: String

    /// What frames the face: the timber crucks across daub, the stone quoins at
    /// a brick corner.
    public let trim: String

    /// What stands on the roof — `none`, `vents`, `array`, `aerial`, `tank`.
    public let rooftop: String

    /// **What stands beside it and says what it is.**
    ///
    /// The field that does the work. A charcoal heap, drying racks, an anvil
    /// under an awning, crates on a loading step — this is where the five
    /// `plant` buildings stop being one building drawn five times. A name the
    /// renderer does not know draws nothing, which reads as a plainer building
    /// rather than as a mistake.
    public let attachments: [String]

    /// What the ground does around it: `none`, `beaten_earth`, `gravel`,
    /// `cobbles`, `planking`.
    public let yard: String

    /// The one thing allowed to be warm in a bone-on-slate world — a forge has
    /// an ember, a lab a cold green, a market an awning. At most one, or the
    /// town becomes a fairground.
    public let accent: String

    public init(id: String, standing: Double, roof: String = "gable",
                fabric: String = "timber", trim: String = "none",
                rooftop: String = "none", attachments: [String] = [],
                yard: String = "beaten_earth", accent: String = "none") {
        self.id = id
        self.standing = standing
        self.roof = roof
        self.fabric = fabric
        self.trim = trim
        self.rooftop = rooftop
        self.attachments = attachments
        self.yard = yard
        self.accent = accent
    }

    /// Written by hand for the ordinary reason (rule 37): a synthesised decoder
    /// does not fall back to a property's default, so a composition written
    /// before a field existed would refuse to load rather than doing without it.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        standing = try c.decodeIfPresent(Double.self, forKey: .standing) ?? 1.0
        roof = try c.decodeIfPresent(String.self, forKey: .roof) ?? "gable"
        fabric = try c.decodeIfPresent(String.self, forKey: .fabric) ?? "timber"
        trim = try c.decodeIfPresent(String.self, forKey: .trim) ?? "none"
        rooftop = try c.decodeIfPresent(String.self, forKey: .rooftop) ?? "none"
        attachments = try c.decodeIfPresent([String].self, forKey: .attachments) ?? []
        yard = try c.decodeIfPresent(String.self, forKey: .yard) ?? "beaten_earth"
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? "none"
    }

    private enum CodingKeys: String, CodingKey {
        case id, standing, roof, fabric, trim, rooftop, attachments, yard, accent
    }

    /// What a building the bank has never heard of is drawn as: an ordinary
    /// one-storey shed. A composition missing is a plainer building, never an
    /// absent one.
    public static let plain = StructureDefinition(id: "", standing: 1.0)
}
