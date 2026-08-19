import Foundation

/// The result of a party's work at a point of interest, for the UI and the
/// journal. Produced when they walk back through the gate — never before.
public struct LocalPOIOutcome: Sendable, Equatable {
    public let kind: LocalPOIKind
    public let rewards: Resources
    /// A colonist hurt in the doing, if any — and whether it killed them.
    public let casualtyName: String?
    public let died: Bool
    public let itemFound: LocalizedText?
    /// Visits left after this one; `nil` for places that never run out.
    public let visitsRemaining: Int?
    public let narrative: LocalizedText

    public init(kind: LocalPOIKind, rewards: Resources, casualtyName: String? = nil,
                died: Bool = false, itemFound: LocalizedText? = nil, visitsRemaining: Int? = nil,
                narrative: LocalizedText) {
        self.kind = kind
        self.rewards = rewards
        self.casualtyName = casualtyName
        self.died = died
        self.itemFound = itemFound
        self.visitsRemaining = visitsRemaining
        self.narrative = narrative
    }
}

/// Makes the valley's own landmarks worth walking to — and makes the walking
/// real.
///
/// Finding a point of interest used to be the entire relationship: `reveal`
/// flipped `discovered`, `grantPOIDiscovery` paid once, and the ruins on your
/// doorstep were scenery you could tap to read their name. The first fix gave
/// them a button, but a button that paid instantly still meant nobody went
/// anywhere: the ruins across the valley cost exactly what the spring next door
/// did, and the colony's hands were never missing from the fields.
///
/// So a visit is an **expedition**. Named colonists — picked for the trade the
/// place actually wants — leave the settlement, walk for as long as the
/// distance says, work the site, and carry the haul home. While they are gone
/// they produce nothing, because they are not there. If the roof comes down it
/// comes down on one of *them*, during the work, not on whoever happened to be
/// healthiest when the player pressed a button.
///
/// Deterministic like the rest of the sim: outcomes are seeded by
/// `(mapSeed, settlementID, poiID, tick)`, never by the frame clock.
public enum LocalPOIEngine {
    /// Where the party forms up and returns to.
    public static let heart = LocalPoint(x: 0.5, y: 0.5)
    /// Ticks of walking per unit of normalised map distance.
    ///
    /// This was 26, which read as "roughly a season's march each way" — but the
    /// map it crosses is the settlement's *own valley*, the ground its farmers
    /// walk to work every morning. A party took months of game time and half an
    /// hour of real time to reach a cave the colony can see from its doorstep.
    ///
    /// **Halved again to 4 on 2026-08-18**, because 8 was still measured against
    /// the wrong thing. A tick is *two* real minutes, and the far side of the
    /// valley is about 0.62 from the heart: at 8 that is five ticks out and five
    /// back, so twenty real minutes of a party being a dot on a road before the
    /// place is even reached — on top of the work, which for a cave is another
    /// ten ticks. The trip has to be a trip; it does not have to be the longest
    /// thing in the game. At 4 the walk is two or three ticks each way and the
    /// **work** is the bulk of the expedition, which is the right way round.
    ///
    /// `roundTripTicks` is what to reason about when tuning this — the number a
    /// player actually waits out — and `POIInspectorCard` shows it before they
    /// commit to it.
    static let travelTicksPerDistance: Double = 4

    // MARK: - Ordering a visit

