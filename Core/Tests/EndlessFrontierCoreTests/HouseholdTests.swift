import Testing
import Foundation
@testable import EndlessFrontierCore

/// A colonist has an address now. These pin the parts that would fail quietly:
/// a home that is reassigned every ten ticks, a house that takes everyone, or
/// a colony that sleeps rough without anyone noticing.
@Suite("A house is a household")
struct HouseholdTests {

    private func registry(housing: Double = 30, footprint: TileSize = TileSize(width: 1, height: 1))
    -> GameDataRegistry {
        GameDataRegistry(
            buildings: [
                BuildingDefinition(id: "hut", era: .earlySettlement, name: "Hut",
                                   cost: [.materials: 10], housing: housing,
                                   footprint: footprint),
                BuildingDefinition(id: "shed", era: .earlySettlement, name: "Shed",
                                   cost: [.materials: 10], workers: 2)
            ],
            techs: [], eras: [], biomes: [], events: [], config: .default)
    }

    private func town(huts: Int, souls: Int) -> Settlement {
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-BEDD-000000000001")!,
                           name: "Bedford", regionID: UUID())
        s.pawns = (0..<souls).map { i in
            Pawn(id: UUID(uuidString: String(format: "00000000-0000-0000-BEDD-1000%08d", i))!,
                 name: "P\(i)")
        }
        var colony = ColonyMap(width: 18, height: 18)
        colony.placements = (0..<huts).map { i in
            BuildingPlacement(
                id: UUID(uuidString: String(format: "00000000-0000-0000-BEDD-2000%08d", i))!,
                definitionID: "hut", coord: TileCoord(i, 0), width: 1, height: 1)
        }
        s.colony = colony
        return s
    }

    @Test("A one-tile hut is a household, not a village in a shed")
    func aHutHoldsAFamily() {
        let reg = registry(housing: 30)
        let placement = BuildingPlacement(id: UUID(), definitionID: "hut",
                                          coord: TileCoord(0, 0), width: 1, height: 1)
        #expect(HouseholdEngine.beds(placement, registry: reg)
                == HouseholdEngine.sleepersPerTile)
    }

    @Test("A bigger dwelling sleeps more")
    func biggerHousesHoldMore() {
        let reg = registry(housing: 70, footprint: TileSize(width: 2, height: 2))
        let small = BuildingPlacement(id: UUID(), definitionID: "hut",
                                      coord: TileCoord(0, 0), width: 1, height: 1)
        let big = BuildingPlacement(id: UUID(), definitionID: "hut",
                                    coord: TileCoord(0, 0), width: 2, height: 2)
        #expect(HouseholdEngine.beds(big, registry: reg)
                > HouseholdEngine.beds(small, registry: reg))
    }

    /// The ledger *is* the beds now. This used to assert the opposite — that a
    /// definition claiming two could stand on nine tiles and still sleep two —
    /// which was the two-numbers-for-one-thing that let a 1×1 hut be credited
    /// with thirty people it had nowhere to put.
    @Test("The ledger and the beds are the same number")
    func theLedgerIsTheBeds() throws {
        let reg = registry(housing: 1, footprint: TileSize(width: 2, height: 2))
        let def = try #require(reg.building("hut"))
        let placement = BuildingPlacement(id: UUID(), definitionID: "hut",
                                          coord: TileCoord(0, 0), width: 2, height: 2)
        #expect(HouseholdEngine.beds(placement, registry: reg) == def.sleepers)
        #expect(def.sleepers == 2 * 2 * BuildingDefinition.sleepersPerTile)
    }

    /// …and a placement smaller than its definition (an old save from before a
    /// resize) sleeps what it actually covers, not what the definition wishes.
    @Test("A dwelling sleeps the ground it actually stands on")
    func groundIsTheCeiling() {
        let reg = registry(housing: 1, footprint: TileSize(width: 3, height: 3))
        let cramped = BuildingPlacement(id: UUID(), definitionID: "hut",
                                        coord: TileCoord(0, 0), width: 1, height: 1)
        #expect(HouseholdEngine.beds(cramped, registry: reg)
                == BuildingDefinition.sleepersPerTile)
    }

    @Test("Everyone who can have a home gets one, and no house is overfilled")
    func homesAreHandedOut() {
        let reg = registry()
        // Three one-tile huts, sized off the constant rather than restating it:
        // a test that hardcodes "four beds apiece" fails the day a household
        // changes size, and says nothing about what actually broke.
        let souls = 3 * BuildingDefinition.sleepersPerTile
        let housed = HouseholdEngine.assignHomes(
            town(huts: 3, souls: souls), registry: reg)
        #expect(HouseholdEngine.homeless(housed) == 0, "three huts hold three huts' worth")
        var perHome: [UUID: Int] = [:]
        for pawn in housed.pawns {
            guard let home = pawn.homeID else { continue }
            perHome[home, default: 0] += 1
        }
        for (_, count) in perHome {
            #expect(count <= HouseholdEngine.sleepersPerTile)
        }
    }

    @Test("A colony with too few roofs leaves people sleeping rough")
    func theRooflessAreCounted() {
        let reg = registry()
        let housed = HouseholdEngine.assignHomes(town(huts: 1, souls: 10), registry: reg)
        #expect(HouseholdEngine.homeless(housed) == 10 - HouseholdEngine.sleepersPerTile)
        #expect(HouseholdEngine.homelessFraction(housed) > 0.5)
    }

    @Test("A home is kept, not re-rolled every pass")
    func homesAreStable() {
        let reg = registry()
        let once = HouseholdEngine.assignHomes(town(huts: 4, souls: 10), registry: reg)
        let twice = HouseholdEngine.assignHomes(once, registry: reg)
        #expect(once.pawns.map(\.homeID) == twice.pawns.map(\.homeID))
    }

    @Test("A house pulled down turns its household out, and they find another")
    func aLostHouseRehomesItsPeople() {
        let reg = registry()
        // Sized so that losing one of the three huts still leaves room for
        // everybody — the test is about rehoming, not about overcrowding.
        var housed = HouseholdEngine.assignHomes(
            town(huts: 3, souls: 2 * BuildingDefinition.sleepersPerTile), registry: reg)
        let lost = housed.pawns[0].homeID
        #expect(lost != nil)
        housed.colony?.placements.removeAll { $0.id == lost }
        let after = HouseholdEngine.assignHomes(housed, registry: reg)
        #expect(after.pawns.allSatisfy { $0.homeID != lost })
        // Two huts left, and only two huts' worth of people: still indoors.
        #expect(HouseholdEngine.homeless(after) == 0)
    }

    @Test("A house still going up houses nobody")
    func scaffoldingIsNotAHome() {
        let reg = registry()
        var s = town(huts: 2, souls: 4)
        for i in s.colony!.placements.indices {
            s.colony?.placements[i].underConstruction = true
        }
        #expect(HouseholdEngine.homeless(HouseholdEngine.assignHomes(s, registry: reg)) == 4)
    }

    @Test("Sleeping rough costs rest and mood; a bed does not")
    func aBedIsWorthHaving() {
        let reg = registry()
        func run(housed: Bool) -> Pawn {
            var s = Settlement(id: UUID(), name: "Cold", regionID: UUID())
            s.pawns = [Pawn(id: UUID(uuidString: "00000000-0000-0000-BEDD-3000000000FF")!,
                            name: "Sleeper",
                            needs: PawnNeeds(hunger: 90, rest: 50, recreation: 70),
                            homeID: housed ? UUID() : nil)]
            s.storage[.food] = 500
            for tick in 0..<30 {
                s = PawnEngine.advanceOneTick(s, registry: reg, tick: tick)
            }
            return s.pawns[0]
        }
        let indoors = run(housed: true)
        let outdoors = run(housed: false)
        #expect(indoors.needs.rest > outdoors.needs.rest)
        #expect(indoors.mood > outdoors.mood)
    }

    @Test("A colonist from an older save has no address and is given one")
    func oldSavesAreRehomed() throws {
        let json = """
        {"id":"00000000-0000-0000-BEDD-40000000000A","name":"Old","trait":"none",
         "skills":[],"skillXP":[],"needs":{"hunger":80,"rest":80,"recreation":70},
         "mood":70,"assignedWork":"idle","health":100,"isBroken":false}
        """
        let pawn = try JSONDecoder().decode(Pawn.self, from: Data(json.utf8))
        #expect(pawn.homeID == nil)

        let reg = registry()
        var s = town(huts: 1, souls: 0)
        s.pawns = [pawn]
        #expect(HouseholdEngine.assignHomes(s, registry: reg).pawns[0].homeID != nil)
    }
}
