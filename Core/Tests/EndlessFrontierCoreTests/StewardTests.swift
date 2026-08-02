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
    @Test("A world nobody touches actually goes somewhere")
    func theWorldAdvancesUnattended() throws {
        let before = try registry()
        let start = GameWorldFactory.newGame(registry: before, seed: 4242)
        let after = try world(ticks: 3000)

        #expect(after.researchedTechs.count > 0,
                "fifty years and the colony learned nothing")
        #expect(after.era.index > start.era.index,
                "fifty years and the colony is in the same age")
        let built = after.settlements[0].buildings.reduce(0) { $0 + $1.count }
        let had = start.settlements[0].buildings.reduce(0) { $0 + $1.count }
        #expect(built > had, "fifty years and nobody raised a roof")
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
        #expect(after.settlements[0].storageCapacity > reg.config.defaultStorageCapacity)
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

    @Test("A town at its housing ceiling raises a roof")
    func housingComesFirst() throws {
        let reg = try registry()
        var s = Settlement(
            id: UUID(uuidString: "57E0A2D0-0000-0000-0000-000000000001")!,
            name: "Full",
            buildings: [BuildingInstance(
                id: UUID(uuidString: "57E0A2D0-1111-0000-0000-000000000001")!,
                definitionID: "hut")],
            storage: [.materials: 400, .food: 400], storageCapacity: 500)
        // Filled right up: `housingCapacity` has a base on top of the huts.
        let beds = Int(ResourceLoop.housingCapacity(s, registry: reg))
        for i in 0..<beds {
            var p = Pawn(id: UUID(uuidString: String(
                format: "57E0A2D0-2222-0000-0000-%012d", i))!, name: "H\(i)")
            p.age = 25 * reg.config.ticksPerYear
            s.pawns.append(p)
        }
        var w = GameWorldFactory.newGame(registry: reg, seed: 1)
        w.settlements = [s]
        let pick = try #require(StewardEngine.nextBuilding(for: s, in: w, registry: reg))
        #expect((reg.building(pick)?.housing ?? 0) > 0,
                "\(beds) souls in \(beds) beds and the council built \(pick)")
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
            storage: [.materials: 480, .food: 480], storageCapacity: 500)
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
                storageCapacity: capacity)
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

    @Test("Two identical worlds run unattended stay identical")
    func stewardIsDeterministic() throws {
        let a = try world(ticks: 1200)
        let b = try world(ticks: 1200)
        #expect(a.researchedTechs == b.researchedTechs)
        #expect(a.settlements[0].buildings == b.settlements[0].buildings)
        #expect(a.settlements[0].pawns.count == b.settlements[0].pawns.count)
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
