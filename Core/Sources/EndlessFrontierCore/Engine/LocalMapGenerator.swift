import Foundation

/// Deterministically builds a settlement's `LocalMap` from `(mapSeed, regionID)`
/// and its biome, honouring the rule `content = f(mapSeed, coord)`: the same
/// world always grows the same wilderness around the same settlement.
///
/// The biome decides the character of the place — how many fields and forests,
/// what scenery stands on the ground, whether a river runs through it — so a
/// mountain outpost and a coastal town read as genuinely different country.
public enum LocalMapGenerator {
    public static func generate(
        mapSeed: UInt64,
        regionID: UUID,
        biome: BiomeDefinition?,
        flavor: RegionKind = .wilderness,
        hazard: Int = 0
    ) -> LocalMap {
        var rng = SeededRNG(seed: seed(mapSeed: mapSeed, regionID: regionID))
        let biomeID = biome?.id ?? "plains"

        // A river crosses most country, but not the driest: a desert map gets a
        // dry wash pushed to the very edge instead.
        let riverBase: Double
        if biomeID == "desert" {
            riverBase = rng.nextUnit() < 0.5 ? 0.06 : 0.94
        } else if biomeID == "wetlands" {
            // A fen's water does not keep to an edge — it lies through the
            // middle of the country and everything is built around it.
            riverBase = 0.38 + rng.nextUnit() * 0.24
        } else {
            riverBase = rng.nextUnit() < 0.5 ? 0.16 : 0.82
        }
        // …and not every valley has one at all. Six kinds of country that all
        // came with the same blue ribbon across them read as one kind of
        // country with six tints. The shape is still generated either way, so
        // every `landPoint` call and the whole POI layout keep their geometry;
        // only the water is decided here.
        let river = RiverShape(
            baseY: riverBase,
            amplitude: 0.025 + rng.nextUnit() * 0.06,
            phase: rng.nextUnit() * 6.283185,
            flows: rng.nextUnit() < RiverShape.chance(biomeID: biomeID)
        )

        // A coast gets actual sea along one edge. Before this the one country
        // whose whole character is the water was a field with a stream through
        // it, exactly like the plains.
        let shore: ShoreShape? = biomeID == "coast"
            ? ShoreShape(
                side: ShoreShape.Side.allCases[
                    Int(rng.nextUnit() * Double(ShoreShape.Side.allCases.count))
                        % ShoreShape.Side.allCases.count],
                depth: 0.14 + rng.nextUnit() * 0.16,
                amplitude: 0.03 + rng.nextUnit() * 0.05,
                phase: rng.nextUnit() * 6.283185)
            : nil

        var nodeID = 0
        func makeNodes(_ kind: LocalResourceKind, count: Int) -> [ResourceNode] {
            (0..<max(0, count)).map { _ in
                let position = landPoint(river: river, shore: shore, rng: &rng)
                // The land's own character decides how much is actually in the
                // ground. `resource_affinity` sat in `biomes.json` being decoded
                // and read by nothing at all, so a mountain's `materials: 1.5`
                // and a desert's `food: 0.5` were decoration — the whole point
                // of standing somewhere meant nothing mechanically.
                let capacity = (160 + rng.nextUnit() * 120) * affinity(biome, for: kind)
                defer { nodeID += 1 }
                return ResourceNode(id: nodeID, kind: kind, position: position,
                                    amount: capacity, capacity: capacity)
            }
        }

        // Biome shapes what the land actually offers — but not to the last
        // deposit. A fixed mix per biome meant every forest valley held exactly
        // six woods, two fields and one seam: the *positions* moved and nothing
        // else did, which is why one map felt like the last one.
        let mix = jittered(depositMix(for: biomeID), rng: &rng)
        var nodes: [ResourceNode] = []
        nodes += makeNodes(.field, count: mix.fields)
        nodes += makeNodes(.forest, count: mix.forests)
        nodes += makeNodes(.stone, count: mix.stone)
        nodes += makeNodes(.herbs, count: mix.herbs)
        nodes += makeNodes(.ironOre, count: mix.ironOre)
        nodes += makeNodes(.coal, count: mix.coal)
        nodes += makeNodes(.oilSeep, count: mix.oilSeep)
        nodes += makeNodes(.clay, count: mix.clay)

        // Points of interest, drawn from what this country plausibly holds —
        // plus whatever the region's character adds (see below).
        //
        // Every map used to get the identical cast of all six kinds, which is
        // the single biggest reason two valleys felt like the same valley: no
        // map ever lacked anything and no map ever had anything the last one
        // didn't. Now a desert rarely hides a spring, mountains are riddled
        // with caves, and finding a shrine means something.
        var pois = pickPOIs(for: biomeID, river: river, shore: shore, rng: &rng)

        // Scenery: the landscape's furniture, biome-appropriate and seeded.
        let (kinds, count) = LocalTerrain.sceneryMix(for: biomeID)
        var scenery = (0..<count).map { index -> SceneryProp in
            let kind = LocalTerrain.weighted(kinds, rng.nextUnit())
            // Reeds and ponds belong by the water; everything else keeps its feet dry.
            let wetLoving = (kind == .reeds || kind == .pond)
            let position = wetLoving
                ? riversidePoint(river: river, shore: shore, rng: &rng)
                : landPoint(river: river, shore: shore, rng: &rng)
            return SceneryProp(id: index, kind: kind, position: position,
                               scale: 0.7 + rng.nextUnit() * 0.6)
        }

        // The region's character marks its ground. A lost city is *streets* of
        // fallen pillars; a sanctuary blooms; plain ruins scatter a few stones.
        // The same seed shapes the same chunk whether you merely survey it or
        // later settle it — what the scouts saw is what the settlers get.
        var propID = scenery.count
        var poiID = pois.count
        func addProps(_ kind: SceneryKind, _ n: Int, around center: LocalPoint, spread: Double) {
            for _ in 0..<n {
                let a = rng.nextUnit() * 2 * .pi
                let r = rng.nextUnit() * spread
                let p = LocalPoint(x: min(0.95, max(0.05, center.x + cos(a) * r)),
                                   y: min(0.95, max(0.05, center.y + sin(a) * r)))
                scenery.append(SceneryProp(id: propID, kind: kind, position: p,
                                           scale: 0.8 + rng.nextUnit() * 0.5))
                propID += 1
            }
        }
        switch flavor {
        case .lostCity:
            let heart = landPoint(river: river, shore: shore, rng: &rng)
            addProps(.ruinPillar, 9, around: heart, spread: 0.16)
            pois.append(LocalPOI(id: poiID, kind: .treasure, position: heart)); poiID += 1
            pois.append(LocalPOI(id: poiID, kind: .ruins,
                                 position: frontierPoint(river: river, shore: shore, rng: &rng))); poiID += 1
            nodes.append(ResourceNode(id: nodeID, kind: .stone,
                                      position: landPoint(river: river, shore: shore, rng: &rng),
                                      amount: 260, capacity: 260)); nodeID += 1
        case .sanctuary:
            let hallow = landPoint(river: river, shore: shore, rng: &rng)
            addProps(.flowers, 6, around: hallow, spread: 0.10)
            pois.append(LocalPOI(id: poiID, kind: .shrine, position: hallow)); poiID += 1
        case .ruins:
            addProps(.ruinPillar, 4, around: landPoint(river: river, shore: shore, rng: &rng), spread: 0.2)
        case .dungeon:
            pois.append(LocalPOI(id: poiID, kind: .cave,
                                 position: frontierPoint(river: river, shore: shore, rng: &rng))); poiID += 1
        case .outlawCamp:
            // What an outlaw camp looks like from the ridge: a caravan that
            // never arrived, and the pile it never arrived with. Both are POI
            // kinds the game already draws — a camp is a *place*, and a place
            // the renderer has no idea about is the fault this project keeps
            // finding (see `docs/RULES.md` on the entity layer being invisible).
            let hollow = landPoint(river: river, shore: shore, rng: &rng)
            pois.append(LocalPOI(id: poiID, kind: .wreck, position: hollow)); poiID += 1
            pois.append(LocalPOI(id: poiID, kind: .treasure,
                                 position: frontierPoint(river: river, shore: shore, rng: &rng))); poiID += 1
        default:
            break
        }

        // A herd sized by how much the land can feed, and predators to match
        // how wild the country is. The region's `hazardLevel` — which the world
        // map computes from biome, region kind and distance from home — never
        // reached the ground the colony actually stands on, so a frontier
        // valley six rings out was exactly as safe as the homeland.
        let capacity = herdCapacity(for: biomeID, rng: &rng)
        let herd = capacity * (0.4 + rng.nextUnit() * 0.3)
        let pressure = 8 + rng.nextUnit() * 8 + Double(max(0, hazard)) * 2.5
        // Real `Animal` entities too — and on **their own stream**.
        //
        // This used to share the map's rng, and the comment above it claimed it
        // was "drawn last" while trees, outcrops and the massif all came after.
        // So editing the wildlife mix changed how many numbers were drawn and
        // reshaped the whole valley: adding a goat to the mountains moved the
        // iron seam and `ProductionChainTests` went red with an ore country
        // that yielded no ore. A separate salt means the wild can be rebalanced
        // for ever without a single deposit moving (rule 2).
        var wildRNG = SeededRNG(
            seed: seed(mapSeed: mapSeed, regionID: regionID) ^ 0xB3A5_7C0D_1E9F_4472)
        let residents = AnimalFactory.wildPopulation(
            biomeID: biomeID, hazard: hazard, rng: &wildRNG)
        let wildlife = WildlifeState(
            deerHerd: herd, deerCapacity: capacity,
            predatorPressure: pressure, animals: residents, usesEntities: true)

        // The land as standing things: trees on the ground the forests claim,
        // outcrops on the stone, iron and clay. Drawn *after* the wildlife and
        // everything else, so no earlier roll shifts and existing worlds keep
        // the exact valley they had.
        let woodCentres = nodes.filter { $0.kind == .forest }.map(\.position)
        let trees = FloraFactory.woods(around: woodCentres, biomeID: biomeID,
                                       shore: shore, river: river, rng: &rng)
        let outcropSites = nodes
            .filter { $0.kind == .stone || $0.kind == .ironOre || $0.kind == .clay
                       || $0.kind == .coal || $0.kind == .oilSeep }
            .map { (kind: $0.kind, position: $0.position, capacity: $0.capacity) }
        let rocks = FloraFactory.outcrops(at: outcropSites, rng: &rng)

        // The mountain, last of all — a new draw inserted anywhere earlier would
        // shift every roll after it and every existing valley with it.
        let stone = StoneEngine.raise(biomeID: biomeID, river: river, shore: shore, rng: &rng)
        // …and the country's own shapes after it, for the same reason: drawn
        // last so inserting them shifts no roll that came before, and every
        // valley generated up to now keeps the land it had.
        let landforms = LandformFactory.forMap(biomeID: biomeID, rng: &rng)

        var map = LocalMap(
            river: river, nodes: nodes, pois: pois, wildlife: wildlife,
            biomeID: biomeID,
            terrainSeed: seed(mapSeed: mapSeed, regionID: regionID) ^ 0x7E_44_A1_04_5E_ED,
            scenery: scenery, landforms: landforms, trees: trees, rocks: rocks,
            usesEntityLand: true, shore: shore, stone: stone)
        // The settlement sits at the centre; its surroundings start revealed.
        // Wide enough to cover the whole build grid — a colony that can build
        // on ground nobody has charted sends its people into the fog, where the
        // canvas refuses to draw them and they vanish at work. Derived from the
        // span rather than written down again, so widening the town cannot
        // leave its own corners uncharted.
        map.reveal(around: LocalPoint(x: 0.5, y: 0.5),
                   radius: SettlementGeometry.cornerReach + 0.02)
        return map
    }

