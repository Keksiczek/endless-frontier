import Foundation

/// Founding new settlements in explored regions.
public enum ExpansionEngine {
    /// Cost to found an outpost, paid from the capital's storage.
    public static let outpostFoundingCost = Resources([.materials: 60, .influence: 30])

    /// Regions that are fully explored and don't yet hold a settlement.
    public static func foundableRegions(_ state: WorldState) -> [Region] {
        state.regions.filter { $0.explorationState == .fullyExplored && $0.settlementIDs.isEmpty }
    }

    /// Founds an outpost in a foundable region, paying the founding cost from
    /// the capital. Returns unchanged state on failure.
    public static func foundOutpost(
        _ state: WorldState,
        regionID: UUID,
        name: String,
        registry: GameDataRegistry
    ) -> WorldState {
        guard let regionIndex = state.regions.firstIndex(where: {
            $0.id == regionID && $0.explorationState == .fullyExplored && $0.settlementIDs.isEmpty
        }), let paid = EffectApplier.payCost(outpostFoundingCost, from: state) else {
            return state
        }
        var s = paid

        // A new outpost arrives as a real, small base: a couple of starter
        // buildings (only those the data actually defines), laid out on its own
        // colony grid, with its settlers put to work.
        let starterBuildingIDs = ["farm_basic", "hut"]

        // Deterministic identity: per-settlement RNG streams key off the id,
        // and the founding buildings key off it in turn.
        let seedBase = settlerSeed(state: s, region: state.regions[regionIndex])
        var idRNG = SeededRNG(seed: seedBase ^ 0x0072_1D0F)
        // A founded hearth deserves a real name, not "Outpost 3" — callers
        // that pass nothing get one forged in the world's language.
        var nameRNG = SeededRNG(seed: seedBase ^ 0x00A9_E5A1)
        let outpostName = name.isEmpty
            ? NameForge.settlementName(language: s.language, using: &nameRNG)
            : name
        let outpostID = idRNG.nextUUID()
        let buildings = starterBuildingIDs
            .filter { registry.building($0) != nil }
            .enumerated()
            .map { BuildingInstance.founding($0.element, at: outpostID, slot: $0.offset) }
        var outpost = Settlement(
            id: outpostID,
            name: outpostName,
            kind: .outpost,
            regionID: regionID,
            foundedTick: s.tick,
            pawns: settlers(seedBase: seedBase, language: s.language),
            buildings: buildings,
            storage: [.food: 40, .materials: 20],
            storageCapacity: registry.config.defaultStorageCapacity,
            stats: SettlementStats(stability: 50, morale: 55),
            colony: ColonyBuilder.seededLayout(for: buildings, registry: registry),
            localMap: LocalMapGenerator.generate(mapSeed: s.mapSeed, regionID: regionID,
                                                 biome: registry.biome(state.regions[regionIndex].biomeID),
                                                 flavor: state.regions[regionIndex].kind,
                                                 hazard: state.regions[regionIndex].hazardLevel)
        )
        for pawn in outpost.pawns {
            outpost = ColonyBuilder.autoAssign(outpost, pawnID: pawn.id, registry: registry)
        }
        // An outpost arrives with its ground broken, exactly as the capital
        // does — settlers who have to wait a cadence before anything is sown
        // are settlers eating their travelling provisions for nothing.
        outpost = FarmEngine.reconcile(
            outpost, registry: registry,
            climate: registry.biome(state.regions[regionIndex].biomeID)?.climate ?? .temperate)

        s.settlements.append(outpost)
        s.regions[regionIndex].settlementIDs.append(outpost.id)
        return s
    }

    /// The founding party of a new outpost — generated deterministically
    /// so each settlement is a real, living community from day one.
    private static func settlers(seedBase: UInt64, language: GameLanguage) -> [Pawn] {
        (0..<6).map { PawnFactory.generate(seed: seedBase &+ UInt64($0) &* 0x9E37_79B9,
                                           language: language) }
    }

    private static func settlerSeed(state: WorldState, region: Region) -> UInt64 {
        var h = state.mapSeed &* 0xD1B5_4A32_D192_ED03
        h = (h ^ UInt64(bitPattern: Int64(region.coord.q))) &* 0x0100_0000_01B3
        h = (h ^ UInt64(bitPattern: Int64(region.coord.r))) &* 0x0100_0000_01B3
        h = (h ^ UInt64(bitPattern: Int64(state.tick)))
        return h ^ (h >> 27)
    }
}
