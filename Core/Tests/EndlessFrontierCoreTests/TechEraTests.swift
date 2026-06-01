import Testing
@testable import EndlessFrontierCore

@Suite("Tech engine")
struct TechEngineTests {
    @Test("Research requires prerequisites")
    func prerequisitesEnforced() {
        let registry = Fixtures.registry()
        let state = Fixtures.world()
        // writing requires basic_tools, which isn't researched yet.
        let after = TechEngine.setResearch(state, techID: "writing", registry: registry)
        #expect(after.activeResearch == nil)
    }

    @Test("Available research can be queued")
    func queueAvailableTech() {
        let registry = Fixtures.registry()
        let state = Fixtures.world()
        let after = TechEngine.setResearch(state, techID: "basic_tools", registry: registry)
        #expect(after.activeResearch == "basic_tools")
    }

    @Test("Research completes when knowledge meets the cost and applies effects")
    func researchCompletes() {
        let registry = Fixtures.registry()
        var state = Fixtures.world()
        state = TechEngine.setResearch(state, techID: "basic_tools", registry: registry)
        state.globalStats.knowledgeOutput = 30   // exactly the cost

        let after = TechEngine.advanceResearch(state, registry: registry)
        #expect(after.researchedTechs.contains("basic_tools"))
        #expect(after.activeResearch == nil)
        #expect(after.unlockedBuildings.contains("library"))   // tech effect
    }

    @Test("availableTechs respects researched prerequisites")
    func availableTechsGating() {
        let registry = Fixtures.registry()
        #expect(registry.availableTechs(researched: []).map(\.id) == ["basic_tools"])
        #expect(registry.availableTechs(researched: ["basic_tools"]).map(\.id).contains("writing"))
    }
}

@Suite("Era engine")
struct EraEngineTests {
    @Test("Era advances only when all milestones are met")
    func advancesOnMilestones() {
        let registry = Fixtures.registry()
        var state = Fixtures.world(population: 60)
        state.researchedTechs.insert("writing")

        let after = EraEngine.checkAdvancement(state, registry: registry)
        #expect(after.era == .ancient)
    }

    @Test("Era does not advance when a milestone is unmet")
    func staysWhenUnmet() {
        let registry = Fixtures.registry()
        var state = Fixtures.world(population: 10)   // population milestone (60) unmet
        state.researchedTechs.insert("writing")

        let after = EraEngine.checkAdvancement(state, registry: registry)
        #expect(after.era == .earlySettlement)
    }

    @Test("Progress to next era is a fraction of satisfied milestones")
    func progressFraction() {
        let registry = Fixtures.registry()
        var state = Fixtures.world(population: 10)
        state.researchedTechs.insert("writing")     // 1 of 2 milestones met
        let progress = EraEngine.progressToNextEra(state, registry: registry)
        #expect(abs(progress - 0.5) < 1e-9)
    }
}
