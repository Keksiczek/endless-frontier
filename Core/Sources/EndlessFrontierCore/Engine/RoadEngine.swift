import Foundation

/// **Who lays the roads, what takes them back, and where a track comes from.**
///
/// Three motions, and only the middle one costs the colony anything:
///
/// 1. **Traffic beats a track.** Nobody decides to build one. Where caravans,
///    expeditions and supply runs actually go, the ground wears into a way —
///    which is how the map earns its first roads without the player having to
///    know roads exist. A track is 1.35× and free.
/// 2. **The council makes a road.** `StewardEngine` runs the colony in the
///    gaps, and `wanted(in:)` tells it which single edge is worth the most
///    right now: the piece that carries the most traffic through the worst
///    country. One edge at a time, paid for out of materials, so the network
///    grows visibly and a half-built road is a real state of the world.
/// 3. **Weather takes it back.** A way nobody mends returns to being country.
///    Stone lasts, a levelled track does not, and a road at zero condition is
///    removed rather than kept as a line on the map that means nothing.
///
/// Pure, like every engine here: `advanceOneTick(state, registry) -> WorldState`
/// with no clock and no unseeded die.
public enum RoadEngine {
    /// How much traffic one journey lays down on each edge it uses.
    static let trafficPerJourney = 1.0

    /// Traffic at which the ground is a track.
    ///
    /// **Measured, not guessed** — and the first guess was wrong by more than
    /// an order of magnitude. `RoadProbe` over two hundred years of a real
    /// world: total traffic across the whole map, at the end, was **four**.
    /// The threshold was sixty. Not one track could ever be worn, in any world,
    /// ever: rule 6 in the plainest form it takes, a threshold beyond the reach
    /// of the rate meant to cross it.
    ///
    /// The rate is what it is because journeys between *regions* are rare — a
    /// caravan every few years, an expedition when the council has hands to
    /// spare. So three crossings of the same edge is a path, which is about
    /// right for a world where crossing it at all is an occasion.
    static let trackThreshold = 3.0

    /// Traffic decays, or a route abandoned two centuries ago still counts.
    ///
    /// Also re-measured. At the first value a lane lost three quarters of its
    /// traffic over a long game, which on a *four*-journey budget is most of
    /// the evidence — so the decay was erasing the signal faster than the world
    /// could write it. Half-life of about four centuries now: long enough that
    /// a lane in use stays warm, short enough that a road to a town that died
    /// is eventually allowed to go under.
    static let trafficDecayPerTick = 0.00003

    /// How much of the colony's materials the council will sink into a road.
    /// A road is worth having and never worth starving for.
    static let reserveMultiple = 2.5

    // MARK: - The tick

    /// How much **two neighbouring towns wear the ground between them**, per
    /// person, each time this is counted.
    ///
    /// The missing half, and it took three measurements to see because each of
    /// the first two moved a number and changed nothing on the map. Traffic was
    /// recorded only when a caravan was *dispatched* or a party sent out — and
    /// in two hundred measured years of a five-town realm that is **thirteen
    /// journeys**, because supply only moves when somebody is short and the
    /// council only explores out of overflow. A threshold tuned against that is
    /// tuning against noise.
    ///
    /// What actually wears a road is not freight. It is people going back and
    /// forth between places that are near each other: to a market, to a
    /// wedding, to a brother's farm. That is a **rate that exists as long as
    /// the towns do**, it scales with how many people live in them, and it puts
    /// roads exactly where roads belong — between neighbours.
    ///
    /// `TradeRoute` was the first guess at this and is not it: `tradeRoutes` is
    /// empty in every world the harness plays, so the clause did nothing at all.
    static let trafficPerPersonVisit = 0.0006

    /// What is left of an ancient way after weather has had everything it can
    /// take. See `RoadOrigin.ancient` — this is the floor, not a slower decay:
    /// the fall already happened, centuries before anybody arrived.
    static let ancientFloor = 0.22

