import Testing
import Foundation
@testable import EndlessFrontierCore

/// Whether the world map reads as **country** rather than as confetti.
///
/// Keks, looking at it: *"tiles na mapě nevypadají vůbec jako mapa"*, and
/// *"mapa musí vypadat dle klimatu — poušť, hory atd"*. The cause was not the
/// drawing: `MapGenerator.rollBiome` rolled every hex **independently** out of
/// `biomeWeights`, so a desert sat beside a tundra beside a coast and no
/// feature was ever larger than one hex. A map made of independent samples
/// cannot look like a map, however it is painted.
///
/// Biomes are chosen from three smooth fields now — how high, how wet, how warm
/// — so what these pin is that the fields actually *correlate* neighbours
/// without flattening the world into one country.
@Suite("The world map is geography")
struct WorldGeographyTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private func disc(radius: Int) -> [HexCoord] { HexCoord.disc(radius: radius) }

    private func biomes(seed: UInt64, radius: Int = 7,
                        registry: GameDataRegistry) -> [HexCoord: String] {
        var out: [HexCoord: String] = [:]
        for coord in disc(radius: radius) where coord != .origin {
            out[coord] = MapGenerator.region(at: coord, mapSeed: seed,
                                             registry: registry).biomeID
        }
        return out
    }

    /// The share of touching pairs that are the same country. This is the
    /// number that separates a map from confetti.
    private func agreement(_ map: [HexCoord: String]) -> Double {
        var same = 0, total = 0
        for (coord, biome) in map {
            for neighbour in coord.neighbors() {
                guard let other = map[neighbour] else { continue }
                total += 1
                if other == biome { same += 1 }
            }
        }
        return total == 0 ? 0 : Double(same) / Double(total)
    }

    // MARK: - It is a map

    /// Independent per-hex rolls over six weighted biomes agree about a fifth
    /// of the time. Anything near that is confetti however it is drawn.
    @Test("Neighbouring hexes are usually the same country")
    func biomesCluster() throws {
        let reg = try registry()
        for seed in [UInt64(4242), 7, 99, 1_234_567] {
            let share = agreement(biomes(seed: seed, registry: reg))
            #expect(share > 0.45,
                    "seed \(seed): only \(Int(share * 100))% of touching hexes matched — that is confetti")
        }
    }

    /// …and the other side of it, which is the failure a clustering fix
    /// actually produces: one country swallowing the world.
    @Test("…but the world is not one country")
    func theWorldIsNotOneBiome() throws {
        let reg = try registry()
        for seed in [UInt64(4242), 7, 99, 1_234_567] {
            let map = biomes(seed: seed, registry: reg)
            let share = agreement(map)
            #expect(share < 0.95, "seed \(seed) is a single country wall to wall")
            #expect(Set(map.values).count >= 3,
                    "seed \(seed) has only \(Set(map.values).count) kinds of country in it")
        }
    }

    @Test("A range is bigger than one hex")
    func featuresHaveSize() throws {
        let reg = try registry()
        // The biggest run of one country reachable by walking from hex to hex.
        func largestRegion(_ map: [HexCoord: String]) -> Int {
            var seen: Set<HexCoord> = []
            var best = 0
            for (start, biome) in map where !seen.contains(start) {
                var stack = [start], size = 0
                seen.insert(start)
                while let here = stack.popLast() {
                    size += 1
                    for next in here.neighbors()
                    where !seen.contains(next) && map[next] == biome {
                        seen.insert(next)
                        stack.append(next)
                    }
                }
                best = max(best, size)
                _ = biome
            }
            return best
        }
        let map = biomes(seed: 4242, radius: 8, registry: reg)
        #expect(largestRegion(map) >= 8,
                "the largest stretch of one country is \(largestRegion(map)) hexes")
    }

    // MARK: - …and no two worlds are alike

    @Test("Two seeds are two different worlds")
    func seedsDiffer() throws {
        let reg = try registry()
        let a = biomes(seed: 4242, registry: reg)
        let b = biomes(seed: 99, registry: reg)
        let shared = a.filter { b[$0.key] == $0.value }.count
        #expect(Double(shared) / Double(a.count) < 0.7,
                "two seeds laid out \(shared) of \(a.count) hexes identically")
    }

    @Test("Every country in the data turns up somewhere")
    func nothingIsExtinct() throws {
        let reg = try registry()
        var found: Set<String> = []
        for seed in [UInt64(1), 2, 3, 4, 5, 6, 7, 8] {
            found.formUnion(biomes(seed: seed, radius: 6, registry: reg).values)
        }
        let named = Set(reg.biomes.keys)
        #expect(found == named,
                "never generated: \(named.subtracting(found).sorted())")
    }

    // MARK: - The rules that must not break

    /// The property the endless map rests on: a hex is generated on its own,
    /// in any order, and always comes out the same. Fields are a pure function
    /// of position, so this must survive them.
    @Test("A hex generated on its own agrees with the whole map")
    func generationIsStillLazyAndPure() throws {
        let reg = try registry()
        let whole = biomes(seed: 4242, radius: 5, registry: reg)
        for (coord, biome) in whole {
            #expect(MapGenerator.region(at: coord, mapSeed: 4242, registry: reg).biomeID == biome)
        }
    }

    @Test("The land at a hex is always inside its scale")
    func fieldsStayInRange() {
        for coord in disc(radius: 12) {
            let land = MapGenerator.land(at: coord, mapSeed: 4242)
            #expect(land.elevation >= -1 && land.elevation <= 1)
            #expect(land.moisture >= -1 && land.moisture <= 1)
            #expect(land.warmth >= -1 && land.warmth <= 1)
        }
    }

    /// A biome added to `biomes.json` without an opinion about where it belongs
    /// still has to appear — the niche is an enrichment, not a requirement.
    @Test("A country with no niche is still placed")
    func nicheLessBiomesStillAppear() throws {
        let plain = BiomeDefinition(id: "nowhere",
                                    name: LocalizedText(values: [.en: "Nowhere", .cs: "Nikde"]))
        let reg = GameDataRegistry(biomes: [plain], config: .default)
        let ids = disc(radius: 4).map {
            MapGenerator.region(at: $0, mapSeed: 4242, registry: reg).biomeID
        }
        #expect(ids.allSatisfy { $0 == "nowhere" })
    }
}
