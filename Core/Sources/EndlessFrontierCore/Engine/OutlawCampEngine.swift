import Foundation

/// **Where the raids come from.**
///
/// `BanditEngine` still answers *why* they come — a full granary, a road to
/// it, and not enough people watching. This answers *who*, and the difference
/// is the whole feature: a raid is now a thing a place did, so it arrives from
/// a direction on the map, it costs the camp what the fighting cost it, what
/// it carries off goes somewhere real, and a colony can walk out and take it
/// back.
///
/// The two constraints the design put on this before a line was written, both
/// of them measured faults from the old bandits:
///
/// - **Sizing must not be off the stores.** It was, which is why a band of
///   four attacked a colony of sixty-eight and the fight was over in six
///   seconds. A camp's strength is the camp's own, grown over time; the
///   stores decide only whether they bother walking.
/// - **They are still not a faction.** No standing, no grudge, no peace. See
///   `OutlawCamp`.
public enum OutlawCampEngine {

    /// Checked on this cadence, in ticks — the same one the old bandits used,
    /// so the odds below mean what they used to mean (rule 4).
    public static let interval = BanditEngine.interval

    /// How many camps a new world is founded with.
    ///
    /// Deliberately few. Every camp is a standing threat that grows, and the
    /// country is meant to have *somewhere* the outlaws are rather than a ring
    /// of them.
    public static let foundingCamps = 3

    /// How far out from the homeland a camp will settle. Close enough to be
    /// somebody's problem, far enough that it is not the first hex you walk
    /// into.
    public static let minimumDistance = 3

    /// What a raid costs the camp that sent it, as a share of its strength.
    /// They send people, not the whole camp — a camp that empties itself on
    /// one raid is a camp that only ever raids once.
    public static let raidShare = 0.55

    /// …and what is left of that when they walk home. The rest died at your
    /// wall, and `SiegeEngine.chargeAttacker` takes it off the camp.
    public static let minimumRaid = 12.0

    /// How long a camp lies low after a colony burns it out, in ticks.
    /// A season, so clearing one buys a summer rather than a century.
    public static let brokenForTicks = 15 * 60

    /// The ceiling a camp grows toward, as a multiple of what it was founded
    /// with. Growth is linear and bounded on purpose: an unbounded camp is a
    /// colony-killer by year two hundred, and rule 16's "a sink must scale
    /// with the world" is served by the *loot* term below rather than by
    /// letting the base run away.
    public static let ceilingMultiple = 4.0

    /// How much a camp fattens on what it takes. A colony that keeps losing
    /// its granary is feeding the people who took it.
    public static let strengthPerLoot = 0.06

    /// **…and what the country itself is worth to them**, per soul in its
    /// largest colony.
    ///
    /// Measured over two centuries: every camp sat pinned at its founding
    /// ceiling from year sixty on, so a warband of twenty-six walked at a
    /// colony of two hundred and sixty-one — which is not a threat, it is
    /// scenery. A place that empties itself into the hills grows the people
    /// living in them: outlaws are recruited out of the same country the
    /// colony is growing (rule 16 — a sink has to scale with the world, not
    /// with a building count).
    public static let ceilingPerSoul = 0.35

    // MARK: - Founding

    /// The camps a new world begins with.
    ///
    /// Placed like `GameWorldFactory.nativeTribes` — from the seed, in a
    /// stable order, far enough out to be a frontier problem — and the regions
    /// they sit on become `.outlawCamp`, so the map has a place to draw.
    ///
    /// Returns the camps *and* the regions with their kinds set, because a
    /// camp whose hex still reads as ordinary wilderness is exactly the
    /// "sim was right, the drawing never knew" fault this project keeps
    /// finding.
    public static func found(
        regions: [Region], tribes: [Tribe], seed: UInt64, language: GameLanguage
    ) -> (regions: [Region], camps: [OutlawCamp]) {
        var rng = SeededRNG(seed: seed ^ 0x0117_1A05_C0DE_0001)
        var out = regions
        let taken = Set(tribes.map(\.regionID))
        // Ordinary country, far enough out, nobody else's — in a stable order
        // so the same seed puts the same camps in the same hills.
        let candidates = regions.enumerated()
            .filter { $0.element.kind == .wilderness
                && !taken.contains($0.element.id)
                && $0.element.settlementIDs.isEmpty
                && $0.element.coord.distance(to: .origin) >= minimumDistance }
            .sorted {
                $0.element.coord.distance(to: .origin) != $1.element.coord.distance(to: .origin)
                    ? $0.element.coord.distance(to: .origin) < $1.element.coord.distance(to: .origin)
                    : $0.element.name < $1.element.name
            }
        guard !candidates.isEmpty else { return (out, []) }

        var camps: [OutlawCamp] = []
        var used: Set<Int> = []
        for index in 0..<foundingCamps {
            // Spread them around the ring rather than stacking them in the
            // nearest corner.
            let pick = candidates.first { !used.contains($0.offset) && $0.offset >= index * 3 }
                ?? candidates.first { !used.contains($0.offset) }
            guard let spot = pick else { break }
            used.insert(spot.offset)
            let kinds = OutlawCamp.Kind.allCases
            let kind = kinds[min(kinds.count - 1, Int(rng.nextUnit() * Double(kinds.count)))]
            out[spot.offset].kind = .outlawCamp
            camps.append(OutlawCamp(
                id: rng.nextUUID(),
                regionID: spot.element.id,
                kind: kind,
                name: name(kind: kind, place: spot.element.name, language: language, rng: &rng),
                strength: kind.foundingStrength * (0.85 + rng.nextUnit() * 0.3),
                foundedTick: 0))
        }
        return (out, camps)
    }