    /// How much of a deposit's resource this ground actually holds, from the
    /// biome's `resource_affinity`. Clamped so a hostile biome is poor, never
    /// barren — a desert field is a hard field, not a hole in the map.
    static func affinity(_ biome: BiomeDefinition?, for kind: LocalResourceKind) -> Double {
        affinity(biome, for: kind.work.resource)
    }

    /// The same, for callers that already know which resource is at stake.
    static func affinity(_ biome: BiomeDefinition?, for resource: ResourceType?) -> Double {
        guard let biome, let resource else { return 1 }
        let value = biome.resourceAffinity[resource]
        guard value > 0 else { return 1 }   // unstated affinity means ordinary
        return min(1.6, max(0.45, value))
    }

    /// The landmarks a given country plausibly holds, and how likely each is.
    /// A weight of zero means the place simply doesn't occur there.
    static func poiMix(for biomeID: String) -> [(LocalPOIKind, Double)] {
        switch biomeID {
        case "forest":
            return [(.ruins, 0.9), (.shrine, 1.0), (.cave, 0.5), (.spring, 0.9),
                    (.treasure, 0.6), (.wreck, 0.5),
                    (.orchard, 1.1), (.hermit, 1.0), (.barrow, 0.8),
                    (.watchtower, 0.5), (.saltPan, 0), (.starfall, 0.15)]
        case "desert":
            // Water is the whole story here: a spring is rare and worth a lot,
            // and salt is everywhere the water used to be.
            return [(.ruins, 1.2), (.treasure, 1.0), (.wreck, 1.0), (.cave, 0.6),
                    (.spring, 0.2), (.shrine, 0.5),
                    (.saltPan, 1.6), (.barrow, 1.0), (.hermit, 0.8),
                    (.watchtower, 0.7), (.orchard, 0.15), (.starfall, 0.3)]
        case "tundra":
            return [(.cave, 0.9), (.ruins, 1.0), (.wreck, 0.8), (.shrine, 0.5),
                    (.treasure, 0.5), (.spring, 0.3),
                    (.barrow, 0.9), (.hermit, 0.7), (.watchtower, 0.6),
                    (.starfall, 0.35), (.saltPan, 0.2), (.orchard, 0)]
        case "mountains":
            return [(.cave, 1.6), (.ruins, 0.8), (.shrine, 0.7), (.treasure, 0.6),
                    (.spring, 0.5), (.wreck, 0.2),
                    (.watchtower, 1.2), (.hermit, 1.1), (.starfall, 0.3),
                    (.barrow, 0.5), (.orchard, 0.2), (.saltPan, 0.2)]
        case "wetlands":
            return [(.barrow, 1.7), (.wreck, 1.2), (.ruins, 1.0), (.shrine, 1.0),
                    (.treasure, 0.9), (.spring, 0.6), (.cave, 0.1),
                    (.hermit, 1.1), (.orchard, 0.4), (.watchtower, 0.3),
                    (.saltPan, 0.2), (.starfall, 0.15)]
        case "coast":
            return [(.wreck, 1.5), (.spring, 0.9), (.shrine, 0.8), (.treasure, 0.8),
                    (.ruins, 0.6), (.cave, 0.4),
                    (.saltPan, 1.3), (.watchtower, 1.0), (.orchard, 0.7),
                    (.hermit, 0.5), (.barrow, 0.5), (.starfall, 0.15)]
        default: // plains & homeland
            return [(.spring, 1.0), (.shrine, 0.9), (.ruins, 0.9), (.treasure, 0.8),
                    (.wreck, 0.7), (.cave, 0.5),
                    (.orchard, 1.2), (.barrow, 1.0), (.watchtower, 0.8),
                    (.hermit, 0.7), (.saltPan, 0.4), (.starfall, 0.2)]
        }
    }

