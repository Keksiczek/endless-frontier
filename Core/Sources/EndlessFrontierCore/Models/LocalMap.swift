import Foundation

/// A point in a settlement's local map, in normalised `0…1` space so the
/// renderer can scale it to any canvas size.
public struct LocalPoint: Codable, Sendable, Equatable, Hashable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// The kinds of harvestable resource deposit on the local map. Each maps to
/// the work colonists do there and the game resource it feeds.
public enum LocalResourceKind: String, Codable, Sendable, CaseIterable {
    case field    // farming → food
    case forest   // logging → materials
    case stone    // mining → materials
    case herbs    // foraging → knowledge/medicine
    case ironOre = "iron_ore"   // mining → materials, and the ore the forge needs
    case clay                   // mining → materials, and the clay the kiln needs

    /// The colonist work that harvests this deposit.
    public var work: WorkKind {
        switch self {
        case .field: return .farming
        case .forest: return .logging
        case .stone, .ironOre, .clay: return .mining
        case .herbs: return .foraging
        }
    }

    /// The concrete material this ground yields, by item id — the root of the
    /// crafting tree.
    ///
    /// Everything the colony dug used to dissolve into one abstract
    /// `materials` pool, while `recipes.json` asked for `iron_ingot` and
    /// `timber_bundle` that no recipe produced and only random loot could
    /// supply. Nine of twenty-three recipes, and the whole steel-to-fusion
    /// chain above them, were unreachable by working for it. A field feeds
    /// people rather than the forge, so it yields nothing here.
    public var rawMaterialID: String? {
        switch self {
        case .field: return nil
        case .forest: return "wood"
        case .stone: return "rough_stone"
        case .herbs: return "herb_bundle"
        case .ironOre: return "iron_ore"
        case .clay: return "clay"
        }
    }
}

/// A harvestable deposit. `amount` is live simulation state — it depletes as
/// colonists work it and regrows seasonally — while `capacity` and `position`
/// are fixed by generation.
public struct ResourceNode: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let kind: LocalResourceKind
    public let position: LocalPoint
    public var amount: Double
    public let capacity: Double

    public init(id: Int, kind: LocalResourceKind, position: LocalPoint, amount: Double, capacity: Double) {
        self.id = id
        self.kind = kind
        self.position = position
        self.amount = amount
        self.capacity = capacity
    }
}

/// The sea's edge on a coastal map.
///
/// A coast used to be a field with a stream through it like everywhere else —
/// the same `RiverShape` every biome got — so the one country whose whole
/// character is *the water* read exactly like the plains. This is an edge of
/// open sea along one side of the map, with a coastline that wanders.
public struct ShoreShape: Codable, Sendable, Equatable {
    public enum Side: String, Codable, Sendable, CaseIterable {
        case north, south, east, west
    }
    public var side: Side
    /// How far in from that edge the water reaches on average, 0…1.
    public var depth: Double
    /// How much the coastline wanders in and out.
    public var amplitude: Double
    public var phase: Double

    public init(side: Side, depth: Double, amplitude: Double, phase: Double) {
        self.side = side
        self.depth = depth
        self.amplitude = amplitude
        self.phase = phase
    }

    /// How far the water reaches in from its edge at a position `t` (0…1)
    /// along the coast.
    public func reach(at t: Double) -> Double {
        max(0.02, depth + sin(t * 6.283185 + phase) * amplitude
                        + sin(t * 15.5 + phase * 1.7) * amplitude * 0.35)
    }

    /// Whether a point is out in the water.
    public func isWater(_ p: LocalPoint) -> Bool {
        switch side {
        case .north: return p.y < reach(at: p.x)
        case .south: return p.y > 1 - reach(at: p.x)
        case .west:  return p.x < reach(at: p.y)
        case .east:  return p.x > 1 - reach(at: p.y)
        }
    }

    /// How far inland a point is from the waterline — negative out at sea.
    /// Lets the shore fade into the beach instead of stopping at a hard line.
    public func distanceInland(_ p: LocalPoint) -> Double {
        switch side {
        case .north: return p.y - reach(at: p.x)
        case .south: return (1 - reach(at: p.x)) - p.y
        case .west:  return p.x - reach(at: p.y)
        case .east:  return (1 - reach(at: p.y)) - p.x
        }
    }
}

