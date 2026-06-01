import Foundation

/// Local health indicators for a settlement, all on a 0–100 scale.
public struct SettlementStats: Codable, Sendable, Equatable {
    public var stability: Double
    public var morale: Double
    public var growth: Double
    public var defense: Double
    public var pollution: Double

    public init(
        stability: Double = 60,
        morale: Double = 60,
        growth: Double = 50,
        defense: Double = 30,
        pollution: Double = 0
    ) {
        self.stability = stability
        self.morale = morale
        self.growth = growth
        self.defense = defense
        self.pollution = pollution
    }

    /// Clamps every stat into `[0, 100]`, returning a new value.
    public func clamped() -> SettlementStats {
        func c(_ v: Double) -> Double { min(max(v, 0), 100) }
        return SettlementStats(
            stability: c(stability),
            morale: c(morale),
            growth: c(growth),
            defense: c(defense),
            pollution: c(pollution)
        )
    }

    /// Mutating-by-name access used when applying data-driven stat effects
    /// like `settlement:all.morale`.
    public func applying(delta: Double, to stat: String) -> SettlementStats {
        var copy = self
        switch stat {
        case "stability": copy.stability += delta
        case "morale": copy.morale += delta
        case "growth": copy.growth += delta
        case "defense": copy.defense += delta
        case "pollution": copy.pollution += delta
        default: break
        }
        return copy.clamped()
    }
}

/// A placed building, referencing a `BuildingDefinition` by its stable id.
public struct BuildingInstance: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let definitionID: String
    public var count: Int

    public init(id: UUID = UUID(), definitionID: String, count: Int = 1) {
        self.id = id
        self.definitionID = definitionID
        self.count = count
    }
}

/// The role of a settlement. Outposts are small and can be upgraded to cities
/// once they meet population and stability thresholds. The capital is the
/// origin settlement and is always considered connected.
public enum SettlementKind: String, Codable, Sendable, Equatable {
    case capital
    case city
    case outpost
}

/// An independent economic and political unit (settlement, outpost or city).
public struct Settlement: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var kind: SettlementKind
    public var regionID: UUID?
    public var foundedTick: Int
    public var population: Double
    public var buildings: [BuildingInstance]
    public var storage: Resources
    public var storageCapacity: Double
    public var stats: SettlementStats

    public init(
        id: UUID = UUID(),
        name: String,
        kind: SettlementKind = .city,
        regionID: UUID? = nil,
        foundedTick: Int = 0,
        population: Double = 50,
        buildings: [BuildingInstance] = [],
        storage: Resources = Resources(),
        storageCapacity: Double = 500,
        stats: SettlementStats = SettlementStats()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.regionID = regionID
        self.foundedTick = foundedTick
        self.population = population
        self.buildings = buildings
        self.storage = storage
        self.storageCapacity = storageCapacity
        self.stats = stats
    }
}
