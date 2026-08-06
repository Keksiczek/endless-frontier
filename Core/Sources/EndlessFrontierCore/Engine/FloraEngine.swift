import Foundation

/// The wood as something that grows and is felled, rather than a number that
/// dips and recovers.
///
/// Trees age every tick — growth is *derived* from age, so nothing has to be
/// recomputed or stored — and loggers' work is banked into the tree itself, so
/// a half-chopped oak stays half-chopped when the shift ends. What comes down
/// is gone; what is planted takes an oak's lifetime to replace, which is the
/// whole point of making a forest out of objects.
///
/// Deterministic and linear in the number of trees. The abstract `forest`
/// deposits still drive the economy; this is the layer taking it over.
public enum FloraEngine {

    /// Axe-work one logger lands on a tree in one tick.
    static let chopPerTick = 0.06
    /// Below this the wood is too thin to be worth working — loggers move on.
    static let minimumWorkableGrowth = 0.35

    /// Ages every tree by a tick. Cheap on purpose: growth is a function of
    /// age, so this is one increment per tree and no allocation when the wood
    /// is empty.
    public static func advanceOneTick(_ map: LocalMap, by ticks: Int = 1) -> LocalMap {
        guard !map.trees.isEmpty, ticks > 0 else { return map }
        var updated = map
        for i in updated.trees.indices {
            updated.trees[i].age += ticks
        }
        return updated
    }

    /// Puts `loggers` to the axe for one tick and returns the timber they
    /// brought down. Work goes into the biggest workable tree first — nobody
    /// fells a sapling while an oak is standing — and a tree that comes down is
    /// removed from the map.
    public static func fell(
        _ map: LocalMap, loggers: Int
    ) -> (map: LocalMap, timber: Double, felled: Int, stumps: [LocalPoint]) {
        guard loggers > 0, !map.trees.isEmpty else { return (map, 0, 0, []) }

        // The standing wood worth an axe, biggest first. Ties break on id so
        // the same world always fells the same tree.
        let workable = map.trees.indices
            .filter { map.trees[$0].growth >= minimumWorkableGrowth }
            .sorted {
                let a = map.trees[$0], b = map.trees[$1]
                if a.timberYield != b.timberYield { return a.timberYield > b.timberYield }
                return a.id < b.id
            }
        guard !workable.isEmpty else { return (map, 0, 0, []) }

        var updated = map
        var timber = 0.0
        var downed: Set<Int> = []
        // Where each trunk came down, so the timber can be left at the stump
        // for somebody to carry in rather than appearing in the storehouse.
        var stumps: [LocalPoint] = []
        for (worker, index) in workable.prefix(loggers).enumerated() {
            _ = worker
            updated.trees[index].chopped += chopPerTick
            if updated.trees[index].chopped >= 1 {
                timber += updated.trees[index].timberYield
                stumps.append(updated.trees[index].position)
                downed.insert(index)
            }
        }
        if !downed.isEmpty {
            updated.trees = updated.trees.enumerated()
                .filter { !downed.contains($0.offset) }
                .map(\.element)
        }
        return (updated, timber, downed.count, stumps)
    }

