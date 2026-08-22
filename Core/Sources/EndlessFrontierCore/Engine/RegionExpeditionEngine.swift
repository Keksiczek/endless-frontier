import Foundation

/// Sending people out of the valley — the last thing in the game that was still
/// a button.
///
/// `SiteEngine.interact` took a region id and handed back an outcome in one
/// call: nobody went, nobody was gone, nobody could fail, and a lost city three
/// regions away cost exactly what one next door did. The valley's own places
/// stopped working that way when `SiteVisitEngine` gave them a middle; this is
/// the same journey one scale up.
///
/// Hands leave the colony and are *not there* — the labour engine notices, and
/// a colony that sends four people to a dungeon is four short at home for as
/// long as the country is wide. Something happens at the far end. What comes
/// home is what they managed to take, and how much of the place they cleared
/// decides how much of its worth they got.
public enum RegionExpeditionEngine {

    /// Ticks of travel per hex of distance, one way. A neighbouring region is a
    /// few days; the far side of the map is a season.
    public static let travelTicksPerHex = 26
    /// The most a party will ever be gone one way, so an unreachable corner of
    /// the map is a long trip and not a lost generation.
    public static let travelCeiling = 260
    /// How long they work the place once they are there.
    public static let workTicks = 12
    /// At most this many go.
    public static let partySize = 4
    /// …and the colony is never stripped below this many hands at home.
    public static let keepAtHome = 4

    // MARK: - Sending them

    /// Sends a party from `settlementID` to the site in `regionID`.
    ///
    /// Returns nil when the order cannot be given: no active site, a party
    /// already on the road to it, or nobody the colony can spare.
    public static func dispatch(
        _ state: WorldState, settlementID: UUID, regionID: UUID,
        registry: GameDataRegistry
    ) -> WorldState? {
        guard let seat = state.settlements.firstIndex(where: { $0.id == settlementID }),
              let target = state.regions.first(where: { $0.id == regionID }),
              target.hasActiveSite,
              !state.regionExpeditions.contains(where: { $0.regionID == regionID })
        else { return nil }

        let ticksPerYear = max(1, registry.config.ticksPerYear)
        let party = chooseParty(state.settlements[seat], ticksPerYear: ticksPerYear)
        guard !party.isEmpty else { return nil }

        var s = state
        var rng = SeededRNG(seed: seed(mapSeed: s.mapSeed, regionID: regionID, tick: s.tick))
        let expedition = RegionExpedition(
            id: rng.nextUUID(), regionID: regionID, fromSettlementID: settlementID,
            memberIDs: party, departedTick: s.tick,
            travelTicks: travelTicks(from: s.settlements[seat], to: target, in: s),
            workTicks: workTicks)

        for index in s.settlements[seat].pawns.indices
        where party.contains(s.settlements[seat].pawns[index].id) {
            s.settlements[seat].pawns[index].expeditionID = expedition.id
        }
        s.regionExpeditions.append(expedition)
        // They walked it, so the ground remembers. Without this the roads only
        // ever appear along trade lanes and the country a colony *explores*
        // never wears a path — which is exactly the "bank with no reader" the
        // generation handoff is about, in my own new system.
        s = RoadEngine.travelled(s, route: routeHexes(from: s.settlements[seat],
                                                     to: target, in: s))
        s.settlements[seat].journal.append(
            tick: s.tick, kind: .work,
            text: LocalizedText(values: [
                .en: "\(party.count) set out for \(target.name) — \(expedition.travelTicks * 2 + workTicks) ticks there and back.",
                .cs: "\(party.count) vyrazilo k \(target.name) — tam a zpět \(expedition.travelTicks * 2 + workTicks) taktů."]))
        return s
    }

    /// How far it is, in ticks one way. Distance is the whole point: a ruin you
    /// can see from the walls and one across the map were the same button.
    static func travelTicks(
        from settlement: Settlement, to target: Region, in state: WorldState
    ) -> Int {
        guard let home = settlement.regionID,
              let seat = state.regions.first(where: { $0.id == home }) else {
            return travelTicksPerHex * 3
        }
        // Over the roads where there are any. `route` answers in plain-hex
        // equivalents, so a party crossing a fen pays for the fen and a party
        // on a made way through it does not — the reason a colony builds one.
        let byCoord = Dictionary(state.regions.map { ($0.coord, $0) }) { first, _ in first }
        let crossing = state.roads.route(from: seat.coord, to: target.coord,
                                         regions: byCoord)?.cost
            ?? Double(seat.coord.distance(to: target.coord))
        let ticks = Int((crossing * Double(travelTicksPerHex)).rounded())
        return min(travelCeiling, max(travelTicksPerHex, ticks))
    }