    /// How many landmarks a map gets. Four to seven now there are twelve kinds
    /// to draw from: the count is part of what makes one valley unlike another,
    /// and with six kinds a map that took five of them was most of the set.
    static let poiCountRange = 4...7

    /// Draws this map's landmarks: distinct kinds, weighted by the biome,
    /// scattered on dry land.
    static func pickPOIs(
        for biomeID: String, river: RiverShape, shore: ShoreShape?, rng: inout SeededRNG
    ) -> [LocalPOI] {
        var pool = poiMix(for: biomeID).filter { $0.1 > 0 }
        let span = poiCountRange.upperBound - poiCountRange.lowerBound + 1
        let wanted = min(pool.count,
                         poiCountRange.lowerBound + Int(rng.nextUnit() * Double(span)))
        var picked: [LocalPOI] = []
        for id in 0..<wanted {
            guard let index = rng.weightedIndex(pool.map(\.1)) else { break }
            let kind = pool.remove(at: index).0
            // Out past the colony's own charted ground: a landmark is a reason
            // to walk somewhere, and one under the market square is not one.
            picked.append(LocalPOI(id: id, kind: kind,
                                   position: frontierPoint(river: river, shore: shore, rng: &rng)))
        }
        return picked
    }

    /// How many deposits of each kind a biome yields.
    ///
    /// Iron and clay are deliberately *not* everywhere. A colony founded on the
    /// plains has clay for its kilns and almost no ore, so a forge needs either
    /// a trade route or a second settlement up in the hills — which is the
    /// point of having a world map at all.
    typealias DepositMix = (fields: Int, forests: Int, stone: Int, herbs: Int,
                            ironOre: Int, clay: Int, coal: Int, oilSeep: Int)

