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

    // MARK: - Room to explore, without a checklist

    /// Keks: *"udělej mapy 2-3× větší, je to malé — nemusí být víc POI, jeden
    /// dva."* Both halves matter, and they pull against each other: more ground
    /// at the same site density is proportionally more landmarks, which turns a
    /// frontier into a list of errands.
    @Test("The world you start inside got bigger without filling up with sites")
    func aBiggerFrontierIsNotACheckList() throws {
        let reg = try registry()
        #expect(reg.mapGen.mapRadius >= 5, "the starting frontier is still one ring wide")

        // Averaged over seeds, because a single world is a small sample.
        var specials = 0
        let seeds: [UInt64] = [1, 2, 3, 4, 5, 6, 7, 8]
        for seed in seeds {
            specials += MapGenerator.generate(seed: seed, registry: reg)
                .count { $0.kind != .wilderness && $0.kind != .homeland }
        }
        let perWorld = Double(specials) / Double(seeds.count)
        // Eight is what the old radius-3 disc averaged. A handful more is the
        // "jeden dva"; twenty would be the checklist.
        #expect(perWorld < 14,
                "a starting world holds \(perWorld) special sites — that is a list of errands")
        #expect(perWorld > 4, "a starting world holds \(perWorld) — there is nothing out there")
    }

    /// The endless half of the same sum, which is the one nobody could see at
    /// the old radius: the distance bonus used to be added to all five site
    /// kinds independently, so it passed 1.0 somewhere around ring twenty and
    /// every far hex became a ruin for ever.
    @Test("The deep frontier is rich, not paved with ruins")
    func theFarCountryStaysCountry() throws {
        let reg = try registry()
        for ring in [10, 20, 60, 500] {
            var specials = 0
            let sample = 400
            for i in 0..<sample {
                var rng = SeededRNG(seed: UInt64(i) &* 0x9E37)
                if MapGenerator.rollKind(config: reg.mapGen, ring: ring, rng: &rng) != .wilderness {
                    specials += 1
                }
            }
            let share = Double(specials) / Double(sample)
            #expect(share < 0.5,
                    "at ring \(ring), \(Int(share * 100))% of hexes hold a site")
        }
    }

    // MARK: - The place is the landmark

    /// Keks: *"ty biomy nebo mapy by mohly samy o sobě být POI — kráterové
    /// jezero, průsmyk."* A landform is only worth having if it is **rare** —
    /// a map where every hex is a landmark has no landmarks — and only worth
    /// trusting if it agrees with the ground it is read from.
    @Test("Landforms are rare enough to be landmarks")
    func featuresAreRare() {
        var featured = 0, total = 0
        for seed in [UInt64(4242), 7, 99, 1_234_567] {
            for coord in disc(radius: 9) {
                total += 1
                if MapGenerator.feature(at: coord, mapSeed: seed) != nil { featured += 1 }
            }
        }
        let share = Double(featured) / Double(total)
        #expect(share > 0.02, "only \(Int(share * 1000))‰ of the world is anywhere at all")
        #expect(share < 0.30, "\(Int(share * 100))% of hexes are landmarks, so none of them are")
    }

    /// The half that makes them worth reading off the ground rather than
    /// rolling: a pass really is a way *through* high country, and a crater
    /// lake really does have a rim.
    @Test("A landform agrees with the land it is read from")
    func featuresMatchTheGround() {
        for seed in [UInt64(4242), 7, 99, 1_234_567, 31] {
            for coord in disc(radius: 9) {
                guard let feature = MapGenerator.feature(at: coord, mapSeed: seed) else { continue }
                let here = MapGenerator.land(at: coord, mapSeed: seed)
                let heights = coord.neighbors().map { MapGenerator.land(at: $0, mapSeed: seed).elevation }
                switch feature {
                case .peak:
                    #expect(here.elevation > (heights.max() ?? 1), "a peak nothing towers over")
                case .pass:
                    #expect((heights.max() ?? 0) > here.elevation, "a pass with nothing to pass through")
                case .craterLake:
                    #expect((heights.min() ?? -1) > here.elevation, "a crater lake with no rim")
                    #expect(here.moisture > 0, "a dry lake")
                case .fen:
                    #expect(here.moisture > 0, "a dry fen")
                case .oasis:
                    #expect(here.moisture > 0, "a dry oasis")
                case .plateau:
                    #expect(here.elevation > 0, "a plateau at the bottom of everything")
                case .gorge, .headland:
                    break   // both are about the spread around, checked by construction
                }
            }
        }
    }

    /// Rule 6, in the shape this project keeps producing: a landform whose
    /// conditions the ground never actually satisfies is dead code that reads
    /// as content. The first cut had four of the eight unreachable — a peak had
    /// to stand 0.10 over all six neighbours, and the 99th percentile of that
    /// measure is +0.018.
    @Test("Every landform the game can name is one the ground can make")
    func everyLandformIsReachable() {
        var seen: Set<RegionFeature> = []
        for seed in UInt64(1)...40 {
            for coord in disc(radius: 9) {
                if let f = MapGenerator.feature(at: coord, mapSeed: seed) { seen.insert(f) }
            }
        }
        let missing = Set(RegionFeature.allCases).subtracting(seen)
        #expect(missing.isEmpty,
                "never produced by any ground: \(missing.map(\.rawValue).sorted())")
    }

    @Test("Two places with the same landform are still two places")
    func featuresDoNotCollapseNames() throws {
        let reg = try registry()
        let regions = disc(radius: 8).map {
            MapGenerator.region(at: $0, mapSeed: 4242, registry: reg)
        }
        let named = regions.filter { $0.feature != nil }
        #expect(named.count > 1)
        #expect(Set(named.map(\.name)).count == named.count,
                "two landmarks share a name — the no-collision naming was lost")
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