    /// Sends a party out to work `poiID`. Returns the updated world, or `nil`
    /// when the order cannot be given — the place is undiscovered, picked
    /// clean, still resting, already has a party out, or the colony has nobody
    /// to spare.
    public static func dispatch(
        _ state: WorldState,
        settlementID: UUID,
        poiID: Int,
        registry: GameDataRegistry
    ) -> WorldState? {
        guard let seat = state.settlements.firstIndex(where: { $0.id == settlementID }),
              let map = state.settlements[seat].localMap,
              let poi = map.pois.first(where: { $0.id == poiID })
        else { return nil }

        let ticksPerYear = max(1, registry.config.ticksPerYear)
        guard poi.isWorkable(tick: state.tick, ticksPerYear: ticksPerYear),
              !state.settlements[seat].hasPartyOut(poiID: poiID)
        else { return nil }

        let party = chooseParty(state.settlements[seat], for: poi.kind, ticksPerYear: ticksPerYear)
        guard !party.isEmpty else { return nil }

        var s = state
        var rng = SeededRNG(seed: poiSeed(mapSeed: s.mapSeed, settlementID: settlementID,
                                          poiID: poiID, tick: s.tick))
        let expedition = POIExpedition(
            id: rng.nextUUID(),
            poiID: poiID,
            memberIDs: party,
            departedTick: s.tick,
            travelTicks: travelTicks(to: poi.position),
            workTicks: poi.kind.workTicks)

        for i in s.settlements[seat].pawns.indices where party.contains(s.settlements[seat].pawns[i].id) {
            s.settlements[seat].pawns[i].expeditionID = expedition.id
        }
        s.settlements[seat].expeditions.append(expedition)
        s.settlements[seat].journal.append(
            tick: s.tick, kind: .work, text: departureLine(poi.kind, party: party.count))
        return s
    }

    /// The whole outing, end to end: out, work, and home again.
    ///
    /// The one number worth tuning against, because it is the one the player
    /// waits through. Stated here rather than recomputed at each call site —
    /// the inspector card was doing the `× 2 + workTicks` arithmetic itself,
    /// which is a formula in two places waiting to disagree.
    public static func roundTripTicks(to poi: LocalPOI) -> Int {
        travelTicks(to: poi.position) * 2 + poi.kind.workTicks
    }

    /// How long the walk out takes, from how far the place is.
    public static func travelTicks(to position: LocalPoint) -> Int {
        let dx = position.x - heart.x, dy = position.y - heart.y
        return max(1, Int((( dx * dx + dy * dy).squareRoot() * travelTicksPerDistance).rounded()))
    }

    /// Who goes: adults who are fit, free, and best at what the place asks for.
    /// Deterministic — ranked by skill, then by id, never by chance.
    public static func chooseParty(
        _ settlement: Settlement, for kind: LocalPOIKind, ticksPerYear: Int
    ) -> [UUID] {
        // The colony's standing roster comes first: a town that has said nobody
        // leaves sends nobody, whatever is out there.
        guard settlement.policy.roster != .nobody else { return [] }
        let wanted = kind.wantedSkill
        // "Spare hands only" means the trades the orders marked as priority
        // keep their people — the mines stay manned while the ruins call.
        let protected = settlement.policy.roster == .spareHands
            ? settlement.policy.protectedTrades : []
        let eligible = settlement.pawns
            .filter { $0.isAdult(ticksPerYear: ticksPerYear) && !$0.isBroken
                      && !$0.isAway && $0.health >= 40
                      && !protected.contains($0.assignedWork) }
            .sorted {
                let a = $0.skill(wanted), b = $1.skill(wanted)
                if a != b { return a > b }
                return $0.id.uuidString < $1.id.uuidString
            }
        // Never strip the settlement bare: a colony of four does not send three
        // of them down a cave.
        let spare = max(0, eligible.count - 2)
        return eligible.prefix(min(kind.partySize, spare)).map(\.id)
    }

    // MARK: - The journey

    /// Advances every party this settlement has out, on one **action step**.
    ///
    /// Parties used to move a whole world tick at a time — a real minute per
    /// stride — and the canvas covered the gap by interpolating between those
    /// jumps. That interpolation was a guess about a position the simulation
    /// never actually held. On the action grid the position exists, eight times
    /// finer, so what the renderer draws is a reading of the world.
    public static func advanceStep(
        _ settlement: Settlement, clock: WorldClock, mapSeed: UInt64, registry: GameDataRegistry
    ) -> Settlement {
        guard !settlement.expeditions.isEmpty else { return settlement }
        var s = settlement

        for index in s.expeditions.indices {
            // They walk up to the place: what is in it is laid out here, once.
            if s.expeditions[index].arrivesAtSite(clock) {
                s = openTheSite(s, expeditionIndex: index, mapSeed: mapSeed)
                s = rollHazard(s, expeditionIndex: index, tick: clock.tick, mapSeed: mapSeed)
            }
            // …and then they work it, a step at a time, exactly as a raid is
            // fought. This is the whole of "an expedition with a goal": there
            // is something in there, it takes time, and it can go badly.
            if s.expeditions[index].phase(at: clock) == .working {
                s = SiteVisitEngine.advanceStep(
                    s, expeditionIndex: index, step: clock.absoluteStep, registry: registry)
            }
        }

        // Home again: pay out, free the hands, and let the journal say so.
        for expedition in s.expeditions where expedition.isFinished(at: clock) {
            s = resolve(s, expedition: expedition, tick: clock.tick,
                        mapSeed: mapSeed, registry: registry)
        }
        s.expeditions.removeAll { $0.isFinished(at: clock) }
        return s
    }

