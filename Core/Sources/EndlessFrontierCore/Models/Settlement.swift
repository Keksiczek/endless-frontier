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

    /// A building a settlement simply *starts with*, with an id derived from
    /// what it is and where it stands.
    ///
    /// `UUID()` is the wrong default for anything the world creates. Two worlds
    /// built from the same seed came out with the same buildings under
    /// different ids, which is a determinism leak the whole project is built to
    /// avoid — `ConstructionEngine` already derives the id of a building it
    /// finishes, and the ones a colony is founded with were the gap.
    public static func founding(
        _ definitionID: String, at settlementID: UUID, slot: Int
    ) -> BuildingInstance {
        var h: UInt64 = 0x9E37_79B9_7F4A_7C15
        for byte in definitionID.utf8 { h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3 }
        let bytes = settlementID.uuid
        h = (h ^ UInt64(bytes.0)) &* 0x0100_0000_01B3
        h = (h ^ UInt64(bytes.8)) &* 0x0100_0000_01B3
        h = (h ^ UInt64(bytes.15)) &* 0x0100_0000_01B3
        h = (h ^ UInt64(bitPattern: Int64(slot))) &* 0x0100_0000_01B3
        var rng = SeededRNG(seed: h ^ (h >> 31))
        return BuildingInstance(id: rng.nextUUID(), definitionID: definitionID, count: 1)
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
    /// How many children have been born here, and how many people have walked
    /// in from outside, since the founding.
    ///
    /// Two counters rather than a reading off `ColonyLog`, which is a
    /// hundred-and-forty-entry ring: counting `.birth` entries in the journal
    /// silently undercounts the moment a colony is older than its diary, and
    /// **"nobody arrived" and "the arrivals were not recorded" are the same
    /// number and different bugs** (rule 67). `GeneProbe` needed to tell those
    /// apart to know whether immigration was moving the gene pool at all.
    public var birthTally: Int = 0
    public var arrivalTally: Int = 0
    public var buildings: [BuildingInstance]
    public var storage: Resources
    /// How deep this settlement's store is, **per resource** — see
    /// `BuildingDefinition.storage`. One number for all five meant a granary
    /// deepened the colony's store of knowledge, and it is why `materials` and
    /// `influence` used to sit pinned at the identical cap for half a run.
    public var storageCapacity: Resources
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
    /// Buildings currently being raised, oldest first (see `ConstructionEngine`).
    public var constructions: [ConstructionProject]
    /// Monotonic id source for construction projects — deterministic identity.
    public var constructionSequence: Int
    /// The settlement's living diary of small moments (see `ColonyLog`).
    public var journal: ColonyLog

    /// What each hunter was doing when the hunt last resolved.
    ///
    /// **Presentation only.** Nothing in the simulation reads this back; it
    /// exists so the canvas can draw a hunt that already happens — a colonist
    /// creeping, a colonist closing, a colonist standing over a carcass —
    /// instead of one arm going up and down at a deer. Replaced whole every
    /// time `WildlifeEngine` runs a hunt, so it is never stale by more than a
    /// tick, and small enough to save.
    public var huntPhases: [UUID: HuntEngine.Phase] = [:]
    /// Bonds between colonists — friendships, rivalries, marriages.
    public var relationships: [Relationship]
    /// Parties currently out working the local map's points of interest.
    public var expeditions: [POIExpedition]
    /// The beasts that belong to this settlement — gentled out of the wild and
    /// kept for what they do. They eat out of the stores, they can be hurt, and
    /// a badly kept one goes back to the woods.
    public var tamed: [TamedAnimal]
    /// **What the player has pointed at.** Trees marked to be felled, rock to
    /// be broken, heaps to be carried in, beasts to be hunted — see
    /// `Designation`. The engines that already choose targets take a marked
    /// one first; nothing here orders a person anywhere.
    public var designations: [Designation] = []
    /// What the colony can move a body or a load with. A mount here points at
    /// a beast in `tamed`; a cart stands on its own. See
    /// `docs/MOUNTS_AND_VEHICLES.md`.
    public var conveyances: [Conveyance]
    /// Raw and processed materials on hand, by item id.
    ///
    /// Materials are *counted*, not individually tracked: nobody cares which
    /// iron ingot goes into the sword, and a colony that mines for two hundred
    /// years would otherwise carry a hundred thousand `ItemInstance` UUIDs
    /// through every save. Equipment and artifacts — where the individual
    /// matters, because a colonist wears one — stay in `inventory`.
    public var stockpile: [String: Int]
    /// Part-finished raw materials, by item id: worker-ticks banked toward the
    /// next whole unit. Without it a colony too small to complete a unit in one
    /// tick would have its work rounded away every tick and never bank
    /// anything at all.
    public var rawProgress: [String: Double]
    /// The most recent battle fought here, beat by beat. Kept so the canvas can
    /// play a raid out over real seconds instead of the player being handed a
    /// finished result — see `BattleLog`.
    public var lastBattle: BattleLog?
    /// The fights before that one, newest first.
    ///
    /// Keks: *"battle logy nejdou nikde zobrazit."* True, and worse than it
    /// sounds — the colony kept exactly **one** record, the report card was the
    /// only thing that could open it, and dismissing the card put it away *for
    /// good*. A raid you looked away from was a raid the game no longer had.
    /// Capped at `battlesKept`: a chronicle, not an archive.
    public var battleHistory: [BattleLog] = []

    /// How many fights a colony remembers in full.
    public static let battlesKept = 8

    /// What the colony has been told to make, oldest first.
    ///
    /// Crafting used to be a button that produced an item out of the stockpile
    /// instantly, made by nobody. These are things somebody has to walk to a
    /// bench and work at — see `CraftingEngine`.
    public var craftOrders: [CraftOrder] = []

    /// Worker-ticks the cooks have banked toward the next batch.
    ///
    /// The same reason `rawProgress` exists: a colony too small to finish a pot
    /// of anything in one tick would have its work rounded away every tick and
    /// never cook a thing. Capped at one batch by `CookingEngine` so a kitchen
    /// standing idle over a bare shelf cannot store up a decade of afternoons.
    public var kitchenProgress: Double = 0

    /// A fight that is **still going on** here, if one is.
    ///
    /// `lastBattle` is a recording; this is the thing itself, mid-swing, with
    /// the player's orders on it. While it is set the raid has not been decided
    /// — see `SiegeEngine`.
    public var siege: Siege?

    /// A sickness running through the colony, if one is.
    ///
    /// The threat that scales the *wrong* way on purpose — a big, crowded,
    /// well-traded town is the one that gets it, and no wall keeps it out. See
    /// `PlagueEngine`.
    public var outbreak: Outbreak?
    /// When the last sickness burned itself out.
    ///
    /// A colony that has just been through one is not ready for another: the
    /// people who survived it are the people who survive things, and the town
    /// has just learned where the bad water was. Without this the odds scale
    /// with population and a big colony is simply *always* ill — measured, a
    /// town of 350 caught something every five years and spent two centuries
    /// too sick to farm.
    public var lastOutbreakTick: Int?

    /// People taken off the field when a raid broke, who are not colonists yet.
    ///
    /// Kept apart from `pawns` on purpose — see `Captive`. They eat, they do no
    /// work, and what the colony is like to live in decides whether they come
    /// round or go over the wall. See `CaptiveEngine`.
    public var captives: [Captive]

    /// The colony's standing orders — trades, rations and who parties may take.
    /// At sixty souls the pawn screen is for looking at somebody; this is how
    /// the town is actually run. See `ColonyPolicy`.
    public var policy: ColonyPolicy

    /// The ways worn into the colony's own ground by the journeys its people
    /// make. Written only by `PathEngine`; read by the canvas. See
    /// `SettlementPaths` — nothing here is built or paid for, it is walked.
    public var paths: SettlementPaths = SettlementPaths()

    /// The party out at a given point of interest, if one is.
    public func expedition(forPOI poiID: Int) -> POIExpedition? {
        expeditions.first { $0.poiID == poiID }
    }

    /// Whether a place already has people on their way to it — you cannot send
    /// two parties to the same ruins.
    public func hasPartyOut(poiID: Int) -> Bool {
        expeditions.contains { $0.poiID == poiID }
    }

    /// Colonists currently out of the settlement on an expedition.
    public var awayPawns: [Pawn] { pawns.filter(\.isAway) }

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
        storageCapacity: Resources = .uniform(500),
        stats: SettlementStats = SettlementStats(),
        inventory: [ItemInstance] = [],
        specialization: SettlementSpecialization = .balanced,
        colony: ColonyMap? = nil,
        localMap: LocalMap? = nil,
        laws: [LawInstance] = [],
        leaderID: UUID? = nil,
        society: SocietyStats = SocietyStats(),
        strikeTicksRemaining: Int = 0,
        faith: FaithState = FaithState(),
        constructions: [ConstructionProject] = [],
        constructionSequence: Int = 0,
        journal: ColonyLog = ColonyLog(),
        relationships: [Relationship] = [],
        expeditions: [POIExpedition] = [],
        tamed: [TamedAnimal] = [],
        conveyances: [Conveyance] = [],
        stockpile: [String: Int] = [:],
        rawProgress: [String: Double] = [:],
        lastBattle: BattleLog? = nil,
        captives: [Captive] = [],
        policy: ColonyPolicy = ColonyPolicy()
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
        self.constructions = constructions
        self.constructionSequence = constructionSequence
        self.journal = journal
        self.relationships = relationships
        self.expeditions = expeditions
        self.tamed = tamed
        self.conveyances = conveyances
        self.stockpile = stockpile
        self.rawProgress = rawProgress
        self.lastBattle = lastBattle
        self.captives = captives
        self.policy = policy
    }

    // MARK: - Codable (resilient to pre-specialisation saves)

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, regionID, foundedTick, pawns, deathTallies, birthTally, arrivalTally
        case buildings, storage, storageCapacity, stats, inventory, specialization, colony, localMap
        case laws, leaderID, society, strikeTicksRemaining, faith
        case constructions, constructionSequence, journal, relationships, expeditions
        case huntPhases
        case tamed
        case conveyances
        case designations
        case stockpile, rawProgress, lastBattle, battleHistory, policy, siege
        case craftOrders, kitchenProgress
        case outbreak, lastOutbreakTick, captives
        case paths
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
        birthTally = try c.decodeIfPresent(Int.self, forKey: .birthTally) ?? 0
        arrivalTally = try c.decodeIfPresent(Int.self, forKey: .arrivalTally) ?? 0
        buildings = try c.decode([BuildingInstance].self, forKey: .buildings)
        storage = try c.decode(Resources.self, forKey: .storage)
        // Typed as of 2026-08-13. A save written before it holds one number for
        // all five, which reads as every store being that deep — the world it
        // was actually played in. `ResourceLoop` re-derives capacity from the
        // standing buildings on the next tick anyway, so this only has to be
        // true for the instant between loading and the first tick.
        if let typed = try? c.decode(Resources.self, forKey: .storageCapacity) {
            storageCapacity = typed
        } else {
            storageCapacity = .uniform(try c.decode(Double.self, forKey: .storageCapacity))
        }
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
        // Construction-over-time and the journal arrived after the first V2 cut.
        constructions = try c.decodeIfPresent([ConstructionProject].self, forKey: .constructions) ?? []
        constructionSequence = try c.decodeIfPresent(Int.self, forKey: .constructionSequence) ?? 0
        journal = try c.decodeIfPresent(ColonyLog.self, forKey: .journal) ?? ColonyLog()
        huntPhases = try c.decodeIfPresent([UUID: HuntEngine.Phase].self, forKey: .huntPhases) ?? [:]
        relationships = try c.decodeIfPresent([Relationship].self, forKey: .relationships) ?? []
        expeditions = try c.decodeIfPresent([POIExpedition].self, forKey: .expeditions) ?? []
        tamed = try c.decodeIfPresent([TamedAnimal].self, forKey: .tamed) ?? []
        designations = try c.decodeIfPresent([Designation].self, forKey: .designations) ?? []
        conveyances = try c.decodeIfPresent([Conveyance].self, forKey: .conveyances) ?? []
        stockpile = try c.decodeIfPresent([String: Int].self, forKey: .stockpile) ?? [:]
        rawProgress = try c.decodeIfPresent([String: Double].self, forKey: .rawProgress) ?? [:]
        lastBattle = try c.decodeIfPresent(BattleLog.self, forKey: .lastBattle)
        // Saves written before the colony kept a history have none, and the
        // fight they were in the middle of is still `lastBattle` (rule 37).
        battleHistory = try c.decodeIfPresent([BattleLog].self, forKey: .battleHistory) ?? []
        siege = try c.decodeIfPresent(Siege.self, forKey: .siege)
        outbreak = try c.decodeIfPresent(Outbreak.self, forKey: .outbreak)
        // Every save written before anybody was ever taken alive holds nobody.
        captives = try c.decodeIfPresent([Captive].self, forKey: .captives) ?? []
        lastOutbreakTick = try c.decodeIfPresent(Int.self, forKey: .lastOutbreakTick)
        craftOrders = try c.decodeIfPresent([CraftOrder].self, forKey: .craftOrders) ?? []
        kitchenProgress = try c.decodeIfPresent(Double.self, forKey: .kitchenProgress) ?? 0
        // Decode-if-present: a save from before standing orders loads as a
        // colony under none, and plays exactly as it did.
        policy = try c.decodeIfPresent(ColonyPolicy.self, forKey: .policy) ?? ColonyPolicy()
        // A save written before the settlement had ways in it loads with none,
        // and `PathEngine` wears them back in over the following seasons.
        paths = try c.decodeIfPresent(SettlementPaths.self, forKey: .paths) ?? SettlementPaths()
    }
}
