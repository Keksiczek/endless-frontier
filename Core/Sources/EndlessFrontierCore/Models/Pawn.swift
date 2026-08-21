import Foundation

/// A kind of work a colonist can be assigned to. Each maps to the resource it
/// helps produce (idle produces nothing).
public enum WorkKind: String, Codable, Sendable, CaseIterable, Equatable {
    case farming
    case logging
    case mining
    case research
    case trade
    case foraging   // herbs → knowledge/medicine
    case hunting    // game → food
    case healing    // tends the sick (no resource)
    case building   // raises structures (no resource)
    case scouting   // reveals the fog of war (no resource)
    case priest     // tends faith (no resource)
    case garrison   // mans the walls and the barracks (no resource)
    /// Makes **things** at a bench: tools, arms, cloth, bread.
    ///
    /// The one trade the colony did not have, and the reason crafting was a
    /// menu button rather than part of the world — a recipe named a workshop
    /// and required a workshop, and no colonist could ever be a person who
    /// worked in one. See `CraftingEngine`.
    case crafting
    /// Turns what the fields and the woods brought in into **food**.
    ///
    /// The trade at the end of the chain, and the one the colony never had.
    /// Farming used to put food in the granary directly — a farmer's skill
    /// became meals wherever they stood — so grain, meat and a kitchen were
    /// three things the game had words for and no mechanism behind. See
    /// `CookingEngine`.
    case cooking
    case idle

    /// The resource this work contributes to, if any.
    ///
    /// Farming and hunting used to answer `.food` here, which is what made a
    /// farmer's skill turn into meals out of nowhere. They make **things** now
    /// — grain in the field, meat at the carcass — exactly as crafting always
    /// has, and cooking is what turns those into the pool the colony eats from.
    /// Kept for settlements still on the old abstract fields (see
    /// `LocalMap.usesEntityFields`), which is the only path that still reads it
    /// for food.
    public var resource: ResourceType? {
        switch self {
        case .farming, .hunting: return .food
        case .logging, .mining: return .materials
        case .research, .foraging: return .knowledge
        case .trade: return .influence
        // Crafting makes *things*, which is exactly why it feeds no
        // abstract pool: its output is an item on a shelf. Cooking is the same
        // shape from the other end: it makes food out of things, and
        // `CookingEngine` — not the per-skill trickle — is what banks it.
        case .healing, .building, .scouting, .priest, .garrison, .crafting,
             .cooking, .idle:
            return nil
        }
    }

    /// The local-map deposits this work is done at.
    ///
    /// Plural since the ground stopped being one undifferentiated "stone": a
    /// miner works whatever is down there — plain rock, an iron seam, a clay
    /// bed — and which of those a valley actually holds is now the biome's
    /// business.
    public var harvestedDeposits: [LocalResourceKind] {
        switch self {
        case .farming: return [.field]
        case .logging: return [.forest]
        case .mining: return [.stone, .ironOre, .clay, .coal, .oilSeep]
        case .foraging: return [.herbs]
        default: return []
        }
    }

    /// The deposit this work is most associated with — what the canvas walks a
    /// colonist to when the map holds several it could work.
    public var harvestedDeposit: LocalResourceKind? { harvestedDeposits.first }
}

/// A colonist's needs, each on a 0–100 scale where 100 is fully satisfied.
public struct PawnNeeds: Codable, Sendable, Equatable {
    public var hunger: Double
    public var rest: Double
    public var recreation: Double
    /// How warm they are, 0…100. Not a temperature — a *comfort*: what the
    /// season is doing to them, less whatever their clothes, their roof and
    /// their hearth give back.
    ///
    /// The wild has had comfort bands since animals got bodies, and colonists
    /// had nothing: a colony on the tundra was exactly as comfortable in
    /// January as one on the plains in June. Winter is the season the whole
    /// game is shaped around and it did nothing to anybody.
    public var warmth: Double

    public init(hunger: Double = 80, rest: Double = 80, recreation: Double = 70,
                warmth: Double = 80) {
        self.hunger = hunger
        self.rest = rest
        self.recreation = recreation
        self.warmth = warmth
    }

