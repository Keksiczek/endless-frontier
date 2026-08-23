import Testing
import Foundation
@testable import EndlessFrontierCore

/// Keks, watching his own town: *"steward staví knihovny a univerzity několikrát
/// a nijaké výrobní nebo obranné budovy ne… chtělo by, aby stavěli nějak
/// rozumně, ideálně zase dle předpokladů lidí z rady."*
///
/// One line did that: once one of every kind stood, the council spent every
/// surplus on **the cheapest thing on the shelf**, for ever. What is tested
/// here is that the choice now reads the colony — and the people in the room.
@Suite("A council that builds what the town is short of")
struct CouncilAppetiteTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    /// A town with everything answered — fields, roofs, stores, larder, light —
    /// so `nextBuilding` reaches its last clause, which is the one under test.
    private func comfortable(_ registry: GameDataRegistry, souls: Int = 60) -> (WorldState, Settlement) {
        var world = GameWorldFactory.newGame(registry: registry, seed: 4242)
        var s = world.settlements[0]
        s.pawns = Fixtures.pawns(souls, work: .farming)
        for index in s.pawns.indices { s.pawns[index].age = 30 * 60 }
        s.storage = [.food: 900, .materials: 4_000, .energy: 400,
                     .knowledge: 400, .influence: 400]
        s.storageCapacity = .uniform(5_000)
        world.settlements[0] = s
        return (world, s)
    }

    private func score(_ id: String, _ world: WorldState, _ s: Settlement,
                       _ registry: GameDataRegistry) throws -> Double {
        let def = try #require(registry.building(id))
        return CouncilAppetite.score(def, for: s, in: world, registry: registry)
    }

    // MARK: - The observatory problem

    /// The fault as reported: the same building, over and over, while the
    /// colony wants something else entirely.
    @Test("The fifth of a thing is worth a fifth of the first")
    func repeatsFall() throws {
        let registry = try registry()
        let (world, base) = comfortable(registry)
        let first = try score("observatory", world, base, registry)
        var many = base
        many.buildings.append(BuildingInstance(definitionID: "observatory", count: 4))
        let fifth = try score("observatory", world, many, registry)
        #expect(first > 0, "an observatory is worth something to a town with none")
        #expect(fifth < first / 3, "\(fifth) against \(first): four already stand")
    }

    /// The other half of the same complaint: production and defence never won.
    @Test("A trade with people in it and nowhere to work outranks another library")
    func handsBeatBooks() throws {
        let registry = try registry()
        let (world, base) = comfortable(registry)
        var crafters = base
        for index in crafters.pawns.indices where index % 3 == 0 {
            crafters.pawns[index].assignedWork = .crafting
        }
        // A colony that already studies plenty and has nowhere to make anything.
        crafters.buildings.append(BuildingInstance(definitionID: "observatory", count: 2))
        let workshop = try score("workshop", world, crafters, registry)
        let observatory = try score("observatory", world, crafters, registry)
        #expect(workshop > observatory,
                "workshop \(workshop) against observatory \(observatory)")
    }

    @Test("A colony that makes nothing wants the thing that makes something")
    func scarcityLeads() throws {
        let registry = try registry()
        let (world, base) = comfortable(registry)
        let bare = try score("lumberyard", world, base, registry)
        var supplied = base
        supplied.buildings.append(BuildingInstance(definitionID: "lumberyard", count: 3))
        let sated = try score("lumberyard", world, supplied, registry)
        #expect(bare > sated, "\(bare) against \(sated)")
    }

    // MARK: - Walls, and only against something

    @Test("A quiet valley does not build walls")
    func peaceBuildsNoWalls() throws {
        let registry = try registry()
        var (world, base) = comfortable(registry)
        world.camps = []
        world.tribes = []
        base.localMap?.wildlife.predatorPressure = 0
        base.stats.defense = 0
        #expect(try score("palisade", world, base, registry) == 0,
                "nothing is out there; a wall answers nothing")
    }

    @Test("A valley with outlaws in it builds walls")
    func threatBuildsWalls() throws {
        let registry = try registry()
        let (world, base) = comfortable(registry)
        var threatened = base
        threatened.stats.defense = 0
        #expect(world.camps.count > 0, "the fixture has no outlaws — it measures nothing")
        #expect(try score("palisade", world, threatened, registry) > 0)
        // …and a colony already behind a good wall stops asking.
        var walled = threatened
        walled.stats.defense = 200
        #expect(try score("palisade", world, walled, registry) == 0)
    }

    // MARK: - The people in the room

    /// The part Keks asked for by name. A tilt, never a decision.
    @Test("A council of brave people reaches for the wall sooner")
    func courageTilts() throws {
        let registry = try registry()
        let (world, base) = comfortable(registry)
        func withCourage(_ value: Double) -> Settlement {
            var s = base
            s.stats.defense = 0
            for index in s.pawns.indices {
                s.pawns[index].genes = Genes(industry: 0.5, fertility: 0.5,
                                             sociability: 0.5, courage: value)
            }
            return s
        }
        let bold = try score("palisade", world, withCourage(0.9), registry)
        let timid = try score("palisade", world, withCourage(0.1), registry)
        #expect(bold > timid, "\(bold) against \(timid)")
        // …but a tilt, not a decision: the timid still build one when there is
        // something out there.
        #expect(timid > 0)
    }

    @Test("A council of workers reaches for the workshop sooner")
    func industryTilts() throws {
        let registry = try registry()
        let (world, base) = comfortable(registry)
        func withIndustry(_ value: Double) -> Settlement {
            var s = base
            for index in s.pawns.indices {
                s.pawns[index].assignedWork = .crafting
                s.pawns[index].genes = Genes(industry: value, fertility: 0.5,
                                             sociability: 0.5, courage: 0.5)
            }
            return s
        }
        let busy = try score("workshop", world, withIndustry(0.9), registry)
        let idle = try score("workshop", world, withIndustry(0.1), registry)
        #expect(busy > idle, "\(busy) against \(idle)")
    }

    @Test("A council of ordinary people tilts nothing")
    func themiddlingTiltNothing() throws {
        let registry = try registry()
        let (_, base) = comfortable(registry)
        var plain = base
        for index in plain.pawns.indices {
            plain.pawns[index].genes = Genes()
            plain.pawns[index].assignedWork = .farming
        }
        let def = try #require(registry.building("palisade"))
        #expect(abs(CouncilAppetite.taste(def, settlement: plain, registry: registry)) < 0.01)
    }

    /// The leader's name is on it, so their opinion is worth two.
    @Test("The leader counts double")
    func theLeaderWeighsMore() throws {
        let registry = try registry()
        let (_, base) = comfortable(registry)
        var s = base
        for index in s.pawns.indices {
            s.pawns[index].genes = Genes(industry: 0.5, fertility: 0.5,
                                         sociability: 0.5, courage: 0.5)
        }
        s.pawns[0].genes = Genes(industry: 0.5, fertility: 0.5, sociability: 0.5, courage: 1)
        let def = try #require(registry.building("palisade"))
        let asOne = CouncilAppetite.taste(def, settlement: s, registry: registry)
        s.leaderID = s.pawns[0].id
        let asLeader = CouncilAppetite.taste(def, settlement: s, registry: registry)
        #expect(asLeader > asOne, "\(asLeader) against \(asOne)")
    }

    // MARK: - Wired

    /// End to end: the council actually picks it, not just scores it.
    @Test("A comfortable colony with idle crafters is given somewhere to work")
    func theCouncilPicksIt() throws {
        let registry = try registry()
        var (world, base) = comfortable(registry)
        for index in base.pawns.indices where index % 2 == 0 {
            base.pawns[index].assignedWork = .crafting
        }
        // Everything the earlier clauses answer, answered — so control reaches
        // the last one, which is the clause under test.
        base.buildings.append(BuildingInstance(definitionID: "observatory", count: 3))
        world.settlements[0] = base
        world.unlockedBuildings = Set(registry.buildings.keys)
        let pick = StewardEngine.nextBuilding(for: base, in: world, registry: registry)
        #expect(pick != "observatory", "a fourth observatory is not an answer to anything")
    }

    /// The second fault the tally found, once the observatories were gone: a
    /// town of 158 souls stood at 124 buildings, **81 of them stores** — a
    /// store defers a spill and never ends one, and the clause that builds
    /// them had no notion of enough.
    @Test("There is such a thing as enough roof")
    func storesStopSomewhere() throws {
        let registry = try registry()
        let (_, base) = comfortable(registry, souls: 100)
        var packed = base
        // Brimming, and roofed far past what a hundred people can use.
        packed.storageCapacity = [.materials: 20_000, .food: 20_000, .energy: 20_000,
                                  .knowledge: 20_000, .influence: 20_000]
        packed.storage = [.materials: 19_500, .food: 19_500, .energy: 19_500,
                          .knowledge: 19_500, .influence: 19_500]
        #expect(StewardEngine.brimmingResources(packed).isEmpty,
                "a colony with two hundred sacks of room per soul is not short of a warehouse")
        // …and a colony that genuinely has no room still asks.
        var cramped = base
        cramped.storageCapacity = .uniform(500)
        cramped.storage = .uniform(490)
        #expect(!StewardEngine.brimmingResources(cramped).isEmpty)
    }

    @Test("Nothing is always worth building")
    func aCouncilMaySaveItsMaterials() throws {
        let registry = try registry()
        let (world, base) = comfortable(registry)
        // A definition that produces nothing, holds nothing, houses nobody and
        // defends nothing scores nothing at all.
        let empty = BuildingDefinition(id: "folly", era: .earlySettlement, name: "Folly",
                                       cost: [.materials: 400])
        #expect(CouncilAppetite.score(empty, for: base, in: world, registry: registry)
                < CouncilAppetite.worthBuilding)
    }
}