    /// Runs a whole world tick's worth of action steps. Kept for callers that
    /// think in world ticks — the tick loop itself steps one at a time.
    public static func advanceOneTick(
        _ settlement: Settlement, tick: Int, mapSeed: UInt64, registry: GameDataRegistry
    ) -> Settlement {
        var s = settlement
        for step in 0..<WorldClock.actionStepsPerTick {
            s = advanceStep(s, clock: WorldClock(tick: tick, step: step),
                            mapSeed: mapSeed, registry: registry)
        }
        return s
    }

    /// Lays out what is actually in the place, the moment the party reaches it.
    ///
    /// Seeded from `(mapSeed, poi, departure)` rather than from the tick, so a
    /// party sent twice to the same ruin in the same year meets the same room —
    /// and one sent a decade later does not.
    private static func openTheSite(
        _ settlement: Settlement, expeditionIndex index: Int, mapSeed: UInt64
    ) -> Settlement {
        var s = settlement
        let expedition = s.expeditions[index]
        guard expedition.site == nil,
              let poi = s.localMap?.pois.first(where: { $0.id == expedition.poiID })
        else { return s }
        let seed = poiSeed(mapSeed: mapSeed, settlementID: s.id,
                           poiID: poi.id, tick: expedition.departedTick) ^ 0x51_7E
        let site = SiteVisitEngine.lay(out: poi, party: expedition.memberIDs, seed: seed)
        guard !site.things.isEmpty else { return s }
        s.expeditions[index].site = site
        return s
    }

    /// Rolls the danger of a place on the party working it.
    private static func rollHazard(
        _ settlement: Settlement, expeditionIndex: Int, tick: Int, mapSeed: UInt64
    ) -> Settlement {
        var s = settlement
        let expedition = s.expeditions[expeditionIndex]
        guard let poi = s.localMap?.pois.first(where: { $0.id == expedition.poiID }),
              poi.kind.hazardChance > 0 else { return s }

        var rng = SeededRNG(seed: poiSeed(mapSeed: mapSeed, settlementID: s.id,
                                          poiID: expedition.poiID, tick: tick))
        guard rng.nextUnit() < poi.kind.hazardChance else { return s }
        // Whoever is standing under it — one of the party, not a bystander at
        // home who never left the settlement.
        let candidates = expedition.memberIDs
        guard !candidates.isEmpty else { return s }
        let victimID = candidates[min(candidates.count - 1, Int(rng.nextUnit() * Double(candidates.count)))]
        guard let i = s.pawns.firstIndex(where: { $0.id == victimID }) else { return s }

        let wound = poi.kind.hazardDamage * CombatEngine.woundMultiplier(s.pawns[i])
        s.pawns[i].health = max(0, s.pawns[i].health - wound)
        s.expeditions[expeditionIndex].casualtyID = victimID
        s.expeditions[expeditionIndex].casualtyDied = s.pawns[i].health <= 0
        return s
    }