    /// What a camp is called. The place it sits on does the work — a colony
    /// that has heard of "the men in the Ashfell" knows where to go.
    static func name(
        kind: OutlawCamp.Kind, place: String, language: GameLanguage, rng: inout SeededRNG
    ) -> LocalizedText {
        switch kind {
        case .deserters:
            return LocalizedText(values: [
                .en: "The deserters of \(place)", .cs: "Zběhové z \(place)"])
        case .starving:
            return LocalizedText(values: [
                .en: "The hungry of \(place)", .cs: "Hladoví z \(place)"])
        case .hold:
            return LocalizedText(values: [
                .en: "The hold at \(place)", .cs: "Hnízdo u \(place)"])
        }
    }

    // MARK: - The tick

    /// Camps grow, and camps come down the road.
    ///
    /// World-level rather than per-settlement, because a raid **spends** the
    /// camp that sent it: the old per-settlement call had nowhere to write
    /// that back to, which is precisely why the bandits were weather rather
    /// than an enemy.
    public static func advanceOneTick(
        _ state: WorldState, registry: GameDataRegistry, tick: Int
    ) -> WorldState {
        guard tick % interval == 0, !state.camps.isEmpty else { return state }
        var s = state
        let ticksPerYear = max(1, registry.config.ticksPerYear)

        // 1. What a year in the hills does to them. Applied on the same
        //    cadence as the check rather than at the year boundary, so a camp
        //    is never a step-function the player can watch flip.
        let yearShare = Double(interval) / Double(ticksPerYear)
        // How big the country they live off has got. The largest colony, not
        // the sum: outlaws are a local problem, and three towns of eighty are
        // not one town of two hundred and forty to the people in the hills.
        let souls = Double(s.settlements.map(\.pawns.count).max() ?? 0)
        for index in s.camps.indices where s.camps[index].isActive(at: tick) {
            let camp = s.camps[index]
            let ceiling = camp.kind.foundingStrength * ceilingMultiple
                + camp.loot.total * strengthPerLoot
                + souls * ceilingPerSoul
            guard camp.strength < ceiling else { continue }
            s.camps[index].strength = min(
                ceiling, camp.strength + camp.kind.growthPerYear * yearShare)
        }

        // 2. …and who they visit. One settlement at a time: a warband is in
        //    one place, and two sieges opened on the same check would be two
        //    bands from one camp.
        for settlementIndex in s.settlements.indices {
            let settlement = s.settlements[settlementIndex]
            guard settlement.siege == nil,
                  settlement.pawns.count >= BanditEngine.minimumPopulation else { continue }
            let lure = BanditEngine.temptation(settlement)
            guard lure > 0 else { continue }

            var rng = SeededRNG(seed: BanditEngine.seed(
                mapSeed: s.mapSeed, settlementID: settlement.id, tick: tick) ^ 0x0A71_A05C_0BAD_0001)
            let odds = BanditEngine.baseChance * lure
                * (1 - BanditEngine.watchfulness(settlement, registry: registry))
            guard rng.nextUnit() < min(0.4, odds) else { continue }

            guard let campIndex = nearestCamp(to: settlement, in: s, at: tick) else {
                // No camp in this world — an old save, or every one of them
                // burned out. The conjured band is the fallback so a colony
                // never stops being worth robbing.
                s.settlements[settlementIndex] = BanditEngine.raid(
                    settlement, registry: registry, tick: tick, era: s.era,
                    lure: lure, rng: &rng)
                continue
            }
            s = send(s, campIndex: campIndex, settlementIndex: settlementIndex,
                     registry: registry, tick: tick, rng: &rng)
        }
        return s
    }

