import Foundation

/// Carrying things home.
///
/// The abstract economy is untouched by this: `materials` still accrues from
/// the harvest the way everything is balanced on. What moves is the **concrete
/// goods** — wood, rough stone, iron ore, clay — which used to be granted by
/// worker-ticks, as though a logger's week turned into planks wherever he
/// happened to be standing. Those goods now come off the ground: a felled tree
/// leaves timber at the stump, a broken block leaves stone at the face, and
/// somebody has to walk out and bring it in.
///
/// The rules are deliberately small. There is no hauling *trade*: anybody whose
/// hands are free carries, because a colony of twelve cannot afford a
/// specialist porter and RimWorld's answer — hauling is what you do when there
/// is nothing better — is the right one. A hauler claims a pile so two people
/// do not walk to the same heap, carries it to the nearest store, and is done.
///
/// Deterministic and cheap: one pass over the piles in their stored order, on
/// the job board's cadence.
public enum HaulEngine {

    /// How much of a load a colonist gets across the map per tick, in
    /// normalised units. A pile a quarter of the map away is a few ticks of
    /// walking, which is the point — distance is a cost now.
    public static let carrySpeed: Double = 0.06
    /// How close is close enough to have arrived.
    public static let arrivalRadius: Double = 0.02
    /// The most piles a map keeps. Past this the oldest are merged into the
    /// nearest neighbour rather than left to accumulate for ever: a valley
    /// logged flat should not carry two hundred heaps in its save.
    public static let maxPiles = 40

    // MARK: - Dropping

    /// Leaves a pile of `itemID` at `position`.
    ///
    /// Piles close together merge, so a wood being worked steadily grows one
    /// heap at the landing rather than a confetti of single logs.
    public static func drop(
        _ map: LocalMap, itemID: String, amount: Int, at position: LocalPoint,
        tick: Int, rng: inout SeededRNG
    ) -> LocalMap {
        guard amount > 0 else { return map }
        var updated = map
        if let index = updated.piles.firstIndex(where: {
            $0.itemID == itemID && $0.claimedBy == nil && within($0.position, position, mergeRadius)
        }) {
            updated.piles[index].amount += amount
            return updated
        }
        updated.piles.append(HaulPile(id: rng.nextUUID(), position: position,
                                      itemID: itemID, amount: amount, droppedTick: tick))
        // Keep the map from silting up: the oldest unclaimed heap goes.
        if updated.piles.count > maxPiles,
           let oldest = updated.piles.enumerated()
            .filter({ $0.element.claimedBy == nil })
            .min(by: { $0.element.droppedTick < $1.element.droppedTick })?.offset {
            updated.piles.remove(at: oldest)
        }
        return updated
    }

    /// How near two heaps have to be to become one.
    static let mergeRadius: Double = 0.035

    static func within(_ a: LocalPoint, _ b: LocalPoint, _ radius: Double) -> Bool {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy <= radius * radius
    }

    // MARK: - Carrying

