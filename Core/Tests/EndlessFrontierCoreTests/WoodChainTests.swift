import Testing
import Foundation
@testable import EndlessFrontierCore

/// **The wood is the bottom of the whole item tree, and it ran out.**
///
/// Measured on a real save 113 years in: seven trees left in the valley, every
/// one below workable growth, nine loggers with nothing to swing at. No `wood`
/// meant no `saw_timber` and no `burn_charcoal`; no charcoal meant `smelt_iron`
/// had never once run; and with no timber bundles, every building in the book
/// that lists a crafted cost — thirty-one of fifty-nine, including every
/// generator — was permanently unbuildable.
///
/// These pin the two halves of the floor that stops it: a stand that is never
/// felled, and seed that is set fast enough to matter.
/// **The book of trees, held against the game that plants them.**
@Suite("Every kind of tree is a real tree")
struct FloraContentTests {

    @Test("Every species names a crown the canvas can draw")
    func crownsAreDrawable() throws {
        let registry = try GameDataRegistry.bundled()
        #expect(!registry.flora.isEmpty, "flora.json loaded nothing")
        // `Crown` is a closed set because each case is a piece of drawing that
        // exists; decoding an unknown one would silently fall back to a
        // broadleaf and a conifer would come out as a bush.
        for (id, def) in registry.flora {
            #expect(FloraDefinition.Crown.allCases.contains(def.crown),
                    "\(id) wears a crown nobody draws")
        }
    }

    @Test("Every species grows somewhere, and every biome grows something")
    func nothingIsStranded() throws {
        let registry = try GameDataRegistry.bundled()
        for (id, def) in registry.flora {
            #expect(!def.biomes.isEmpty, "\(id) is named by no biome, so it grows nowhere")
        }
        for biome in registry.biomes.keys {
            #expect(!registry.flora(inBiome: biome).isEmpty,
                    "\(biome) has no tree in the book")
        }
    }

    @Test("Every species has a colour to be drawn in")
    func everySpeciesIsPainted() throws {
        let registry = try GameDataRegistry.bundled()
        // `scenery.json` holds the seasonal palette, keyed by the same id. A
        // species with no entry falls back to `SceneryDefinition.plain`, which
        // is a grey tree — the sort of silent default that ships broken content.
        for id in registry.flora.keys {
            #expect(registry.scenery[id] != nil,
                    "\(id) has no seasonal colour in scenery.json")
        }
    }

    @Test("The frozen table agrees with the book it was frozen from")
    func legacyAgreesWithContent() throws {
        let registry = try GameDataRegistry.bundled()
        for legacy in LegacyTreeSpecies.allCases {
            guard let def = registry.tree(legacy.rawValue) else {
                Issue.record("\(legacy.rawValue) is in the frozen table and not in flora.json")
                continue
            }
            #expect(def.maturityTicks == legacy.maturityTicks,
                    "\(legacy.rawValue) matures differently in the two")
            #expect(def.timber == legacy.timber,
                    "\(legacy.rawValue) yields differently in the two")
            #expect(def.crown == legacy.crown,
                    "\(legacy.rawValue) is drawn differently in the two")
        }
    }
}

/// **The book of beasts, held against the game that puts them on a map.**
@Suite("Every kind of beast is a real beast")
struct AnimalContentTests {

    @Test("Every species names a build the canvas can draw")
    func buildsAreDrawable() throws {
        let registry = try GameDataRegistry.bundled()
        #expect(!registry.animals.isEmpty, "animals.json loaded nothing")
        for (id, def) in registry.animals {
            #expect(AnimalDefinition.Build.allCases.contains(def.build),
                    "\(id) wears a build nobody draws")
        }
    }

    @Test("Every beast lives somewhere, and every biome has something living in it")
    func nothingIsStranded() throws {
        let registry = try GameDataRegistry.bundled()
        for (id, def) in registry.animals {
            #expect(!def.biomes.isEmpty, "\(id) is named by no biome, so it lives nowhere")
            for range in def.biomes {
                #expect(range.min <= range.max, "\(id) in \(range.id) has a backwards range")
                #expect(registry.biomes[range.id] != nil,
                        "\(id) lives in '\(range.id)', which is not a biome")
            }
        }
        for biome in registry.biomes.keys {
            #expect(!registry.animals(inBiome: biome).isEmpty,
                    "nothing lives in \(biome)")
        }
    }

    @Test("Somewhere for a predator to be, or the whole of that half is dead code")
    func predatorsExist() throws {
        let registry = try GameDataRegistry.bundled()
        // `isPredator` is honoured all over the engine — hunters skip them,
        // prey flee them, they stalk the weak. A book with none in it makes
        // every one of those paths unreachable, which is how it was before the
        // wild was seeded at all.
        #expect(registry.animals.values.contains { $0.isPredator },
                "nothing in the book hunts")
    }

    @Test("The frozen table agrees with the book it was frozen from")
    func legacyAgreesWithContent() throws {
        let registry = try GameDataRegistry.bundled()
        for legacy in LegacyAnimalSpecies.allCases {
            guard let def = registry.beast(legacy.rawValue) else {
                Issue.record("\(legacy.rawValue) is in the frozen table and not in animals.json")
                continue
            }
            #expect(def.baseHealth == legacy.baseHealth,
                    "\(legacy.rawValue) is a different size of life in the two")
            #expect(def.isPredator == legacy.isPredator,
                    "\(legacy.rawValue) hunts in one and not the other")
            #expect(def.build == legacy.build,
                    "\(legacy.rawValue) is drawn differently in the two")
            #expect(def.comfortLow == legacy.comfortLow && def.comfortHigh == legacy.comfortHigh,
                    "\(legacy.rawValue) keeps a different band in the two")
            // Size is load-bearing — meat, retaliation and danger all derive
            // from it — so a disagreement here is a beast that is quietly the
            // wrong animal depending on how it was made.
            #expect(def.size == legacy.size,
                    "\(legacy.rawValue) is a different size in the two")
        }
    }
}