    /// Puts `miners` to the rock for one tick and returns what they broke out,
    /// and **where it is lying**.
    ///
    /// Harder stone gives up less for the same work, and a spent outcrop is
    /// left behind rather than removed — a worked-out quarry is a feature of
    /// the ground, not a hole in the save.
    ///
    /// `broken` is the half of this that was missing for as long as outcrops
    /// have existed. The caller took `.map` and dropped `.yield` on the floor,
    /// and nothing anywhere turned a worked outcrop into goods — so a valley
    /// with no massif in it (every coast, most plains) had its miners grind
    /// nine clay banks to nothing over four hundred ticks and bank *not one
    /// unit of clay*. Wood falls at the stump and hewn stone falls at the face;
    /// this is the same rule for the third and commonest kind of working.
    public static func quarry(
        _ map: LocalMap, miners: Int
    ) -> (map: LocalMap, yield: [LocalResourceKind: Double],
          broken: [(kind: LocalResourceKind, amount: Double, at: LocalPoint)]) {
        guard miners > 0, !map.rocks.isEmpty else { return (map, [:], []) }
        let workable = map.rocks.indices
            .filter { !map.rocks[$0].isSpent }
            .sorted {
                let a = map.rocks[$0], b = map.rocks[$1]
                if a.kind.hardness != b.kind.hardness { return a.kind.hardness < b.kind.hardness }
                return a.id < b.id
            }
        guard !workable.isEmpty else { return (map, [:], []) }

        var updated = map
        var yield: [LocalResourceKind: Double] = [:]
        var broken: [(kind: LocalResourceKind, amount: Double, at: LocalPoint)] = []
        for index in workable.prefix(miners) {
            let rock = updated.rocks[index]
            let taken = min(rock.amount, 1 / rock.kind.hardness)
            updated.rocks[index].amount = max(0, rock.amount - taken)
            yield[rock.kind.deposit, default: 0] += taken
            broken.append((kind: rock.kind.deposit, amount: taken, at: rock.position))
        }
        return (updated, yield, broken)
    }

    /// How far from a deposit's centre the things standing on it count as
    /// belonging to it. Generation scatters a wood inside 0.07 and outcrops
    /// inside 0.05, so this comfortably covers both with room for the fringe.
    public static let claimRadius: Double = 0.10

    static func within(_ a: LocalPoint, _ b: LocalPoint, _ radius: Double) -> Bool {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy <= radius * radius
    }

    /// Rewrites every deposit's `amount` from what is actually standing on it.
    ///
    /// A forest node used to be an independent number that dipped when someone
    /// worked it and crept back in spring, while the trees drawn over it were
    /// scenery that only *pretended* to thin out. Now the number **is** the
    /// wood: fell the trees and the deposit falls with them, let them grow and
    /// it recovers on its own. Stone is the same, except it never comes back.
    ///
    /// Deposits with nothing standing on them — an old save, a field, a herb
    /// patch — are left exactly as they were, so this can be applied to any map.
    public static func syncDeposits(_ map: LocalMap) -> LocalMap {
        guard map.usesEntityLand else { return map }
        var updated = map
        for i in updated.nodes.indices {
            let node = updated.nodes[i]
            switch node.kind {
            case .forest:
                let standing = map.trees
                    .filter { within($0.position, node.position, claimRadius) }
                    .reduce(0.0) { $0 + $1.timberYield }
                updated.nodes[i].amount = min(node.capacity, standing)
            case .stone, .ironOre, .clay:
                let left = map.rocks
                    .filter { $0.kind.deposit == node.kind
                              && within($0.position, node.position, claimRadius) }
                    .reduce(0.0) { $0 + $1.amount }
                updated.nodes[i].amount = min(node.capacity, left)
            case .field, .herbs:
                continue    // nothing stands on these; they keep the old arithmetic
            }
        }
        return updated
    }

    /// Whether a deposit kind is backed by real things, and so should neither
    /// be depleted nor regrown by the old node arithmetic.
    public static func isEntityBacked(_ kind: LocalResourceKind, in map: LocalMap) -> Bool {
        // Fields answer to their own layer, on their own flag: a map can have
        // plots without having trees (an old save whose colony has since raised
        // a farm) and trees without plots. See `LocalMap.usesEntityFields`.
        if kind == .field { return map.usesEntityFields }
        guard map.usesEntityLand else { return false }
        switch kind {
        case .forest, .stone, .ironOre, .clay: return true
        case .field, .herbs: return false
        }
    }

    /// Plants a sapling — the other half of felling, and the only way a wood
    /// that has been cleared ever comes back inside a colony's lifetime.
    public static func plant(
        _ map: LocalMap, species: TreeSpecies, at position: LocalPoint
    ) -> LocalMap {
        var updated = map
        let nextID = (updated.trees.map(\.id).max() ?? -1) + 1
        updated.trees.append(Tree(id: nextID, species: species, position: position, age: 0))
        return updated
    }
}