    // Resilient decode: warmth postdates the first three needs.
    private enum CodingKeys: String, CodingKey { case hunger, rest, recreation, warmth }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hunger = try c.decode(Double.self, forKey: .hunger)
        rest = try c.decode(Double.self, forKey: .rest)
        recreation = try c.decode(Double.self, forKey: .recreation)
        warmth = try c.decodeIfPresent(Double.self, forKey: .warmth) ?? 80
    }

    /// The average satisfaction across needs — the basis for mood.
    public var average: Double {
        (hunger + rest + recreation + warmth) / 4
    }

    public func clamped() -> PawnNeeds {
        func c(_ v: Double) -> Double { min(max(v, 0), 100) }
        return PawnNeeds(hunger: c(hunger), rest: c(rest),
                         recreation: c(recreation), warmth: c(warmth))
    }
}

/// Selects which colonist(s) a pawn-targeting event effect applies to.
/// Deterministic — no randomness — so the simulation stays reproducible.
public enum PawnSelector: String, Codable, Sendable, Equatable {
    case all
    case first
    case lowestHealth = "lowest_health"
    case lowestMood = "lowest_mood"
}

/// A personality trait that shifts mood and (optionally) skill aptitude.
public enum PawnTrait: String, Codable, Sendable, CaseIterable, Equatable {
    case optimist
    case pessimist
    case hardWorker = "hard_worker"
    case lazy
    case none

    /// Flat mood modifier applied on top of need satisfaction.
    public var moodModifier: Double {
        switch self {
        case .optimist: return 8
        case .pessimist: return -8
        default: return 0
        }
    }

    /// What to call it, in the player's language.
    public var displayName: LocalizedText {
        switch self {
        case .optimist: return LocalizedText(values: [.en: "Optimist", .cs: "Optimista"])
        case .pessimist: return LocalizedText(values: [.en: "Pessimist", .cs: "Pesimista"])
        case .hardWorker: return LocalizedText(values: [.en: "Hard worker", .cs: "Dříč"])
        case .lazy: return LocalizedText(values: [.en: "Idler", .cs: "Lenoch"])
        case .none: return LocalizedText(values: [.en: "Ordinary", .cs: "Obyčejný"])
        }
    }
}

/// A named colonist — the individual unit of the colony. Every inhabitant of
/// a settlement is a pawn: the macro `Settlement.population` is derived from
/// the pawn count, and lives (birth, growth, old age, inheritance) play out
/// through the `PopulationEngine`.
public struct Pawn: Codable, Sendable, Identifiable, Equatable {
    /// The age (in years) at which a colonist starts working and voting.
    public static let adultAgeYears = 14
    /// The default age for pawns created without an explicit one (founders,
    /// recruits, test fixtures): a working adult in their prime.
    public static let defaultAdultAgeTicks = 1500   // 25 years at 60 ticks/year