    /// What a ruin takes off the price of building on it, because the ground is
    /// already levelled and the stone is already quarried and lying there.
    ///
    /// Not free: clearing two centuries of scrub off a buried causeway is work,
    /// and a discount large enough to make a ruin the *only* place worth
    /// building would turn the map into a puzzle with one answer.
    static let ancientDiscount = 0.55

    /// How often the neighbourly traffic is counted, in ticks.
    ///
    /// Not every tick: this pathfinds per settlement, and a realm that grows
    /// over a long game would turn an offline catch-up into a bill nobody
    /// asked for (rule 4 — put a cost on the think cadence and multiply, don't
    /// compound). On the same cadence as `SupplyEngine` for the same reason.
    static let visitInterval = 40

    public static func advanceOneTick(
        _ state: WorldState, registry: GameDataRegistry
    ) -> WorldState {
        var s = state
        s = neighbourlyTraffic(s)
        s = decayTraffic(s)
        s = beatTracks(s)
        s = weather(s, registry: registry)
        return s
    }

    /// **People going back and forth between towns that are near each other.**
    ///
    /// Each settlement to its *nearest* neighbour, weighted by the smaller of
    /// the two populations — a hamlet beside a city wears the road at a
    /// hamlet's rate, because it is the hamlet's feet doing the walking.
    ///
    /// Nearest-only, so this is O(settlements) rather than O(settlements²): a
    /// realm of twenty towns pathfinds twenty times, not a hundred and ninety.
    /// The network that comes out is a chain between neighbours, which is what
    /// a road network *is* before anybody plans one.
    static func neighbourlyTraffic(_ state: WorldState) -> WorldState {
        guard state.tick % visitInterval == 0, state.settlements.count > 1 else { return state }
        var s = state
        let seats = Dictionary(
            s.settlements.compactMap { settlement -> (UUID, HexCoord)? in
                guard let regionID = settlement.regionID,
                      let region = s.regions.first(where: { $0.id == regionID })
                else { return nil }
                return (settlement.id, region.coord)
            }) { first, _ in first }

        for settlement in s.settlements {
            guard let here = seats[settlement.id] else { continue }
            // The nearest other town, by hexes — sorted by id on a tie so the
            // choice cannot depend on array order (which is not stable).
            let nearest = s.settlements
                .filter { $0.id != settlement.id && seats[$0.id] != nil }
                .min { a, b in
                    let da = here.distance(to: seats[a.id]!)
                    let db = here.distance(to: seats[b.id]!)
                    return da == db ? a.id.uuidString < b.id.uuidString : da < db
                }
            guard let nearest, let there = seats[nearest.id] else { continue }
            let walkers = Double(min(settlement.pawns.count, nearest.pawns.count))
            guard walkers > 0 else { continue }
            let byCoord = Dictionary(s.regions.map { ($0.coord, $0) }) { first, _ in first }
            guard let route = s.roads.route(from: here, to: there, regions: byCoord) else { continue }
            let laid = walkers * trafficPerPersonVisit * Double(visitInterval)
            for (a, b) in zip(route.hexes, route.hexes.dropFirst()) {
                s.roadTraffic[RoadLink.key(a, b), default: 0] += laid
            }
        }
        return s
    }

    /// Records that somebody went this way. Called by whoever moves across the
    /// map — the caravans, the supply runs, the expeditions — so the roads
    /// appear where the world actually travels rather than where a table says.
    public static func travelled(_ state: WorldState, route: [HexCoord]) -> WorldState {
        guard route.count > 1 else { return state }
        var s = state
        for (from, to) in zip(route, route.dropFirst()) {
            s.roadTraffic[RoadLink.key(from, to), default: 0] += trafficPerJourney
        }
        return s
    }

