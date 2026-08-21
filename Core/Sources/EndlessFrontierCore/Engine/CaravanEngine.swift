import Foundation

/// Dispatches and advances caravans: escorted batch shipments that travel
/// between settlements over several ticks, risk ambush on the road, and deliver
/// their cargo and surviving guards to the destination. Fully deterministic —
/// ambush rolls come from a `SeededRNG` keyed on (mapSeed, caravan, tick).
public enum CaravanEngine {
    /// Who the record says fell on the wagons, and who held them.
    static let ambusherName = LocalizedText(values: [.en: "Bandits", .cs: "Lupiči"])
    static let escortName = LocalizedText(values: [.en: "The escort", .cs: "Doprovod"])

    // Tuning (first-pass constants; candidates for world-config later).
    static let ticksPerHex = 3
    static let minTravelTicks = 2
    static let fallbackTravelTicks = 4
    static let baseAmbushStrength = 8.0
    static let ambushThreatScale = 0.25
    static let maxAmbushChance = 0.4
    static let woundSeverity = 1.5

    /// Travel time between two settlements, from the hex distance of their
    /// regions (a fallback covers settlements without a placed region).
    ///
    /// **The road reads the yard.** Second of the two travel seams in
    /// `docs/MOUNTS_AND_VEHICLES.md`, and the same conversion as the first:
    /// this counts *ticks per hex*, so a conveyance's `regionPace` — which is
    /// stated as a speed — divides rather than multiplies. `registry` is
    /// optional so the many callers that only want the geography keep working;
    /// pass it and the caravan travels at what the origin has to send it with.
    public static func travelTicks(
        from origin: Settlement, to destination: Settlement, in state: WorldState,
        registry: GameDataRegistry? = nil
    ) -> Int {
        guard let o = region(of: origin, in: state), let d = region(of: destination, in: state) else {
            let pace = registry.map { StableEngine.bestRegionPace(origin, registry: $0) } ?? 1
            return max(minTravelTicks, Int((Double(fallbackTravelTicks) / max(0.1, pace)).rounded()))
        }
        // **The country between them.** A cart that cannot take marsh cannot
        // take the road through the fens, so the pace this journey gets is the
        // pace of the best thing in the yard that can actually make it — not
        // the best thing in the yard.
        let crossed = countryBetween(o, d, in: state)
        let pace = registry.map {
            StableEngine.bestRegionPace(origin, crossing: crossed, registry: $0)
        } ?? 1
        // **Over the roads, where there are any.** `RoadNetwork.route` returns
        // the journey in plain-hex equivalents, so hard country costs more than
        // one hex and a made way through it costs less — which is the whole
        // reason to build one. An empty network routes across open ground and
        // comes back to what this used to be.
        //
        // The route already knows what is travelling, so the pace is **not**
        // divided out again here: the first cut of this did, and a lorry got
        // its own speed applied twice.
        let plain = Double(ticksPerHex) * crossing(from: o, to: d, in: state, pace: pace)
        return max(minTravelTicks, Int(plain.rounded()))
    }

    /// The journey in plain-hexes **for this traveller**: over the network if it
    /// can be routed, and straight-line otherwise (an unexplored corner of the
    /// map, or a world that has not laid a stone yet).
    ///
    /// The mover's own speed is applied inside `RoadNetwork.stepCost`, where it
    /// can differ by what it is standing on — which is the point of paving. The
    /// fallback has no ground to stand on, so it divides plainly.
    static func crossing(
        from origin: Region, to destination: Region, in state: WorldState, pace: Double
    ) -> Double {
        let byCoord = Dictionary(state.regions.map { ($0.coord, $0) }) { first, _ in first }
        let mover: RoadNetwork.Mover = pace > 1.05 ? .wheeled(pace: pace) : .onFoot
        if let route = state.roads.route(from: origin.coord, to: destination.coord,
                                         regions: byCoord, mover: mover) {
            return route.cost
        }
        return Double(origin.coord.distance(to: destination.coord)) / max(0.1, pace)
    }

    /// The hexes a caravan will actually pass through, so whoever dispatched it
    /// can record that somebody went that way. Roads appear where the world
    /// travels; this is the half that says where that was.
    public static func routeHexes(
        from origin: Settlement, to destination: Settlement, in state: WorldState
    ) -> [HexCoord] {
        guard let o = region(of: origin, in: state),
              let d = region(of: destination, in: state) else { return [] }
        let byCoord = Dictionary(state.regions.map { ($0.coord, $0) }) { first, _ in first }
        return state.roads.route(from: o.coord, to: d.coord, regions: byCoord)?.hexes ?? []
    }

