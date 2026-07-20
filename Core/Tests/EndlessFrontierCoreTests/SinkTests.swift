import Testing
import Foundation
@testable import EndlessFrontierCore

/// Every resource needs a sink, and each must scale with something *different*
/// — that is the property that made food the only one that ever worked, while
/// energy, knowledge and influence ran to the storage cap and sat there.
///
/// · food       people eat            → population   (already worked)
/// · materials  building upkeep       → what you built
/// · energy     people live           → population × era
/// · influence  people are governed   → population above a threshold
/// · knowledge  endless research      → the player's choice

@Suite("Sinks — energy powers the colony's life")
struct EnergyDemandTests {
    static let generator = BuildingDefinition(
        id: "generator", era: .earlyIndustrial, name: "Generator",
        cost: [.materials: 100], production: [.energy: 50]
    )

    private func world(era: Era, population: Int, energy: Double) -> WorldState {
        var state = WorldState(tick: 0, settlements: [
            Settlement(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!,
                name: "Works", pawns: Fixtures.pawns(population),
                buildings: [BuildingInstance(definitionID: "generator", count: 1)],
                storage: [.energy: energy, .food: 5000]
            )
        ])
        state.era = era
        return state
    }

    /// A hamlet with no wiring shouldn't be billed for electricity — there is
    /// no generation at all before the windmill, so an early demand would just
    /// bankrupt a colony that can do nothing about it.
    @Test("An early settlement draws no domestic power")
    func noDemandBeforeIndustry() {
        let registry = Fixtures.registry(buildings: [Self.generator], config: .default)
        let demand = ResourceLoop.domesticEnergyDemand(
            population: 500, era: .earlySettlement, config: registry.config)
        #expect(demand == 0)
    }

    @Test("Domestic demand rises with population and with the era")
    func demandScales() {
        let config = WorldConfig.default
        let small = ResourceLoop.domesticEnergyDemand(population: 100, era: .modern, config: config)
        let large = ResourceLoop.domesticEnergyDemand(population: 2000, era: .modern, config: config)
        let earlier = ResourceLoop.domesticEnergyDemand(population: 2000, era: .earlyIndustrial, config: config)
        #expect(large > small, "more people draw more power")
        #expect(large > earlier, "a later era lives more electrically")
    }

    @Test("A modern city actually drains its grid")
    func demandIsCharged() {
        let registry = Fixtures.registry(buildings: [Self.generator], config: .default)
        let before = world(era: .modern, population: 800, energy: 400)
        let after = TickEngine.advance(before, ticks: 1, registry: registry).state
        // One generator makes 50/tick; 800 modern citizens should outdraw it.
        #expect(after.settlements[0].storage[.energy] < before.settlements[0].storage[.energy],
                "a city too big for its grid must run its stores down, not fill them")
    }

    @Test("A grid that cannot meet demand costs morale")
    func brownoutsHurt() {
        let registry = Fixtures.registry(buildings: [Self.generator], config: .default)
        let dark = world(era: .nearFuture, population: 4000, energy: 0)
        let after = TickEngine.advance(dark, ticks: 1, registry: registry).state
        #expect(after.settlements[0].stats.morale < dark.settlements[0].stats.morale,
                "living in the dark should be felt")
    }
}

@Suite("Sinks — influence governs the civilisation")
struct AdministrationTests {
    private func world(population: Int, influence: Double) -> WorldState {
        WorldState(tick: 0, settlements: [
            Settlement(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!,
                name: "Capital", pawns: Fixtures.pawns(population),
                buildings: [],
                storage: [.influence: influence, .food: 5000]
            )
        ])
    }

    /// A village settles its business by talking to each other; it shouldn't
    /// need political capital it has no way to earn (no influence building
    /// exists before the ancient trade post).
    @Test("A village governs itself for free")
    func smallSettlementsAreFree() {
        let cost = ResourceLoop.administrationCost(
            population: 40, settlements: 1, config: .default)
        #expect(cost == 0)
    }

    @Test("Administration grows with the population it must hold together")
    func costScalesWithSize() {
        let config = WorldConfig.default
        let town = ResourceLoop.administrationCost(population: 500, settlements: 1, config: config)
        let empire = ResourceLoop.administrationCost(population: 5000, settlements: 1, config: config)
        #expect(empire > town)
        #expect(town > 0)
    }

    @Test("More settlements cost more to hold")
    func costScalesWithSettlements() {
        let config = WorldConfig.default
        let one = ResourceLoop.administrationCost(population: 500, settlements: 1, config: config)
        let five = ResourceLoop.administrationCost(population: 500, settlements: 5, config: config)
        #expect(five > one)
    }

    /// The link that gives influence teeth: a civilisation whose administration
    /// has run dry starts coming apart, which is already how tribes split off.
    @Test("An ungovernable civilisation loses stability")
    func bankruptAdministrationCostsStability() {
        let registry = Fixtures.registry(buildings: [], config: .default)
        let broke = world(population: 3000, influence: 0)
        let after = TickEngine.advance(broke, ticks: 1, registry: registry).state
        #expect(after.settlements[0].stats.stability < broke.settlements[0].stats.stability,
                "with nothing left to govern with, the realm should start to fray")
    }
}