    static func decayTraffic(_ state: WorldState) -> WorldState {
        guard !state.roadTraffic.isEmpty else { return state }
        var s = state
        for (key, value) in s.roadTraffic {
            let next = value * (1 - trafficDecayPerTick)
            if next < 0.01 { s.roadTraffic.removeValue(forKey: key) } else { s.roadTraffic[key] = next }
        }
        return s
    }

    /// Where the ground has been walked enough, it is a track.
    static func beatTracks(_ state: WorldState) -> WorldState {
        var s = state
        let byCoord = coordIndex(s)
        for (key, traffic) in s.roadTraffic where traffic >= trackThreshold {
            guard s.roads.links[key] == nil,
                  let ends = ends(of: key),
                  byCoord[ends.0] != nil, byCoord[ends.1] != nil else { continue }
            s.roads.lay(RoadLink(a: ends.0, b: ends.1, grade: .track))
        }
        return s
    }

    /// What the sky does to a way nobody is mending.
    ///
    /// Traffic *keeps* a road as well as making one: a way in daily use is
    /// repaired by the people using it, and a way nobody takes goes under. So
    /// the network thins back to what the world actually needs rather than
    /// accumulating every road ever built, which is what would happen if wear
    /// were flat.
    static func weather(_ state: WorldState, registry: GameDataRegistry) -> WorldState {
        var s = state
        var ruined: [(HexCoord, HexCoord)] = []
        for link in s.roads.all {
            let traffic = s.roadTraffic[link.id] ?? 0
            // A way in daily use is kept by the people using it. Scaled against
            // `trackThreshold`, so this stays right when that number moves —
            // which it already has once, by a factor of twenty.
            let kept = min(0.9, traffic / trackThreshold * 0.5)
            var next = link
            let floor = link.origin == .ancient ? ancientFloor : 0
            next.condition = max(floor, link.condition - link.grade.wearPerTick * (1 - kept))
            if next.condition <= 0 {
                // A track that fails is simply gone; anything dearer falls back
                // to the grade below rather than vanishing, because the levelled
                // ground under a paved road does not stop existing.
                if let lower = fallback(from: link.grade) {
                    s.roads.update(RoadLink(a: link.a, b: link.b, grade: lower,
                                            condition: 0.5, origin: link.origin))
                } else {
                    ruined.append((link.a, link.b))
                }
            } else {
                s.roads.update(next)
            }
        }
        for (a, b) in ruined { s.roads.remove(a, b) }
        return s
    }

    static func fallback(from grade: RoadGrade) -> RoadGrade? {
        switch grade {
        case .track: return nil
        case .road:  return .track
        case .paved: return .road
        // A railway that fails leaves its embankment, which is a road.
        case .rail:  return .road
        }
    }

    // MARK: - What the council should build

    /// The one edge most worth making, and what it would cost.
    ///
    /// Scored by **traffic × how bad the country is**, because that is exactly
    /// where a road pays: a made way across a plain saves a tenth of the
    /// journey, and one through a fen or over a pass saves half of it. The
    /// council therefore ends up building the pass — which is the piece a
    /// player would have chosen, arrived at from the numbers rather than from a
    /// list of special cases.
    public static func wanted(
        in state: WorldState, registry: GameDataRegistry
    ) -> (link: RoadLink, cost: Double)? {
        let byCoord = coordIndex(state)
        var best: (link: RoadLink, cost: Double, score: Double)?

        for (key, traffic) in state.roadTraffic.sorted(by: { $0.key < $1.key }) {
            guard let ends = ends(of: key),
                  let here = byCoord[ends.0], let there = byCoord[ends.1] else { continue }
            let existing = state.roads.links[key]
            guard let grade = nextGrade(after: existing?.grade, state: state) else { continue }

            // The worse of the two hexes decides: a road is only as good as its
            // hardest stretch, and it is the hard stretch you are paying to fix.
            let country = max(TerrainCost.of(here), TerrainCost.of(there))
            let gain = country - max(1, country / grade.speed)
            let score = traffic * gain
            guard score > 0 else { continue }
            let cost = price(grade, here: here, there: there, existing: existing)
            if best == nil || score > best!.score {
                best = (RoadLink(a: ends.0, b: ends.1, grade: grade), cost, score)
            }
        }
        guard let best else { return nil }
        return (best.link, best.cost)
    }

