import Foundation

/// High-level façade the app talks to. Wraps the deterministic engines and
/// player actions. All methods are pure: they take a state and return a new
/// one, so the UI layer can drive persistence and observation as it sees fit.
public enum GameEngine {
    // MARK: - Session lifecycle

    /// Opens a session: advances the world by the real time elapsed since the
    /// last session (capped), then stamps `lastRealTimestamp = now`.
    public static func openSession(
        _ state: WorldState,
        now: Date,
        registry: GameDataRegistry
    ) -> PlannerResult {
        let ticks = TickEngine.ticksElapsed(since: state.lastRealTimestamp, until: now, config: registry.config)
        var result = TickEngine.advance(state, ticks: ticks, registry: registry)
        result.state.lastRealTimestamp = now
        return result
    }

    // MARK: - Player actions

    /// Queues a tech for research (validates prerequisites).
    public static func setResearch(
        _ state: WorldState,
        techID: String,
        registry: GameDataRegistry
    ) -> WorldState {
        TechEngine.setResearch(state, techID: techID, registry: registry)
    }

    /// Constructs one building in a settlement if it is unlocked and that
    /// settlement can pay the cost from its own storage. Returns unchanged
    /// state on failure.
    public static func build(
        _ state: WorldState,
        settlementID: UUID,
        buildingID: String,
        registry: GameDataRegistry
    ) -> WorldState {
        guard let def = registry.building(buildingID),
              state.unlockedBuildings.contains(buildingID) || def.era == .earlySettlement,
              let settlementIndex = state.settlements.firstIndex(where: { $0.id == settlementID }),
              let paid = EffectApplier.payCost(def.cost, from: state, settlementID: settlementID) else {
            return state
        }
        var s = paid
        if let existing = s.settlements[settlementIndex].buildings.firstIndex(where: { $0.definitionID == buildingID }) {
            s.settlements[settlementIndex].buildings[existing].count += 1
        } else {
            s.settlements[settlementIndex].buildings.append(BuildingInstance(definitionID: buildingID, count: 1))
        }
        return s
    }

    /// Sets a settlement's economic specialisation, reshaping its production.
    public static func setSpecialization(
        _ state: WorldState,
        settlementID: UUID,
        specialization: SettlementSpecialization
    ) -> WorldState {
        guard let i = state.settlements.firstIndex(where: { $0.id == settlementID }) else { return state }
        var s = state
        // Re-tooling a settlement's economy is disruptive: switching costs a
        // one-off hit to stability, so specialisation is a commitment, not a
        // free per-tick toggle.
        if s.settlements[i].specialization != specialization {
            s.settlements[i].stats.stability = max(0, s.settlements[i].stats.stability - specializationSwitchStabilityCost)
        }
        s.settlements[i].specialization = specialization
        return s
    }

    /// Stability lost when a settlement changes its specialisation.
    static let specializationSwitchStabilityCost: Double = 8

    /// Dispatches an escorted caravan carrying `amount` of `resource` from one
    /// settlement to another. Returns unchanged state if it can't be sent.
    public static func dispatchCaravan(
        _ state: WorldState,
        originID: UUID,
        destinationID: UUID,
        resource: ResourceType,
        amount: Double,
        guardIDs: [UUID]
    ) -> WorldState {
        CaravanEngine.dispatch(state, originID: originID, destinationID: destinationID,
                               resource: resource, amount: amount, guardIDs: guardIDs)
    }

    /// The leader's answer to the assembly's motion. Ratifying enacts the law;
    /// vetoing shelves it. Overruling the council's vote costs morale — unless
    /// the Leader spends their standing to smooth it over instead, which is
    /// what political capital is *for*.
    public static func resolveLawProposal(
        _ state: WorldState,
        approve: Bool,
        spendInfluence: Bool = false,
        registry: GameDataRegistry
    ) -> WorldState {
        SocietyEngine.resolveProposal(state, approve: approve,
                                      spendInfluence: spendInfluence, registry: registry)
    }

    // MARK: - Diplomacy
    //
    // Neighbouring peoples traded, married, raided and defected entirely on
    // their own, and the Leader could only watch it happen. These are the acts
    // that make influence a currency rather than a tax: standing you *spend*.

