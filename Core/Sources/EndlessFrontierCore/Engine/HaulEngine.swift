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

    /// **How much one colonist gets home in one trip.**
    ///
    /// There was no such number. A hauler picked up *the whole heap* however
    /// big it was — `amount: pile.amount` — so twelve logs and one log were the
    /// same walk, and a colony's carrying capacity was purely a question of how
    /// many feet it had. That is why `ConveyanceDefinition.cargo` had nowhere to
    /// land: you cannot multiply a limit that does not exist.
    ///
    /// Four is a person's arms full. It is deliberately small enough that a
    /// good harvest takes several trips, because that is the pressure a cart is
    /// an answer to — see `docs/MOUNTS_AND_VEHICLES.md`.
    public static let armfuls = 4

    /// What this colony can move in one trip: a pair of arms, plus whatever is
    /// standing in the yard.
    ///
    /// The fourth seam, and the one the yard exists for. `cargo` is stated in
    /// *multiples of a back*, so it adds to the armful rather than scaling the
    /// walk — a cart does not make you faster, it makes the trip worth more,
    /// and those are different sentences about a colony.
    public static func carryLimit(
        _ settlement: Settlement, registry: GameDataRegistry,
        /// What the colony has learned about carrying — a yoke, a pannier, a
        /// barrow (`ResearchStat.carryCapacity`). Applied to the arms and to
        /// the cart alike, and rounded down, so a study that has not yet
        /// bought a whole extra armful buys nothing.
        learned: Double = 1
    ) -> Int {
        let base = Double(armfuls + StableEngine.cargoCapacity(settlement, registry: registry))
        return max(1, Int(base * learned))
    }

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
        _ settlement: Settlement, registry: GameDataRegistry, clock: WorldClock,
        /// `ResearchStat.carryCapacity`, passed from `ActionLoop` because a
        /// hauling step has no `WorldState` to ask.
        carryFactor: Double = 1
    ) -> Settlement {
        guard var map = settlement.localMap else { return settlement }
        guard !map.piles.isEmpty || settlement.pawns.contains(where: { $0.carrying != nil })
        else { return settlement }

        var s = settlement
        let step = clock.absoluteStep
        // Where a hauler with nothing to their name stands, and the point the
        // heap search measures from. Not a *destination* any more — a load's
        // destination depends on what the load is and where it was picked up,
        // and is decided at the heap (`storePosition(_:for:registry:from:)`).
        let yard = storePosition(s, registry: registry)
        let ticksPerYear = max(1, registry.config.ticksPerYear)
        // What the player has pointed at, gathered once for the whole pass
        // rather than per hauler per step.
        let wanted = DesignationEngine.piles(s)
        // Claims are swept on the tick, not on every step: it is a whole pass
        // over the piles against a set of the living, and nobody dies eight
        // times in two minutes (rule 4).
        if clock.step == 0 {
            map.piles = releasingDeadClaims(map.piles, pawns: s.pawns, ticksPerYear: ticksPerYear)
            // …and what the weather took off the heaps nobody has carried in
            // yet. On the tick, not the step: rot is a rate per unit time and
            // running it eight times a tick would rot the valley eight times as
            // fast — the exact mistake `ErrandEngine` made when it moved onto
            // this clock (rule 34's tail).
            map.piles = weathered(map.piles, tick: clock.tick,
                                  seed: map.terrainSeed, registry: registry)
        }
        // A pack animal takes the weight off: the colony's beasts of burden
        // make every hauler quicker, which is the whole reason to keep one.
        //
        // …and so does the yard. A travois, a cart, an ox under a load — the
        // first of the four seams in `docs/MOUNTS_AND_VEHICLES.md`, and the one
        // the colony feels most, because hauling is most of what it does. Two
        // sources, one multiplier, each with its own ceiling: a colony with
        // both a stable and a cartwright is quicker than one with either, and
        // neither can run away on its own.
        let lift = 1 + TamingEngine.bonuses(s).haul
            + StableEngine.haulLift(s, registry: registry)
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
            let here = pawn.haulWalk?.position(at: Double(step)) ?? yard
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
                    ?? (looking ? nearestUnclaimed(in: map, to: yard, marked: wanted) : nil)
            else { continue }
            // Claim it, walk to it, and pick it up when they get there.
            map.piles[index].claimedBy = s.pawns[i].id
            let pilePosition = map.piles[index].position
            let out = walk(of: s.pawns[i], to: pilePosition, pace: emptySpeed * lift)
            if out.hasArrived(at: step) {
                // As much of the heap as they can carry, and the rest stays
                // where it is for the next trip — which is what makes a cart
                // worth building.
                let limit = carryLimit(s, registry: registry, learned: carryFactor)
                let pile: HaulPile
                if map.piles[index].amount > limit {
                    map.piles[index].amount -= limit
                    map.piles[index].claimedBy = nil
                    pile = HaulPile(id: map.piles[index].id,
                                    position: map.piles[index].position,
                                    itemID: map.piles[index].itemID,
                                    amount: limit,
                                    droppedTick: map.piles[index].droppedTick)
                } else {
                    pile = map.piles.remove(at: index)
                }
                // Which store this load goes to is decided **here**, with the
                // heap in their hands: grain to the granary, timber to the
                // warehouse, and the nearest one of the right kind measured
                // from where they are standing rather than from the middle of
                // town. A colony with two quarters carries to its own quarter.
                let destination = storePosition(s, for: pile.itemID, registry: registry,
                                                from: pilePosition)
                s.pawns[i].carrying = HaulLoad(itemID: pile.itemID, amount: pile.amount,
                                               destination: destination)
                // …and they turn round on the spot: the walk home begins at the
                // heap, not at the store they set out from.
                s.pawns[i].haulWalk = WalkPath.across(
                    from: pilePosition, to: destination, leavingAt: step,
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

    // MARK: - Lying in the mud

    /// What a year in the open costs a heap, by what the stuff **is**.
    ///
    /// Keks: *"chybí sklady, protože materiál a jídlo se hromadí venku na
    /// hromadách ve vesnici — za co by měla být penalizace… stejně tak když je
    /// necháš ležet venku v hlíně (kameny ne třeba)."* Which is exactly right,
    /// and it is also the reason a store was worth building and never was: a
    /// granary and a warehouse deepen a cap that a colony rarely reaches, and
    /// nothing at all happened to goods left where they fell. A sink only bites
    /// when there is a force pushing the other way.
    ///
    /// Read off `ItemDefinition.substance` rather than a list of item ids, so a
    /// new material rots correctly on the day it is added and stone is exempt
    /// because stone *is* stone — not because somebody remembered to exempt it.
    static func spoilPerTick(_ substance: Cover.Substance?) -> Double {
        switch substance {
        // Grain, roots, greens, meat, berries, hide, herbs. Six in-game days
        // in the rain is a real bite: about half of an unclaimed heap is gone
        // inside a season, which is what makes a granary a building and not a
        // number.
        case .foliage: return 0.015
        // Timber and charcoal go slowly — they warp and they rot at the ends.
        case .wood: return 0.004
        // Stone, ore, brick, iron. Nothing the weather does to these matters.
        case .stone, .air, .none: return 0
        }
    }

    /// Weathers the heaps lying about the valley, and clears the ones that have
    /// gone entirely.
    ///
    /// Deterministic per `(seed, pile, tick)` — rule 3. Whole units, because a
    /// pile is a countable thing: the expected loss is spent as whole units and
    /// the remainder is the chance of one more, so a heap of two hundred rots
    /// smoothly and a heap of three rots as luck has it.
    static func weathered(
        _ piles: [HaulPile], tick: Int, seed: UInt64, registry: GameDataRegistry
    ) -> [HaulPile] {
        var out: [HaulPile] = []
        out.reserveCapacity(piles.count)
        for pile in piles {
            let rate = spoilPerTick(registry.item(pile.itemID)?.substance)
            guard rate > 0, pile.amount > 0 else { out.append(pile); continue }
            let expected = Double(pile.amount) * rate
            var rng = SeededRNG(seed: spoilSeed(seed, pile: pile.id, tick: tick))
            var lost = Int(expected)
            if rng.nextUnit() < expected - Double(lost) { lost += 1 }
            guard lost > 0 else { out.append(pile); continue }
            var worse = pile
            worse.amount = max(0, pile.amount - lost)
            guard worse.amount > 0 else { continue }   // gone into the ground
            out.append(worse)
        }
        return out
    }

    /// `(map seed, this heap, this tick)` — never `UUID.hashValue`, which Swift
    /// seeds per process and which would give a different valley every launch
    /// (rule 3, and §10.7's founder bug in miniature).
    static func spoilSeed(_ mapSeed: UInt64, pile: UUID, tick: Int) -> UInt64 {
        var h = mapSeed &* 0x9E37_79B9_7F4A_7C15
        let b = pile.uuid
        h ^= UInt64(b.0) << 56 | UInt64(b.1) << 48 | UInt64(b.2) << 40 | UInt64(b.3) << 32
            | UInt64(b.4) << 24 | UInt64(b.5) << 16 | UInt64(b.6) << 8 | UInt64(b.7)
        h = (h ^ UInt64(bitPattern: Int64(tick))) &* 0xD1B5_4A32_D192_ED03
        return (h ^ (h >> 29)) | 1
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
    /// The next heap worth walking to. **A heap the player marked is fetched
    /// before any other**, however far it is — that is the whole of what
    /// marking one means (`Designation`) — and otherwise the nearest.
    static func nearestUnclaimed(
        in map: LocalMap, to point: LocalPoint, marked: Set<UUID> = []
    ) -> Int? {
        var best: Int?
        var bestDistance = Double.greatestFiniteMagnitude
        var bestMarked = false
        for (index, pile) in map.piles.enumerated() where pile.claimedBy == nil {
            guard map.isExplored(pile.position) else { continue }
            let dx = pile.position.x - point.x, dy = pile.position.y - point.y
            let d = dx * dx + dy * dy
            let wanted = marked.contains(pile.id)
            if wanted != bestMarked {
                guard wanted else { continue }
                bestMarked = true; bestDistance = d; best = index
                continue
            }
            if d < bestDistance { bestDistance = d; best = index }
        }
        return best
    }

    /// Where a load of `itemID` is put down.
    ///
    /// **The nearest building that keeps that kind of thing**, and the goods
    /// yard if the colony has not built one yet. Three things were wrong with
    /// the name-matching version this replaces, and they compounded:
    ///
    /// 1. It matched on the *id string* — `contains("granary")` — so a store
    ///    was a store because of what it was called. A new building called
    ///    `root_cellar` would have kept nothing, silently.
    /// 2. It took the **first** match in placement order, so a colony with a
    ///    granary in one quarter and a warehouse in another carried everything
    ///    to whichever happened to be raised first, however far it was.
    /// 3. Grain and timber went to the *same* building, because neither the
    ///    kind of the good nor the kind of the store was ever asked about.
    ///
    /// Now the good says what it is (`CookingEngine.foodstuffs` is the same
    /// list the kitchens read, so there is one answer to "is this food"), the
    /// building says what it holds (`storage`, which is data and already
    /// exists), and the walk is to the nearest of the ones that agree. A granary
    /// takes the harvest, a warehouse takes the timber, a market takes either.
    ///
    /// The fallback is the **goods yard, not the green**: a colony with nowhere
    /// to put its timber used to pile it on the one square people gather in.
    public static func storePosition(
        _ settlement: Settlement, for itemID: String? = nil,
        registry: GameDataRegistry = GameDataRegistry(),
        from: LocalPoint? = nil
    ) -> LocalPoint {
        guard let colony = settlement.colony else { return SettlementGeometry.goodsYard }
        let wanted: ResourceType = itemID.map {
            CookingEngine.foodstuffs(registry).contains($0) ? .food : .materials
        } ?? .materials
        let origin = from ?? SettlementGeometry.goodsYard

        var best: (at: LocalPoint, distance: Double)?
        for placement in colony.placements where !placement.underConstruction {
            guard let def = registry.building(placement.definitionID),
                  (def.storage[wanted] ?? 0) > 0 else { continue }
            let at = SettlementGeometry.canvasPoint(for: placement, in: colony)
            let distance = SiegeField.distance(origin, at)
            if distance < (best?.distance ?? .infinity) { best = (at, distance) }
        }
        // A colony that has raised no store of the right kind still has to put
        // the load down somewhere, and the *wrong* store is better than the
        // middle of the square: a granary will hold sacks of anything at a
        // pinch. Only a colony with nothing at all uses the yard.
        if best == nil {
            for placement in colony.placements where !placement.underConstruction {
                guard let def = registry.building(placement.definitionID),
                      ResourceType.allCases.contains(where: { (def.storage[$0] ?? 0) > 0 })
                else { continue }
                let at = SettlementGeometry.canvasPoint(for: placement, in: colony)
                let distance = SiegeField.distance(origin, at)
                if distance < (best?.distance ?? .infinity) { best = (at, distance) }
            }
        }
        return best?.at ?? SettlementGeometry.goodsYard
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
        case .forest, .stone, .ironOre, .clay, .coal, .oilSeep: return true
        case .field, .herbs: return false
        }
    }

    /// Everything lying about, for the objective and the ledger to read.
    public static func waiting(_ settlement: Settlement) -> Int {
        settlement.localMap?.piles.reduce(0) { $0 + $1.amount } ?? 0
    }
}
