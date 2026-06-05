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
        let buildings = starterBuildingIDs
            .filter { registry.building($0) != nil }
            .map { BuildingInstance(definitionID: $0, count: 1) }

        var outpost = Settlement(
            name: name,
            kind: .outpost,
            regionID: regionID,
            foundedTick: s.tick,
            population: 20,
            pawns: settlers(seedBase: settlerSeed(state: s, region: state.regions[regionIndex])),
            buildings: buildings,
            storage: [.food: 40, .materials: 20],
            storageCapacity: registry.config.defaultStorageCapacity,
            stats: SettlementStats(stability: 50, morale: 55),
            colony: ColonyBuilder.seededLayout(for: buildings)
        )
        for pawn in outpost.pawns {
            outpost = ColonyBuilder.autoAssign(outpost, pawnID: pawn.id, registry: registry)
        }

        s.settlements.append(outpost)
        s.regions[regionIndex].settlementIDs.append(outpost.id)
        return s
    }

    /// Two founding colonists for a new outpost — generated deterministically
    /// so each settlement is a real, living community from day one.
    private static func settlers(seedBase: UInt64) -> [Pawn] {
        [
            PawnFactory.generate(seed: seedBase),
            PawnFactory.generate(seed: seedBase &+ 0x9E37_79B9)
        ]
    }

    private static func settlerSeed(state: WorldState, region: Region) -> UInt64 {
        var h = state.mapSeed &* 0xD1B5_4A32_D192_ED03
        h = (h ^ UInt64(bitPattern: Int64(region.coord.q))) &* 0x0100_0000_01B3
        h = (h ^ UInt64(bitPattern: Int64(region.coord.r))) &* 0x0100_0000_01B3
        h = (h ^ UInt64(bitPattern: Int64(state.tick)))
        return h ^ (h >> 27)
    }
}
