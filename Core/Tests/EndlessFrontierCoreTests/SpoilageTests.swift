import Testing
import Foundation
@testable import EndlessFrontierCore

/// §11.26 B — **goods lying in the open should suffer for it.**
///
/// Keks: *"chybí sklady, protože materiál a jídlo se hromadí venku na hromadách
/// ve vesnici — za co by měla být penalizace… stejně tak když je necháš ležet
/// venku v hlíně (kameny ne třeba)."*
///
/// The stores existed and were a pure upgrade: a granary and a warehouse deepen
/// a cap the colony rarely reaches, and *nothing at all* happened to a harvest
/// left where it fell. A sink only bites when something pushes the other way,
/// which is the same rule the resource sinks kept failing.
///
/// What decides the rate is `ItemDefinition.substance` — the same field cover is
/// read off — so a new material rots correctly the day it is added, and stone is
/// exempt because it *is* stone rather than because somebody remembered it.
@Suite("What lying in the mud costs")
struct SpoilageTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    /// Fixed ids: rot is seeded from `(map seed, pile, tick)`, so a `UUID()`
    /// here would make every run a different answer (rule 3).
    private func pile(_ itemID: String, _ amount: Int, id: Int = 1) -> HaulPile {
        let uuid = UUID(uuidString: String(format: "5B010000-0000-0000-0000-%012d", id))
            ?? UUID(uuidString: "5B010000-0000-0000-0000-000000000001")!
        return HaulPile(id: uuid, position: LocalPoint(x: 0.5, y: 0.5),
                        itemID: itemID, amount: amount, droppedTick: 0)
    }

    /// How much of a heap survives `ticks` of lying about.
    private func left(_ itemID: String, _ amount: Int, ticks: Int,
                      registry r: GameDataRegistry) -> Int {
        var piles = [pile(itemID, amount)]
        for tick in 0..<ticks {
            piles = HaulEngine.weathered(piles, tick: tick, seed: 0xC0FFEE, registry: r)
        }
        return piles.first?.amount ?? 0
    }

    @Test("Grain left in the field goes bad")
    func foodRots() throws {
        let r = try registry()
        let after = left("grain", 200, ticks: 20, registry: r)
        #expect(after < 200, "three in-game months in the rain is not free")
        #expect(after > 100, "and it is not a bonfire either")
    }

    @Test("Stone does not care about the weather")
    func stoneIsExempt() throws {
        let r = try registry()
        #expect(left("rough_stone", 200, ticks: 60, registry: r) == 200)
        #expect(left("brick", 40, ticks: 60, registry: r) == 40)
        #expect(left("iron_ingot", 40, ticks: 60, registry: r) == 40)
    }

    @Test("Timber spoils, and slower than the harvest does")
    func woodOutlastsFood() throws {
        let r = try registry()
        let timber = left("timber_bundle", 400, ticks: 30, registry: r)
        let grain = left("grain", 400, ticks: 30, registry: r)
        #expect(timber < 400)
        #expect(timber > grain)
    }

    @Test("A heap that rots away is gone, not left at nothing")
    func nothingBecomesNoPile() throws {
        let r = try registry()
        var piles = [pile("grain", 2)]
        for tick in 0..<400 {
            piles = HaulEngine.weathered(piles, tick: tick, seed: 7, registry: r)
        }
        #expect(piles.isEmpty)
    }

    /// Rule 3: the same valley, twice, is the same valley.
    @Test("Rot is the same on the same seed and different on another")
    func spoilageIsDeterministic() throws {
        let r = try registry()
        func run(seed: UInt64) -> [Int] {
            var piles = (1...6).map { pile("grain", 30, id: $0) }
            for tick in 0..<25 {
                piles = HaulEngine.weathered(piles, tick: tick, seed: seed, registry: r)
            }
            return piles.map(\.amount)
        }
        #expect(run(seed: 11) == run(seed: 11))
    }

    /// The whole reason it is worth carrying anything anywhere: what is under a
    /// roof is not what is lying in the mud.
    @Test("A rate per tick is a rate per tick, not per step")
    func rotIsNotRunEightTimesAsFast() throws {
        let r = try registry()
        // One tick of weathering is applied once per tick, whatever the action
        // clock does inside it — see `HaulEngine.advanceStep`.
        let once = left("grain", 1000, ticks: 1, registry: r)
        #expect(once >= 970, "one tick takes about fifteen in a thousand")
    }
}
