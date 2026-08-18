import Testing
import Foundation
@testable import EndlessFrontierCore

/// The food chain: ground somebody tills, a crop that ripens, a harvest carried
/// in, and a cook who turns it into what the colony eats.
///
/// What it replaced was the largest measured failure in the game. Food came out
/// of `PawnEngine` as `skill × 0.15 × gatherFactor`, where `gatherFactor` read
/// how full the `.field` deposits were — and those regrew at
/// `capacity × 0.0009` a tick against `0.45` drawn per farmer, so the
/// equilibrium was **under one farmer**. Every colony stripped its fields
/// inside a season and stayed there for two centuries, and every extra farmer
/// made it worse. 182 dead of starvation against 134 of old age, measured.
@Suite("The food chain")
struct FoodChainTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    // MARK: - Reachability

    /// The test rule 6 asks for, named for the reachability and not for the
    /// behaviour: **can the rate cross the threshold it is aimed at?**
    ///
    /// Everything downstream of this is tuning. If a plot cannot feed the
    /// people the council builds farms for, the colony starves however well
    /// every individual piece works — which is exactly how the first cut of
    /// this died at t=6 500 with two farms and seventy-four mouths.
    @Test("A plot feeds the mouths the council builds it for")
    func aPlotFeedsWhatItIsBuiltFor() throws {
        let reg = try registry()

        // What one plot yields in ingredient units per tick, worked out from
        // the crop table rather than asserted from a constant — so a change to
        // any species' yield or ripening has to keep this true.
        let rotation: [CropSpecies] = (0..<4).map { CropSpecies.sown(inPlot: $0) }
        var rotationTotal = 0.0
        for species in rotation { rotationTotal += species.yield / species.ripenTicks }
        let perGrowthTick = rotationTotal / Double(rotation.count)
        var seasonTotal = 0.0
        for season in Season.allCases { seasonTotal += FarmEngine.seasonGrowth[season] ?? 0 }
        let seasonAverage = seasonTotal / Double(Season.allCases.count)
        let unitsPerTick = perGrowthTick * seasonAverage

        // …and what a cook gets out of a unit, taken from the leanest meal in
        // the table, so this cannot pass on the strength of a stew the colony
        // may have no meat for.
        let leanest = try #require(reg.cookableMeals
            .filter { $0.ingredientUnits > 0 }
            .min { $0.food / Double($0.ingredientUnits) < $1.food / Double($1.ingredientUnits) })
        let foodPerUnit = leanest.food / Double(leanest.ingredientUnits)

        let foodPerPlotPerTick = unitsPerTick * foodPerUnit
        let eatenPerHead = reg.config.foodPerPersonPerTick

        #expect(foodPerPlotPerTick / eatenPerHead >= FarmEngine.peoplePerPlot,
                """
                A plot must feed at least the \(FarmEngine.peoplePerPlot) people \
                `StewardEngine` sizes the colony's fields against — it feeds \
                \(foodPerPlotPerTick / eatenPerHead) on the leanest meal there is.
                """)

        // …and **well** below it, not merely below it.
        //
        // This is the ceiling of a plot: what the ground yields if every valve
        // downstream is wide open. A crop only counts once a farmer has walked
        // out and cut it, what is cut waits to be hauled, and what is hauled
        // waits for a cook. Measured, seed 4242: at `peoplePerPlot = 4` the
        // council stopped raising farms at thirty-eight plots, and the colony
        // starved at a hundred and ten with sixty-nine dead — the fields were
        // delivering about half of this. The margin is the valves.
        #expect(foodPerPlotPerTick / eatenPerHead >= FarmEngine.peoplePerPlot * 1.8, """
            the council sizes the fields at \(FarmEngine.peoplePerPlot) mouths a \
            plot against a ceiling of \(foodPerPlotPerTick / eatenPerHead) — too \
            little slack for reaping, hauling and cooking to take their cut
            """)
    }

    /// The other end of the same question: the cooks have to be able to keep up
    /// with the fields, or the shelf fills while the larder empties.
    @Test("The cooking quota can keep up with the farming quota")
    func cooksKeepUpWithFarmers() throws {
        let reg = try registry()
        let share = { (work: WorkKind) in
            LaborEngine.quotas.first { $0.work == work }?.share ?? 0
        }
        // A thousand adults, so the shares are readable as headcounts.
        let cooks = share(.cooking) * 1000
        #expect(cooks > 0, "somebody has to make dinner")

        // The worst meal on the table, measured the way a cook is actually paid:
        // food per unit of work. **Not** `min(food) / max(work)` — that pairs
        // the dearest pot with the thinnest one, a combination no meal in the
        // file has, and it only ever passed because the first eight meals
        // happened to sit in a narrow band. Forty-seven meals later the band is
        // wider at both ends while every single ratio is *tighter* than before
        // (6.0…8.8), and the old formula failed content that is fine.
        let effort = CookingEngine.effortPerCook + CookingEngine.skillEffort * 0.5
        let leanest = try #require(reg.cookableMeals.map { $0.food / $0.work }.min())
        let foodCooked = cooks * effort * leanest
        let eaten = 1000 / 0.65 * reg.config.foodPerPersonPerTick   // adults are ~65% of a town

        let summary = "cooks at \(share(.cooking)) of the town make \(foodCooked) a tick "
            + "against \(eaten) eaten, on the leanest meal in the file (\(leanest) food per work)"
        #expect(foodCooked > eaten, "\(summary)")
    }

    /// The question the quota arithmetic above never asks: `cooksKeepUpWith
    /// Farmers` divides a *thousand* cooks' hands by the dearest meal, which is
    /// true of a town and says nothing about a village. A batch is not divisible
    /// — one cook either clears the work a pot costs or the pot is never made —
    /// so the rate that matters is **one** pair of hands against **one** batch.
    ///
    /// Rule 6, and the arithmetic form of it: banked effort plus a tick's work
    /// has to reach the dearest thing `best(for:)` is willing to reach for.
    @Test("A lone unskilled cook can pay for the dearest meal on the table")
    func aLoneCookCanReachTheDearestMeal() throws {
        let reg = try registry()
        let dearest = try #require(reg.cookableMeals.map(\.work).max())
        // The worst cook the game can staff a kitchen with: no skill, and only
        // just well enough to stand.
        let hands = CookingEngine.effortPerCook * 0.35
        #expect(CookingEngine.bankCeiling(reg) + hands >= dearest,
                """
                One cook banks at most \(CookingEngine.bankCeiling(reg)) and adds \
                \(hands) a tick, against a \(dearest)-work pot the kitchen will \
                keep choosing — so it is never made and nothing else is either.
                """)
    }

    /// …and the same thing run rather than reasoned about. A colony that has
    /// done *everything right* — fields, harvest, granary, cookhouse, a cook —
    /// must not starve because there is only one of them.
    @Test("One cook with a full shelf and a cookhouse actually feeds people")
    func oneCookIsEnough() throws {
        let reg = try registry()
        var s = Settlement(
            id: UUID(uuidString: "00000000-0000-0000-C00C-00000000F00D")!,
            name: "One Pot", buildings: [BuildingInstance(definitionID: "cookhouse")],
            storage: [.food: 0], storageCapacity: .uniform(400))
        s.pawns = [Pawn(id: UUID(uuidString: "00000000-0000-0000-C00C-000000000001")!,
                        name: "Cook", assignedWork: .cooking)]
        // A shelf with everything on it, which is when the kitchen reaches
        // highest — and when the bug bit hardest.
        for kind in CookingEngine.foodstuffs(reg) { s.stockpile[kind] = 200 }

        for tick in 0..<40 {
            s = CookingEngine.advanceOneTick(s, registry: reg, tick: tick)
        }
        #expect(s.storage[.food] > 0, "one cook, a cookhouse and a full shelf cooked nothing")
        #expect(s.pawns[0].skill(.cooking) == 0, "and did it without needing to be trained first")
    }

    // MARK: - The chain, end to end

    @Test("A colony left alone reaps, carries, cooks and eats")
    func theChainRuns() throws {
        let reg = try registry()
        var world = GameWorldFactory.newGame(registry: reg, seed: 4242)
        let kinds = CookingEngine.foodstuffs(reg)

        #expect(world.settlements[0].localMap?.crops.isEmpty == false,
                "the founding farm arrives with its ground tilled")

        world = TickEngine.advance(world, ticks: 1200, registry: reg).state
        let s = world.settlements[0]

        let shelf = kinds.reduce(0) { $0 + s.stockpile[$1, default: 0] }
        #expect(shelf > 0, "raw ingredients reach the shelf")
        #expect(s.storage[.food] > 0, "and somebody cooks them")
        #expect(s.pawns.contains { $0.assignedWork == .cooking }, "the colony has a cook")
        #expect(s.deathTallies["starvation", default: 0] == 0,
                "nobody starves in a colony this size in twenty years")
    }

    /// The whole point of the change, stated as the number it moved.
    @Test("Two hundred years no longer starve the colony out")
    func theFamineIsOver() throws {
        let reg = try registry()
        var world = GameWorldFactory.newGame(registry: reg, seed: 4242)
        world = TickEngine.advance(world, ticks: 12_000, registry: reg).state
        let s = world.settlements[0]

        #expect(s.population > 0, "the colony is alive")
        let starved = s.deathTallies["starvation", default: 0]
        let old = s.deathTallies["old_age", default: 0]
        #expect(starved < old,
                "hunger killed \(starved) against \(old) of old age — it used to be 182 against 134")
    }

    // MARK: - The valves

    /// Adding a link between the field and the mouth adds a new way for
    /// everybody to die. Both valves are load-bearing.
    @Test("A colony with no cook eats badly rather than dying")
    func rawFoodKeepsThemAlive() throws {
        let reg = try registry()
        var s = Settlement(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000F00D")!,
            name: "Hungry", kind: .capital, pawns: [],
            storage: [.food: 0], storageCapacity: .uniform(500))
        s.pawns = (0..<4).map { i in
            var p = Pawn(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 700 + i))!,
                         name: "Soul \(i)", assignedWork: .farming)
            p.age = 30 * reg.config.ticksPerYear
            p.needs = PawnNeeds(hunger: 20, rest: 80, recreation: 80)
            return p
        }
        s.stockpile = ["grain": 200]

        let before = s.pawns.map(\.needs.hunger).reduce(0, +)
        for tick in 0..<40 {
            s = ErrandEngine.advanceStep(s, registry: reg, clock: .at(absoluteStep: tick))
        }
        let after = s.pawns.map(\.needs.hunger).reduce(0, +)

        #expect(after > before, "they got at the sacks")
        #expect(s.stockpile["grain", default: 0] < 200, "and it cost the shelf")
        #expect(s.storage[.food] == 0, "without ever conjuring a cooked meal")
    }

    @Test("A strike stops the harvest and the kitchens")
    func aStrikeReachesTheFood() throws {
        let reg = try registry()
        var s = GameWorldFactory.newGame(registry: reg, seed: 4242).settlements[0]
        #expect(FarmEngine.reapingEffort(of: s, registry: reg) > 0)
        #expect(CookingEngine.effort(of: s, registry: reg) > 0)

        // Neither trade passes through `gatheringFactors`, which is where a
        // strike used to reach food. A strike nobody feels in the larder costs
        // the colony nothing, which is not what a strike is.
        s.strikeTicksRemaining = 10
        #expect(FarmEngine.reapingEffort(of: s, registry: reg) == 0)
        #expect(CookingEngine.effort(of: s, registry: reg) == 0)
    }

    @Test("A world with no meal data still has something to cook")
    func mealDataCannotStarveTheColony() {
        // `meals.json` is loaded with `try?` like every other optional data
        // file, and rule 9b is what that costs: one malformed entry empties the
        // whole table. For items that means no loot; here it would mean the
        // colony cannot cook at all.
        let bare = GameDataRegistry()
        #expect(bare.meals.isEmpty)
        #expect(bare.cookableMeals.count == 1)
        #expect(bare.cookableMeals[0].food > 0)
        #expect(CookingEngine.foodstuffs(bare).isEmpty == false)
    }

    // MARK: - The rules the change must not break

    @Test("The same seed grows the same harvest")
    func plotsAreDeterministic() throws {
        let reg = try registry()
        let a = TickEngine.advance(GameWorldFactory.newGame(registry: reg, seed: 909),
                                   ticks: 900, registry: reg).state
        let b = TickEngine.advance(GameWorldFactory.newGame(registry: reg, seed: 909),
                                   ticks: 900, registry: reg).state
        let cropsA = a.settlements[0].localMap?.crops ?? []
        let cropsB = b.settlements[0].localMap?.crops ?? []
        #expect(cropsA == cropsB)
        #expect(a.settlements[0].stockpile == b.settlements[0].stockpile)
        #expect(a.settlements[0].storage[.food] == b.settlements[0].storage[.food])
    }

    @Test("A save written before there were plots still loads")
    func oldSavesDecode() throws {
        let reg = try registry()
        let world = GameWorldFactory.newGame(registry: reg, seed: 4242)
        var object = try #require(
            try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(world)) as? [String: Any])

        // Strip every field this change added, the way a real older save has
        // them: absent, not null.
        var settlements = try #require(object["settlements"] as? [[String: Any]])
        settlements[0].removeValue(forKey: "kitchenProgress")
        if var map = settlements[0]["localMap"] as? [String: Any] {
            map.removeValue(forKey: "crops")
            map.removeValue(forKey: "usesEntityFields")
            map.removeValue(forKey: "harvestCredit")
            settlements[0]["localMap"] = map
        }
        object["settlements"] = settlements

        let data = try JSONSerialization.data(withJSONObject: object)
        let loaded = try JSONDecoder().decode(WorldState.self, from: data)
        let map = try #require(loaded.settlements[0].localMap)
        #expect(map.crops.isEmpty)
        #expect(map.usesEntityFields == false)
        #expect(loaded.settlements[0].kitchenProgress == 0)

        // …and it must keep the *old* arithmetic, or a save that has no plots
        // and no per-skill food trickle either simply starves.
        let ticked = TickEngine.advance(loaded, ticks: 300, registry: reg).state
        #expect(ticked.settlements[0].population > 0)
    }

    @Test("Reconciling the plots never resets a crop that is already growing")
    func reconcileKeepsTheHarvest() throws {
        let reg = try registry()
        var world = GameWorldFactory.newGame(registry: reg, seed: 4242)
        world = TickEngine.advance(world, ticks: 40, registry: reg).state
        var s = world.settlements[0]
        let growing = try #require(s.localMap?.crops.first { $0.growth > 0 })

        s = FarmEngine.reconcile(s, registry: reg)
        let after = try #require(s.localMap?.crops.first { $0.id == growing.id })
        #expect(after.growth == growing.growth)
        #expect(after.species == growing.species)
    }

    @Test("A farm falling into disrepair keeps its fields")
    func disrepairDoesNotEatTheFields() throws {
        let reg = try registry()
        var s = GameWorldFactory.newGame(registry: reg, seed: 4242).settlements[0]
        let before = s.localMap?.crops.count ?? 0
        #expect(before > 0)

        // Run the roof down to nothing. The ground under it does not move.
        for i in s.colony!.placements.indices {
            s.colony!.placements[i].condition = 1
        }
        s = FarmEngine.reconcile(s, registry: reg)
        #expect(s.localMap?.crops.count == before)
    }

    @Test("Nothing ripens under snow")
    func winterStopsGrowth() {
        for species in CropSpecies.allCases {
            #expect(FarmEngine.growthStep(species, season: .winter, temperature: 10) == 0)
            #expect(FarmEngine.growthStep(species, season: .summer, temperature: 20) > 0)
        }
        // …and a hard enough frost stops it whatever the calendar says.
        #expect(FarmEngine.growthStep(.greens, season: .spring, temperature: -20) == 0)
        #expect(FarmEngine.growthStep(.roots, season: .spring, temperature: -5) > 0,
                "roots take a frost that finishes greens")
    }

    /// The reachability question for the *top* of the range, which had no
    /// answer at all: a desert summer is 42° and nothing anywhere read it.
    @Test("Heat stops a crop as surely as frost")
    func heatStopsGrowth() throws {
        let reg = try registry()
        let desert = try #require(reg.biome("desert")).climate
        #expect(desert.temperature(.summer) > CropSpecies.greens.heatCeiling,
                "a desert summer has to reach past a crop's ceiling or the ceiling is decoration")
        #expect(FarmEngine.growthStep(.greens, season: .summer,
                                      temperature: desert.temperature(.summer)) == 0)
        #expect(FarmEngine.growthStep(.roots, season: .summer, temperature: 30) > 0,
                "roots sit in the ground and take the most")
    }

    /// A biome that does not change what a farm plants is a colour.
    @Test("A farm sows what its own country will carry")
    func sowingFollowsTheClimate() throws {
        let reg = try registry()
        let tundra = try #require(reg.biome("tundra")).climate
        let plains = try #require(reg.biome("plains")).climate

        // Tundra spring is −2° and its autumn −4°, against a greens floor of
        // +3. A fixed rotation put a quarter of every northern farm under a
        // crop that grows at an eighth rate.
        #expect(!CropSpecies.greens.thrives(in: tundra))
        #expect(CropSpecies.roots.thrives(in: tundra))
        let north = (0..<8).map { CropSpecies.sown(inPlot: $0, climate: tundra) }
        #expect(!north.contains(.greens), "nobody plants lettuce on the tundra")

        // …and the ordinary country still gets the ordinary rotation, or the
        // fallback has quietly become the rule.
        let home = Set((0..<8).map { CropSpecies.sown(inPlot: $0, climate: plains) })
        #expect(home == Set(CropSpecies.allCases))
    }

    @Test("A farmer reaps the plot they were sent to")
    func theJobIsTheWork() throws {
        let reg = try registry()
        var world = GameWorldFactory.newGame(registry: reg, seed: 4242)
        // Far enough for a crop to have come ripe and the board to have run.
        world = TickEngine.advance(world, ticks: 400, registry: reg).state
        let s = world.settlements[0]

        let farmers = s.pawns.filter { $0.assignedWork == .farming }
        #expect(!farmers.isEmpty)
        let onPlots = farmers.filter { $0.currentJob?.kind == .workPlot }
        #expect(!onPlots.isEmpty, "farmers must be sent to a furrow, not to the farm")

        // Every plot job names a plot that is actually on the map — a job
        // pointing at nothing is a colonist standing on bare ground.
        let plotIDs = Set((s.localMap?.crops ?? []).map(\.id))
        for pawn in onPlots {
            let crop = try #require(pawn.currentJob?.cropID)
            #expect(plotIDs.contains(crop))
            let plot = try #require(s.localMap?.crops.first { $0.id == crop })
            #expect(SiegeField.distance(plot.position, pawn.currentJob!.position) < 0.001,
                    "the job is at the furrow, so the figure drawn there is standing on it")
        }
    }

    @Test("A colony with plots is never offered its old field blobs")
    func plotsRetireTheFieldNodes() throws {
        let reg = try registry()
        let s = GameWorldFactory.newGame(registry: reg, seed: 4242).settlements[0]
        let jobs = JobBoard.post(for: s, registry: reg)
        #expect(jobs.contains { $0.kind == .workPlot })
        // §9.11's mistake, in the one system that had not made it yet: half the
        // farmers sent to an abstract blob that no longer produces anything.
        let fieldNodes = Set((s.localMap?.nodes ?? []).filter { $0.kind == .field }.map(\.position.x))
        #expect(!jobs.contains { $0.kind == .tendDeposit && fieldNodes.contains($0.position.x) })
    }

    @Test("Cooks use up what there is most of")
    func cooksReachForThePile() throws {
        let reg = try registry()
        // A mountain of greens against a handful of everything else. The
        // kitchens may well make one stew while there is still meat for it —
        // that is a kitchen doing its job — but they must not go on burning the
        // scarce staples while the pile they are standing next to grows. This
        // is the failure that buried a colony under 2 852 greens and 17 grain
        // and then killed it: picking the richest meal outright, for ever.
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C00C")!,
                           name: "Kitchen", kind: .capital, pawns: [],
                           buildings: [BuildingInstance(definitionID: "cookhouse")],
                           storageCapacity: .uniform(9999))
        s.stockpile = ["greens": 2000, "grain": 30, "roots": 20, "berries": 20, "meat": 20]

        var reached = 0
        for _ in 0..<40 {
            guard let meal = CookingEngine.best(for: s, registry: reg, hasKitchen: true) else { break }
            if meal.ingredients["greens"] != nil { reached += 1 }
            for (itemID, count) in meal.ingredients {
                s.stockpile[itemID, default: 0] -= count
            }
        }
        #expect(reached > 20, "only \(reached) of 40 pots touched the pile")
        #expect(s.stockpile["greens", default: 0] < 2000, "the pile went down")
        #expect(s.stockpile["grain", default: 0] > 0, "and the last of the grain survived")
    }

    @Test("More harvest than roof goes over")
    func theShelfHasACeiling() throws {
        let reg = try registry()
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-0000-00000000500F")!,
                           name: "Full", kind: .capital, pawns: [], storageCapacity: .uniform(100))
        s.stockpile = ["grain": 400, "greens": 400, "iron_ore": 400]
        s = CookingEngine.spoil(s, registry: reg, tick: 0)

        let food = CookingEngine.foodstuffs(reg).reduce(0) { $0 + s.stockpile[$1, default: 0] }
        #expect(food <= 100, "the granary is a claim on how much can be kept")
        #expect(s.stockpile["iron_ore"] == 400, "and it is a claim about food, not about ore")
    }
}
