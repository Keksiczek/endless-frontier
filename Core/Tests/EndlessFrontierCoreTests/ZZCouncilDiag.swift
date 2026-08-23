import Testing
import Foundation
@testable import EndlessFrontierCore

/// **Why the council builds what it builds**, clause by clause.
///
/// `ZZStewardProbe` prints the outcome; this prints the *argument*. A colony
/// pinned at its materials cap with no warehouse standing is either a council
/// that cannot see the problem, one that cannot afford the answer, or one whose
/// earlier clause is permanently true and starving the rest (rule 27) — and
/// those three want completely different fixes.
@Suite("council diag", .enabled(if: ProcessInfo.processInfo.environment["EF_DIAG"] != nil, "diag"))
struct ZZCouncilDiag {

    @Test("what the council sees, and what it decides")
    func theArgument() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)

        print("\nyear pop | food/cap  mats/cap  know/cap  infl/cap | brimming | plots/want beds/want | able | clause -> pick")
        for step in 1...20 {
            state = TickEngine.advance(state, ticks: 600, registry: registry).state
            guard let s = state.settlements.first else { break }
            let year = step * 10
            let brim = StewardEngine.brimmingResources(s).map(\.rawValue).joined(separator: ",")
            let able = StewardEngine.buildableHere(s, in: state, registry: registry)
            let pick = StewardEngine.nextBuilding(for: s, in: state, registry: registry)

            // Which clause would answer, worked out the same way the engine does.
            let plots = FarmEngine.plotsStanding(s)
            let wantPlots = FarmEngine.plotsWanted(for: s.population)
            let beds = ResourceLoop.housingCapacity(s, registry: registry)
            let wantBeds = StewardEngine.bedsWanted(for: s.population)
            var clause = "none"
            if plots < wantPlots, able.contains(where: { $0.plots > 0 }) { clause = "1 fields" }
            else if beds < wantBeds, able.contains(where: { $0.housing > 0 }) { clause = "2 roofs" }
            else if !brim.isEmpty,
                    able.contains(where: { def in
                        StewardEngine.brimmingResources(s).contains { def.storage[$0] > 0 } })
            { clause = "3 stores" }
            else if StewardEngine.hasSomethingSpare(s) { clause = "4 breadth" }
            else { clause = "nothing spare" }

            print(String(format:
                "%4d %3d | %5.0f/%-5.0f %5.0f/%-5.0f %5.0f/%-5.0f %5.0f/%-5.0f | %-18@ | %3d/%-3d %4.0f/%-4.0f | %2d | %@ -> %@",
                year, Int(s.population),
                s.storage[.food], s.storageCapacity[.food],
                s.storage[.materials], s.storageCapacity[.materials],
                s.storage[.knowledge], s.storageCapacity[.knowledge],
                s.storage[.influence], s.storageCapacity[.influence],
                brim.isEmpty ? "-" : brim,
                plots, wantPlots, beds, wantBeds,
                able.count, clause, pick ?? "—"))
        }

        // What actually stands at the end, and what the stores could hold.
        guard let s = state.settlements.first else { return }
        print("\nstanding:")
        for b in s.buildings.sorted(by: { $0.definitionID < $1.definitionID }) {
            let def = registry.building(b.definitionID)
            print(String(format: "  %-20@ x%-3d  storage %@",
                         b.definitionID, b.count,
                         String(describing: def?.storage.nonZero ?? [:])))
        }
        print("\nnever built, though early-settlement and cheap:")
        for def in registry.buildings.values.sorted(by: { $0.id < $1.id })
        where !s.buildings.contains(where: { $0.definitionID == def.id })
            && def.era == .earlySettlement {
            print(String(format: "  %-20@ cost %4.0f  storage %@", def.id,
                         def.cost[.materials], String(describing: def.storage.nonZero)))
        }
    }
    
    /// **What the town is made of after two centuries.**
    ///
    /// The clause Keks reported on — *"staví knihovny a univerzity několikrát a
    /// nijaké výrobní nebo obranné budovy ne"* — is only visible in the tally,
    /// not in one sitting's pick. Prints what stands, by count, and what share
    /// of it makes something, keeps something, houses somebody or defends.
    @Test("what a colony ends up made of")
    func theTown() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        for _ in 0..<20 {
            state = BalanceHarness.autoPlay(state, registry: registry)
            state = TickEngine.advance(state, ticks: 600, registry: registry).state
        }
        guard let s = state.settlements.first else { return }
        let standing = s.buildings
            .compactMap { instance -> (String, Int, BuildingDefinition)? in
                guard let def = registry.building(instance.definitionID) else { return nil }
                return (instance.definitionID, instance.count, def)
            }
            .sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }

        func share(_ keep: (BuildingDefinition) -> Bool) -> Int {
            standing.filter { keep($0.2) }.reduce(0) { $0 + $1.1 }
        }
        let total = standing.reduce(0) { $0 + $1.1 }
        print("""

        ── what the council built, two hundred years ──────────────────
        \(total) buildings, \(s.pawns.count) souls, era \(state.era.rawValue)
        makes something  \(share { def in ResourceType.allCases.contains { def.production[$0] > 0 } })
        a place to work  \(share { $0.work != nil })
        defends          \(share { $0.defense > 0 })
        houses           \(share { $0.housing > 0 })
        stores           \(share { def in def.storage.amounts.contains { $0.value > 0 } })
        ───────────────────────────────────────────────────────────────
        """)
        for (id, count, _) in standing.prefix(18) {
            print(String(format: "  %-24@ %3d", id, count))
        }
        print("")
    }
}

extension Resources {
    /// Only the entries that are actually set — a dictionary of thirty zeroes
    /// says nothing in a diagnostic.
    var nonZero: [String: Double] {
        var out: [String: Double] = [:]
        for resource in ResourceType.allCases where self[resource] != 0 {
            out[resource.rawValue] = self[resource]
        }
        return out
    }
}