@Suite("A wood the colony cannot fell to nothing")
struct WoodChainTests {

    static let registry = try! GameDataRegistry.bundled()

    static func wood(_ count: Int, growth: Double, species: String = "birch") -> [Tree] {
        (0..<count).map { i in
            Tree(id: i, species: species,
                 position: LocalPoint(x: 0.1 + Double(i % 20) * 0.04,
                                      y: 0.1 + Double(i / 20) * 0.04),
                 age: Int(Double(LegacyTreeSpecies(rawValue: species)?.maturityTicks ?? 2000) * growth))
        }
    }

    static func map(_ trees: [Tree]) -> LocalMap {
        var m = LocalMap(river: RiverShape(baseY: 0.5, amplitude: 0.05, phase: 0),
                         nodes: [], pois: [],
                         wildlife: WildlifeState(deerHerd: 0, deerCapacity: 0),
                         terrainSeed: 99, trees: trees, rocks: [])
        m.usesEntityLand = true
        return m
    }

    @Test("The axes stop before the last seed-bearing trees")
    func theStandSurvives() {
        var m = Self.map(Self.wood(FloraEngine.seedStand + 2, growth: 1))
        // A hundred shifts of a whole colony's loggers, which before this would
        // have taken every tree in the valley several times over.
        for _ in 0..<400 { m = FloraEngine.fell(m, loggers: 12).map }
        let bearing = m.trees.filter { $0.growth >= FloraEngine.bearingGrowth }.count
        #expect(bearing >= FloraEngine.seedStand,
                "only \(bearing) bearing trees left of \(FloraEngine.seedStand)")
    }

    @Test("A tree the player marked is felled even when the wood is at its floor")
    func aMarkOutranksTheFloor() {
        let trees = Self.wood(FloraEngine.seedStand, growth: 1)
        var m = Self.map(trees)
        let target = trees[0].id
        for _ in 0..<40 { m = FloraEngine.fell(m, loggers: 1, marked: [target]).map }
        #expect(!m.trees.contains { $0.id == target },
                "a marked tree is a decision, and the colony ignored it")
    }

    @Test("Nothing is felled before it has ever set seed")
    func nothingIsFelledBeforeItBears() {
        #expect(FloraEngine.minimumWorkableGrowth >= FloraEngine.bearingGrowth,
                "harvesting under breeding age is how the valley emptied")
    }

    @Test("A stripped valley comes back inside a colony's lifetime")
    func aStrippedValleyRecovers() {
        // What the save actually held: seven saplings and nothing else.
        var m = Self.map(Self.wood(7, growth: 0))
        // Fifty years, seeded on the cadence `WildlifeEngine` uses.
        let pass = LaborEngine.staffingInterval * 5
        for tick in stride(from: 0, to: 3000, by: pass) {
            m = FloraEngine.advanceOneTick(m, by: pass)
            m = FloraEngine.reseeded(m, mapSeed: 4242, tick: tick, registry: Self.registry)
        }
        let bearing = m.trees.filter { $0.growth >= FloraEngine.bearingGrowth }.count
        #expect(m.trees.count > 30, "only \(m.trees.count) trees after fifty years")
        #expect(bearing >= FloraEngine.seedStand,
                "only \(bearing) of them bearing — the wood has no future")
    }

    // MARK: - A wood the colony can grow

    /// **The trap this closes**, measured by `WoodProbe` over two centuries,
    /// seed 4242: the bearing count pinned at *exactly* `seedStand` from year
    /// thirty to year two hundred, because the axes take every tree the moment
    /// it bears. So `spare` was zero for a hundred and seventy years, and the
    /// term that makes seed scale — `bearers / bearersPerSapling`, 16/6 = 2 —
    /// sat under the `thinWoodSaplings` floor of four for ever. Wood supply was
    /// a **constant** while the colony went from 39 people to 298; the shelf
    /// went 276 → 39 → 3 → 1 and eight standing orders read "short of
    /// materials" for the rest of the run.
    @Test("A wood held at its seed stand still grows when somebody plants")
    func aFloorBoundWoodStillGrows() {
        // Exactly the state the probe found: at the floor, nothing spare.
        var m = Self.map(Self.wood(FloraEngine.seedStand, growth: 1))
        #expect(FloraEngine.spareToFell(m) == 0, "the fixture is not at the floor")
        let before = m.trees.count
        for tick in stride(from: 0, to: 2000, by: LaborEngine.staffingInterval) {
            m = FloraEngine.tended(m, foresters: 4, mapSeed: 4242, tick: tick,
                                   registry: Self.registry)
        }
        #expect(m.trees.count > before,
                "loggers at a floor-bound wood planted nothing — \(m.trees.count) trees")
    }

    /// The rate answers the colony, which is the whole point: a constant cannot
    /// feed a town that quadruples.
    @Test("More foresters plant more wood")
    func plantingScalesWithLoggers() {
        func grown(foresters: Int) -> Int {
            var m = Self.map(Self.wood(FloraEngine.seedStand, growth: 1))
            for tick in stride(from: 0, to: 600, by: LaborEngine.staffingInterval) {
                m = FloraEngine.tended(m, foresters: foresters, mapSeed: 4242, tick: tick,
                                       registry: Self.registry)
            }
            return m.trees.count
        }
        #expect(grown(foresters: 12) > grown(foresters: 2))
    }

    /// …and stops. A valley is not a jungle, and a planting rate with no top to
    /// it is the same bug pointing the other way.
    @Test("Planting stops at the ceiling")
    func plantingHasATop() {
        var m = Self.map(Self.wood(FloraEngine.woodCeiling, growth: 1))
        for tick in stride(from: 0, to: 2000, by: LaborEngine.staffingInterval) {
            m = FloraEngine.tended(m, foresters: 40, mapSeed: 4242, tick: tick,
                                   registry: Self.registry)
        }
        #expect(m.trees.count <= FloraEngine.woodCeiling,
                "the valley grew past its ceiling to \(m.trees.count)")
    }

    /// Determinism, because planting rolls dice (CLAUDE.md rule 3).
    @Test("The same valley plants the same wood twice")
    func plantingIsDeterministic() {
        func run() -> [LocalPoint] {
            var m = Self.map(Self.wood(FloraEngine.seedStand, growth: 1))
            for tick in stride(from: 0, to: 400, by: LaborEngine.staffingInterval) {
                m = FloraEngine.tended(m, foresters: 3, mapSeed: 4242, tick: tick,
                                       registry: Self.registry)
            }
            return m.trees.map(\.position)
        }
        let a = run(), b = run()
        #expect(a.count == b.count)
        #expect(zip(a, b).allSatisfy { $0.x == $1.x && $0.y == $1.y })
    }

    /// The other half of the same switch: while there *is* something spare, the
    /// axes still go to it. A colony that plants instead of felling a standing
    /// crop has swapped one starvation for another.
    @Test("A wood above its seed stand is still felled")
    func aThickWoodIsStillCut() {
        let m = Self.map(Self.wood(FloraEngine.seedStand + 9, growth: 1))
        #expect(FloraEngine.spareToFell(m) == 9,
                "the axes were told there was nothing to cut in a wood with nine to spare")
    }
}

