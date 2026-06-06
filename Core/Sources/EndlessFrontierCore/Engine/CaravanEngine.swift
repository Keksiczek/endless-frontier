import Foundation

/// Dispatches and advances caravans: escorted batch shipments that travel
/// between settlements over several ticks, risk ambush on the road, and deliver
/// their cargo and surviving guards to the destination. Fully deterministic —
/// ambush rolls come from a `SeededRNG` keyed on (mapSeed, caravan, tick).
public enum CaravanEngine {
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
    public static func travelTicks(from origin: Settlement, to destination: Settlement, in state: WorldState) -> Int {
        guard let o = region(of: origin, in: state), let d = region(of: destination, in: state) else {
            return fallbackTravelTicks
        }
        return max(minTravelTicks, o.coord.distance(to: d.coord) * ticksPerHex)
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
        guardIDs: [UUID]
    ) -> WorldState {
        guard canDispatch(state, originID: originID, destinationID: destinationID,
                          resource: resource, amount: amount, guardIDs: guardIDs),
              let oi = state.settlements.firstIndex(where: { $0.id == originID }) else { return state }

        var s = state
        let guardSet = Set(guardIDs)
        let guards = s.settlements[oi].pawns.filter { guardSet.contains($0.id) }
        // Remove guards and cargo from the origin.
        s.settlements[oi].pawns.removeAll { guardSet.contains($0.id) }
        s.settlements[oi].population = max(0, s.settlements[oi].population - Double(guards.count))
        s.settlements[oi].storage[resource] = s.settlements[oi].storage[resource] - amount

        let destination = s.settlements.first { $0.id == destinationID }!
        let ticks = travelTicks(from: s.settlements[oi], to: destination, in: s)
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
        return s
    }

    /// Advances every in-flight caravan by one tick: rolls for ambush, then
    /// either delivers (on arrival), drops it (if wiped out), or keeps it
    /// traveling.
    public static func advanceOneTick(_ state: WorldState, registry: GameDataRegistry) -> WorldState {
        guard !state.caravans.isEmpty else { return state }
        var s = state
        var stillTraveling: [Caravan] = []
        for var caravan in s.caravans {
            caravan.ticksRemaining -= 1
            resolveTravelTick(&caravan, threat: s.globalStats.threatLevel, mapSeed: s.mapSeed, tick: s.tick)

            // An escort wiped out on the road means the caravan is taken: cargo
            // and any survivors are lost.
            if caravan.guards.isEmpty { continue }

            if caravan.ticksRemaining <= 0 {
                deliver(caravan, into: &s)
            } else {
                stillTraveling.append(caravan)
            }
        }
        s.caravans = stillTraveling
        return s
    }

    // MARK: - Internals

    static func region(of settlement: Settlement, in state: WorldState) -> Region? {
        settlement.regionID.flatMap { id in state.regions.first { $0.id == id } }
    }

    /// One leg of travel: maybe an ambush, resolved against the escort's
    /// militia strength. Cargo bleeds and the weakest guard is wounded when the
    /// raiders break through.
    static func resolveTravelTick(_ caravan: inout Caravan, threat: Double, mapSeed: UInt64, tick: Int) {
        var rng = SeededRNG(seed: travelSeed(caravanID: caravan.id, mapSeed: mapSeed, tick: tick))
        let chance = min(maxAmbushChance, max(0, threat / 100 * 0.3))
        guard rng.nextUnit() < chance else {
            caravan.status = .traveling
            return
        }
        applyAmbush(&caravan, threat: threat)
    }

    /// Resolves an ambush that *has* occurred against the escort's militia
    /// strength. Split out from the roll so the combat maths is deterministic
    /// and directly testable.
    static func applyAmbush(_ caravan: inout Caravan, threat: Double) {
        let strength = baseAmbushStrength + threat * ambushThreatScale
        let defense = EffectApplier.militiaDefense(caravan.guards)
        if defense >= strength {
            caravan.status = .skirmished   // escort beat them off
            return
        }

        let deficit = strength - defense
        let lossFraction = min(1, deficit / strength)
        caravan.cargo = max(0, caravan.cargo * (1 - lossFraction))

        if let weakest = caravan.guards.indices.min(by: { caravan.guards[$0].health < caravan.guards[$1].health }) {
            let armored = caravan.guards[weakest].equipment[.weapon] != nil ? 0.5 : 1.0
            caravan.guards[weakest].health = max(0, caravan.guards[weakest].health - deficit * woundSeverity * armored)
        }
        caravan.guards.removeAll { $0.health <= 0 }
        caravan.status = .raided
    }

    /// Deposits cargo (clamped to storage room) and settles the surviving
    /// guards into the destination — a caravan also migrates colonists.
    static func deliver(_ caravan: Caravan, into s: inout WorldState) {
        guard let di = s.settlements.firstIndex(where: { $0.id == caravan.destinationID }) else { return }
        let room = max(0, s.settlements[di].storageCapacity - s.settlements[di].storage[caravan.resource])
        s.settlements[di].storage[caravan.resource] = s.settlements[di].storage[caravan.resource] + min(caravan.cargo, room)
        s.settlements[di].pawns.append(contentsOf: caravan.guards)
        s.settlements[di].population += Double(caravan.guards.count)
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
