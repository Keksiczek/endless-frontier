import Foundation

/// A crafting recipe: consume material items (and resources) to produce a piece
/// of gear or an artifact. Loaded from `recipes.json`.
public struct RecipeDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let outputItemID: String
    public let materials: [String: Int]   // material item id → count required
    public let resourceCost: Resources
    public let requiresBuilding: String?
    public let requiresTech: String?
    public let description: String

    public init(
        id: String,
        name: String,
        outputItemID: String,
        materials: [String: Int] = [:],
        resourceCost: Resources = Resources(),
        requiresBuilding: String? = nil,
        requiresTech: String? = nil,
        description: String = ""
    ) {
        self.id = id
        self.name = name
        self.outputItemID = outputItemID
        self.materials = materials
        self.resourceCost = resourceCost
        self.requiresBuilding = requiresBuilding
        self.requiresTech = requiresTech
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, outputItemID, materials, resourceCost, requiresBuilding, requiresTech, description
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        outputItemID = try c.decode(String.self, forKey: .outputItemID)
        materials = try c.decodeIfPresent([String: Int].self, forKey: .materials) ?? [:]
        resourceCost = try c.decodeIfPresent(Resources.self, forKey: .resourceCost) ?? Resources()
        requiresBuilding = try c.decodeIfPresent(String.self, forKey: .requiresBuilding)
        requiresTech = try c.decodeIfPresent(String.self, forKey: .requiresTech)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}
