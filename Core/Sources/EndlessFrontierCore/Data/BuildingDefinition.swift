import Foundation

/// A data-defined building. Loaded from `buildings.json`. The resource loop
/// reads `production` and `consumption` each tick; `workers` gates how many
/// of a building a settlement's population can staff.
public struct BuildingDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let era: Era
    public let name: String
    public let cost: Resources
    public let workers: Int
    public let production: Resources
    public let consumption: Resources
    public let moraleEffect: Double
    public let defense: Double
    public let housing: Double
    public let pollution: Double
    public let description: String

    public init(
        id: String,
        era: Era,
        name: String,
        cost: Resources = Resources(),
        workers: Int = 0,
        production: Resources = Resources(),
        consumption: Resources = Resources(),
        moraleEffect: Double = 0,
        defense: Double = 0,
        housing: Double = 0,
        pollution: Double = 0,
        description: String = ""
    ) {
        self.id = id
        self.era = era
        self.name = name
        self.cost = cost
        self.workers = workers
        self.production = production
        self.consumption = consumption
        self.moraleEffect = moraleEffect
        self.defense = defense
        self.housing = housing
        self.pollution = pollution
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case id, era, name, cost, workers, production, consumption
        case moraleEffect = "morale_effect"
        case defense, housing, pollution
        case description
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        era = try c.decode(Era.self, forKey: .era)
        name = try c.decode(String.self, forKey: .name)
        cost = try c.decodeIfPresent(Resources.self, forKey: .cost) ?? Resources()
        workers = try c.decodeIfPresent(Int.self, forKey: .workers) ?? 0
        production = try c.decodeIfPresent(Resources.self, forKey: .production) ?? Resources()
        consumption = try c.decodeIfPresent(Resources.self, forKey: .consumption) ?? Resources()
        moraleEffect = try c.decodeIfPresent(Double.self, forKey: .moraleEffect) ?? 0
        defense = try c.decodeIfPresent(Double.self, forKey: .defense) ?? 0
        housing = try c.decodeIfPresent(Double.self, forKey: .housing) ?? 0
        pollution = try c.decodeIfPresent(Double.self, forKey: .pollution) ?? 0
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}
