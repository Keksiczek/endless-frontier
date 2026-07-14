import Foundation

/// Builds the initial world for a new game: a procedurally generated hex map
/// with the capital settled in the homeland region at its centre.
public enum GameWorldFactory {
    public static func newGame(
        registry: GameDataRegistry,
        seed: UInt64 = 0x5EED_F00D,
        now: Date = Date()
    ) -> WorldState {
        // Procedurally generate the world map (homeland at the origin).
        var regions = MapGenerator.generate(seed: seed, registry: registry)
        let homelandIndex = regions.firstIndex { $0.kind == .homeland } ?? 0
        let homeland = regions[homelandIndex]

        // Starter buildings, only those that actually exist in the data.
        let starterBuildingIDs = ["farm_basic", "lumberyard", "hut"]
        let buildings = starterBuildingIDs
            .filter { registry.building($0) != nil }
            .map { BuildingInstance(definitionID: $0, count: 1) }

        // The capital's identity must come from the seed: engines derive
        // per-settlement RNG streams from the settlement id, so a random id
        // would leak nondeterminism into every replay.
        var idRNG = SeededRNG(seed: seed ^ 0x5E77_1E1D)
        var settlement = Settlement(
            id: idRNG.nextUUID(),
            name: "First Light",
            kind: .capital,
            regionID: homeland.id,
            foundedTick: 0,
            pawns: starterPawns(seed: seed),
            buildings: buildings,
            storage: [.food: 200, .materials: 120, .energy: 0, .knowledge: 0, .influence: 20],
            storageCapacity: registry.config.defaultStorageCapacity,
            stats: SettlementStats(stability: 60, morale: 60),
            colony: ColonyBuilder.seededLayout(for: buildings, registry: registry)
        )

        // Put the founding colonists to work on the buildings that suit them.
        for pawn in settlement.pawns {
            settlement = ColonyBuilder.autoAssign(settlement, pawnID: pawn.id, registry: registry)
        }

        regions[homelandIndex].settlementIDs = [settlement.id]

        // Reveal the homeland's biome so biome-gated events can fire there.
        var flags: [String: Bool] = [:]
        if let flag = registry.biome(homeland.biomeID)?.worldFlag {
            flags[flag] = true
        }

        let unlocked = Set(starterBuildingIDs.filter { registry.building($0) != nil })

        return WorldState(
            tick: 0,
            lastRealTimestamp: now,
            rngSeed: seed,
            mapSeed: seed,
            era: .earlySettlement,
            unlockedBuildings: unlocked,
            worldFlags: flags,
            settlements: [settlement],
            regions: regions
        )
    }

    /// The founding colonists: four named specialists the narrator can lean
    /// on, plus a band of settlers — every inhabitant is a real pawn now.
    private static func starterPawns(seed: UInt64) -> [Pawn] {
        var rng = SeededRNG(seed: seed ^ 0xF0_0D_CAFE)
        let named = [
            Pawn(name: "Mara", trait: .hardWorker, skills: [.farming: 8, .logging: 4],
                 assignedWork: .farming, genes: .founder(using: &rng)),
            Pawn(name: "Joss", trait: .optimist, skills: [.logging: 7, .mining: 5],
                 assignedWork: .logging, genes: .founder(using: &rng)),
            Pawn(name: "Eli", trait: .none, skills: [.research: 6, .trade: 3],
                 assignedWork: .research, genes: .founder(using: &rng)),
            Pawn(name: "Nadia", trait: .pessimist, skills: [.farming: 5, .trade: 6],
                 assignedWork: .farming, genes: .founder(using: &rng))
        ]
        let settlers = (0..<14).map { PawnFactory.generate(seed: rng.next() &+ UInt64($0)) }
        return named + settlers
    }
}
