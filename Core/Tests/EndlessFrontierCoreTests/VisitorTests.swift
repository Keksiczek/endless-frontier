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

    private func run(_ world: WorldState, ticks: Int) -> WorldState {
        var w = world
        for _ in 0..<ticks {
            w = VisitorEngine.advanceOneTick(w, registry: registry(), mapSeed: w.mapSeed)
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
            w = VisitorEngine.advanceOneTick(w, registry: registry(), mapSeed: w.mapSeed)
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
            w = VisitorEngine.advanceOneTick(w, registry: registry(), mapSeed: w.mapSeed)
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

    @Test("An envoy's visit is a diplomatic one, not a market day")
    func anEnvoyIsNotATrader() {
        var s = world(tribes: []).settlements[0]
        let entry = LocalPoint(x: 0.5, y: 0.02)
        let envoy = Visitor(id: UUID(), kind: .envoy, fromName: "Kamenní",
                            position: entry, entry: entry)
        let before = s.storage[.materials]
        s = VisitorEngine.settle(s, visitor: envoy, tick: 10)
        #expect(s.storage[.materials] == before)
        #expect(s.storage[.influence] > 0)
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