/// A point of interest discovered by exploring the fog of war — ruins, a cave,
/// a spring, buried treasure, a forgotten shrine or a wrecked caravan.
/// Discovery grants a one-off reward and a journal line (see
/// `ResourceLoop.chartGround`) — finding something *feels* like finding it.
///
/// Finding it is only the first half. A discovered POI is a *place you can
/// work* (see `LocalPOIEngine`): the finite ones give up their goods over a
/// few runs and are then picked clean, while a spring and a shrine keep
/// giving as long as you let them rest between visits.
public enum LocalPOIKind: String, Codable, Sendable, CaseIterable {
    case ruins      // ancient knowledge
    case cave       // rich stone
    case spring     // healing waters
    case treasure   // a cache of goods
    case shrine     // the old gods still listen
    case wreck      // a caravan that never arrived
    // Six place kinds was thin after an evening: by the second valley you had
    // seen all of them and a landmark stopped being news. These six each give a
    // *different* reason to send people out — food, a teacher, a map, salt,
    // grave goods, and something that fell out of the sky.
    case orchard    // a farm gone feral — food, year after year
    case hermit     // somebody living out there who will teach
    case watchtower // climb it and the country draws itself
    case saltPan    // salt: the difference between meat and meat that keeps
    case barrow     // a burial mound, and what was buried with them
    case starfall   // a fallen star, still warm

    /// The journal's line for the moment of discovery.
    public var discoveryText: LocalizedText {
        switch self {
        case .ruins: return LocalizedText(values: [
            .en: "Scouts found ancient ruins — old knowledge lay among the stones.",
            .cs: "Zvědové našli prastaré zříceniny — mezi kameny leželo staré vědění."])
        case .cave: return LocalizedText(values: [
            .en: "Scouts found a deep cave rich in stone.",
            .cs: "Zvědové objevili hlubokou jeskyni plnou kamene."])
        case .spring: return LocalizedText(values: [
            .en: "Scouts found a healing spring — the whole colony drinks well.",
            .cs: "Zvědové našli léčivý pramen — celé osadě se ulevilo."])
        case .treasure: return LocalizedText(values: [
            .en: "Scouts unearthed a buried cache of goods.",
            .cs: "Zvědové vykopali zakopanou skrýš plnou zásob."])
        case .shrine: return LocalizedText(values: [
            .en: "Scouts found a forgotten shrine — the old gods still listen.",
            .cs: "Zvědové našli zapomenutou svatyni — staří bohové stále naslouchají."])
        case .wreck: return LocalizedText(values: [
            .en: "Scouts found a wrecked caravan, its timber still good.",
            .cs: "Zvědové našli vrak karavany — dřevo je pořád dobré."])
        case .orchard: return LocalizedText(values: [
            .en: "Scouts walked into an old orchard gone wild — and still bearing.",
            .cs: "Zvědové vešli do starého sadu, co zplaněl — a pořád rodí."])
        case .hermit: return LocalizedText(values: [
            .en: "Scouts found a hermit's hut. Somebody has been out here a long time.",
            .cs: "Zvědové našli poustevnu. Někdo tu žije už hodně dlouho."])
        case .watchtower: return LocalizedText(values: [
            .en: "Scouts found a ruined watchtower. From its top you would see the whole country.",
            .cs: "Zvědové našli rozbořenou strážní věž. Z jejího vrcholu je vidět celý kraj."])
        case .saltPan: return LocalizedText(values: [
            .en: "Scouts found a salt pan — white crust as far as the eye goes.",
            .cs: "Zvědové našli solisko — bílá kůra, kam oko dohlédne."])
        case .barrow: return LocalizedText(values: [
            .en: "Scouts found a burial mound. Whoever lies there was buried rich.",
            .cs: "Zvědové našli mohylu. Ať v ní leží kdokoli, pohřbili ho bohatě."])
        case .starfall: return LocalizedText(values: [
            .en: "Scouts found a crater with something at the bottom of it that fell from the sky.",
            .cs: "Zvědové našli kráter a na jeho dně něco, co spadlo z nebe."])
        }
    }

