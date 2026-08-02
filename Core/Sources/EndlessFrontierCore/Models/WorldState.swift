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

/// An event that fired with choices attached and is waiting for the player —
/// the Leader — to decide. Without this the choices' effects (welcoming
/// migrants, buying a caravan's goods) could never run at all.
///
/// Identified by `templateID`, so the same event queuing again while one is
/// already pending replaces it rather than burying the player in duplicates.
public struct PendingEvent: Codable, Sendable, Equatable, Identifiable {
    public let templateID: String
    public let tick: Int

    public var id: String { templateID }

    public init(templateID: String, tick: Int) {
        self.templateID = templateID
        self.tick = tick
    }
}

/// The single source of truth for the simulation. Codable for JSON
/// persistence. Mutated only inside engine functions.
public struct WorldState: Codable, Sendable, Equatable {
    /// Bump when the meaning of persisted fields changes in a way that needs a
    /// migration step (not merely adding a new field — those are handled
    /// gracefully by the resilient decoder below).
    ///
    /// v2 is the "Endless Frontier V2" world: population became derived from
    /// pawns (every inhabitant is a colonist with genes/age/wealth) and each
    /// settlement gained a living local map. v1 saves are not migratable —
    /// their macro `population` no longer has meaning — so they are reset.
    public static let currentSchemaVersion = 2

    /// The oldest save the current build can load. Older saves are discarded
    /// and the player starts a fresh V2 world.
    public static let minimumSupportedSchemaVersion = 2

    public var schemaVersion: Int
    /// The world tick — the civilisation's clock. Harvests, births, seasons,
    /// laws. `ticksPerYear` counts years in these.
    public var tick: Int
    /// Which action step inside the current world tick the simulation has
    /// reached, `0 ..< WorldClock.actionStepsPerTick`.
    ///
    /// The finer grain people act on: a round of a fight, a stage of a march.
    /// Kept beside `tick` rather than replacing it so every number the game is
    /// balanced on keeps its meaning — see `WorldClock`.
    public var actionStep: Int

    /// Where the simulation stands on both clocks at once.
    public var clock: WorldClock { WorldClock(tick: tick, step: actionStep) }
    public var lastRealTimestamp: Date
    public var rngSeed: UInt64
    public var mapSeed: UInt64      // stable seed for per-hex map generation (never mutated)
    /// Whether the council runs the town when nobody is telling it what to do.
    ///
    /// On by default, and it never overrules an explicit choice — see
    /// `StewardEngine`. Off is for a player who wants every roof and every
    /// study to be theirs; the world then behaves exactly as it did before the
    /// steward existed, which is to say it stops advancing on its own.
    public var stewardEnabled: Bool = true

    public var era: Era
    /// The language this world was founded in. Everything *generated* — a
    /// newborn's name, an outpost, a seceded people, a freshly charted region
    /// — speaks it (see `NameForge`). Fixed at creation; UI chrome follows
    /// the app language independently.
    public var language: GameLanguage

    public var researchedTechs: Set<String>
    /// How many times each `repeatable` tech has been completed. Drives the
    /// escalating cost of an endless study, and how far its stacking effects
    /// have been pushed.
    public var techCompletions: [String: Int]
    /// Standing additive bonuses a tech's `modifier` effect has granted, keyed
    /// by global stat name.
    ///
    /// Research bonuses used to be written straight onto `globalStats` — where
    /// `recomputeGlobalStats` overwrote `knowledgeOutput` and `influenceOutput`
    /// from the buildings on the very next tick, silently erasing them. Every
    /// such effect in `techs.json` was dead on arrival. Held here, they survive
    /// the recompute and are re-applied on top of it.
    public var statModifiers: [String: Double]
    public var activeResearch: String?
    public var researchProgress: Double      // knowledge accumulated toward activeResearch

    public var globalStats: GlobalStats
    public var unlockedBuildings: Set<String>
    public var worldFlags: [String: Bool]