    /// **What a bridge adds to the price of a way that has to cross water.**
    ///
    /// Nearly double, and deliberately not more: rule 21 says a ladder whose
    /// rungs nobody can afford has no rungs, and a river that made a road
    /// unbuildable would simply be a wall drawn in blue. What it should be is
    /// a *reason to go round* — which is what a nine-tenths premium buys, since
    /// `wanted` scores every candidate edge against every other.
    static let bridgePremium = 1.9

    /// Whether a way between these two hexes has to get across the water.
    ///
    /// A road that runs **along the course** — from a hex to the one the water
    /// runs on to — follows the bank and needs no bridge. Anything else that
    /// touches a river hex has to cross it, because at this scale the water
    /// runs through the middle of the region and a road into that region meets
    /// it. See `RiverCourse`.
    public static func needsBridge(_ here: Region, _ there: Region) -> Bool {
        if here.river?.runsTo(there.coord) == true { return false }
        if there.river?.runsTo(here.coord) == true { return false }
        return here.river != nil || there.river != nil
    }

    /// **What laying `grade` on this edge costs.**
    ///
    /// One place, because three callers wanted it — the council, a road built
    /// toward a people, and a road the player lays — and a discount honoured in
    /// two of them is a discount that does not exist.
    public static func price(
        _ grade: RoadGrade, here: Region, there: Region, existing: RoadLink?
    ) -> Double {
        let country = max(TerrainCost.buildingCost(here), TerrainCost.buildingCost(there))
        // Building on a ruin is cheaper: the bed is cut and the stone is lying
        // there. This is the whole mechanical point of an ancient way.
        let discount = existing?.origin == .ancient ? ancientDiscount : 1
        // …and a bridge, where the water is. An ancient way already has one —
        // whoever cut that causeway got across somehow — so the discount and
        // the premium are allowed to meet.
        let water = needsBridge(here, there) ? bridgePremium : 1
        return grade.cost * country * discount * water
    }

    /// The next grade this world may lay on an edge that is currently at
    /// `current`. Gated by era *and* tech, so a road is something the colony
    /// learns to make rather than something it always could.
    ///
    /// **One rung at a time.** This used to hand back the best grade the world
    /// could reach, and `RoadProbe` showed what that does: by the time a colony
    /// had any traffic worth acting on it was modern, so the council laid
    /// *railways* across bare country and never built a road or a paved way in
    /// two hundred years. Three of the four grades were content nothing could
    /// ever produce.
    ///
    /// A colony beats a path, levels it into a road, paves the road and lays
    /// rail on the route that has earned it. Each step is cheap enough to be
    /// affordable when it is wanted, which is also rule 21: a ladder whose only
    /// rung is the dearest one is a ladder nobody climbs.
    static func nextGrade(after current: RoadGrade?, state: WorldState) -> RoadGrade? {
        let ladder: [RoadGrade] = [.road, .paved, .rail]
        func reachable(_ grade: RoadGrade) -> Bool {
            guard state.era >= grade.era else { return false }
            guard let tech = grade.requiresTech else { return true }
            return state.researchedTechs.contains(tech)
        }
        return ladder.first { grade in
            grade > (current ?? .track) && reachable(grade)
        }
    }