    /// One tick of hauling for a settlement: pick up, walk, put down.
    ///
    /// Runs every tick, unlike the job board — a carried load has to *move*
    /// every tick or a hauler would teleport between board cycles. It is
    /// linear in the number of carriers, which is small.
    public static func advanceOneTick(
        _ settlement: Settlement, registry: GameDataRegistry, tick: Int
    ) -> Settlement {
        guard var map = settlement.localMap else { return settlement }
        guard !map.piles.isEmpty || settlement.pawns.contains(where: { $0.carrying != nil })
        else { return settlement }

        var s = settlement
        let store = storePosition(s)
        let ticksPerYear = max(1, registry.config.ticksPerYear)

        for i in s.pawns.indices {
            // Someone already carrying just walks, and hands it over on arrival.
            if let load = s.pawns[i].carrying {
                if within(s.pawns[i].haulPosition ?? store, load.destination, arrivalRadius) {
                    s.stockpile[load.itemID, default: 0] += load.amount
                    s.pawns[i].carrying = nil
                    s.pawns[i].haulPosition = nil
                    continue
                }
                let next = step(from: s.pawns[i].haulPosition ?? store,
                                toward: load.destination, by: carrySpeed)
                s.pawns[i].haulPosition = next
                if within(next, load.destination, arrivalRadius) {
                    s.stockpile[load.itemID, default: 0] += load.amount
                    s.pawns[i].carrying = nil
                    s.pawns[i].haulPosition = nil
                }
                continue
            }

            // Otherwise: hands free, and a heap out there with their name on it.
            guard canHaul(s.pawns[i], ticksPerYear: ticksPerYear) else { continue }
            let held = map.piles.firstIndex(where: { $0.claimedBy == s.pawns[i].id })
            // Looking for *new* work is the expensive half — it walks every
            // heap for every free pair of hands — and it is also the half that
            // does not need answering every minute. Fetching and carrying stay
            // per-tick, because a load has to move; picking up a fresh errand
            // happens on the job board's cadence. Without this an offline
            // catch-up pays that search forty thousand times over.
            guard let index = held
                    ?? (tick % JobBoard.interval == 0
                        ? nearestUnclaimed(in: map, to: store) : nil) else { continue }
            // Claim it, walk to it, and pick it up when they get there.
            map.piles[index].claimedBy = s.pawns[i].id
            let pilePosition = map.piles[index].position
            let standing = s.pawns[i].haulPosition ?? store
            if within(standing, pilePosition, arrivalRadius) {
                let pile = map.piles.remove(at: index)
                s.pawns[i].carrying = HaulLoad(itemID: pile.itemID, amount: pile.amount,
                                               destination: store)
                s.pawns[i].haulPosition = pilePosition
            } else {
                s.pawns[i].haulPosition = step(from: standing, toward: pilePosition,
                                               by: carrySpeed)
            }
        }

        s.localMap = map
        return s
    }

    /// Whether this colonist's hands are free for a heap.
    ///
    /// Hauling is what you do when there is nothing better: an adult who is
    /// here, not broken, and not out at a landmark. Deliberately *not* a trade
    /// — a colony of twelve cannot spare a specialist porter.
    static func canHaul(_ pawn: Pawn, ticksPerYear: Int) -> Bool {
        pawn.isAdult(ticksPerYear: ticksPerYear) && !pawn.isBroken && !pawn.isAway
            && pawn.health > 0
    }

    /// The nearest heap nobody has claimed.
    static func nearestUnclaimed(in map: LocalMap, to point: LocalPoint) -> Int? {
        var best: Int?
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, pile) in map.piles.enumerated() where pile.claimedBy == nil {
            guard map.isExplored(pile.position) else { continue }
            let dx = pile.position.x - point.x, dy = pile.position.y - point.y
            let d = dx * dx + dy * dy
            if d < bestDistance { bestDistance = d; best = index }
        }
        return best
    }

    /// Where goods are put down: the colony's storehouse if it has one, else
    /// its heart.
    public static func storePosition(_ settlement: Settlement) -> LocalPoint {
        guard let colony = settlement.colony else { return SettlementGeometry.heart }
        // Anything with a granary's job stands in for a warehouse.
        for placement in colony.placements where !placement.underConstruction {
            if placement.definitionID.contains("granary")
                || placement.definitionID.contains("warehouse")
                || placement.definitionID.contains("store") {
                return SettlementGeometry.canvasPoint(for: placement, in: colony)
            }
        }
        return SettlementGeometry.heart
    }

    /// A step toward a point, kept on the map.
    static func step(from: LocalPoint, toward: LocalPoint, by distance: Double) -> LocalPoint {
        let dx = toward.x - from.x, dy = toward.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 1e-9 else { return toward }
        let t = min(1, distance / length)
        return LocalPoint(x: min(1, max(0, from.x + dx * t)),
                          y: min(1, max(0, from.y + dy * t)))
    }

    /// Whether this ground's goods arrive by being carried rather than by being
    /// worked for.
    ///
    /// Wood and stone come off felled trees and broken blocks — things that
    /// happen at a place and leave something lying there. A field and a herb
    /// patch do not: you carry the basket home as part of picking it, and
    /// modelling a hauler for every handful of herbs would be tedious rather
    /// than interesting. This is the line between the two, and the reason
    /// `extractRawMaterials` no longer grants timber and ore by the week.
    public static func isHauled(_ kind: LocalResourceKind) -> Bool {
        switch kind {
        case .forest, .stone, .ironOre, .clay: return true
        case .field, .herbs: return false
        }
    }

    /// Everything lying about, for the objective and the ledger to read.
    public static func waiting(_ settlement: Settlement) -> Int {
        settlement.localMap?.piles.reduce(0) { $0 + $1.amount } ?? 0
    }
}
