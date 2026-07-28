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
            resolveRaid(&s, strength: strength, registry: registry)
        }
        return s
    }

    /// Resolves a raid against the capital's defense. If defended, it's
    /// repelled with a morale lift; otherwise the shortfall in defense
    /// determines the damage to resources, stability, morale and colonists.
    ///
    /// The *numbers* are one deterministic step, unchanged — but the raid now
    /// also leaves a `BattleLog`, the same record a tribe's raid does, so the
    /// canvas can play it out and the report can lay out its cost. A storyteller
    /// raid was the one fight that resolved invisibly; now it shows.
    static func resolveRaid(_ s: inout WorldState, strength: Double, registry: GameDataRegistry) {
        guard let capital = s.settlements.indices.first else { return }
        let raiderName = s.language == .cs ? "Nájezdníci" : "Raiders"
        let defenderName = s.settlements[capital].name
        // A deterministic id/seed from (mapSeed, tick): the record is identical
        // on identical input, so the raid stays reproducible.
        var rng = SeededRNG(seed: s.mapSeed &+ UInt64(bitPattern: Int64(s.tick)) &+ 0x5241_4944)
        var record = CombatEngine.BattleRecorder()

        // Defense = fortifications (walls/artifacts) + the colonists who
        // muster to fight — real arms weighed by class (see `CombatEngine`),
        // with the ranged half loosing a volley before the clash.
        let militia = CombatEngine.militia(s.settlements[capital].pawns, registry: registry)
        let softened = max(0, strength - militia.ranged * 0.8)
        let effectiveDefense = s.settlements[capital].stats.defense + militia.melee + militia.ranged * 0.2

        // The opening volley (if anyone can shoot), then the charge onto the line.
        if militia.ranged > 0 { record.record(.volley, step: 0, amount: militia.ranged * 0.8) }
        record.record(.charge, step: 0, amount: strength)
        record.record(.clash, step: 1, amount: effectiveDefense)

        // Who turns out to meet them, garrison first — the same line the canvas
        // sends running to the wall.
        let muster = s.settlements[capital].pawns
            .filter { $0.health > 0 && !$0.isBroken && !$0.isAway }
            .sorted { ($0.assignedWork == .garrison ? 0 : 1) < ($1.assignedWork == .garrison ? 0 : 1) }
            .prefix(12).map(\.id)

        if effectiveDefense >= softened {
            record.record(.repelled, step: 2)
            let id = rng.nextUUID()
            let approach = rng.nextUnit() * 2 * .pi
            s.settlements[capital].lastBattle = record.finish(
                id: id, tick: s.tick,
                attackerName: raiderName, defenderName: defenderName, repelled: true,
                approach: approach, attackers: BattleResolver.drawnStrength(strength),
                line: Array(muster))
            s.settlements[capital].stats = s.settlements[capital].stats.applying(delta: 6, to: "morale")
            s.globalStats = s.globalStats.applying(delta: -8, to: "threatLevel")
            s.settlements[capital].journal.append(tick: s.tick, kind: .danger, text: LocalizedText(values: [
                .en: "\(raiderName) came for \(defenderName) — the wall held and turned them back.",
                .cs: "\(raiderName) přišli na \(defenderName) — hradba vydržela a zahnala je."]))
            return
        }

        let deficit = softened - effectiveDefense
        applyResourceDelta(&s, resource: .materials, delta: -deficit * 4, scope: .global)
        applyResourceDelta(&s, resource: .food, delta: -deficit * 2, scope: .global)
        record.record(.plunder, step: 5, amount: deficit * 6)
        s.settlements[capital].stats = s.settlements[capital].stats
            .applying(delta: -deficit * 0.5, to: "stability")
            .applying(delta: -deficit * 0.3, to: "morale")
        s.globalStats = s.globalStats.applying(delta: -4, to: "threatLevel")

        // Casualties scale with how badly the defense was overrun, spread across
        // the most vulnerable defenders. Armed colonists take less harm.
        let woundCount = min(s.settlements[capital].pawns.count, max(1, Int(deficit / 18)))
        var deaths = 0
        var woundStep = 2
        for _ in 0..<woundCount {
            guard let pawnIndex = s.settlements[capital].pawns.indices
                .filter({ s.settlements[capital].pawns[$0].health > 0 })
                .min(by: { s.settlements[capital].pawns[$0].health < s.settlements[capital].pawns[$1].health }) else { break }
            var pawn = s.settlements[capital].pawns[pawnIndex]
            // Armor, not a weapon, is what blunts the blow you receive.
            let dealt = deficit * 1.5 * CombatEngine.woundMultiplier(pawn)
            pawn.health = max(0, pawn.health - dealt)
            let killed = pawn.health <= 0
            record.record(killed ? .death : .wound, step: min(4, woundStep),
                          pawnID: pawn.id, pawnName: pawn.name, amount: dealt)
            woundStep += 1
            s.settlements[capital].pawns[pawnIndex] = pawn
            if killed { deaths += 1 }
        }
        if deaths > 0 {
            s.settlements[capital].pawns.removeAll { $0.health <= 0 }
            s.settlements[capital].deathTallies[PawnDeathCause.battle.rawValue, default: 0] += deaths
            s.settlements[capital].stats = s.settlements[capital].stats.applying(delta: -10 * Double(deaths), to: "morale")
        }

        let id = rng.nextUUID()
        let approach = rng.nextUnit() * 2 * .pi
        s.settlements[capital].lastBattle = record.finish(
            id: id, tick: s.tick,
            attackerName: raiderName, defenderName: defenderName, repelled: false,
            approach: approach, attackers: BattleResolver.drawnStrength(strength),
            line: Array(muster))
        // The day, on the record — a raid resolved off-screen still tells you.
        let entry: LocalizedText
        if deaths > 0 {
            entry = LocalizedText(values: [
                .en: "\(raiderName) broke into \(defenderName) — \(deaths) of ours fell and the stores are lighter.",
                .cs: "\(raiderName) prolomili obranu \(defenderName) — \(deaths) našich padlo a zásoby jsou lehčí."])
        } else {
            entry = LocalizedText(values: [
                .en: "\(raiderName) broke the line at \(defenderName) and carried off part of the stores.",
                .cs: "\(raiderName) prorazili obranu \(defenderName) a odnesli část zásob."])
        }
        s.settlements[capital].journal.append(tick: s.tick, kind: .danger, text: entry)
    }

    /// The defensive value the colonists themselves provide. Delegates to
    /// `CombatEngine`, which weighs real arms by class instead of the old
    /// flat +6 for anything in the weapon slot.
    static func militiaDefense(_ pawns: [Pawn], registry: GameDataRegistry) -> Double {
        CombatEngine.defensePower(pawns, registry: registry)
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
        s.settlements[capital].pawns.append(PawnFactory.generate(seed: seed, language: s.language))
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
    }
}
