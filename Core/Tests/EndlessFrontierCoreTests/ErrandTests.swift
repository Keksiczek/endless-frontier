import Testing
import Foundation
@testable import EndlessFrontierCore

/// Needs that cause decisions.
///
/// The colony had needs and they bit, and not one of them ever made anybody do
/// anything: a hungry colonist ate out of the settlement's store wherever they
/// happened to be standing, and warmth went up because a hearth existed
/// somewhere. The properties below are the ones that make the difference real
/// rather than cosmetic — that the food is taken *at the granary*, that getting
/// there costs time, and that a colony which cannot answer a need fails to
/// answer it instead of quietly answering it anyway.
@Suite("Needs send people places")
struct ErrandTests {

    /// The real building data: a granary is a granary because `buildings.json`
    /// says it holds two hundred and fifty, and a hut has a hearth because it
    /// houses people. A fixture registry with two invented buildings in it
    /// would be testing the fixture.
    private let registry: GameDataRegistry = {
        (try? GameDataRegistry.bundled()) ?? GameDataRegistry()
    }()

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "E44A0000-0000-0000-0000-%012d", n))!
    }

    /// A town with a granary in one corner and a hut in the other, so "nearest"
    /// has something to mean.
    private func town(
        souls: Int = 4, food: Double = 500,
        granaryAt: TileCoord? = TileCoord(1, 1)
    ) -> Settlement {
        var s = Settlement(id: id(1), name: "Larder",
                           storage: [.food: food], storageCapacity: 2000)
        s.pawns = (0..<souls).map { Pawn(id: id(100 + $0), name: "Hand \($0)") }
        var colony = ColonyMap(width: 18, height: 18)
        var placements: [BuildingPlacement] = [
            BuildingPlacement(id: id(200), definitionID: "hut",
                              coord: TileCoord(15, 15), width: 2, height: 2)
        ]
        if let granaryAt {
            placements.append(BuildingPlacement(id: id(201), definitionID: "granary",
                                                coord: granaryAt, width: 3, height: 3))
        }
        colony.placements = placements
        s.colony = colony
        return s
    }

    private func hungry(_ s: Settlement, to hunger: Double = 40) -> Settlement {
        var out = s
        for i in out.pawns.indices { out.pawns[i].needs.hunger = hunger }
        return out
    }

    // MARK: - Going for it

    @Test("Hunger past the threshold sends somebody to the granary")
    func hungerPostsAnErrand() {
        let s = ErrandEngine.advanceOneTick(hungry(town()), registry: registry, tick: 0)
        let errand = try? #require(s.pawns[0].errand)
        #expect(errand?.kind == .eat)
        #expect(errand?.placementID == id(201), "to the building that holds the food")
        #expect(s.storage[.food] == 500, "and nothing is eaten before they get there")
    }

    @Test("The meal is taken on arrival, not on the tick it was decided")
    func satisfiedOnArrival() {
        var s = hungry(town())
        s = ErrandEngine.advanceOneTick(s, registry: registry, tick: 0)
        let arrival = try? #require(s.pawns[0].errand?.arrivesAt)
        #expect((arrival ?? 0) > 0, "the granary is across the town, so it takes time")

        // One tick short of it: still walking, still hungry, still nothing gone.
        s = ErrandEngine.advanceOneTick(s, registry: registry, tick: (arrival ?? 1) - 1)
        #expect(s.pawns[0].errand != nil)
        #expect(s.storage[.food] == 500)

        s = ErrandEngine.advanceOneTick(s, registry: registry, tick: arrival ?? 1)
        #expect(s.pawns[0].errand == nil, "they got there")
        #expect(s.pawns[0].needs.hunger > 40, "and ate")
        #expect(s.storage[.food] < 500, "out of the store")
    }

    /// The point of the whole change: distance is a cost the colony pays.
    @Test("A granary on the far side of town is a longer walk")
    func distanceCostsTime() {
        func walk(_ at: TileCoord) -> Int {
            let s = ErrandEngine.advanceOneTick(
                hungry(town(granaryAt: at)), registry: registry, tick: 0)
            let errand = s.pawns[0].errand
            return (errand?.arrivesAt ?? 0) - (errand?.leftAt ?? 0)
        }
        // Everybody is anchored at the middle of town when they have no work
        // and no home of their own, so a granary at the edge is further off.
        #expect(walk(TileCoord(8, 8)) < walk(TileCoord(0, 0)))
    }

    @Test("A colony with nothing in the store feeds nobody")
    func emptyStoreFeedsNobody() {
        let s = ErrandEngine.advanceOneTick(
            hungry(town(food: 0)), registry: registry, tick: 0)
        #expect(s.pawns.allSatisfy { $0.errand == nil },
                "no trip is worth making to an empty granary")
        #expect(s.pawns[0].needs.hunger == 40, "and nobody is fed out of thin air")
    }

    @Test("A colony with no granary yet still eats, at the fire in the middle")
    func youngColonyStillEats() {
        var s = hungry(town(granaryAt: nil))
        for tick in 0..<6 { s = ErrandEngine.advanceOneTick(s, registry: registry, tick: tick) }
        #expect(s.pawns[0].needs.hunger > 40)
        #expect(s.storage[.food] < 500)
    }

    // MARK: - What it costs the colony

    /// Steady-state food upkeep must not move. The meal is bigger and comes
    /// round far less often; the two have to cancel, or moving eating out of
    /// `PawnEngine` would silently start or end a famine (rule 6).
    @Test("Eating at the granary costs the colony what eating always cost")
    func upkeepIsUnchanged() {
        var s = town(souls: 20, food: 4000)
        s.storageCapacity = 8000
        for tick in 0..<600 {
            s = ErrandEngine.advanceOneTick(s, registry: registry, tick: tick)
            s = PawnEngine.advanceOneTick(s, registry: registry, tick: tick)
        }
        let eaten = 4000 - s.storage[.food]
        // The old inline meal: `hungerDecay / hungerPerMeal × foodPerMeal` per
        // person per tick, which is 0.1 — so twenty people over six hundred
        // ticks is about twelve hundred, less whatever they were carrying in
        // hand when the clock stopped.
        let expected = PawnEngine.hungerDecay / PawnEngine.hungerPerMeal
            * PawnEngine.foodPerMeal * 20 * 600
        #expect(abs(eaten - expected) < expected * 0.15,
                "ate \(eaten) against the old \(expected)")
        #expect(s.pawns.allSatisfy { $0.needs.hunger > 0 }, "and nobody starved doing it")
    }

    /// A meal that fills you would let whoever reached the door first take the
    /// last of the granary. A per-tick top-up shared a famine evenly by
    /// construction; a sit-down meal has to be told to.
    @Test("In a famine nobody eats the granary")
    func famineIsShared() {
        var s = hungry(town(souls: 10, food: 6), to: 20)
        for tick in 0..<40 {
            s = ErrandEngine.advanceOneTick(s, registry: registry, tick: tick)
        }
        let fed = s.pawns.count { $0.needs.hunger > 20 }
        #expect(fed >= 5, "only \(fed) of ten got anything at all")
    }

    // MARK: - The cold

    @Test("Somebody cold enough goes to a fire")
    func coldSendsThemToTheHearth() {
        var s = town()
        for i in s.pawns.indices { s.pawns[i].needs.warmth = 20 }
        var out = ErrandEngine.advanceOneTick(s, registry: registry, tick: 0)
        #expect(out.pawns[0].errand?.kind == .warmUp)
        #expect(out.pawns[0].errand?.placementID == id(200), "the hut has the hearth in it")

        let arrival = out.pawns[0].errand?.arrivesAt ?? 1
        out = ErrandEngine.advanceOneTick(out, registry: registry, tick: arrival)
        #expect(out.pawns[0].needs.warmth >= ErrandEngine.hearthWarmth)
    }

    @Test("A person who is both cold and hungry goes for the food")
    func hungerOutranksCold() {
        var s = hungry(town())
        for i in s.pawns.indices { s.pawns[i].needs.warmth = 20 }
        let out = ErrandEngine.advanceOneTick(s, registry: registry, tick: 0)
        #expect(out.pawns[0].errand?.kind == .eat)
    }

    // MARK: - It has to replay identically

    @Test("The same colony sends the same people to the same doors")
    func deterministic() {
        func run() -> [Errand?] {
            var s = hungry(town(souls: 12))
            for tick in 0..<20 { s = ErrandEngine.advanceOneTick(s, registry: registry, tick: tick) }
            return s.pawns.map(\.errand)
        }
        #expect(run() == run())
    }

    @Test("A colonist saved before errands existed is standing still")
    func oldSavesDecode() throws {
        let pawn = Pawn(id: id(9), name: "Old")
        var data = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(pawn)) as? [String: Any] ?? [:]
        data.removeValue(forKey: "errand")
        let back = try JSONDecoder().decode(
            Pawn.self, from: JSONSerialization.data(withJSONObject: data))
        #expect(back.errand == nil)
    }
}
