import Testing
import Foundation
@testable import EndlessFrontierCore

/// **The middle of a town is a place, not spare ground.**
///
/// Keks, watching a colony fill up: *"vadí mi že je náves zastavěna když se tam
/// hromadí lidé a je tam budova nebo položené věci, chtělo by to sklady na
/// materiál, itemy atd."* Two faults with one root — the heart of the colony was
/// treated as an address rather than as ground. `ColonyBuilder` measured from it
/// and built on it; `HaulEngine` had nowhere else to put a load and piled goods
/// on it.
@Suite("The green, and where goods go")
struct GreenAndStoresTests {

    private func registry() -> GameDataRegistry {
        GameDataRegistry(
            buildings: [
                BuildingDefinition(id: "hut", era: .earlySettlement, name: "Hut",
                                   cost: [.materials: 10], housing: 20),
                BuildingDefinition(id: "granary", era: .earlySettlement, name: "Granary",
                                   cost: [.materials: 20], storage: [.food: 250]),
                BuildingDefinition(id: "warehouse", era: .earlySettlement, name: "Warehouse",
                                   cost: [.materials: 30], storage: [.materials: 350]),
            ],
            techs: [], eras: [], biomes: [], events: [], config: .default)
    }

    /// Raises a finished building wherever the colony would actually put one.
    private func raise(_ settlement: Settlement, _ id: String) -> Settlement {
        var s = ColonyBuilder.placeSiteAtFirstFit(
            settlement, definitionID: id, registry: registry()).settlement
        // Finished, not scaffolding: a store under construction holds nothing.
        for i in s.colony?.placements.indices ?? (0..<0).indices where true {
            s.colony?.placements[i].underConstruction = false
        }
        return s
    }

    private func town() -> Settlement {
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-6666-000000000001")!,
                           name: "Greenford", regionID: UUID())
        s.colony = ColonyMap(width: 24, height: 24)
        return s
    }

    // MARK: - The green

    @Test("Nothing is ever built on the green")
    func theGreenIsNotBuildingLand() {
        var s = town()
        // Raise more buildings than one district holds, so the colony really
        // does try to fill its heart first.
        for i in 0..<20 {
            s = raise(s, i % 2 == 0 ? "hut" : "granary")
        }
        guard let colony = s.colony else { Issue.record("no colony"); return }
        #expect(colony.placements.count >= 12, "the town did get built")
        for placement in colony.placements {
            for dy in 0..<max(1, placement.height) {
                for dx in 0..<max(1, placement.width) {
                    let tile = TileCoord(placement.coord.x + dx, placement.coord.y + dy)
                    #expect(!SettlementGeometry.isGreen(tile, in: colony),
                            "\(placement.definitionID) is standing on the green")
                }
            }
        }
    }

    @Test("The green is a square in the middle, and small")
    func theGreenIsWhereItShouldBe() {
        let colony = ColonyMap(width: 24, height: 24)
        #expect(SettlementGeometry.isGreen(TileCoord(12, 12), in: colony))
        #expect(SettlementGeometry.isGreen(TileCoord(13, 13), in: colony))
        #expect(!SettlementGeometry.isGreen(TileCoord(9, 12), in: colony))
        #expect(!SettlementGeometry.isGreen(TileCoord(0, 0), in: colony))
        var green = 0
        for y in 0..<24 where true {
            for x in 0..<24 where SettlementGeometry.isGreen(TileCoord(x, y), in: colony) {
                green += 1
            }
        }
        #expect(green == SettlementGeometry.greenTiles * SettlementGeometry.greenTiles)
    }

    // MARK: - Where goods go

    @Test("Goods with nowhere to go land in the yard, not on the green")
    func theFallbackIsAYardNotTheSquare() {
        let where_ = HaulEngine.storePosition(town(), for: "wood", registry: registry())
        #expect(where_ != SettlementGeometry.heart, "the square is where people stand")
        #expect(where_ == SettlementGeometry.goodsYard)
    }

    @Test("Grain goes to the granary and timber goes to the warehouse")
    func aStoreIsPickedByWhatItHolds() {
        var s = town()
        s = raise(s, "granary")
        s = raise(s, "warehouse")
        guard let colony = s.colony,
              let granary = colony.placements.first(where: { $0.definitionID == "granary" }),
              let warehouse = colony.placements.first(where: { $0.definitionID == "warehouse" })
        else { Issue.record("the stores were not raised"); return }
        let atGranary = SettlementGeometry.canvasPoint(for: granary, in: colony)
        let atWarehouse = SettlementGeometry.canvasPoint(for: warehouse, in: colony)

        let food = HaulEngine.storePosition(s, for: "grain", registry: registry())
        let timber = HaulEngine.storePosition(s, for: "wood", registry: registry())
        #expect(food == atGranary, "the harvest goes where the harvest is kept")
        #expect(timber == atWarehouse, "and the timber where the timber is")
        #expect(food != timber, "one store for everything is what this replaced")
    }

    /// The old version took the **first** store in placement order, so a colony
    /// with two quarters carried everything to whichever was raised first.
    @Test("A load goes to the nearest store of its kind, not the oldest")
    func theNearestStoreWins() {
        var s = town()
        s = raise(s, "warehouse")
        s = raise(s, "warehouse")
        guard let colony = s.colony, colony.placements.count == 2 else {
            Issue.record("two warehouses were not raised"); return
        }
        let places = colony.placements.map { SettlementGeometry.canvasPoint(for: $0, in: colony) }
        for from in places {
            let chosen = HaulEngine.storePosition(s, for: "wood", registry: registry(), from: from)
            let nearest = places.min { SiegeField.distance($0, from) < SiegeField.distance($1, from) }
            #expect(chosen == nearest, "they walked past the near one")
        }
    }

    @Test("A colony with only the wrong store still puts the load down in it")
    func thewrongStoreBeatsTheSquare() {
        var s = town()
        s = raise(s, "granary")
        let timber = HaulEngine.storePosition(s, for: "wood", registry: registry())
        #expect(timber != SettlementGeometry.goodsYard,
                "a granary will hold sacks of anything at a pinch")
    }
}