    /// The party is home: apply what the place gave, free the hands, and write
    /// the day into the diary.
    private static func resolve(
        _ settlement: Settlement, expedition: POIExpedition, tick: Int,
        mapSeed: UInt64, registry: GameDataRegistry
    ) -> Settlement {
        var s = settlement
        guard let map = s.localMap,
              let poiIndex = map.pois.firstIndex(where: { $0.id == expedition.poiID })
        else { return freeMembers(s, of: expedition) }

        let poi = map.pois[poiIndex]
        var rng = SeededRNG(seed: poiSeed(mapSeed: mapSeed, settlementID: s.id,
                                          poiID: poi.id, tick: expedition.departedTick))
        // Each return trip to a finite place digs deeper for less.
        let depletion = poi.kind.isRenewable ? 1 : max(0.45, 1 - Double(poi.visits) * 0.3)

        let casualtyName = expedition.casualtyID
            .flatMap { id in s.pawns.first { $0.id == id }?.name }
        // Who actually walked there, for the places that reward the *party*
        // rather than the colony — a hermit teaches the people in front of him.
        let party = s.pawns.filter { $0.expeditionID == expedition.id }.map(\.id)
        var outcome = work(&s, poi: poi, depletion: depletion, party: party,
                           registry: registry, rng: &rng)
        outcome = outcome.with(casualtyName: casualtyName, died: expedition.casualtyDied)
        // What they actually got the lid off. A place's table says what it is
        // *worth*; this is what came home in somebody's hands, and a party
        // driven back out by whatever was living in there comes home with less.
        s = carryHome(s, expedition: expedition, registry: registry, rng: &rng)

        // The dead do not come home.
        if expedition.casualtyDied, let id = expedition.casualtyID,
           let i = s.pawns.firstIndex(where: { $0.id == id }) {
            s.pawns.remove(at: i)
            s.deathTallies[PawnDeathCause.accident.rawValue, default: 0] += 1
            s.stats.morale = max(0, s.stats.morale - 8)
        }

        // Read the map back rather than writing the stale copy taken above: a
        // watchtower charts ground *during* `work`, and assigning the old value
        // would put the fog straight back.
        if var worked = s.localMap, worked.pois.indices.contains(poiIndex) {
            worked.pois[poiIndex].visits = poi.visits + 1
            worked.pois[poiIndex].lastVisitTick = tick
            s.localMap = worked
        }
        s.journal.append(tick: tick, kind: journalKind(poi.kind), text: outcome.narrative)
        return freeMembers(s, of: expedition)
    }

    /// Puts the party back on the colony's books.
    private static func freeMembers(_ settlement: Settlement, of expedition: POIExpedition) -> Settlement {
        var s = settlement
        for i in s.pawns.indices where s.pawns[i].expeditionID == expedition.id {
            s.pawns[i].expeditionID = nil
        }
        return s
    }

    /// Dispatches to what this kind of place actually does to the colony.
    static func work(
        _ s: inout Settlement, poi: LocalPOI, depletion: Double, party: [UUID] = [],
        registry: GameDataRegistry, rng: inout SeededRNG
    ) -> LocalPOIOutcome {
        switch poi.kind {
        case .ruins:    return siftRuins(&s, poi: poi, depletion: depletion, registry: registry, rng: &rng)
        case .cave:     return workCave(&s, poi: poi, depletion: depletion)
        case .treasure: return emptyCache(&s, poi: poi, depletion: depletion, registry: registry, rng: &rng)
        case .wreck:    return stripWreck(&s, poi: poi, depletion: depletion)
        case .spring:   return drinkSpring(&s)
        case .shrine:   return keepVigil(&s)
        case .orchard:  return pickOrchard(&s, depletion: depletion)
        case .hermit:   return learnFromHermit(&s, party: party, rng: &rng)
        case .watchtower: return climbTower(&s, poi: poi)
        case .saltPan:  return rakeSalt(&s, poi: poi, depletion: depletion)
        case .barrow:   return openBarrow(&s, registry: registry, rng: &rng)
        case .starfall: return quarryStar(&s, registry: registry, rng: &rng)
        }
    }

    // MARK: - The places

    /// Scholars go back over ground the scouts only glanced at.
    private static func siftRuins(
        _ s: inout Settlement, poi: LocalPOI, depletion: Double,
        registry: GameDataRegistry, rng: inout SeededRNG
    ) -> LocalPOIOutcome {
        let rewards = Resources([
            .knowledge: (22 * depletion).rounded(),
            .influence: (8 * depletion).rounded()
        ])
        grant(&s, rewards)
        let item = dropItem(&s, registry: registry, rarityBias: 0, rng: &rng)
        return LocalPOIOutcome(
            kind: .ruins, rewards: rewards, itemFound: item,
            visitsRemaining: poi.kind.maxVisits - poi.visits - 1,
            narrative: LocalizedText(values: [
                .en: "The party came back from the ruins with \(haul(rewards))."
                    + (item.map { " Among the rubble: \($0.resolve(.en))." } ?? ""),
                .cs: "Výprava se vrátila ze zřícenin — \(haul(rewards))."
                    + (item.map { " Mezi sutinami: \($0.resolve(.cs))." } ?? "")]))
    }

