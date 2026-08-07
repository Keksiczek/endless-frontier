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
        // A founding party has a fire they cook over, and it is the only reason
        // the grain they reap becomes anything. Without a cookhouse in this
        // list nobody in the colony can ever hold the cooking trade —
        // `LaborEngine.staffBuildings` seats people at buildings, so a trade
        // with no building is a trade with no people — and the whole colony
        // lives off raw grain out of `ErrandEngine.rawFoodValue` for ever.
        // Measured before it was here: a hundred years, a shelf with 246 sacks
        // of grain on it, and a larder at zero the entire time.
        let starterBuildingIDs = ["farm_basic", "cookhouse", "lumberyard", "hut"]

        // The capital's identity must come from the seed: engines derive
        // per-settlement RNG streams from the settlement id, so a random id
        // would leak nondeterminism into every replay. Drawn *before* the
        // buildings, because their ids are derived from it too.
        var idRNG = SeededRNG(seed: seed ^ 0x5E77_1E1D)
        let capitalID = idRNG.nextUUID()
        let buildings = starterBuildingIDs
            .filter { registry.building($0) != nil }
            .enumerated()
            .map { BuildingInstance.founding($0.element, at: capitalID, slot: $0.offset) }

        var settlement = Settlement(
            id: capitalID,
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
            // The homeland's own character and danger, not defaults: the
            // starting valley was generated as generic wilderness at hazard
            // zero regardless of what the world map said sat there.
            localMap: LocalMapGenerator.generate(mapSeed: seed, regionID: homeland.id,
                                                 biome: registry.biome(homeland.biomeID),
                                                 flavor: homeland.kind,
                                                 hazard: homeland.hazardLevel)
        )

        // Put the founding colonists to work on the buildings that suit them.
        for pawn in settlement.pawns {
            settlement = ColonyBuilder.autoAssign(settlement, pawnID: pawn.id, registry: registry)
        }

        // The founding farm arrives with its ground already tilled. Without
        // this the colony's food chain does not start until the first reconcile
        // cadence, and a world the player opens on tick 0 shows a farm with
        // nothing growing on it — which reads as broken rather than as early.
        settlement = FarmEngine.reconcile(
            settlement, registry: registry,
            climate: registry.biome(homeland.biomeID)?.climate ?? .temperate)

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
    /// The four founders, and then the rest of the boat.
    ///
    /// **Their ids come from the seed.** `Pawn.init` defaults `id` to a fresh
    /// `UUID()`, and these four were taking it — so the very first four people
    /// in every world were different people every launch. Per-entity randomness
    /// is derived from `(mapSeed, entity.id, tick)`, which means the whole game
    /// was nondeterministic from tick zero: the same seed grew a different
    /// colony every time, and any test that asked two identical worlds to agree
    /// was passing on luck. Exactly the landmine CLAUDE.md rule 3 names, in the
    /// one place nobody thought to look — world creation itself. The recruits
    /// behind them were always seeded (`PawnFactory.generate`); it was only the
    /// people with names.
    private static func starterPawns(seed: UInt64) -> [Pawn] {
        var rng = SeededRNG(seed: seed ^ 0xF0_0D_CAFE)
        var idRNG = SeededRNG(seed: seed ^ 0xFACE_0FF)
        // **Different ages.** `Pawn.defaultAdultAgeTicks` is twenty-five, so a
        // founding party that states no age is five people who are all exactly
        // twenty-five — and who therefore leave the fertile window in the same
        // year. Measured: the colony had one childbearing couple at a time for
        // two centuries and never grew past fourteen. A party that arrives with
        // a spread of ages has a spread of futures.
        func years(_ n: Int) -> Int { n * 60 }
        let named = [
            Pawn(id: idRNG.nextUUID(),
                 name: "Mara", trait: .hardWorker, skills: [.farming: 8, .logging: 4],
                 assignedWork: .farming, age: years(22), genes: .founder(using: &rng)),
            Pawn(id: idRNG.nextUUID(),
                 name: "Joss", trait: .optimist, skills: [.logging: 7, .mining: 5],
                 assignedWork: .logging, age: years(25), genes: .founder(using: &rng)),
            Pawn(id: idRNG.nextUUID(),
                 name: "Eli", trait: .none, skills: [.research: 6, .trade: 3],
                 assignedWork: .research, age: years(28), genes: .founder(using: &rng)),
            // Someone has to walk out and look. Without a scout on day one the
            // valley stays the circle it was born with: `chartGround` needs at
            // least one, and `LaborEngine`'s 5% share is the last quota filled,
            // so at founding size it never was.
            Pawn(id: idRNG.nextUUID(),
                 name: "Nadia", trait: .pessimist, skills: [.scouting: 6, .trade: 5],
                 assignedWork: .scouting, age: years(18), genes: .founder(using: &rng)),
            // And someone who can cook, for exactly the reason Nadia is here.
            // `ColonyBuilder.autoAssign` only ever seats a colonist at a
            // building matching the trade they *already* hold, so a cookhouse
            // with nobody in the party who cooks stands empty — and
            // `assignIdleAdults` cannot fix it, because it only touches the
            // idle and the first colonist born will not come of age for
            // sixteen years. Measured without her: six hundred ticks, 269 sacks
            // of grain on the shelf and a larder at zero the whole time.
            Pawn(id: idRNG.nextUUID(),
                 name: "Osk", trait: .none, skills: [.cooking: 7, .farming: 4],
                 assignedWork: .cooking, age: years(23), genes: .founder(using: &rng))
        ]
        // **Two, not fourteen.**
        //
        // A colony that arrives nineteen strong is a colony you meet as a
        // crowd: by year ten it was twenty-nine people and nobody in it was
        // anybody. Five named founders and a couple who came with them is a
        // party you can hold in your head, and it is what "starting from zero"
        // has to mean if the first decade is going to be about *people* rather
        // than about a headcount going up.
        let settlers = (0..<7).map { PawnFactory.generate(seed: rng.next() &+ UInt64($0)) }
        return named + settlers
    }
}