    /// The hexes a party sent to `target` will walk, for `RoadEngine.travelled`.
    static func routeHexes(
        from settlement: Settlement, to target: Region, in state: WorldState
    ) -> [HexCoord] {
        guard let home = settlement.regionID,
              let seat = state.regions.first(where: { $0.id == home }) else { return [] }
        let byCoord = Dictionary(state.regions.map { ($0.coord, $0) }) { first, _ in first }
        return state.roads.route(from: seat.coord, to: target.coord, regions: byCoord)?.hexes ?? []
    }

    /// Who goes: fit adults nobody at home is depending on, best scouts first.
    static func chooseParty(_ settlement: Settlement, ticksPerYear: Int) -> [UUID] {
        guard settlement.policy.roster != .nobody else { return [] }
        let protected = settlement.policy.roster == .spareHands
            ? settlement.policy.protectedTrades : []
        let eligible = settlement.pawns
            .filter { $0.isAdult(ticksPerYear: ticksPerYear) && !$0.isBroken
                      && !$0.isAway && $0.health >= 50
                      && !protected.contains($0.assignedWork) }
            .sorted {
                let a = $0.skill(.scouting), b = $1.skill(.scouting)
                if a != b { return a > b }
                return $0.id.uuidString < $1.id.uuidString
            }
        let spare = max(0, eligible.count - keepAtHome)
        return eligible.prefix(min(partySize, spare)).map(\.id)
    }

    // MARK: - The journey

    /// Carries every party on the road forward by one action step.
    public static func advanceStep(
        _ state: WorldState, clock: WorldClock, registry: GameDataRegistry
    ) -> WorldState {
        guard !state.regionExpeditions.isEmpty else { return state }
        var s = state

        for index in s.regionExpeditions.indices {
            let expedition = s.regionExpeditions[index]
            guard let seat = s.settlements.firstIndex(
                where: { $0.id == expedition.fromSettlementID }) else { continue }

            // They walk up to it: what is in it is laid out once.
            if expedition.arrives(at: clock.tick), clock.step == 0 {
                s.regionExpeditions[index].site = lay(
                    out: expedition, in: s, registry: registry)
            }
            // …and then they work it, exactly as a valley place is worked.
            guard expedition.phase(at: clock.tick) == .working,
                  let site = s.regionExpeditions[index].site else { continue }
            let worked = SiteVisitEngine.work(
                s.settlements[seat], site: site, party: expedition.memberIDs,
                step: clock.absoluteStep, registry: registry)
            s.settlements[seat] = worked.settlement
            s.regionExpeditions[index].site = worked.site
        }

        // Home again.
        for expedition in s.regionExpeditions where expedition.isFinished(at: clock.tick) {
            s = comeHome(s, expedition: expedition, registry: registry)
        }
        s.regionExpeditions.removeAll { $0.isFinished(at: clock.tick) }
        return s
    }

    /// What is waiting at the far end. Built from the region's own hazard, so a
    /// dead city out in bad country is a worse room than a barrow next door.
    static func lay(
        out expedition: RegionExpedition, in state: WorldState, registry: GameDataRegistry
    ) -> SiteEncounter? {
        guard let region = state.regions.first(where: { $0.id == expedition.regionID })
        else { return nil }
        // An outlaw camp is not a *find*: what is in it is the camp, and the
        // camp is a thing the world keeps. Laid out from its own strength,
        // its own kind and its own hoard — see `OutlawCampEngine.encounter`.
        if region.kind == .outlawCamp,
           let camp = state.camps.first(where: { $0.regionID == region.id }) {
            return OutlawCampEngine.encounter(
                for: camp, party: expedition.memberIDs, at: state.tick,
                seed: self.seed(mapSeed: state.mapSeed, regionID: region.id,
                                tick: expedition.departedTick) ^ 0x0A71)
        }
        // Reuse the valley's vocabulary: a place is a place. The region's kind
        // picks which of them it reads as, and its hazard says how bad.
        let kind: LocalPOIKind
        switch region.kind {
        case .ruins: kind = .ruins
        case .dungeon: kind = .barrow
        case .anomaly: kind = .starfall
        case .lostCity: kind = .treasure
        case .sanctuary: kind = .shrine
        default: kind = .ruins
        }
        let poi = LocalPOI(id: 0, kind: kind,
                           position: LocalPoint(x: 0.5, y: 0.5), discovered: true)
        let seed = self.seed(mapSeed: state.mapSeed, regionID: region.id,
                             tick: expedition.departedTick) ^ 0x5175
        var site = SiteVisitEngine.lay(out: poi, party: expedition.memberIDs, seed: seed)
        // Out in bad country, whatever is living there is worse.
        let harder = 1 + Double(region.hazardLevel) * 0.12
        for index in site.things.indices where site.things[index].kind != .cache {
            site.things[index].strength *= harder
        }
        return site
    }

