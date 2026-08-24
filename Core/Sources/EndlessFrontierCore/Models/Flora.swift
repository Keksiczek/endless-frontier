import Foundation

/// The land made of *things*, not of numbers.
///
/// A forest was a `ResourceNode` with an `amount` that went down when someone
/// worked it and crept back up in spring. Nobody ever felled a tree; a number
/// fell. This is the same move already made for the wild in `Animal`: a tree is
/// an object that stands somewhere, grows for years, and is *gone* when it comes
/// down — and a rock is a body with ore in it that is spent when the ore is out.
///
/// (The abstract nodes still drive the economy for now; these entities are the
/// layer that grows to take it over. See `docs/RIMWORLD_LAYER.md`.)

/// A kind of tree. Traits live on the species — a Flyweight, the role
/// `ThingDef` plays in RimWorld — so a `Tree` instance stays small enough to
/// have thousands of.
/// **What saves written before flora was data are carrying.**
///
/// Species used to be this enum with five hand-written tables hanging off it,
/// and a `Tree` stored the case. They are `flora.json` now (`FloraDefinition`),
/// so a ninth kind of tree is a JSON entry rather than Swift in six files —
/// but every colony already on disk has `"species": "oak"` and no numbers
/// beside it, and `Tree.init(from:)` has no registry to look them up in.
///
/// So these eight are **frozen**. Nothing is ever added here: no save can
/// contain a species that did not exist when it was written, so a new one has
/// nothing to migrate. This is a snapshot of history, not a second source of
/// truth — `flora.json` is the authority for every tree the game plants from
/// now on, and `ContentTests` holds the two in agreement for the eight that
/// appear in both.
enum LegacyTreeSpecies: String, CaseIterable {
    case pine, oak, birch, spruce, beech, willow, juniper, poplar

    var timber: Double {
        switch self {
        case .oak: return 32
        case .beech: return 30
        case .pine, .spruce: return 24
        case .poplar: return 18
        case .birch: return 16
        case .willow: return 14
        case .juniper: return 7
        }
    }

    var maturityTicks: Int {
        switch self {
        case .oak: return 4200
        case .beech: return 3800
        case .spruce: return 2600
        case .pine: return 2400
        case .juniper: return 1900
        case .birch: return 1400
        case .poplar: return 1300
        case .willow: return 1100
        }
    }

    var crown: FloraDefinition.Crown {
        switch self {
        case .pine, .spruce: return .conifer
        case .juniper: return .scrub
        case .poplar: return .column
        case .willow: return .weeping
        case .oak, .birch, .beech: return .broadleaf
        }
    }
}

