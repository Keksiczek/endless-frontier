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

    /// The colonist work that harvests this deposit.
    public var work: WorkKind {
        switch self {
        case .field: return .farming
        case .forest: return .logging
        case .stone: return .mining
        case .herbs: return .foraging
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

/// A point of interest discovered by exploring the fog of war — ruins, a cave,
/// a spring, buried treasure, a forgotten shrine or a wrecked caravan.
/// Discovery grants a one-off reward and a journal line (see
/// `ResourceLoop.chartGround`) — finding something *feels* like finding it.
public enum LocalPOIKind: String, Codable, Sendable, CaseIterable {
    case ruins      // ancient knowledge
    case cave       // rich stone
    case spring     // healing waters
    case treasure   // a cache of goods
    case shrine     // the old gods still listen
    case wreck      // a caravan that never arrived

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
        }
    }
}

public struct LocalPOI: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let kind: LocalPOIKind
    public let position: LocalPoint
    public var discovered: Bool

    public init(id: Int, kind: LocalPOIKind, position: LocalPoint, discovered: Bool = false) {
        self.id = id
        self.kind = kind
        self.position = position
        self.discovered = discovered
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

    public init(deerHerd: Double = 40, deerCapacity: Double = 80, predatorPressure: Double = 10) {
        self.deerHerd = deerHerd
        self.deerCapacity = deerCapacity
        self.predatorPressure = predatorPressure
    }

    /// How well-stocked the herd is (0…1) — hunting yield scales with this.
    public var herdFraction: Double {
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
        scenery: [SceneryProp] = []
    ) {
        self.river = river
        self.nodes = nodes
        self.pois = pois
        self.wildlife = wildlife
        self.exploredCells = exploredCells
        self.biomeID = biomeID
        self.terrainSeed = terrainSeed
        self.scenery = scenery
    }

    // MARK: - Codable (resilient: fields were added incrementally)

    private enum CodingKeys: String, CodingKey {
        case river, nodes, pois, wildlife, exploredCells, biomeID, terrainSeed, scenery
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
    }
}
