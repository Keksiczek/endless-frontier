import Foundation

/// Builds the initial world for a new game: a procedurally generated hex map
/// with the capital settled in the homeland region at its centre.
public enum GameWorldFactory {
    public static func newGame(
        registry: GameDataRegistry,
        seed: UInt64 = 0x5EED_F00D,
        now: Date = Date(),
        language: GameLanguage = .cs
    ) -> WorldState {
        // Procedurally generate the world map (homeland at the origin).
        var regions = MapGenerator.generate(seed: seed, registry: registry, language: language)
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
            name: NameForge.capitalName(language: language),
            kind: .capital,
            regionID: homeland.id,
            foundedTick: 0,
            pawns: starterPawns(seed: seed),
            buildings: buildings,
            storage: [.food: 200, .materials: 120, .energy: 0, .knowledge: 0, .influence: 20],
            storageCapacity: registry.config.defaultStorageCapacity,
            stats: SettlementStats(stability: 60, morale: 60),
            colony: ColonyBuilder.seededLayout(for: buildings, registry: registry),
            localMap: LocalMapGenerator.generate(mapSeed: seed, regionID: homeland.id,
                                                 biome: registry.biome(homeland.biomeID))
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
            language: language,
            unlockedBuildings: unlocked,
            worldFlags: flags,
            settlements: [settlement],
            regions: regions,
            tribes: nativeTribes(regions: regions, seed: seed)
        )
    }

    /// The valley was never empty: two or three native peoples live in the
    /// distant regions from the very first tick. They stay hidden — and
    /// diplomatically inert — until an expedition walks into their land, so
    /// the world *fills in* as you explore it rather than being born hollow.
    static let nativeTribeNames = ["Vorenn", "Askarel", "Thalen", "Muirn", "Sorne"]
    static let nativeTribeCount = 3
    static let nativeMinDistance = 2

    static func nativeTribes(regions: [Region], seed: UInt64) -> [Tribe] {
        var rng = SeededRNG(seed: seed ^ 0x0071_1BE5)
        // Candidate homes: far enough out that first contact takes an
        // expedition or two, in a stable order so the same seed settles the
        // same peoples in the same hills.
        let candidates = regions
            .filter { $0.kind != .homeland && $0.coord.distance(to: .origin) >= nativeMinDistance }
            .sorted { $0.coord.distance(to: .origin) != $1.coord.distance(to: .origin)
                ? $0.coord.distance(to: .origin) < $1.coord.distance(to: .origin)
                : $0.name < $1.name }
        guard !candidates.isEmpty else { return [] }

        var tribes: [Tribe] = []
        var taken: Set<UUID> = []
        for (index, name) in nativeTribeNames.prefix(nativeTribeCount).enumerated() {
            // Spread them: skip through the candidate list so two peoples
            // don't crowd the same corner of the map.
            let pick = candidates.enumerated().first {
                !taken.contains($0.element.id) && $0.offset >= index * 2
            }?.element ?? candidates.first { !taken.contains($0.id) }
            guard let home = pick else { break }
            taken.insert(home.id)
            tribes.append(Tribe(
                id: rng.nextUUID(),
                name: name,
                regionID: home.id,
                foundedTick: 0,
                originStory: LocalizedText(values: [
                    .en: "The \(name) were in the valley long before your first fire was lit.",
                    .cs: "\(name) žili v údolí dávno předtím, než jste zapálili první oheň."
                ]),
                population: 18 + rng.nextUnit() * 30,
                genes: Genes(
                    industry: 0.35 + rng.nextUnit() * 0.4,
                    fertility: 0.4 + rng.nextUnit() * 0.3,
                    sociability: 0.3 + rng.nextUnit() * 0.5,
                    courage: 0.3 + rng.nextUnit() * 0.5),
                defense: 10 + rng.nextUnit() * 12,
                stores: 60 + rng.nextUnit() * 60,
                standing: 0,
                isNative: true,
                discovered: false))
        }
        return tribes
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