/// One tree standing on the local map.
public struct Tree: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    /// Which kind of tree this is — a `FloraDefinition` id.
    public let species: String
    public let position: LocalPoint
    /// Age in world ticks.
    public var age: Int
    /// Axe-work done so far, 0…1. A tree half-chopped stays half-chopped: the
    /// work is banked in the tree, not in whoever swung the axe.
    public var chopped: Double

    // MARK: - What this tree is, carried on the tree

    /// Ticks from sapling to full grown, and timber a full-grown one yields.
    ///
    /// **Copied onto the tree when it is planted**, rather than looked up.
    /// `growth` and `timberYield` are read in the middle of felling, sorting
    /// and drawing — dozens of times a tick and thousands of times a frame —
    /// and they have always been pure functions of the tree. Handing them a
    /// registry would mean threading one through `FloraEngine.fell`, every
    /// test that stands a tree up, and the canvas. A tree knows how big it
    /// gets, the way an animal knows how big it gets.
    public let maturityTicks: Int
    public let timber: Double
    /// The silhouette it is drawn with, so the canvas needs no registry either.
    public let crown: FloraDefinition.Crown

    /// A tree named rather than described.
    ///
    /// The numbers fall back to the **frozen** table (`LegacyTreeSpecies`) for
    /// the eight kinds that predate `flora.json`, so a call site that names one
    /// of them gets exactly what it always got. Everything the game plants goes
    /// through `init(id:definition:position:)` and reads the book — a species
    /// the content added has no entry here and could not be named this way
    /// without silently coming out twenty timber and two thousand ticks.
    public init(id: Int, species: String, position: LocalPoint,
                age: Int = 0, chopped: Double = 0,
                maturityTicks: Int? = nil, timber: Double? = nil,
                crown: FloraDefinition.Crown? = nil) {
        let legacy = LegacyTreeSpecies(rawValue: species)
        self.id = id
        self.species = species
        self.position = position
        self.age = age
        self.chopped = chopped
        self.maturityTicks = max(1, maturityTicks ?? legacy?.maturityTicks ?? 2000)
        self.timber = timber ?? legacy?.timber ?? 20
        self.crown = crown ?? legacy?.crown ?? .broadleaf
    }

    /// One of a kind the content describes.
    public init(id: Int, definition: FloraDefinition, position: LocalPoint,
                age: Int = 0, chopped: Double = 0) {
        self.init(id: id, species: definition.id, position: position,
                  age: age, chopped: chopped,
                  maturityTicks: definition.maturityTicks,
                  timber: definition.timber, crown: definition.crown)
    }

    private enum CodingKeys: String, CodingKey {
        case id, species, position, age, chopped, maturityTicks, timber, crown
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        species = try c.decode(String.self, forKey: .species)
        position = try c.decode(LocalPoint.self, forKey: .position)
        age = try c.decodeIfPresent(Int.self, forKey: .age) ?? 0
        chopped = try c.decodeIfPresent(Double.self, forKey: .chopped) ?? 0
        // A tree planted before species were data carries only its name. The
        // frozen table is what it meant when it was written — see
        // `LegacyTreeSpecies`.
        let legacy = LegacyTreeSpecies(rawValue: species)
        maturityTicks = max(1, try c.decodeIfPresent(Int.self, forKey: .maturityTicks)
                            ?? legacy?.maturityTicks ?? 2000)
        timber = try c.decodeIfPresent(Double.self, forKey: .timber)
            ?? legacy?.timber ?? 20
        crown = try c.decodeIfPresent(FloraDefinition.Crown.self, forKey: .crown)
            ?? legacy?.crown ?? .broadleaf
    }

    /// 0…1, sapling to full grown.
    public var growth: Double {
        let span = Double(max(1, maturityTicks))
        return min(1, Double(max(0, age)) / span)
    }

    public var isMature: Bool { growth >= 1 }

    /// What felling it right now would yield — a sapling is barely worth the axe.
    public var timberYield: Double { timber * growth }
}

/// What a rock is made of, and therefore what breaking it gives up.
public enum RockKind: String, Codable, Sendable, CaseIterable {
    case granite, limestone, ironSeam = "iron_seam", clayBank = "clay_bank"
    /// Black rock that burns — the seam a locomotive is downstream of.
    case coalSeam = "coal_seam"
    /// Where the oil comes up on its own. Not really rock at all, and
    /// drawn dark and wet rather than broken.
    case oilSeep = "oil_seep"

    /// The deposit kind this rock reads as for the harvesting economy.
    public var deposit: LocalResourceKind {
        switch self {
        case .granite, .limestone: return .stone
        case .ironSeam: return .ironOre
        case .coalSeam: return .coal
        case .oilSeep: return .oilSeep
        case .clayBank: return .clay
        }
    }

    /// How stubborn it is — work needed per unit taken out.
    public var hardness: Double {
        switch self {
        case .granite: return 2.2
        case .ironSeam: return 1.8
        case .limestone: return 1.3
        case .clayBank: return 0.8
        // Coal is softer than the rock around it — that is why a seam is worth
        // following. Oil takes no breaking at all; the work is catching it.
        case .coalSeam: return 1.1
        case .oilSeep: return 0.6
        }
    }

