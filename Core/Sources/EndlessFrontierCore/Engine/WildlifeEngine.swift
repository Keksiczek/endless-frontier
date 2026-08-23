import Foundation

/// The wild half of a settlement's local world: the deer herd hunters live off
/// and the predators that stalk the edges. Deterministic — attack rolls come
/// from a seed derived from `(mapSeed, settlement.id, tick)`.
///
/// Runs once per settlement per tick, after the harvest so it sees this tick's
/// hunters. Hunting yield (produced in `PawnEngine`) is gated by the herd via
/// `huntingFactor`; here the herd itself grows, is culled, and predators
/// occasionally wound a colonist unless the settlement's defenses hold.
public enum WildlifeEngine {
    /// …and what it calls the several of them the watch turns back.
    static let packName = LocalizedText(values: [.en: "Wolves", .cs: "Vlci"])

    /// How many of them came at the herds. Purely for the canvas — the roll is
    /// settled on pressure alone — but a pack has to *look* like a pack, and
    /// like a bigger one in a bad year.
    static func packSize(pressure: Double) -> Int {
        min(6, max(2, Int((max(0, pressure) / 7).rounded(.down)) + 2))
    }

    /// Per-tick logistic growth rate of the herd.
    static let herdGrowthRate: Double = 0.02
    /// Deer a single hunter takes per tick at a full herd.
    static let cullPerHunter: Double = 0.35
    /// Predator pressure climbs slowly toward this era-scaled ceiling…
    static let basePredatorPressure: Double = 8
    static let predatorPressurePerEra: Double = 5
    static let predatorPressureDrift: Double = 0.01
    /// …and an attack roll each tick scales with it. At a pressure of twelve
    /// that is a pack roughly every three and a half years, which is often
    /// enough to be part of the life of the colony rather than a thing you
    /// remember happening once.
    static let attackChancePerPressure: Double = 0.0004
    /// How many colonists a settlement has to hold before it is worth another
    /// full measure of pressure to the things in the wood.
    static let packPerColonist: Double = 26

    /// Hunting-work efficiency: a thin herd yields less meat, never zero.
    static let huntFloorFactor: Double = 0.3
    public static func huntingFactor(_ wildlife: WildlifeState?) -> Double {
        guard let wildlife else { return 1 }
        return huntFloorFactor + (1 - huntFloorFactor) * wildlife.herdFraction
    }