    static func depositMix(for biomeID: String) -> DepositMix {
        switch biomeID {
        // Coal goes where the rock is folded and the oil where it is not:
        // mountains and tundra hold seams, the desert and the coast hold seeps,
        // and a forest valley holds neither, which is what makes the industrial
        // eras a reason to settle somewhere else.
        case "forest":    return (2, 6, 2, 3, 1, 1, 0, 0)
        case "desert":    return (1, 1, 4, 1, 1, 0, 0, 2)
        case "tundra":    return (1, 2, 3, 2, 2, 0, 2, 1)
        case "mountains": return (1, 2, 6, 1, 4, 0, 3, 0)   // the ore country
        case "coast":     return (3, 2, 2, 3, 0, 3, 0, 1)   // clay beds, no iron
        // Peat is the fen's coal and it has no iron at all: fuel it can dig
        // and metal it has to trade for.
        case "wetlands":  return (4, 3, 0, 4, 0, 4, 2, 0)
        default:          return (4, 3, 2, 2, 1, 2, 1, 0)   // plains & homeland
        }
    }

    /// The biome's mix, varied per map.
    ///
    /// Each count lands between roughly half and one and a half times the
    /// biome's character, so two valleys of the same country genuinely differ:
    /// one is thick with timber where the next has the ore. Anything the biome
    /// says it holds keeps at least one, so a forest is never woodless — the
    /// point is variety, not a map that can't be played.
    static func jittered(_ mix: DepositMix, rng: inout SeededRNG) -> DepositMix {
        func vary(_ n: Int) -> Int {
            guard n > 0 else { return 0 }
            return max(1, Int((Double(n) * (0.5 + rng.nextUnit())).rounded()))
        }
        return (fields: vary(mix.fields), forests: vary(mix.forests),
                stone: vary(mix.stone), herbs: vary(mix.herbs),
                ironOre: vary(mix.ironOre), clay: vary(mix.clay),
                coal: vary(mix.coal), oilSeep: vary(mix.oilSeep))
    }