    public var displayName: LocalizedText {
        switch self {
        case .granite: return LocalizedText(values: [.en: "Granite", .cs: "Žula"])
        case .limestone: return LocalizedText(values: [.en: "Limestone", .cs: "Vápenec"])
        case .ironSeam: return LocalizedText(values: [.en: "Iron seam", .cs: "Železná žíla"])
        case .clayBank: return LocalizedText(values: [.en: "Clay bank", .cs: "Hliniště"])
        case .coalSeam: return LocalizedText(values: [.en: "Coal seam", .cs: "Uhelná sloj"])
        case .oilSeep: return LocalizedText(values: [.en: "Oil seep", .cs: "Ropný vývěr"])
        }
    }
}

/// One outcrop on the local map. Unlike a tree it does not grow back: what is
/// quarried out is gone, which is what makes a rich seam worth defending and a
/// spent one worth leaving.
public struct Rock: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let kind: RockKind
    public let position: LocalPoint
    /// How much is still in it.
    public var amount: Double
    public let capacity: Double

    public init(id: Int, kind: RockKind, position: LocalPoint,
                amount: Double, capacity: Double) {
        self.id = id
        self.kind = kind
        self.position = position
        self.amount = amount
        self.capacity = capacity
    }

    public var isSpent: Bool { amount <= 0 }
    /// 0…1 — how much of it is left, for drawing it visibly eaten into.
    public var remaining: Double {
        capacity > 0 ? min(1, max(0, amount / capacity)) : 0
    }
}

/// Builds standing things deterministically — same seed, same wood, same stone.
public enum FloraFactory {
    /// A stand of trees around a point, thinning towards its edge so a wood has
    /// a dense heart and a ragged fringe rather than a hard circle.
    public static func stand(
        _ species: FloraDefinition, count: Int, around centre: LocalPoint,
        spread: Double, rng: inout SeededRNG
    ) -> [Tree] {
        (0..<max(0, count)).map { _ in
            let angle = rng.nextUnit() * 2 * .pi
            // Square-rooting the radius spreads points evenly over the disc
            // instead of piling them at the centre.
            let radius = spread * (rng.nextUnit() * rng.nextUnit()).squareRoot()
            let p = LocalPoint(x: min(0.97, max(0.03, centre.x + cos(angle) * radius)),
                               y: min(0.97, max(0.03, centre.y + sin(angle) * radius)))
            // A wood is not all one age: mostly grown, with saplings coming on.
            let maturity = 0.25 + rng.nextUnit() * 0.9
            let age = Int(Double(species.maturityTicks) * min(1.2, maturity))
            return Tree(id: 0, definition: species, position: p, age: age)
        }
    }

    /// The trees a fresh map stands up, placed on the ground the abstract forest
    /// deposits already claim, so the wood you see is the wood you work.
    ///
    /// Ids are assigned here in one sweep, so they stay stable and unique.
    public static func woods(
        around forests: [LocalPoint], biomeID: String,
        shore: ShoreShape? = nil, river: RiverShape? = nil,
        registry: GameDataRegistry,
        rng: inout SeededRNG
    ) -> [Tree] {
        let palette = species(for: biomeID, registry: registry)
        // A book with no trees in it stands up a bare valley rather than
        // crashing on a remainder. Loud in the one place it matters — the
        // content test holds `flora.json` and the biome list together — and
        // silent here, where the only caller with an empty book is a test
        // registry built by hand.
        guard !palette.isEmpty else { return [] }
        var trees: [Tree] = []

        /// Nothing grows in the sea, and nothing grows in the channel.
        func dry(_ p: LocalPoint) -> Bool {
            if let shore, shore.isWater(p) { return false }
            if let river, river.flows, abs(p.y - river.y(atX: p.x)) < 0.03 { return false }
            return true
        }

        for centre in forests {
            // A stand is **mixed**. One species per stand meant a valley was
            // three flat blocks of colour — all pine here, all oak there — and
            // no wood anywhere in it looked like a wood.
            let count = 11 + Int(rng.nextUnit() * 9)
            for _ in 0..<count {
                let kind = palette[Int(rng.nextUnit() * Double(palette.count)) % palette.count]
                trees += stand(kind, count: 1, around: centre, spread: 0.075, rng: &rng)
                    .filter { dry($0.position) }
            }
        }

        // …and the trees that grow where nobody marked a deposit.
        //
        // Every tree in the game stood inside a forest *resource node*, so a
        // valley the generator gave no forest to had **not one tree on it** —
        // and the plains, the coast and the tundra are exactly those valleys.
        // The wild wood is scattered over the whole map, thinner than a stand
        // and thinnest where the country is hard.
        let scatter = wildTreeCount(for: biomeID)
        for _ in 0..<scatter {
            let kind = palette[Int(rng.nextUnit() * Double(palette.count)) % palette.count]
            let anywhere = LocalPoint(x: 0.04 + rng.nextUnit() * 0.92,
                                      y: 0.04 + rng.nextUnit() * 0.92)
            guard dry(anywhere) else { continue }
            trees += stand(kind, count: 1, around: anywhere, spread: 0.02, rng: &rng)
                .filter { dry($0.position) }
        }

        return trees.enumerated().map { index, tree in
            Tree(id: index, species: tree.species, position: tree.position,
                 age: tree.age, chopped: tree.chopped)
        }
    }

