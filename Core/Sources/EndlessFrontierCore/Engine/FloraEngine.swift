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
    public static func advanceOneTick(_ map: LocalMap) -> LocalMap {
        guard !map.trees.isEmpty else { return map }
        var updated = map
        for i in updated.trees.indices {
            updated.trees[i].age += 1
        }
        return updated
    }

    /// Puts `loggers` to the axe for one tick and returns the timber they
    /// brought down. Work goes into the biggest workable tree first — nobody
    /// fells a sapling while an oak is standing — and a tree that comes down is
    /// removed from the map.
    public static func fell(
        _ map: LocalMap, loggers: Int
    ) -> (map: LocalMap, timber: Double, felled: Int) {
        guard loggers > 0, !map.trees.isEmpty else { return (map, 0, 0) }

        // The standing wood worth an axe, biggest first. Ties break on id so
        // the same world always fells the same tree.
        let workable = map.trees.indices
            .filter { map.trees[$0].growth >= minimumWorkableGrowth }
            .sorted {
                let a = map.trees[$0], b = map.trees[$1]
                if a.timberYield != b.timberYield { return a.timberYield > b.timberYield }
                return a.id < b.id
            }
        guard !workable.isEmpty else { return (map, 0, 0) }

        var updated = map
        var timber = 0.0
        var downed: Set<Int> = []
        for (worker, index) in workable.prefix(loggers).enumerated() {
            _ = worker
            updated.trees[index].chopped += chopPerTick
            if updated.trees[index].chopped >= 1 {
                timber += updated.trees[index].timberYield
                downed.insert(index)
            }
        }
        if !downed.isEmpty {
            updated.trees = updated.trees.enumerated()
                .filter { !downed.contains($0.offset) }
                .map(\.element)
        }
        return (updated, timber, downed.count)
    }

    /// Puts `miners` to the rock for one tick and returns what they broke out.
    /// Harder stone gives up less for the same work, and a spent outcrop is
    /// left behind rather than removed — a worked-out quarry is a feature of
    /// the ground, not a hole in the save.
    public static func quarry(
        _ map: LocalMap, miners: Int
    ) -> (map: LocalMap, yield: [LocalResourceKind: Double]) {
        guard miners > 0, !map.rocks.isEmpty else { return (map, [:]) }
        let workable = map.rocks.indices
            .filter { !map.rocks[$0].isSpent }
            .sorted {
                let a = map.rocks[$0], b = map.rocks[$1]
                if a.kind.hardness != b.kind.hardness { return a.kind.hardness < b.kind.hardness }
                return a.id < b.id
            }
        guard !workable.isEmpty else { return (map, [:]) }

        var updated = map
        var yield: [LocalResourceKind: Double] = [:]
        for index in workable.prefix(miners) {
            let rock = updated.rocks[index]
            let taken = min(rock.amount, 1 / rock.kind.hardness)
            updated.rocks[index].amount = max(0, rock.amount - taken)
            yield[rock.kind.deposit, default: 0] += taken
        }
        return (updated, yield)
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