    /// A spring does not run dry, the old gods do not stop listening, an orchard
    /// bears again next year and a hermit is still there when you go back: these
    /// recover with time instead of being used up.
    public var isRenewable: Bool {
        switch self {
        case .spring, .shrine, .orchard, .hermit: return true
        case .ruins, .cave, .treasure, .wreck, .watchtower, .saltPan,
             .barrow, .starfall: return false
        }
    }

    /// How many working visits a finite place holds before it is picked clean.
    /// Ignored for renewable kinds.
    public var maxVisits: Int {
        switch self {
        case .treasure, .barrow, .starfall: return 1  // you empty it once
        case .ruins, .wreck, .watchtower: return 2
        case .cave, .saltPan: return 3                // a seam outlasts a rummage
        case .spring, .shrine, .orchard, .hermit: return .max
        }
    }

    /// In-game years a renewable place needs before it is worth walking to
    /// again. Ignored for finite kinds.
    public var cooldownYears: Int {
        switch self {
        case .spring: return 3
        case .shrine: return 4
        case .orchard: return 1     // it fruits every year, like anything else
        case .hermit: return 5      // he has only so much to teach
        default: return 0
        }
    }

    // MARK: - What working the place asks of the colony

    /// How many colonists the job wants. Kept small: a party is people the
    /// fields do without until they are back.
    public var partySize: Int {
        switch self {
        case .spring: return 2
        case .ruins, .treasure: return 2
        case .shrine, .wreck: return 3
        case .cave: return 3
        case .hermit, .watchtower: return 2
        case .orchard, .barrow: return 3
        case .saltPan: return 3
        case .starfall: return 4   // whatever it is, you do not go alone
        }
    }

    /// Ticks of work once the party arrives — a spring is a errand, a cave
    /// is a season of cutting.
    public var workTicks: Int {
        switch self {
        case .spring: return 3
        case .shrine: return 4
        case .watchtower: return 4
        case .orchard: return 5
        case .treasure: return 5
        case .hermit: return 6
        case .wreck: return 6
        case .barrow: return 7
        case .saltPan: return 8
        case .ruins: return 8
        case .cave: return 10
        case .starfall: return 12
        }
    }

    /// The trade the place rewards — the party is picked for it.
    public var wantedSkill: WorkKind {
        switch self {
        case .ruins: return .research
        case .cave, .saltPan, .starfall: return .mining
        case .wreck, .treasure: return .logging
        case .spring: return .healing
        case .shrine, .barrow: return .priest
        case .orchard: return .farming
        case .hermit: return .research
        case .watchtower: return .scouting
        }
    }

    /// Odds that working here hurts one of the party, and how hard.
    public var hazardChance: Double {
        switch self {
        case .cave: return 0.22
        case .starfall: return 0.26   // it is still hot, and it is not stone
        case .barrow: return 0.16     // a mound is a hole that wants to close
        case .watchtower: return 0.12 // the stair is four hundred years old
        case .ruins: return 0.08
        default: return 0
        }
    }

    public var hazardDamage: Double {
        switch self {
        case .starfall: return 24
        case .cave: return 18
        case .watchtower: return 16
        case .barrow: return 14
        case .ruins: return 10
        default: return 0
        }
    }

    /// The bare noun, for sentences the journal builds.
    public var plainName: LocalizedText {
        switch self {
        case .ruins: return LocalizedText(values: [.en: "ruins", .cs: "zříceniny"])
        case .cave: return LocalizedText(values: [.en: "deep cave", .cs: "jeskyně"])
        case .spring: return LocalizedText(values: [.en: "spring", .cs: "pramen"])
        case .treasure: return LocalizedText(values: [.en: "buried cache", .cs: "skrýš"])
        case .shrine: return LocalizedText(values: [.en: "old shrine", .cs: "svatyně"])
        case .wreck: return LocalizedText(values: [.en: "wrecked caravan", .cs: "vrak"])
        case .orchard: return LocalizedText(values: [.en: "wild orchard", .cs: "zplanělý sad"])
        case .hermit: return LocalizedText(values: [.en: "hermit's hut", .cs: "poustevna"])
        case .watchtower: return LocalizedText(values: [.en: "watchtower", .cs: "strážní věž"])
        case .saltPan: return LocalizedText(values: [.en: "salt pan", .cs: "solisko"])
        case .barrow: return LocalizedText(values: [.en: "burial mound", .cs: "mohyla"])
        case .starfall: return LocalizedText(values: [.en: "fallen star", .cs: "spadlá hvězda"])
        }
    }

