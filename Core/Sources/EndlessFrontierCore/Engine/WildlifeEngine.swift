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
    /// What the record calls the thing out of the trees.
    static let beastName = LocalizedText(values: [.en: "A beast", .cs: "Šelma"])

    /// Per-tick logistic growth rate of the herd.
    static let herdGrowthRate: Double = 0.02
    /// Deer a single hunter takes per tick at a full herd.
    static let cullPerHunter: Double = 0.35
    /// Predator pressure climbs slowly toward this era-scaled ceiling…
    static let basePredatorPressure: Double = 8
    static let predatorPressurePerEra: Double = 5
    static let predatorPressureDrift: Double = 0.01
    /// …and an attack roll each tick scales with it.
    static let attackChancePerPressure: Double = 0.00025
    /// Defense (walls, militia) that fully wards off a predator attack.
    static let defenseToRepel: Double = 25
    /// Wound dealt to the least-healthy colonist by a successful attack.
    static let attackWound: Double = 45

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
        mapSeed: UInt64
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

        // Attack roll: a wounded (possibly killed) colonist unless defense holds.
        let attackChance = map.wildlife.predatorPressure * attackChancePerPressure
        if rng.nextUnit() < attackChance {
            let defense = s.stats.defense
                + CombatEngine.defensePower(s.pawns, registry: registry) * 0.5
            if defense < defenseToRepel,
               let victim = s.pawns.indices
                .filter({ s.pawns[$0].health > 0 })
                .min(by: { s.pawns[$0].health < s.pawns[$1].health }) {
                // Armor blunts the mauling; a weapon doesn't stop teeth.
                let name = s.pawns[victim].name
                let pawnID = s.pawns[victim].id
                let mult = CombatEngine.woundMultiplier(s.pawns[victim])
                s.pawns[victim].health = max(0, s.pawns[victim].health - attackWound * mult)
                // The attack, beat by beat, so the canvas can play it out
                // instead of the journal being the only trace it happened.
                var record = CombatEngine.BattleRecorder()
                record.record(.charge, step: 0, amount: map.wildlife.predatorPressure)
                record.record(.clash, step: 1, amount: defense)
                let killed = s.pawns[victim].health <= 0
                record.record(killed ? .death : .wound, step: 2, pawnID: pawnID,
                              pawnName: name, amount: attackWound * mult)
                s.lastBattle = record.finish(
                    id: rng.nextUUID(), tick: tick,
                    attackerName: beastName.resolve(.en), defenderName: s.name, repelled: false)
                if killed {
                    s.pawns.remove(at: victim)
                    s.deathTallies[PawnDeathCause.beast.rawValue, default: 0] += 1
                    s.stats.morale = max(0, s.stats.morale - 6)
                    s.journal.append(tick: tick, kind: .danger, text: LocalizedText(values: [
                        .en: "A beast took \(name) at the edge of the woods.",
                        .cs: "Šelma na kraji lesa strhla \(name)."]))
                } else {
                    s.journal.append(tick: tick, kind: .danger, text: LocalizedText(values: [
                        .en: "A beast mauled \(name) — dragged back bleeding, but alive.",
                        .cs: "Šelma potrhala \(name) — dovlekli ho zpět zkrvaveného, ale žije."]))
                }
            } else {
                // Repelled: the hunt thins the predators a little.
                map.wildlife.predatorPressure = max(0, map.wildlife.predatorPressure - 3)
                s.journal.append(tick: tick, kind: .danger, text: LocalizedText(values: [
                    .en: "Wolves tried the herds by night; the watch drove them off.",
                    .cs: "Vlci v noci zkusili stáda; hlídka je zahnala."]))
            }
        }

        s.localMap = map
        return s
    }

    /// How much predator pressure each ranged-armed hunter bleeds off per tick.
    static let rangedHunterSuppression = 0.03

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