    /// The land's carrying capacity for game.
    static func herdCapacity(for biomeID: String, rng: inout SeededRNG) -> Double {
        let base: Double
        switch biomeID {
        case "forest":    base = 110
        case "plains":    base = 95
        case "coast":     base = 80
        case "wetlands":  base = 85
        case "tundra":    base = 55
        case "mountains": base = 50
        case "desert":    base = 35
        default:          base = 90
        }
        return base * (0.85 + rng.nextUnit() * 0.3)
    }

    /// A point on dry land (away from the river), biased toward the interior.
    /// Dry ground **outside the colony's own charted circle**.
    ///
    /// A landmark is a reason to walk out of the valley's middle, and a treasure
    /// under the market square is not one. With the town doubled, `landPoint`
    /// alone put most landmarks on ground the colony starts with already
    /// revealed — so the frontier had nothing in it and the fog had nothing to
    /// hide. Falls back to `landPoint` if the ring is too crowded to land in,
    /// because a map with no ruins at all is worse than one with a near ruin.
    static func frontierPoint(
        river: RiverShape, shore: ShoreShape? = nil, rng: inout SeededRNG
    ) -> LocalPoint {
        let charted = SettlementGeometry.cornerReach + 0.06
        for _ in 0..<24 {
            let p = landPoint(river: river, shore: shore, rng: &rng)
            let dx = p.x - 0.5, dy = p.y - 0.5
            if (dx * dx + dy * dy).squareRoot() >= charted { return p }
        }
        return landPoint(river: river, shore: shore, rng: &rng)
    }

