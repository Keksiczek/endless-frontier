import Foundation

/// A layout synergy: a building gains a bonus for each orthogonally-adjacent
/// neighbour of a given kind on the colony grid. Data-defined so designers can
/// tune which buildings reward being placed together. A rule grants *either* a
/// per-tick production bonus (`resource` + `bonus`) or a morale bonus
/// (`morale`).
public struct AdjacencyRule: Codable, Sendable, Equatable {
    public let neighbor: String       // building id that triggers the bonus
    public let resource: ResourceType?
    public let bonus: Double
    public let morale: Double

    public init(neighbor: String, resource: ResourceType? = nil, bonus: Double = 0, morale: Double = 0) {
        self.neighbor = neighbor
        self.resource = resource
        self.bonus = bonus
        self.morale = morale
    }

    private enum CodingKeys: String, CodingKey { case neighbor, resource, bonus, morale }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        neighbor = try c.decode(String.self, forKey: .neighbor)
        resource = try c.decodeIfPresent(ResourceType.self, forKey: .resource)
        bonus = try c.decodeIfPresent(Double.self, forKey: .bonus) ?? 0
        morale = try c.decodeIfPresent(Double.self, forKey: .morale) ?? 0
    }
}

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
    public let adjacency: [AdjacencyRule]
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
        adjacency: [AdjacencyRule] = [],
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
        self.adjacency = adjacency
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case id, era, name, cost, workers, production, consumption
        case moraleEffect = "morale_effect"
        case defense, housing, pollution, adjacency
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
        adjacency = try c.decodeIfPresent([AdjacencyRule].self, forKey: .adjacency) ?? []
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}
