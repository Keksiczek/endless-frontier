import Foundation

/// **What a kind of tree is**, as data rather than as a `switch`.
///
/// Keks: *"taky mě lákají zvířata, kytky, mapy, tvorové obecně — ale ať je vše
/// jedinečné."* `Tools/generate.py kinds` refused flora outright, and it was
/// right to: species were eight cases of an enum with five hand-written tables
/// hanging off them, so a ninth needed Swift in six files and a new drawing.
/// A file nothing reads is worse than no file — so this is the reader first,
/// and the eight shipped species are the same eight numbers they always were.
///
/// The **crown** is the part that makes a new species look like itself. The
/// canvas has drawn five silhouettes for a while — a conifer's stacked skirts,
/// a broadleaf's lobes, a juniper's low scrub, a poplar's column, a willow's
/// fall — and every one of them was reachable only by naming an enum case. A
/// generated species names a crown and has a real shape on the day it ships,
/// which is the whole difference between content and a list of words
/// (`ef-composition-not-shapes`).
///
/// Colour is deliberately **not** here. `scenery.json` already holds a seasonal
/// palette keyed by the same id and the renderer already reads it; a second
/// colour on this definition would be two numbers for one thing (rule 8).
public struct FloraDefinition: Codable, Sendable, Identifiable, Equatable {

    /// The silhouette this species is drawn with.
    ///
    /// A closed set on purpose: each one is a piece of drawing that exists, and
    /// a species asking for a crown nobody drew would be a tree that is not
    /// there. `ContentTests` holds the two lists together.
    public enum Crown: String, Codable, Sendable, CaseIterable {
        /// Stacked skirts narrowing to a point. Keeps its needles all winter.
        case conifer
        /// Overlapping lobes; bare branches once the leaves are off.
        case broadleaf
        /// Wider than it is tall, and evergreen. What grows where nothing
        /// grows *up*.
        case scrub
        /// Tall and narrow. A line of them reads as a line and not as a hedge.
        case column
        /// A crown that falls — wet ground, and the only shape that hangs.
        case weeping
    }

    public let id: String
    public let name: LocalizedText
    public let crown: Crown
    /// Timber a full-grown one yields when felled.
    public let timber: Double
    /// In-game ticks from sapling to full grown. An oak is a lifetime; a birch
    /// is a decade — so a felled oak wood is a real loss and a birch stand
    /// comes back.
    public let maturityTicks: Int
    /// How much cold it will take before it stops growing, in °C.
    public let hardiness: Double
    /// The biomes this grows in. A species named by no biome grows nowhere,
    /// which the content check treats as a fault rather than as a choice.
    public let biomes: [String]
    public let description: LocalizedText

    public init(
        id: String,
        name: LocalizedText,
        crown: Crown = .broadleaf,
        timber: Double = 20,
        maturityTicks: Int = 2000,
        hardiness: Double = -20,
        biomes: [String] = [],
        description: LocalizedText = LocalizedText("")
    ) {
        self.id = id
        self.name = name
        self.crown = crown
        self.timber = timber
        self.maturityTicks = max(1, maturityTicks)
        self.hardiness = hardiness
        self.biomes = biomes
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, crown, timber, maturityTicks, hardiness, biomes, description
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(LocalizedText.self, forKey: .name)
        crown = try c.decodeIfPresent(Crown.self, forKey: .crown) ?? .broadleaf
        timber = try c.decodeIfPresent(Double.self, forKey: .timber) ?? 20
        maturityTicks = max(1, try c.decodeIfPresent(Int.self, forKey: .maturityTicks) ?? 2000)
        hardiness = try c.decodeIfPresent(Double.self, forKey: .hardiness) ?? -20
        biomes = try c.decodeIfPresent([String].self, forKey: .biomes) ?? []
        description = try c.decodeIfPresent(LocalizedText.self, forKey: .description) ?? ""
    }
}
