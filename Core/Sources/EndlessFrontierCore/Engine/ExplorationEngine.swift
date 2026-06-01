import Foundation

/// Exploration: sending expeditions to reveal unknown regions, which unlocks
/// new biomes (and the events gated on them) and new places to settle.
public enum ExplorationEngine {
    /// Regions the player can send an expedition to: unknown regions adjacent
    /// to an already-known (explored or settled) region. This makes discovery
    /// gradual and spatial — the frontier expands outward from what you hold.
    public static func exploreableRegions(_ state: WorldState) -> [Region] {
        let knownCoords = Set(
            state.regions
                .filter { $0.explorationState != .unknown }
                .map(\.coord)
        )
        return state.regions.filter { region in
            region.explorationState == .unknown
                && region.coord.neighbors().contains { knownCoords.contains($0) }
        }
    }

    /// Duration in ticks for an expedition to `region`, scaled by hazard.
    public static func expeditionDuration(to region: Region, config: WorldConfig) -> Int {
        config.baseExpeditionTicks + region.hazardLevel * config.ticksPerHazard
    }

    /// Cost in resources to launch an expedition to `region`.
    public static func expeditionCost(to region: Region, config: WorldConfig) -> Resources {
        let hazardScale = 1 + Double(region.hazardLevel) * 0.2
        return Resources([
            .food: config.expeditionFoodCost * hazardScale,
            .materials: config.expeditionMaterialsCost * hazardScale
        ])
    }

    /// Launches an expedition to an unknown region if affordable and none is
    /// already in progress. Returns unchanged state otherwise.
    public static func startExpedition(
        _ state: WorldState,
        targetRegionID: UUID,
        registry: GameDataRegistry
    ) -> WorldState {
        guard state.activeExpedition == nil,
              let region = state.regions.first(where: { $0.id == targetRegionID && $0.explorationState == .unknown }),
              let paid = EffectApplier.payCost(expeditionCost(to: region, config: registry.config), from: state) else {
            return state
        }
        var s = paid
        s.activeExpedition = Expedition(
            targetRegionID: region.id,
            ticksRemaining: expeditionDuration(to: region, config: registry.config)
        )
        return s
    }

    /// Advances any active expedition by one tick, completing it (revealing the
    /// region, setting the biome flag, firing a discovery record) when done.
    public static func advanceOneTick(_ state: WorldState, registry: GameDataRegistry) -> PlannerResult {
        guard var expedition = state.activeExpedition else {
            return PlannerResult(state: state, fired: [])
        }
        var s = state
        expedition.ticksRemaining -= 1
        guard expedition.ticksRemaining <= 0 else {
            s.activeExpedition = expedition
            return PlannerResult(state: s, fired: [])
        }

        // Expedition complete — reveal the region.
        s.activeExpedition = nil
        if let index = s.regions.firstIndex(where: { $0.id == expedition.targetRegionID }) {
            s.regions[index].explorationState = .fullyExplored
            if let flag = registry.biome(s.regions[index].biomeID)?.worldFlag {
                s.worldFlags[flag] = true
            }
            // Grow the world: reveal opens up new unknown neighbours, so the
            // frontier always extends further out — endlessly.
            MapGenerator.expandFrontier(
                around: s.regions[index].coord,
                regions: &s.regions,
                mapSeed: s.mapSeed,
                registry: registry
            )
        }
        let record = HistoricalEvent(templateID: "region_discovered", type: .flavor, tick: s.tick)
        s.eventHistory.append(record)
        return PlannerResult(state: s, fired: [record])
    }
}