    /// Cutting stone out of a cave is work, and the roof does not always hold.
    private static func workCave(
        _ s: inout Settlement, poi: LocalPOI, depletion: Double
    ) -> LocalPOIOutcome {
        let rewards = Resources([.materials: (34 * depletion).rounded()])
        grant(&s, rewards)
        return LocalPOIOutcome(
            kind: .cave, rewards: rewards,
            visitsRemaining: poi.kind.maxVisits - poi.visits - 1,
            narrative: LocalizedText(values: [
                .en: "The cutting crew hauled \(haul(rewards)) out of the deep cave.",
                .cs: "Parta lamačů vytahala z hluboké jeskyně \(haul(rewards))."]))
    }

    /// Whoever buried it is long past minding.
    private static func emptyCache(
        _ s: inout Settlement, poi: LocalPOI, depletion: Double,
        registry: GameDataRegistry, rng: inout SeededRNG
    ) -> LocalPOIOutcome {
        let rewards = Resources([
            .materials: (20 * depletion).rounded(),
            .influence: (16 * depletion).rounded()
        ])
        grant(&s, rewards)
        let item = dropItem(&s, registry: registry, rarityBias: 2, rng: &rng)
        return LocalPOIOutcome(
            kind: .treasure, rewards: rewards, itemFound: item, visitsRemaining: 0,
            narrative: LocalizedText(values: [
                .en: "The cache gave up everything it held: \(haul(rewards))."
                    + (item.map { " Wrapped in oilcloth: \($0.resolve(.en))." } ?? ""),
                .cs: "Skrýš vydala všechno, co v ní bylo — \(haul(rewards))."
                    + (item.map { " Zabalené v plátně: \($0.resolve(.cs))." } ?? "")]))
    }

    /// Timber, iron and whatever the drivers were carrying when it went over.
    private static func stripWreck(
        _ s: inout Settlement, poi: LocalPOI, depletion: Double
    ) -> LocalPOIOutcome {
        let rewards = Resources([
            .materials: (26 * depletion).rounded(),
            .food: (12 * depletion).rounded()
        ])
        grant(&s, rewards)
        return LocalPOIOutcome(
            kind: .wreck, rewards: rewards,
            visitsRemaining: poi.kind.maxVisits - poi.visits - 1,
            narrative: LocalizedText(values: [
                .en: "The wreck was stripped for \(haul(rewards)).",
                .cs: "Z vraku se sneslo \(haul(rewards))."]))
    }

    /// The party fetches the water, and the whole colony is better for it.
    private static func drinkSpring(_ s: inout Settlement) -> LocalPOIOutcome {
        for i in s.pawns.indices {
            s.pawns[i].health = min(100, s.pawns[i].health + 14)
        }
        s.stats.morale = min(100, s.stats.morale + 4)
        return LocalPOIOutcome(
            kind: .spring, rewards: Resources([:]), visitsRemaining: nil,
            narrative: LocalizedText(values: [
                .en: "The water carriers came back from the spring. The sick mended.",
                .cs: "Nosiči se vrátili od pramene. Nemocným se ulevilo."]))
    }

    /// An old altar, a night of it, and a people surer of themselves.
    private static func keepVigil(_ s: inout Settlement) -> LocalPOIOutcome {
        for i in s.pawns.indices {
            s.pawns[i].needs.recreation = min(100, s.pawns[i].needs.recreation + 12)
        }
        s.stats.morale = min(100, s.stats.morale + 6)
        let rewards = Resources([.influence: 10])
        grant(&s, rewards)
        if s.faith.cultID != nil {
            s.faith.faith = min(100, s.faith.faith + 10)
        }
        return LocalPOIOutcome(
            kind: .shrine, rewards: rewards, visitsRemaining: nil,
            narrative: LocalizedText(values: [
                .en: "The pilgrims came home from the old shrine, lighter of heart.",
                .cs: "Poutníci se vrátili od staré svatyně s lehčím srdcem."]))
    }

