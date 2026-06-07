import Foundation

/// A single time-sampled reading of colony health, used to chart and tune
/// balance over a long auto-played run.
public struct BalanceSnapshot: Sendable, Equatable {
    public let tick: Int
    public let population: Double
    public let morale: Double          // average across settlements
    public let stability: Double       // average across settlements
    public let threat: Double
    public let food: Double            // total across settlements
    public let materials: Double       // total across settlements
    public let knowledgeOutput: Double
    public let settlements: Int
    public let era: Era
}

/// Headless auto-player for balance testing: spins up a fresh world and plays
/// it forward for many ticks, making simple greedy decisions (keep research
/// going, build the cheapest affordable building) so the economy is actually
/// exercised rather than left idle. Returns a metrics series for charting /
/// regression assertions. Fully deterministic for a given seed.
public enum BalanceHarness {
    public static func run(
        seed: UInt64,
        ticks: Int,
        sampleEvery: Int = 50,
        registry: GameDataRegistry
    ) -> [BalanceSnapshot] {
        var state = GameWorldFactory.newGame(registry: registry, seed: seed)
        var samples = [snapshot(state)]
        let step = max(1, sampleEvery)
        var elapsed = 0
        while elapsed < ticks {
            state = autoPlay(state, registry: registry)
            let n = min(step, ticks - elapsed)
            state = TickEngine.advance(state, ticks: n, registry: registry).state
            elapsed += n
            samples.append(snapshot(state))
        }
        return samples
    }

    /// Simple greedy management so a run reflects a *played* colony, not an
    /// abandoned one: keep the lab busy and keep building the cheapest thing
    /// the capital can afford.
    static func autoPlay(_ state: WorldState, registry: GameDataRegistry) -> WorldState {
        var s = state

        if s.activeResearch == nil {
            let techs = registry.availableTechs(researched: s.researchedTechs)
            if let cheapest = techs.min(by: { $0.knowledgeCost < $1.knowledgeCost }) {
                s = GameEngine.setResearch(s, techID: cheapest.id, registry: registry)
            }
        }

        if let capital = s.settlements.first {
            let buildable = registry.buildings.values.filter {
                s.unlockedBuildings.contains($0.id) || $0.era == .earlySettlement
            }
            // Build the affordable building the capital has the *fewest* of
            // (cheaper breaks ties), so the economy diversifies — food, housing
            // and knowledge all develop — instead of spamming one cheap hut.
            let counts = capital.buildings.reduce(into: [String: Int]()) { $0[$1.definitionID, default: 0] += $1.count }
            if let pick = buildable
                .filter({ canAfford($0.cost, capital) })
                .min(by: { a, b in
                    let ca = counts[a.id] ?? 0, cb = counts[b.id] ?? 0
                    return ca != cb ? ca < cb : totalCost(a) < totalCost(b)
                }) {
                s = GameEngine.build(s, settlementID: capital.id, buildingID: pick.id, registry: registry)
            }
        }
        return s
    }

    static func snapshot(_ s: WorldState) -> BalanceSnapshot {
        let count = max(1, s.settlements.count)
        let morale = s.settlements.map(\.stats.morale).reduce(0, +) / Double(count)
        let stability = s.settlements.map(\.stats.stability).reduce(0, +) / Double(count)
        let food = s.settlements.map { $0.storage[.food] }.reduce(0, +)
        let materials = s.settlements.map { $0.storage[.materials] }.reduce(0, +)
        return BalanceSnapshot(
            tick: s.tick,
            population: s.totalPopulation,
            morale: morale,
            stability: stability,
            threat: s.globalStats.threatLevel,
            food: food,
            materials: materials,
            knowledgeOutput: s.globalStats.knowledgeOutput,
            settlements: s.settlements.count,
            era: s.era
        )
    }

    /// Formats a run as CSV for charting or eyeballing in a spreadsheet.
    public static func csv(_ series: [BalanceSnapshot]) -> String {
        var lines = ["tick,population,morale,stability,threat,food,materials,knowledge,settlements,era"]
        for s in series {
            lines.append("\(s.tick),\(s.population),\(s.morale),\(s.stability),\(s.threat),\(s.food),\(s.materials),\(s.knowledgeOutput),\(s.settlements),\(s.era)")
        }
        return lines.joined(separator: "\n")
    }

    static func totalCost(_ def: BuildingDefinition) -> Double {
        ResourceType.allCases.reduce(0) { $0 + max(0, def.cost[$1]) }
    }

    static func canAfford(_ cost: Resources, _ settlement: Settlement) -> Bool {
        ResourceType.allCases.allSatisfy { settlement.storage[$0] >= cost[$0] }
    }
}
