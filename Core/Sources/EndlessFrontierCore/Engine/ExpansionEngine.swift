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
        let outpost = Settlement(
            name: name,
            kind: .outpost,
            regionID: regionID,
            foundedTick: s.tick,
            population: 20,
            buildings: [],
            storage: [.food: 40, .materials: 20],
            storageCapacity: registry.config.defaultStorageCapacity,
            stats: SettlementStats(stability: 50, morale: 55)
        )
        s.settlements.append(outpost)
        s.regions[regionIndex].settlementIDs.append(outpost.id)
        return s
    }
}