    private static func landPoint(
        river: RiverShape, shore: ShoreShape? = nil, rng: inout SeededRNG
    ) -> LocalPoint {
        for _ in 0..<24 {
            let x = 0.06 + rng.nextUnit() * 0.88
            let y = 0.06 + rng.nextUnit() * 0.88
            let p = LocalPoint(x: x, y: y)
            // Nothing grows in the river, and nothing at all stands in the sea.
            // A dry valley has no channel to keep clear of, so it may use the
            // whole of its ground — which is most of the point of not having
            // a river in the first place.
            if river.flows, abs(y - river.y(atX: x)) <= 0.09 { continue }
            if let shore, shore.distanceInland(p) < 0.04 { continue }
            return p
        }
        let y = river.baseY < 0.5 ? 0.7 : 0.3
        let fallback = LocalPoint(x: 0.2 + rng.nextUnit() * 0.6, y: y)
        // Even the fallback must be dry land.
        guard let shore, shore.isWater(fallback) else { return fallback }
        return LocalPoint(x: 0.5, y: 0.5)
    }

    /// A point hugging the riverbank — where reeds grow and ponds gather. In a
    /// dry valley there is no bank, so the reeds simply do not grow: the caller
    /// gets an ordinary land point and a desert stops sprouting bulrushes along
    /// a channel that has no water in it.
    private static func riversidePoint(
        river: RiverShape, shore: ShoreShape? = nil, rng: inout SeededRNG
    ) -> LocalPoint {
        let x = 0.06 + rng.nextUnit() * 0.88
        let side: Double = rng.nextUnit() < 0.5 ? -1 : 1
        let offset = (0.03 + rng.nextUnit() * 0.05) * side
        guard river.flows else { return landPoint(river: river, shore: shore, rng: &rng) }
        let y = min(0.96, max(0.04, river.y(atX: x) + offset))
        return LocalPoint(x: x, y: y)
    }

    static func seed(mapSeed: UInt64, regionID: UUID) -> UInt64 {
        var h = mapSeed &* 0x9E37_79B9_7F4A_7C15
        let b = regionID.uuid
        let hi = UInt64(b.0) << 56 | UInt64(b.1) << 48 | UInt64(b.2) << 40 | UInt64(b.3) << 32
            | UInt64(b.4) << 24 | UInt64(b.5) << 16 | UInt64(b.6) << 8 | UInt64(b.7)
        let lo = UInt64(b.8) << 56 | UInt64(b.9) << 48 | UInt64(b.10) << 40 | UInt64(b.11) << 32
            | UInt64(b.12) << 24 | UInt64(b.13) << 16 | UInt64(b.14) << 8 | UInt64(b.15)
        h = (h ^ hi) &* 0xD1B5_4A32_D192_ED03
        h = (h ^ lo) &* 0xCBF2_9CE4_8422_2325
        return h ^ (h >> 29)
    }
}