    /// Lays one road, if the colony can pay for it out of what it can spare.
    ///
    /// **A rate, not a store** (rule 16): the reserve is a multiple of the
    /// price of the thing being bought, never a share of the warehouse — a
    /// granary multiplies the cap, and a reserve that grows with the cap is a
    /// colony that can suddenly never afford anything again.
    public static func build(
        _ state: WorldState, registry: GameDataRegistry
    ) -> WorldState {
        guard let (link, cost) = wanted(in: state, registry: registry),
              let index = state.settlements.indices.first(where: { _ in true })
        else { return state }
        let purse = state.settlements[index].storage[.materials]
        guard purse >= cost * reserveMultiple else { return state }
        guard let paid = EffectApplier.payCost([.materials: cost], from: state,
                                               settlementID: state.settlements[index].id)
        else { return state }

        var s = paid
        s.roads.lay(link)
        let what = link.grade.displayName
        s.settlements[index].note(
            tick: s.tick, kind: .construction,
            text: LocalizedText(values: [
                .en: "A \(what.resolve(.en).lowercased()) now runs to the next country.",
                .cs: "K sousední krajině teď vede \(what.resolve(.cs).lowercased())."]))
        return s
    }

    // MARK: - What was here before

    /// How many stretches of ancient way a world is seeded with.
    static let ruinStretches = 2
    /// How long one of them runs, in hexes.
    static let ruinLengthRange = 3...5
    /// How far from the homeland a ruin may start. Close enough to be found,
    /// far enough that finding it is a journey.
    static let ruinMinDistanceFromHome = 3

    /// **Lays the roads that were here before anybody was.**
    ///
    /// A stretch of paved way running out of empty country into more empty
    /// country, with nothing at either end. `docs/ROADS.md` §7 asked for this
    /// and named the reason: it is a strong piece of world-telling, and the
    /// road system already has everything needed to say it.
    ///
    /// It is not decoration. An ancient way is faster to walk than the ground
    /// beside it (`RoadLink.effectiveSpeed` at `ancientFloor`), it does not rot
    /// any further, and building on it costs `ancientDiscount` of the price —
    /// so a colony that finds one has been handed a reason to expand *that*
    /// way rather than any other.
    ///
    /// Deterministic: everything is drawn from the map seed, so the ruins are
    /// in the same country on every launch of the same world. A ruin whose
    /// position moved between launches would break the one thing it is for,
    /// which is being a place.
    public static func seedRuins(
        _ roads: RoadNetwork, regions: [Region], homeland: HexCoord, mapSeed: UInt64
    ) -> RoadNetwork {
        var out = roads
        var rng = SeededRNG(seed: mapSeed ^ 0x0AD0_0AD0_0AD0_0AD0)
        let byCoord = Dictionary(regions.map { ($0.coord, $0) }) { first, _ in first }
        // Sorted, so the candidate list does not depend on the order regions
        // came out of the generator.
        let far = regions
            .filter { $0.coord.distance(to: homeland) >= ruinMinDistanceFromHome }
            .sorted { ($0.coord.q, $0.coord.r) < ($1.coord.q, $1.coord.r) }
        guard !far.isEmpty else { return out }

        for _ in 0..<ruinStretches {
            let start = far[Int(rng.next() % UInt64(far.count))].coord
            // One heading, held for the whole stretch: an old highway went
            // somewhere, and a drunkard's walk does not read as one.
            let heading = Int(rng.next() % 6)
            let length = ruinLengthRange.lowerBound
                + Int(rng.next() % UInt64(ruinLengthRange.count))

            var here = start
            for _ in 0..<length {
                let onwards = here.neighbors()
                guard heading < onwards.count else { break }
                let there = onwards[heading]
                // It stops where the map does, and it never touches the
                // homeland — the whole point of a ruin is that both its ends
                // are nowhere.
                guard byCoord[here] != nil, byCoord[there] != nil,
                      there != homeland else { break }
                out.lay(RoadLink(a: here, b: there, grade: .paved,
                                 condition: ancientFloor, origin: .ancient))
                here = there
            }
        }
        return out
    }

    // MARK: - What a war does to the ways