    /// The camp that would actually walk here: the nearest active one with
    /// anything left in it.
    static func nearestCamp(to settlement: Settlement, in state: WorldState, at tick: Int) -> Int? {
        guard let home = state.regions.first(where: { $0.id == settlement.regionID })
        else { return nil }
        var best: (index: Int, distance: Int)?
        for (index, camp) in state.camps.enumerated() {
            guard camp.isActive(at: tick), camp.strength >= minimumRaid,
                  let hills = state.regions.first(where: { $0.id == camp.regionID })
            else { continue }
            let distance = home.coord.distance(to: hills.coord)
            if best == nil || distance < best!.distance { best = (index, distance) }
        }
        return best?.index
    }

    /// **A camp sends a warband.** What it sends is its own strength, it walks
    /// in from where it lives, and it carries the arms its kind has.
    static func send(
        _ state: WorldState, campIndex: Int, settlementIndex: Int,
        registry: GameDataRegistry, tick: Int, rng: inout SeededRNG
    ) -> WorldState {
        var s = state
        let camp = s.camps[campIndex]
        let sent = max(minimumRaid, camp.strength * raidShare)
        let settlement = s.settlements[settlementIndex]

        s.settlements[settlementIndex] = SiegeEngine.begin(
            settlement,
            attackerStrength: sent,
            attackerName: camp.name.resolve(.en),
            attackerLabel: camp.name,
            // Deliberately no tribe. There is nobody to charge for this and
            // nobody to make peace with — see `OutlawCamp`.
            attackerTribeID: nil,
            attackerCampID: camp.id,
            fortification: settlement.stats.defense,
            tick: tick, registry: registry, seed: rng.next(),
            // They come in from where they live, like a neighbour's warband
            // does: the road they walk is a road you could have cut.
            approachBearing: Bearing.angle(
                fromRegion: settlement.regionID, towardRegion: camp.regionID, in: s),
            era: camp.armsEra(in: s.era),
            drawn: camp.drawn(for: sent))

        s.camps[campIndex].strength = max(0, camp.strength - sent)
        s.camps[campIndex].lastRaidTick = tick
        s.settlements[settlementIndex].journal.append(
            tick: tick, kind: .danger,
            text: LocalizedText(values: [
                .en: "\(camp.name.resolve(.en)) are on the granary road — \(placeName(of: camp, in: s, language: .en)).",
                .cs: "\(camp.name.resolve(.cs)) jsou na cestě k sýpce — \(placeName(of: camp, in: s, language: .cs))."]))
        return s
    }

    /// "…from the Ashfell, three days east." What the colony can actually say
    /// about where they came from, which is the whole difference from a band
    /// that appeared out of the weather.
    static func placeName(of camp: OutlawCamp, in state: WorldState, language: GameLanguage) -> String {
        guard let region = state.regions.first(where: { $0.id == camp.regionID })
        else { return language == .cs ? "odnikud" : "from nowhere" }
        return language == .cs ? "z kraje \(region.name)" : "out of \(region.name)"
    }

    // MARK: - What a fight costs them, and what it feeds them

    /// Charges the camp for the warband it sent, and credits it with whatever
    /// got past the door. The mirror of `SiegeEngine.chargeAttacker` for a
    /// people; kept beside it in `ActionLoop`.
    public static func charge(_ state: WorldState, for siege: Siege) -> WorldState {
        guard let campID = siege.attackerCampID,
              let index = state.camps.firstIndex(where: { $0.id == campID })
        else { return state }
        var s = state
        // Whatever walked home rejoins the camp; whatever died at the wall
        // does not. `siege.strength` is what is left of the warband.
        s.camps[index].strength += max(0, siege.strength)
        if siege.plundered > 0 {
            s.camps[index].loot = s.camps[index].loot
                .adding(siege.plundered * 0.6, to: .food)
                .adding(siege.plundered * 0.4, to: .materials)
        }
        return s
    }

    // MARK: - Burning them out

