import Foundation
import Testing
@testable import EndlessFrontierCore

/// Construction over time: paying for a building opens a *site*, builders push
/// it forward, and the roof going on is when the economy first counts it.
@Suite("Construction engine")
struct ConstructionEngineTests {
    private let registry = Fixtures.registry()

    private func settlement(pawns: [Pawn]) -> Settlement {
        // Fixed id: a random one would (correctly) fail the determinism test.
        Settlement(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!,
                   name: "Test", kind: .capital, pawns: pawns,
                   storage: [.materials: 500], storageCapacity: 9999)
    }

    @Test("Work required scales with cost between the floor and the cap")
    func workRequiredBounds() {
        let cheap = BuildingDefinition(id: "shed", era: .earlySettlement, name: "Shed", cost: [.materials: 1])
        let dear = BuildingDefinition(id: "wonder", era: .earlySettlement, name: "Wonder", cost: [.materials: 4000])
        #expect(ConstructionEngine.workRequired(for: cheap) == ConstructionEngine.minimumWork)
        #expect(ConstructionEngine.workRequired(for: dear) == ConstructionEngine.maximumWork)
    }

    @Test("A queued project completes over ticks and lands in the ledger")
    func projectCompletes() {
        let base = settlement(pawns: Fixtures.pawns(4, work: .building))
        var s = ConstructionEngine.enqueue(base, definitionID: "farm",
                                           placementID: nil, registry: registry, tick: 0)
        #expect(s.constructions.count == 1)
        #expect(s.buildings.isEmpty)

        var ticks = 0
        while !s.constructions.isEmpty, ticks < 100 {
            s = ConstructionEngine.advanceOneTick(s, registry: registry, tick: ticks)
            ticks += 1
        }
        #expect(s.constructions.isEmpty)
        #expect(s.buildings.first { $0.definitionID == "farm" }?.count == 1)
        // The journal recorded both breaking ground and finishing.
        #expect(s.journal.entries.contains { $0.kind == .construction })
        #expect(s.journal.entries.count >= 2)
    }

    @Test("More builders raise a building faster")
    func buildersAccelerate() {
        func ticksToFinish(builderCount: Int) -> Int {
            let hands = Fixtures.pawns(builderCount, work: .building)
            var s = ConstructionEngine.enqueue(settlement(pawns: hands), definitionID: "library",
                                               placementID: nil, registry: registry, tick: 0)
            var ticks = 0
            while !s.constructions.isEmpty, ticks < 500 {
                s = ConstructionEngine.advanceOneTick(s, registry: registry, tick: ticks)
                ticks += 1
            }
            return ticks
        }
        #expect(ticksToFinish(builderCount: 4) < ticksToFinish(builderCount: 1))
    }

    @Test("An unstaffed site drafts hands from the gathering trades")
    func siteDraftsWorkers() {
        let farmers = Fixtures.pawns(6, work: .farming)
        var s = ConstructionEngine.enqueue(settlement(pawns: farmers), definitionID: "farm",
                                           placementID: nil, registry: registry, tick: 0)
        s = ConstructionEngine.advanceOneTick(s, registry: registry, tick: 0)
        #expect(s.pawns.contains { $0.assignedWork == .building })
    }

    @Test("Finishing the last site releases the crew back to the labour pool")
    func crewReleasedWhenDone() {
        var s = ConstructionEngine.enqueue(settlement(pawns: Fixtures.pawns(6, work: .building)),
                                           definitionID: "farm",
                                           placementID: nil, registry: registry, tick: 0)
        var ticks = 0
        while !s.constructions.isEmpty, ticks < 100 {
            s = ConstructionEngine.advanceOneTick(s, registry: registry, tick: ticks)
            ticks += 1
        }
        #expect(s.pawns.allSatisfy { $0.assignedWork != .building })
    }

