import Foundation

/// Applies event/choice effects to the world. This is the *only* path through
/// which events change `WorldState` — the storyteller and the LLM narrator
/// never mutate state directly.
///
/// Scope semantics (Phase 1):
/// - `global` resource deltas apply to the capital settlement (index 0). With
///   a single settlement this is exact; multi-settlement distribution is a
///   Phase 2 refinement.
/// - `settlement:all` applies to every settlement.
/// - `settlement:any` / `settlement:closest` apply to the capital settlement.
public enum EffectApplier {
    public static func apply(
        _ effects: [EventEffect],
        to state: WorldState,
        registry: GameDataRegistry
    ) -> WorldState {
        effects.reduce(state) { apply($0, effect: $1, registry: registry) }
    }

    public static func apply(
        _ state: WorldState,
        effect: EventEffect,
        registry: GameDataRegistry
    ) -> WorldState {
        var s = state
        switch effect {
        case let .resourceDelta(resource, delta, scope, duration):
            if let duration, duration > 0 {
                // Spread the total delta evenly across the duration as a drip.
                let perTick = delta / Double(duration)
                s.scheduledEffects.append(
                    ScheduledEffect(
                        kind: .resource(resource: resource, perTick: perTick, scope: scope),
                        ticksRemaining: duration
                    )
                )
            } else {
                applyResourceDelta(&s, resource: resource, delta: delta, scope: scope)
            }
        case let .statDelta(path, delta):
            applyStatDelta(&s, path: path, delta: delta)
        case let .unlockTech(techID):
            if !s.researchedTechs.contains(techID) {
                s.researchedTechs.insert(techID)
                if let tech = registry.tech(techID) {
                    s = TechEngine.applyEffects(of: tech, to: s)
                }
            }
        case let .triggerEvent(eventID, delay):
            s.scheduledEffects.append(
                ScheduledEffect(
                    kind: .triggerEvent(eventID: eventID),
                    firesAtTick: s.tick + max(1, delay)
                )
            )
        case let .setWorldFlag(flag, value):
            s.worldFlags[flag] = value
        case let .pawnHealthDelta(delta, selector):
            applyToPawns(&s, selector: selector) { $0.health = clamp01_100($0.health + delta) }
        case let .pawnMoodDelta(delta, selector):
            applyToPawns(&s, selector: selector) { $0.mood = clamp01_100($0.mood + delta) }
        case .addPawn:
            addPawn(&s)
        case let .removePawn(selector):
            removePawn(&s, selector: selector)
        case let .regionHazardDelta(delta, selector):
            if let index = regionIndex(in: s, selector: selector) {
                s.regions[index].hazardLevel = max(0, s.regions[index].hazardLevel + delta)
            }
        case let .regionKindChange(kind, selector):
            if let index = regionIndex(in: s, selector: selector) {
                s.regions[index].kind = kind
            }
        case let .raid(strength):
            resolveRaid(&s, strength: strength)
        }
        return s
    }

    /// Resolves a raid against the capital's defense. If defended, it's
    /// repelled with a morale lift; otherwise the shortfall in defense
    /// determines the damage to resources, stability, morale and a colonist.
    /// Deterministic — no RNG.
    static func resolveRaid(_ s: inout WorldState, strength: Double) {
        guard let capital = s.settlements.indices.first else { return }

        // Defense = fortifications (walls/artifacts) + the colonists who muster
        // to fight. Armed colonists are far more effective.
        let militia = militiaDefense(s.settlements[capital].pawns)
        let effectiveDefense = s.settlements[capital].stats.defense + militia

        if effectiveDefense >= strength {
            s.settlements[capital].stats = s.settlements[capital].stats.applying(delta: 6, to: "morale")
            s.globalStats = s.globalStats.applying(delta: -8, to: "threatLevel")
            return
        }

        let deficit = strength - effectiveDefense
        applyResourceDelta(&s, resource: .materials, delta: -deficit * 4, scope: .global)
        applyResourceDelta(&s, resource: .food, delta: -deficit * 2, scope: .global)
        s.settlements[capital].stats = s.settlements[capital].stats
            .applying(delta: -deficit * 0.5, to: "stability")
            .applying(delta: -deficit * 0.3, to: "morale")
        s.globalStats = s.globalStats.applying(delta: -4, to: "threatLevel")

        // Casualties scale with how badly the defense was overrun, spread across
        // the most vulnerable defenders. Armed colonists take less harm.
        let woundCount = min(s.settlements[capital].pawns.count, max(1, Int(deficit / 18)))
        var deaths = 0
        for _ in 0..<woundCount {
            guard let pawnIndex = s.settlements[capital].pawns.indices
                .filter({ s.settlements[capital].pawns[$0].health > 0 })
                .min(by: { s.settlements[capital].pawns[$0].health < s.settlements[capital].pawns[$1].health }) else { break }
            var pawn = s.settlements[capital].pawns[pawnIndex]
            let armored = pawn.equipment[.weapon] != nil ? 0.5 : 1.0
            pawn.health = max(0, pawn.health - deficit * 1.5 * armored)
            s.settlements[capital].pawns[pawnIndex] = pawn
            if pawn.health <= 0 { deaths += 1 }
        }
        if deaths > 0 {
            s.settlements[capital].pawns.removeAll { $0.health <= 0 }
            s.settlements[capital].population = max(0, s.settlements[capital].population - Double(deaths))
            s.settlements[capital].stats = s.settlements[capital].stats.applying(delta: -10 * Double(deaths), to: "morale")
        }
    }