    /// The biomes a road between two regions runs through.
    ///
    /// A straight line over the hex grid rather than a path-find: the world map
    /// has no roads yet, and what this is for is asking *what country is in the
    /// way*, which a line answers as well as a route would. Regions the world
    /// does not have are skipped rather than guessed at.
    static func countryBetween(
        _ from: Region, _ to: Region, in state: WorldState
    ) -> [String] {
        let steps = max(1, from.coord.distance(to: to.coord))
        let a = Bearing.plane(from.coord), b = Bearing.plane(to.coord)
        var out: [String] = [from.biomeID, to.biomeID]
        for i in 1..<steps {
            let t = Double(i) / Double(steps)
            let x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t
            // Back to axial, and to the nearest hex.
            let r = (y / 0.866_025_4).rounded()
            let q = (x - r / 2).rounded()
            let coord = HexCoord(Int(q), Int(r))
            if let region = state.regions.first(where: { $0.coord == coord }) {
                out.append(region.biomeID)
            }
        }
        return out
    }

    /// Whether a caravan can be dispatched with the given cargo and escort.
    public static func canDispatch(
        _ state: WorldState,
        originID: UUID,
        destinationID: UUID,
        resource: ResourceType,
        amount: Double,
        guardIDs: [UUID]
    ) -> Bool {
        guard originID != destinationID, amount > 0, !guardIDs.isEmpty,
              let origin = state.settlements.first(where: { $0.id == originID }),
              state.settlements.contains(where: { $0.id == destinationID }),
              origin.storage[resource] >= amount else { return false }
        let guardSet = Set(guardIDs)
        return origin.pawns.contains { guardSet.contains($0.id) }
    }

    /// Sends a caravan: pulls cargo and the chosen guards out of the origin,
    /// then schedules its arrival. Returns unchanged state if it can't dispatch.
    public static func dispatch(
        _ state: WorldState,
        originID: UUID,
        destinationID: UUID,
        resource: ResourceType,
        amount: Double,
        guardIDs: [UUID],
        /// Optional so every existing caller keeps working; with it, the
        /// caravan travels at what the origin's yard can send it out with.
        registry: GameDataRegistry? = nil
    ) -> WorldState {
        guard canDispatch(state, originID: originID, destinationID: destinationID,
                          resource: resource, amount: amount, guardIDs: guardIDs),
              let oi = state.settlements.firstIndex(where: { $0.id == originID }) else { return state }

        var s = state
        let guardSet = Set(guardIDs)
        let guards = s.settlements[oi].pawns.filter { guardSet.contains($0.id) }
        // Remove guards and cargo from the origin.
        s.settlements[oi].pawns.removeAll { guardSet.contains($0.id) }
        s.settlements[oi].storage[resource] = s.settlements[oi].storage[resource] - amount

        let destination = s.settlements.first { $0.id == destinationID }!
        let ticks = travelTicks(from: s.settlements[oi], to: destination, in: s,
                                registry: registry)
        var rng = SeededRNG(seed: dispatchSeed(state: s, originID: originID, destinationID: destinationID))
        let caravan = Caravan(
            id: rng.nextUUID(),
            originID: originID,
            destinationID: destinationID,
            resource: resource,
            cargo: amount,
            guards: guards,
            ticksRemaining: ticks,
            totalTicks: ticks
        )
        s.caravans.append(caravan)
        // Somebody went this way. Enough of them and the ground is a track;
        // enough traffic through bad country and the council pays to make it a
        // road. See `RoadEngine`.
        s = RoadEngine.travelled(s, route: routeHexes(from: s.settlements[oi],
                                                     to: destination, in: s))
        return s
    }

