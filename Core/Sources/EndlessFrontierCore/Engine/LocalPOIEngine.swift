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
    /// Ticks of walking per unit of normalised map distance. The valley is one
    /// unit across, so the far corner is roughly a season's march each way.
    static let travelTicksPerDistance: Double = 26

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
        let wanted = kind.wantedSkill
        let eligible = settlement.pawns
            .filter { $0.isAdult(ticksPerYear: ticksPerYear) && !$0.isBroken
                      && !$0.isAway && $0.health >= 40 }
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
            // The roof comes down on the step the work starts, on one of the
            // people who actually went.
            if s.expeditions[index].arrivesAtSite(clock) {
                s = rollHazard(s, expeditionIndex: index, tick: clock.tick, mapSeed: mapSeed)
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
        guard var map = s.localMap,
              let poiIndex = map.pois.firstIndex(where: { $0.id == expedition.poiID })
        else { return freeMembers(s, of: expedition) }

        let poi = map.pois[poiIndex]
        var rng = SeededRNG(seed: poiSeed(mapSeed: mapSeed, settlementID: s.id,
                                          poiID: poi.id, tick: expedition.departedTick))
        // Each return trip to a finite place digs deeper for less.
        let depletion = poi.kind.isRenewable ? 1 : max(0.45, 1 - Double(poi.visits) * 0.3)

        let casualtyName = expedition.casualtyID
            .flatMap { id in s.pawns.first { $0.id == id }?.name }
        var outcome = work(&s, poi: poi, depletion: depletion, registry: registry, rng: &rng)
        outcome = outcome.with(casualtyName: casualtyName, died: expedition.casualtyDied)

        // The dead do not come home.
        if expedition.casualtyDied, let id = expedition.casualtyID,
           let i = s.pawns.firstIndex(where: { $0.id == id }) {
            s.pawns.remove(at: i)
            s.deathTallies[PawnDeathCause.accident.rawValue, default: 0] += 1
            s.stats.morale = max(0, s.stats.morale - 8)
        }

        map.pois[poiIndex].visits = poi.visits + 1
        map.pois[poiIndex].lastVisitTick = tick
        s.localMap = map
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
        _ s: inout Settlement, poi: LocalPOI, depletion: Double,
        registry: GameDataRegistry, rng: inout SeededRNG
    ) -> LocalPOIOutcome {
        switch poi.kind {
        case .ruins:    return siftRuins(&s, poi: poi, depletion: depletion, registry: registry, rng: &rng)
        case .cave:     return workCave(&s, poi: poi, depletion: depletion)
        case .treasure: return emptyCache(&s, poi: poi, depletion: depletion, registry: registry, rng: &rng)
        case .wreck:    return stripWreck(&s, poi: poi, depletion: depletion)
        case .spring:   return drinkSpring(&s)
        case .shrine:   return keepVigil(&s)
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
            s.storage[resource] = min(s.storageCapacity, s.storage[resource] + rewards[resource])
        }
    }

    /// Rolls a single item drop into the settlement's inventory and returns its
    /// display name. Local finds are humbler than a dungeon's: most trips home
    /// carry nothing but the goods.
    private static func dropItem(
        _ s: inout Settlement, registry: GameDataRegistry, rarityBias: Double, rng: inout SeededRNG
    ) -> LocalizedText? {
        guard rng.nextUnit() < 0.35 else { return nil }
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

    /// Which diary voice the moment belongs to.
    private static func journalKind(_ kind: LocalPOIKind) -> ColonyLogEntry.Kind {
        switch kind {
        case .shrine: return .faith
        case .cave: return .work
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