    public let id: UUID
    public var name: String
    public var trait: PawnTrait
    public var skills: [WorkKind: Int]   // 0…20 per work kind
    public var skillXP: [WorkKind: Double]  // progress toward the next level
    public var needs: PawnNeeds
    public var mood: Double              // 0…100, derived from needs + trait
    /// How the last thing that happened is still sitting with them, added on
    /// top of the mood their needs give and fading over a season.
    ///
    /// `mood` is recomputed from scratch every tick, which made every
    /// `pawn_mood` effect in `events.json` a lie: a golden age lifted a
    /// colonist's spirits for exactly one tick and `PawnEngine` wrote over it
    /// before anybody could notice. An event has to be *felt*, so what it does
    /// lands here and decays, and the mood formula reads it.
    public var moodShift: Double = 0
    public var assignedWork: WorkKind
    public var health: Double            // 0…100
    public var isBroken: Bool            // mental break — stops working until mood recovers
    public var equipment: [EquipmentSlot: ItemInstance]  // one item per slot
    public var age: Int                  // in ticks; interpret via config.ticksPerYear
    public var genes: Genes
    public var wealth: Double            // personal savings — class standing, inheritance
    public var pregnancyTicksRemaining: Int   // 0 = not expecting
    /// The expedition this colonist is away on, if any. Someone out at the
    /// ruins is not also at the plough: `PawnEngine` skips their output and
    /// `AgentMotion` walks them across the map instead of through their day.
    public var expeditionID: UUID?
    /// The people this colonist is posted to as an envoy, if any.
    ///
    /// An embassy is a colonist who **is not here**. That is the whole cost of
    /// it and the reason it is a decision rather than a purchase: a colony of
    /// thirty feels one fewer pair of hands, for as long as the post stands.
    ///
    /// Deliberately the *only* record of the posting — the tribe does not keep
    /// a copy (rule 8, two numbers for one thing). And deliberately not paired
    /// with a "posted since" tick either: standing accrues as a **rate** every
    /// year the envoy sits, so the accumulated total already is the duration.
    ///
    /// Optional, so every save written before embassies existed decodes to
    /// nobody being posted anywhere (rule 3).
    public var envoyToTribeID: UUID?
    /// The concrete piece of work this colonist is on right now — which tree,
    /// which outcrop, which scaffold. A trade says what they do; this says what
    /// they are doing. Nil when idle, away or unemployed; old saves decode to
    /// nil and are given work on the next posting.
    public var currentJob: Job?
    /// Where they are going **because of something they need** — a meal, a
    /// fire. Outranks the job: a need interrupts work rather than queueing
    /// behind it, which is the whole reason it is a field of its own and not a
    /// `JobKind`. Nil is the ordinary case.
    public var errand: Errand?
    /// The dwelling this colonist sleeps in — a `BuildingPlacement.id`, or nil
    /// for someone sleeping rough.
    ///
    /// A settlement's *housing capacity* says how many souls it can hold. This
    /// says where one of them actually lives, which is a different question and
    /// the one that had never been asked: everybody picked a house from a list
    /// every frame, so a dozen colonists slept stacked on one doorstep while
    /// three huts stood empty next door. A home is a place now, held by one
    /// household, with a bed in it — and the colonists who could not get one
    /// sleep badly and say so.
    public var homeID: UUID?
    /// What they have in their arms, if anything — a heap of timber or stone
    /// on its way to the store. Nil for everyone not presently carrying.
    public var carrying: HaulLoad?
    /// The walk a hauler is on. Only ever set while they are fetching or
    /// carrying: the rest of the time their place on the canvas is a function
    /// of their day, and this stays nil so nothing overrides it.
    ///
    /// This used to be a single point advanced one step per tick, and that is
    /// why the village looked dead. A tick is two real minutes, hauling
    /// outranks the day in `AgentMotion`, and the whole food chain runs on
    /// carrying the harvest in — so most of the colony was drawn standing
    /// perfectly still for two minutes at a time, legs swinging, then jumping a
    /// stride. A walk that knows when it began and when it ends can be asked
    /// for a *fractional* tick, which is what `Errand` had worked out already.
    public var haulWalk: WalkPath?

    /// Where a hauler is at `tick` — nil for everyone not presently on a walk.
    public func haulPosition(at tick: Double) -> LocalPoint? {
        haulWalk?.position(at: tick)
    }
    /// What happened to them, part by part.
    ///
    /// `health` is still the aggregate everything balances on; this is the
    /// answer to *what* took it. A hunter gored by a boar and a hunter who had
    /// a bad winter used to be the same colonist at sixty — now one of them has
    /// an arm that will not swing an axe until somebody sees to it.
    public var body: Body

    /// Whether this colonist is out of the settlement right now.
    ///
    /// An envoy counts, which is what makes the embassy cost anything at all:
    /// everything that already respects `isAway` — the labour engine, the food
    /// they do not eat at home, the canvas that does not draw them at a bench —
    /// takes the absence into account without a second seam being cut for it.
    public var isAway: Bool { expeditionID != nil || envoyToTribeID != nil }

    public init(
        id: UUID = UUID(),
        name: String,
        trait: PawnTrait = .none,
        skills: [WorkKind: Int] = [:],
        skillXP: [WorkKind: Double] = [:],
        needs: PawnNeeds = PawnNeeds(),
        mood: Double = 70,
        assignedWork: WorkKind = .idle,
        health: Double = 100,
        isBroken: Bool = false,
        equipment: [EquipmentSlot: ItemInstance] = [:],
        age: Int = Pawn.defaultAdultAgeTicks,
        genes: Genes = Genes(),
        wealth: Double = 0,
        pregnancyTicksRemaining: Int = 0,
        expeditionID: UUID? = nil,
        envoyToTribeID: UUID? = nil,
        currentJob: Job? = nil,
        errand: Errand? = nil,
        homeID: UUID? = nil,
        carrying: HaulLoad? = nil,
        haulWalk: WalkPath? = nil,
        body: Body = Body()
    ) {
        self.id = id
        self.name = name
        self.trait = trait
        self.skills = skills
        self.skillXP = skillXP
        self.needs = needs
        self.mood = mood
        self.assignedWork = assignedWork
        self.health = health
        self.isBroken = isBroken
        self.equipment = equipment
        self.age = age
        self.genes = genes
        self.wealth = wealth
        self.pregnancyTicksRemaining = pregnancyTicksRemaining
        self.expeditionID = expeditionID
        self.envoyToTribeID = envoyToTribeID
        self.currentJob = currentJob
        self.errand = errand
        self.homeID = homeID
        self.carrying = carrying
        self.haulWalk = haulWalk
        self.body = body
    }

