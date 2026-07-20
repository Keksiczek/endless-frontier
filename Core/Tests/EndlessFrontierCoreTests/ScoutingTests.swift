import Testing
import Foundation
@testable import EndlessFrontierCore

/// Reported from a real game: "the settlement map never gets explored and never
/// grows." Literally true — `LocalMap.reveal` was called exactly once in the
/// whole life of a world, by the generator, and never again. The fog was a
/// circle baked at birth.
///
/// And the purest form of this codebase's signature bug sat right next to it:
/// `WorkKind.scouting` is documented `// reveals the fog of war`, `LaborEngine`
/// dutifully staffs it with 5% of every colony's adults — and nothing anywhere
/// did the revealing. At 79 souls, four people had a job that did nothing.
@Suite("Scouts push back the fog")
struct ScoutingTests {
    private func world(scouts: Int, others: Int = 10) -> WorldState {
        var settlement = Settlement(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E5")!,
            name: "Camp", pawns: [], storage: [.food: 900]
        )
        settlement.pawns =
            (0..<scouts).map { i in
                var p = Pawn(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 500 + i))!,
                             name: "Scout \(i)", assignedWork: .scouting)
                p.age = 25 * 60
                return p
            }
            + (0..<others).map { i in
                var p = Pawn(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 600 + i))!,
                             name: "Farmer \(i)", assignedWork: .farming)
                p.age = 25 * 60
                return p
            }
        settlement.localMap = LocalMapGenerator.generate(
            mapSeed: 7, regionID: settlement.id, biome: Fixtures.defaultBiomes[0])
        return WorldState(tick: 0, settlements: [settlement])
    }

    private var registry: GameDataRegistry {
        Fixtures.registry(buildings: [], config: .default)
    }

    @Test("A colony with scouts comes to know more of its own ground")
    func scoutsRevealGround() {
        let reg = registry
        var s = world(scouts: 3)
        let before = s.settlements[0].localMap!.exploredFraction

        s = TickEngine.advance(s, ticks: 400, registry: reg).state
        let after = s.settlements[0].localMap!.exploredFraction

        #expect(after > before, "scouts exist to push the fog back; they must actually do it")
    }

    @Test("A colony with no scouts learns nothing new")
    func noScoutsNoReveal() {
        let reg = registry
        var s = world(scouts: 0)
        let before = s.settlements[0].localMap!.exploredFraction

        s = TickEngine.advance(s, ticks: 400, registry: reg).state
        #expect(s.settlements[0].localMap!.exploredFraction == before,
                "ground doesn't chart itself")
    }

    @Test("More scouts chart faster")
    func scoutsScale() {
        let reg = registry
        var few = world(scouts: 1)
        var many = world(scouts: 6)
        few = TickEngine.advance(few, ticks: 300, registry: reg).state
        many = TickEngine.advance(many, ticks: 300, registry: reg).state
        #expect(many.settlements[0].localMap!.exploredFraction
                > few.settlements[0].localMap!.exploredFraction)
    }

    @Test("The map is finite — scouting settles at fully charted, and stays valid")
    func revealTerminates() {
        let reg = registry
        var s = world(scouts: 20)
        s = TickEngine.advance(s, ticks: 4000, registry: reg).state
        let fraction = s.settlements[0].localMap!.exploredFraction
        #expect(fraction <= 1.0)
        #expect(fraction > 0.5, "a colony working at it for decades should know its own valley")
    }

    /// Presentation must never write the simulation — but the fog is simulation,
    /// so it has to be deterministic like everything else.
    @Test("Charting is deterministic for a seed")
    func revealIsDeterministic() {
        let reg = registry
        let a = TickEngine.advance(world(scouts: 3), ticks: 300, registry: reg).state
        let b = TickEngine.advance(world(scouts: 3), ticks: 300, registry: reg).state
        #expect(a.settlements[0].localMap!.exploredCells == b.settlements[0].localMap!.exploredCells)
    }
}
