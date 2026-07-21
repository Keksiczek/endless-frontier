import Testing
import Foundation
@testable import EndlessFrontierCore

/// Regressions for "the colony is safe, prosperous and nothing ever happens".
///
/// Measured before these fixes, over 12,000 auto-played ticks: tension never
/// rose above ~7, so the planner's `tension > 40` gate meant **not one** of the
/// 16 disaster and 9 threat templates could ever fire; the storyteller spent
/// 200 years rolling the same handful of flavour events (calm_season 400×).
@Suite("Drama — the colony must be able to get into trouble")
struct TensionRangeTests {
    /// The calm death spiral: prosperity chases morale, so a healthy colony sat
    /// at prosperity ≈ 83, whose dampener (×0.2 = 16.6) alone exceeded base+threat
    /// (14) and clamped tension to exactly 0 — forever.
    @Test("A thriving colony still carries real tension")
    func thrivingColonyIsNotAtZeroTension() {
        var world = Fixtures.world(population: 50)
        world.globalStats.prosperity = 83
        world.globalStats.threatLevel = 10

        let tension = TensionCalculator.calculate(world, config: .default)
        #expect(tension > 0, "a prosperous colony must not be pinned at zero tension")
    }

    /// Prosperity should still soothe — but relative to a neutral midpoint, so
    /// it can never single-handedly swamp every other term.
    @Test("Prosperity soothes, misery bites")
    func prosperityIsRelativeToNeutral() {
        var poor = Fixtures.world(population: 50)
        poor.globalStats.prosperity = 15
        var rich = poor
        rich.globalStats.prosperity = 90

        let poorTension = TensionCalculator.calculate(poor, config: .default)
        let richTension = TensionCalculator.calculate(rich, config: .default)
        #expect(poorTension > richTension, "a miserable colony should be tenser than a rich one")
    }

    /// The pressure the game was missing: a big fat colony is a target. This is
    /// what keeps late-game interesting instead of terminally safe.
    @Test("A large colony attracts more trouble than a hamlet")
    func scalePressureRisesWithPopulation() {
        let hamlet = Fixtures.world(population: 20)
        let city = Fixtures.world(population: 2000)
        #expect(TensionCalculator.calculate(city, config: .default)
                > TensionCalculator.calculate(hamlet, config: .default))
    }

    @Test("Tension stays clamped to 0…100 even at absurd scale")
    func stillBounded() {
        var world = Fixtures.world(population: 100_000)
        world.globalStats.threatLevel = 100
        world.globalStats.prosperity = 0
        world.era = .nearFuture
        let t = TensionCalculator.calculate(world, config: .default)
        #expect(t >= 0 && t <= 100)
    }
}

@Suite("Drama — disasters must be reachable")
struct DisasterReachabilityTests {
    static let quake = EventTemplate(
        id: "quake", type: .disaster, name: "Quake", era: [], weight: 100,
        cooldownTicks: 0,
        effects: [.statDelta(stat: .parse("global.prosperity"), delta: -5)],
        narrativeHint: "The earth moves."
    )

    /// The bug: `StoryPlanner.run` hard-gated major events on `tension > 40`,
    /// below which the pool was `[.opportunity, .quest]` — so a calm colony
    /// could never, in principle, see a disaster. The tension *bands* already
    /// express "calm ⇒ fewer disasters" (disasterWeight 0.5); the hard gate was
    /// redundant and turned a soft weighting into a wall.
    @Test("A calm colony can still be struck by disaster")
    func disastersCanFireAtLowTension() {
        let registry = Fixtures.registry(events: [Self.quake], config: .default)
        var world = Fixtures.world()
        world.globalStats.prosperity = 90   // as calm as it gets
        world.globalStats.threatLevel = 0

        #expect(TensionCalculator.calculate(world, config: registry.config) <= 40,
                "precondition: this colony is in the calm band")

        // Over many cycles the disaster must fire at least once.
        var fired = 0
        for cycle in 0..<400 {
            var s = world
            s.tick = cycle * registry.config.plannerInterval
            s.rngSeed = UInt64(cycle &* 2_654_435_761)
            fired += StoryPlanner.run(s, registry: registry).fired.count
        }
        #expect(fired > 0, "disasters must be possible in a calm colony, merely rare")
    }

    @Test("Rising tension makes disasters more likely, not merely possible")
    func disastersScaleWithTension() {
        let registry = Fixtures.registry(events: [Self.quake], config: .default)

        func fireCount(prosperity: Double, threat: Double) -> Int {
            var total = 0
            for cycle in 0..<400 {
                var s = Fixtures.world()
                s.globalStats.prosperity = prosperity
                s.globalStats.threatLevel = threat
                s.tick = cycle * registry.config.plannerInterval
                s.rngSeed = UInt64(cycle &* 2_654_435_761)
                total += StoryPlanner.run(s, registry: registry).fired.count
            }
            return total
        }

        let calm = fireCount(prosperity: 90, threat: 0)
        let dire = fireCount(prosperity: 10, threat: 100)
        #expect(dire > calm, "a colony in crisis should see more disasters than a calm one")
    }
}

@Suite("Drama — the storyteller must know how to be quiet")
struct EventDensityTests {
    static let flavour = EventTemplate(
        id: "calm", type: .flavor, name: "Calm Season", era: [], weight: 100,
        cooldownTicks: 0,
        effects: [], narrativeHint: "Nothing much happens."
    )

