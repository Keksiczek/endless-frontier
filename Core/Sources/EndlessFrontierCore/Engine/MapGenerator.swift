import Foundation

/// Procedurally generates the hex world map. Generation is **per-hex**: a
/// region's content is a pure function of `(mapSeed, coord)`, so any hex can be
/// generated lazily, in any order, and always comes out the same. That makes
/// the map both fully reproducible *and* endlessly extensible — as the player
/// pushes outward, new rings are generated on demand and the frontier never
/// ends.
///
/// Difficulty scales with distance from the homeland (more hazard, more
/// special sites), so there is always a reason — and a risk — to explore
/// further.
public enum MapGenerator {
    // Place names are *built*, not picked from a list.
    //
    // There used to be 25 of them, taken modulo the coordinate, on a map that
    // is deliberately endless and grows every time you reveal a hex. So the
    // same two dozen names repeated forever: a player charts the Duskwater in
    // front of them, sees three more Duskwaters still offering an expedition,
    // and concludes that exploring did nothing. The map was lying about which
    // place was which. (The old scheme also ignored `mapSeed` entirely, so
    // every world named its places identically.)
    //
    // 25 × 20 × 10 = 5,000 names, and the coordinate is folded into that space
    // through a bijection — so within any map a player will ever walk, two
    // places cannot share a name *by construction*, not by luck.
    // The morpheme pools live in `NameForge` (Czech and English, same pool
    // sizes) so a world charts "Mlhoviště" or "Duskwater" by its language
    // while the no-collision bijection below holds identically for either.

    /// A unique number for every hex — a Cantor pairing of the axial
    /// coordinates, mapped through ℤ→ℕ first. Being a bijection is the whole
    /// point: distinct hexes cannot collide here, so they cannot collide in the
    /// names built from it.
    static func hexIndex(_ coord: HexCoord) -> Int {
        let a = coord.q >= 0 ? 2 * coord.q : -2 * coord.q - 1
        let b = coord.r >= 0 ? 2 * coord.r : -2 * coord.r - 1
        return (a + b) * (a + b + 1) / 2 + b
    }

    /// The name of the place at a coordinate. Deterministic per `(mapSeed,
    /// coord)`, and distinct from every other place a player will reach.
    public static func name(for coord: HexCoord, mapSeed: UInt64,
                            language: GameLanguage = .en) -> String {
        let space = NameForge.regionNameSpace
        // Offsetting by the seed keeps the mapping a bijection while giving
        // each world its own names — the old scheme gave every world the same
        // ones in the same places.
        let offset = Int(mapSeed % UInt64(space))
        let index = (hexIndex(coord) + offset) % space
        return NameForge.regionName(index: index, language: language)
    }

    /// Deterministic per-hex seed.
    static func hexSeed(_ mapSeed: UInt64, _ coord: HexCoord) -> UInt64 {
        // Injective in the coordinate, by construction rather than by luck.
        //
        // This used to fold q and r in with `(h ^ q) &* K ^ r`, which collides
        // *systematically* — multiplication isn't linear over XOR, so different
        // (q, r) pairs land on the same seed in a regular pattern: (−2, 8) and
        // (0, −10), (−4, 8) and (2, −10), and hundreds more. A region's `id` is
        // drawn from this seed, so those hexes became two places sharing one
        // id, and every lookup that keys on id — which is all of them — crossed
        // the wires between them. On screen: a card describing a charted
        // mountain region while offering the Send Expedition button belonging
        // to the *uncharted* hex that shared its id, and tapping it did nothing
        // because `startExpedition` re-checks the real target and correctly
        // refuses.
        //
        // `hexIndex` is a bijection ℤ² → ℕ and splitmix64 is a bijection over
        // UInt64, so within a world two hexes cannot land on the same seed.
        splitmix64(UInt64(bitPattern: Int64(hexIndex(coord))) &+ mapSeed)
    }