    public static func advanceOneTick(
        _ settlement: Settlement,
        registry: GameDataRegistry,
        tick: Int,
        era: Era,
        mapSeed: UInt64,
        climate: Climate = .temperate,
        /// What the colony has learned about hunting and butchering
        /// (`ResearchStat.huntYield`). 1 when nothing has been studied.
        huntYield: Double = 1
    ) -> Settlement {
        guard var map = settlement.localMap else { return settlement }
        var s = settlement
        var rng = SeededRNG(seed: wildlifeSeed(mapSeed: mapSeed, settlementID: s.id, tick: tick))
        let ticksPerYear = registry.config.ticksPerYear

        // Herd: logistic growth (season-scaled), then culled by hunters.
        var herd = map.wildlife.deerHerd
        let cap = map.wildlife.deerCapacity
        if cap > 0 {
            let season = registry.config.seasonYieldMultiplier(for: .food, tick: tick)
            herd += herd * herdGrowthRate * season * (1 - herd / cap)
        }
        let adultAgeTicks = Pawn.adultAgeYears * ticksPerYear
        var hunters = 0
        for pawn in s.pawns where pawn.assignedWork == .hunting && pawn.age >= adultAgeTicks && !pawn.isBroken {
            hunters += 1
        }
        let culled = min(herd, Double(hunters) * cullPerHunter * map.wildlife.herdFraction)
        herd = max(0, herd - culled)
        map.wildlife.deerHerd = herd

        // Predator pressure drifts toward an era-scaled baseline — and hunters
        // with ranged arms actively push it back down. A bow changes what a
        // hunter *is* to the wild: not just a mouth the herd feeds, but a
        // reason wolves keep their distance.
        let ceiling = basePredatorPressure + Double(era.index) * predatorPressurePerEra
        map.wildlife.predatorPressure += (ceiling - map.wildlife.predatorPressure) * predatorPressureDrift
        let armedHunters = CombatEngine.rangedCount(
            s.pawns.filter { $0.assignedWork == .hunting }, registry: registry)
        if armedHunters > 0 {
            map.wildlife.predatorPressure = max(
                0, map.wildlife.predatorPressure - Double(armedHunters) * rangedHunterSuppression)
        }

        // A pack comes at the herds. It **opens a fight**, exactly as a raid
        // does, so the one combat a colony has regularly is one you can stand
        // in and give orders to. It used to be settled here in three lines of
        // arithmetic: whoever was weakest took a bite and the journal said so.
        //
        // A siege already running is left alone — the colony has enough on.
        let attackChance = map.wildlife.predatorPressure * attackChancePerPressure
        if s.siege == nil, rng.nextUnit() < attackChance {
            let able = s.pawns.filter { $0.health > 0 && !$0.isBroken && !$0.isAway }
            let watch = able
                .sorted { $0.assignedWork == .garrison && $1.assignedWork != .garrison }
                .prefix(max(6, able.count / 6)).map(\.id)
            if !watch.isEmpty {
                // The pack's weight is its pressure — and how much there is to
                // come for.
                //
                // Pressure alone is capped by the era (8, plus 5 an era), so a
                // pack was ten strong whether the colony was five people or
                // four hundred. Measured over the first thirty years of a real
                // world: four fights, worst wound *nothing at all*. A threat
                // that does not answer the thing it threatens is not a threat;
                // it is scenery. More herds, more middens, more trails — a big
                // settlement genuinely does bring something worse out of the
                // wood.
                let strength = max(6, map.wildlife.predatorPressure
                                   * (0.9 + Double(able.count) / packPerColonist))
                s = SiegeEngine.begin(
                    s, attackerStrength: strength,
                    attackerName: packName.resolve(.en),
                    attackerLabel: packName,
                    fortification: s.stats.defense,
                    tick: tick, registry: registry, seed: rng.next(),
                    // Wolves eat; they do not loot a granary. Carrying the same
                    // share a warband does is how a colony starves.
                    carriesOff: 0.12)
                s.journal.append(tick: tick, kind: .danger, text: LocalizedText(values: [
                    .en: "Wolves are at the herds — the watch is turning out.",
                    .cs: "Vlci jsou u stád — hlídka vybíhá."]))
                // The hunt that answers them thins the wood either way.
                map.wildlife.predatorPressure = max(0, map.wildlife.predatorPressure - 3)
            }
        }

        // The wild as entities — and now the other way round.
        //
        // The herd number used to be the truth and the beasts were culled down
        // to match it, which meant the animals on the map were an illustration
        // of an arithmetic that had already happened. It is the wrong way up:
        // a hunter should take *a deer*, and the ledger should find out about
        // it afterwards. So hunters go out and meet actual animals, and
        // `deerHerd` is recomputed from what is left standing.
        if map.wildlife.usesEntities {
            if tick % AnimalEngine.thinkInterval == 0 {
                map = huntWithParty(&s, map: map, registry: registry, tick: tick,
                                    mapSeed: mapSeed, ticksPerYear: ticksPerYear,
                                    huntYield: huntYield)
                // And the wild moves: prey drift with the herd and bolt from
                // anything that means them harm — hunters included, which is
                // why a herd worked hard drifts to the far side of the valley.
                let hunters = s.pawns
                    .filter { $0.assignedWork == .hunting && !$0.isAway }
                    .compactMap { $0.currentJob?.position }
                map = AnimalEngine.roam(map, tick: tick, threats: hunters)
            }
            map.wildlife.deerHerd = mirroredHerd(map.wildlife)
        }
        // Their own lives: ageing, wounds, illness, cold and heat, and death.
        // On the same cadence they think on, standing for the whole window —
        // everything in there is a rate, and a valley now holds two and a half
        // times as many beasts as it did (rule 4).
        if tick % AnimalEngine.thinkInterval == 0 {
            map = AnimalEngine.advanceOneTick(map, tick: tick, ticksPerYear: ticksPerYear,
                                              steps: AnimalEngine.thinkInterval,
                                              climate: climate)
        }
        map = AnimalEngine.breed(map, tick: tick, ticksPerYear: ticksPerYear)
        // And the wood grows while all this happens — in batches, since a tree
        // takes thousands of ticks to grow and ageing one every tick is a copy
        // of the whole wood for no visible difference.
        if tick % LaborEngine.staffingInterval == 0 {
            map = FloraEngine.advanceOneTick(map, by: LaborEngine.staffingInterval)
            // …and comes back where it was cut. `FloraEngine.plant` existed
            // with no callers, so a felled valley stayed bare for ever and the
            // colony lost `timber_bundle` — and with it every building that
            // lists a crafted cost. See `FloraEngine.reseeded`.
            // Twice a season rather than once a shift. A sapling needs
            // hundreds of ticks to be worth an axe, so seeding every shift buys
            // nothing a player could see and costs a scan of the wood each time
            // (rule 4) — but once every hundred ticks, against nine loggers
            // taking half a tree a tick, was a supply two orders of magnitude
            // under the demand (`FloraEngine.seedStand`). This is the other
            // half of that fix; the seed stand is what keeps parents alive to
            // make it possible.
            if tick % (LaborEngine.staffingInterval * 5) == 0 {
                map = FloraEngine.reseeded(map, mapSeed: mapSeed, tick: tick)
            }
        }

        s.localMap = map
        return s
    }

    /// How much predator pressure each ranged-armed hunter bleeds off per tick.
    static let rangedHunterSuppression = 0.03

    /// Below this share of what the land can carry, the hunters come home
    /// empty. Not a mercy rule — it is what actually happens when game gets
    /// thin, and it is what stops a colony hunting its own valley to
    /// extinction and then starving in it.
    static let huntingFloor = 0.25

