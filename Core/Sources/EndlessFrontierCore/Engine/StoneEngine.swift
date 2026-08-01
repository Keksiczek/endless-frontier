import Foundation

/// Digging into the mountain.
///
/// A `StoneField` is worked one block at a time, and only at the face — a block
/// with open ground beside it. Work banks *in the block*, the way it banks in a
/// half-felled tree, so a corridor stops and starts as miners come and go and
/// nothing is lost. When a block's work is done it is gone: the ground under it
/// opens, the blocks behind it become the new face, and its stone goes into the
/// colony's hands.
///
/// Rock does not grow back. That is the point of it: a mountain is a finite
/// thing, and a colony that has eaten its own hillside has to go and find
/// another one.
public enum StoneEngine {

    /// Work one miner does on a block per tick. A block is a chunk of hillside,
    /// so several ticks of one pick, more for granite.
    public static let workPerMiner: Double = 0.34
    /// What a block gives up when it comes out, in deposit units.
    public static let yieldPerBlock: Double = 14
    /// …and how many whole raw items — the concrete goods a forge and a kiln
    /// actually ask for.
    public static let itemsPerBlock: Int = 3

    /// Puts `miners` on the face for one tick.
    ///
    /// Miners are spread across separate blocks rather than piled onto one, so
    /// a big crew opens a wide gallery instead of a single tunnel — and so that
    /// what you watch on the canvas is a row of people at a rock face.
    @discardableResult
    public static func mine(
        _ field: StoneField, miners: Int
    ) -> (field: StoneField, yield: [LocalResourceKind: Double], broken: [Int]) {
        guard miners > 0, !field.isEmpty else { return (field, [:], []) }
        let faces = field.faces()
        guard !faces.isEmpty else { return (field, [:], []) }

        var updated = field
        var yield: [LocalResourceKind: Double] = [:]
        var broken: [Int] = []
        for index in faces.prefix(miners) {
            let kind = field.kind(of: index)
            let progress = (updated.cut[index] ?? 0) + workPerMiner / kind.hardness
            if progress >= 1 {
                updated.solid.remove(index)
                updated.cut[index] = nil
                yield[kind.deposit, default: 0] += yieldPerBlock
                broken.append(index)
            } else {
                updated.cut[index] = progress
            }
        }
        // Work banked in a block that is no longer a face — the mountain moved
        // on around it — is not lost, but it is not kept for ever either.
        return (updated, yield, broken)
    }

    /// The blocks a colony can currently get at, nearest to a point first.
    /// What the job board hands out, so miners walk to the near end of the
    /// working rather than across the massif.
    public static func workableBlocks(
        _ field: StoneField, from: LocalPoint, charted: (LocalPoint) -> Bool
    ) -> [Int] {
        field.faces()
            .filter { charted(StoneField.centre(of: $0)) }
            .sorted { a, b in
                let pa = StoneField.centre(of: a), pb = StoneField.centre(of: b)
                let da = (pa.x - from.x) * (pa.x - from.x) + (pa.y - from.y) * (pa.y - from.y)
                let db = (pb.x - from.x) * (pb.x - from.x) + (pb.y - from.y) * (pb.y - from.y)
                return da == db ? a < b : da < db
            }
    }

    // MARK: - Raising a mountain

    /// How much of the map a biome's rock covers, and how solid it is.
    static func massifWeight(for biomeID: String) -> Double {
        switch biomeID {
        case "mountains": return 1.0
        case "tundra":    return 0.55
        case "desert":    return 0.45
        case "forest":    return 0.22
        case "coast":     return 0.20
        default:          return 0.16   // plains & homeland: an outcrop, if that
        }
    }

    /// What is *in* a country's rock, as shares of a block.
    ///
    /// Mirrors `LocalMapGenerator.depositMix`: the coast has clay beds and no
    /// iron, the mountains are the ore country. A cliff that yielded the same
    /// seams everywhere made a coastal colony self-sufficient in iron and undid
    /// the reason to have a world map at all.
    static func seamMix(for biomeID: String) -> (iron: Double, clay: Double) {
        switch biomeID {
        case "mountains": return (0.24, 0.04)
        case "tundra":    return (0.16, 0.02)
        case "desert":    return (0.10, 0.00)
        case "forest":    return (0.08, 0.08)
        case "coast":     return (0.00, 0.26)
        default:          return (0.05, 0.14)   // plains & homeland
        }
    }

    /// The ground the colony's own buildings need, kept clear of rock. A massif
    /// grown over the build grid would wall a colony into its own founding site
    /// — the recurring shape of bug where a threshold and the thing meant to
    /// cross it never meet.
    /// Derived from the build grid's own reach rather than written down again:
    /// the town got wider twice, and a clearance left behind would have grown a
    /// massif straight over the new outer quarters.
    static var colonyClearance: Double { SettlementGeometry.cornerReach + 0.02 }

    /// Raises a massif against one edge of the map.
    ///
    /// The shape is a ridge line with a thickness that wanders, so a mountain
    /// has bays and spurs rather than being a rectangle. Nothing is placed
    /// within `colonyClearance` of the heart, and nothing in the river or the
    /// sea — a cliff standing in the water would be a lie about where the water
    /// is.
    public static func raise(
        biomeID: String, river: RiverShape, shore: ShoreShape?, rng: inout SeededRNG
    ) -> StoneField {
        let weight = massifWeight(for: biomeID)
        guard weight > 0.01 else { return StoneField() }
        // A minority of ordinary country simply has no crag in it at all,
        // which is what makes finding one worth something.
        if weight < 0.3, rng.nextUnit() > weight * 2 { return StoneField() }

        let seed = rng.next()
        // Which edge the high ground runs along, and how far in it reaches.
        let side = Int(rng.nextUnit() * 4) % 4
        let reach = (0.13 + rng.nextUnit() * 0.16) * (0.55 + weight * 0.75)
        let waviness = 0.35 + rng.nextUnit() * 0.5
        let phase = rng.nextUnit() * 6.283185
        let heart = SettlementGeometry.heart

        var solid: Set<Int> = []
        for row in 0..<LocalMap.gridRows {
            for col in 0..<LocalMap.gridColumns {
                let p = StoneField.centre(of: StoneField.index(column: col, row: row))
                // How far in from this map's edge the rock reaches here.
                let along: Double
                let depth: Double
                switch side {
                case 0: along = p.x; depth = p.y                        // north
                case 1: along = p.y; depth = 1 - p.x                    // east
                case 2: along = p.x; depth = 1 - p.y                    // south
                default: along = p.y; depth = p.x                       // west
                }
                let edge = reach * (1 + sin(along * 6.283185 + phase) * waviness * 0.6
                                      + sin(along * 15.1 + phase * 1.7) * waviness * 0.25)
                guard depth < edge else { continue }
                // Never over the town, never in the water.
                let dx = p.x - heart.x, dy = p.y - heart.y
                guard (dx * dx + dy * dy).squareRoot() > colonyClearance else { continue }
                if river.flows, abs(p.y - river.y(atX: p.x)) <= 0.05 { continue }
                if let shore, shore.distanceInland(p) < 0.03 { continue }
                solid.insert(StoneField.index(column: col, row: row))
            }
        }
        guard solid.count >= 4 else { return StoneField() }
        let seams = seamMix(for: biomeID)
        return StoneField(solid: solid, seed: seed,
                          ironShare: seams.iron, clayShare: seams.clay,
                          usesBlocks: true)
    }
}
