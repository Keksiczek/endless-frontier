import Foundation

/// **The ground keeps giving up rock, because the seam is still down there.**
///
/// The wood had `FloraEngine.reseeded` and the rock had nothing. An outcrop is
/// finite by nature — you break it up and it is gone — so a valley's stone,
/// clay and ore were laid down once at generation and could only ever run
/// down. Measured on Keks's save, 113 years in:
///
/// ```
/// rocks 9, every one amount 0
/// nodes: stone 0/222  iron_ore 0/181  clay 0/135   (fields full, herbs 0.3/246)
/// stone (the massif): solid [], usesBlocks true      ← a plains valley has no mountain
/// ```
///
/// So the colony's entire mineral supply was nine boulders, all broken, for
/// ever. No stone, no clay, no ore, and therefore no brick, no iron and nothing
/// downstream of either — the same absorbing state the wood was in, minus even
/// the seed blowing over the valley wall.
///
/// A quarry does not grow back. What *does* happen, over the decades a colony
/// lives, is that the ground opens: frost splits a face, a wet spring slips a
/// bank, a stream cuts down to the clay again. So new outcrops **surface at the
/// deposits that are already there** — the node is the geology, and it says
/// what is under this particular valley. That makes the supply map-specific and
/// biome-specific for free, which is what it has to be: a plains valley is not
/// a mountain, and `resource_affinity.materials` is the number the content
/// already carries to say so (plains 0.8).
///
/// The **rate** is the limit, not a total. That is the difference between a
/// colony that must eventually die and one that is merely constrained — and it
/// is the honest reading of a real quarry, which is worked for centuries and
/// limited by how fast men can break rock, not by running out of hill.
///
/// Deterministic from `(mapSeed, tick)` per rule 3. Nothing here reads a clock.
public enum MineralEngine {

    /// How often the ground is asked whether anything new has come up.
    ///
    /// The same cadence the wood is seeded on, and for the same reason: this
    /// scans the outcrops, and a catch-up replays tens of thousands of ticks
    /// (rule 4).
    public static let interval = 50

    /// The most live outcrops one deposit will carry at once.
    ///
    /// The generator lays two to four per node, so this is a little above what
    /// a fresh valley looks like — a worked deposit ends up *more* broken open
    /// than an untouched one, which is what a quarry is.
    public static let mostOutcropsPerNode = 5

    /// What a newly surfaced outcrop holds, as a share of its deposit's
    /// capacity.
    ///
    /// Sized against the demand it has to answer. A miner pulls
    /// `ResourceLoop.harvestPerWorker` (0.45) a tick and a colony of a hundred
    /// runs seven of them, spread across whichever kinds this valley holds — so
    /// about one unit a tick per kind. At a fifth of a 200-unit deposit every
    /// fifty ticks that is 0.8 a tick before the biome is applied: a rich
    /// country keeps up with its miners and a poor one does not, which is the
    /// point of settling one rather than the other.
    public static let surfacedShare = 0.2

    /// How much of the biome's materials affinity feeds through to the rate.
    ///
    /// Straight through. A plains valley at 0.8 surfaces four fifths as fast as
    /// a balanced one and a mountain rather more, and that difference *is* the
    /// reason to care where you settled. Clamped so no content value can stop
    /// the ground opening altogether — a valley that surfaces nothing at all is
    /// the state this engine exists to make impossible.
    static let leanestGround = 0.35

    /// How close two deposits' remaining shares have to be to count as equally
    /// worked out. A twentieth: three deposits all standing at nothing are the
    /// same problem, and so are three standing at a tenth.
    static let tiedWithin = 0.05

    /// One pass of the ground opening, for a single settlement's valley.
    ///
    /// Returns the map unchanged on any tick that is not a pass, so callers can
    /// hand it every tick without a guard of their own.
    public static func advanceOneTick(
        _ map: LocalMap, biome: BiomeDefinition?, mapSeed: UInt64, tick: Int
    ) -> LocalMap {
        guard tick % interval == 0 else { return map }
        return surfaced(map, biome: biome, mapSeed: mapSeed, tick: tick)
    }

