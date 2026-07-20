import Testing
import Foundation
@testable import EndlessFrontierCore

/// The old diagnostic logged births, deaths and event names — it answered "what
/// happened" and never "why is nothing happening", which is the question every
/// serious bug in this game has actually been. It could not have shown tension
/// pinned at zero, a disaster gate nothing could reach, scouts whose only job
/// no code performed, or a lit expedition button over an empty woodpile.
@Suite("The report explains, rather than narrating")
struct WorldReportTests {
    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    @Test("It reports a world without crashing on a fresh one")
    func generatesForNewGame() throws {
        let reg = try registry()
        let world = GameWorldFactory.newGame(registry: reg, seed: 42)
        let text = WorldReport.generate(world, registry: reg)

        #expect(text.contains("WORLD REPORT"))
        #expect(text.contains("TENSION"))
        #expect(text.contains("CANNOT HAPPEN RIGHT NOW"))
    }

    /// Tension being a single number is what hid the calm death spiral for so
    /// long; the breakdown is the whole point.
    @Test("Tension is shown as its parts, not just its total")
    func tensionIsBrokenDown() throws {
        let reg = try registry()
        let world = GameWorldFactory.newGame(registry: reg, seed: 42)
        let text = WorldReport.generate(world, registry: reg)

        for part in ["base", "threat", "comfort", "shortages", "era ramp", "scale", "band"] {
            #expect(text.contains(part), "the breakdown must name '\(part)'")
        }
    }

    @Test("A store pinned at its cap is called out as pinned")
    func pinnedStoresAreNamed() throws {
        let reg = try registry()
        var world = GameWorldFactory.newGame(registry: reg, seed: 42)
        for resource in ResourceType.allCases {
            world.settlements[0].storage[resource] = world.settlements[0].storageCapacity
        }
        #expect(WorldReport.generate(world, registry: reg).contains("PINNED at cap"))
    }

    /// The exact report from the playtest: "I sent an expedition and nothing
    /// happened." The colony was broke and nothing said so.
    @Test("An unaffordable expedition is named as a blocker")
    func brokeExplorationIsABlocker() throws {
        let reg = try registry()
        var world = GameWorldFactory.newGame(registry: reg, seed: 42)
        for resource in ResourceType.allCases {
            world.settlements[0].storage[resource] = 1
        }
        let blockers = WorldReport.blockers(world, registry: reg)
        #expect(blockers.contains { $0.system == "world exploration" && $0.reason.contains("affordable") },
                "got: \(blockers)")
    }

    /// The other playtest report: "the settlement map never gets explored."
    @Test("Ground nobody is charting is named as a blocker")
    func unscoutedGroundIsABlocker() throws {
        let reg = try registry()
        var world = GameWorldFactory.newGame(registry: reg, seed: 42)
        for i in world.settlements[0].pawns.indices {
            world.settlements[0].pawns[i].assignedWork = .farming
        }
        let blockers = WorldReport.blockers(world, registry: reg)
        #expect(blockers.contains { $0.system == "settlement map" }, "got: \(blockers)")
    }

    @Test("A colony with scouts on the job is not flagged for it")
    func scoutedGroundIsFine() throws {
        let reg = try registry()
        var world = GameWorldFactory.newGame(registry: reg, seed: 42)
        world.settlements[0].pawns[0].assignedWork = .scouting
        #expect(!WorldReport.blockers(world, registry: reg).contains { $0.system == "settlement map" })
    }

    /// The signature bug of this codebase, checked automatically: a gate set
    /// above anything the system driving it can produce.
    @Test("The shipped diplomacy gates all sit under their own ceiling")
    func diplomacyGatesAreReachable() throws {
        let reg = try registry()
        let world = GameWorldFactory.newGame(registry: reg, seed: 42)
        let blockers = WorldReport.blockers(world, registry: reg)
        #expect(!blockers.contains { $0.system == "tribe marriage" },
                "a marriage gate above the compatibility ceiling is unreachable by arithmetic")
    }

    @Test("It survives an empty world")
    func emptyWorldIsSafe() throws {
        let reg = try registry()
        let empty = WorldState(tick: 0, settlements: [])
        let text = WorldReport.generate(empty, registry: reg)
        #expect(!text.isEmpty)
    }
}
