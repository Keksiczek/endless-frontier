import Foundation

/// Aggregate, world-level health indicators (0–100 unless noted).
public struct GlobalStats: Codable, Sendable, Equatable {
    public var prosperity: Double
    public var stability: Double
    public var threatLevel: Double
    public var knowledgeOutput: Double   // per-tick, feeds research
    public var influenceOutput: Double   // per-tick, feeds expansion

    public init(
        prosperity: Double = 30,
        stability: Double = 60,
        threatLevel: Double = 10,
        knowledgeOutput: Double = 0,
        influenceOutput: Double = 0
    ) {
        self.prosperity = prosperity
        self.stability = stability
        self.threatLevel = threatLevel
        self.knowledgeOutput = knowledgeOutput
        self.influenceOutput = influenceOutput
    }

    public func applying(delta: Double, to stat: String) -> GlobalStats {
        var copy = self
        switch stat {
        case "prosperity": copy.prosperity += delta
        case "stability": copy.stability += delta
        case "threatLevel": copy.threatLevel += delta
        case "knowledgeOutput": copy.knowledgeOutput += delta
        case "influenceOutput": copy.influenceOutput += delta
        default: break
        }
        return copy.clamped()
    }

    public func clamped() -> GlobalStats {
        func c(_ v: Double) -> Double { min(max(v, 0), 100) }
        var copy = self
        copy.prosperity = c(prosperity)
        copy.stability = c(stability)
        copy.threatLevel = c(threatLevel)
        // outputs are not 0–100 bounded; only floored at 0
        copy.knowledgeOutput = max(0, knowledgeOutput)
        copy.influenceOutput = max(0, influenceOutput)
        return copy
    }
}

/// A record of an event that fired, kept for tension calculation and the
/// "while you were away" summary.
///
/// `id` is derived deterministically from `templateID` and `tick` (not a
/// random UUID) so that persisted world state is byte-for-byte reproducible
/// for a given seed — the simulation's core determinism guarantee.
public struct HistoricalEvent: Codable, Sendable, Equatable, Identifiable {
    public let templateID: String
    public let type: EventType
    public let tick: Int

    public var id: String { "\(templateID)#\(tick)" }

    public init(templateID: String, type: EventType, tick: Int) {
        self.templateID = templateID
        self.type = type
        self.tick = tick
    }
}

/// The single source of truth for the simulation. Codable for JSON
/// persistence. Mutated only inside engine functions.
public struct WorldState: Codable, Sendable, Equatable {
    /// Bump when the meaning of persisted fields changes in a way that needs a
    /// migration step (not merely adding a new field — those are handled
    /// gracefully by the resilient decoder below).
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var tick: Int
    public var lastRealTimestamp: Date
    public var rngSeed: UInt64
    public var mapSeed: UInt64      // stable seed for per-hex map generation (never mutated)
    public var era: Era

    public var researchedTechs: Set<String>
    public var activeResearch: String?
    public var researchProgress: Double      // knowledge accumulated toward activeResearch

    public var globalStats: GlobalStats
    public var unlockedBuildings: Set<String>
    public var worldFlags: [String: Bool]

    public var settlements: [Settlement]
    public var regions: [Region]
    public var tradeRoutes: [TradeRoute]
    public var activeExpedition: Expedition?

    public var eventHistory: [HistoricalEvent]
    public var eventCooldowns: [String: Int]  // templateID -> tick when it last fired
    public var scheduledEffects: [ScheduledEffect]
    public var activeQuests: [QuestProgress]
    public var completedQuests: Set<String>

