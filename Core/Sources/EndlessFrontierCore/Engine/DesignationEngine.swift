import Foundation

/// **What the player pointed at, and keeping that list honest.**
///
/// The marks themselves live on the settlement (`Settlement.designations`) and
/// are read by the engines that were already choosing targets — the axe, the
/// pick, the haulers, the hunt. This is the small amount of bookkeeping around
/// them: the sets those engines ask for, placing and lifting a mark, and
/// sweeping the ones whose thing is gone.
///
/// **Sweeping is the part that matters.** A tree that has been felled, a heap
/// that has been carried in and a beast that has been shot all vanish from the
/// map, and a mark that outlives its target is a line in the save that can
/// never be satisfied and an icon drawn over grass. Rule 5's shape: a list the
/// world can invalidate has to be reconciled against the world, not trusted.
public enum DesignationEngine {

    /// The most marks one settlement will hold.
    ///
    /// A cap because this is a *player's* list — somebody dragging across a
    /// wood should not be able to write four thousand entries into every save
    /// — and because a colony that is behind on forty marks is behind whether
    /// or not it is behind on four hundred.
    public static let limit = 64

    // MARK: - What the engines ask for

    public static func trees(_ settlement: Settlement) -> Set<Int> {
        var out: Set<Int> = []
        for mark in settlement.designations {
            if case .tree(let id) = mark.target { out.insert(id) }
        }
        return out
    }

    public static func rocks(_ settlement: Settlement) -> Set<Int> {
        var out: Set<Int> = []
        for mark in settlement.designations {
            if case .rock(let id) = mark.target { out.insert(id) }
        }
        return out
    }

    public static func piles(_ settlement: Settlement) -> Set<UUID> {
        var out: Set<UUID> = []
        for mark in settlement.designations {
            if case .pile(let id) = mark.target { out.insert(id) }
        }
        return out
    }

    public static func animals(_ settlement: Settlement) -> Set<UUID> {
        var out: Set<UUID> = []
        for mark in settlement.designations {
            if case .animal(let id) = mark.target { out.insert(id) }
        }
        return out
    }

    // MARK: - Placing and lifting

    /// Marks a thing, or lifts the mark if it is already there.
    ///
    /// One call for both, because that is what a tap on the same thing twice
    /// means, and it keeps the two halves from drifting apart.
    public static func toggle(
        _ settlement: Settlement, target: Designation.Target, tick: Int
    ) -> Settlement {
        var s = settlement
        if let existing = s.designations.firstIndex(where: { $0.target == target }) {
            s.designations.remove(at: existing)
            return s
        }
        guard s.designations.count < limit else { return s }
        s.designations.append(Designation(target: target, placedTick: tick))
        return s
    }

    public static func isMarked(_ settlement: Settlement, target: Designation.Target) -> Bool {
        settlement.designations.contains { $0.target == target }
    }

    /// Everything marked, in the order it was asked for.
    public static func standing(_ settlement: Settlement) -> [Designation] {
        settlement.designations.sorted {
            $0.placedTick == $1.placedTick
                ? $0.id.uuidString < $1.id.uuidString
                : $0.placedTick < $1.placedTick
        }
    }

    // MARK: - Sweeping

    /// Drops the marks whose thing is no longer there.
    ///
    /// Called once a tick. Cheap — four sets built from the map against a list
    /// the size of a player's patience — and it is what keeps a mark from
    /// being a permanent icon over an empty patch of ground.
    public static func prune(_ settlement: Settlement) -> Settlement {
        guard !settlement.designations.isEmpty else { return settlement }
        guard let map = settlement.localMap else {
            // No valley to check against: leave the marks alone rather than
            // silently binning a player's list because a map has not loaded.
            return settlement
        }
        let trees = Set(map.trees.map(\.id))
        // A rock that has been dug out is still on the map with nothing in it,
        // and a mark on it can never be satisfied.
        let rocks = Set(map.rocks.filter { !$0.isSpent }.map(\.id))
        let piles = Set(map.piles.map(\.id))
        let animals = Set(map.wildlife.animals.map(\.id))
        var s = settlement
        s.designations.removeAll { mark in
            switch mark.target {
            case .tree(let id): return !trees.contains(id)
            case .rock(let id): return !rocks.contains(id)
            case .pile(let id): return !piles.contains(id)
            case .animal(let id): return !animals.contains(id)
            }
        }
        return s
    }
}