    /// One round of hunting: the party goes out, meets what is there, and
    /// brings back meat and hides — or somebody comes back mauled.
    static func huntWithParty(
        _ s: inout Settlement, map: LocalMap, registry: GameDataRegistry,
        tick: Int, mapSeed: UInt64, ticksPerYear: Int, huntYield: Double = 1
    ) -> LocalMap {
        let capacity = map.wildlife.preyCapacity
        guard capacity > 0,
              Double(map.wildlife.preyCount) > Double(capacity) * huntingFloor else { return map }
        let party = HuntEngine.party(s, registry: registry, ticksPerYear: ticksPerYear)
        guard !party.isEmpty else { return map }

        // Where each hunter is standing: at the beast the job board sent them
        // to if it did, otherwise out at the herd.
        var posts: [UUID: LocalPoint] = [:]
        for pawn in s.pawns where pawn.assignedWork == .hunting {
            posts[pawn.id] = pawn.currentJob?.position
                ?? map.wildlife.animals.first?.position
                ?? LocalPoint(x: 0.5, y: 0.52)
        }

        let bag = HuntEngine.run(map, hunters: party, at: posts, tick: tick,
                                 seed: wildlifeSeed(mapSeed: mapSeed, settlementID: s.id,
                                                    tick: tick) ^ 0x48_55_4E_54,
                                 marked: DesignationEngine.animals(s))
        // Taken before the early return below, because a hunt where nothing was
        // caught is still a hunt happening — that is the tick where the canvas
        // should show somebody creeping through the wood, and returning early
        // would leave it showing the last kill for ever.
        s.huntPhases = bag.phases
        guard !bag.kills.isEmpty || !bag.wounds.isEmpty else { return bag.map }

        // The carcass, banked: meat on the table and a hide off its back —
        // and what a colony has learned about butchering it (`.huntYield`).
        if bag.meat > 0 {
            s.storage[.food] = min(s.storageCapacity[.food],
                                   s.storage[.food] + bag.meat * huntYield)
        }
        if bag.hides > 0 {
            s.stockpile[ResourceLoop.hideItemID, default: 0]
                += Int((Double(bag.hides) * huntYield).rounded())
        }
        // And whoever got it wrong.
        for wound in bag.wounds {
            guard let i = s.pawns.firstIndex(where: { $0.id == wound.hunterID }) else { continue }
            // A boar's tusks go into a leg, not into an abstraction.
            var goring = SeededRNG(seed: wildlifeSeed(mapSeed: mapSeed, settlementID: s.id,
                                                      tick: tick) ^ 0x60_52_45_44)
            s.pawns[i] = MedicineEngine.wound(s.pawns[i], amount: wound.damage,
                                              tick: tick, rng: &goring)
            let beast = wound.species.displayName
            if s.pawns[i].health <= 0 {
                s.pawns.remove(at: i)
                s.deathTallies[PawnDeathCause.beast.rawValue, default: 0] += 1
                s.journal.append(tick: tick, kind: .danger, text: LocalizedText(values: [
                    .en: "\(wound.hunterName) closed with a \(beast.resolve(.en).lowercased()) and did not come back.",
                    .cs: "\(wound.hunterName) šel na \(beast.resolve(.cs).lowercased())ho zblízka a už se nevrátil."]))
            } else {
                s.journal.append(tick: tick, kind: .danger, text: LocalizedText(values: [
                    .en: "\(wound.hunterName) was gored bringing down a \(beast.resolve(.en).lowercased()).",
                    .cs: "\(wound.hunterName) to schytal při lovu — \(beast.resolve(.cs).lowercased()) se bránil."]))
            }
        }
        return bag.map
    }

    /// The old herd number, recomputed from the beasts actually standing on the
    /// map. It is a *view* now, not a simulation: everything that still reads
    /// `deerHerd` keeps working, and none of it can disagree with what you see.
    static func mirroredHerd(_ wildlife: WildlifeState) -> Double {
        let capacity = wildlife.preyCapacity
        guard capacity > 0 else { return wildlife.deerHerd }
        return min(wildlife.deerCapacity,
                   Double(wildlife.preyCount) / Double(capacity) * wildlife.deerCapacity)
    }

    static func wildlifeSeed(mapSeed: UInt64, settlementID: UUID, tick: Int) -> UInt64 {
        var h: UInt64 = mapSeed &* 0xCBF2_9CE4_8422_2325
        let b = settlementID.uuid
        let lo = UInt64(b.8) << 56 | UInt64(b.9) << 48 | UInt64(b.10) << 40 | UInt64(b.11) << 32
            | UInt64(b.12) << 24 | UInt64(b.13) << 16 | UInt64(b.14) << 8 | UInt64(b.15)
        h ^= lo
        h = (h ^ UInt64(bitPattern: Int64(tick))) &* 0x0100_0000_01B3
        return h ^ (h >> 27)
    }
}