    /// Sends a neighbouring people a gift, buying goodwill with standing.
    public static func sendGift(
        _ state: WorldState, tribeID: UUID, registry: GameDataRegistry
    ) -> WorldState {
        let config = registry.config
        guard let index = state.tribes.firstIndex(where: { $0.id == tribeID }),
              var s = spendInfluence(state, amount: config.giftInfluenceCost) else { return state }
        s.tribes[index].standing = min(100, s.tribes[index].standing + config.giftStandingGain)
        // A gift softens an old wound as well as buying today's goodwill.
        s.tribes[index].grudge = max(0, s.tribes[index].grudge - config.giftStandingGain / 2)
        return s
    }

    /// Presses a people for tribute: their stores, at the price of their trust.
    public static func demandTribute(
        _ state: WorldState, tribeID: UUID, registry: GameDataRegistry
    ) -> WorldState {
        let config = registry.config
        guard let index = state.tribes.firstIndex(where: { $0.id == tribeID }),
              let seatIndex = state.settlements.indices.first,
              var s = spendInfluence(state, amount: config.demandInfluenceCost) else { return state }
        let taken = s.tribes[index].stores * config.demandStoresShare
        s.tribes[index].stores = max(0, s.tribes[index].stores - taken)
        s.tribes[index].standing = max(-100, s.tribes[index].standing - config.demandStandingLoss)
        s.tribes[index].grudge = min(100, s.tribes[index].grudge + config.demandStandingLoss / 2)
        s.settlements[seatIndex].storage[.food] = min(
            s.settlements[seatIndex].storageCapacity,
            s.settlements[seatIndex].storage[.food] + taken)
        return s
    }

    /// Seals a pact with a people who already trust you. Standing alone can't
    /// buy an alliance from strangers — they have to want it first.
    public static func proposePact(
        _ state: WorldState, tribeID: UUID, registry: GameDataRegistry
    ) -> WorldState {
        let config = registry.config
        guard let index = state.tribes.firstIndex(where: { $0.id == tribeID }),
              state.tribes[index].standing >= config.pactMinStanding,
              var s = spendInfluence(state, amount: config.pactInfluenceCost) else { return state }
        s.tribes[index].standing = max(s.tribes[index].standing, 60)   // `.allied`
        s.tribes[index].grudge = 0
        return s
    }

    /// Whether the seat can currently afford an act of this price.
    public static func canAfford(influence amount: Double, in state: WorldState) -> Bool {
        (state.settlements.first?.storage[.influence] ?? 0) >= amount
    }

    /// Draws influence from the seat of power, or `nil` if it can't be paid —
    /// so a half-affordable act is inert rather than partially applied.
    static func spendInfluence(_ state: WorldState, amount: Double) -> WorldState? {
        guard let index = state.settlements.indices.first,
              state.settlements[index].storage[.influence] >= amount else { return nil }
        var s = state
        s.settlements[index].storage[.influence] -= amount
        return s
    }

    /// Reassigns a colonist to a different kind of work.
    public static func assignWork(
        _ state: WorldState,
        settlementID: UUID,
        pawnID: UUID,
        work: WorkKind
    ) -> WorldState {
        guard let si = state.settlements.firstIndex(where: { $0.id == settlementID }),
              let pi = state.settlements[si].pawns.firstIndex(where: { $0.id == pawnID }) else {
            return state
        }
        var s = state
        s.settlements[si].pawns[pi].assignedWork = work
        return s
    }

    /// Equips an inventory item onto a colonist, into the item's body slot.
    /// Any item already in that slot returns to the inventory. Returns
    /// unchanged state on failure.
    public static func equipItem(
        _ state: WorldState,
        settlementID: UUID,
        pawnID: UUID,
        itemID: UUID,
        registry: GameDataRegistry
    ) -> WorldState {
        guard let si = state.settlements.firstIndex(where: { $0.id == settlementID }),
              let ii = state.settlements[si].inventory.firstIndex(where: { $0.id == itemID }),
              let pi = state.settlements[si].pawns.firstIndex(where: { $0.id == pawnID }),
              let def = registry.item(state.settlements[si].inventory[ii].definitionID),
              def.slot == .equipment, let slot = def.equipSlot else {
            return state
        }
        var s = state
        let item = s.settlements[si].inventory.remove(at: ii)
        if let previous = s.settlements[si].pawns[pi].equipment[slot] {
            s.settlements[si].inventory.append(previous)
        }
        s.settlements[si].pawns[pi].equipment[slot] = item
        return s
    }

