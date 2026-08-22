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
    case sanctuary      // a sacred valley — a pilgrimage blesses the colony
    case lostCity = "lost_city"   // a dead city — rich salvage among the bones
    /// **An outlaw camp.** A place on the map with people in it who belong to
    /// nobody: no standing, no diplomacy, nothing to negotiate. Raids come
    /// from here, and a colony can walk out and burn it out. See `OutlawCamp`.
    ///
    /// Placed at world creation on ordinary country far from anybody rather
    /// than rolled in `MapGenerator.rollKind`, because it is not a *find* —
    /// the map has exactly as many of these as the world was founded with,
    /// and adding it to the site budget would have quietly made every other
    /// site rarer.
    case outlawCamp = "outlaw_camp"
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
    /// Whether a special site (ruins/dungeon/anomaly) here has been exploited.
    public var siteCleared: Bool
    /// How many times the site has been worked. Optional so saves from before
    /// multi-visit sites decode (missing key → nil → zero visits). A lost city
    /// takes several salvage runs to strip bare.
    public var siteVisits: Int?
    /// What the land here actually is, when the ground makes something of
    /// itself — a pass, a crater lake, an oasis. Read off the elevation,
    /// moisture and warmth fields rather than rolled, so it can never disagree
    /// with the country around it. See `RegionFeature`.
    ///
    /// Optional in every sense: most hexes are ordinary country, and a map
    /// where everywhere is a landmark has no landmarks. Being `Optional` on a
    /// synthesised `Codable` is also what lets every save written before the
    /// land had features decode straight through (rule 3).
    public var feature: RegionFeature?
    /// The water, where there is any. Optional for the same two reasons
    /// `feature` is: most country has no river in it, and an `Optional` on a
    /// synthesised `Codable` lets every save written before the map had water
    /// decode straight through.
    public var river: RiverCourse?

    public init(
        id: UUID = UUID(),
        name: String,
        coord: HexCoord = .origin,
        kind: RegionKind = .wilderness,
        biomeID: String,
        hazardLevel: Int = 0,
        explorationState: ExplorationState = .unknown,
        resourceDeposits: Resources = Resources(),
        settlementIDs: [UUID] = [],
        siteCleared: Bool = false,
        siteVisits: Int? = nil,
        feature: RegionFeature? = nil,
        river: RiverCourse? = nil
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
        self.siteCleared = siteCleared
        self.siteVisits = siteVisits
        self.feature = feature
        self.river = river
    }

    /// `true` if this region has an interactable special site that's explored
    /// and not yet cleared.
    public var hasActiveSite: Bool {
        explorationState == .fullyExplored
            && !siteCleared
            && [.ruins, .dungeon, .anomaly, .sanctuary, .lostCity, .outlawCamp].contains(kind)
    }
}
