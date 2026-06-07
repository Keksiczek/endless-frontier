import Foundation
import Testing
@testable import EndlessFrontierCore

/// A headless auto-play harness for balancing. It plays a long game with a
/// simple policy (always research the cheapest available tech; keep building the
/// most productive thing it can afford, and housing when crowded), samples key
/// metrics over time, asserts the world stays within invariants, and writes a
/// CSV trace you can chart while tuning `world-config.json` / `map-gen.json`.
///
/// Deterministic: the same seed yields the same trace every run.
@Suite("Balance harness")
struct BalanceHarnessTests {
    @Test("Auto-play stays within invariants and emits a balance trace")
    func autoPlayTrace() throws {
        let reg = try GameDataRegistry.bundled()
        var world = GameWorldFactory.newGame(registry: reg, seed: 2025)

        let totalTicks = 12_000
        let step = 250
        let header = "tick,era,population,food,materials,energy,knowledge,influence,morale,prosperity,threat,tension"
        var rows: [String] = [header]

        func sample() {
            let cap = world.settlements.first
            func store(_ r: ResourceType) -> Int { Int((cap?.storage[r] ?? 0).rounded()) }
            let values: [String] = [
                "\(world.tick)",
                world.era.rawValue,
                "\(Int(world.totalPopulation.rounded()))",
                "\(store(.food))", "\(store(.materials))", "\(store(.energy))",
                "\(store(.knowledge))", "\(store(.influence))",
                "\(Int((cap?.stats.morale ?? 0).rounded()))",
                "\(Int(world.globalStats.prosperity.rounded()))",
                "\(Int(world.globalStats.threatLevel.rounded()))",
                "\(Int(TensionCalculator.calculate(world, config: reg.config).rounded()))"
            ]
            rows.append(values.joined(separator: ","))
        }

        func autoResearch() {
            guard world.activeResearch == nil else { return }
            let next = reg.availableTechs(researched: world.researchedTechs)
                .sorted { $0.knowledgeCost < $1.knowledgeCost }
                .first
            if let next {
                world = TechEngine.setResearch(world, techID: next.id, registry: reg)
            }
        }

        func autoBuild() {
            guard let cap = world.settlements.first else { return }
            let capID = cap.id
            // Build housing when nearing the cap so growth doesn't stall.
            if cap.population > ResourceLoop.housingCapacity(cap, registry: reg) * 0.8 {
                world = GameEngine.build(world, settlementID: capID, buildingID: "hut", registry: reg)
                return
            }
            // Otherwise build the most productive thing currently affordable.
            func totalProduction(_ def: BuildingDefinition) -> Double {
                ResourceType.allCases.reduce(0) { $0 + def.production[$1] }
            }
            let affordable = reg.buildings.values
                .filter { world.unlockedBuildings.contains($0.id) || $0.era == .earlySettlement }
                .filter { def in ResourceType.allCases.allSatisfy { cap.storage[$0] >= def.cost[$0] } }
                .sorted { totalProduction($0) > totalProduction($1) }
            if let pick = affordable.first {
                world = GameEngine.build(world, settlementID: capID, buildingID: pick.id, registry: reg)
            }
        }

        sample()
        var elapsed = 0
        while elapsed < totalTicks {
            autoResearch()
            autoBuild()
            world = TickEngine.advance(world, ticks: step, registry: reg).state
            elapsed += step
            sample()

            for settlement in world.settlements {
                #expect(settlement.population >= 0)
                #expect(settlement.stats.morale >= 0 && settlement.stats.morale <= 100)
                #expect(settlement.stats.stability >= 0 && settlement.stats.stability <= 100)
                for resource in ResourceType.allCases {
                    #expect(settlement.storage[resource] >= 0)
                    #expect(settlement.storage[resource] <= settlement.storageCapacity)
                }
            }
            #expect(world.globalStats.prosperity >= 0 && world.globalStats.prosperity <= 100)
            #expect(world.globalStats.threatLevel >= 0 && world.globalStats.threatLevel <= 100)
        }

        // Emit the trace: a CSV file (for charting) and the table to the console.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ef-balance-trace.csv")
        try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        print("── Balance trace (\(rows.count - 1) samples) → \(url.path) ──")
        for row in rows { print(row) }

        #expect(world.tick == totalTicks)
        #expect(world.totalPopulation > 0)   // the colony survived the run
    }
}