    /// Returns the item in a colonist's given slot to the settlement inventory.
    public static func unequipItem(
        _ state: WorldState,
        settlementID: UUID,
        pawnID: UUID,
        slot: EquipmentSlot
    ) -> WorldState {
        guard let si = state.settlements.firstIndex(where: { $0.id == settlementID }),
              let pi = state.settlements[si].pawns.firstIndex(where: { $0.id == pawnID }),
              let item = state.settlements[si].pawns[pi].equipment[slot] else {
            return state
        }
        var s = state
        s.settlements[si].inventory.append(item)
        s.settlements[si].pawns[pi].equipment[slot] = nil
        return s
    }

    /// Crafts a recipe at a settlement (consumes its materials + resources).
    /// When `settlementID` is `nil` the capital crafts, as before.
    public static func craft(
        _ state: WorldState,
        recipeID: String,
        settlementID: UUID? = nil,
        registry: GameDataRegistry
    ) -> WorldState {
        CraftingEngine.craft(state, recipeID: recipeID, settlementID: settlementID, registry: registry)
    }

    /// Interacts with the special site (ruins/dungeon/anomaly) in a region.
    /// Returns the new state and the outcome, or unchanged state + `nil`.
    public static func interactWithSite(
        _ state: WorldState,
        regionID: UUID,
        registry: GameDataRegistry
    ) -> (WorldState, SiteOutcome?) {
        if let (newState, outcome) = SiteEngine.interact(state, regionID: regionID, registry: registry) {
            return (newState, outcome)
        }
        return (state, nil)
    }

    /// Founds an outpost in a fully-explored, unsettled region.
    public static func foundOutpost(
        _ state: WorldState,
        regionID: UUID,
        name: String,
        registry: GameDataRegistry
    ) -> WorldState {
        ExpansionEngine.foundOutpost(state, regionID: regionID, name: name, registry: registry)
    }

    /// Establishes a standing trade route between two settlements.
    public static func addTradeRoute(
        _ state: WorldState,
        from: UUID,
        to: UUID,
        resource: ResourceType,
        amountPerTick: Double
    ) -> WorldState {
        guard state.settlements.contains(where: { $0.id == from }),
              state.settlements.contains(where: { $0.id == to }),
              from != to else { return state }
        var s = state
        s.tradeRoutes.append(TradeRoute(fromID: from, toID: to, resource: resource, amountPerTick: amountPerTick))
        return s
    }

    /// Removes a trade route by id.
    public static func removeTradeRoute(_ state: WorldState, routeID: UUID) -> WorldState {
        var s = state
        s.tradeRoutes.removeAll { $0.id == routeID }
        return s
    }

    /// Sends an expedition to an unknown region (cost + duration applied).
    public static func startExpedition(
        _ state: WorldState,
        targetRegionID: UUID,
        registry: GameDataRegistry
    ) -> WorldState {
        ExplorationEngine.startExpedition(state, targetRegionID: targetRegionID, registry: registry)
    }

    /// Resolves a player choice on an event: pays the choice cost (if any) and
    /// applies the choice's effects. Returns unchanged state when the choice
    /// can't be found or afforded.
    public static func resolveChoice(
        _ state: WorldState,
        eventID: String,
        choiceID: String,
        registry: GameDataRegistry
    ) -> WorldState {
        guard let template = registry.events.first(where: { $0.id == eventID }),
              let choice = template.choices.first(where: { $0.id == choiceID }) else {
            return state
        }
        guard let paid = EffectApplier.payCost(choice.cost, from: state) else {
            return state
        }
        var s = EffectApplier.apply(choice.effects, to: paid, registry: registry)
        // The decision is made; take it off the Leader's desk.
        s.pendingEvents.removeAll { $0.templateID == eventID }
        return s
    }