/// Every write to stability in the whole engine was a subtraction — an
/// uprising, isolation, a specialisation switch — and nothing anywhere put it
/// back. A realm could only ever ratchet down to zero and stay there, which
/// also meant the influence penalty above would have been permanent damage
/// rather than pressure.
@Suite("Stability recovers")
struct StabilityRecoveryTests {
    private func world(stability: Double, morale: Double) -> WorldState {
        var settlement = Settlement(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!,
            name: "Recovering", pawns: Fixtures.pawns(20),
            storage: [.food: 5000, .influence: 5000]
        )
        settlement.stats.stability = stability
        settlement.stats.morale = morale
        return WorldState(tick: 0, settlements: [settlement])
    }

    @Test("A shaken but contented settlement settles back down")
    func stabilityClimbsBack() {
        let registry = Fixtures.registry(buildings: [], config: .default)
        let shaken = world(stability: 20, morale: 80)
        let after = TickEngine.advance(shaken, ticks: 1, registry: registry).state
        #expect(after.settlements[0].stats.stability > 20,
                "a realm must be able to recover from a shock, or every wound is terminal")
    }

    @Test("A miserable settlement does not")
    func miseryKeepsItDown() {
        let registry = Fixtures.registry(buildings: [], config: .default)
        let wretched = world(stability: 60, morale: 5)
        let after = TickEngine.advance(wretched, ticks: 1, registry: registry).state
        #expect(after.settlements[0].stats.stability < 60,
                "recovery must be earned by contentment, not handed out")
    }

    @Test("Recovery is slower than the shocks that cause it")
    func recoveryIsSlow() {
        let registry = Fixtures.registry(buildings: [], config: .default)
        let shaken = world(stability: 20, morale: 100)
        let after = TickEngine.advance(shaken, ticks: 1, registry: registry).state
        let gained = after.settlements[0].stats.stability - 20
        #expect(gained < ResourceLoop.ungovernedStabilityPenalty,
                "an ungoverned realm must still lose ground faster than it heals")
    }
}

@Suite("Sinks — research never runs out")
struct EndlessResearchTests {
    static let finite = TechDefinition(
        id: "writing", name: "Writing", era: .earlySettlement, cost: [.knowledge: 50]
    )
    static let endless = TechDefinition(
        id: "inquiry", name: "Continued Inquiry", era: .earlySettlement,
        cost: [.knowledge: 100], repeatable: true
    )

    private func registry() -> GameDataRegistry {
        Fixtures.registry(techs: [Self.finite, Self.endless], config: .default)
    }

    /// DESIGN.md promises one endless world with no "you finished it" wall, but
    /// the tech tree had exactly 29 techs — after which knowledge had no sink at
    /// all and simply pinned at the cap forever.
    @Test("A repeatable tech stays available after it's been researched")
    func repeatableStaysOnTheBoard() {
        let reg = registry()
        let available = reg.availableTechs(researched: ["writing", "inquiry"])
        #expect(available.contains { $0.id == "inquiry" })
        #expect(!available.contains { $0.id == "writing" }, "a finite tech is done for good")
    }

    @Test("Each completion makes the next one dearer")
    func costEscalates() {
        let reg = registry()
        var world = WorldState(tick: 0, settlements: [])
        let first = TechEngine.cost(of: Self.endless, in: world, config: reg.config)
        world.techCompletions["inquiry"] = 3
        let fourth = TechEngine.cost(of: Self.endless, in: world, config: reg.config)
        #expect(fourth > first, "endless research must get harder or it's free knowledge")
    }

    @Test("Researching a repeatable tech banks a completion and can be restarted")
    func completionsAccumulate() {
        let reg = registry()
        var world = WorldState(tick: 0, settlements: [
            Settlement(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!,
                name: "Scholars", pawns: Fixtures.pawns(3),
                storage: [.knowledge: 500, .food: 500]
            )
        ])
        world = TechEngine.setResearch(world, techID: "inquiry", registry: reg)
        world = TechEngine.advanceResearch(world, registry: reg)
        #expect(world.techCompletions["inquiry"] == 1)

        // …and the Leader may commit to it again.
        world = TechEngine.setResearch(world, techID: "inquiry", registry: reg)
        #expect(world.activeResearch == "inquiry", "an endless study must be re-selectable")
    }

    @Test("Finite techs still complete exactly once")
    func finiteTechsUnchanged() {
        let reg = registry()
        var world = WorldState(tick: 0, settlements: [
            Settlement(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C4")!,
                name: "Scholars", pawns: Fixtures.pawns(3),
                storage: [.knowledge: 500, .food: 500]
            )
        ])
        world = TechEngine.setResearch(world, techID: "writing", registry: reg)
        world = TechEngine.advanceResearch(world, registry: reg)
        #expect(world.researchedTechs.contains("writing"))
        #expect(world.techCompletions["writing"] == nil)
        world = TechEngine.setResearch(world, techID: "writing", registry: reg)
        #expect(world.activeResearch == nil, "a finished tech can't be studied again")
    }
}