    /// **The camp as a place a party walks into.**
    ///
    /// Not a second combat system: `SiteVisitEngine` already sends a party to
    /// a place, fights what is living in it, opens what it holds and can lose
    /// people doing it — and the canvas already draws that. A camp lays out in
    /// the same vocabulary: the outlaws are **guardians** whose weight is the
    /// camp's own strength, their hoard is a **cache**, and a hold's fence is
    /// a **trap**, which is the whole of what "the hardest to be rid of"
    /// means mechanically.
    public static func encounter(
        for camp: OutlawCamp, party: [UUID], at tick: Int, seed: UInt64
    ) -> SiteEncounter {
        var rng = SeededRNG(seed: seed)
        var things: [SiteEncounter.Thing] = []
        let middle = LocalPoint(x: 0.5, y: 0.5)
        func place(_ spread: Double) -> LocalPoint {
            let angle = rng.nextUnit() * 2 * .pi
            let radius = spread * (0.35 + rng.nextUnit() * 0.65)
            return LocalPoint(x: middle.x + cos(angle) * radius,
                              y: middle.y + sin(angle) * radius)
        }

        // Nobody home. A camp burned out last season is still a camp on the
        // map — walking into it should say so rather than fight ghosts.
        guard camp.isActive(at: tick) else {
            things.append(SiteEncounter.Thing(
                id: 0, kind: .cache, at: middle, strength: 1,
                label: LocalizedText(values: [
                    .en: "A cold fire pit", .cs: "Vyhaslé ohniště"])))
            return SiteEncounter(things: things, seed: rng.next())
        }

        // The people. Their number is the kind's (a starving band is a crowd),
        // and the weight of each is the camp divided among them — so the same
        // camp is a different fight depending on what it is.
        // Capped, because a party walks into a *place* rather than a battle
        // line — but capped above what `bodyShare` can reach for a middling
        // camp, or a starving crowd and a handful of deserters are the same
        // eight figures and the kinds stop meaning anything on the ground.
        let heads = max(1, min(12, camp.drawn(for: camp.strength)))
        let each = camp.strength / Double(heads)
        for index in 0..<heads {
            things.append(SiteEncounter.Thing(
                id: index, kind: .guardian, at: place(0.22),
                strength: each * (0.75 + rng.nextUnit() * 0.5),
                label: camp.kind.label))
        }
        // The fence, where there is one.
        if camp.kind.walls > 0 {
            things.append(SiteEncounter.Thing(
                id: things.count, kind: .trap, at: place(0.3),
                strength: camp.kind.walls * 0.4,
                label: LocalizedText(values: [
                    .en: "A stake pit under the fence", .cs: "Zákop pod palisádou"])))
        }
        // …and what they came for.
        things.append(SiteEncounter.Thing(
            id: things.count, kind: .cache, at: place(0.12), strength: 1,
            label: LocalizedText(values: [
                .en: "The camp's hoard", .cs: "Kořist z tábora"])))

        var places: [UUID: LocalPoint] = [:]
        for (index, id) in party.enumerated() {
            let angle = Double(index) / Double(max(1, party.count)) * 2 * .pi
            places[id] = LocalPoint(x: middle.x + cos(angle) * 0.36,
                                    y: middle.y + sin(angle) * 0.36)
        }
        return SiteEncounter(things: things, places: places, seed: rng.next())
    }

    /// **What a party brings home from a camp**, in proportion to how much of
    /// it they actually cleared.
    ///
    /// A camp is broken, never abolished: it lies low for a season and fills
    /// up again. A country with no outlaws left in it is a country with
    /// nothing left to do in it — and a raid you can end for ever is a raid
    /// that stops being a reason to keep a garrison.
    public static func sacked(
        _ state: WorldState, regionID: UUID, settlementIndex: Int, share: Double
    ) -> (WorldState, Clearing?) {
        guard let index = state.camps.firstIndex(where: { $0.regionID == regionID })
        else { return (state, nil) }
        var s = state
        let camp = s.camps[index]
        guard camp.isActive(at: s.tick) else { return (s, nil) }

        let got = min(1, max(0, share))
        var recovered = Resources()
        for resource in ResourceType.allCases where camp.loot[resource] > 0 {
            let taken = camp.loot[resource] * got
            recovered = recovered.adding(taken, to: resource)
            s.camps[index].loot = s.camps[index].loot.adding(-taken, to: resource)
            if s.settlements.indices.contains(settlementIndex) {
                s.settlements[settlementIndex].storage[resource] += taken
            }
        }
        // What is left of them, and whether they were actually broken up.
        s.camps[index].strength = max(0, camp.strength * (1 - got))
        let broken = got >= brokenAtShare
        if broken {
            s.camps[index].strength = camp.kind.foundingStrength * 0.25
            s.camps[index].brokenUntil = s.tick + brokenForTicks
        }
        return (s, Clearing(campID: camp.id, campName: camp.name,
                            recovered: recovered, cost: camp.strength * got,
                            broken: broken))
    }

    /// How much of a camp has to be cleared before it is actually broken up.
    /// Below this they were bloodied and are still there, which is the honest
    /// outcome of a party that got in and had to leave again.
    public static let brokenAtShare = 0.7

    /// What a colony finds when it walks into a camp.
    public struct Clearing: Sendable, Equatable {
        public let campID: UUID
        public let campName: LocalizedText
        /// What was taken back — their loot, in proportion to what was cleared.
        public let recovered: Resources
        /// What it cost them, as the weight of camp that had to be put down.
        public let cost: Double
        /// Whether the party actually broke them up.
        public let broken: Bool
    }
}