    /// How many loose trees a given country grows outside its marked woods.
    public static func wildTreeCount(for biomeID: String) -> Int {
        switch biomeID {
        case "forest":    return 60
        case "plains":    return 26
        case "coast":     return 18
        // Not bare, but not a wood either: a fen grows in stands on the dry
        // hummocks and nothing at all between them.
        case "wetlands":  return 20
        case "mountains": return 14
        case "tundra":    return 12
        case "desert":    return 4
        default:          return 22
        }
    }

    /// Which trees this country grows.
    ///
    /// Read off `flora.json` rather than a `switch`, so a species added to the
    /// content grows somewhere on the day it ships. A biome the content names
    /// no tree for falls back to everything that will stand the cold: an empty
    /// palette is a valley with no wood in it, which is a content hole and not
    /// a design.
    public static func species(
        for biomeID: String, registry: GameDataRegistry
    ) -> [FloraDefinition] {
        let named = registry.flora(inBiome: biomeID)
        guard named.isEmpty else { return named }
        return registry.flora.values.sorted { $0.id < $1.id }
    }

    /// The outcrops a fresh map stands up, on the ground the stone, iron and
    /// clay deposits already claim.
    public static func outcrops(
        at deposits: [(kind: LocalResourceKind, position: LocalPoint, capacity: Double)],
        rng: inout SeededRNG
    ) -> [Rock] {
        var rocks: [Rock] = []
        for deposit in deposits {
            let kinds = rockKinds(for: deposit.kind)
            let count = 2 + Int(rng.nextUnit() * 3)
            for _ in 0..<count {
                let kind = kinds[Int(rng.nextUnit() * Double(kinds.count)) % kinds.count]
                let angle = rng.nextUnit() * 2 * .pi
                let radius = 0.05 * (rng.nextUnit() * rng.nextUnit()).squareRoot()
                let p = LocalPoint(
                    x: min(0.97, max(0.03, deposit.position.x + cos(angle) * radius)),
                    y: min(0.97, max(0.03, deposit.position.y + sin(angle) * radius)))
                // The outcrops share out the deposit they belong to.
                let share = deposit.capacity / Double(count) * (0.7 + rng.nextUnit() * 0.6)
                rocks.append(Rock(id: rocks.count, kind: kind, position: p,
                                  amount: share, capacity: share))
            }
        }
        return rocks.enumerated().map { index, rock in
            Rock(id: index, kind: rock.kind, position: rock.position,
                 amount: rock.amount, capacity: rock.capacity)
        }
    }

    static func rockKinds(for deposit: LocalResourceKind) -> [RockKind] {
        switch deposit {
        case .ironOre: return [.ironSeam]
        case .clay: return [.clayBank]
        case .coal: return [.coalSeam]
        case .oilSeep: return [.oilSeep]
        default: return [.granite, .limestone]
        }
    }
}
