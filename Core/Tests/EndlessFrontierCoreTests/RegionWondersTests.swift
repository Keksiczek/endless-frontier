import Foundation
import Testing
@testable import EndlessFrontierCore

/// The map's new wonders: sacred valleys and dead cities — rolled by the
/// generator, interacted with as sites, and flavouring their local chunk.
@Suite("Region wonders")
struct RegionWondersTests {
    static let book = try! GameDataRegistry.bundled()

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    @Test("The generator can roll both wonders")
    func wondersAreRollable() {
        let config = MapGenConfig.default
        var seen: Set<RegionKind> = []
        var rng = SeededRNG(seed: 1234)
        for _ in 0..<4000 {
            seen.insert(MapGenerator.rollKind(config: config, ring: 3, rng: &rng))
        }
        #expect(seen.contains(.sanctuary))
        #expect(seen.contains(.lostCity))
        #expect(seen.contains(.wilderness))   // still the common case
    }

    @Test("A pilgrimage blesses the colony and clears the site")
    func pilgrimage() throws {
        let reg = try registry()
        var world = GameWorldFactory.newGame(registry: reg, seed: 21)
        for i in world.settlements[0].pawns.indices {
            world.settlements[0].pawns[i].needs.recreation = 40
            world.settlements[0].pawns[i].health = 60
        }
        world.regions.append(Region(
            id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!,
            name: "Tichá dolina", coord: HexCoord(4, 4), kind: .sanctuary,
            biomeID: "plains", explorationState: .fullyExplored))

        guard let (after, outcome) = SiteEngine.interact(
            world, regionID: world.regions.last!.id, registry: Self.book) else {
            Issue.record("sanctuary site refused interaction")
            return
        }
        #expect(outcome.kind == .sanctuary)
        #expect(after.regions.last?.siteCleared == true)
        #expect(after.settlements[0].pawns[0].needs.recreation > 40)
        #expect(after.settlements[0].pawns[0].health > 60)
        #expect(after.settlements[0].journal.entries.contains { $0.kind == .discovery })
    }

    @Test("Salvaging a lost city pays materials and knowledge")
    func lostCitySalvage() throws {
        let reg = try registry()
        var world = GameWorldFactory.newGame(registry: reg, seed: 22)
        world.regions.append(Region(
            id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000002")!,
            name: "Kostěné město", coord: HexCoord(5, 2), kind: .lostCity,
            biomeID: "plains", hazardLevel: 4, explorationState: .fullyExplored))
        let before = world.settlements[0].storage

        guard let (after, outcome) = SiteEngine.interact(
            world, regionID: world.regions.last!.id, registry: Self.book) else {
            Issue.record("lost city refused interaction")
            return
        }
        #expect(outcome.kind == .lostCity)
        #expect(after.settlements[0].storage[.materials] > before[.materials])
        #expect(after.settlements[0].storage[.knowledge] > before[.knowledge])
        #expect(outcome.died == false)   // the rubble wounds, never kills
    }

    @Test("A region's character flavours its local chunk — deterministically")
    func chunkFlavour() {
        let id = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000003")!
        let plain = LocalMapGenerator.generate(mapSeed: 9, regionID: id, biome: nil, registry: Self.book)
        let city = LocalMapGenerator.generate(mapSeed: 9, regionID: id, biome: nil, flavor: .lostCity, registry: Self.book)
        let holy = LocalMapGenerator.generate(mapSeed: 9, regionID: id, biome: nil, flavor: .sanctuary, registry: Self.book)

        // A dead city stands in fallen pillars and hides more to find.
        let pillars = city.scenery.filter { $0.kind == .ruinPillar }.count
        #expect(pillars > plain.scenery.filter { $0.kind == .ruinPillar }.count)
        #expect(city.pois.count > plain.pois.count)
        // A sanctuary holds a second shrine.
        #expect(holy.pois.filter { $0.kind == .shrine }.count == 2)
        // Same seed, same flavour → same chunk. Surveying then settling agree.
        let again = LocalMapGenerator.generate(mapSeed: 9, regionID: id, biome: nil, flavor: .lostCity, registry: Self.book)
        #expect(again == city)
    }

    @Test("A lost city takes three runs to strip, each poorer than the last")
    func lostCityDepletes() throws {
        let reg = try registry()
        var world = GameWorldFactory.newGame(registry: reg, seed: 23)
        world.regions.append(Region(
            id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000004")!,
            name: "Popelné město", coord: HexCoord(6, 1), kind: .lostCity,
            biomeID: "plains", hazardLevel: 2, explorationState: .fullyExplored))
        let cityID = world.regions.last!.id

        var hauls: [Double] = []
        for run in 0..<SiteEngine.lostCityVisits {
            let before = world.settlements[0].storage[.materials]
            guard let (after, _) = SiteEngine.interact(world, regionID: cityID, registry: Self.book) else {
                Issue.record("run \(run + 1) refused — city closed too early")
                return
            }
            hauls.append(after.settlements[0].storage[.materials] - before)
            world = after
            let cleared = world.regions.first { $0.id == cityID }?.siteCleared
            #expect(cleared == (run == SiteEngine.lostCityVisits - 1))
        }
        // Diminishing returns, and afterwards the site refuses a fourth run.
        #expect(hauls[0] > hauls[1] && hauls[1] > hauls[2])
        #expect(SiteEngine.interact(world, regionID: cityID, registry: Self.book) == nil)
    }

    @Test("Old map-gen JSON without wonder chances still decodes")
    func configDecodes() throws {
        let json = #"{"mapRadius": 2, "ruinsChance": 0.1}"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(MapGenConfig.self, from: json)
        #expect(config.sanctuaryChance == MapGenConfig.default.sanctuaryChance)
        #expect(config.lostCityChance == MapGenConfig.default.lostCityChance)
    }
}