    /// They walk back in: hands are free, the loot is unpacked, and the site's
    /// own reward is paid out **in proportion to how much of it they cleared**.
    static func comeHome(
        _ state: WorldState, expedition: RegionExpedition, registry: GameDataRegistry
    ) -> WorldState {
        var s = state
        guard let seat = s.settlements.firstIndex(
            where: { $0.id == expedition.fromSettlementID }) else { return s }
        for index in s.settlements[seat].pawns.indices
        where s.settlements[seat].pawns[index].expeditionID == expedition.id {
            s.settlements[seat].pawns[index].expeditionID = nil
        }

        let cleared = expedition.site?.progress ?? 0
        // Nothing at all got done: they were driven out, and the place keeps
        // what it holds — including the right to be tried again.
        guard cleared > 0.05 else {
            s.settlements[seat].journal.append(
                tick: s.tick, kind: .danger, text: LocalizedText(values: [
                    .en: "The party came back from the far country with nothing.",
                    .cs: "Výprava se z daleké země vrátila s prázdnou."]))
            return s
        }

        var rng = SeededRNG(seed: seed(mapSeed: s.mapSeed, regionID: expedition.regionID,
                                       tick: expedition.departedTick) ^ 0xC0FFEE)
        for (itemID, count) in (expedition.site?.loot ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard registry.item(itemID) != nil else { continue }
            for _ in 0..<count {
                s.settlements[seat].inventory.append(
                    ItemInstance(id: rng.nextUUID(), definitionID: itemID))
            }
        }

        // A camp pays in what it *took*, and the payment is the point: a raid
        // that emptied your granary is a raid you can go and undo. Kept off
        // the site table entirely — there is no loot table for a camp, only
        // the plunder it is holding.
        if let region = s.regions.first(where: { $0.id == expedition.regionID }),
           region.kind == .outlawCamp {
            let (after, clearing) = OutlawCampEngine.sacked(
                s, regionID: region.id, settlementIndex: seat, share: cleared)
            s = after
            if let clearing {
                s.settlements[seat].journal.append(
                    tick: s.tick, kind: clearing.broken ? .discovery : .danger,
                    text: clearing.broken
                        ? LocalizedText(values: [
                            .en: "\(clearing.campName.resolve(.en)) are broken up, and what they took is home.",
                            .cs: "\(clearing.campName.resolve(.cs)) jsou rozprášeni a co odnesli, je zpátky."])
                        : LocalizedText(values: [
                            .en: "The party bloodied \(clearing.campName.resolve(.en)) and came away.",
                            .cs: "Výprava potrápila \(clearing.campName.resolve(.cs)) a stáhla se."]))
            }
            return s
        }

        // The site's own table, scaled by what they actually got through.
        if let (after, outcome) = SiteEngine.interact(
            s, regionID: expedition.regionID, registry: registry) {
            s = after
            if cleared < 1 {
                // They left part of it: give back the share they did not earn.
                for resource in ResourceType.allCases where outcome.rewards[resource] > 0 {
                    let unearned = outcome.rewards[resource] * (1 - cleared)
                    s.settlements[seat].storage[resource] = max(
                        0, s.settlements[seat].storage[resource] - unearned)
                }
            }
            // `SiteOutcome.narrative` is a plain string — the world-map sites
            // predate `LocalizedText`, and translating them is a content job
            // the backlog already carries.
            s.settlements[seat].journal.append(
                tick: s.tick, kind: .discovery,
                text: LocalizedText(outcome.narrative))
        }
        return s
    }

    static func seed(mapSeed: UInt64, regionID: UUID, tick: Int) -> UInt64 {
        var h = mapSeed &* 0xD1B5_4A32_D192_ED03
        let b = regionID.uuid
        h ^= UInt64(b.0) << 56 | UInt64(b.1) << 48 | UInt64(b.2) << 40 | UInt64(b.3) << 32
            | UInt64(b.4) << 24 | UInt64(b.5) << 16 | UInt64(b.6) << 8 | UInt64(b.7)
        h = (h ^ UInt64(bitPattern: Int64(tick))) &* 0x9E37_79B9_7F4A_7C15
        return (h ^ (h >> 31)) | 1
    }
}
