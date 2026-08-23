import Testing
import Foundation
@testable import EndlessFrontierCore

/// **What a colony's grid actually looks like**, decade by decade.
///
/// `ZZCouncilDiag` prints the council's argument but has no energy column at
/// all, so the one thing Keks reported — *"chybí továrny, ale hlavně
/// elektrika"* — was invisible in the only place it could have been seen.
/// Rule 23: print the distribution before moving a number.
///
/// Demand has two halves that behave completely differently (rule 16): the
/// domestic draw scales with **people**, the operating draw with **buildings**,
/// and generation only ever moves when the council decides to raise a
/// generator. Printing them apart is the whole point — a colony short of power
/// because it grew wants a different answer from one short because it built a
/// university.
@Suite("energy diag", .enabled(if: ProcessInfo.processInfo.environment["EF_DIAG"] != nil, "diag"))
struct ZZEnergyDiag {

    @Test("the grid, two hundred years")
    func theGrid() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)

        print("\nyear pop era              | gen  domestic  bldgs  net | store/cap | brownout | generators")
        for step in 1...20 {
            state = BalanceHarness.autoPlay(state, registry: registry)
            state = TickEngine.advance(state, ticks: 600, registry: registry).state
            guard let s = state.settlements.first else { break }

            let domestic = ResourceLoop.domesticEnergyDemand(
                population: s.population, era: state.era, config: registry.config)
            let generation = StewardEngine.production(of: s, .energy, registry: registry)
            let buildingDraw = s.buildings.reduce(0.0) { acc, instance in
                guard let def = registry.building(instance.definitionID) else { return acc }
                return acc + def.consumption[.energy] * Double(instance.count)
            }
            let generators = s.buildings
                .filter { (registry.building($0.definitionID)?.production[.energy] ?? 0) > 0 }
                .sorted { $0.definitionID < $1.definitionID }
                .map { "\($0.definitionID)x\($0.count)" }
                .joined(separator: " ")
            let dark = domestic > 0 && s.storage[.energy] <= 0

            print(String(format:
                "%4d %3d %-16@ | %4.1f %8.2f %6.1f %5.1f | %5.0f/%-5.0f | %-8@ | %@",
                step * 10, Int(s.population), state.era.rawValue,
                generation, domestic, buildingDraw,
                generation - domestic - buildingDraw,
                s.storage[.energy], s.storageCapacity[.energy],
                dark ? "DARK" : "-",
                generators.isEmpty ? "—" : generators))
        }
    }

    /// **Whether the brownout clause can ever fire before the clauses above
    /// it.** The council answers power fourth, behind fields, roofs and stores;
    /// if one of those is permanently true the grid is never asked about
    /// (rule 27). This prints which clause actually answers, every decade.
    @Test("which clause answers, and whether power ever gets a turn")
    func whoAnswers() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        var turns: [String: Int] = [:]

        for step in 1...20 {
            state = BalanceHarness.autoPlay(state, registry: registry)
            state = TickEngine.advance(state, ticks: 600, registry: registry).state
            guard let s = state.settlements.first else { break }
            let able = StewardEngine.buildableHere(s, in: state, registry: registry)
            let draw = ResourceLoop.domesticEnergyDemand(
                population: s.population, era: state.era, config: registry.config)
            let generation = StewardEngine.production(of: s, .energy, registry: registry)

            var clause = "nothing spare"
            if FarmEngine.plotsStanding(s) < FarmEngine.plotsWanted(for: s.population),
               able.contains(where: { $0.plots > 0 }) { clause = "1 fields" }
            else if ResourceLoop.housingCapacity(s, registry: registry)
                        < StewardEngine.bedsWanted(for: s.population),
                    able.contains(where: { $0.housing > 0 }) { clause = "2 roofs" }
            else if !StewardEngine.brimmingResources(s).isEmpty,
                    able.contains(where: { def in
                        StewardEngine.brimmingResources(s).contains { def.storage[$0] > 0 } })
            { clause = "3 stores" }
            else if draw > 0, generation < draw,
                    able.contains(where: { $0.production[.energy] > 0 }) { clause = "3c power" }
            else if StewardEngine.hasSomethingSpare(s) { clause = "4 breadth" }
            turns[clause, default: 0] += 1

            print(String(format: "%4d  %-14@  gen %4.1f  want %5.2f  able-generators %d",
                         step * 10, clause, generation, draw,
                         able.filter { $0.production[.energy] > 0 }.count))
        }
        print("\ndecades by clause: \(turns.sorted { $0.value > $1.value })")
    }
}