    /// The defensive value the colonists themselves provide: everyone fights a
    /// little, the armed fight much more, scaled by health; the broken don't.
    static func militiaDefense(_ pawns: [Pawn]) -> Double {
        pawns.reduce(0) { acc, pawn in
            guard !pawn.isBroken, pawn.health > 0 else { return acc }
            let armed = pawn.equipment[.weapon] != nil ? 6.0 : 0.0
            return acc + (2.0 + armed) * (pawn.health / 100)
        }
    }

    /// Deducts a cost from a settlement's storage if affordable. When
    /// `settlementID` is `nil` (or unknown) the cost is paid by the capital
    /// settlement — preserving the original capital-scoped behaviour used by
    /// event choices. Player actions that target a specific settlement
    /// (building, founding) pass that settlement's id so it pays its own way.
    /// Returns `nil` when the cost cannot be paid.
    public static func payCost(
        _ cost: Resources,
        from state: WorldState,
        settlementID: UUID? = nil
    ) -> WorldState? {
        let payerIndex: Int
        if let settlementID, let i = state.settlements.firstIndex(where: { $0.id == settlementID }) {
            payerIndex = i
        } else if let first = state.settlements.indices.first {
            payerIndex = first
        } else {
            return cost.amounts.isEmpty ? state : nil
        }
        var s = state
        var storage = s.settlements[payerIndex].storage
        for resource in ResourceType.allCases where cost[resource] > 0 {
            if storage[resource] < cost[resource] { return nil }
        }
        for resource in ResourceType.allCases where cost[resource] > 0 {
            storage[resource] = storage[resource] - cost[resource]
        }
        s.settlements[payerIndex].storage = storage
        return s
    }

    /// Applies an instant resource delta (used directly by the scheduled
    /// drip engine, and internally for non-duration effects).
    static func applyResourceDelta(
        _ s: inout WorldState,
        resource: ResourceType,
        delta: Double,
        scope: StatPath.Target
    ) {
        switch scope {
        case .settlementAll:
            s.settlements = s.settlements.map { settlement in
                var copy = settlement
                copy.storage[resource] = clampToStorage(copy.storage[resource] + delta, copy.storageCapacity)
                return copy
            }
        case .global, .settlementAny, .settlementClosest:
            guard let i = s.settlements.indices.first else { return }
            let cap = s.settlements[i].storageCapacity
            s.settlements[i].storage[resource] = clampToStorage(s.settlements[i].storage[resource] + delta, cap)
        }
    }

    private static func applyStatDelta(_ s: inout WorldState, path: StatPath, delta: Double) {
        switch path.target {
        case .global:
            s.globalStats = s.globalStats.applying(delta: delta, to: path.stat)
        case .settlementAll:
            s.settlements = s.settlements.map { settlement in
                var copy = settlement
                copy.stats = copy.stats.applying(delta: delta, to: path.stat)
                return copy
            }
        case .settlementAny, .settlementClosest:
            guard let i = s.settlements.indices.first else { return }
            s.settlements[i].stats = s.settlements[i].stats.applying(delta: delta, to: path.stat)
        }
    }

    private static func clampToStorage(_ value: Double, _ capacity: Double) -> Double {
        min(max(value, 0), capacity)
    }

    private static func clamp01_100(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }

    // MARK: - Pawn effects (capital settlement)

    /// Resolves which colonists a selector targets. Deterministic; ties resolve
    /// to the earliest index.
    static func selectedPawnIndices(_ pawns: [Pawn], _ selector: PawnSelector) -> [Int] {
        guard !pawns.isEmpty else { return [] }
        switch selector {
        case .all:
            return Array(pawns.indices)
        case .first:
            return [pawns.startIndex]
        case .lowestHealth:
            return [pawns.indices.min { pawns[$0].health < pawns[$1].health }!]
        case .lowestMood:
            return [pawns.indices.min { pawns[$0].mood < pawns[$1].mood }!]
        }
    }

    private static func applyToPawns(
        _ s: inout WorldState,
        selector: PawnSelector,
        _ transform: (inout Pawn) -> Void
    ) {
        guard let capital = s.settlements.indices.first else { return }
        for index in selectedPawnIndices(s.settlements[capital].pawns, selector) {
            transform(&s.settlements[capital].pawns[index])
        }
    }

    private static func addPawn(_ s: inout WorldState) {
        guard let capital = s.settlements.indices.first else { return }
        let seed = UInt64(bitPattern: Int64(s.tick)) &+ UInt64(s.settlements[capital].pawns.count) &+ 1
        s.settlements[capital].pawns.append(PawnFactory.generate(seed: seed))
        s.settlements[capital].population += 1
    }

    /// Resolves which region a dynamic event targets. Deterministic.
    static func regionIndex(in state: WorldState, selector: RegionSelector) -> Int? {
        let regions = state.regions
        switch selector {
        case .anyExplored:
            return regions.firstIndex { $0.explorationState != .unknown && $0.kind != .homeland }
        case .anyUnknown:
            return regions.firstIndex { $0.explorationState == .unknown }
        case .highestHazard:
            return regions.indices.max { regions[$0].hazardLevel < regions[$1].hazardLevel }
        case .lowestHazard:
            return regions.indices.min { regions[$0].hazardLevel < regions[$1].hazardLevel }
        }
    }

    private static func removePawn(_ s: inout WorldState, selector: PawnSelector) {
        guard let capital = s.settlements.indices.first else { return }
        let remove = Set(selectedPawnIndices(s.settlements[capital].pawns, selector))
        guard !remove.isEmpty else { return }
        s.settlements[capital].pawns = s.settlements[capital].pawns
            .enumerated()
            .filter { !remove.contains($0.offset) }
            .map(\.element)
        s.settlements[capital].population = max(0, s.settlements[capital].population - Double(remove.count))
    }
}
