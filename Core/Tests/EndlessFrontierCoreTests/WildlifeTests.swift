import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Wildlife")
struct WildlifeTests {
    private let registry = Fixtures.registry()

    private func settlement(
        hunters: Int = 0,
        wildlife: WildlifeState = WildlifeState(),
        defense: Double = 0,
        pawns extra: [Pawn] = []
    ) -> Settlement {
        let huntPawns = (0..<hunters).map { i in
            Pawn(id: UUID(uuidString: String(format: "00000000-0000-0000-0E0E-%012d", i + 1))!,
                 name: "Hunter \(i)", skills: [.hunting: 6], assignedWork: .hunting)
        }
        let map = LocalMap(river: RiverShape(baseY: 0.8, amplitude: 0.03, phase: 0),
                           nodes: [], pois: [], wildlife: wildlife)
        // A fixed id keeps the per-settlement wildlife RNG stream stable, so
        // determinism tests compare like with like.
        return Settlement(id: UUID(uuidString: "00000000-0000-0000-0EEE-000000000001")!,
                          name: "Hunt Camp", kind: .capital, pawns: huntPawns + extra,
                          storage: [.food: 200], storageCapacity: 9999,
                          stats: SettlementStats(defense: defense), localMap: map)
    }

    @Test("The herd grows logistically toward capacity when unhunted")
    func herdGrows() {
        var s = settlement(hunters: 0, wildlife: WildlifeState(deerHerd: 20, deerCapacity: 80))
        for tick in 0..<100 {
            s = WildlifeEngine.advanceOneTick(s, registry: registry, tick: tick,
                                              era: .earlySettlement, mapSeed: 1)
        }
        #expect(s.localMap!.wildlife.deerHerd > 20)
        #expect(s.localMap!.wildlife.deerHerd <= 80)
    }

    @Test("Hunters cull the herd")
    func huntingCulls() {
        let s = settlement(hunters: 5, wildlife: WildlifeState(deerHerd: 80, deerCapacity: 80))
        let after = WildlifeEngine.advanceOneTick(s, registry: registry, tick: 20,
                                                  era: .earlySettlement, mapSeed: 1)
        #expect(after.localMap!.wildlife.deerHerd < 80)
    }

    @Test("Hunting yield scales with the herd, never to zero")
    func huntingFactorScales() {
        #expect(WildlifeEngine.huntingFactor(WildlifeState(deerHerd: 80, deerCapacity: 80)) == 1.0)
        let thin = WildlifeEngine.huntingFactor(WildlifeState(deerHerd: 0, deerCapacity: 80))
        #expect(thin == WildlifeEngine.huntFloorFactor)
        #expect(thin > 0)
    }

    @Test("Predator pressure climbs with the era")
    func pressureClimbsByEra() {
        var early = settlement(wildlife: WildlifeState(predatorPressure: 5))
        var late = settlement(wildlife: WildlifeState(predatorPressure: 5))
        for tick in 0..<500 {
            early = WildlifeEngine.advanceOneTick(early, registry: registry, tick: tick,
                                                  era: .earlySettlement, mapSeed: 2)
            late = WildlifeEngine.advanceOneTick(late, registry: registry, tick: tick,
                                                 era: .modern, mapSeed: 2)
        }
        #expect(late.localMap!.wildlife.predatorPressure > early.localMap!.wildlife.predatorPressure)
    }

    @Test("Strong defenses fend off predators — no beast deaths")
    func defenseRepelsPredators() {
        // High pressure + strong walls: colonists should not be killed by beasts.
        var s = settlement(wildlife: WildlifeState(predatorPressure: 100), defense: 100,
                           pawns: [Pawn(name: "Guard", health: 50)])
        for tick in 0..<500 {
            s = WildlifeEngine.advanceOneTick(s, registry: registry, tick: tick,
                                              era: .modern, mapSeed: 3)
        }
        #expect(s.deathTallies[PawnDeathCause.beast.rawValue, default: 0] == 0)
    }

    /// Rule 12, named for the reachability. Predator pressure is capped by the
    /// era, so the same ten-strong pack came at a colony of five and a colony
    /// of four hundred — and a threat that does not answer the thing it
    /// threatens is scenery. Measured before this: the first thirty years of a
    /// real world gave four fights and a worst wound of nothing at all.
    @Test("The wild answers a colony that has grown")
    func packScalesWithTheColony() {
        func packStrength(colonists: Int) -> Double {
            var s = settlement(wildlife: WildlifeState(predatorPressure: 100),
                               pawns: (0..<colonists).map { i in
                Pawn(id: UUID(uuidString: String(
                    format: "00000000-0000-0000-0E0F-%012d", i + 1))!, name: "Hand \(i)")
            })
            for tick in 0..<3000 {
                s = WildlifeEngine.advanceOneTick(s, registry: registry, tick: tick,
                                                  era: .earlySettlement, mapSeed: 31)
                if let siege = s.siege { return siege.openingStrength }
                s.localMap?.wildlife.predatorPressure = 100
            }
            return 0
        }
        let small = packStrength(colonists: 8)
        let big = packStrength(colonists: 120)
        #expect(small > 0 && big > 0, "no pack ever came")
        #expect(big > small * 2, "a town of a hundred and twenty drew the same wolves as eight")
    }

    @Test("Wildlife evolution is deterministic")
    func deterministic() {
        func run() -> WildlifeState {
            var s = settlement(hunters: 2, wildlife: WildlifeState(deerHerd: 50, deerCapacity: 80,
                                                                   predatorPressure: 40))
            for tick in 0..<300 {
                s = WildlifeEngine.advanceOneTick(s, registry: registry, tick: tick,
                                                  era: .medieval, mapSeed: 9)
            }
            return s.localMap!.wildlife
        }
        #expect(run() == run())
    }
}
