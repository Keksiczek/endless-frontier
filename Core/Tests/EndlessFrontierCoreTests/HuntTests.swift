import Testing
import Foundation
@testable import EndlessFrontierCore

/// The wild walks its own valley, and the hunt is an encounter with a named
/// beast rather than arithmetic on a number called `deerHerd`.
@Suite("The wild moves and the hunt is a fight")
struct HuntTests {

    private func mapWith(_ animals: [Animal], seed: UInt64 = 99) -> LocalMap {
        var map = LocalMap(river: RiverShape(baseY: 0.8, amplitude: 0, phase: 0),
                           nodes: [], pois: [],
                           wildlife: WildlifeState(deerHerd: 40, deerCapacity: 80,
                                                   animals: animals, usesEntities: true),
                           terrainSeed: seed)
        map.reveal(around: LocalPoint(x: 0.5, y: 0.5), radius: 1.5)
        return map
    }

    private func deer(at p: LocalPoint, health: Double? = nil,
                      id: UUID = UUID()) -> Animal {
        Animal(id: id, species: .deer, sex: .female, age: 120,
               health: health, position: p)
    }

    private func hunter(ranged: Double, melee: Double) -> HuntEngine.Hunter {
        HuntEngine.Hunter(id: UUID(), name: "Vlk", ranged: ranged, melee: melee,
                          woundMultiplier: 1)
    }

    // MARK: - Roaming

