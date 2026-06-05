import Foundation

/// The result of interacting with a special site, for the UI and history.
public struct SiteOutcome: Sendable, Equatable {
    public let kind: RegionKind
    public let regionName: String
    public let rewards: Resources
    public let casualtyName: String?   // a colonist hurt (dungeon)
    public let died: Bool              // …or killed
    public let threatGain: Double      // anomaly stirs danger
    public let narrative: String
}

/// Makes the map's special sites worth visiting: ruins, dungeons and
/// anomalies each offer a distinct risk/reward interaction, with loot scaling
/// by hazard (and therefore by distance from the homeland). Deterministic —
/// outcomes are seeded by `(mapSeed, coord, tick)`.
public enum SiteEngine {
    /// Interacts with the special site in `regionID`. Returns the updated world
    /// and an outcome, or `nil` if there's no active site there.
    public static func interact(
        _ state: WorldState,
        regionID: UUID,
        registry: GameDataRegistry
    ) -> (WorldState, SiteOutcome)? {
        guard let index = state.regions.firstIndex(where: { $0.id == regionID }),
              state.regions[index].hasActiveSite else {
            return nil
        }
        var s = state
        let region = s.regions[index]
        let hazard = Double(region.hazardLevel)
        var rng = SeededRNG(seed: siteSeed(mapSeed: s.mapSeed, coord: region.coord, tick: s.tick))

        let outcome: SiteOutcome
        switch region.kind {
        case .ruins:
            outcome = excavateRuins(&s, region: region, hazard: hazard)
        case .dungeon:
            outcome = delveDungeon(&s, region: region, hazard: hazard, rng: &rng)
        case .anomaly:
            outcome = probeAnomaly(&s, region: region, hazard: hazard)
        default:
            return nil
        }

        s.regions[index].siteCleared = true
        let record = HistoricalEvent(templateID: "site_\(region.kind.rawValue)", type: siteEventType(region.kind), tick: s.tick)
        s.eventHistory.append(record)
        return (s, outcome)
    }

    // MARK: - Site behaviours

    private static func excavateRuins(_ s: inout WorldState, region: Region, hazard: Double) -> SiteOutcome {
        let rewards = Resources([
            .knowledge: 40 + hazard * 8,
            .influence: 20 + hazard * 4
        ])
        grant(&s, rewards)
        return SiteOutcome(
            kind: .ruins, regionName: region.name, rewards: rewards,
            casualtyName: nil, died: false, threatGain: 0,
            narrative: "Your scholars sift the ruins of \(region.name), recovering lost knowledge and relics of influence."
        )
    }

    private static func delveDungeon(_ s: inout WorldState, region: Region, hazard: Double, rng: inout SeededRNG) -> SiteOutcome {
        let rewards = Resources([
            .materials: 60 + hazard * 12,
            .influence: 30 + hazard * 6
        ])
        grant(&s, rewards)

        // Risk: the deeper (more hazardous) the dungeon, the worse the danger.
        var casualtyName: String?
        var died = false
        if let capital = s.settlements.indices.first, !s.settlements[capital].pawns.isEmpty {
            let injuryRoll = rng.nextUnit()
            let injuryChance = min(0.85, 0.25 + hazard * 0.06)
            if injuryRoll < injuryChance {
                // Hurt the healthiest colonist (the one who went in).
                let pawnIndex = s.settlements[capital].pawns.indices
                    .max { s.settlements[capital].pawns[$0].health < s.settlements[capital].pawns[$1].health }!
                let damage = 20 + hazard * 5
                var pawn = s.settlements[capital].pawns[pawnIndex]
                pawn.health = max(0, pawn.health - damage)
                casualtyName = pawn.name
                if pawn.health <= 0 {
                    died = true
                    s.settlements[capital].pawns.remove(at: pawnIndex)
                    s.settlements[capital].population = max(0, s.settlements[capital].population - 1)
                    s.settlements[capital].stats.morale = max(0, s.settlements[capital].stats.morale - 10)
                } else {
                    s.settlements[capital].pawns[pawnIndex] = pawn
                }
            }
        }

        let fate = died ? " \(casualtyName!) did not return."
            : (casualtyName != nil ? " \(casualtyName!) was wounded in the dark." : "")
        return SiteOutcome(
            kind: .dungeon, regionName: region.name, rewards: rewards,
            casualtyName: casualtyName, died: died, threatGain: 0,
            narrative: "A delving party plunders \(region.name) for materials and influence.\(fate)"
        )
    }

    private static func probeAnomaly(_ s: inout WorldState, region: Region, hazard: Double) -> SiteOutcome {
        let rewards = Resources([.knowledge: 50 + hazard * 10])
        grant(&s, rewards)
        let threatGain = hazard * 2
        s.globalStats = s.globalStats.applying(delta: threatGain, to: "threatLevel")
        return SiteOutcome(
            kind: .anomaly, regionName: region.name, rewards: rewards,
            casualtyName: nil, died: false, threatGain: threatGain,
            narrative: "Studying the anomaly at \(region.name) yields strange insight — but stirs something best left sleeping."
        )
    }

    // MARK: - Helpers

    /// Adds rewards to the capital's storage (clamped to capacity).
    private static func grant(_ s: inout WorldState, _ rewards: Resources) {
        for resource in ResourceType.allCases where rewards[resource] != 0 {
            EffectApplier.applyResourceDelta(&s, resource: resource, delta: rewards[resource], scope: .global)
        }
    }

    static func siteSeed(mapSeed: UInt64, coord: HexCoord, tick: Int) -> UInt64 {
        var h = mapSeed &* 0x9E37_79B9_7F4A_7C15
        h = (h ^ UInt64(bitPattern: Int64(coord.q))) &* 0xD1B5_4A32_D192_ED03
        h = (h ^ UInt64(bitPattern: Int64(coord.r))) &* 0xCBF2_9CE4_8422_2325
        h = (h ^ UInt64(bitPattern: Int64(tick))) &* 0x1000_0000_01B3
        return h ^ (h >> 31)
    }

    private static func siteEventType(_ kind: RegionKind) -> EventType {
        switch kind {
        case .dungeon: return .threat
        case .anomaly: return .threat
        default: return .opportunity
        }
    }
}