    /// Whether the player could actually afford a choice — the UI greys out the
    /// rest rather than letting them tap into a dead end.
    public static func canAffordChoice(
        _ state: WorldState,
        eventID: String,
        choiceID: String,
        registry: GameDataRegistry
    ) -> Bool {
        guard let template = registry.events.first(where: { $0.id == eventID }),
              let choice = template.choices.first(where: { $0.id == choiceID }) else {
            return false
        }
        return EffectApplier.payCost(choice.cost, from: state) != nil
    }

    /// Sets a decision aside without acting on it — the moment passes.
    public static func dismissEvent(_ state: WorldState, eventID: String) -> WorldState {
        var s = state
        s.pendingEvents.removeAll { $0.templateID == eventID }
        return s
    }

    // MARK: - Colony layout (in-settlement base building)

    /// Places a building on a settlement's colony grid, paying its cost from the
    /// capital. Validates that the building is unlocked and the tile is free.
    /// Returns unchanged state on failure.
    public static func placeBuilding(
        _ state: WorldState,
        settlementID: UUID,
        buildingID: String,
        at coord: TileCoord,
        registry: GameDataRegistry
    ) -> WorldState {
        guard let def = registry.building(buildingID),
              state.unlockedBuildings.contains(buildingID) || def.era == .earlySettlement,
              let si = state.settlements.firstIndex(where: { $0.id == settlementID }),
              ColonyBuilder.canPlace(state.settlements[si], definitionID: buildingID, at: coord, registry: registry),
              let paid = EffectApplier.payCost(def.cost, from: state) else {
            return state
        }
        var s = paid
        guard let place = s.settlements.firstIndex(where: { $0.id == settlementID }) else { return state }
        s.settlements[place] = ColonyBuilder.place(
            s.settlements[place], definitionID: buildingID, at: coord, registry: registry
        )
        return s
    }

    /// Demolishes whatever stands on a colony tile (no refund).
    public static func demolish(
        _ state: WorldState,
        settlementID: UUID,
        at coord: TileCoord
    ) -> WorldState {
        guard let si = state.settlements.firstIndex(where: { $0.id == settlementID }) else { return state }
        var s = state
        s.settlements[si] = ColonyBuilder.remove(s.settlements[si], at: coord)
        return s
    }

    /// Puts a colonist to work on a specific placed building.
    public static func assignToBuilding(
        _ state: WorldState,
        settlementID: UUID,
        pawnID: UUID,
        placementID: UUID,
        registry: GameDataRegistry
    ) -> WorldState {
        guard let si = state.settlements.firstIndex(where: { $0.id == settlementID }) else { return state }
        var s = state
        s.settlements[si] = ColonyBuilder.assign(s.settlements[si], pawnID: pawnID, to: placementID, registry: registry)
        return s
    }

    /// Frees a colonist from any building in a settlement and sets them idle.
    public static func unassignFromBuilding(
        _ state: WorldState,
        settlementID: UUID,
        pawnID: UUID
    ) -> WorldState {
        guard let si = state.settlements.firstIndex(where: { $0.id == settlementID }) else { return state }
        var s = state
        s.settlements[si] = ColonyBuilder.unassign(s.settlements[si], pawnID: pawnID)
        return s
    }

    /// Paints an amenity zone tile (park/plaza/garden) on a settlement's grid.
    public static func paintZone(
        _ state: WorldState,
        settlementID: UUID,
        at coord: TileCoord,
        kind: ZoneKind
    ) -> WorldState {
        guard let si = state.settlements.firstIndex(where: { $0.id == settlementID }) else { return state }
        var s = state
        s.settlements[si] = ColonyBuilder.paintZone(s.settlements[si], at: coord, kind: kind)
        return s
    }

    /// Clears any amenity zone on a colony tile.
    public static func eraseZone(
        _ state: WorldState,
        settlementID: UUID,
        at coord: TileCoord
    ) -> WorldState {
        guard let si = state.settlements.firstIndex(where: { $0.id == settlementID }) else { return state }
        var s = state
        s.settlements[si] = ColonyBuilder.eraseZone(s.settlements[si], at: coord)
        return s
    }
}
