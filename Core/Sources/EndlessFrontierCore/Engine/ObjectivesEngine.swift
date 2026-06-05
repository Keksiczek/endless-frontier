import Foundation

/// Derives the player's current objectives from world state. Pure and
/// deterministic; recomputed whenever the UI needs it.
public enum ObjectivesEngine {
    /// Returns up to `limit` prioritised objectives.
    public static func current(_ state: WorldState, registry: GameDataRegistry, limit: Int = 6) -> [Objective] {
        var objectives: [Objective] = []
        objectives += colonistObjectives(state)
        objectives += defenseObjectives(state)
        objectives += housingObjectives(state, registry: registry)
        objectives += eraObjectives(state, registry: registry)
        objectives += researchObjectives(state, registry: registry)
        objectives += siteObjectives(state)
        objectives += explorationObjectives(state)
        objectives += expansionObjectives(state)

        return Array(objectives.sorted { $0.priority < $1.priority }.prefix(limit))
    }

    private static func housingObjectives(_ state: WorldState, registry: GameDataRegistry) -> [Objective] {
        for settlement in state.settlements {
            let capacity = ResourceLoop.housingCapacity(settlement, registry: registry)
            if capacity > 0, settlement.population >= capacity * 0.85 {
                return [Objective(
                    id: "build_housing",
                    title: "Build more housing",
                    detail: "\(settlement.name) is filling up (\(Int(settlement.population))/\(Int(capacity))). Crowding stalls growth and dents morale.",
                    progress: min(1, settlement.population / capacity),
                    category: .expand, priority: 4
                )]
            }
        }
        return []
    }

    // MARK: - Sources

    private static func defenseObjectives(_ state: WorldState) -> [Objective] {
        guard state.globalStats.threatLevel >= 50, let capital = state.settlements.first else { return [] }
        let effectiveDefense = capital.stats.defense + EffectApplier.militiaDefense(capital.pawns)
        guard effectiveDefense < 25 else { return [] }
        return [Objective(
            id: "prepare_defense",
            title: "Prepare your defenses",
            detail: "Threat is rising and \(capital.name) is poorly defended. Build walls, arm colonists with weapons, or raise the threat away.",
            progress: min(1, effectiveDefense / 25),
            category: .colonists, priority: 2
        )]
    }

    private static func colonistObjectives(_ state: WorldState) -> [Objective] {
        var result: [Objective] = []
        let allPawns = state.settlements.flatMap(\.pawns)
        if let hurt = allPawns.filter({ $0.health < 40 }).min(by: { $0.health < $1.health }) {
            result.append(Objective(
                id: "tend_\(hurt.id)",
                title: "Tend to \(hurt.name)",
                detail: "A colonist is badly hurt (health \(Int(hurt.health))). Find care before it's too late.",
                progress: hurt.health / 100,
                category: .colonists, priority: 0
            ))
        }
        if allPawns.contains(where: { $0.isBroken }) {
            result.append(Objective(
                id: "morale_break",
                title: "Lift the colony's spirits",
                detail: "A colonist has broken under the strain. Improve food, rest and morale.",
                category: .colonists, priority: 1
            ))
        }
        return result
    }

    private static func eraObjectives(_ state: WorldState, registry: GameDataRegistry) -> [Objective] {
        guard let nextEra = state.era.next,
              let definition = registry.eraDefinition(nextEra) else { return [] }
        return definition.milestones
            .filter { !EraEngine.isSatisfied($0, in: state) }
            .map { milestone in objective(for: milestone, nextEra: nextEra, state: state, registry: registry) }
    }

    private static func objective(
        for milestone: EraMilestone,
        nextEra: Era,
        state: WorldState,
        registry: GameDataRegistry
    ) -> Objective {
        let eraName = nextEra.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        switch milestone {
        case let .techResearched(id):
            return Objective(
                id: "era_tech_\(id)",
                title: "Research \(registry.tech(id)?.name ?? id)",
                detail: "A key advance toward the \(eraName) era.",
                category: .era, priority: 10
            )
        case let .globalStat(stat, min):
            let current = WorldQuery.globalValue(stat, in: state)
            return Objective(
                id: "era_stat_\(stat)",
                title: "Raise \(stat) to \(Int(min))",
                detail: "Now \(Int(current)). Needed for the \(eraName) era.",
                progress: min > 0 ? current / min : nil,
                category: .era, priority: 11
            )
        case let .settlementCount(min):
            return Objective(
                id: "era_settlements",
                title: "Hold \(min) settlements",
                detail: "Now \(state.settlements.count). Expand toward the \(eraName) era.",
                progress: Double(state.settlements.count) / Double(min),
                category: .era, priority: 12
            )
        case let .populationTotal(min):
            return Objective(
                id: "era_population",
                title: "Grow to \(Int(min)) population",
                detail: "Now \(Int(state.totalPopulation)). Needed for the \(eraName) era.",
                progress: state.totalPopulation / min,
                category: .era, priority: 12
            )
        }
    }

    private static func researchObjectives(_ state: WorldState, registry: GameDataRegistry) -> [Objective] {
        guard state.activeResearch == nil,
              !registry.availableTechs(researched: state.researchedTechs).isEmpty else { return [] }
        return [Objective(
            id: "pick_research",
            title: "Choose a research project",
            detail: "Your scholars are idle. Pick the next technology to pursue.",
            category: .research, priority: 5
        )]
    }

    private static func siteObjectives(_ state: WorldState) -> [Objective] {
        guard let site = state.regions.first(where: { $0.hasActiveSite }) else { return [] }
        let verb: String
        switch site.kind {
        case .ruins: verb = "Excavate the ruins"
        case .dungeon: verb = "Delve the dungeon"
        case .anomaly: verb = "Probe the anomaly"
        default: verb = "Investigate"
        }
        return [Objective(
            id: "site_\(site.id)",
            title: "\(verb) at \(site.name)",
            detail: "An uncovered site awaits — risk and reward both grow with distance.",
            category: .sites, priority: 20
        )]
    }

    private static func explorationObjectives(_ state: WorldState) -> [Objective] {
        guard state.activeExpedition == nil,
              !ExplorationEngine.exploreableRegions(state).isEmpty else { return [] }
        return [Objective(
            id: "explore",
            title: "Push the frontier",
            detail: "Unknown land lies just beyond your borders. Send an expedition.",
            category: .explore, priority: 25
        )]
    }

    private static func expansionObjectives(_ state: WorldState) -> [Objective] {
        guard !ExpansionEngine.foundableRegions(state).isEmpty else { return [] }
        return [Objective(
            id: "found_outpost",
            title: "Found a new outpost",
            detail: "Charted land is ready to settle. Expand your reach.",
            category: .expand, priority: 30
        )]
    }
}