    @Test("A grid site is unveiled on completion and only then counted")
    func gridSiteUnveiled() {
        let base = ColonyBuilder.placeSite(settlement(pawns: Fixtures.pawns(4, work: .building)),
                                           definitionID: "farm", at: TileCoord(2, 2), registry: registry)
        let placementID = base.colony?.placement(at: TileCoord(2, 2))?.id
        #expect(placementID != nil)
        #expect(base.colony?.placements.first?.underConstruction == true)
        #expect(base.buildings.isEmpty)

        var s = ConstructionEngine.enqueue(base, definitionID: "farm",
                                           placementID: placementID, registry: registry, tick: 0)
        var ticks = 0
        while !s.constructions.isEmpty, ticks < 100 {
            s = ConstructionEngine.advanceOneTick(s, registry: registry, tick: ticks)
            ticks += 1
        }
        #expect(s.colony?.placements.first?.underConstruction == false)
        #expect(s.buildings.first { $0.definitionID == "farm" }?.count == 1)
    }

    @Test("A scaffolded site grants no adjacency synergies until finished")
    func siteGrantsNoSynergies() {
        let well = BuildingDefinition(id: "well", era: .earlySettlement, name: "Well", cost: [.materials: 5])
        let farm = BuildingDefinition(
            id: "farm", era: .earlySettlement, name: "Farm", cost: [.materials: 20],
            production: [.food: 10],
            adjacency: [AdjacencyRule(neighbor: "well", resource: .food, bonus: 2)])
        let reg = Fixtures.registry(buildings: [well, farm])

        var s = ColonyBuilder.place(settlement(pawns: []), definitionID: "farm",
                                    at: TileCoord(0, 0), registry: reg)
        s = ColonyBuilder.placeSite(s, definitionID: "well", at: TileCoord(1, 0), registry: reg)
        #expect(ColonyBonus.adjacencyProduction(s, registry: reg)[.food] == 0)

        // Once the well is finished the synergy switches on.
        if var map = s.colony, let i = map.placements.firstIndex(where: { $0.definitionID == "well" }) {
            map.placements[i].underConstruction = false
            s.colony = map
        }
        #expect(ColonyBonus.adjacencyProduction(s, registry: reg)[.food] == 2)
    }

    @Test("Demolishing a site cancels its project without touching the ledger")
    func demolishSiteCancelsProject() {
        let cap = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-87cb5c040202")!, name: "C", kind: .capital, storage: [.materials: 100], storageCapacity: 9999)
        let world = WorldState(settlements: [cap])
        let placed = GameEngine.placeBuilding(world, settlementID: cap.id,
                                              buildingID: "farm", at: TileCoord(0, 0), registry: registry)
        #expect(placed.settlements[0].constructions.count == 1)

        let razed = GameEngine.demolish(placed, settlementID: cap.id, at: TileCoord(0, 0))
        #expect(razed.settlements[0].constructions.isEmpty)
        #expect(razed.settlements[0].colony?.placements.isEmpty == true)
        #expect(razed.settlements[0].buildings.isEmpty)
    }

    @Test("Construction is deterministic across identical runs")
    func deterministic() {
        func run() -> Settlement {
            var s = ConstructionEngine.enqueue(settlement(pawns: Fixtures.pawns(5, work: .farming)),
                                               definitionID: "library",
                                               placementID: nil, registry: registry, tick: 3)
            for tick in 0..<60 {
                s = ConstructionEngine.advanceOneTick(s, registry: registry, tick: tick)
            }
            return s
        }
        #expect(run() == run())
    }

    @Test("The journal keeps ids monotonic and trims past capacity")
    func journalRing() {
        var log = ColonyLog()
        for i in 0..<(ColonyLog.capacity + 25) {
            log.append(tick: i, kind: .social, text: LocalizedText("m\(i)"))
        }
        #expect(log.entries.count == ColonyLog.capacity)
        #expect(log.entries.first?.id == 25)
        #expect(log.nextID == ColonyLog.capacity + 25)
        #expect(log.entries(after: ColonyLog.capacity + 20).count == 4)
    }

    @Test("A settlement JSON without construction fields still decodes")
    func decodesLegacySettlement() throws {
        let legacy = Settlement(id: UUID(uuidString: "00000000-0000-0000-0F00-d2f36cc36640")!, name: "Old", kind: .capital, pawns: Fixtures.pawns(2))
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(legacy)) as! [String: Any]
        json.removeValue(forKey: "constructions")
        json.removeValue(forKey: "constructionSequence")
        json.removeValue(forKey: "journal")
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(Settlement.self, from: data)
        #expect(decoded.constructions.isEmpty)
        #expect(decoded.journal.entries.isEmpty)
    }
}
