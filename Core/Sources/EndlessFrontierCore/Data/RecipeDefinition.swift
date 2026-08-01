import Foundation

/// A crafting recipe: consume material items (and resources) to produce a piece
/// of gear or an artifact. Loaded from `recipes.json`.
public struct RecipeDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: LocalizedText
    public let outputItemID: String
    public let materials: [String: Int]   // material item id → count required
    public let resourceCost: Resources
    public let requiresBuilding: String?
    public let requiresTech: String?
    public let description: LocalizedText
    /// Worker-ticks one of these takes to make, if the content says so.
    ///
    /// Optional because crafting used to be instant and free of labour, so no
    /// recipe in `recipes.json` has ever carried a cost. Rather than make
    /// twenty-nine recipes wrong until they are all edited, an unstated cost
    /// is *derived* from what the thing is made of — see `workPerUnit`.
    public let workTicks: Double?

    public init(
        id: String,
        name: LocalizedText,
        outputItemID: String,
        materials: [String: Int] = [:],
        resourceCost: Resources = Resources(),
        requiresBuilding: String? = nil,
        requiresTech: String? = nil,
        description: LocalizedText = "",
        workTicks: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.outputItemID = outputItemID
        self.materials = materials
        self.resourceCost = resourceCost
        self.requiresBuilding = requiresBuilding
        self.requiresTech = requiresTech
        self.description = description
        self.workTicks = workTicks
    }

    /// How many worker-ticks one of these costs.
    ///
    /// Derived when the content does not say: a bench-hour per unit of stuff
    /// that goes in, a floor so nothing is free, and a surcharge for needing a
    /// building at all — the things that want a foundry are the things worth
    /// waiting for. Deliberately coarse; the point is that making a plate
    /// harness is an afternoon's work and a leather jerkin is not.
    public var workPerUnit: Double {
        if let workTicks { return max(1, workTicks) }
        let stuff = materials.values.reduce(0, +)
        let base = 6.0 + Double(stuff) * 4
        return requiresBuilding == nil ? base : base * 1.5
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, outputItemID, materials, resourceCost, requiresBuilding
        case requiresTech, description, workTicks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(LocalizedText.self, forKey: .name)
        outputItemID = try c.decode(String.self, forKey: .outputItemID)
        materials = try c.decodeIfPresent([String: Int].self, forKey: .materials) ?? [:]
        resourceCost = try c.decodeIfPresent(Resources.self, forKey: .resourceCost) ?? Resources()
        requiresBuilding = try c.decodeIfPresent(String.self, forKey: .requiresBuilding)
        requiresTech = try c.decodeIfPresent(String.self, forKey: .requiresTech)
        description = try c.decodeIfPresent(LocalizedText.self, forKey: .description) ?? ""
        workTicks = try c.decodeIfPresent(Double.self, forKey: .workTicks)
    }
}