    public init(
        schemaVersion: Int = WorldState.currentSchemaVersion,
        tick: Int = 0,
        lastRealTimestamp: Date = Date(timeIntervalSince1970: 0),
        rngSeed: UInt64 = 0x5EED_F00D,
        mapSeed: UInt64 = 0x5EED_F00D,
        era: Era = .earlySettlement,
        researchedTechs: Set<String> = [],
        activeResearch: String? = nil,
        researchProgress: Double = 0,
        globalStats: GlobalStats = GlobalStats(),
        unlockedBuildings: Set<String> = [],
        worldFlags: [String: Bool] = [:],
        settlements: [Settlement] = [],
        regions: [Region] = [],
        tradeRoutes: [TradeRoute] = [],
        activeExpedition: Expedition? = nil,
        eventHistory: [HistoricalEvent] = [],
        eventCooldowns: [String: Int] = [:],
        scheduledEffects: [ScheduledEffect] = [],
        activeQuests: [QuestProgress] = [],
        completedQuests: Set<String> = []
    ) {
        self.schemaVersion = schemaVersion
        self.tick = tick
        self.lastRealTimestamp = lastRealTimestamp
        self.rngSeed = rngSeed
        self.mapSeed = mapSeed
        self.era = era
        self.researchedTechs = researchedTechs
        self.activeResearch = activeResearch
        self.researchProgress = researchProgress
        self.globalStats = globalStats
        self.unlockedBuildings = unlockedBuildings
        self.worldFlags = worldFlags
        self.settlements = settlements
        self.regions = regions
        self.tradeRoutes = tradeRoutes
        self.activeExpedition = activeExpedition
        self.eventHistory = eventHistory
        self.eventCooldowns = eventCooldowns
        self.scheduledEffects = scheduledEffects
        self.activeQuests = activeQuests
        self.completedQuests = completedQuests
    }

    /// Total population across all settlements.
    public var totalPopulation: Double {
        settlements.reduce(0) { $0 + $1.population }
    }

    // MARK: - Resilient Codable
    //
    // Saves are a long-lived, evolving format for a game meant to be played for
    // weeks. A hand-written decoder lets *adding* a field stay backward
    // compatible: any key missing from an older save falls back to its default
    // instead of failing the whole load (which would silently reset the world).
    // `schemaVersion` is reserved for migrations where field *meaning* changes.

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, tick, lastRealTimestamp, rngSeed, mapSeed, era,
             researchedTechs, activeResearch, researchProgress, globalStats,
             unlockedBuildings, worldFlags, settlements, regions, tradeRoutes,
             activeExpedition, eventHistory, eventCooldowns, scheduledEffects,
             activeQuests, completedQuests
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        schemaVersion = value(.schemaVersion, WorldState.currentSchemaVersion)
        tick = value(.tick, 0)
        lastRealTimestamp = value(.lastRealTimestamp, Date(timeIntervalSince1970: 0))
        rngSeed = value(.rngSeed, 0x5EED_F00D)
        mapSeed = value(.mapSeed, 0x5EED_F00D)
        era = value(.era, .earlySettlement)
        researchedTechs = value(.researchedTechs, [])
        activeResearch = (try? c.decodeIfPresent(String.self, forKey: .activeResearch)) ?? nil
        researchProgress = value(.researchProgress, 0)
        globalStats = value(.globalStats, GlobalStats())
        unlockedBuildings = value(.unlockedBuildings, [])
        worldFlags = value(.worldFlags, [:])
        settlements = value(.settlements, [])
        regions = value(.regions, [])
        tradeRoutes = value(.tradeRoutes, [])
        activeExpedition = (try? c.decodeIfPresent(Expedition.self, forKey: .activeExpedition)) ?? nil
        eventHistory = value(.eventHistory, [])
        eventCooldowns = value(.eventCooldowns, [:])
        scheduledEffects = value(.scheduledEffects, [])
        activeQuests = value(.activeQuests, [])
        completedQuests = value(.completedQuests, [])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(tick, forKey: .tick)
        try c.encode(lastRealTimestamp, forKey: .lastRealTimestamp)
        try c.encode(rngSeed, forKey: .rngSeed)
        try c.encode(mapSeed, forKey: .mapSeed)
        try c.encode(era, forKey: .era)
        try c.encode(researchedTechs, forKey: .researchedTechs)
        try c.encodeIfPresent(activeResearch, forKey: .activeResearch)
        try c.encode(researchProgress, forKey: .researchProgress)
        try c.encode(globalStats, forKey: .globalStats)
        try c.encode(unlockedBuildings, forKey: .unlockedBuildings)
        try c.encode(worldFlags, forKey: .worldFlags)
        try c.encode(settlements, forKey: .settlements)
        try c.encode(regions, forKey: .regions)
        try c.encode(tradeRoutes, forKey: .tradeRoutes)
        try c.encodeIfPresent(activeExpedition, forKey: .activeExpedition)
        try c.encode(eventHistory, forKey: .eventHistory)
        try c.encode(eventCooldowns, forKey: .eventCooldowns)
        try c.encode(scheduledEffects, forKey: .scheduledEffects)
        try c.encode(activeQuests, forKey: .activeQuests)
        try c.encode(completedQuests, forKey: .completedQuests)
    }
}