    /// **Cuts the road a warband walks in on.**
    ///
    /// `RoadNetwork.remove` has existed since the network did, and nothing
    /// called it — the model could lose a road and the world never did. This is
    /// the payoff `RegionFeature.pass` has been waiting for since it was
    /// written: a chokepoint only matters if holding it, or losing it, changes
    /// something.
    ///
    /// Not a random edge. Raiders wreck what is **on their own line of march**,
    /// and of that they wreck the piece that hurts most to lose — the one
    /// through the worst country, which is exactly the piece the colony paid
    /// the most to make (`TerrainCost.buildingCost`). A cut pass is a season's
    /// work and a long way round.
    ///
    /// A cut takes the way down one grade rather than deleting it: an
    /// embankment does not stop existing because somebody tore up the rails,
    /// and a colony that has to *repair* rather than *rebuild* has a decision
    /// worth making. A track has nothing under it and simply goes.
    ///
    /// Returns the state unchanged when there is nothing on their road to cut,
    /// which is the ordinary case for a colony that has built nothing.
    public static func cut(
        _ state: WorldState, from raiderRegionID: UUID?, to settlementID: UUID
    ) -> WorldState {
        guard let raiderRegionID,
              let from = state.regions.first(where: { $0.id == raiderRegionID }),
              let seat = state.settlements.first(where: { $0.id == settlementID })?.regionID,
              let target = state.regions.first(where: { $0.id == seat }),
              !state.roads.hasBuiltNothing
        else { return state }

        let byCoord = coordIndex(state)
        guard let march = state.roads.route(from: from.coord, to: target.coord,
                                            regions: byCoord) else { return state }

        // The dearest piece of made way on their line of march. Ancient stone
        // is not on the list: a raid is a blow against what *this* colony
        // built, and there is nothing to take from a road that fell before
        // anybody here was born.
        var worst: (link: RoadLink, cost: Double)?
        for (a, b) in zip(march.hexes, march.hexes.dropFirst()) {
            guard let link = state.roads.link(a, b), link.origin == .built else { continue }
            guard let here = byCoord[a], let there = byCoord[b] else { continue }
            let dearness = link.grade.cost
                * max(TerrainCost.buildingCost(here), TerrainCost.buildingCost(there))
            if worst == nil || dearness > worst!.cost { worst = (link, dearness) }
        }
        guard let worst else { return state }

        var s = state
        if let lower = fallback(from: worst.link.grade) {
            s.roads.update(RoadLink(a: worst.link.a, b: worst.link.b,
                                    grade: lower, condition: 0.35,
                                    origin: worst.link.origin))
        } else {
            s.roads.remove(worst.link.a, worst.link.b)
        }
        // Traffic remembers the lane, so the council will want to mend it
        // rather than forgetting the route existed.
        if let index = s.settlements.firstIndex(where: { $0.id == settlementID }) {
            let what = worst.link.grade.displayName
            s.settlements[index].note(
                tick: s.tick, kind: .danger,
                text: LocalizedText(values: [
                    .en: "They tore up the \(what.resolve(.en).lowercased()) behind them.",
                    .cs: "Za sebou strhli \(what.resolve(.cs).lowercased())."]))
        }
        return s
    }

    // MARK: - Helpers

    static func coordIndex(_ state: WorldState) -> [HexCoord: Region] {
        Dictionary(state.regions.map { ($0.coord, $0) }) { first, _ in first }
    }

    static func ends(of key: String) -> (HexCoord, HexCoord)? {
        let halves = key.split(separator: "|")
        guard halves.count == 2 else { return nil }
        func coord(_ part: Substring) -> HexCoord? {
            let parts = part.split(separator: ",")
            guard parts.count == 2, let q = Int(parts[0]), let r = Int(parts[1]) else { return nil }
            return HexCoord(q, r)
        }
        guard let a = coord(halves[0]), let b = coord(halves[1]) else { return nil }
        return (a, b)
    }
}
