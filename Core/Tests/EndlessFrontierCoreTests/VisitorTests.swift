import Testing
import Foundation
@testable import EndlessFrontierCore

/// The world beyond the valley arrives now. These pin the parts that fail
/// silently: nobody ever coming, everybody coming at once, a party that walks
/// in and never leaves, or a visit that pays twice.
@Suite("Somebody is coming up the road")
struct VisitorTests {

    private func registry() -> GameDataRegistry {
        GameDataRegistry(buildings: [], techs: [], eras: [], biomes: [], events: [],
                         config: .default)
    }

    private func world(tribes: [Tribe]) -> WorldState {
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-7715-000000000001")!,
                           name: "Waypoint", regionID: UUID())
        var map = LocalMap(river: RiverShape(baseY: 0.9, amplitude: 0, phase: 0),
                           nodes: [], pois: [])
        map.reveal(around: LocalPoint(x: 0.5, y: 0.5), radius: 2)
        s.localMap = map
        var w = WorldState(settlements: [s], tribes: tribes)
        w.mapSeed = 4242
        return w
    }

    private func tribe(name: String, standing: Double, stores: Double = 500,
                       population: Double = 60, discovered: Bool = true,
                       id: UUID = UUID()) -> Tribe {
        Tribe(id: id, name: name, foundedTick: 0,
              originStory: LocalizedText(values: [.en: "Walked out", .cs: "Odešli"]),
              population: population, genes: Genes(),
              stores: stores, standing: standing, discovered: discovered)
    }

    /// The shape `TickEngine` runs: a party walks on the **action grid**
    /// (`WalkPace`, rule 34) and the world tick settles what they came for.
    /// Driving `advanceOneTick` alone is a valley where nobody ever crosses the
    /// fields, so no party ever reaches the square.
    private func liveTick(_ world: WorldState, registry: GameDataRegistry) -> WorldState {
        var w = world
        for step in 0..<WorldClock.actionStepsPerTick {
            let clock = WorldClock(tick: w.tick, step: step)
            w.settlements = w.settlements.map { VisitorEngine.advanceStep($0, clock: clock) }
        }
        return VisitorEngine.advanceOneTick(w, registry: registry, mapSeed: w.mapSeed)
    }

    private func run(_ world: WorldState, ticks: Int) -> WorldState {
        var w = world
        for _ in 0..<ticks {
            w = liveTick(w, registry: registry())
            w.tick += 1
        }
        return w
    }

    // MARK: - Coming

    @Test("Somebody eventually comes up the road")
    func visitorsArrive() {
        let after = run(world(tribes: [tribe(name: "Kamenní", standing: 40)]), ticks: 600)
        // Either they are still here or they have been and gone — the journal
        // is the record either way.
        #expect(after.settlements[0].journal.entries.contains { $0.kind == .arrival })
    }

    @Test("A valley is not a fairground")
    func partiesAreCapped() {
        let crowd = (0..<6).map { i in tribe(name: "T\(i)", standing: 70) }
        var w = run(world(tribes: crowd), ticks: 400)
        for _ in 0..<10 {
            w = liveTick(w, registry: registry())
            w.tick += 1
            #expect((w.settlements[0].localMap?.visitors.count ?? 0)
                    <= VisitorEngine.maxVisitors)
        }
    }

    @Test("Nobody has heard of a colony nobody has met")
    func theUndiscoveredStayAway() {
        let hidden = tribe(name: "Neznámí", standing: 80, discovered: false)
        let after = run(world(tribes: [hidden]), ticks: 400)
        // A wanderer can still turn up — nobody sends *them* — but no party
        // ever comes from a people the colony has not met.
        let fromHidden = after.settlements[0].localMap?.visitors
            .contains { $0.fromName == "Neznámí" } ?? false
        #expect(!fromHidden)
    }

    // MARK: - Who they send

    @Test("Friends send traders and the wary send envoys")
    func standingDecidesWhoComes() {
        var rng = SeededRNG(seed: 1)
        let friendly = tribe(name: "Blízcí", standing: 70)
        var traders = 0
        for _ in 0..<40 where VisitorEngine.pick(for: friendly, rng: &rng) == .trader {
            traders += 1
        }
        #expect(traders > 20, "a people who like you mostly send goods")

        let tense = tribe(name: "Nedůvěřiví", standing: -40)
        #expect(VisitorEngine.pick(for: tense, rng: &rng) == .envoy)
    }

    @Test("A starving people send their families, whatever they think of you")
    func hungerSendsRefugees() {
        var rng = SeededRNG(seed: 3)
        let starving = tribe(name: "Hladoví", standing: 80, stores: 4, population: 80)
        #expect(VisitorEngine.pick(for: starving, rng: &rng) == .refugee)
    }

    @Test("A traveller from nowhere belongs to nobody")
    func aWandererHasNoPeople() {
        var rng = SeededRNG(seed: 5)
        #expect(VisitorEngine.pick(for: nil, rng: &rng) == .wanderer)
    }

    // MARK: - The visit

    @Test("A party walks in, does its business once, and goes home")
    func aVisitRunsItsCourse() {
        var w = world(tribes: [])
        let entry = LocalPoint(x: 0.02, y: 0.5)
        w.settlements[0].localMap?.visitors = [
            Visitor(id: UUID(uuidString: "00000000-0000-0000-7715-000000000002")!,
                    kind: .trader, fromName: "Kamenní",
                    position: entry, entry: entry)
        ]
        let before = w.settlements[0].storage[.materials]

        // Long enough to walk in, stand a while, and walk back out.
        var reached = false
        var paidTwice = false
        for _ in 0..<200 {
            w = liveTick(w, registry: registry())
            w.tick += 1
            let visitors = w.settlements[0].localMap?.visitors ?? []
            if visitors.contains(where: { $0.phase == .visiting }) { reached = true }
            let gained = w.settlements[0].storage[.materials] - before
            if gained > 200 { paidTwice = true }
            if visitors.isEmpty && reached { break }
        }
        #expect(reached, "they never got to the square")
        #expect(w.settlements[0].localMap?.visitors.isEmpty == true, "they never left")
        #expect(w.settlements[0].storage[.materials] > before, "and the trade paid")
        #expect(!paidTwice, "a visit pays once")
    }

    /// A party crossed the valley one stride per tick, and a tick is two real
    /// minutes — so a visitor stood frozen for two minutes and then jumped.
    /// `position` is still the simulation's answer; the *leg they just walked*
    /// is what the canvas draws, and it has to move between one step and the
    /// next. The same defect, and the same fix, as `Pawn.haulWalk` — and the
    /// stride is measured on the action grid now, so a party approaching is a
    /// party you can watch approach (`WalkPace`).
    @Test("A visitor is somewhere new between one step and the next")
    func theWalkInIsContinuous() {
        var w = world(tribes: [])
        let entry = LocalPoint(x: 0.02, y: 0.5)
        w.settlements[0].localMap?.visitors = [
            Visitor(id: UUID(uuidString: "00000000-0000-0000-7715-000000000009")!,
                    kind: .trader, fromName: "Kamenní",
                    position: entry, entry: entry)
        ]
        w = liveTick(w, registry: registry())

        guard let walk = w.settlements[0].localMap?.visitors.first?.walk else {
            Issue.record("the party took a step without leaving a leg behind")
            return
        }
        let start = Double(walk.leftAt)
        #expect(walk.position(at: start + 0.25) != walk.from,
                "a quarter of a tick in, still on the spot")
        #expect(walk.position(at: start + 0.5) != walk.position(at: start + 0.25),
                "half a tick later, not a step further")
        // The leg ends exactly where the tick put them: the canvas fills in the
        // gap, it does not invent a different answer from the simulation's.
        #expect(walk.to == w.settlements[0].localMap?.visitors.first?.position)
    }

    @Test("A visitor out of a save written before walks had legs stands where they stood")
    func oldSavesStandStill() throws {
        let json = """
        {"id":"00000000-0000-0000-7715-00000000000A","kind":"trader","fromName":"Kamenní",
         "position":{"x":0.3,"y":0.4},"entry":{"x":0.02,"y":0.5},
         "phase":"arriving","ticksRemaining":0,"settled":false}
        """
        let visitor = try JSONDecoder().decode(Visitor.self, from: Data(json.utf8))
        #expect(visitor.walk == nil)
        #expect(visitor.position(at: 12.5) == LocalPoint(x: 0.3, y: 0.4))
    }

    @Test("An envoy's visit is a diplomatic one, not a market day")
    func anEnvoyIsNotATrader() {
        var s = world(tribes: []).settlements[0]
        let entry = LocalPoint(x: 0.5, y: 0.02)
        let envoy = Visitor(id: UUID(), kind: .envoy, fromName: "Kamenní",
                            position: entry, entry: entry)
        let before = s.storage[.materials]
        s = VisitorEngine.settle(s, visitor: envoy, world: world(tribes: []), tick: 10)
        #expect(s.storage[.materials] == before)
        #expect(s.storage[.influence] > 0)
    }

    // MARK: - Word getting around

    /// A colony that is doing well enough to be worth moving to, so the roll is
    /// the only thing left between it and a household on the road.
    private func thriving() -> WorldState {
        var w = world(tribes: [])
        var s = w.settlements[0]
        s.pawns = (0..<6).map {
            Pawn(id: UUID(uuidString: String(format: "00000000-0000-0000-7715-1000%08d", $0))!,
                 name: "Soul \($0)")
        }
        s.storage[.food] = VisitorEngine.settlerFoodPerHead * s.population + 40
        s.stats.morale = 80
        w.settlements[0] = s
        return w
    }

    @Test("A colony worth moving to has people move to it")
    func settlersComeToAGoodColony() {
        let after = run(thriving(), ticks: 900)
        #expect(after.settlements[0].pawns.count > 6,
                "nobody came in fifteen years to a colony doing everything right")
    }

    /// The half that keeps a colony able to fail. Every condition is checked on
    /// its own, because three conditions where one is doing all the work is one
    /// condition with two decorations.
    @Test("Nobody moves to a colony with an empty larder, no beds or no heart")
    func settlersStayAwayFromABadOne() {
        // The baseline is taken *after* the change, because two of these cases
        // work by adding people — measuring against the six the fixture starts
        // with would call the setup itself an arrival.
        func comes(_ change: (inout Settlement) -> Void) -> Bool {
            var w = thriving()
            change(&w.settlements[0])
            let before = w.settlements[0].pawns.count
            return run(w, ticks: 900).settlements[0].pawns.count > before
        }
        #expect(!comes { $0.storage[.food] = 0 }, "they came to a colony with nothing to eat")
        #expect(!comes { $0.stats.morale = 20 }, "they came to a wretched colony")
        #expect(!comes { s in
            // Filled to the rafters: no bed to offer anybody.
            let beds = ResourceLoop.housingCapacity(s, registry: registry())
            s.pawns += (0..<Int(beds)).map { i in
                Pawn(id: UUID(uuidString: String(format: "00000000-0000-0000-7715-2000%08d", i))!,
                     name: "Full \(i)")
            }
            s.storage[.food] = VisitorEngine.settlerFoodPerHead * s.population + 40
        }, "they came to a colony with nowhere to sleep")
    }

    @Test("Settlers put the handcart down and stay")
    func settlersNeverLeave() {
        var w = thriving()
        // Shut the road behind them, so what arrives is the one party placed
        // here and not a second household that heard the same good news. An
        // already-walking party settles regardless — the conditions are checked
        // when somebody sets out, not when they knock.
        w.settlements[0].stats.morale = 20
        let entry = LocalPoint(x: 0.02, y: 0.5)
        w.settlements[0].localMap?.visitors = [
            Visitor(id: UUID(uuidString: "00000000-0000-0000-7715-000000000003")!,
                    kind: .settler, fromName: "downriver",
                    position: entry, entry: entry)
        ]
        for _ in 0..<200 {
            w = liveTick(w, registry: registry())
            w.tick += 1
        }
        #expect(w.settlements[0].localMap?.visitors.isEmpty == true,
                "the party is still standing in the square")
        #expect(w.settlements[0].pawns.count == 6 + VisitorKind.settler.partySize,
                "they left, or they arrived more than once")
    }

    /// The reason this door has no card at all: `StoryPlanner.expireDecisions`
    /// applies none of a decision's effects when the moment passes, so a colony
    /// whose only way to grow needs a tap is a colony that dies whenever nobody
    /// is watching. Growth by arrival has to survive an empty chair.
    @Test("Settlers arrive without anybody answering a card")
    func settlersNeedNoDecision() {
        let after = run(thriving(), ticks: 900)
        #expect(after.pendingEvents.isEmpty, "a settler asked for a decision")
        #expect(after.settlements[0].pawns.count > 6)
    }

    @Test("A traveller now has something to ask")
    func aWandererAsksToStay() throws {
        let bundled = try GameDataRegistry.bundled()
        let asks = try #require(VisitorEngine.decision(for: .wanderer))
        #expect(bundled.events.contains { $0.id == asks },
                "the wanderer asks for an event that is not in the table")
        let template = try #require(bundled.events.first { $0.id == asks })
        #expect(template.choices.contains { choice in
            choice.effects.contains { if case .addPawn = $0 { return true }; return false }
        }, "and none of the answers actually takes them in")
    }

    // MARK: - The rules that must not break

    @Test("Who comes is the same for the same world")
    func arrivalsAreDeterministic() {
        let tribes = [tribe(name: "Kamenní", standing: 45,
                            id: UUID(uuidString: "00000000-0000-0000-7715-0000000000AA")!)]
        let a = run(world(tribes: tribes), ticks: 300)
        let b = run(world(tribes: tribes), ticks: 300)
        #expect(a.settlements[0].localMap?.visitors.map(\.position)
                == b.settlements[0].localMap?.visitors.map(\.position))
        #expect(a.settlements[0].journal.entries.count
                == b.settlements[0].journal.entries.count)
    }

    @Test("They come in from an edge, not out of the middle of town")
    func theyComeFromOutside() {
        var rng = SeededRNG(seed: 9)
        for _ in 0..<30 {
            let p = VisitorEngine.edgePoint(rng: &rng)
            let onEdge = p.x <= 0.03 || p.x >= 0.97 || p.y <= 0.03 || p.y >= 0.97
            #expect(onEdge, "a party appeared at \(p)")
        }
    }

    @Test("A save written before anyone visited has nobody on the road")
    func oldSavesAreEmpty() throws {
        let json = """
        {"river":{"baseY":0.8,"amplitude":0.02,"phase":0},"nodes":[],"pois":[]}
        """
        let map = try JSONDecoder().decode(LocalMap.self, from: Data(json.utf8))
        #expect(map.visitors.isEmpty)
    }
}