    public var settlements: [Settlement]
    public var regions: [Region]
    public var tradeRoutes: [TradeRoute]
    public var caravans: [Caravan]
    public var activeExpedition: Expedition?

    public var eventHistory: [HistoricalEvent]
    public var eventCooldowns: [String: Int]  // templateID -> tick when it last fired
    public var scheduledEffects: [ScheduledEffect]
    public var activeQuests: [QuestProgress]
    public var completedQuests: Set<String>
    /// A motion the assembly has voted on and put before the leader (the
    /// player) to ratify or veto. Only one sits at a time.
    public var pendingLawProposal: LawProposal?
    /// One snapshot per in-game year — the chronicle's raw material.
    public var records: [WorldRecord]
    /// Neighbouring peoples who grew out of your own settlement.
    public var tribes: [Tribe]
    /// Events awaiting the Leader's decision (see `PendingEvent`).
    public var pendingEvents: [PendingEvent]

    public init(
        schemaVersion: Int = WorldState.currentSchemaVersion,
        tick: Int = 0,
        actionStep: Int = 0,
        lastRealTimestamp: Date = Date(timeIntervalSince1970: 0),
        rngSeed: UInt64 = 0x5EED_F00D,
        mapSeed: UInt64 = 0x5EED_F00D,
        era: Era = .earlySettlement,
        language: GameLanguage = .cs,
        researchedTechs: Set<String> = [],
        techCompletions: [String: Int] = [:],
        statModifiers: [String: Double] = [:],
        activeResearch: String? = nil,
        researchProgress: Double = 0,
        globalStats: GlobalStats = GlobalStats(),
        unlockedBuildings: Set<String> = [],
        worldFlags: [String: Bool] = [:],
        settlements: [Settlement] = [],
        regions: [Region] = [],
        tradeRoutes: [TradeRoute] = [],
        caravans: [Caravan] = [],
        activeExpedition: Expedition? = nil,
        eventHistory: [HistoricalEvent] = [],
        eventCooldowns: [String: Int] = [:],
        scheduledEffects: [ScheduledEffect] = [],
        activeQuests: [QuestProgress] = [],
        completedQuests: Set<String> = [],
        pendingLawProposal: LawProposal? = nil,
        records: [WorldRecord] = [],
        tribes: [Tribe] = [],
        pendingEvents: [PendingEvent] = []
    ) {
        self.schemaVersion = schemaVersion
        self.tick = tick
        self.actionStep = actionStep
        self.lastRealTimestamp = lastRealTimestamp
        self.rngSeed = rngSeed
        self.mapSeed = mapSeed
        self.era = era
        self.language = language
        self.researchedTechs = researchedTechs
        self.techCompletions = techCompletions
        self.statModifiers = statModifiers
        self.activeResearch = activeResearch
        self.researchProgress = researchProgress
        self.globalStats = globalStats
        self.unlockedBuildings = unlockedBuildings
        self.worldFlags = worldFlags
        self.settlements = settlements
        self.regions = regions
        self.tradeRoutes = tradeRoutes
        self.caravans = caravans
        self.activeExpedition = activeExpedition
        self.eventHistory = eventHistory
        self.eventCooldowns = eventCooldowns
        self.scheduledEffects = scheduledEffects
        self.activeQuests = activeQuests
        self.completedQuests = completedQuests
        self.pendingLawProposal = pendingLawProposal
        self.records = records
        self.tribes = tribes
        self.pendingEvents = pendingEvents
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
        case schemaVersion, tick, lastRealTimestamp, rngSeed, mapSeed, era, language,
             researchedTechs, techCompletions, statModifiers, activeResearch,
             researchProgress, globalStats,
             unlockedBuildings, worldFlags, settlements, regions, tradeRoutes,
             caravans, activeExpedition, eventHistory, eventCooldowns,
             scheduledEffects, activeQuests, completedQuests, pendingLawProposal, records, tribes, pendingEvents
        case actionStep, stewardEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        // A save missing the key predates versioning → treat as the oldest
        // (legacy v1), so the loader can decide to reset it.
        schemaVersion = value(.schemaVersion, 1)
        tick = value(.tick, 0)
        actionStep = value(.actionStep, 0)
        // Worlds saved before the council ran the town get it switched on:
        // they are exactly the saves that have been standing still.
        stewardEnabled = value(.stewardEnabled, true)
        lastRealTimestamp = value(.lastRealTimestamp, Date(timeIntervalSince1970: 0))
        rngSeed = value(.rngSeed, 0x5EED_F00D)
        mapSeed = value(.mapSeed, 0x5EED_F00D)
        era = value(.era, .earlySettlement)
        // Worlds saved before languages existed were Czech-voiced ones.
        language = value(.language, .cs)
        researchedTechs = value(.researchedTechs, [])
        techCompletions = value(.techCompletions, [:])
        statModifiers = value(.statModifiers, [:])
        activeResearch = (try? c.decodeIfPresent(String.self, forKey: .activeResearch)) ?? nil
        researchProgress = value(.researchProgress, 0)
        globalStats = value(.globalStats, GlobalStats())
        unlockedBuildings = value(.unlockedBuildings, [])
        worldFlags = value(.worldFlags, [:])
        settlements = value(.settlements, [])
        regions = value(.regions, [])
        tradeRoutes = value(.tradeRoutes, [])
        caravans = value(.caravans, [])
        activeExpedition = (try? c.decodeIfPresent(Expedition.self, forKey: .activeExpedition)) ?? nil
        eventHistory = value(.eventHistory, [])
        eventCooldowns = value(.eventCooldowns, [:])
        scheduledEffects = value(.scheduledEffects, [])
        activeQuests = value(.activeQuests, [])
        completedQuests = value(.completedQuests, [])
        pendingLawProposal = (try? c.decodeIfPresent(LawProposal.self, forKey: .pendingLawProposal)) ?? nil
        records = value(.records, [])
        tribes = value(.tribes, [])
        pendingEvents = value(.pendingEvents, [])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(tick, forKey: .tick)
        try c.encode(lastRealTimestamp, forKey: .lastRealTimestamp)
        try c.encode(rngSeed, forKey: .rngSeed)
        try c.encode(mapSeed, forKey: .mapSeed)
        try c.encode(era, forKey: .era)
        try c.encode(language, forKey: .language)
        try c.encode(researchedTechs, forKey: .researchedTechs)
        try c.encode(techCompletions, forKey: .techCompletions)
        try c.encode(statModifiers, forKey: .statModifiers)
        try c.encodeIfPresent(activeResearch, forKey: .activeResearch)
        try c.encode(researchProgress, forKey: .researchProgress)
        try c.encode(globalStats, forKey: .globalStats)
        try c.encode(unlockedBuildings, forKey: .unlockedBuildings)
        try c.encode(worldFlags, forKey: .worldFlags)
        try c.encode(settlements, forKey: .settlements)
        try c.encode(regions, forKey: .regions)
        try c.encode(tradeRoutes, forKey: .tradeRoutes)
        try c.encode(caravans, forKey: .caravans)
        try c.encodeIfPresent(activeExpedition, forKey: .activeExpedition)
        try c.encode(eventHistory, forKey: .eventHistory)
        try c.encode(eventCooldowns, forKey: .eventCooldowns)
        try c.encode(scheduledEffects, forKey: .scheduledEffects)
        try c.encode(activeQuests, forKey: .activeQuests)
        try c.encode(completedQuests, forKey: .completedQuests)
        try c.encodeIfPresent(pendingLawProposal, forKey: .pendingLawProposal)
        try c.encode(records, forKey: .records)
        try c.encode(tribes, forKey: .tribes)
        try c.encode(pendingEvents, forKey: .pendingEvents)
    }
}
