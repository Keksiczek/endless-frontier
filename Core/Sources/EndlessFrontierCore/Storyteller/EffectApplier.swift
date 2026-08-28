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
            noteWhoItFellOn(&s, delta: delta, selector: selector)
        case let .pawnMoodDelta(delta, selector):
            // Into the *shift*, not into `mood` — `PawnEngine` derives mood from
            // needs every tick and wrote straight over this, so every authored
            // mood effect in the game lasted exactly one tick and was never
            // felt. See `Pawn.moodShift`.
            applyToPawns(&s, selector: selector) {
                $0.moodShift = min(PawnEngine.moodShiftLimit,
                                   max(-PawnEngine.moodShiftLimit, $0.moodShift + delta))
                $0.mood = clamp01_100($0.mood + delta)
            }
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
        case let .damageBuildings(kind, severity):
            resolveDamage(&s, kind: kind, severity: severity)
        }
        return s
    }

    /// Breaks things. What authored disasters use, so a storm or a fire leaves
    /// the town looking like it happened rather than merely costing goods.
    static func resolveDamage(
        _ s: inout WorldState, kind: BuildingEngine.DamageKind, severity: Double
    ) {
        guard let capital = s.settlements.indices.first else { return }
        var rng = SeededRNG(
            seed: s.mapSeed &+ UInt64(bitPattern: Int64(s.tick)) &+ 0x0D_A0_9A_6E)
        let result = BuildingEngine.damage(s.settlements[capital], kind: kind,
                                           severity: severity, rng: &rng)
        guard result.hit > 0 else { return }
        s.settlements[capital] = result.settlement
        let what = kind.displayName
        let entry: LocalizedText
        if result.ruined.isEmpty {
            entry = LocalizedText(values: [
                .en: "\(result.hit) buildings were knocked about by \(what.resolve(.en)).",
                .cs: "\(result.hit) staveb poničila \(what.resolve(.cs))."])
        } else {
            entry = LocalizedText(values: [
                .en: "\(what.resolve(.en).capitalized) left \(result.ruined.count) buildings in ruins.",
                .cs: "\(what.resolve(.cs).capitalized) nechala \(result.ruined.count) staveb v troskách."])
        }
        s.settlements[capital].note(tick: s.tick, kind: .danger, text: entry,
                                              subject: result.seat.map { .building($0) })
    }

    /// **A raid the player can answer**, in place of one that has already
    /// happened by the time they hear about it.
    ///
    /// This resolved the whole thing in one step and left a `BattleLog` — so a
    /// storyteller raid was announced by its own report card, and the fight it
    /// described was over. Keks, watching for one: *"to, co vyskočí, když na
    /// tebe teď zaútočí, nevidím — jen jinou, že nájezd odražen nebo ne."* He
    /// was not missing it; there was nothing to miss.
    ///
    /// `SiegeEngine.begin` has said what to do about it since it was written —
    /// *"a raid becomes a siege where somebody might be watching"* — and every
    /// other raid in the game goes through it. This one now does too, so all
    /// raids are the same thing: a line forms, the warband comes on, and the
    /// player who is here can order the defence. Nobody watching costs nothing:
    /// `ActionLoop` fights the steps out on the world clock and `conclude`
    /// leaves the same record the report card reads.
    static func resolveRaid(_ s: inout WorldState, strength: Double, registry: GameDataRegistry) {
        guard let capital = s.settlements.indices.first else { return }
        let raiderName = s.language == .cs ? "Nájezdníci" : "Raiders"
        // One raid at a time on one colony: a second warband arriving while the
        // first is still at the wall would overwrite the fight in progress.
        guard s.settlements[capital].siege == nil else { return }
        s.settlements[capital] = SiegeEngine.begin(
            s.settlements[capital],
            attackerStrength: strength,
            attackerName: raiderName,
            attackerLabel: LocalizedText(values: [.en: "Raiders", .cs: "Nájezdníci"]),
            fortification: s.settlements[capital].stats.defense,
            tick: s.tick,
            registry: registry,
            // Deterministic from (mapSeed, tick), exactly as the resolved raid
            // was: the same world rolls the same warband.
            seed: s.mapSeed &+ UInt64(bitPattern: Int64(s.tick)) &+ 0x5241_4944,
            era: s.era,
            language: s.language)
        s.globalStats = s.globalStats.applying(delta: -4, to: "threatLevel")
        s.settlements[capital].note(tick: s.tick, kind: .danger, text: LocalizedText(values: [
            .en: "\(raiderName) are at the edge of the fields.",
            .cs: "\(raiderName) stojí na kraji polí."]))
    }

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
                copy.storage[resource] = clampToStorage(copy.storage[resource] + delta, copy.storageCapacity[resource])
                return copy
            }
        case .global, .settlementAny, .settlementClosest:
            guard let i = s.settlements.indices.first else { return }
            let cap = s.settlements[i].storageCapacity[resource]
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

    /// Says out loud who a disaster actually landed on.
    ///
    /// An event that takes eight points of health off "the colonist in the worst
    /// way" is a thing that happened *to somebody*, and until this it was a
    /// number moving in a struct: the chronicle carried the drought and never the
    /// person who nearly died of it. Only for a picked colonist — a delta on
    /// `all` is the weather, and the weather does not have a name.
    private static func noteWhoItFellOn(
        _ s: inout WorldState, delta: Double, selector: PawnSelector
    ) {
        guard delta < 0, selector != .all,
              let capital = s.settlements.indices.first,
              let index = selectedPawnIndices(s.settlements[capital].pawns, selector).first
        else { return }
        let who = s.settlements[capital].pawns[index]
        let text: LocalizedText = who.health <= 0
            ? LocalizedText(values: [
                .en: "\(who.name) did not come through it.",
                .cs: "\(who.name) to nepřežil(a)."])
            : LocalizedText(values: [
                .en: "\(who.name) came off worst, and is a while mending.",
                .cs: "\(who.name) to odnesl(a) nejhůř a chvíli se bude sbírat."])
        s.settlements[capital].note(tick: s.tick, kind: .danger, text: text,
                                    subject: .pawn(who.id), keptBy: [who.id])
    }

    private static func addPawn(_ s: inout WorldState) {
        guard let capital = s.settlements.indices.first else { return }
        let seed = UInt64(bitPattern: Int64(s.tick)) &+ UInt64(s.settlements[capital].pawns.count) &+ 1
        // Whoever an event brings in comes from **this country**, as far as the
        // game knows — an event does not say which people they walked from. So
        // they resemble the colony rather than being a fresh roll at mean 0.5,
        // which would quietly reset the world's dispositions toward the middle
        // every time the storyteller was generous. See `Genes.drawn(from:using:)`.
        let stock = Genes.mean(of: s.settlements[capital].pawns.map(\.genes))
        s.settlements[capital].pawns.append(
            PawnFactory.generate(seed: seed, language: s.language, stock: stock))
        s.settlements[capital].arrivalTally += 1
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
