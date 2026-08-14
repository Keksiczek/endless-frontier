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
                           storage: [.food: food], storageCapacity: .uniform(2000))
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
        let s = ErrandEngine.advanceStep(hungry(town()), registry: registry, clock: .at(absoluteStep: 0))
        let errand = try? #require(s.pawns[0].errand)
        #expect(errand?.kind == .eat)
        #expect(errand?.placementID == id(201), "to the building that holds the food")
        #expect(s.storage[.food] == 500, "and nothing is eaten before they get there")
    }

    @Test("The meal is taken on arrival, not on the tick it was decided")
    func satisfiedOnArrival() {
        var s = hungry(town())
        s = ErrandEngine.advanceStep(s, registry: registry, clock: .at(absoluteStep: 0))
        let arrival = try? #require(s.pawns[0].errand?.arrivesAt)
        #expect((arrival ?? 0) > 0, "the granary is across the town, so it takes time")

        // One tick short of it: still walking, still hungry, still nothing gone.
        s = ErrandEngine.advanceStep(s, registry: registry, clock: .at(absoluteStep: (arrival ?? 1) - 1))
        #expect(s.pawns[0].errand != nil)
        #expect(s.storage[.food] == 500)

        s = ErrandEngine.advanceStep(s, registry: registry, clock: .at(absoluteStep: arrival ?? 1))
        #expect(s.pawns[0].errand == nil, "they got there")
        #expect(s.pawns[0].needs.hunger > 40, "and ate")
        #expect(s.storage[.food] < 500, "out of the store")
    }

    /// The point of the whole change: distance is a cost the colony pays.
    @Test("A granary on the far side of town is a longer walk")
    func distanceCostsTime() {
        func walk(_ at: TileCoord) -> Int {
            let s = ErrandEngine.advanceStep(
                hungry(town(granaryAt: at)), registry: registry, clock: .at(absoluteStep: 0))
            let errand = s.pawns[0].errand
            return (errand?.arrivesAt ?? 0) - (errand?.leftAt ?? 0)
        }
        // Everybody is anchored at the middle of town when they have no work
        // and no home of their own, so a granary at the edge is further off.
        #expect(walk(TileCoord(8, 8)) < walk(TileCoord(0, 0)))
    }

    @Test("A colony with nothing in the store feeds nobody")
    func emptyStoreFeedsNobody() {
        let s = ErrandEngine.advanceStep(
            hungry(town(food: 0)), registry: registry, clock: .at(absoluteStep: 0))
        #expect(s.pawns.allSatisfy { $0.errand == nil },
                "no trip is worth making to an empty granary")
        #expect(s.pawns[0].needs.hunger == 40, "and nobody is fed out of thin air")
    }

    @Test("A colony with no granary yet still eats, at the fire in the middle")
    func youngColonyStillEats() {
        var s = hungry(town(granaryAt: nil))
        for tick in 0..<6 { s = ErrandEngine.advanceStep(s, registry: registry, clock: .at(absoluteStep: tick)) }
        #expect(s.pawns[0].needs.hunger > 40)
        #expect(s.storage[.food] < 500)
    }

    // MARK: - The walk nobody made

    /// `furthestWorthGoing` is a **comfort** rule, and applied to a need that
    /// kills it was a quiet death sentence with no story attached.
    ///
    /// The valley is a unit square and work happens all over it — a logger's
    /// tree, a scout's fog, a beast being stalked at the treeline — while the
    /// granary stands wherever the town happened to put it. Anybody whose day
    /// took them further than half a map from it simply *never went to eat
    /// again*: the errand was refused every tick, hunger ran to zero, and they
    /// starved beside a full store. Measured over two centuries of seed 4242:
    /// eighteen dead of hunger with the granary at 1148 of 1150.
    ///
    /// Named for the reachability rather than the behaviour (rule 6): can a
    /// colonist standing at the furthest point the game is able to put them
    /// reach the food the colony actually has?
    @Test("A colonist working at the far edge of the valley can still reach the granary")
    func theFurthestWorkerCanStillEat() {
        var s = hungry(town(granaryAt: TileCoord(0, 0)), to: 20)
        // Out at the fog, which is where scouting, hunting and logging take
        // people — and the diagonally opposite corner from the granary.
        for i in s.pawns.indices {
            s.pawns[i].currentJob = Job(id: id(300 + i), kind: .stalkAnimal,
                                        position: LocalPoint(x: 0.98, y: 0.98))
        }
        let start = ErrandEngine.anchor(of: s.pawns[0], in: s, registry: registry)
        let larder = ErrandEngine.places(in: s, registry: registry) { $0.storage[.food] > 0 }
        #expect(larder.contains { SiegeField.distance(start, $0.at)
                                    > ErrandEngine.furthestWorthGoing },
                "the fixture has to actually put the food out of comfortable reach")

        var out = ErrandEngine.advanceStep(s, registry: registry, clock: .at(absoluteStep: 0))
        let errand = out.pawns[0].errand
        #expect(errand?.kind == .eat, "starving is not a reason to stay put")

        let arrival = errand?.arrivesAt ?? 1
        out = ErrandEngine.advanceStep(out, registry: registry, clock: .at(absoluteStep: arrival))
        #expect(out.pawns[0].needs.hunger > 20, "and they ate when they got there")
        #expect(out.storage[.food] < 500, "out of the store that was full all along")
    }

    /// The other half of the same rule: the cap still has to *mean* something,
    /// or every mild twinge sends the whole colony walking and no work is done.
    @Test("A merely peckish colonist that far out stays where they are")
    func theFurthestWorkerDoesNotStrollForASnack() {
        var s = hungry(town(granaryAt: TileCoord(0, 0)),
                       to: ErrandEngine.hungryBelow - 1)
        for i in s.pawns.indices {
            s.pawns[i].currentJob = Job(id: id(300 + i), kind: .stalkAnimal,
                                        position: LocalPoint(x: 0.98, y: 0.98))
        }
        let out = ErrandEngine.advanceStep(s, registry: registry, clock: .at(absoluteStep: 0))
        #expect(out.pawns.allSatisfy { $0.errand == nil })
    }

    /// Freezing is the same shape, and would have been the same bug the first
    /// winter somebody worked the far hedge.
    @Test("A colonist freezing at the far edge can still reach a fire")
    func theFurthestWorkerCanStillGetWarm() {
        var s = town(granaryAt: nil)
        for i in s.pawns.indices {
            s.pawns[i].needs.warmth = ComfortEngine.freezingBelow - 4
            s.pawns[i].currentJob = Job(id: id(300 + i), kind: .fellTree,
                                        position: LocalPoint(x: 0.02, y: 0.02))
        }
        // The hut with the hearth in it stands at the far corner of the grid.
        let out = ErrandEngine.advanceStep(s, registry: registry, clock: .at(absoluteStep: 0))
        #expect(out.pawns[0].errand?.kind == .warmUp)
    }

    // MARK: - What it costs the colony

    /// Steady-state food upkeep must not move. The meal is bigger and comes
    /// round far less often; the two have to cancel, or moving eating out of
    /// `PawnEngine` would silently start or end a famine (rule 6).
    @Test("Eating at the granary costs the colony what eating always cost")
    func upkeepIsUnchanged() {
        var s = town(souls: 20, food: 4000)
        s.storageCapacity = .uniform(8000)
        for tick in 0..<600 {
            s = ErrandEngine.advanceStep(s, registry: registry, clock: .at(absoluteStep: tick))
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
            s = ErrandEngine.advanceStep(s, registry: registry, clock: .at(absoluteStep: tick))
        }
        let fed = s.pawns.count { $0.needs.hunger > 20 }
        #expect(fed >= 5, "only \(fed) of ten got anything at all")
    }

    // MARK: - The cold

    @Test("Somebody cold enough goes to a fire")
    func coldSendsThemToTheHearth() {
        var s = town()
        for i in s.pawns.indices { s.pawns[i].needs.warmth = 20 }
        var out = ErrandEngine.advanceStep(s, registry: registry, clock: .at(absoluteStep: 0))
        #expect(out.pawns[0].errand?.kind == .warmUp)
        #expect(out.pawns[0].errand?.placementID == id(200), "the hut has the hearth in it")

        let arrival = out.pawns[0].errand?.arrivesAt ?? 1
        out = ErrandEngine.advanceStep(out, registry: registry, clock: .at(absoluteStep: arrival))
        #expect(out.pawns[0].needs.warmth >= ErrandEngine.hearthWarmth)
    }

    @Test("A person who is both cold and hungry goes for the food")
    func hungerOutranksCold() {
        var s = hungry(town())
        for i in s.pawns.indices { s.pawns[i].needs.warmth = 20 }
        let out = ErrandEngine.advanceStep(s, registry: registry, clock: .at(absoluteStep: 0))
        #expect(out.pawns[0].errand?.kind == .eat)
    }

    // MARK: - It has to replay identically

    @Test("The same colony sends the same people to the same doors")
    func deterministic() {
        func run() -> [Errand?] {
            var s = hungry(town(souls: 12))
            for tick in 0..<20 { s = ErrandEngine.advanceStep(s, registry: registry, clock: .at(absoluteStep: tick)) }
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
