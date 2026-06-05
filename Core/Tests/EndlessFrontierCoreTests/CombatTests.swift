import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Combat — colonist militia")
struct CombatTests {
    private func armedPawn(_ name: String, health: Double = 100) -> Pawn {
        var p = Pawn(name: name, health: health)
        p.equipment[.weapon] = ItemInstance(definitionID: "sturdy_axe")
        return p
    }

    @Test("Armed colonists provide more militia defense than unarmed")
    func armedStronger() {
        let unarmed = EffectApplier.militiaDefense([Pawn(name: "A")])
        let armed = EffectApplier.militiaDefense([armedPawn("B")])
        #expect(armed > unarmed)
        #expect(unarmed > 0)
    }

    @Test("Broken or dead colonists do not fight")
    func nonCombatants() {
        var broken = Pawn(name: "X"); broken.isBroken = true
        let dead = Pawn(name: "Y", health: 0)
        #expect(EffectApplier.militiaDefense([broken, dead]) == 0)
    }

    @Test("An armed garrison repels a raid that overruns an unarmed one")
    func armedRepels() {
        let reg = Fixtures.registry()
        func world(armed: Bool) -> WorldState {
            let pawns = (0..<4).map { armed ? armedPawn("P\($0)") : Pawn(name: "P\($0)") }
            var capital = Settlement(name: "C", kind: .capital, population: 4, pawns: pawns,
                                     storage: [.materials: 100, .food: 100], storageCapacity: 999)
            capital.stats.defense = 0
            return WorldState(settlements: [capital])
        }

        let overrun = EffectApplier.apply([.raid(strength: 25)], to: world(armed: false), registry: reg)
        #expect(overrun.settlements[0].storage[.materials] < 100)   // unarmed → losses

        let held = EffectApplier.apply([.raid(strength: 25)], to: world(armed: true), registry: reg)
        #expect(held.settlements[0].storage[.materials] == 100)     // armed garrison repels
        #expect(held.settlements[0].pawns.allSatisfy { $0.health == 100 })
    }
}