    // MARK: - The places (added because six of them was an evening's worth)

    /// Somebody's farm, a long time ago. It has not stopped fruiting because
    /// they stopped coming.
    private static func pickOrchard(
        _ s: inout Settlement, depletion: Double
    ) -> LocalPOIOutcome {
        let rewards = Resources([.food: (46 * depletion).rounded()])
        grant(&s, rewards)
        s.stats.morale = min(100, s.stats.morale + 2)
        return LocalPOIOutcome(
            kind: .orchard, rewards: rewards, visitsRemaining: nil,
            narrative: LocalizedText(values: [
                .en: "The pickers came home under \(haul(rewards)) of fruit. It bears again next year.",
                .cs: "Česáči se vrátili obtěžkaní — \(haul(rewards)). Za rok to obrodí znovu."]))
    }

    /// The one place that pays the *party* and not the colony: he teaches what
    /// he knows to the people standing in front of him, and they carry it home
    /// in their hands rather than in a sack.
    ///
    /// Deliberately the trade each of them is already best at — a hermit who
    /// turned a farmer into a mediocre scholar would be a worse teacher than
    /// one who made a good farmer better.
    private static func learnFromHermit(
        _ s: inout Settlement, party: [UUID], rng: inout SeededRNG
    ) -> LocalPOIOutcome {
        var taught: [String] = []
        for id in party {
            guard let i = s.pawns.firstIndex(where: { $0.id == id }) else { continue }
            let best = WorkKind.allCases
                .filter { $0 != .idle }
                .max(by: { s.pawns[i].skill($0) < s.pawns[i].skill($1) }) ?? .farming
            s.pawns[i].skills[best] = min(20, s.pawns[i].skill(best) + 1)
            s.pawns[i].needs.recreation = min(100, s.pawns[i].needs.recreation + 10)
            taught.append(s.pawns[i].name)
        }
        let rewards = Resources([.knowledge: rng.nextUnit() < 0.5 ? 10 : 14])
        grant(&s, rewards)
        let names = taught.isEmpty ? nil : taught.joined(separator: ", ")
        return LocalPOIOutcome(
            kind: .hermit, rewards: rewards, visitsRemaining: nil,
            narrative: LocalizedText(values: [
                .en: "The hermit talked for three days and sent them back better at their trades."
                    + (names.map { " (\($0))" } ?? ""),
                .cs: "Poustevník mluvil tři dny a poslal je zpátky lepší ve svém řemesle."
                    + (names.map { " (\($0))" } ?? "")]))
    }

    /// Four hundred years of stair, and at the top of it the country lays
    /// itself out. The only place that pays in *map*.
    private static func climbTower(_ s: inout Settlement, poi: LocalPOI) -> LocalPOIOutcome {
        let before = s.localMap?.exploredCells.count ?? 0
        if var map = s.localMap {
            // A wide sweep from a high place — worth several seasons of walking.
            map.reveal(around: poi.position, radius: 0.34)
            s.localMap = map
        }
        let charted = (s.localMap?.exploredCells.count ?? 0) - before
        let rewards = Resources([.influence: 12])
        grant(&s, rewards)
        return LocalPOIOutcome(
            kind: .watchtower, rewards: rewards,
            visitsRemaining: poi.kind.maxVisits - poi.visits - 1,
            narrative: LocalizedText(values: [
                .en: "From the tower's head they drew the country: \(charted) fresh stretches of it.",
                .cs: "Z hlavy věže obkreslili kraj — \(charted) nových kusů země."]))
    }

    /// Salt is the difference between meat and meat that keeps. It arrives as
    /// food because that is what it *does*: a winter's worth of it survives.
    private static func rakeSalt(
        _ s: inout Settlement, poi: LocalPOI, depletion: Double
    ) -> LocalPOIOutcome {
        let rewards = Resources([
            .food: (30 * depletion).rounded(),
            .influence: (10 * depletion).rounded()
        ])
        grant(&s, rewards)
        return LocalPOIOutcome(
            kind: .saltPan, rewards: rewards,
            visitsRemaining: poi.kind.maxVisits - poi.visits - 1,
            narrative: LocalizedText(values: [
                .en: "They raked the pan white-handed and carried back \(haul(rewards)).",
                .cs: "Shrabali solisko do bíla a přinesli \(haul(rewards))."]))
    }

