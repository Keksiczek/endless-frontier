import Testing
import Foundation
@testable import EndlessFrontierCore

/// A town of sixty was one dense knot: everything went as near the middle as it
/// would go, so there were no quarters to tell apart. These pin that the colony
/// opens districts as it grows and still always finds somewhere to build.
@Suite("A town grows into quarters")
struct DistrictTests {

    private var registry: GameDataRegistry {
        GameDataRegistry(
            buildings: [
                BuildingDefinition(id: "hut", era: .earlySettlement, name: "Hut",
                                   cost: [.materials: 5], housing: 8)
            ],
            techs: [], eras: [], biomes: [], events: [], config: .default)
    }

    private func town(_ count: Int) -> Settlement {
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-D157-000000000001")!,
                           name: "Quarters", regionID: UUID())
        s.storage[ResourceType.materials] = 10_000
        s = ColonyBuilder.ensureMap(s)
        for _ in 0..<count {
            s = ColonyBuilder.placeSiteAtFirstFit(s, definitionID: "hut",
                                                  registry: registry).settlement
        }
        return s
    }

    @Test("A small colony keeps to one square")
    func oneDistrictAtFirst() {
        let map = ColonyMap(width: 18, height: 18)
        #expect(ColonyBuilder.districtCentres(in: map, count: 1).count == 1)
        let heart = ColonyBuilder.districtCentres(in: map, count: 1)[0]
        #expect(heart.x == 9 && heart.y == 9)
    }

    @Test("Quarters open as the town grows, and stay on the grid")
    func districtsOpenWithGrowth() {
        let map = ColonyMap(width: 18, height: 18)
        for count in 1...5 {
            let centres = ColonyBuilder.districtCentres(in: map, count: count)
            #expect(centres.count == count)
            for centre in centres {
                #expect(centre.x >= 0 && centre.x < map.width)
                #expect(centre.y >= 0 && centre.y < map.height)
            }
        }
    }

    @Test("A grown town is not one knot around the middle")
    func aTownSpreads() {
        let packed = town(6)
        let grown = town(26)

        func spread(_ s: Settlement) -> Double {
            guard let colony = s.colony, !colony.placements.isEmpty else { return 0 }
            let heart = TileCoord(colony.width / 2, colony.height / 2)
            return colony.placements.reduce(0.0) {
                $0 + ColonyBuilder.squaredDistance($1.coord, heart).squareRoot()
            } / Double(colony.placements.count)
        }
        #expect(spread(grown) > spread(packed),
                "a town of twenty-six should stand further out than a town of six")
    }

    @Test("Every building still gets somewhere to stand")
    func nothingFailsToBuild() {
        let grown = town(30)
        #expect(grown.colony?.placements.count == 30)
        // …and none of them overlap.
        var seen = Set<String>()
        for placement in grown.colony?.placements ?? [] {
            for tile in placement.footprint {
                let key = "\(tile.x),\(tile.y)"
                #expect(!seen.contains(key), "two buildings on \(key)")
                seen.insert(key)
            }
        }
    }

    @Test("The same colony always grows the same shape")
    func layoutIsDeterministic() {
        #expect(town(20).colony?.placements.map(\.coord)
                == town(20).colony?.placements.map(\.coord))
    }

    /// A colony out of room **takes in more of the valley** (§11.21). This used
    /// to assert the opposite — that a full grid gives up — and giving up was
    /// the ceiling the whole game sat under: `FarmEngine.reconcile` makes plots
    /// out of placements, so a farm that could not be sited grew nothing, and a
    /// town that had filled its 24×24 quietly stopped being able to feed itself.
    @Test("A colony out of room takes in more of the valley")
    func aFullGridGrows() {
        var s = Settlement(id: UUID(), name: "Tight", regionID: UUID())
        s.storage[ResourceType.materials] = 10_000
        s = ColonyBuilder.ensureMap(s, width: 2, height: 2)
        for _ in 0..<8 {
            s = ColonyBuilder.placeSiteAtFirstFit(s, definitionID: "hut",
                                                  registry: registry).settlement
        }
        #expect(s.colony?.placements.count == 8,
                "eight huts asked for and \(s.colony?.placements.count ?? 0) stood up")
        #expect((s.colony?.width ?? 0) > 2, "the ground never widened")
        #expect((s.colony?.width ?? 0) <= ColonyBuilder.maxSide)
    }

    /// …and the valley is not endless. The fuse still has to be there, or a
    /// colony that cannot place a building loops for ever trying.
    @Test("A colony that has taken the whole valley grows no further")
    func growthStopsAtTheEdge() {
        var s = Settlement(id: UUID(), name: "Wide", regionID: UUID())
        s = ColonyBuilder.ensureMap(s, width: ColonyBuilder.maxSide,
                                    height: ColonyBuilder.maxSide)
        let grown = ColonyBuilder.grownOutward(s)
        #expect(grown.colony?.width == ColonyBuilder.maxSide)
        #expect(grown.colony?.height == ColonyBuilder.maxSide)
    }
}