    /// A bijection over `UInt64` — every step (xor-shift, odd multiply) is
    /// invertible, so distinct inputs are guaranteed distinct outputs.
    static func splitmix64(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// The country the colony wakes up in, drawn from `homeland_weight` in
    /// `biomes.json`.
    ///
    /// This was hardcoded to plains, which meant the one map a player looks at
    /// for an entire game — their capital's valley — was the same grass, the
    /// same scenery mix and the same deposit spread every single run, no matter
    /// what the world map said. `LocalTerrain` and `LocalMapGenerator` have
    /// always had real per-biome variety; nothing was ever feeding them
    /// anything but "plains".
    ///
    /// Derived from `mapSeed` alone, so a seed keeps its homeland for the life
    /// of the world.
    static func homelandBiome(
        mapSeed: UInt64, registry: GameDataRegistry, biomeIDs: [String]
    ) -> String {
        let fallback = biomeIDs.contains("plains") ? "plains" : (biomeIDs.first ?? "plains")
        let candidates = biomeIDs.compactMap { id -> (String, Double)? in
            guard let weight = registry.biome(id)?.homelandWeight, weight > 0 else { return nil }
            return (id, weight)
        }
        // A biome set that nominates nobody keeps the old behaviour rather than
        // dropping the player into a world with no ground.
        guard !candidates.isEmpty else { return fallback }

        // Among the countries the data nominates, the one that suits the ground
        // the homeland actually stands on.
        //
        // Drawn rather than rolled, because the homeland sits at the *origin*
        // of the same three fields every other hex is read from — and a
        // homeland that ignores them is a desert capital ringed by forest, with
        // the map disagreeing with itself at the one hex the player looks at
        // most. The land at the origin still differs from seed to seed, so this
        // stays as varied as the roll it replaces, and only nominated biomes
        // can win it.
        let ground = land(at: .origin, mapSeed: mapSeed)
        var best: (String, Double)?
        for (id, weight) in candidates {
            guard let niche = registry.biome(id)?.niche else { continue }
            let fit = niche.fit(elevation: ground.elevation,
                                moisture: ground.moisture,
                                warmth: ground.warmth) * weight
            if fit > (best?.1 ?? 0) { best = (id, fit) }
        }
        if let best { return best.0 }

        // Nobody nominated has an opinion about where it belongs: roll, as before.
        var rng = SeededRNG(seed: splitmix64(mapSeed ^ 0xB10E_5EED_0000_0001))
        guard let index = rng.weightedIndex(candidates.map(\.1)) else { return fallback }
        return candidates[index].0
    }

    /// The region at a coordinate. Pure: same `(mapSeed, coord)` → same region.
    public static func region(at coord: HexCoord, mapSeed: UInt64, registry: GameDataRegistry,
                              language: GameLanguage = .en) -> Region {
        let biomeIDs = registry.biomes.keys.sorted()
        let homelandBiome = homelandBiome(mapSeed: mapSeed, registry: registry, biomeIDs: biomeIDs)
        var rng = SeededRNG(seed: hexSeed(mapSeed, coord))

        if coord == .origin {
            return Region(
                id: rng.nextUUID(),
                name: NameForge.homelandName(language: language),
                coord: .origin,
                kind: .homeland,
                biomeID: homelandBiome,
                hazardLevel: registry.biome(homelandBiome)?.baseHazard ?? 0,
                explorationState: .fullyExplored,
                feature: feature(at: .origin, mapSeed: mapSeed),
                river: river(at: .origin, mapSeed: mapSeed)
            )
        }

        let config = registry.mapGen
        let ring = coord.distance(to: .origin)
        let kind = rollKind(config: config, ring: ring, rng: &rng)
        let biomeID = biome(at: coord, mapSeed: mapSeed, registry: registry,
                            biomeIDs: biomeIDs, config: config, rng: &rng)
        let baseHazard = registry.biome(biomeID)?.baseHazard ?? 1
        let hazard = baseHazard
            + hazardBonus(for: kind, config: config)
            + Int(Double(ring) * config.hazardPerRing)
        let name = name(for: coord, mapSeed: mapSeed, language: language)

        return Region(
            id: rng.nextUUID(),
            name: name,
            coord: coord,
            kind: kind,
            biomeID: biomeID,
            hazardLevel: hazard,
            explorationState: .unknown,
            feature: feature(at: coord, mapSeed: mapSeed),
            river: river(at: coord, mapSeed: mapSeed)
        )
    }

    // MARK: - Where the water runs

    /// How wet ground has to be before water will run on it.
    ///
    /// **Measured, not guessed** (rule 23). `MapProbe.whereTheWaterRuns` prints
    /// the moisture percentiles *and sweeps this constant*, so it is chosen
    /// against the shape of the whole map rather than against one number
    /// somebody liked the look of:
    ///
    /// ```
    /// moisture   share   courses   longest
    ///     0.06   30.7%        55        14
    ///     0.30   15.8%        31         9
    ///     0.50    8.0%        18         8
    ///     0.60    5.5%        14         8
    /// ```
    ///
    /// The first guess was 0.06 and put water on nearly a third of the map,
    /// which does not make rivers a feature of a valley — it makes a bridge a
    /// flat tax on building anything. At 0.50 water is on one hex in twelve:
    /// rare enough to be a thing about *this* country, common enough that a
    /// road will meet it.
    static let riverMoisture = 0.50

    /// How high a spring rises. Wet flat country with nothing feeding it is a
    /// marsh, not a river, and the difference is that a river comes *down* from
    /// somewhere.
    static let springElevation = 0.18

    /// Where water goes from here: the lowest neighbour, if any is lower.
    ///
    /// Ties broken on the coordinate, never on the order `neighbors()` happens
    /// to return, so the same seed runs the same water.
    static func downhill(from coord: HexCoord, mapSeed: UInt64) -> HexCoord? {
        let here = land(at: coord, mapSeed: mapSeed).elevation
        var best: (coord: HexCoord, elevation: Double)?
        for neighbour in coord.neighbors() {
            let there = land(at: neighbour, mapSeed: mapSeed).elevation
            guard there < here else { continue }
            let better = best.map { there < $0.elevation
                || (there == $0.elevation && hexIndex(neighbour) < hexIndex($0.coord)) } ?? true
            if better { best = (neighbour, there) }
        }
        return best?.coord
    }

    static func carriesWater(_ coord: HexCoord, mapSeed: UInt64) -> Bool {
        land(at: coord, mapSeed: mapSeed).moisture >= riverMoisture
    }

    /// **The water through one hex, if there is any.**
    ///
    /// Purely local — this hex and its six neighbours — because the map is
    /// generated per hex and grows outward for ever as the player explores. A
    /// river traced globally from its source would come out differently
    /// depending on which hexes happened to exist when it was asked for, which
    /// is the one thing a deterministic map may not do.
    ///
    /// Courses still form: a hex runs water when something upstream feeds it,
    /// and that upstream hex runs water when *its* upstream does, so a line
    /// grows on its own and ends where the ground dries out or stops falling.
    public static func river(at coord: HexCoord, mapSeed: UInt64) -> RiverCourse? {
        guard carriesWater(coord, mapSeed: mapSeed) else { return nil }
        let here = land(at: coord, mapSeed: mapSeed)
        let onward = downhill(from: coord, mapSeed: mapSeed)

        // Who feeds it: the wettest neighbour that carries water and falls into
        // this hex.
        var inflow: (coord: HexCoord, moisture: Double)?
        for neighbour in coord.neighbors() {
            guard carriesWater(neighbour, mapSeed: mapSeed),
                  downhill(from: neighbour, mapSeed: mapSeed) == coord else { continue }
            let wet = land(at: neighbour, mapSeed: mapSeed).moisture
            let better = inflow.map { wet > $0.moisture
                || (wet == $0.moisture && hexIndex(neighbour) < hexIndex($0.coord)) } ?? true
            if better { inflow = (neighbour, wet) }
        }

        // Something feeds it, or a spring rises here. Otherwise the hex is
        // merely damp.
        guard inflow != nil || here.elevation >= springElevation else { return nil }
        // …and water that neither arrives nor leaves is standing water.
        guard inflow != nil || onward != nil else { return nil }
        return RiverCourse(from: inflow?.coord, to: onward)
    }

    /// The initial world: a disc of regions of radius `mapRadius`. Only a
    /// starting frontier — the world grows beyond it as the player explores.
    public static func generate(seed: UInt64, registry: GameDataRegistry,
                                language: GameLanguage = .en) -> [Region] {
        HexCoord.disc(radius: max(1, registry.mapGen.mapRadius))
            .map { region(at: $0, mapSeed: seed, registry: registry, language: language) }
    }

    /// Ensures every neighbour of `coord` exists in `regions`, generating the
    /// missing ones (unknown). Called when a region is revealed so the frontier
    /// keeps expanding outward without bound.
    public static func expandFrontier(
        around coord: HexCoord,
        regions: inout [Region],
        mapSeed: UInt64,
        registry: GameDataRegistry,
        language: GameLanguage = .en
    ) {
        let existing = Set(regions.map(\.coord))
        for neighbour in coord.neighbors() where !existing.contains(neighbour) {
            regions.append(region(at: neighbour, mapSeed: mapSeed, registry: registry,
                                  language: language))
        }
    }

    // MARK: - Rolls

    /// The most the frontier's distance may add to the chance of a hex holding
    /// something. Past this the far country is dangerous and rich, not paved
    /// with ruins.
    static let maxRingBonus = 0.25

    static func rollKind(config: MapGenConfig, ring: Int, rng: inout SeededRNG) -> RegionKind {
        // The distance bonus is **split across** the kinds, not added to each.
        //
        // It used to be added to all five independently, so a ring-*r* hex got
        // `4 × r × specialChancePerRing` of extra site chance in total. At the
        // old starting radius of three that was invisible; at radius five it
        // put twenty-nine specials in a starting world, and on an endless map
        // it passes 1.0 somewhere around ring twenty — every far hex a ruin,
        // for ever. Rule 14 in the map generator: a per-ring rate multiplied by
        // the number of things it is added to, with nothing bounding either.
        let bonus = min(maxRingBonus, Double(ring) * config.specialChancePerRing)
        let ruins = config.ruinsChance + bonus * 0.40
        let dungeon = config.dungeonChance + bonus * 0.28
        let anomaly = config.anomalyChance + bonus * 0.20
        // The wonders are rarer and take the smallest slice of the growth —
        // they should stay finds, not fixtures.
        let sanctuary = config.sanctuaryChance + bonus * 0.06
        let lostCity = config.lostCityChance + bonus * 0.06
        let roll = rng.nextUnit()
        if roll < ruins { return .ruins }
        if roll < ruins + dungeon { return .dungeon }
        if roll < ruins + dungeon + anomaly { return .anomaly }
        if roll < ruins + dungeon + anomaly + sanctuary { return .sanctuary }
        if roll < ruins + dungeon + anomaly + sanctuary + lostCity { return .lostCity }
        return .wilderness
    }

    static func rollBiome(biomeIDs: [String], config: MapGenConfig, rng: inout SeededRNG) -> String {
        guard !biomeIDs.isEmpty else { return "plains" }
        let weights = biomeIDs.map { config.biomeWeights[$0] ?? 1.0 }
        let index = rng.weightedIndex(weights) ?? 0
        return biomeIDs[index]
    }

    // MARK: - Geography

    /// How wide a feature is, in hexes. Elevation runs on the longest
    /// wavelength because ranges are the biggest thing on a map; moisture and
    /// warmth run shorter, so a range can be wet on one side and dry on the
    /// other.
    static let elevationScale: Double = 7.5
    static let moistureScale: Double = 5.5
    static let warmthScale: Double = 9.0

    /// The land at a hex: how high, how wet, how warm, each −1…1.
    ///
    /// Three smooth fields, sampled at the hex's position on the plane. This is
    /// what turns the world map from salt and pepper into geography: because
    /// the fields are *continuous*, neighbouring hexes get nearly the same
    /// answer, so mountains come in ranges, deserts gather in the dry heat and
    /// a coast is a line rather than a speckle.
    ///
    /// Still a pure function of `(mapSeed, coord)` with no global pass, which
    /// is the property the whole endless map rests on — a hex ten rings out can
    /// be generated on its own, in any order, and always comes out the same.
    ///
    /// Elevation gets a second, finer octave so a range has foothills instead
    /// of one smooth dome.
    public static func land(
        at coord: HexCoord, mapSeed: UInt64
    ) -> (elevation: Double, moisture: Double, warmth: Double) {
        // Axial hex → the plane. Without this the fields are sampled in a
        // sheared space and the features come out as lozenges (rule 10b's
        // shape: a field that does not know what the grid is really doing).
        let x = Double(coord.q) + Double(coord.r) / 2
        let y = Double(coord.r) * 0.8660254
        let elevation = 0.72 * noise(x / elevationScale, y / elevationScale, mapSeed ^ 0xE1E7)
            + 0.28 * noise(x / (elevationScale / 3), y / (elevationScale / 3), mapSeed ^ 0xF007)
        return (
            elevation: max(-1, min(1, elevation * 1.25)),
            moisture: noise(x / moistureScale, y / moistureScale, mapSeed ^ 0x3157),
            warmth: noise(x / warmthScale, y / warmthScale, mapSeed ^ 0x7EAF)
        )
    }

    /// The country that wants this ground most.
    ///
    /// Biomes with no niche keep the old behaviour and are placed by weight, so
    /// a biome added to `biomes.json` without an opinion still appears.
    static func biome(
        at coord: HexCoord, mapSeed: UInt64, registry: GameDataRegistry,
        biomeIDs: [String], config: MapGenConfig, rng: inout SeededRNG
    ) -> String {
        let ground = land(at: coord, mapSeed: mapSeed)
        var best: String?
        var bestFit = 0.0
        for id in biomeIDs {
            guard let niche = registry.biome(id)?.niche else { continue }
            // Weight still counts, as a thumb on the scale rather than the
            // whole decision: a common country wins ties on its own ground.
            let fit = niche.fit(elevation: ground.elevation,
                                moisture: ground.moisture,
                                warmth: ground.warmth)
                * (config.biomeWeights[id] ?? 1)
            if fit > bestFit { bestFit = fit; best = id }
        }
        guard let best else {
            return rollBiome(biomeIDs: biomeIDs, config: config, rng: &rng)
        }
        return best
    }

    // MARK: - What the land is

    /// The landform at a hex, if the ground makes one.
    ///
    /// Read off the fields rather than rolled, so a pass is genuinely a way
    /// through high country and a crater lake genuinely has a rim — see
    /// `RegionFeature`. Nil is the ordinary case and must stay that way: a map
    /// where every hex is a landmark has no landmarks.
    ///
    /// Order matters. The tests are the specific shapes, so they are asked
    /// first; the broad ones (plateau, fen) are what is left.
    public static func feature(at coord: HexCoord, mapSeed: UInt64) -> RegionFeature? {
        let here = land(at: coord, mapSeed: mapSeed)
        let around = coord.neighbors().map { land(at: $0, mapSeed: mapSeed) }
        guard around.count == 6 else { return nil }
        let heights = around.map(\.elevation)
        guard let highest = heights.max(), let lowest = heights.min() else { return nil }
        let mean = heights.reduce(0, +) / Double(heights.count)
        let wetAround = around.map(\.moisture).reduce(0, +) / Double(around.count)

        // Every threshold below is measured against what the ground **actually
        // does** between neighbours, which `MapProbe.relief` prints. The first
        // cut guessed instead and was wrong in both directions at once: it
        // wanted a peak to stand 0.10 above all six neighbours, when the 99th
        // percentile of "this hex minus its highest neighbour" is +0.018, so no
        // peak ever existed — while asking a plateau to be flat to within 0.22,
        // which is the 33rd percentile, so *every* high hex was one. Twenty-nine
        // plateaus in a world and never a pass or a crater lake.
        //
        // So the sharp features are defined as **local extrema** instead, which
        // needs no magic number and cannot drift when the field's scale is
        // retuned: a peak is simply higher than everything it touches.
        let spread = highest - lowest

        // Higher than everything around it.
        if here.elevation > highest, here.elevation > 0.42 { return .peak }
        // Lower than everything around it, and holding water: a hollow with a rim.
        if here.elevation < lowest, here.moisture > 0.15,
           here.elevation < 0.3 { return .craterLake }
        // The ground opens: the biggest step across a hex, p97 and above.
        if spread > 0.70 { return .gorge }
        // A dip *through* high country — low against its neighbours, but not a
        // pit, or it would be the hollow above.
        if highest > 0.45, here.elevation < mean - 0.045,
           here.elevation > lowest { return .pass }
        // Green with a great deal of nothing around it: the wettest hex in dry,
        // warm country. A local maximum again rather than an absolute number,
        // because moisture is as smooth as height is — asking for a hex 0.25
        // wetter than its neighbours produced no oasis in ten thousand hexes.
        if here.moisture > (around.map(\.moisture).max() ?? 1),
           here.warmth > 0.25, wetAround < 0.05 { return .oasis }
        // Land reaching out into the low ground: it falls away on half its
        // sides. Measured against *this hex* rather than against sea level, for
        // the same reason — "three neighbours below −0.45" never happened.
        if heights.count(where: { $0 < here.elevation - 0.28 }) >= 3 { return .headland }
        // High, and level to within the flattest tenth of the map.
        if here.elevation > 0.45, spread < 0.13 { return .plateau }
        // Low and soaked.
        if here.elevation < -0.32, here.moisture > 0.55 { return .fen }
        return nil
    }

    // MARK: - Value noise

    /// Smooth value noise in −1…1: a lattice of stable random values with a
    /// smoothstep between them.
    ///
    /// Deterministic and positional — the same `(mapSeed, x, y)` is the same
    /// number on every machine and every run, which is what lets a hex be
    /// generated lazily and still agree with the hexes around it.
    static func noise(_ x: Double, _ y: Double, _ seed: UInt64) -> Double {
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        let fx = x - Double(x0), fy = y - Double(y0)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let a = lattice(seed, x0, y0), b = lattice(seed, x0 + 1, y0)
        let c = lattice(seed, x0, y0 + 1), d = lattice(seed, x0 + 1, y0 + 1)
        let top = a + (b - a) * sx
        let bottom = c + (d - c) * sx
        return top + (bottom - top) * sy
    }

    /// One lattice point's value, −1…1.
    static func lattice(_ seed: UInt64, _ x: Int, _ y: Int) -> Double {
        var h = seed &+ 0x9E37_79B9_7F4A_7C15
        h = (h ^ UInt64(bitPattern: Int64(x))) &* 0xBF58_476D_1CE4_E5B9
        h = (h ^ UInt64(bitPattern: Int64(y))) &* 0x94D0_49BB_1331_11EB
        h = splitmix64(h)
        // `h >> 11` is 53 bits, so the divisor is 2^53 — the same arithmetic
        // that `Climate.wobble` got wrong and that made every swing there three
        // times its stated size.
        return Double(h >> 11) / Double(1 << 53) * 2 - 1
    }

    static func hazardBonus(for kind: RegionKind, config: MapGenConfig) -> Int {
        switch kind {
        case .dungeon: return config.dungeonHazardBonus
        case .anomaly: return config.anomalyHazardBonus
        default: return 0
        }
    }

}