    /// Czech needs the dative for "set out for the …", and a lookup table beats
    /// a sentence that reads like a machine wrote it.
    public var plainNameDative: String {
        switch self {
        case .ruins: return "zříceninám"
        case .cave: return "jeskyni"
        case .spring: return "prameni"
        case .treasure: return "skrýši"
        case .shrine: return "svatyni"
        case .wreck: return "vraku"
        case .orchard: return "zplanělému sadu"
        case .hermit: return "poustevně"
        case .watchtower: return "strážní věži"
        case .saltPan: return "solisku"
        case .barrow: return "mohyle"
        case .starfall: return "spadlé hvězdě"
        }
    }
}

/// A point of interest and everything the colony has done with it. `visits`
/// and `lastVisitTick` are live state written only by `LocalPOIEngine`.
public struct LocalPOI: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let kind: LocalPOIKind
    public let position: LocalPoint
    public var discovered: Bool
    /// How many times the colony has worked this place.
    public var visits: Int
    /// The tick of the last visit — the clock a renewable place rests against.
    public var lastVisitTick: Int?

    public init(id: Int, kind: LocalPOIKind, position: LocalPoint, discovered: Bool = false,
                visits: Int = 0, lastVisitTick: Int? = nil) {
        self.id = id
        self.kind = kind
        self.position = position
        self.discovered = discovered
        self.visits = visits
        self.lastVisitTick = lastVisitTick
    }

    /// A finite place that has given up everything it had.
    public var isExhausted: Bool {
        !kind.isRenewable && visits >= kind.maxVisits
    }

    /// Ticks until a renewable place is worth visiting again — 0 when it is
    /// ready now, and always 0 for finite kinds.
    public func ticksUntilReady(tick: Int, ticksPerYear: Int) -> Int {
        guard kind.isRenewable, let last = lastVisitTick else { return 0 }
        let cooldown = kind.cooldownYears * max(1, ticksPerYear)
        return max(0, last + cooldown - tick)
    }

    /// Whether the colony can work this place right now.
    public func isWorkable(tick: Int, ticksPerYear: Int) -> Bool {
        discovered && !isExhausted && ticksUntilReady(tick: tick, ticksPerYear: ticksPerYear) == 0
    }

    // MARK: - Codable (resilient: visit state was added after the first saves)

    private enum CodingKeys: String, CodingKey {
        case id, kind, position, discovered, visits, lastVisitTick
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        kind = try c.decode(LocalPOIKind.self, forKey: .kind)
        position = try c.decode(LocalPoint.self, forKey: .position)
        discovered = try c.decode(Bool.self, forKey: .discovered)
        visits = try c.decodeIfPresent(Int.self, forKey: .visits) ?? 0
        lastVisitTick = try c.decodeIfPresent(Int.self, forKey: .lastVisitTick)
    }
}

/// The sine-curve river that crosses a settlement's map. Purely visual, but it
/// shapes where deposits can generate (never on the water).
public struct RiverShape: Codable, Sendable, Equatable {
    public var baseY: Double       // 0…1
    public var amplitude: Double   // 0…1
    public var phase: Double       // radians

    public init(baseY: Double, amplitude: Double, phase: Double) {
        self.baseY = baseY
        self.amplitude = amplitude
        self.phase = phase
    }

    /// The river's y at a given x (both normalised 0…1).
    public func y(atX x: Double) -> Double {
        baseY + sin(x * 6.283185 + phase) * amplitude
    }
}

/// The wild animals sharing a settlement's map: a deer herd that hunters cull
/// for food and predators that pressure the colony. Live simulation state.
public struct WildlifeState: Codable, Sendable, Equatable {
    /// Current head of game.
    public var deerHerd: Double
    /// The land's carrying capacity for the herd.
    public var deerCapacity: Double
    /// How dangerous the predators are right now (0…100) — drives attack rolls.
    public var predatorPressure: Double
    /// The wild as *entities* — a pawn-like `Animal` per head (life, body parts,
    /// conditions). The emerging layer that will take over from the abstract
    /// `deerHerd` count above. Old saves have none; they decode to empty.
    public var animals: [Animal]
    /// Whether this wild is made of animals. Not the same question as
    /// `animals.isEmpty`: a valley whose every beast has died is empty too, and
    /// falling back to the abstract herd there let a dead valley go on feeding
    /// its hunters exactly as before.
    public var usesEntities: Bool