    /// Advances every in-flight caravan by one tick: rolls for ambush, then
    /// either delivers (on arrival), drops it (if wiped out), or keeps it
    /// traveling. Returns chronicle entries for ambushes, losses and arrivals
    /// so the "while you were away" summary can report them.
    public static func advanceOneTick(_ state: WorldState, registry: GameDataRegistry) -> PlannerResult {
        guard !state.caravans.isEmpty else { return PlannerResult(state: state, fired: []) }
        var s = state
        var stillTraveling: [Caravan] = []
        var fired: [HistoricalEvent] = []
        for var caravan in s.caravans {
            caravan.ticksRemaining -= 1
            let originMercantile = s.settlements.first { $0.id == caravan.originID }?.specialization == .mercantile
            resolveTravelTick(&caravan, threat: s.globalStats.threatLevel,
                              originMercantile: originMercantile, mapSeed: s.mapSeed, tick: s.tick,
                              registry: registry)

            // An escort wiped out on the road means the caravan is taken: cargo
            // and any survivors are lost.
            if caravan.guards.isEmpty {
                fired.append(HistoricalEvent(templateID: "caravan_lost", type: .disaster, tick: s.tick))
                continue
            }
            switch caravan.status {
            case .raided:
                fired.append(HistoricalEvent(templateID: "caravan_ambushed", type: .threat, tick: s.tick))
            case .skirmished:
                fired.append(HistoricalEvent(templateID: "caravan_skirmish", type: .flavor, tick: s.tick))
            case .traveling:
                break
            }

            if caravan.ticksRemaining <= 0 {
                deliver(caravan, into: &s)
                fired.append(HistoricalEvent(templateID: "caravan_arrived", type: .opportunity, tick: s.tick))
            } else {
                stillTraveling.append(caravan)
            }
        }
        s.caravans = stillTraveling
        return PlannerResult(state: s, fired: fired)
    }

    // MARK: - Internals

    static func region(of settlement: Settlement, in state: WorldState) -> Region? {
        settlement.regionID.flatMap { id in state.regions.first { $0.id == id } }
    }

    /// One leg of travel: maybe an ambush, resolved against the escort's
    /// militia strength. Cargo bleeds and the weakest guard is wounded when the
    /// raiders break through.
    static func resolveTravelTick(
        _ caravan: inout Caravan,
        threat: Double,
        originMercantile: Bool,
        mapSeed: UInt64,
        tick: Int,
        registry: GameDataRegistry = GameDataRegistry()
    ) {
        var rng = SeededRNG(seed: travelSeed(caravanID: caravan.id, mapSeed: mapSeed, tick: tick))
        let chance = ambushChance(threat: threat, guards: caravan.guards, originMercantile: originMercantile)
        guard rng.nextUnit() < chance else {
            caravan.status = .traveling
            return
        }
        applyAmbush(&caravan, threat: threat, registry: registry, tick: tick)
    }

    /// Per-tick ambush probability. Rises with threat, but a skilled trading
    /// escort (the `trade` skill) and a mercantile home settlement both keep
    /// the roads safer — so investment in trade pays off in fewer raids.
    static func ambushChance(threat: Double, guards: [Pawn], originMercantile: Bool) -> Double {
        let base = max(0, threat / 100 * 0.3)
        let avgTrade = guards.isEmpty ? 0
            : Double(guards.map { $0.skill(.trade) }.reduce(0, +)) / Double(guards.count)
        let skillFactor = max(0.4, 1 - avgTrade * 0.05)   // each trade level −5%, floored at −60%
        let mercantileFactor = originMercantile ? 0.6 : 1.0
        return min(maxAmbushChance, base * skillFactor * mercantileFactor)
    }

