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

    /// How much of a load a colonist gets across the map per **action step**.
    ///
    /// Was `0.06` *per tick*, which is the same number against a clock eight
    /// times coarser: a heap a quarter of the map away was four ticks of
    /// walking each way — the better part of an in-game month, and eight real
    /// minutes of a figure that did not visibly move. Distance is still a cost;
    /// it is now a cost measured in the unit a walk actually happens in. See
    /// `WalkPace`.
    public static let carrySpeed: Double = WalkPace.carryingPerStep
    /// …and empty-handed, on the way out to the heap. Hands free is quicker.
    public static let emptySpeed: Double = WalkPace.perStep
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

    /// One action step of hauling for a settlement: pick up, walk, put down.
    ///
    /// Runs every step, unlike the job board, so a load that has arrived is put
    /// down on the step it arrives rather than at the next board cycle. The
    /// *walk* is not stepped here — it was decided when it began (`WalkPath`)
    /// and the canvas reads it at a fractional step — so this only starts walks,
    /// finishes them, and hands loads over. Linear in the number of carriers.
    ///
    /// It used to run once a world tick, which made a walk across the colony a
    /// whole in-game week at minimum. The eight-fold finer grid is why a hauler
    /// now reads as a person crossing a town rather than as scenery.
    public static func advanceStep(
        _ settlement: Settlement, registry: GameDataRegistry, clock: WorldClock
    ) -> Settlement {
        guard var map = settlement.localMap else { return settlement }
        guard !map.piles.isEmpty || settlement.pawns.contains(where: { $0.carrying != nil })
        else { return settlement }

        var s = settlement
        let step = clock.absoluteStep
        let store = storePosition(s)
        let ticksPerYear = max(1, registry.config.ticksPerYear)
        // Claims are swept on the tick, not on every step: it is a whole pass
        // over the piles against a set of the living, and nobody dies eight
        // times in two minutes (rule 4).
        if clock.step == 0 {
            map.piles = releasingDeadClaims(map.piles, pawns: s.pawns, ticksPerYear: ticksPerYear)
        }
        // A pack animal takes the weight off: the colony's beasts of burden
        // make every hauler quicker, which is the whole reason to keep one.
        let lift = 1 + TamingEngine.bonuses(s).haul
        // What stands where, worked out once for the whole colony rather than
        // once per walker per sampled point (§11.23).
        // …and the rock with it: a cliff is as impassable as a wall, and
        // routing used to know only about walls.
        //
        // Built **lazily**, because this runs eight times as often as it used
        // to and laying out a 24×24 grid against every landform for a colony
        // where nobody happens to set off this step is exactly the per-step
        // cost rule 4 is about.
        var standing: ColonyRoute.Occupancy??
        func occupancy() -> ColonyRoute.Occupancy? {
            if let cached = standing { return cached }
            let built = s.colony.map {
                ColonyRoute.Occupancy($0, stone: map.stone, landforms: map.landforms)
            }
            standing = .some(built)
            return built
        }

        // Where a hauler is right now, and the walk that gets them to `target`
        // — the one they are already on if it still goes there, or a fresh one
        // from wherever they have got to. Deciding the walk **once** is the
        // whole point: it is what lets the canvas draw them crossing the town
        // instead of standing still and jumping (`WalkPath`), and it takes the
        // route out of the per-step path (rule 4).
        func walk(of pawn: Pawn, to target: LocalPoint, pace: Double) -> WalkPath {
            if let under = pawn.haulWalk, under.to == target { return under }
            let here = pawn.haulWalk?.position(at: Double(step)) ?? store
            return WalkPath.across(from: here, to: target, leavingAt: step,
                                   pace: pace, in: s.colony, occupancy: occupancy())
        }

        for i in s.pawns.indices {
            // Whether this colonist put a load down *this step*, and so has
            // both empty hands and a reason to look for the next heap now.
            var turnedRound = false
            // Someone already carrying just walks, and hands it over on arrival.
            if let load = s.pawns[i].carrying {
                let home = walk(of: s.pawns[i], to: load.destination,
                                pace: carrySpeed * lift)
                guard home.hasArrived(at: step) else {
                    s.pawns[i].haulWalk = home
                    continue
                }
                s.stockpile[load.itemID, default: 0] += load.amount
                s.pawns[i].carrying = nil
                s.pawns[i].haulWalk = nil
                turnedRound = true
                // …and they do **not** stand at the store until the next board
                // cycle. Falling through to the search below is what "turn
                // round and fetch the next one" means: a walk is a few steps
                // now, so a hauler tied to a ten-tick cadence would spend nine
                // tenths of the colony's day standing in the doorway.
            }

            // Otherwise: hands free, and a heap out there with their name on it.
            guard canHaul(s.pawns[i], ticksPerYear: ticksPerYear) else { continue }
            let held = map.piles.firstIndex(where: { $0.claimedBy == s.pawns[i].id })
            // Looking for *new* work is the expensive half — it walks every
            // heap for every free pair of hands — and it is also the half that
            // does not need answering every step. Fetching and carrying stay
            // per-step, because a load has to move; a fresh errand is picked up
            // on the job board's cadence, or the moment a load is put down.
            // Without this an offline catch-up pays that search forty thousand
            // times over.
            let looking = turnedRound
                || (clock.tick % JobBoard.interval == 0 && clock.step == 0)
            guard let index = held
                    ?? (looking ? nearestUnclaimed(in: map, to: store) : nil) else { continue }
            // Claim it, walk to it, and pick it up when they get there.
            map.piles[index].claimedBy = s.pawns[i].id
            let pilePosition = map.piles[index].position
            let out = walk(of: s.pawns[i], to: pilePosition, pace: emptySpeed * lift)
            if out.hasArrived(at: step) {
                let pile = map.piles.remove(at: index)
                s.pawns[i].carrying = HaulLoad(itemID: pile.itemID, amount: pile.amount,
                                               destination: store)
                // …and they turn round on the spot: the walk home begins at the
                // heap, not at the store they set out from.
                s.pawns[i].haulWalk = WalkPath.across(
                    from: pilePosition, to: store, leavingAt: step,
                    pace: carrySpeed * lift, in: s.colony, occupancy: occupancy())
            } else {
                s.pawns[i].haulWalk = out
            }
        }

        s.localMap = map
        return s
    }

    /// Gives back the heaps whose claimant can no longer come for them.
    ///
    /// **This was the famine.** A claim was only ever *set* — the one place it
    /// came off was `piles.remove(at:)`, when the carrier arrived. A colonist
    /// who claimed a heap and then died, sickened, or walked out to a landmark
    /// took it with them: `nearestUnclaimed` skips a claimed heap, so that food
    /// sat on the ground for the rest of the game. Over two centuries of
    /// ordinary deaths the claims accumulate and the harvest quietly stops
    /// arriving.
    ///
    /// Measured by `ZZStewardProbe`, seed 4242: goods lying reaped and uncarried
    /// climbed **9 → 42 → 136 → 228 → 318 → 354 and never once came down**,
    /// while the raw shelf went 4118 → 516 → **0** and the colony fell from 197
    /// to 44. Plots stood at 140 against 79 wanted the whole time, cooks and
    /// farmers both scaled with the population, and the larder emptied anyway —
    /// which is what "the famine is downstream of the fields" turned out to
    /// mean. Nothing was short. The food was reaped, dropped, and owned by
    /// somebody who was no longer alive to fetch it.
    ///
    /// Rule 6 in a place nobody thought to look for it: a resource whose
    /// *release* rate is zero fills up whatever the arrival rate is.
    static func releasingDeadClaims(
        _ piles: [HaulPile], pawns: [Pawn], ticksPerYear: Int
    ) -> [HaulPile] {
        guard piles.contains(where: { $0.claimedBy != nil }) else { return piles }
        // Who could still walk to a heap. A carrier already holding a load is
        // not among them — they picked their pile up, which removed it — so
        // anything still claimed in their name is a leak too.
        let ableHands = Set(
            pawns.filter { canHaul($0, ticksPerYear: ticksPerYear) && $0.carrying == nil }
                .map(\.id))
        guard !ableHands.isEmpty || piles.contains(where: { $0.claimedBy != nil }) else {
            return piles
        }
        return piles.map { pile in
            guard let owner = pile.claimedBy, !ableHands.contains(owner) else { return pile }
            var freed = pile
            freed.claimedBy = nil
            return freed
        }
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
