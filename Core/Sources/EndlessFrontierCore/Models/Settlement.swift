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
    /// Every inhabitant is a pawn; the headcount is derived, never stored.
    public var population: Double { Double(pawns.count) }
    public var pawns: [Pawn]
    /// Lifetime deaths by `PawnDeathCause.rawValue` — chronicle material.
    public var deathTallies: [String: Int]
    public var buildings: [BuildingInstance]
    public var storage: Resources
    public var storageCapacity: Double
    public var stats: SettlementStats
    public var inventory: [ItemInstance]   // unequipped items + active artifacts
    public var specialization: SettlementSpecialization
    /// Optional in-settlement spatial layout (the RimWorld-style colony grid).
    /// `nil` until the player opens build mode; the economy never depends on it.
    public var colony: ColonyMap?
    /// The living outdoor map — river, deposits, fog of war, points of interest.
    /// `nil` for pre-V2 saves; generated on demand from the world seed.
    public var localMap: LocalMap?
    /// Laws currently in force (see `SocietyEngine`).
    public var laws: [LawInstance]
    /// The colonist the assembly elected to lead — the player's voice in-world.
    public var leaderID: UUID?
    /// Wealth distribution: Gini and the class boundaries.
    public var society: SocietyStats
    /// Ticks left of a strike — gatherers have downed tools.
    public var strikeTicksRemaining: Int
    /// The settlement's faith: its cult, its devotion, its prophets.
    public var faith: FaithState

    public init(
        id: UUID = UUID(),
        name: String,
        kind: SettlementKind = .city,
        regionID: UUID? = nil,
        foundedTick: Int = 0,
        pawns: [Pawn] = [],
        deathTallies: [String: Int] = [:],
        buildings: [BuildingInstance] = [],
        storage: Resources = Resources(),
        storageCapacity: Double = 500,
        stats: SettlementStats = SettlementStats(),
        inventory: [ItemInstance] = [],
        specialization: SettlementSpecialization = .balanced,
        colony: ColonyMap? = nil,
        localMap: LocalMap? = nil,
        laws: [LawInstance] = [],
        leaderID: UUID? = nil,
        society: SocietyStats = SocietyStats(),
        strikeTicksRemaining: Int = 0,
        faith: FaithState = FaithState()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.regionID = regionID
        self.foundedTick = foundedTick
        self.pawns = pawns
        self.deathTallies = deathTallies
        self.buildings = buildings
        self.storage = storage
        self.storageCapacity = storageCapacity
        self.stats = stats
        self.inventory = inventory
        self.specialization = specialization
        self.colony = colony
        self.localMap = localMap
        self.laws = laws
        self.leaderID = leaderID
        self.society = society
        self.strikeTicksRemaining = strikeTicksRemaining
        self.faith = faith
    }

    // MARK: - Codable (resilient to pre-specialisation saves)

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, regionID, foundedTick, pawns, deathTallies
        case buildings, storage, storageCapacity, stats, inventory, specialization, colony, localMap
        case laws, leaderID, society, strikeTicksRemaining, faith
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(SettlementKind.self, forKey: .kind)
        regionID = try c.decodeIfPresent(UUID.self, forKey: .regionID)
        foundedTick = try c.decode(Int.self, forKey: .foundedTick)
        pawns = try c.decode([Pawn].self, forKey: .pawns)
        deathTallies = try c.decodeIfPresent([String: Int].self, forKey: .deathTallies) ?? [:]
        buildings = try c.decode([BuildingInstance].self, forKey: .buildings)
        storage = try c.decode(Resources.self, forKey: .storage)
        storageCapacity = try c.decode(Double.self, forKey: .storageCapacity)
        stats = try c.decode(SettlementStats.self, forKey: .stats)
        inventory = try c.decode([ItemInstance].self, forKey: .inventory)
        // Saves written before specialisations default to neutral.
        specialization = try c.decodeIfPresent(SettlementSpecialization.self, forKey: .specialization) ?? .balanced
        // Saves written before the colony grid have no layout yet.
        colony = try c.decodeIfPresent(ColonyMap.self, forKey: .colony)
        // Pre-V2 saves have no local map; it regenerates from the world seed.
        localMap = try c.decodeIfPresent(LocalMap.self, forKey: .localMap)
        // Society arrived after the first V2 cut.
        laws = try c.decodeIfPresent([LawInstance].self, forKey: .laws) ?? []
        leaderID = try c.decodeIfPresent(UUID.self, forKey: .leaderID)
        society = try c.decodeIfPresent(SocietyStats.self, forKey: .society) ?? SocietyStats()
        strikeTicksRemaining = try c.decodeIfPresent(Int.self, forKey: .strikeTicksRemaining) ?? 0
        faith = try c.decodeIfPresent(FaithState.self, forKey: .faith) ?? FaithState()
    }
}