    public init(deerHerd: Double = 40, deerCapacity: Double = 80,
                predatorPressure: Double = 10, animals: [Animal] = [],
                usesEntities: Bool = false) {
        self.deerHerd = deerHerd
        self.deerCapacity = deerCapacity
        self.predatorPressure = predatorPressure
        self.animals = animals
        self.usesEntities = usesEntities || !animals.isEmpty
    }

    // Resilient decode: `animals` postdates the abstract herd, so older saves
    // lack it — default to none rather than failing the settlement load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deerHerd = try c.decodeIfPresent(Double.self, forKey: .deerHerd) ?? 40
        deerCapacity = try c.decodeIfPresent(Double.self, forKey: .deerCapacity) ?? 80
        predatorPressure = try c.decodeIfPresent(Double.self, forKey: .predatorPressure) ?? 10
        animals = try c.decodeIfPresent([Animal].self, forKey: .animals) ?? []
        usesEntities = try c.decodeIfPresent(Bool.self, forKey: .usesEntities) ?? !animals.isEmpty
    }

    /// Prey the land can carry, as a head count — the entity counterpart of
    /// `deerCapacity`, which is measured in the older abstract units.
    public var preyCapacity: Int { Int(max(0, deerCapacity / 4)) }

    /// The game actually alive on this map right now.
    public var preyCount: Int { animals.count { !$0.species.isPredator } }

    /// How well-stocked the wild is (0…1) — hunting yield scales with this.
    ///
    /// Reads the **real animals** wherever there are any. That is the whole
    /// point of them: a valley whose deer froze to death over a hard winter
    /// should stop feeding its hunters, and while this was only
    /// `deerHerd / deerCapacity` it went on feeding them exactly as before —
    /// the beasts could all die and the larder would never notice. Saves that
    /// predate the entities fall back to the abstract number.
    public var herdFraction: Double {
        if usesEntities, preyCapacity > 0 {
            return min(1, Double(preyCount) / Double(preyCapacity))
        }
        return abstractHerdFraction
    }

    /// The old number on its own, without the animals. Used where the two must
    /// not chase each other — the cull that keeps the entities in step with it.
    public var abstractHerdFraction: Double {
        deerCapacity > 0 ? min(1, deerHerd / deerCapacity) : 0
    }
}

/// The living outdoor map of a single settlement: the river, harvestable
/// deposits, points of interest, wildlife and the fog of war. Generated
/// deterministically from `(mapSeed, regionID)`, then evolved as live state
/// (deposits deplete, scouts reveal fog, POIs get discovered, herds move).
///
/// Distinct from `ColonyMap`, which is the built-structures tile grid; this is
/// the surrounding wilderness the civilisation lives in.
public struct LocalMap: Codable, Sendable, Equatable {
    /// Fog-of-war grid resolution.
    public static let gridColumns = 40
    public static let gridRows = 25