    /// Grave goods, and the price of taking them. The richest single item drop
    /// in the game, and the colony is not glad about it.
    private static func openBarrow(
        _ s: inout Settlement, registry: GameDataRegistry, rng: inout SeededRNG
    ) -> LocalPOIOutcome {
        let rewards = Resources([.influence: 24, .materials: 12])
        grant(&s, rewards)
        let item = dropItem(&s, registry: registry, rarityBias: 4, chance: 0.75, rng: &rng)
        // Robbing the dead is not free, and a colony with a faith minds more.
        let cost = s.faith.cultID != nil ? 9.0 : 5.0
        s.stats.morale = max(0, s.stats.morale - cost)
        if s.faith.cultID != nil {
            s.faith.faith = max(0, s.faith.faith - 6)
        }
        return LocalPOIOutcome(
            kind: .barrow, rewards: rewards, itemFound: item, visitsRemaining: 0,
            narrative: LocalizedText(values: [
                .en: "They opened the mound and took \(haul(rewards)) from it."
                    + (item.map { " On the breastbone: \($0.resolve(.en))." } ?? "")
                    + " Nobody spoke on the walk home.",
                .cs: "Otevřeli mohylu a odnesli si \(haul(rewards))."
                    + (item.map { " Na hrudní kosti: \($0.resolve(.cs))." } ?? "")
                    + " Cestou domů nikdo nepromluvil."]))
    }

    /// Whatever it is, it is not stone, and it is worth every day of the walk.
    private static func quarryStar(
        _ s: inout Settlement, registry: GameDataRegistry, rng: inout SeededRNG
    ) -> LocalPOIOutcome {
        let rewards = Resources([.materials: 40, .knowledge: 34])
        grant(&s, rewards)
        let item = dropItem(&s, registry: registry, rarityBias: 5, chance: 0.85, rng: &rng)
        s.stats.morale = min(100, s.stats.morale + 5)
        return LocalPOIOutcome(
            kind: .starfall, rewards: rewards, itemFound: item, visitsRemaining: 0,
            narrative: LocalizedText(values: [
                .en: "They cut the star out of its crater: \(haul(rewards))."
                    + (item.map { " The smiths made of it: \($0.resolve(.en))." } ?? ""),
                .cs: "Vysekali hvězdu z kráteru — \(haul(rewards))."
                    + (item.map { " Kováři z ní udělali: \($0.resolve(.cs))." } ?? "")]))
    }

    // MARK: - Helpers

    /// The journal's line for a party setting out.
    static func departureLine(_ kind: LocalPOIKind, party: Int) -> LocalizedText {
        LocalizedText(values: [
            .en: "\(party) set out for the \(kind.plainName.resolve(.en)).",
            .cs: "\(party) \(party == 1 ? "člověk vyrazil" : party < 5 ? "lidé vyrazili" : "lidí vyrazilo") k \(kind.plainNameDative)."])
    }

    /// "18 materials and 6 influence" — so the diary line, and the toast made
    /// from it, actually says what the trip was worth.
    static func haul(_ rewards: Resources) -> String {
        let parts = ResourceType.allCases
            .filter { rewards[$0] > 0 }
            .map { "\(Int($0 == .food ? rewards[$0] : rewards[$0])) \($0.rawValue)" }
        guard !parts.isEmpty else { return "nothing but the walk" }
        if parts.count == 1 { return parts[0] }
        return parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
    }

    /// Adds rewards to the settlement's own stores, clamped to capacity. Local
    /// work fills the local granary — unlike `SiteEngine`, which is the whole
    /// realm's business and grants globally.
    private static func grant(_ s: inout Settlement, _ rewards: Resources) {
        for resource in ResourceType.allCases where rewards[resource] != 0 {
            s.storage[resource] = min(s.storageCapacity[resource], s.storage[resource] + rewards[resource])
        }
    }