    /// A beast thinks once every `thinkInterval` ticks and a tick is two real
    /// minutes, so a grazing deer held one pose for **twenty minutes** and then
    /// teleported a stride. `position` is still the simulation's answer — a
    /// hunter walks to *that* — and the leg it just walked is what the canvas
    /// draws, spread over the whole think. Same defect, same fix, as hauling.
    @Test("A beast is somewhere new between one think and the next")
    func theRoamIsContinuous() {
        let map = AnimalEngine.roam(
            mapWith([deer(at: LocalPoint(x: 0.3, y: 0.3)),
                     deer(at: LocalPoint(x: 0.6, y: 0.6))]), tick: 0)
        guard let walk = map.wildlife.animals.first?.walk else {
            Issue.record("a beast moved without leaving a leg behind")
            return
        }
        // **A beast walks its stride and then stops.** It used to be stretched
        // over the whole think — ten world ticks, twenty real minutes — which
        // made a grazing deer a statue and, worse, made a *bolting* one flee
        // for twenty minutes. How far a think moves an animal and how fast it
        // moves are two different questions (`WalkPace`, rule 34), and this is
        // the second one: the crossing takes as long as walking that far takes.
        let legSteps = walk.arrivesAt - walk.leftAt
        #expect(legSteps >= 1)
        #expect(legSteps < AnimalEngine.thinkInterval * WorldClock.actionStepsPerTick,
                "the beast is still smearing one stride over the whole think")
        let start = Double(walk.leftAt)
        #expect(walk.position(at: start + Double(legSteps) * 0.25) != walk.from,
                "a quarter of the way in, still on the spot")
        #expect(walk.position(at: start + Double(legSteps) * 0.5)
                    != walk.position(at: start + Double(legSteps) * 0.25),
                "and no further a quarter later")
        #expect(walk.to == map.wildlife.animals.first?.position)
    }

    @Test("A herd keeps together rather than scattering")
    func herdKeepsTogether() {
        let far = [deer(at: LocalPoint(x: 0.2, y: 0.3)),
                   deer(at: LocalPoint(x: 0.8, y: 0.7)),
                   deer(at: LocalPoint(x: 0.5, y: 0.5))]
        var map = mapWith(far)
        func spread(_ m: LocalMap) -> Double {
            let ps = m.wildlife.animals.map(\.position)
            let cx = ps.reduce(0) { $0 + $1.x } / Double(ps.count)
            let cy = ps.reduce(0) { $0 + $1.y } / Double(ps.count)
            return ps.reduce(0) { $0 + abs($1.x - cx) + abs($1.y - cy) }
        }
        let before = spread(map)
        for tick in stride(from: 0, to: 200, by: AnimalEngine.thinkInterval) {
            map = AnimalEngine.roam(map, tick: tick)
        }
        #expect(spread(map) < before)
    }

    @Test("Prey bolt away from a hunter, not toward one")
    func preyFlee() {
        let threat = LocalPoint(x: 0.5, y: 0.5)
        let start = LocalPoint(x: 0.54, y: 0.5)
        var map = mapWith([deer(at: start)])
        map = AnimalEngine.roam(map, tick: 10, threats: [threat])
        let after = map.wildlife.animals[0]
        #expect(after.activity == .fleeing)
        #expect(after.position.x > start.x)   // away from the threat, not past it
    }

    @Test("A lamed beast lies up instead of roaming")
    func theLameRest() {
        var hurt = deer(at: LocalPoint(x: 0.4, y: 0.4))
        for part in [AnimalBodyPartKind.frontLeftLeg, .frontRightLeg, .backLeftLeg] {
            hurt.injure(part, by: 60)
        }
        var map = mapWith([hurt, deer(at: LocalPoint(x: 0.7, y: 0.7))])
        let before = map.wildlife.animals[0].position
        map = AnimalEngine.roam(map, tick: 20)
        #expect(map.wildlife.animals[0].position == before)
        #expect(map.wildlife.animals[0].activity == .resting)
    }

    @Test("Roaming is deterministic for a seed")
    func roamingIsDeterministic() {
        let animals = [deer(at: LocalPoint(x: 0.3, y: 0.4), id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!),
                       deer(at: LocalPoint(x: 0.6, y: 0.5), id: UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!)]
        let a = AnimalEngine.roam(mapWith(animals), tick: 40)
        let b = AnimalEngine.roam(mapWith(animals), tick: 40)
        #expect(a.wildlife.animals.map(\.position) == b.wildlife.animals.map(\.position))
    }

    // MARK: - The hunt

    @Test("A hunter only meets a beast that is actually near them")
    func theHuntNeedsSomethingToHunt() {
        let far = mapWith([deer(at: LocalPoint(x: 0.95, y: 0.95))])
        let party = [hunter(ranged: 8, melee: 2)]
        let bag = HuntEngine.run(far, hunters: party,
                                 at: [party[0].id: LocalPoint(x: 0.1, y: 0.1)],
                                 tick: 10, seed: 5)
        #expect(bag.kills.isEmpty)
        #expect(bag.map.wildlife.animals.count == 1)
    }

    @Test("A kill takes that beast off the map and yields its meat")
    func aKillIsACarcass() {
        // A whole party at point-blank range: something dies.
        let herd = (0..<6).map { i in
            deer(at: LocalPoint(x: 0.5 + Double(i) * 0.005, y: 0.5))
        }
        let party = (0..<4).map { _ in hunter(ranged: 12, melee: 2) }
        var posts: [UUID: LocalPoint] = [:]
        for h in party { posts[h.id] = LocalPoint(x: 0.5, y: 0.5) }
        let bag = HuntEngine.run(mapWith(herd), hunters: party, at: posts,
                                 tick: 30, seed: 77)
        #expect(!bag.kills.isEmpty)
        #expect(bag.map.wildlife.animals.count == 6 - bag.kills.count)
        #expect(bag.meat > 0)
        #expect(bag.hides == bag.kills.count)
    }

    @Test("Two hunters never take the same deer")
    func noTwoHuntersShareAQuarry() {
        let one = deer(at: LocalPoint(x: 0.5, y: 0.5))
        let party = [hunter(ranged: 20, melee: 0), hunter(ranged: 20, melee: 0)]
        var posts: [UUID: LocalPoint] = [:]
        for h in party { posts[h.id] = LocalPoint(x: 0.5, y: 0.5) }
        let bag = HuntEngine.run(mapWith([one]), hunters: party, at: posts,
                                 tick: 12, seed: 3)
        #expect(bag.kills.count <= 1)
        #expect(bag.map.wildlife.animals.count + bag.kills.count == 1)
    }

    /// A spear means walking up to it, and a boar that is still standing when
    /// you arrive is the reason hunting is dangerous work.
    @Test("Closing with dangerous game can cost the hunter")
    func dangerousGameFightsBack() {
        let boars = (0..<12).map { i in
            Animal(id: UUID(), species: .boar, sex: .male, age: 200,
                   position: LocalPoint(x: 0.5 + Double(i) * 0.004, y: 0.5))
        }
        let party = (0..<12).map { _ in hunter(ranged: 0, melee: 6) }
        var posts: [UUID: LocalPoint] = [:]
        for h in party { posts[h.id] = LocalPoint(x: 0.5, y: 0.5) }
        let bag = HuntEngine.run(mapWith(boars), hunters: party, at: posts,
                                 tick: 8, seed: 21)
        #expect(!bag.wounds.isEmpty, "twelve spears against twelve boars and nobody got hurt")
    }

    @Test("A bow reaches from cover, so nothing gets a chance to gore you")
    func aBowIsSafe() {
        let boars = (0..<12).map { i in
            Animal(id: UUID(), species: .boar, sex: .male, age: 200,
                   position: LocalPoint(x: 0.5 + Double(i) * 0.004, y: 0.5))
        }
        let party = (0..<12).map { _ in hunter(ranged: 10, melee: 1) }
        var posts: [UUID: LocalPoint] = [:]
        for h in party { posts[h.id] = LocalPoint(x: 0.5, y: 0.5) }
        let bag = HuntEngine.run(mapWith(boars), hunters: party, at: posts,
                                 tick: 8, seed: 21)
        #expect(bag.wounds.isEmpty)
    }

    @Test("The wounded one that got away is wounded, and running")
    func aWoundedBeastFlees() {
        // A single melee hunter against a healthy deer: whatever the roll, the
        // beast either dies or is hurt and moving.
        let start = LocalPoint(x: 0.5, y: 0.5)
        let party = [hunter(ranged: 0, melee: 1)]
        let bag = HuntEngine.run(mapWith([deer(at: LocalPoint(x: 0.52, y: 0.5))]),
                                 hunters: party, at: [party[0].id: start],
                                 tick: 6, seed: 2)
        if let survivor = bag.map.wildlife.animals.first {
            #expect(survivor.activity == .fleeing)
            #expect(survivor.position.x > 0.52)
            #expect(survivor.health < survivor.species.baseHealth)
        } else {
            #expect(bag.kills.count == 1)
        }
    }

    // MARK: - The herd number is a view now

    @Test("The old herd count follows the beasts, not the other way round")
    func theLedgerFollowsTheAnimals() {
        let full = mapWith((0..<20).map { i in
            deer(at: LocalPoint(x: 0.3 + Double(i) * 0.01, y: 0.5))
        })
        let thin = mapWith([deer(at: LocalPoint(x: 0.5, y: 0.5))])
        #expect(WildlifeEngine.mirroredHerd(full.wildlife)
                > WildlifeEngine.mirroredHerd(thin.wildlife))
        // An empty valley reads as empty, which is what stops it feeding anyone.
        let dead = mapWith([])
        #expect(WildlifeEngine.mirroredHerd(dead.wildlife) == 0)
    }

    @Test("A beast from an older save still stands somewhere")
    func oldSavesGetAPlace() throws {
        // A save written before the wild had positions.
        let json = """
        {"id":"00000000-0000-0000-0000-0000000000CC","species":"deer","sex":"female",
         "age":100,"health":90,"body":[],"conditions":[]}
        """
        let animal = try JSONDecoder().decode(Animal.self, from: Data(json.utf8))
        #expect(animal.position.x > 0 && animal.position.x < 1)
        #expect(animal.position.y > 0 && animal.position.y < 1)
        #expect(animal.activity == .grazing)
    }
}
