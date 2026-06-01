import Foundation

/// How much of a region the player has uncovered.
public enum ExplorationState: String, Codable, Sendable {
    case unknown
    case partiallyExplored = "partially_explored"
    case fullyExplored = "fully_explored"
}

/// The archetype of a map region. Extensible — future content (more biome
/// flavours, settlement sites, dungeons, anomalies) adds cases here without
/// touching the engine.
public enum RegionKind: String, Codable, Sendable, CaseIterable {
    case homeland       // the starting region
    case wilderness     // an ordinary biome region to settle
    case ruins          // ancient site — bonus loot / lore events
    case dungeon        // dangerous site — high risk, high reward (future depth)
    case anomaly        // strange, shifting region (dynamic events)
}

/// Selects which region a dynamic region-changing event applies to.
/// Deterministic (no randomness) to preserve seed reproducibility.
public enum RegionSelector: String, Codable, Sendable, Equatable {
    case anyExplored = "any_explored"   // first explored, non-homeland region
    case anyUnknown = "any_unknown"     // first still-unknown region
    case highestHazard = "highest_hazard"
    case lowestHazard = "lowest_hazard"
}

/// A hex on the world map. Exploration and expansion operate at the region
/// level. Regions carry a hex `coord`, a `kind` archetype, a biome, and can be
/// mutated over time by dynamic storyteller events.
public struct Region: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var coord: HexCoord
    public var kind: RegionKind
    public var biomeID: String
    public var hazardLevel: Int
    public var explorationState: ExplorationState
    public var resourceDeposits: Resources
    public var settlementIDs: [UUID]

    public init(
        id: UUID = UUID(),
        name: String,
        coord: HexCoord = .origin,
        kind: RegionKind = .wilderness,
        biomeID: String,
        hazardLevel: Int = 0,
        explorationState: ExplorationState = .unknown,
        resourceDeposits: Resources = Resources(),
        settlementIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.coord = coord
        self.kind = kind
        self.biomeID = biomeID
        self.hazardLevel = hazardLevel
        self.explorationState = explorationState
        self.resourceDeposits = resourceDeposits
        self.settlementIDs = settlementIDs
    }
}