    /// The reported symptom: 1,418 ticks produced 100+ events, the same few on
    /// repeat. The planner fired up to `maxMinorEventsPerCycle` (3) *every*
    /// cycle unconditionally — there was no "nothing happens" outcome at all.
    @Test("Most cycles pass without an event")
    func quietCyclesAreTheNorm() {
        let registry = Fixtures.registry(events: [Self.flavour], config: .default)
        var firedCycles = 0
        let cycles = 500
        for cycle in 0..<cycles {
            var s = Fixtures.world()
            s.tick = cycle * registry.config.plannerInterval
            s.rngSeed = UInt64(cycle &* 2_654_435_761)
            if !StoryPlanner.run(s, registry: registry).fired.isEmpty { firedCycles += 1 }
        }
        #expect(firedCycles < cycles / 2,
                "an event every cycle is spam; quiet must be the default (fired \(firedCycles)/\(cycles))")
        #expect(firedCycles > 0, "…but the storyteller must not go mute either")
    }
}

/// Nothing in the game consumed materials or influence at all — they were only
/// ever spent as a one-off at build time — so every stockpile except food ran
/// to the cap and sat there. A colony you have built should cost something to
/// keep standing.
@Suite("Drama — the colony costs something to run")
struct UpkeepTests {
    static let quarry = BuildingDefinition(
        id: "quarry", era: .earlySettlement, name: "Quarry",
        cost: [.materials: 100], production: [.materials: 5]
    )

    @Test("Upkeep is derived from what the building cost to raise")
    func upkeepScalesWithCost() {
        let cheap = BuildingDefinition(id: "hut", era: .earlySettlement, name: "Hut",
                                       cost: [.materials: 10])
        let dear = BuildingDefinition(id: "arcology", era: .nearFuture, name: "Arcology",
                                      cost: [.materials: 480])
        let config = WorldConfig.default
        #expect(ResourceLoop.upkeep(for: dear, config: config)[.materials]
                > ResourceLoop.upkeep(for: cheap, config: config)[.materials],
                "a costlier building should cost more to maintain, so upkeep scales with era for free")
    }

    @Test("An explicit upkeep in the data overrides the derived one")
    func explicitUpkeepWins() {
        let monument = BuildingDefinition(
            id: "monument", era: .ancient, name: "Monument",
            cost: [.materials: 200], upkeep: [.materials: 0]
        )
        #expect(ResourceLoop.upkeep(for: monument, config: .default)[.materials] == 0,
                "data must be able to say 'this one needs no upkeep'")
    }

    @Test("Standing buildings draw upkeep every tick")
    func upkeepIsCharged() {
        let registry = Fixtures.registry(buildings: [Self.quarry], config: .default)
        var world = WorldState(tick: 0, settlements: [
            Settlement(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!,
                name: "Works", pawns: Fixtures.pawns(2, work: .mining),
                buildings: [BuildingInstance(definitionID: "quarry", count: 10)],
                storage: [.materials: 300, .food: 500]
            )
        ])
        let before = world.settlements[0].storage[.materials]
        world = TickEngine.advance(world, ticks: 1, registry: registry).state
        let after = world.settlements[0].storage[.materials]
        // 10 quarries produce 50/tick gross but cost 10 × (100 × rate) to keep.
        let expectedUpkeep = 10 * ResourceLoop.upkeep(for: Self.quarry, config: .default)[.materials]
        #expect(after < before + 50, "upkeep must be drawn from the same stockpile production feeds")
        #expect(expectedUpkeep > 0)
    }
}

@Suite("Drama — storage is a real sink")
struct StorageCapacityTests {
    static let granary = BuildingDefinition(
        id: "granary", era: .earlySettlement, name: "Granary",
        cost: [.materials: 20], storage: 250,
        description: "Stores grain against the lean months."
    )

    /// The Granary's description promised storage and granted exactly none —
    /// capacity was a flat 500 forever, in every era, at any size. With nothing
    /// scarce, no choice costs anything.
    @Test("A granary actually grants storage")
    func granaryGrantsCapacity() {
        let registry = Fixtures.registry(buildings: [Self.granary], config: .default)
        let bare = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-4461e84c85e0")!, name: "Bare", pawns: Fixtures.pawns(5), buildings: [])
        let stocked = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-fa3e745b4cbf")!, name: "Stocked", pawns: Fixtures.pawns(5),
                                 buildings: [BuildingInstance(definitionID: "granary", count: 2)])

        let bareCap = ResourceLoop.storageCapacity(bare, registry: registry)
        let stockedCap = ResourceLoop.storageCapacity(stocked, registry: registry)
        #expect(stockedCap == bareCap + 500, "two granaries should add 2×250 capacity")
    }

    /// Capacity is derived from buildings like housing is, so an existing save
    /// (which stores a flat 500) simply recomputes on the next tick — no
    /// migration needed.
    @Test("Capacity recomputes from buildings as the colony grows")
    func capacityRecomputesOnTick() {
        let registry = Fixtures.registry(buildings: [Self.granary], config: .default)
        var world = WorldState(tick: 0, settlements: [
            Settlement(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
                name: "Old Save", pawns: Fixtures.pawns(5),
                buildings: [BuildingInstance(definitionID: "granary", count: 1)],
                storage: [.food: 10],
                storageCapacity: 500   // what a pre-fix save holds
            )
        ])
        world = TickEngine.advance(world, ticks: 1, registry: registry).state
        #expect(world.settlements[0].storageCapacity > 500,
                "the granary's capacity should be picked up without a migration")
    }
}