/// **Crafting from the list, in parallel.**
///
/// Keks: *"asi by bylo fajn moct z toho seznamu craftit paralelně."* His town
/// has seven lumberyards and six bloomeries and worked **one** lumberyard order
/// at a time, because the bench was keyed on the building's id rather than on
/// how many of them stand.
@Suite("Every shop that stands is a bench")
struct ParallelBenchTests {

    static func settlement(_ registry: GameDataRegistry) -> Settlement {
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-0B01-f7695d4586ee")!,
                           name: "Bench", kind: .capital)
        for slot in 0..<3 {
            s.buildings.append(BuildingInstance.founding("lumberyard", at: s.id, slot: slot))
        }
        s.stockpile["wood"] = 999
        return s
    }

    @Test("Three lumberyards work three orders at once")
    func threeShopsThreeBenches() throws {
        let registry = try GameDataRegistry.bundled()
        var s = Self.settlement(registry)
        for i in 0..<3 {
            s.craftOrders.append(CraftOrder(id: UUID(), recipeID: "saw_timber",
                                           wanted: nil, placedTick: i))
        }
        let benches = CraftingEngine.workableBenches(
            at: s, researched: [], crafters: 6, registry: registry)
        #expect(benches.count == 3, "only \(benches.count) of three lumberyards is working")
    }

    @Test("No more benches than there are hands to stand at them")
    func handsAreTheCeiling() throws {
        let registry = try GameDataRegistry.bundled()
        var s = Self.settlement(registry)
        for i in 0..<3 {
            s.craftOrders.append(CraftOrder(id: UUID(), recipeID: "saw_timber",
                                           wanted: nil, placedTick: i))
        }
        let benches = CraftingEngine.workableBenches(
            at: s, researched: [], crafters: 1, registry: registry)
        #expect(benches.count == 1,
                "one crafter opened \(benches.count) benches and each order crawls")
    }
}
