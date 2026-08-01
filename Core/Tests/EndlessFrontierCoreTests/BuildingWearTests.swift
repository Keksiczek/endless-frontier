import Testing
import Foundation
@testable import EndlessFrontierCore

/// Buildings were immortal. Now they weather, take damage of particular kinds,
/// stop working when it gets bad enough, and have to be kept up. These pin the
/// parts that fail quietly: wear that can never reach the threshold meant to
/// matter, repair that is free, or a ruin that still shelters people.
@Suite("A building is a thing that needs keeping")
struct BuildingWearTests {

    private var registry: GameDataRegistry {
        GameDataRegistry(
            buildings: [
                BuildingDefinition(id: "hut", era: .earlySettlement, name: "Hut",
                                   cost: [.materials: 10], housing: 8),
                BuildingDefinition(id: "workshop", era: .earlySettlement, name: "Workshop",
                                   cost: [.materials: 40], workers: 2,
                                   production: [.materials: 4])
            ],
            techs: [], eras: [], biomes: [], events: [], config: .default)
    }

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-B111-%012d", n))!
    }

    private func town(_ buildings: [(String, Double)], masons: Int = 0,
                      materials: Double = 500) -> Settlement {
        var s = Settlement(id: id(999), name: "Wearing", regionID: UUID())
        var colony = ColonyMap(width: 18, height: 18)
        colony.placements = buildings.enumerated().map { index, entry in
            BuildingPlacement(id: id(index), definitionID: entry.0,
                              coord: TileCoord(index % 6 * 2, index / 6 * 2),
                              condition: entry.1)
        }
        s.colony = colony
        s.storage[.materials] = materials
        s.pawns = (0..<masons).map { i in
            Pawn(id: id(500 + i), name: "Mason \(i)", assignedWork: .building)
        }
        return s
    }

    // MARK: - Wear

    @Test("A roof left alone through a winter is visibly worse for it")
    func weatherBites() {
        var s = town([("hut", 1.0)])
        // A winter's worth of intervals.
        for tick in stride(from: 0, to: 900, by: BuildingEngine.interval) {
            s = BuildingEngine.weather(s, registry: registry, tick: tick)
        }
        let after = s.colony?.placements[0].condition ?? 1
        #expect(after < 1)
        #expect(after > 0, "a few years of weather should not level a hut")
    }

    /// The recurring bug in this codebase: a threshold beyond the reach of the
    /// rate meant to cross it. Wear has to actually be able to ruin a building
    /// left alone, or the whole layer is decoration.
    @Test("Weather alone can eventually ruin a building nobody keeps up")
    func neglectIsReachable() {
        var s = town([("hut", 1.0)])
        var ticks = 0
        while (s.colony?.placements[0].condition ?? 0) >= BuildingEngine.derelictBelow,
              ticks < 400_000 {
            s = BuildingEngine.weather(s, registry: registry, tick: ticks)
            ticks += BuildingEngine.interval
        }
        #expect((s.colony?.placements[0].condition ?? 1) < BuildingEngine.derelictBelow,
                "wear never reached the threshold it is meant to cross")
    }

    @Test("Winter is harder on a roof than summer")
    func seasonsDiffer() {
        // Tick 0 is spring in the default calendar; a winter tick is three
        // quarters of the way round the year.
        let ticksPerYear = registry.config.ticksPerYear
        var summer = town([("hut", 1.0)])
        var winter = town([("hut", 1.0)])
        for year in 0..<8 {
            summer = BuildingEngine.weather(summer, registry: registry,
                                            tick: year * ticksPerYear + ticksPerYear / 4)
            winter = BuildingEngine.weather(winter, registry: registry,
                                            tick: year * ticksPerYear + ticksPerYear * 3 / 4)
        }
        #expect((winter.colony?.placements[0].condition ?? 1)
                < (summer.colony?.placements[0].condition ?? 1))
    }

    @Test("Scaffolding does not weather — there is no roof on it yet")
    func sitesDoNotWear() {
        var s = town([("hut", 1.0)])
        s.colony?.placements[0].underConstruction = true
        s = BuildingEngine.weather(s, registry: registry, tick: 100)
        #expect(s.colony?.placements[0].condition == 1)
    }

    // MARK: - Damage

    @Test("A raid breaks the town, and goes for the outskirts first")
    func aRaidComesFromOutside() {
        // One building in the middle, one out at the edge.
        var s = town([("hut", 1.0), ("hut", 1.0)])
        s.colony?.placements[0].coord = TileCoord(9, 9)      // the middle
        s.colony?.placements[1].coord = TileCoord(0, 0)      // the edge
        var rng = SeededRNG(seed: 5)
        let hit = BuildingEngine.damage(s, kind: .raid, severity: 0.5, rng: &rng)
        #expect(hit.hit >= 1)
        let outer = hit.settlement.colony?.placements[1].condition ?? 1
        let inner = hit.settlement.colony?.placements[0].condition ?? 1
        #expect(outer < inner, "raiders reached the middle before the edge")
    }

    @Test("A storm reaches more of the town than a beast does")
    func spreadDiffersByKind() {
        let s = town(Array(repeating: ("hut", 1.0), count: 12))
        var a = SeededRNG(seed: 11)
        var b = SeededRNG(seed: 11)
        let storm = BuildingEngine.damage(s, kind: .storm, severity: 1, rng: &a)
        let beast = BuildingEngine.damage(s, kind: .beast, severity: 1, rng: &b)
        #expect(storm.hit > beast.hit)
    }

    @Test("Enough harm leaves a ruin, and a ruin works for nobody")
    func aRuinStopsWorking() {
        var s = town([("workshop", 0.3)])
        s.colony?.placements[0].assignedPawnIDs = [id(700)]
        var rng = SeededRNG(seed: 3)
        let after = BuildingEngine.damage(s, kind: .fire, severity: 1, rng: &rng).settlement
        let placement = after.colony?.placements[0]
        #expect((placement?.condition ?? 1) < BuildingEngine.derelictBelow)
        #expect(BuildingEngine.isWorking(placement!) == false)
        #expect(placement?.assignedPawnIDs.isEmpty == true, "nobody is at a bench in a wreck")
        #expect(BuildingEngine.output(placement!.condition) == 0)
    }

    @Test("A ruined house sleeps nobody, and turns its household out")
    func aRuinedHouseIsNoHome() {
        var s = town([("hut", 1.0)])
        s.pawns = [Pawn(id: id(800), name: "Sleeper", homeID: id(0))]
        var rng = SeededRNG(seed: 7)
        let after = BuildingEngine.damage(s, kind: .quake, severity: 1, rng: &rng).settlement
        guard let placement = after.colony?.placements.first else { return }
        if placement.condition < BuildingEngine.derelictBelow {
            #expect(HouseholdEngine.beds(placement, registry: registry) == 0)
            #expect(after.pawns[0].homeID == nil)
        }
    }

    @Test("Damage is the same for the same world")
    func damageIsDeterministic() {
        let s = town(Array(repeating: ("hut", 1.0), count: 8))
        var a = SeededRNG(seed: 99)
        var b = SeededRNG(seed: 99)
        let one = BuildingEngine.damage(s, kind: .storm, severity: 0.7, rng: &a)
        let two = BuildingEngine.damage(s, kind: .storm, severity: 0.7, rng: &b)
        #expect(one.settlement.colony?.placements.map(\.condition)
                == two.settlement.colony?.placements.map(\.condition))
    }

    // MARK: - Repair

    @Test("Masons put a battered building back, and it costs the stores")
    func repairWorksAndCosts() {
        var s = town([("workshop", 0.4)], masons: 3)
        let before = s.storage[.materials]
        for _ in 0..<20 { s = BuildingEngine.repair(s, registry: registry) }
        #expect((s.colony?.placements[0].condition ?? 0) > 0.4)
        #expect(s.storage[.materials] < before, "repair should not be free")
    }

    @Test("A colony with empty stores watches its town go to pieces")
    func repairNeedsMaterials() {
        var s = town([("workshop", 0.4)], masons: 3, materials: 0)
        for _ in 0..<20 { s = BuildingEngine.repair(s, registry: registry) }
        #expect(s.colony?.placements[0].condition == 0.4)
    }

    @Test("The worst building is seen to first")
    func theWorstIsMended() {
        var s = town([("hut", 0.8), ("hut", 0.3)], masons: 1)
        s = BuildingEngine.repair(s, registry: registry)
        let mended = s.colony?.placements[1].condition ?? 0
        #expect(mended > 0.3)
        #expect(s.colony?.placements[0].condition == 0.8)
    }

    @Test("A sound town needs no masons and spends nothing")
    func nothingToDoCostsNothing() {
        var s = town([("hut", 1.0), ("workshop", 1.0)], masons: 4)
        let before = s.storage[.materials]
        s = BuildingEngine.repair(s, registry: registry)
        #expect(s.storage[.materials] == before)
    }

    @Test("A save written before wear finds everything sound")
    func oldSavesAreSound() throws {
        let json = """
        {"id":"00000000-0000-0000-B111-000000000042","definitionID":"hut",
         "coord":{"x":1,"y":1},"assignedPawnIDs":[]}
        """
        let placement = try JSONDecoder().decode(BuildingPlacement.self, from: Data(json.utf8))
        #expect(placement.condition == 1)
        #expect(BuildingEngine.isWorking(placement))
    }
}