    /// Opens the ground where a deposit is thinnest on the surface.
    ///
    /// One outcrop a pass, at the **neediest** deposit — the one with the least
    /// left in it — so a valley being worked for clay opens clay rather than
    /// spreading its luck evenly over three seams the colony is not touching.
    public static func surfaced(
        _ map: LocalMap, biome: BiomeDefinition?, mapSeed: UInt64, tick: Int
    ) -> LocalMap {
        guard map.usesEntityLand, !map.nodes.isEmpty else { return map }
        let richness = max(leanestGround, biome?.resourceAffinity[.materials] ?? 1)
        var rng = SeededRNG(seed: mapSeed &* 0x9E37_79B9_7F4A_7C15
                            &+ UInt64(bitPattern: Int64(tick)) &* 0xC2B2_AE3D_27D4_EB4F
                            ^ 0x0DE_C0DE)
        // Lean ground opens on some passes and not others, rather than opening
        // a smaller rock every time: a boulder is a boulder.
        guard rng.nextUnit() < min(1, richness) else { return map }

        // Which deposit is worth opening. Only the mineral kinds — a field and
        // a herb patch are not rock, and the wood has its own engine.
        // **Every worked-out deposit gets its turn, not just the first one.**
        //
        // This took the strict minimum, and a valley whose stone, iron and clay
        // are *all* at zero has three deposits tied on nothing — so the tie
        // went to whichever sat earliest in the array, every pass, for ever.
        // Measured: over forty years the stone went 111 → 336 on the shelf and
        // the iron 193 → 295, while the **clay stood at three the whole time**,
        // one short of the four `fire_bricks` wants. A colony that can never
        // fire a brick is a colony that can never raise anything a brick is
        // named in. Rule 23's cousin: a tie-break nobody chose is a policy.
        var candidates: [(index: Int, left: Double)] = []
        for (index, node) in map.nodes.enumerated() {
            guard isMineral(node.kind), node.capacity > 0 else { continue }
            let live = map.rocks.filter {
                $0.kind.deposit == node.kind
                    && FloraEngine.within($0.position, node.position, FloraEngine.claimRadius)
                    && !$0.isSpent
            }
            guard live.count < mostOutcropsPerNode else { continue }
            candidates.append((index, live.reduce(0.0) { $0 + $1.amount } / node.capacity))
        }
        guard let thinnest = candidates.map(\.left).min() else { return map }
        // Anything within a whisker of the thinnest is equally worth opening;
        // which of them opens is the die's, so the ground does not favour an
        // array index.
        let tied = candidates.filter { $0.left <= thinnest + tiedWithin }
        guard !tied.isEmpty else { return map }
        let pick = tied[Int(rng.nextUnit() * Double(tied.count)) % tied.count]
        let node = map.nodes[pick.index]

        // Somewhere on the deposit, not on top of anything standing.
        let kinds = FloraFactory.rockKinds(for: node.kind)
        let kind = kinds[Int(rng.nextUnit() * Double(kinds.count)) % kinds.count]
        let angle = rng.nextUnit() * 2 * .pi
        let radius = FloraEngine.claimRadius * (rng.nextUnit() * rng.nextUnit()).squareRoot()
        let at = LocalPoint(
            x: min(0.97, max(0.03, node.position.x + cos(angle) * radius)),
            y: min(0.97, max(0.03, node.position.y + sin(angle) * radius)))
        guard FloraEngine.isClearGround(map, at) else { return map }

        // What came up. A little either side of the share, so two outcrops on
        // the same seam are not twins.
        let held = node.capacity * surfacedShare * (0.75 + rng.nextUnit() * 0.5)
        var updated = map
        let nextID = (updated.rocks.map(\.id).max() ?? -1) + 1
        updated.rocks.append(Rock(id: nextID, kind: kind, position: at,
                                  amount: held, capacity: held))
        // The deposit now reads what is standing on it (`FloraEngine.syncDeposits`
        // does this for the whole map each tick, but a caller that only surfaces
        // rock should not have to know that).
        updated = FloraEngine.syncDeposits(updated)
        return updated
    }

    /// Whether a deposit is rock the ground can open again. The wood answers to
    /// `FloraEngine`, and a field and a herb patch are not broken out of
    /// anything.
    static func isMineral(_ kind: LocalResourceKind) -> Bool {
        switch kind {
        case .stone, .ironOre, .clay, .coal, .oilSeep: return true
        case .forest, .field, .herbs: return false
        }
    }
}
