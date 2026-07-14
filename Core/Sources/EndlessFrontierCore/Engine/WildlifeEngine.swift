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

        // Predator pressure drifts toward an era-scaled baseline.
        let ceiling = basePredatorPressure + Double(era.index) * predatorPressurePerEra
        map.wildlife.predatorPressure += (ceiling - map.wildlife.predatorPressure) * predatorPressureDrift

        // Attack roll: a wounded (possibly killed) colonist unless defense holds.
        let attackChance = map.wildlife.predatorPressure * attackChancePerPressure
        if rng.nextUnit() < attackChance {
            let defense = s.stats.defense + EffectApplier.militiaDefense(s.pawns) * 0.5
            if defense < defenseToRepel,
               let victim = s.pawns.indices
                .filter({ s.pawns[$0].health > 0 })
                .min(by: { s.pawns[$0].health < s.pawns[$1].health }) {
                let armored = s.pawns[victim].equipment[.weapon] != nil ? 0.5 : 1.0
                s.pawns[victim].health = max(0, s.pawns[victim].health - attackWound * armored)
                if s.pawns[victim].health <= 0 {
                    s.pawns.remove(at: victim)
                    s.deathTallies[PawnDeathCause.beast.rawValue, default: 0] += 1
                    s.stats.morale = max(0, s.stats.morale - 6)
                }
            } else {
                // Repelled: the hunt thins the predators a little.
                map.wildlife.predatorPressure = max(0, map.wildlife.predatorPressure - 3)
            }
        }

        s.localMap = map
        return s
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
