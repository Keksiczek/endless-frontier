import Testing
import Foundation
@testable import EndlessFrontierCore

/// **The wild has to be moving when you look at it.**
///
/// Keks, watching a valley: *"zvířata se teď po mapě nepohybují."* They did —
/// a grazing beast covered its whole stride in **one** action step and then
/// stood still for the other seventy-nine before it next thought, which is one
/// and a half real seconds of movement in every twenty real minutes. The
/// distance was right and the *rate* was in the wrong unit (rule 34).
@Suite("A wild that is moving when you look at it")
struct WildMotionTests {

    static func valley(_ count: Int) -> LocalMap {
        var animals: [Animal] = []
        for i in 0..<count {
            animals.append(Animal(
                id: UUID(uuidString: String(format: "00000000-0000-0000-BEA5-%012d", i))!,
                species: "deer", sex: i.isMultiple(of: 2) ? .female : .male, age: 200))
        }
        return LocalMap(river: RiverShape(baseY: 0.8, amplitude: 0, phase: 0),
                        nodes: [], pois: [],
                        wildlife: WildlifeState(deerHerd: 0, deerCapacity: 0,
                                                animals: animals, usesEntities: true),
                        terrainSeed: 99, trees: [], rocks: [])
    }

    @Test("A grazing beast is somewhere different a minute later")
    func theHerdDrifts() {
        let map = AnimalEngine.roam(Self.valley(8), tick: 0)
        let start = WorldClock(tick: 0, step: 0).absoluteStep
        // A third of the way to the next think — well inside one real minute.
        let soon = Double(start) + Double(AnimalEngine.thinkInterval
                                          * WorldClock.actionStepsPerTick) / 3

        var moved = 0
        for beast in map.wildlife.animals {
            let a = beast.position(at: Double(start))
            let b = beast.position(at: soon)
            if SiegeField.distance(a, b) > 0.0005 { moved += 1 }
        }
        #expect(moved >= map.wildlife.animals.count / 2,
                "only \(moved) of \(map.wildlife.animals.count) had moved a minute in")
    }

    @Test("A grazing stride lasts until the beast next thinks")
    func theStrideFillsTheThink() {
        let map = AnimalEngine.roam(Self.valley(6), tick: 0)
        let span = AnimalEngine.thinkInterval * WorldClock.actionStepsPerTick
        for beast in map.wildlife.animals where beast.activity != .fleeing {
            let walk = try? #require(beast.walk)
            guard let walk else { continue }
            #expect(walk.arrivesAt - walk.leftAt == span,
                    "a graze takes \(walk.arrivesAt - walk.leftAt) steps of \(span)")
        }
    }

    @Test("A bolt is still a bolt")
    func flightIsFast() {
        // A wolf in the middle of the herd: the deer round it should run, and
        // running is not a twenty-minute amble.
        var map = Self.valley(8)
        var wolf = Animal(id: UUID(uuidString: "00000000-0000-0000-BEA5-FFFFFFFFFFFF")!,
                          species: "wolf", sex: .male, age: 200)
        wolf.position = LocalPoint(x: 0.5, y: 0.52)
        map.wildlife.animals.append(wolf)
        for index in map.wildlife.animals.indices where map.wildlife.animals[index].species == "deer" {
            map.wildlife.animals[index].position = LocalPoint(x: 0.52, y: 0.53)
        }
        let after = AnimalEngine.roam(map, tick: 0)
        let span = AnimalEngine.thinkInterval * WorldClock.actionStepsPerTick
        let bolting = after.wildlife.animals.filter { $0.activity == .fleeing }
        for beast in bolting {
            guard let walk = beast.walk else { continue }
            #expect(walk.arrivesAt - walk.leftAt < span,
                    "a bolt took the whole think, which is not a bolt")
        }
    }
}