    /// Rolls a single item drop into the settlement's inventory and returns its
    /// display name. Local finds are humbler than a dungeon's: most trips home
    /// carry nothing but the goods.
    private static func dropItem(
        _ s: inout Settlement, registry: GameDataRegistry, rarityBias: Double,
        chance: Double = 0.35, rng: inout SeededRNG
    ) -> LocalizedText? {
        guard rng.nextUnit() < chance else { return nil }
        let defs = SiteEngine.lootPool(registry: registry)
        guard !defs.isEmpty else { return nil }
        let weights = defs.map { SiteEngine.rarityWeight($0.rarity, rarityBias) }
        guard let index = rng.weightedIndex(weights) else { return nil }
        let def = defs[index]
        s.inventory.append(ItemInstance(id: rng.nextUUID(), definitionID: def.id))
        // Interpolating the `LocalizedText` itself would print the struct.
        return LocalizedText(values: [
            .en: "\(def.name.resolve(.en)) (\(def.rarity.rawValue))",
            .cs: "\(def.name.resolve(.cs)) (\(def.rarity.rawValue))"])
    }

    /// Puts the contents of every cache the party actually opened into the
    /// stores, and writes what happened in there into the journal.
    private static func carryHome(
        _ settlement: Settlement, expedition: POIExpedition,
        registry: GameDataRegistry, rng: inout SeededRNG
    ) -> Settlement {
        var s = settlement
        guard let site = expedition.site else { return s }
        for (itemID, count) in site.loot.sorted(by: { $0.key < $1.key }) {
            guard registry.item(itemID) != nil else { continue }
            for _ in 0..<count {
                s.inventory.append(ItemInstance(id: rng.nextUUID(), definitionID: itemID))
            }
        }
        // One line, not a feed: the shape of the visit, and what it left.
        let opened = site.things.count { $0.kind == .cache && $0.done }
        let killed = site.beats.count { $0.kind == .killed }
        let left = site.unopenedCaches
        guard opened + killed + left > 0 else { return s }
        var en = "The party opened \(opened) of what was sealed there"
        var cs = "Výprava otevřela \(opened) z toho, co tam bylo zapečetěné"
        if killed > 0 {
            en += ", and had to kill \(killed) to do it"
            cs += " — a musela pro to \(killed)krát zabíjet"
        }
        if left > 0 {
            en += ". \(left) they could not reach."
            cs += ". \(left) nedosáhli."
        } else {
            en += "."
            cs += "."
        }
        s.journal.append(tick: expedition.departedTick, kind: .work,
                         text: LocalizedText(values: [.en: en, .cs: cs]))
        return s
    }

    /// Which diary voice the moment belongs to.
    private static func journalKind(_ kind: LocalPOIKind) -> ColonyLogEntry.Kind {
        switch kind {
        case .shrine, .barrow: return .faith
        case .cave, .saltPan, .orchard: return .work
        default: return .discovery
        }
    }

    static func poiSeed(mapSeed: UInt64, settlementID: UUID, poiID: Int, tick: Int) -> UInt64 {
        var h = mapSeed &* 0x9E37_79B9_7F4A_7C15
        let b = settlementID.uuid
        h ^= UInt64(b.0) << 56 | UInt64(b.1) << 48 | UInt64(b.2) << 40 | UInt64(b.3) << 32
            | UInt64(b.4) << 24 | UInt64(b.5) << 16 | UInt64(b.6) << 8 | UInt64(b.7)
        h = (h ^ UInt64(bitPattern: Int64(poiID))) &* 0xD1B5_4A32_D192_ED03
        h = (h ^ UInt64(bitPattern: Int64(tick))) &* 0xCBF2_9CE4_8422_2325
        return h ^ (h >> 31)
    }
}

private extension LocalPOIOutcome {
    /// The casualty is only known once the party is home, so the outcome is
    /// built first and told who limped back second.
    func with(casualtyName: String?, died: Bool) -> LocalPOIOutcome {
        LocalPOIOutcome(kind: kind, rewards: rewards, casualtyName: casualtyName,
                        died: died, itemFound: itemFound, visitsRemaining: visitsRemaining,
                        narrative: casualtyName.map { name in
                            LocalizedText(values: [
                                .en: narrative.resolve(.en) + (died
                                    ? " \(name) did not come home."
                                    : " \(name) was hurt out there."),
                                .cs: narrative.resolve(.cs) + (died
                                    ? " \(name) se nevrátil."
                                    : " \(name) se vrátil zraněný.")])
                        } ?? narrative)
    }
}
