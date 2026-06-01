import Foundation

/// How much of a region the player has uncovered.
public enum ExplorationState: String, Codable, Sendable {
    case unknown
    case partiallyExplored = "partially_explored"
    case fullyExplored = "fully_explored"
}

/// A group of tiles sharing a biome. Exploration and expansion (Phase 2)
/// operate at the region level. The model exists from Phase 0 so the world
/// can hold the starting region and persist exploration progress.
public struct Region: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var biomeID: String
    public var hazardLevel: Int
    public var explorationState: ExplorationState
    public var resourceDeposits: Resources
    public var settlementIDs: [UUID]

    public init(
        id: UUID = UUID(),
        name: String,
        biomeID: String,
        hazardLevel: Int = 0,
        explorationState: ExplorationState = .unknown,
        resourceDeposits: Resources = Resources(),
        settlementIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.biomeID = biomeID
        self.hazardLevel = hazardLevel
        self.explorationState = explorationState
        self.resourceDeposits = resourceDeposits
        self.settlementIDs = settlementIDs
    }
}
