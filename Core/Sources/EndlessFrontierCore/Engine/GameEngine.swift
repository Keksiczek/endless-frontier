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

    /// The same thing, reported as it goes.
    ///
    /// A month away is up to 43,200 ticks, and in a debug build that is minutes
    /// with a spinner over it and no way to tell it from a hang. `onProgress`
    /// is called with `(ticks done, ticks in total)` after each slice.
    ///
    /// **This is not a different simulation.** `TickEngine.advance` is a plain
    /// `for _ in 0..<ticks` over a pure step, and `ticks` is nothing but the
    /// loop's bound — everything else it reads comes off the state. So
    /// advancing 600 then 600 lands on the same world as advancing 1,200, and
    /// `catchUpIsTheSameWorldEitherWay` says so in a test rather than in a
    /// comment. Determinism is the project's hardest invariant; a progress bar
    /// is not worth spending it.
    public static func openSession(
        _ state: WorldState,
        now: Date,
        registry: GameDataRegistry,
        sliceTicks: Int = 240,
        onProgress: (Int, Int) -> Void
    ) -> PlannerResult {
        openSession(state, now: now, registry: registry, sliceTicks: sliceTicks,
                    stoppingWhen: nil, onProgress: onProgress).result
    }

    /// The same, allowed to stop the moment something happens that the player
    /// should be **in** rather than told about.
    ///
    /// The one thing that uses it is a raid: see
    /// `TickEngine.advance(_:ticks:registry:stoppingWhen:)` for why a fight
    /// with a middle left open was a surface nobody had ever reached. When the
    /// years stop short, the clock stops with them — `lastRealTimestamp` is
    /// moved on by the ticks actually run, so the rest of the absence is still
    /// owed and is caught up once the fight is over.
    public static func openSession(
        _ state: WorldState,
        now: Date,
        registry: GameDataRegistry,
        sliceTicks: Int = 240,
        stoppingWhen halt: (@Sendable (WorldState) -> Bool)?,
        /// **How big the next slice should be**, asked after each one.
        ///
        /// A slice sized once cannot be right: the cost of a tick is the cost of
        /// walking the colony, and the colony grows *during the absence being
        /// caught up*. Sizing by head-count at the start helped and did not
        /// finish the job — at a hundred and sixty colonists the first slice is
        /// still seconds long, and the bar reads "0 years · 0 %" while it runs.
        ///
        /// So the caller may hand back a new size after every slice, having
        /// timed the last one. **The clock stays outside**: nothing here reads a
        /// wall clock, and `TickEngine.advance` is the same pure loop it always
        /// was, so a slice of 13 and a slice of 10,000 still land on the same
        /// world (`CatchUpSliceTests`, rule 3).
        nextSlice: ((_ lastSlice: Int) -> Int)? = nil,
        onProgress: (Int, Int) -> Void
    ) -> (result: PlannerResult, stoppedShort: Bool) {
        let total = TickEngine.ticksElapsed(
            since: state.lastRealTimestamp, until: now, config: registry.config)
        var result = PlannerResult(state: state, fired: [])
        var done = 0
        var short = false
        var size = sliceTicks
        onProgress(0, total)
        while done < total {
            let slice = min(max(1, size), total - done)
            let step = TickEngine.advance(result.state, ticks: slice,
                                          registry: registry, stoppingWhen: halt)
            result.state = step.result.state
            result.fired.append(contentsOf: step.result.fired)
            done += step.ticksRun
            onProgress(done, total)
            if step.ticksRun < slice { short = true; break }
            if let nextSlice { size = max(1, nextSlice(slice)) }
        }
        // Stopped short, the remaining absence is still owed: the stamp moves
        // on by what was actually simulated and no further.
        result.state.lastRealTimestamp = short
            ? state.lastRealTimestamp
                .addingTimeInterval(Double(done) * registry.config.realSecondsPerTick)
            : now
        return (result, short)
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

    /// Opens a construction site for one building in a settlement if it is
    /// unlocked and that settlement can pay the cost from its own storage.
    /// The building joins the economy only when `ConstructionEngine` finishes
    /// it — paying is breaking ground, not conjuring a roof. Returns unchanged
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
              hasMaterials(def.materialCost, in: state, settlementID: settlementID),
              let paid = EffectApplier.payCost(def.cost, from: state, settlementID: settlementID) else {
            return state
        }
        // **Somewhere to stand, before anything is paid for.**
        //
        // This used to pay first and site afterwards, and shrug if there was no
        // room: the building went into the ledger with `placementID: nil`, owned
        // no ground, and could never be drawn. For a farm that is fatal rather
        // than untidy — `FarmEngine.reconcile` makes plots out of *placements*,
        // so a farm with nowhere to stand grows nothing at all, and a colony
        // that has filled its grid quietly stops being able to feed itself while
        // its ledger still says it built four more farms. Measured, seed 4242:
        // buildings 79 → 107 with plots frozen at 38 and a hundred and twenty
        // people starving on a full larder of materials.
        //
        // `placeSiteAtFirstFit` widens the colony's ground when it is full, so
        // this only refuses at `ColonyBuilder.maxSide` — and refusing is right:
        // materials not spent are materials the council can spend on something
        // it *can* stand up.
        var placementID: UUID?
        var sitedSettlement: Settlement?
        if state.settlements[settlementIndex].colony != nil {
            let sited = ColonyBuilder.placeSiteAtFirstFit(
                state.settlements[settlementIndex], definitionID: buildingID, registry: registry)
            guard sited.placementID != nil else { return state }
            sitedSettlement = sited.settlement
            placementID = sited.placementID
        }
        var s = payMaterials(def.materialCost, from: paid, settlementIndex: settlementIndex)
        var target = s.settlements[settlementIndex]
        if let sitedSettlement {
            // The paying happened on a copy taken before the siting; carry the
            // ground across rather than the other way round, so a wider grid and
            // a lighter store both survive.
            target.colony = sitedSettlement.colony
        }
        s.settlements[settlementIndex] = ConstructionEngine.enqueue(
            target, definitionID: buildingID, placementID: placementID,
            registry: registry, tick: s.tick)
        return s
    }

    /// Whether a settlement holds the goods a build calls for.
    public static func hasMaterials(
        _ cost: [String: Int], in state: WorldState, settlementID: UUID
    ) -> Bool {
        guard !cost.isEmpty else { return true }
        guard let s = state.settlements.first(where: { $0.id == settlementID }) else { return false }
        let held = CraftingEngine.materialCounts(s)
        return cost.allSatisfy { (held[$0.key] ?? 0) >= $0.value }
    }

    /// Takes the goods off the pile — stockpile first, then any loose instances
    /// left over from loot or an older save.
    static func payMaterials(
        _ cost: [String: Int], from state: WorldState, settlementIndex: Int
    ) -> WorldState {
        guard !cost.isEmpty else { return state }
        var s = state
        for (materialID, needed) in cost {
            var remaining = needed
            let stocked = s.settlements[settlementIndex].stockpile[materialID] ?? 0
            let fromStock = min(stocked, remaining)
            if fromStock > 0 {
                s.settlements[settlementIndex].stockpile[materialID] = stocked - fromStock
                remaining -= fromStock
            }
            guard remaining > 0 else { continue }
            var removed = 0
            s.settlements[settlementIndex].inventory.removeAll { instance in
                guard removed < remaining, instance.definitionID == materialID else { return false }
                removed += 1
                return true
            }
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
              state.tribes[index].discovered,
              var s = spendInfluence(state, amount: config.giftInfluenceCost) else { return state }
        s.tribes[index].standing = min(100, s.tribes[index].standing + config.giftStandingGain)
        // A gift softens an old wound as well as buying today's goodwill.
        s.tribes[index].grudge = max(0, s.tribes[index].grudge - config.giftStandingGain / 2)
        return s
    }

    /// **Builds the next stretch of road toward a neighbour's country.**
    ///
    /// The verb `docs/NEIGHBOURS.md` puts first, because it is the one that
    /// stands on the map. The other three — gift, demand, pact — are a one-off
    /// spend of influence that moves a number and is then over. A road:
    ///
    /// - **is visible**, in the grade you paid for;
    /// - **is mutual**, and that is the point rather than a drawback. It
    ///   shortens the journey *both ways*, so it is a commitment and not a
    ///   present. A road to a people who later hate you is a road their warband
    ///   walks in on, and `RoadEngine.cut` means it is also a thing they take
    ///   from you;
    /// - **accrues**. `DiplomacyProbe` measured standings swinging over bands
    ///   of sixty to a hundred and sixty points, which makes a gift's twelve
    ///   into noise. What a verb needs is not a bigger number but a *rate*, and
    ///   a road earns its standing every year it stands.
    ///
    /// One edge per call, cheapest-useful grade, paid in materials — the same
    /// shape as the council's own road-building, so a player and the steward are
    /// spending on the same terms. Returns the state unchanged if there is
    /// nowhere to build, nothing to build with, or the road already runs all
    /// the way.
    public static func buildRoadToward(
        _ state: WorldState, tribeID: UUID, registry: GameDataRegistry
    ) -> WorldState {
        guard let tribeIndex = state.tribes.firstIndex(where: { $0.id == tribeID }),
              state.tribes[tribeIndex].discovered,
              let theirRegionID = state.tribes[tribeIndex].regionID,
              let theirs = state.regions.first(where: { $0.id == theirRegionID }),
              let capitalIndex = state.settlements.indices.first,
              let seatID = state.settlements[capitalIndex].regionID,
              let seat = state.regions.first(where: { $0.id == seatID })
        else { return state }

        guard let (link, cost) = nextStretch(state, toward: theirs, from: seat),
              let paid = EffectApplier.payCost([.materials: cost], from: state,
                                               settlementID: state.settlements[capitalIndex].id)
        else { return state }

        var s = paid
        s.roads.lay(link)
        // Standing for the commitment, and it eases the grievance of being the
        // larger neighbour — a road is the one thing a big colony can offer
        // that costs it something the smaller one can see.
        s.tribes[tribeIndex].standing = min(100, s.tribes[tribeIndex].standing
                                            + registry.config.giftStandingGain / 2)
        DiplomacyEngine.resent(&s.tribes[tribeIndex], by: -4)
        let what = link.grade.displayName
        s.settlements[capitalIndex].note(
            tick: s.tick, kind: .construction,
            text: LocalizedText(values: [
                .en: "A \(what.resolve(.en).lowercased()) now reaches toward \(s.tribes[tribeIndex].name).",
                .cs: "Směrem k \(s.tribes[tribeIndex].name) teď vede \(what.resolve(.cs).lowercased())."]))
        return s
    }

    /// The first stretch on the way there that is not yet as made as this world
    /// knows how to make it, and what it would cost.
    ///
    /// Nearest first, so the road grows out from home and a half-built one goes
    /// *part* of the way rather than being a scatter of paving in the
    /// wilderness.
    static func nextStretch(
        _ state: WorldState, toward theirs: Region, from seat: Region
    ) -> (link: RoadLink, cost: Double)? {
        let byCoord = Dictionary(state.regions.map { ($0.coord, $0) }) { first, _ in first }
        guard let march = state.roads.route(from: seat.coord, to: theirs.coord,
                                            regions: byCoord) else { return nil }
        for (a, b) in zip(march.hexes, march.hexes.dropFirst()) {
            guard let grade = RoadEngine.nextGrade(after: state.roads.link(a, b)?.grade,
                                                   state: state),
                  let here = byCoord[a], let there = byCoord[b] else { continue }
            return (RoadLink(a: a, b: b, grade: grade),
                    RoadEngine.price(grade, here: here, there: there,
                                     existing: state.roads.link(a, b)))
        }
        return nil
    }

    /// What the next stretch toward this people would cost, or `nil` when the
    /// road already runs all the way and there is nothing left to build.
    ///
    /// **Asked without paying.** The first cut answered by calling
    /// `buildRoadToward` and looking at what changed — which works, because
    /// these are pure functions, and is wrong anyway: a colony that cannot
    /// afford the stretch gets an unchanged world back, so "too poor" and
    /// "nothing to build" came out as the same `nil`. A panel needs to tell a
    /// price it cannot pay from a road that is finished.
    public static func roadTowardCost(
        _ state: WorldState, tribeID: UUID, registry: GameDataRegistry
    ) -> Double? {
        guard let tribe = state.tribes.first(where: { $0.id == tribeID }),
              tribe.discovered,
              let theirRegionID = tribe.regionID,
              let theirs = state.regions.first(where: { $0.id == theirRegionID }),
              let seatID = state.settlements.first?.regionID,
              let seat = state.regions.first(where: { $0.id == seatID })
        else { return nil }
        return nextStretch(state, toward: theirs, from: seat)?.cost
    }

    // MARK: - A road the player lays

    /// Lays the next grade of way on **one edge the player chose**, paid for
    /// out of the capital's materials.
    ///
    /// The council builds where the traffic is (`RoadEngine.build`) and a road
    /// toward a people is a gesture to them (`buildRoadToward`). This is
    /// neither: it is the player saying *this stretch, here*, which is the one
    /// road-laying the game did not have and the only one that lets somebody
    /// road a pass before they need it rather than after.
    ///
    /// The same ladder as everywhere else — one rung at a time, era- and
    /// tech-gated (rule 66) — and the same price, so a player-laid road is
    /// never a cheaper way of buying what the council would have built.
    ///
    /// Both hexes must be **known**: a colony cannot survey a route through
    /// country nobody has walked.
    public static func layRoad(
        _ state: WorldState, from a: HexCoord, to b: HexCoord, registry: GameDataRegistry
    ) -> WorldState {
        guard let (link, cost) = stretch(state, from: a, to: b),
              let capital = state.settlements.first,
              let paid = EffectApplier.payCost([.materials: cost], from: state,
                                               settlementID: capital.id)
        else { return state }

        var s = paid
        s.roads.lay(link)
        let what = link.grade.displayName
        let where_ = s.regions.first { $0.coord == b }?.name ?? ""
        s.settlements[0].note(
            tick: s.tick, kind: .construction,
            text: LocalizedText(values: [
                .en: "The people have laid a \(what.resolve(.en).lowercased()) toward \(where_).",
                .cs: "Lid vybudoval \(what.resolve(.cs).lowercased()) směrem k \(where_)."]))
        return s
    }

    /// What laying the next grade on this edge would cost, or `nil` when there
    /// is nothing left to lay on it.
    ///
    /// Asked without paying, for the same reason `roadTowardCost` is: a panel
    /// has to tell a price it cannot meet from a way that is already finished.
    public static func roadCost(
        _ state: WorldState, from a: HexCoord, to b: HexCoord
    ) -> Double? {
        stretch(state, from: a, to: b)?.cost
    }

    /// The grade this edge would take next and what it would cost — `nil` when
    /// the two hexes are not neighbours, when either is unknown country, or
    /// when the way is already as made as this world knows how to make it.
    ///
    /// Public because the panel that offers the road has to show the grade as
    /// well as the price: "a road, thirty" and "a railway, four hundred" are
    /// different offers and a lone number cannot tell them apart.
    public static func stretch(
        _ state: WorldState, from a: HexCoord, to b: HexCoord
    ) -> (link: RoadLink, cost: Double)? {
        guard a != b, a.neighbors().contains(b) else { return nil }
        guard let here = state.regions.first(where: { $0.coord == a }),
              let there = state.regions.first(where: { $0.coord == b }),
              here.explorationState != .unknown, there.explorationState != .unknown
        else { return nil }
        guard let grade = RoadEngine.nextGrade(after: state.roads.link(a, b)?.grade,
                                               state: state) else { return nil }
        return (RoadLink(a: a, b: b, grade: grade),
                RoadEngine.price(grade, here: here, there: there,
                                 existing: state.roads.link(a, b)))
    }

    /// **Every edge on the map the player could lay a way on right now.**
    ///
    /// The affordance for laying a road was a list of neighbours in a panel —
    /// which is a fine way to buy a road and a poor way to *see* one, because
    /// a road is a line between two places and a row of text is not. What the
    /// map wants is the edges themselves, and it needs all of them at once
    /// rather than one hex's worth.
    ///
    /// Indexed once. `stretch` looks a region up by walking `regions`, so
    /// asking it six times per hex over a charted world is quadratic in the
    /// map — fine for one panel and not for something a drawing reads.
    public static func layableEdges(_ state: WorldState) -> [(link: RoadLink, cost: Double)] {
        let byCoord = Dictionary(state.regions.map { ($0.coord, $0) }) { a, _ in a }
        var seen = Set<String>()
        var out: [(link: RoadLink, cost: Double)] = []
        for region in state.regions where region.explorationState != .unknown {
            for coord in region.coord.neighbors() {
                let key = RoadLink.key(region.coord, coord)
                guard !seen.contains(key) else { continue }
                guard let there = byCoord[coord], there.explorationState != .unknown else { continue }
                guard let grade = RoadEngine.nextGrade(after: state.roads.link(region.coord, coord)?.grade,
                                                       state: state) else { continue }
                seen.insert(key)
                let link = RoadLink(a: region.coord, b: coord, grade: grade)
                out.append((link, RoadEngine.price(grade, here: region, there: there,
                                                   existing: state.roads.link(region.coord, coord))))
            }
        }
        // Sorted, because a dictionary's order is not stable and a drawing that
        // walks this list would otherwise reshuffle itself between frames.
        return out.sorted { $0.link.id < $1.link.id }
    }

    // MARK: - An embassy

    /// **Posts a colonist to live among a people.**
    ///
    /// The verb `docs/NEIGHBOURS.md` writes as costing "influence, and a
    /// colonist who is *there* and not at home". The second half is the real
    /// price: `Pawn.isAway` covers an envoy, so the labour engine stops
    /// counting them, and a colony of thirty feels the gap for as long as the
    /// post stands.
    ///
    /// What it buys is **not** a lump of standing. `DiplomacyProbe` measured
    /// standings swinging over bands of fifty-eight to a hundred and
    /// fifty-five points, which makes any single payment noise — so an embassy
    /// pays a little every year it stands (`DiplomacyEngine.envoyStandingPerYear`),
    /// and one that has stood for fifty years is worth something no gift can
    /// buy. Rule 69: the rate has to exist *because the embassy stands*, not
    /// fire when something happens.
    ///
    /// One envoy per people. Returns the state unchanged if the people is
    /// unmet, already hosts one, or the colony cannot spare anybody.
    public static func sendEnvoy(
        _ state: WorldState, tribeID: UUID, registry: GameDataRegistry
    ) -> WorldState {
        guard let tribeIndex = state.tribes.firstIndex(where: { $0.id == tribeID }),
              state.tribes[tribeIndex].discovered,
              let capitalIndex = state.settlements.indices.first,
              !state.settlements[capitalIndex].pawns.contains(where: { $0.envoyToTribeID == tribeID }),
              let chosen = envoyCandidate(state.settlements[capitalIndex], registry: registry),
              var s = spendInfluence(state, amount: registry.config.giftInfluenceCost)
        else { return state }

        guard let personIndex = s.settlements[capitalIndex].pawns
            .firstIndex(where: { $0.id == chosen }) else { return state }
        s.settlements[capitalIndex].pawns[personIndex].envoyToTribeID = tribeID
        // Their post is not their trade any more, and the job board must not
        // keep them on a scaffold they are a hundred miles from.
        s.settlements[capitalIndex].pawns[personIndex].currentJob = nil
        let name = s.settlements[capitalIndex].pawns[personIndex].name
        let them = s.tribes[tribeIndex].name
        s.settlements[capitalIndex].note(
            tick: s.tick, kind: .departure,
            text: LocalizedText(values: [
                .en: "\(name) has gone to live among \(them), and speak for us there.",
                .cs: "\(name) odešel_a žít mezi \(them) a mluvit tam za nás."]))
        return s
    }

    /// Calls an envoy home. The standing they earned stays earned — it was
    /// paid a year at a time and is not on loan.
    public static func recallEnvoy(
        _ state: WorldState, tribeID: UUID, registry: GameDataRegistry
    ) -> WorldState {
        var s = state
        var found = false
        for settlementIndex in s.settlements.indices {
            for personIndex in s.settlements[settlementIndex].pawns.indices
            where s.settlements[settlementIndex].pawns[personIndex].envoyToTribeID == tribeID {
                s.settlements[settlementIndex].pawns[personIndex].envoyToTribeID = nil
                found = true
            }
        }
        guard found else { return state }
        return s
    }

    /// Who the colony can spare. An adult in good health who is not already
    /// elsewhere and is not the last pair of hands in a trade the colony is
    /// relying on — the same judgement `RegionExpeditionEngine.chooseParty`
    /// makes, kept simple because a single envoy is a smaller ask than a party.
    public static func envoyCandidate(
        _ settlement: Settlement, registry: GameDataRegistry
    ) -> UUID? {
        let ticksPerYear = max(1, registry.config.ticksPerYear)
        return settlement.pawns
            .filter { $0.isAdult(ticksPerYear: ticksPerYear) && !$0.isAway
                      && !$0.isBroken && $0.health >= 60 }
            // The most sociable, because that is what the post is for — and by
            // id on a tie, so the choice never depends on array order.
            .max { a, b in
                a.genes.sociability == b.genes.sociability
                    ? a.id.uuidString > b.id.uuidString
                    : a.genes.sociability < b.genes.sociability
            }?.id
    }

    /// Whether a people currently hosts one of ours.
    public static func envoy(in state: WorldState, toward tribeID: UUID) -> Pawn? {
        state.settlements
            .flatMap(\.pawns)
            .first { $0.envoyToTribeID == tribeID }
    }

    // MARK: - Buying peace

    /// **Offers a people a yearly payment to leave us alone.**
    ///
    /// `demandTribute` has always pointed outward. Nothing pointed in, so a
    /// colony that could not fight had no way to buy peace except a gift: one
    /// payment against a grievance that keeps growing. This is the verb a
    /// losing player needs, and the one that makes losing interesting rather
    /// than terminal.
    ///
    /// A **standing charge**, priced as a multiple of what it buys and never as
    /// a share of the warehouse (rule 16) — otherwise a colony that builds a
    /// granary can suddenly no longer afford peace. Set it to zero to stop
    /// paying, and see `DiplomacyEngine.collectTribute` for what stopping does.
    public static func payTribute(
        _ state: WorldState, tribeID: UUID, perYear: Double, registry: GameDataRegistry
    ) -> WorldState {
        guard let index = state.tribes.firstIndex(where: { $0.id == tribeID }),
              state.tribes[index].discovered,
              perYear >= 0, perYear <= DiplomacyEngine.tributeMostPerYear
        else { return state }
        var s = state
        s.tribes[index].tributePerYear = perYear
        if let capital = s.settlements.indices.first {
            let them = s.tribes[index].name
            s.settlements[capital].note(
                tick: s.tick, kind: .discovery,
                text: perYear > 0
                    ? LocalizedText(values: [
                        .en: "We have agreed to send \(them) a share of the stores each year.",
                        .cs: "Dohodli jsme se posílat \(them) každý rok díl ze zásob."])
                    : LocalizedText(values: [
                        .en: "We will send \(them) nothing more.",
                        .cs: "\(them) už nepošleme nic."]))
        }
        return s
    }

    /// Presses a people for tribute: their stores, at the price of their trust.
    public static func demandTribute(
        _ state: WorldState, tribeID: UUID, registry: GameDataRegistry
    ) -> WorldState {
        let config = registry.config
        guard let index = state.tribes.firstIndex(where: { $0.id == tribeID }),
              state.tribes[index].discovered,
              let seatIndex = state.settlements.indices.first,
              var s = spendInfluence(state, amount: config.demandInfluenceCost) else { return state }
        let taken = s.tribes[index].stores * config.demandStoresShare
        s.tribes[index].stores = max(0, s.tribes[index].stores - taken)
        s.tribes[index].standing = max(-100, s.tribes[index].standing - config.demandStandingLoss)
        s.tribes[index].grudge = min(100, s.tribes[index].grudge + config.demandStandingLoss / 2)
        s.settlements[seatIndex].storage[.food] = min(
            s.settlements[seatIndex].storageCapacity[.food],
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
              state.tribes[index].discovered,
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

    // `interactWithSite` stood here: a pass-through to `SiteEngine.interact`
    // that turned its optional into a tuple, called by nothing and covered by
    // nothing. It is what the app used before going to a site became a journey
    // — `RegionExpeditionEngine` is the way there now, and it calls
    // `SiteEngine.interact` itself.

    /// Sends a party out to work a discovered point of interest. The haul
    /// lands when they walk back in, not now. Returns the world unchanged when
    /// the order cannot be given — the place is undiscovered, picked clean,
    /// resting, already has a party out, or nobody can be spared.
    public static func dispatchToPOI(
        _ state: WorldState,
        settlementID: UUID,
        poiID: Int,
        registry: GameDataRegistry
    ) -> WorldState {
        LocalPOIEngine.dispatch(state, settlementID: settlementID, poiID: poiID,
                                registry: registry) ?? state
    }

    /// Points the settlement's scouts at a spot on the local map. They walk
    /// there on their next outing instead of wandering, and the order clears
    /// itself once that ground is charted.
    public static func sendScouts(
        _ state: WorldState,
        settlementID: UUID,
        to point: LocalPoint
    ) -> WorldState {
        guard let seat = state.settlements.firstIndex(where: { $0.id == settlementID }),
              var map = state.settlements[seat].localMap,
              !map.isExplored(point) else { return state }
        var s = state
        map.scoutFocus = point
        s.settlements[seat].localMap = map
        return s
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

    /// Establishes a standing route carrying a *material* — timber, ore, clay —
    /// from one settlement's stockpile to another's. This is how a colony
    /// founded on a coast with no iron ever gets any.
    public static func addMaterialRoute(
        _ state: WorldState,
        from: UUID,
        to: UUID,
        materialID: String,
        unitsPerTick: Double,
        registry: GameDataRegistry
    ) -> WorldState {
        guard state.settlements.contains(where: { $0.id == from }),
              state.settlements.contains(where: { $0.id == to }),
              from != to, unitsPerTick > 0,
              registry.item(materialID)?.slot == .material else { return state }
        var s = state
        s.tradeRoutes.append(TradeRoute(fromID: from, toID: to, resource: .materials,
                                        amountPerTick: unitsPerTick, materialID: materialID))
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

    /// Opens a construction site on a settlement's colony grid, paying its cost
    /// from the capital. The tiles are reserved and the scaffolding goes up at
    /// once; the building itself joins the economy when the builders finish.
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
              hasMaterials(def.materialCost, in: state, settlementID: settlementID),
              let paid = EffectApplier.payCost(def.cost, from: state) else {
            return state
        }
        var s = paid
        guard let place = s.settlements.firstIndex(where: { $0.id == settlementID }) else { return state }
        s = payMaterials(def.materialCost, from: s, settlementIndex: place)
        let sited = ColonyBuilder.placeSite(
            s.settlements[place], definitionID: buildingID, at: coord, registry: registry
        )
        guard let placementID = sited.colony?.placement(at: coord)?.id else { return state }
        s.settlements[place] = ConstructionEngine.enqueue(
            sited, definitionID: buildingID, placementID: placementID,
            registry: registry, tick: s.tick)
        return s
    }

    /// Demolishes whatever stands on a colony tile (no refund). Tearing down a
    /// half-raised site also cancels its construction project.
    public static func demolish(
        _ state: WorldState,
        settlementID: UUID,
        at coord: TileCoord
    ) -> WorldState {
        guard let si = state.settlements.firstIndex(where: { $0.id == settlementID }) else { return state }
        var s = state
        let removed = s.settlements[si].colony?.placement(at: coord)
        s.settlements[si] = ColonyBuilder.remove(s.settlements[si], at: coord)
        if let removed, removed.underConstruction {
            s.settlements[si].constructions.removeAll { $0.placementID == removed.id }
        }
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