    /// Resolves an ambush that *has* occurred against the escort's militia
    /// strength. Split out from the roll so the combat maths is deterministic
    /// and directly testable.
    static func applyAmbush(_ caravan: inout Caravan, threat: Double,
                            registry: GameDataRegistry = GameDataRegistry(),
                            tick: Int = 0) {
        var record = CombatEngine.BattleRecorder()
        let strength = baseAmbushStrength + threat * ambushThreatScale
        // The escort's arms count for real now: bows soften the ambush before
        // it closes, blades hold the wagons.
        let militia = CombatEngine.militia(caravan.guards, registry: registry)
        let defense = militia.melee + militia.ranged * 0.9
        if militia.ranged > 0 { record.record(.volley, step: 0, amount: militia.ranged * 0.9) }
        record.record(.charge, step: 1, amount: strength)
        record.record(.clash, step: 2, amount: defense)
        if defense >= strength {
            caravan.status = .skirmished   // escort beat them off
            record.record(.repelled, step: 3)
            caravan.lastBattle = record.finish(
                id: caravan.id, tick: tick, attackerName: ambusherName.resolve(.en),
                defenderName: escortName.resolve(.en), repelled: true)
            return
        }

        let deficit = strength - defense
        let lossFraction = min(1, deficit / strength)
        let lost = caravan.cargo * lossFraction
        caravan.cargo = max(0, caravan.cargo - lost)

        if lost > 0 { record.record(.plunder, step: 3, amount: lost) }
        if let weakest = caravan.guards.indices.min(by: { caravan.guards[$0].health < caravan.guards[$1].health }) {
            let mult = CombatEngine.woundMultiplier(caravan.guards[weakest])
            caravan.guards[weakest].health = max(0, caravan.guards[weakest].health - deficit * woundSeverity * mult)
            let hurt = caravan.guards[weakest]
            record.record(hurt.health <= 0 ? .death : .wound, step: 4, pawnID: hurt.id,
                          pawnName: hurt.name, amount: deficit * woundSeverity * mult)
        }
        caravan.guards.removeAll { $0.health <= 0 }
        caravan.status = .raided
        caravan.lastBattle = record.finish(
            id: caravan.id, tick: tick, attackerName: ambusherName.resolve(.en),
            defenderName: escortName.resolve(.en), repelled: false)
    }

    /// Deposits cargo (clamped to storage room) and settles the surviving
    /// guards into the destination — a caravan also migrates colonists.
    ///
    /// A caravan to a *full* store used to burn its whole load: the cargo left
    /// the origin at dispatch, `min(cargo, room)` with `room == 0` delivered
    /// nothing, and the goods simply vanished — "the caravans leave but never
    /// send any goods." Now whatever the destination has no room for comes back
    /// to the origin instead of being destroyed.
    static func deliver(_ caravan: Caravan, into s: inout WorldState) {
        guard let di = s.settlements.firstIndex(where: { $0.id == caravan.destinationID }) else { return }
        let room = max(0, s.settlements[di].storageCapacity[caravan.resource] - s.settlements[di].storage[caravan.resource])
        let delivered = min(caravan.cargo, room)
        s.settlements[di].storage[caravan.resource] += delivered
        s.settlements[di].pawns.append(contentsOf: caravan.guards)

        // Return the undeliverable remainder to the origin rather than losing it.
        let returned = caravan.cargo - delivered
        if returned > 0, let oi = s.settlements.firstIndex(where: { $0.id == caravan.originID }) {
            let originRoom = max(0, s.settlements[oi].storageCapacity[caravan.resource] - s.settlements[oi].storage[caravan.resource])
            s.settlements[oi].storage[caravan.resource] += min(returned, originRoom)
        }
    }

    private static func dispatchSeed(state: WorldState, originID: UUID, destinationID: UUID) -> UInt64 {
        var h: UInt64 = state.mapSeed &* 0x9E37_79B9_7F4A_7C15
        h = (h ^ UInt64(bitPattern: Int64(state.tick))) &* 0x0100_0000_01B3
        h = h ^ hash(originID) ^ (hash(destinationID) &* 0x9E37_79B9)
        h = h &+ UInt64(state.caravans.count)
        return h ^ (h >> 29)
    }

    private static func travelSeed(caravanID: UUID, mapSeed: UInt64, tick: Int) -> UInt64 {
        var h: UInt64 = mapSeed &* 0x9E37_79B9_7F4A_7C15
        h = h ^ hash(caravanID)
        h = (h ^ UInt64(bitPattern: Int64(tick))) &* 0x0100_0000_01B3
        return h ^ (h >> 29)
    }

    private static func hash(_ uuid: UUID) -> UInt64 {
        let b = uuid.uuid
        let hi = UInt64(b.0) << 56 | UInt64(b.1) << 48 | UInt64(b.2) << 40 | UInt64(b.3) << 32
              | UInt64(b.4) << 24 | UInt64(b.5) << 16 | UInt64(b.6) << 8 | UInt64(b.7)
        let lo = UInt64(b.8) << 56 | UInt64(b.9) << 48 | UInt64(b.10) << 40 | UInt64(b.11) << 32
              | UInt64(b.12) << 24 | UInt64(b.13) << 16 | UInt64(b.14) << 8 | UInt64(b.15)
        return hi ^ (lo &* 0x9E37_79B9_7F4A_7C15)
    }
}
