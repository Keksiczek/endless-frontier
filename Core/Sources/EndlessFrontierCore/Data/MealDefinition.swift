import Foundation

/// Something a cook can make out of what is on the shelf.
///
/// A recipe (`RecipeDefinition`) turns materials into a **thing**; a meal turns
/// raw ingredients into **food** — the pool the colony actually eats out of.
/// They are separate types because they are separate questions: nobody wears a
/// stew, and a sword does not go off.
///
/// Meals are ranked by what they give back for the work they take, so a colony
/// with grain and nothing else eats gruel and a colony with meat and roots eats
/// properly out of the same amount of grain. That is the whole reason for more
/// than one crop.
public struct MealDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: LocalizedText
    /// Raw ingredient item id → units consumed per serving batch.
    public let ingredients: [String: Int]
    /// Food (meals in the larder) one batch puts in the store.
    public let food: Double
    /// Worker-ticks a cook spends on one batch.
    public let work: Double
    /// The building this needs, if any. A meal with none is cooked over the
    /// fire, which is what keeps a colony that has not built a cookhouse — or
    /// has just lost one — fed rather than dead.
    public let requiresBuilding: String?
    public let description: LocalizedText

    public init(
        id: String,
        name: LocalizedText,
        ingredients: [String: Int],
        food: Double,
        work: Double,
        requiresBuilding: String? = nil,
        description: LocalizedText = ""
    ) {
        self.id = id
        self.name = name
        self.ingredients = ingredients
        self.food = food
        self.work = work
        self.requiresBuilding = requiresBuilding
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, ingredients, food, work, description
        case requiresBuilding = "requires_building"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(LocalizedText.self, forKey: .name)
        ingredients = try c.decodeIfPresent([String: Int].self, forKey: .ingredients) ?? [:]
        food = try c.decodeIfPresent(Double.self, forKey: .food) ?? 0
        // A meal that states no work cost still costs something. Nothing the
        // colony eats may be free — that was the whole shape of the crafting
        // bug (§6.14): twenty-nine recipes with no stated cost, and therefore
        // no cost at all.
        work = try c.decodeIfPresent(Double.self, forKey: .work) ?? 1
        requiresBuilding = try c.decodeIfPresent(String.self, forKey: .requiresBuilding)
        description = try c.decodeIfPresent(LocalizedText.self, forKey: .description) ?? ""
    }

    /// Food per worker-tick. What a cook chooses by, once the shelf and the
    /// standing buildings have narrowed the field.
    public var yieldPerWork: Double {
        work > 0 ? food / work : 0
    }

    /// Total ingredient units one batch swallows. Used to break ties toward the
    /// meal that stretches the stores furthest.
    public var ingredientUnits: Int {
        ingredients.values.reduce(0, +)
    }

    /// The pot that exists whether or not the content does.
    ///
    /// See `GameDataRegistry.cookableMeals`: every optional data file is loaded
    /// with `try?`, so a single malformed entry empties the table. A colony
    /// that cannot cook cannot eat, and a data typo must not be a famine — so
    /// there is always gruel. Deliberately the worst meal in the game: it keeps
    /// a colony alive and never competes with authored content.
    public static let fallback = MealDefinition(
        id: "gruel",
        name: LocalizedText(values: [.en: "Gruel", .cs: "Kaše"]),
        ingredients: ["grain": 3],
        food: 6,
        work: 1,
        description: LocalizedText(values: [
            .en: "Grain boiled in water. Nobody asks for it twice.",
            .cs: "Obilí uvařené ve vodě. Nikdo si o ni neřekne dvakrát."])
    )
}