    public var river: RiverShape
    public var nodes: [ResourceNode]
    public var pois: [LocalPOI]
    public var wildlife: WildlifeState
    /// Indices (`row * gridColumns + column`) of revealed fog cells.
    public var exploredCells: Set<Int>
    /// The biome this settlement sits in — drives ground cover and scenery.
    public var biomeID: String
    /// Seed for the ground-cover tiling (see `LocalTerrain`). Tiles are computed
    /// on demand rather than stored, so saves stay small.
    public var terrainSeed: UInt64
    /// Decorative landscape features, placed by the seed.
    public var scenery: [SceneryProp]
    /// The wood as *trees* — individual things that grow for years and are gone
    /// when felled, standing on the ground the forest deposits claim. The
    /// abstract nodes still drive the economy; these are the layer taking it
    /// over. Old saves have none and decode to empty.
    public var trees: [Tree]
    /// The stone as *outcrops* — bodies with ore in them that do not grow back.
    public var rocks: [Rock]
    /// Whether this map's wood and stone are made of *things*.
    ///
    /// `!trees.isEmpty` looked like the same question and is not: a map whose
    /// last tree has just been felled has no trees either, and treating that as
    /// "no entity layer" made the forest deposit keep the value it held before
    /// the final trunk came down — a wood logged flat that still read as
    /// half-full. Maps generated before the entity layer decode this as false
    /// and keep the old arithmetic for ever.
    public var usesEntityLand: Bool
    /// The sea, on the maps that have one. Nil inland — most country has none,
    /// and a save written before coasts existed decodes to nil.
    public var shore: ShoreShape?
    /// The mountain, where there is one: solid rock in blocks, dug into at the
    /// face. Empty on most country, and on every map made before there were
    /// mountains to dig.
    public var stone: StoneField
    /// Goods lying where the work happened, waiting to be carried in.
    public var piles: [HaulPile]
    /// Outsiders presently on this ground — traders, envoys, refugees.
    public var visitors: [Visitor]
    /// Scout-steps walked so far — one per scout per reveal step. How far the
    /// frontier has moved is a function of *work done*, never of the world
    /// clock: a colony founded in year 200 charts its own valley from scratch
    /// exactly like the first one did.
    public var scoutProgress: Double
    /// Where the player has pointed the scouts, if anywhere. Set by tapping
    /// the fog; cleared by `reveal` once that ground is charted.
    public var scoutFocus: LocalPoint?

    /// The ground cover of a grid cell, derived from the seed and the biome.
    public func cover(column: Int, row: Int) -> GroundCover {
        LocalTerrain.cover(terrainSeed: terrainSeed, biomeID: biomeID, column: column, row: row)
    }

    public init(
        river: RiverShape,
        nodes: [ResourceNode],
        pois: [LocalPOI],
        wildlife: WildlifeState = WildlifeState(),
        exploredCells: Set<Int> = [],
        biomeID: String = "plains",
        terrainSeed: UInt64 = 0,
        scenery: [SceneryProp] = [],
        trees: [Tree] = [],
        rocks: [Rock] = [],
        usesEntityLand: Bool = false,
        shore: ShoreShape? = nil,
        stone: StoneField = StoneField(),
        piles: [HaulPile] = [],
        visitors: [Visitor] = [],
        scoutProgress: Double = 0,
        scoutFocus: LocalPoint? = nil
    ) {
        self.stone = stone
        self.piles = piles
        self.visitors = visitors
        self.river = river
        self.nodes = nodes
        self.pois = pois
        self.wildlife = wildlife
        self.exploredCells = exploredCells
        self.biomeID = biomeID
        self.terrainSeed = terrainSeed
        self.scenery = scenery
        self.trees = trees
        self.rocks = rocks
        self.usesEntityLand = usesEntityLand
        self.shore = shore
        self.scoutProgress = scoutProgress
        self.scoutFocus = scoutFocus
    }

    // MARK: - Codable (resilient: fields were added incrementally)

    private enum CodingKeys: String, CodingKey {
        case river, nodes, pois, wildlife, exploredCells, biomeID, terrainSeed, scenery
        case trees, rocks, shore, usesEntityLand, stone, piles, visitors
        case scoutProgress, scoutFocus
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        river = try c.decode(RiverShape.self, forKey: .river)
        nodes = try c.decode([ResourceNode].self, forKey: .nodes)
        pois = try c.decode([LocalPOI].self, forKey: .pois)
        wildlife = try c.decodeIfPresent(WildlifeState.self, forKey: .wildlife) ?? WildlifeState()
        exploredCells = try c.decodeIfPresent(Set<Int>.self, forKey: .exploredCells) ?? []
        biomeID = try c.decodeIfPresent(String.self, forKey: .biomeID) ?? "plains"
        terrainSeed = try c.decodeIfPresent(UInt64.self, forKey: .terrainSeed) ?? 0
        scenery = try c.decodeIfPresent([SceneryProp].self, forKey: .scenery) ?? []
        trees = try c.decodeIfPresent([Tree].self, forKey: .trees) ?? []
        rocks = try c.decodeIfPresent([Rock].self, forKey: .rocks) ?? []
        usesEntityLand = try c.decodeIfPresent(Bool.self, forKey: .usesEntityLand) ?? false
        shore = try c.decodeIfPresent(ShoreShape.self, forKey: .shore)
        stone = try c.decodeIfPresent(StoneField.self, forKey: .stone) ?? StoneField()
        piles = try c.decodeIfPresent([HaulPile].self, forKey: .piles) ?? []
        visitors = try c.decodeIfPresent([Visitor].self, forKey: .visitors) ?? []
        scoutProgress = try c.decodeIfPresent(Double.self, forKey: .scoutProgress) ?? 0
        scoutFocus = try c.decodeIfPresent(LocalPoint.self, forKey: .scoutFocus)
    }

