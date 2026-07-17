import Testing
import Foundation
@testable import EndlessFrontierCore

/// Neighbouring peoples are the *only* way diplomacy comes into being — they're
/// emergent, founded by colonists who walk out. Measured over 250 auto-played
/// years: **0 tribes appeared**, so trade, marriage, war, defectors and every
/// player-facing diplomatic act were unreachable.
///
/// Neither existing trigger could fire in a functioning colony:
/// · misery   — needs morale < 42; a working colony sits at 70–86.
/// · crowding — needs population > 105% of housing, which
///   `PopulationEngine.headroomFactor` makes impossible by damping births to
///   nothing as the last huts fill.
///
/// Inequality, by contrast, is abundant: Gini measured 0.588, over the revolt
/// threshold in 197 of 300 samples, with 1,328 poor of 3,322 colonists. So the
/// people who leave are the ones with nothing to stay for.
@Suite("Secession — the aggrieved walk out")
struct SecessionTests {
    /// A prosperous, contented, well-housed colony — with a chasm between its
    /// richest and poorest.
    private func unequalColony(gini: Double, morale: Double = 80) -> WorldState {
        var settlement = Settlement(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            name: "Seat", pawns: [], buildings: [BuildingInstance(definitionID: "hut", count: 40)],
            storage: [.food: 5000]
        )
        // 40 adults: a few rich, the rest with nothing.
        settlement.pawns = (0..<40).map { i in
            var pawn = Pawn(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 100 + i))!,
                name: "Settler \(i)", assignedWork: .farming)
            pawn.age = 25 * 60
            pawn.wealth = i < 4 ? 900 : 3
            return pawn
        }
        settlement.stats.morale = morale
        settlement.society.gini = gini
        settlement.society.poorCeiling = 10
        settlement.society.wealthyFloor = 500
        var state = WorldState(tick: 6000, settlements: [settlement])
        state.mapSeed = 99
        return state
    }

    private var registry: GameDataRegistry {
        Fixtures.registry(
            buildings: [BuildingDefinition(id: "hut", era: .earlySettlement, name: "Hut",
                                           cost: [.materials: 10], housing: 30)],
            config: .default)
    }

    @Test("A grievance drives a people out even from a contented colony")
    func inequalityCausesSecession() {
        let reg = registry
        // Sweep years: the roll is seeded per (mapSeed, settlement, year), so a
        // live trigger must fire within a plausible span rather than never.
        var seceded = false
        for year in 0..<40 {
            let after = DiplomacyEngine.secede(unequalColony(gini: 0.6), registry: reg, year: year)
            if !after.tribes.isEmpty { seceded = true; break }
        }
        #expect(seceded, "a colony this unequal must eventually shed the people it failed")
    }

    @Test("An equal colony holds together")
    func equalityHoldsTogether() {
        let reg = registry
        var seceded = false
        for year in 0..<40 {
            let after = DiplomacyEngine.secede(unequalColony(gini: 0.05), registry: reg, year: year)
            if !after.tribes.isEmpty { seceded = true; break }
        }
        #expect(!seceded, "nobody walks out of a colony that shares what it has")
    }

    @Test("It is the poor who leave")
    func thePoorAreTheOnesWhoGo() {
        let reg = registry
        for year in 0..<40 {
            let before = unequalColony(gini: 0.6)
            let after = DiplomacyEngine.secede(before, registry: reg, year: year)
            guard !after.tribes.isEmpty else { continue }
            let left = Set(before.settlements[0].pawns.map(\.id))
                .subtracting(after.settlements[0].pawns.map(\.id))
            let wealthOfLeavers = before.settlements[0].pawns
                .filter { left.contains($0.id) }.map(\.wealth)
            #expect(wealthOfLeavers.allSatisfy { $0 < 500 },
                    "the rich have no reason to walk into the wilderness")
            return
        }
        Issue.record("no secession fired, so the trigger is unreachable")
    }

    @Test("Their story says why they went")
    func grievanceHasItsOwnStory() {
        let reg = registry
        for year in 0..<40 {
            let after = DiplomacyEngine.secede(unequalColony(gini: 0.6), registry: reg, year: year)
            guard let tribe = after.tribes.first else { continue }
            #expect(tribe.standing < 0, "people who left over injustice don't start out friendly")
            return
        }
        Issue.record("no secession fired, so the trigger is unreachable")
    }
}

/// Banking knowledge was actively harmful: `advanceResearch` drew *every*
/// settlement's stock and then reset `researchProgress` to zero on completion,
/// so a colony holding 5,000 that finished a 100-cost tech destroyed 4,900 of
/// it. Measured exactly that. It's also why the knowledge pill read 0 forever.
@Suite("Research spends what it costs, not everything you have")
struct KnowledgeOverflowTests {
    static let cheap = TechDefinition(id: "cheap", name: "Cheap", era: .earlySettlement,
                                      cost: [.knowledge: 100])
    static let dear = TechDefinition(id: "dear", name: "Dear", era: .earlySettlement,
                                     cost: [.knowledge: 100_000])

    private func world(knowledge: Double) -> WorldState {
        WorldState(tick: 0, settlements: [
            Settlement(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
                       name: "Scholars", pawns: Fixtures.pawns(2),
                       storage: [.knowledge: knowledge, .food: 500])
        ])
    }

    @Test("A cheap study leaves the rest of the stockpile alone")
    func surplusSurvives() {
        let reg = Fixtures.registry(techs: [Self.cheap], config: .default)
        var w = TechEngine.setResearch(world(knowledge: 5000), techID: "cheap", registry: reg)
        w = TechEngine.advanceResearch(w, registry: reg)

        #expect(w.researchedTechs.contains("cheap"))
        #expect(w.settlements[0].storage[.knowledge] == 4900,
                "banking knowledge must not be a way to burn it")
    }

    @Test("A study still draws everything it needs")
    func drawsWhatItNeeds() {
        let reg = Fixtures.registry(techs: [Self.dear], config: .default)
        var w = TechEngine.setResearch(world(knowledge: 5000), techID: "dear", registry: reg)
        w = TechEngine.advanceResearch(w, registry: reg)

        #expect(!w.researchedTechs.contains("dear"))
        #expect(w.settlements[0].storage[.knowledge] == 0, "an unfinished study takes all you can give")
        #expect(w.researchProgress == 5000)
    }

    @Test("With nothing being studied, knowledge simply accumulates")
    func idleColonyBanks() {
        let reg = Fixtures.registry(techs: [Self.cheap], config: .default)
        let w = TechEngine.advanceResearch(world(knowledge: 5000), registry: reg)
        #expect(w.settlements[0].storage[.knowledge] == 5000)
    }
}
