import Testing
import Foundation
@testable import EndlessFrontierCore

/// The council, and the two hundred frozen years it exists to end.
///
/// Measured before it: a fresh world run for twelve thousand ticks came out
/// with three buildings, no construction ever started, no tech ever researched
/// and still in the first era, while every store sat pinned at the cap. Every
/// link of the chain — research, building, the bench — was reachable only from
/// the UI, so a game whose whole premise is closing it and coming back did not
/// advance at all on its own.
///
/// These are named for that: what must be *reachable* without a player.
@Suite("The council")
struct StewardTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private func world(ticks: Int) throws -> WorldState {
        let reg = try registry()
        return TickEngine.advance(
            GameWorldFactory.newGame(registry: reg, seed: 4242),
            ticks: ticks, registry: reg).state
    }

    // MARK: - The world advances on its own

    /// The one that matters. Everything else here is detail.
    ///
    /// Sixty-seven years rather than fifty, since the council started leaving
    /// the valley. Charting the map and working the ruins costs food, timber
    /// and hands, and meeting the neighbours costs the colony the people who
    /// decide they would rather live with them — so an unattended world reaches
    /// the second era about a decade later than one that never looked over the
    /// hill. That is the trade, and it is the right way round: the canary here
    /// is *frozen*, not *slow*.
    @Test("A world nobody touches actually goes somewhere")
    func theWorldAdvancesUnattended() throws {
        let before = try registry()
        let start = GameWorldFactory.newGame(registry: before, seed: 4242)
        let after = try world(ticks: 4000)

        #expect(after.researchedTechs.count > 0,
                "fifty years and the colony learned nothing")
        #expect(after.era.index > start.era.index,
                "fifty years and the colony is in the same age")
        let built = after.settlements[0].buildings.reduce(0) { $0 + $1.count }
        let had = start.settlements[0].buildings.reduce(0) { $0 + $1.count }
        #expect(built > had, "fifty years and nobody raised a roof")
    }

    /// The colony must still be a going concern in its second century, and the
    /// canary is again *frozen* rather than *slow*.
    ///
    /// It was not. Upkeep is charged per tick as a share of what a building cost
    /// to raise, and at 0.03 a tick — against a year of sixty ticks — a colony
    /// paid **one hundred and eighty per cent of its own price every year** to
    /// keep standing. Measured, seed 4242: twenty-three buildings by year
    /// thirty, materials at 1, and `buildableHere` empty for the next hundred
    /// and seventy years. Not a balance but a trap: the store clamps at zero, so
    /// there was no way back out of it, and the beds could never be raised
    /// however loudly the council asked for them.
    ///
    /// A sink that grows with everything you own, against an income that grows
    /// only when you can afford one of three buildings — rule 6 in the ledger.
    ///
    /// **Solvency, not appetite.** The first version of this asked whether
    /// `buildableHere` was non-empty at the hundredth year, and that is a
    /// different question with a misleading answer: measured, the colony reaches
    /// seventy-nine buildings by year eighty and then wants nothing, because the
    /// repeat cap is `1 + population / 15` and it already has one of everything
    /// it is allowed. Empty because it is **full**, with the material store
    /// pinned at its cap the whole way. A colony that has finished is not a
    /// colony that is frozen — the freeze is *cannot pay*, so pay is what this
    /// measures.
    @Test("A century in, the colony can still afford to build")
    func theEconomyDoesNotSeizeUp() throws {
        let reg = try registry()
        var state = GameWorldFactory.newGame(registry: reg, seed: 4242)
        state = TickEngine.advance(state, ticks: 1800, registry: reg).state   // year 30
        let early = state.settlements[0].buildings.reduce(0) { $0 + $1.count }
        state = TickEngine.advance(state, ticks: 4200, registry: reg).state   // year 100
        let late = state.settlements[0].buildings.reduce(0) { $0 + $1.count }
        #expect(late > early, """
            the colony stood at \(early) buildings in its thirtieth year and \
            \(late) in its hundredth — seventy years of paying to stand still
            """)

        // Could it pay for a roof, if it wanted one? Under the old upkeep it
        // could not have paid for anything at all from year thirty on: the
        // store clamped at zero and stayed there, which is the difference
        // between a colony that has finished and a colony that is trapped.
        //
        // Cheapest by price *then by id* — a `Dictionary`'s order decides
        // nothing here, because two buildings at the same price would otherwise
        // make this a different test between runs.
        let cheapest = try #require(
            reg.buildings.values
                .filter { $0.era == .earlySettlement && $0.cost[.materials] > 0 }
                .min { a, b in
                    a.cost[.materials] == b.cost[.materials]
                        ? a.id < b.id
                        : a.cost[.materials] < b.cost[.materials]
                })
        let held = state.settlements[0].storage[.materials]
        #expect(held >= cheapest.cost[.materials], """
            a hundred years on the colony is holding \(Int(held)) materials and \
            the cheapest thing in the book — a \(cheapest.id) — costs \
            \(Int(cheapest.cost[.materials])). That is the trap, not a balance.
            """)
    }

    /// Housing was the ceiling the whole game sat under: thirty beds, so a
    /// population that oscillated around twenty-six for two centuries.
    @Test("The colony outgrows the beds it started with")
    func housingCeilingLifts() throws {
        let reg = try registry()
        let start = GameWorldFactory.newGame(registry: reg, seed: 4242)
        let opening = ResourceLoop.housingCapacity(start.settlements[0], registry: reg)
        let after = try world(ticks: 3000)
        let now = ResourceLoop.housingCapacity(after.settlements[0], registry: reg)
        #expect(now > opening)
        #expect(after.settlements[0].pawns.count > start.settlements[0].pawns.count)
    }

    /// A granary raises the cap for **everything**, not just for grain — and
    /// the colony has to get around to building one by itself.
    @Test("The store deepens without being told to")
    func storageDeepens() throws {
        let reg = try registry()
        let after = try world(ticks: 3000)
        #expect(after.settlements[0].storageCapacity.total > reg.config.defaultStorageCapacity * 5)
    }

    /// Half the early buildings ask for `timber_bundle`, which only comes off
    /// a bench, from an order nobody was ever placing.
    @Test("The colony keeps its own building materials coming")
    func benchStocksTheShelf() throws {
        let after = try world(ticks: 2000)
        let s = after.settlements[0]
        let madeAny = (s.stockpile["timber_bundle"] ?? 0) > 0
            || s.craftOrders.contains { $0.recipeID == "saw_timber" }
        #expect(madeAny, "nobody ever sawed a plank, so nothing needing one was ever built")
    }

    // MARK: - It never overrules the player

    @Test("A study the player chose is left alone")
    func playerResearchWins() throws {
        let reg = try registry()
        var w = GameWorldFactory.newGame(registry: reg, seed: 7)
        // Something with no prerequisites, so the choice actually takes.
        let chosen = try #require(reg.techs.values
            .filter { $0.requires.isEmpty }
            .map(\.id).sorted().last)
        w = TechEngine.setResearch(w, techID: chosen, registry: reg)
        #expect(w.activeResearch == chosen)
        let after = StewardEngine.chooseResearch(w, registry: reg)
        #expect(after.activeResearch == chosen,
                "the council took the study out of the player's hands")
    }

    @Test("Switched off, the council does nothing at all")
    func stewardCanBeSilenced() throws {
        let reg = try registry()
        var w = GameWorldFactory.newGame(registry: reg, seed: 4242)
        w.stewardEnabled = false
        let after = TickEngine.advance(w, ticks: 3000, registry: reg).state
        #expect(after.activeResearch == nil)
        #expect(after.researchedTechs.isEmpty,
                "the player asked to run it themselves and the council carried on regardless")
    }

    @Test("A colony already building is not given a second project")
    func oneProjectAtATime() throws {
        let reg = try registry()
        let after = try world(ticks: 3000)
        #expect(after.settlements[0].constructions.count <= 1)
    }

    // MARK: - What it chooses

    /// Fields outrank roofs (§11.21), so a fixture about *housing* has to have
    /// its ground already under crop — otherwise the council quite rightly
    /// answers "a farm" and the test is measuring the clause above the one it
    /// means to. Given, not faked: plots come from farms standing, so this hands
    /// the settlement the farms a town that size would have raised.
    private func fed(_ s: Settlement, registry: GameDataRegistry) -> Settlement {
        var fedSettlement = s
        let farms = max(1, FarmEngine.plotsWanted(for: max(1, s.population)))
        fedSettlement.buildings.append(BuildingInstance(
            id: UUID(uuidString: "57E0A2D0-FA13-0000-0000-000000000001")!,
            definitionID: "farm_basic", count: farms))
        var map = fedSettlement.localMap ?? LocalMap(
            river: RiverShape(baseY: 0.5, amplitude: 0.04, phase: 0),
            nodes: [], pois: [])
        map.crops = (0..<farms).map { index in
            Crop(id: index, species: .grain,
                 position: LocalPoint(x: 0.5, y: 0.5),
                 farmID: UUID(uuidString: "57E0A2D0-FA13-0000-0000-000000000001")!)
        }
        fedSettlement.localMap = map
        return fedSettlement
    }

    @Test("A town at its housing ceiling raises a roof")
    func housingComesFirst() throws {
        let reg = try registry()
        var s = Settlement(
            id: UUID(uuidString: "57E0A2D0-0000-0000-0000-000000000001")!,
            name: "Full",
            buildings: [BuildingInstance(
                id: UUID(uuidString: "57E0A2D0-1111-0000-0000-000000000001")!,
                definitionID: "hut")],
            storage: [.materials: 400, .food: 400], storageCapacity: .uniform(500))
        // Filled right up: `housingCapacity` has a base on top of the huts.
        let beds = Int(ResourceLoop.housingCapacity(s, registry: reg))
        for i in 0..<beds {
            var p = Pawn(id: UUID(uuidString: String(
                format: "57E0A2D0-2222-0000-0000-%012d", i))!, name: "H\(i)")
            p.age = 25 * reg.config.ticksPerYear
            s.pawns.append(p)
        }
        s = fed(s, registry: reg)
        var w = GameWorldFactory.newGame(registry: reg, seed: 1)
        w.settlements = [s]
        let pick = try #require(StewardEngine.nextBuilding(for: s, in: w, registry: reg))
        #expect((reg.building(pick)?.housing ?? 0) > 0,
                "\(beds) souls in \(beds) beds and the council built \(pick)")
    }

    /// The two numbers that decide whether a village can ever become a town,
    /// checked against each other rather than one at a time.
    ///
    /// `PopulationEngine.headroomFactor` squares the free fraction of the beds
    /// and `StewardEngine` decides when to raise another roof; either alone
    /// reads fine. Together they were unreachable — births died at two-thirds
    /// full and the council did not sit until ninety-five per cent — and the
    /// colony stood at 82 beds and fifty-five souls for a hundred and eighty
    /// years. This is that arithmetic, written down so it cannot drift apart
    /// again: at the moment the council acts, a couple must still have a real
    /// chance of filling what it builds.
    @Test("The roof is raised while the births can still fill it")
    func theTriggerIsReachable() {
        let atTheTrigger = PopulationEngine.headroomFactor(
            population: StewardEngine.crowdedAbove, capacity: 1)
        #expect(atTheTrigger > 0.15, """
            at the council's trigger a couple breeds at \(atTheTrigger) of vigour \
            — the roof arrives after the births it was meant to house
            """)
    }

    @Test("A town raises a roof before the last bed is taken")
    func roofsComeBeforeTheCeiling() throws {
        let reg = try registry()
        var s = Settlement(
            id: UUID(uuidString: "57E0A2D0-0000-0000-0000-000000000005")!,
            name: "Close",
            storage: [.materials: 400, .food: 400], storageCapacity: .uniform(500))
        let beds = ResourceLoop.housingCapacity(s, registry: reg)
        // Two-thirds housed: nineteen free beds, and a birth rate already down
        // to a ninth of its vigour.
        for i in 0..<Int(beds * 0.67) {
            var p = Pawn(id: UUID(uuidString: String(
                format: "57E0A2D0-5555-0000-0000-%012d", i))!, name: "H\(i)")
            p.age = 25 * reg.config.ticksPerYear
            s.pawns.append(p)
        }
        s = fed(s, registry: reg)
        var w = GameWorldFactory.newGame(registry: reg, seed: 1)
        w.settlements = [s]
        let pick = try #require(StewardEngine.nextBuilding(for: s, in: w, registry: reg))
        #expect((reg.building(pick)?.housing ?? 0) > 0,
                "\(s.pawns.count) souls in \(Int(beds)) beds and the council built \(pick)")
    }

    /// The repeat cap grows with the population and the population is bounded
    /// by the beds, so capping dwellings is "no more huts until there are more
    /// people, and no more people until there are more huts".
    @Test("A colony short of roofs is not held to the repeat cap")
    func roofsAreExemptFromTheRepeatCap() throws {
        let reg = try registry()
        var s = Settlement(
            id: UUID(uuidString: "57E0A2D0-0000-0000-0000-000000000006")!,
            name: "Crowded",
            buildings: [BuildingInstance(
                id: UUID(uuidString: "57E0A2D0-1111-0000-0000-000000000006")!,
                definitionID: "hut", count: 9)],
            storage: [.materials: 400, .food: 400], storageCapacity: .uniform(500))
        for i in 0..<Int(ResourceLoop.housingCapacity(s, registry: reg) * 0.9) {
            var p = Pawn(id: UUID(uuidString: String(
                format: "57E0A2D0-6666-0000-0000-%012d", i))!, name: "H\(i)")
            p.age = 25 * reg.config.ticksPerYear
            s.pawns.append(p)
        }
        var w = GameWorldFactory.newGame(registry: reg, seed: 1)
        w.settlements = [s]
        let allowed = 1 + Int(s.population / StewardEngine.soulsPerRepeatBuilding)
        #expect(allowed < 9, "the cap is not even binding — the test proves nothing")
        #expect(StewardEngine.buildableHere(s, in: w, registry: reg)
            .contains { $0.sleepers > 0 },
                "nine huts and nowhere to sleep, and the council may not build a tenth")
    }

    /// Nine granaries is not an answer to a full granary.
    @Test("A small town does not build nine of the same thing")
    func repeatsAreCapped() throws {
        let reg = try registry()
        var s = Settlement(
            id: UUID(uuidString: "57E0A2D0-0000-0000-0000-000000000002")!,
            name: "Hoard",
            buildings: [BuildingInstance(
                id: UUID(uuidString: "57E0A2D0-1111-0000-0000-000000000002")!,
                definitionID: "granary", count: 9)],
            storage: [.materials: 480, .food: 480], storageCapacity: .uniform(500))
        for i in 0..<8 {
            var p = Pawn(id: UUID(uuidString: String(
                format: "57E0A2D0-3333-0000-0000-%012d", i))!, name: "H\(i)")
            p.age = 25 * reg.config.ticksPerYear
            s.pawns.append(p)
        }
        var w = GameWorldFactory.newGame(registry: reg, seed: 1)
        w.settlements = [s]
        let options = StewardEngine.buildableHere(s, in: w, registry: reg)
        #expect(!options.contains { $0.id == "granary" })
    }

    /// The reserve is a multiple of the *cost*, not a share of the warehouse.
    /// A share of capacity looks reasonable and is a trap: granaries multiply
    /// the cap, the reserve grows with it, and a colony whose income never
    /// changed can suddenly never afford anything again. Measured: capacity
    /// 500 → 2750 and the town stopped building for ten thousand ticks.
    @Test("Deepening the store does not price the colony out of building")
    func reserveDoesNotScaleWithTheWarehouse() throws {
        let reg = try registry()
        func canBuild(capacity: Double) -> Bool {
            var s = Settlement(
                id: UUID(uuidString: "57E0A2D0-0000-0000-0000-000000000003")!,
                name: "Deep", storage: [.materials: 120, .food: 120],
                storageCapacity: .uniform(capacity))
            var p = Pawn(id: UUID(uuidString: "57E0A2D0-4444-0000-0000-000000000001")!,
                         name: "One")
            p.age = 25 * reg.config.ticksPerYear
            s.pawns.append(p)
            var w = GameWorldFactory.newGame(registry: reg, seed: 1)
            w.settlements = [s]
            return !StewardEngine.buildableHere(s, in: w, registry: reg).isEmpty
        }
        #expect(canBuild(capacity: 500))
        #expect(canBuild(capacity: 5000),
                "the same colony with a bigger barn can no longer afford a hut")
    }

    @Test("The council picks the cheapest study it can reach, always the same one")
    func researchChoiceIsDeterministic() throws {
        let reg = try registry()
        let w = GameWorldFactory.newGame(registry: reg, seed: 9)
        let a = StewardEngine.nextTech(for: w, registry: reg)
        let b = StewardEngine.nextTech(for: w, registry: reg)
        #expect(a != nil)
        #expect(a == b)
        // …and it is genuinely the cheapest reachable one.
        let chosen = try #require(a)
        let pick = try #require(reg.tech(chosen))
        for tech in reg.techs.values
        where tech.requires.allSatisfy(w.researchedTechs.contains)
            && !w.researchedTechs.contains(tech.id) {
            #expect(TechEngine.cost(of: pick, in: w, config: reg.config)
                    <= TechEngine.cost(of: tech, in: w, config: reg.config))
        }
    }

    // MARK: - It leaves the valley

    /// The council did three things and none of them was ever *outside*. A
    /// player who never taps the world map therefore saw none of the expedition
    /// content at all — the fog never lifted, the ruins were never worked. All
    /// three paths existed and worked; nothing autonomous called them.
    @Test("A colony nobody steers charts its own map")
    func theFogLifts() throws {
        let reg = try registry()
        let start = GameWorldFactory.newGame(registry: reg, seed: 4242)
        let known = { (w: WorldState) in
            w.regions.count { $0.explorationState != .unknown }
        }
        let after = try world(ticks: 3000)
        #expect(known(after) > known(start),
                "fifty years and the colony never looked over the hill")
    }

    @Test("A colony nobody steers works the landmarks in its own valley")
    func theRuinsGetWorked() throws {
        let reg = try registry()
        var w = GameWorldFactory.newGame(registry: reg, seed: 4242)
        var everSentOut = false
        for _ in 0..<40 {
            w = TickEngine.advance(w, ticks: 60, registry: reg).state
            if !w.settlements[0].expeditions.isEmpty { everSentOut = true; break }
        }
        #expect(everSentOut, "nobody was ever sent to a place in their own valley")
    }

    /// The council must not empty the town. Every dispatch it uses refuses on
    /// its own when the roster says nobody leaves — this pins that the fourth
    /// clause did not find a way round them.
    @Test("A colony that has said nobody leaves sends nobody")
    func theRosterStillHolds() throws {
        let reg = try registry()
        var w = GameWorldFactory.newGame(registry: reg, seed: 4242)
        for index in w.settlements.indices { w.settlements[index].policy.roster = .nobody }
        for _ in 0..<20 {
            w = TickEngine.advance(w, ticks: 60, registry: reg).state
            for index in w.settlements.indices { w.settlements[index].policy.roster = .nobody }
            #expect(w.settlements[0].expeditions.isEmpty)
            #expect(w.regionExpeditions.isEmpty)
        }
    }

    /// The same seed must grow the same colony, and the *first* thing that has
    /// to be true of that is that it starts with the same people.
    ///
    /// `Pawn.init` defaults `id` to a fresh `UUID()`, and the four founders
    /// were taking it — so every launch of the same seed began with four
    /// different people, and since per-entity randomness is derived from
    /// `(mapSeed, entity.id, tick)`, the whole world diverged from tick zero.
    /// Every determinism test in the suite was comparing counts loose enough to
    /// pass on luck. This one compares names and ids.
    @Test("The same seed always founds the same colony")
    func theSameSeedFoundsTheSamePeople() throws {
        let reg = try registry()
        let a = GameWorldFactory.newGame(registry: reg, seed: 4242)
        let b = GameWorldFactory.newGame(registry: reg, seed: 4242)
        #expect(a.settlements[0].pawns.map(\.id) == b.settlements[0].pawns.map(\.id))
        #expect(a.settlements[0].id == b.settlements[0].id)
        #expect(a.tribes.map(\.id) == b.tribes.map(\.id))

        let other = GameWorldFactory.newGame(registry: reg, seed: 99)
        #expect(other.settlements[0].pawns.map(\.id) != a.settlements[0].pawns.map(\.id),
                "…and a different seed founds a different one")
    }

    @Test("Two identical worlds run unattended stay identical")
    func stewardIsDeterministic() throws {
        let a = try world(ticks: 1200)
        let b = try world(ticks: 1200)
        #expect(a.researchedTechs == b.researchedTechs)
        #expect(a.settlements[0].buildings == b.settlements[0].buildings)
        // Names and ids, not a headcount: two worlds can lose the same number
        // of people and not be the same world.
        #expect(a.settlements[0].pawns.map(\.id) == b.settlements[0].pawns.map(\.id))
        #expect(a.tribes.map(\.population) == b.tribes.map(\.population))
        #expect(a.regions.map(\.explorationState) == b.regions.map(\.explorationState))
    }

    @Test("A save written before the council existed switches it on")
    func oldSavesGetACouncil() throws {
        let reg = try registry()
        let w = GameWorldFactory.newGame(registry: reg, seed: 3)
        var object = try #require(try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(w)) as? [String: Any])
        object.removeValue(forKey: "stewardEnabled")
        let back = try JSONDecoder().decode(
            WorldState.self,
            from: try JSONSerialization.data(withJSONObject: object))
        #expect(back.stewardEnabled, "the saves that need it most are the old ones")
    }
}

/// What the council does when a store is at the brim, and how much of the
/// bench it is allowed to take.
@Suite("A council that leaves room")
struct CouncilRoomTests {

    /// A colony holding everything it can hold, with a store to build.
    static func brimming(_ registry: GameDataRegistry) -> WorldState {
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        state.era = .medieval
        state.settlements[0].storage[.materials] =
            state.settlements[0].storageCapacity[.materials]
        return state
    }

    @Test("A colony at its materials cap may raise the store that lifts it")
    func theBrimBeatsTheUpkeepBrake() throws {
        // The brake weighs a building's **materials production** against its
        // upkeep, and a warehouse produces nothing — so a colony pinned at its
        // cap was refused, for ever, the one building that raises the cap.
        let registry = try GameDataRegistry.bundled()
        var state = Self.brimming(registry)
        // Enough standing buildings that the upkeep brake genuinely bites.
        for _ in 0..<12 {
            state.settlements[0].buildings.append(
                BuildingInstance.founding("library", at: state.settlements[0].id, slot: 0))
        }
        // The made things a warehouse is built out of, on the shelf.
        let warehouse = try #require(registry.building("warehouse"))
        for (material, needed) in warehouse.materialCost {
            state.settlements[0].stockpile[material] = needed * 3
        }
        let settlement = state.settlements[0]
        #expect(StewardEngine.brimmingResources(settlement).contains(.materials))
        let able = StewardEngine.buildableHere(settlement, in: state, registry: registry)
        #expect(able.contains { $0.id == "warehouse" },
                "a colony at its cap must be able to raise the store that lifts it")
    }

    @Test("The council shops for what is standing between it and a building")
    func theShoppingListIsOrdered() throws {
        // `wantedMaterials` is a set sorted alphabetically, which against a
        // bench of twelve slots meant the four timber bundles between the
        // colony and a warehouse arrived at a twelfth of the rate — if the
        // alphabet reached them at all.
        let registry = try GameDataRegistry.bundled()
        var state = Self.brimming(registry)
        state.settlements[0].stockpile = [:]
        let list = StewardEngine.shoppingList(for: state.settlements[0], in: state,
                                              registry: registry)
        #expect(!list.isEmpty)
        // Whatever is first must be a material some building the colony wants
        // is actually waiting on.
        let blocking = Set(StewardEngine.wantedHere(state.settlements[0], in: state,
                                                    registry: registry)
            .filter { !GameEngine.hasMaterials($0.materialCost, in: state,
                                               settlementID: state.settlements[0].id) }
            .flatMap { $0.materialCost.keys })
        #expect(blocking.contains(try #require(list.first)),
                "the council's first order is \(list.first ?? "nothing"), which unblocks nothing")
    }

    @Test("A brimming colony reaches for a store, not for something novel")
    func theBrimIsAnswered() throws {
        let registry = try GameDataRegistry.bundled()
        var state = Self.brimming(registry)
        // Fed, housed and with its ground broken, so the clauses above stores
        // fall through and this one gets its turn.
        state.settlements[0].storage[.food] = state.settlements[0].storageCapacity[.food]
        for _ in 0..<40 {
            state.settlements[0].buildings.append(
                BuildingInstance.founding("hut", at: state.settlements[0].id, slot: 0))
        }
        // …and the made things on the shelf, or the whole book is unbuildable
        // and the clause has nothing to choose between.
        for def in registry.buildings.values {
            for (material, needed) in def.materialCost {
                state.settlements[0].stockpile[material] =
                    max(state.settlements[0].stockpile[material, default: 0], needed * 4)
            }
        }
        let pick = StewardEngine.nextBuilding(for: state.settlements[0], in: state,
                                              registry: registry)
        let chosen = pick.flatMap { registry.building($0) }
        #expect(chosen != nil)
        let spilling = StewardEngine.brimmingResources(state.settlements[0])
        #expect(spilling.contains { (chosen?.storage[$0] ?? 0) > 0 },
                "picked \(pick ?? "nothing"), which holds none of \(spilling)")
    }

    @Test("The council never takes the whole bench")
    func theBenchStaysOpen() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        state.era = .medieval
        state.unlockedBuildings = Set(registry.buildings.keys)
        // Run the council's own pass many times over; its standing orders never
        // finish, so without a share it fills every slot and stays there.
        for _ in 0..<40 {
            state = StewardEngine.keepMaterialsComing(state, index: 0, registry: registry)
            state = QuartermasterEngine.advance(state, index: 0, registry: registry)
        }
        let queued = state.settlements[0].craftOrders.count
        #expect(queued <= StewardEngine.councilBenchShare,
                "the council queued \(queued) of \(CraftingEngine.maxOrders)")
        #expect(queued < CraftingEngine.maxOrders,
                "a full bench refuses the player's own orders silently")
    }
}