    /// Fraction of the map revealed (0…1).
    public var exploredFraction: Double {
        Double(exploredCells.count) / Double(LocalMap.gridColumns * LocalMap.gridRows)
    }

    /// Whether the cell containing a normalised point has been revealed.
    public func isExplored(_ point: LocalPoint) -> Bool {
        exploredCells.contains(Self.cellIndex(point))
    }

    /// The grid cell index a normalised point falls in.
    public static func cellIndex(_ point: LocalPoint) -> Int {
        let col = min(gridColumns - 1, max(0, Int(point.x * Double(gridColumns))))
        let row = min(gridRows - 1, max(0, Int(point.y * Double(gridRows))))
        return row * gridColumns + col
    }

    /// Reveals every cell whose centre lies within `radius` (normalised) of a
    /// point, and marks any POI thereby uncovered as discovered.
    public mutating func reveal(around point: LocalPoint, radius: Double) {
        let r2 = radius * radius
        for row in 0..<Self.gridRows {
            for col in 0..<Self.gridColumns {
                let cx = (Double(col) + 0.5) / Double(Self.gridColumns)
                let cy = (Double(row) + 0.5) / Double(Self.gridRows)
                let dx = cx - point.x
                let dy = cy - point.y
                if dx * dx + dy * dy <= r2 {
                    exploredCells.insert(row * Self.gridColumns + col)
                }
            }
        }
        for i in pois.indices where !pois[i].discovered && isExplored(pois[i].position) {
            pois[i].discovered = true
        }
        // Scouts sent somewhere specific stop being sent once they've been:
        // the order is finished, not standing.
        if let focus = scoutFocus, isExplored(focus) {
            scoutFocus = nil
        }
    }

    /// Whether any ground is left to chart. Drives the "the fog will not move"
    /// warning and the scouting floor in `LaborEngine`.
    public var isFullyCharted: Bool {
        exploredCells.count >= LocalMap.gridColumns * LocalMap.gridRows
    }

    /// The centre of a random still-dark cell lying within `reach` of the
    /// heart, or `nil` when everything in range is already known.
    ///
    /// Scouts used to walk a random *bearing*, which meant most outings
    /// re-trod ground the colony already knew and the fog crawled — the map
    /// looked static because, most steps, it was. Walking at the dark instead
    /// makes every outing count and makes a valley finishable: with a random
    /// bearing the four corners were a coupon-collector's tail that in practice
    /// never came up.
    ///
    /// Two passes and a single RNG draw, so it stays cheap on offline catch-up
    /// and deterministic for a seed.
    public func unchartedCell(within reach: Double, rng: inout SeededRNG) -> LocalPoint? {
        let reach2 = reach * reach
        func isCandidate(column: Int, row: Int) -> Bool {
            guard !exploredCells.contains(row * Self.gridColumns + column) else { return false }
            let dx = (Double(column) + 0.5) / Double(Self.gridColumns) - 0.5
            let dy = (Double(row) + 0.5) / Double(Self.gridRows) - 0.5
            return dx * dx + dy * dy <= reach2
        }

        var count = 0
        for row in 0..<Self.gridRows {
            for col in 0..<Self.gridColumns where isCandidate(column: col, row: row) {
                count += 1
            }
        }
        guard count > 0 else { return nil }

        var pick = min(count - 1, Int(rng.nextUnit() * Double(count)))
        for row in 0..<Self.gridRows {
            for col in 0..<Self.gridColumns where isCandidate(column: col, row: row) {
                if pick == 0 {
                    return LocalPoint(x: (Double(col) + 0.5) / Double(Self.gridColumns),
                                      y: (Double(row) + 0.5) / Double(Self.gridRows))
                }
                pick -= 1
            }
        }
        return nil
    }
}