    public func skill(_ kind: WorkKind) -> Int { skills[kind] ?? 0 }

    /// Whole in-game years lived.
    public func ageYears(ticksPerYear: Int) -> Int {
        guard ticksPerYear > 0 else { return 0 }
        return age / ticksPerYear
    }

    /// Adults work, vote and can bear children.
    public func isAdult(ticksPerYear: Int) -> Bool {
        ageYears(ticksPerYear: ticksPerYear) >= Pawn.adultAgeYears
    }

    // MARK: - Codable (resilient to pre-V2 saves without life-cycle fields)

    private enum CodingKeys: String, CodingKey {
        case id, name, trait, skills, skillXP, needs, mood, assignedWork
        case health, isBroken, equipment
        case age, genes, wealth, pregnancyTicksRemaining, expeditionID, currentJob
        case envoyToTribeID
        case homeID, carrying, haulWalk, body, errand, moodShift
    }

    /// Keys that no longer have a property behind them. Kept apart from
    /// `CodingKeys` so `Encodable` still synthesises: a key with nothing to
    /// encode stops Swift writing the encoder for the whole type.
    private enum LegacyKeys: String, CodingKey {
        /// A hauler used to be stored as the one point they stood on.
        case haulPosition
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        trait = try c.decode(PawnTrait.self, forKey: .trait)
        skills = try c.decode([WorkKind: Int].self, forKey: .skills)
        skillXP = try c.decode([WorkKind: Double].self, forKey: .skillXP)
        needs = try c.decode(PawnNeeds.self, forKey: .needs)
        mood = try c.decode(Double.self, forKey: .mood)
        assignedWork = try c.decode(WorkKind.self, forKey: .assignedWork)
        health = try c.decode(Double.self, forKey: .health)
        isBroken = try c.decode(Bool.self, forKey: .isBroken)
        equipment = try c.decodeIfPresent([EquipmentSlot: ItemInstance].self, forKey: .equipment) ?? [:]
        age = try c.decodeIfPresent(Int.self, forKey: .age) ?? Pawn.defaultAdultAgeTicks
        genes = try c.decodeIfPresent(Genes.self, forKey: .genes) ?? Genes()
        wealth = try c.decodeIfPresent(Double.self, forKey: .wealth) ?? 0
        pregnancyTicksRemaining = try c.decodeIfPresent(Int.self, forKey: .pregnancyTicksRemaining) ?? 0
        expeditionID = try c.decodeIfPresent(UUID.self, forKey: .expeditionID)
        envoyToTribeID = try c.decodeIfPresent(UUID.self, forKey: .envoyToTribeID)
        currentJob = try c.decodeIfPresent(Job.self, forKey: .currentJob)
        // A colonist saved before needs sent anybody anywhere is standing still.
        errand = try c.decodeIfPresent(Errand.self, forKey: .errand)
        homeID = try c.decodeIfPresent(UUID.self, forKey: .homeID)
        carrying = try c.decodeIfPresent(HaulLoad.self, forKey: .carrying)
        // A hauler saved before walks had a beginning and an end is standing on
        // the one point that was kept for them; the next tick gives them a
        // proper walk from there (rule 3).
        if let walk = try c.decodeIfPresent(WalkPath.self, forKey: .haulWalk) {
            haulWalk = walk
        } else {
            let old = try decoder.container(keyedBy: LegacyKeys.self)
            haulWalk = try old.decodeIfPresent(LocalPoint.self, forKey: .haulPosition)
                .map { WalkPath(from: $0, to: $0, leftAt: 0, arrivesAt: 0) }
        }
        // A colonist from before bodies is whole.
        body = try c.decodeIfPresent(Body.self, forKey: .body) ?? Body()
        // …and one saved before events were felt is feeling nothing in particular.
        moodShift = try c.decodeIfPresent(Double.self, forKey: .moodShift) ?? 0
    }
}
