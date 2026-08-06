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

    @Test("A colony that has forbidden scouting learns nothing new")
    func noScoutsNoReveal() {
        let reg = registry
        var s = world(scouts: 0)
        // Scouting **switched off**, not merely unstaffed.
        //
        // `LaborEngine.rebalance` runs on the engine's own quotas now, whether
        // or not the player has set a policy — which it must, or a trade the
        // colony has no members of can never acquire any, and cooking would
        // have stayed at zero for ever in a town where nobody is idle. The
        // consequence here is that a colony with no scouts *hires* one within
        // a few cadences, so "nobody happens to be scouting" is no longer a
        // state a world can sit in. The thing worth pinning was never the
        // accident; it is that ground does not chart itself without somebody
        // walking it. Saying so out loud is what this policy does.
        s.settlements[0].policy = ColonyPolicy(trades: [.scouting: .off])

        s = TickEngine.advance(s, ticks: 400, registry: reg).state
        // Measured as **scout-work done**, not as fog cleared.
        //
        // `exploredFraction` is not scouting's alone: driving a shaft into the
        // hillside opens ground the colony can see through, and `StoneEngine`
        // says so out loud by inserting those cells itself. With rebalance now
        // following the default quotas, a town of ten farmers acquires miners
        // — so the fog moves for a reason that has nothing to do with anybody
        // walking out to look at it. `scoutProgress` is the honest number here:
        // one step per scout per reveal, and nothing else touches it.
        #expect(s.settlements[0].localMap!.scoutProgress == 0,
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

    /// The corners of the map sit 0.707 from the heart. Reach used to be capped
    /// at 0.62 and a scout's swathe is 0.07 wide, so 0.69 was the furthest ink
    /// could ever reach: the four corners stayed black no matter how many
    /// people you sent or how long you left them at it. A map you can never
    /// finish is a progress bar that lies.
    /// Drives charting on its own, without the life cycle underneath: over the
    /// centuries these tests span, colonists age out and die, so a full
    /// `TickEngine` run measures population churn as much as scouting.
    private func chart(scouts: Int, steps: Int, startTick: Int = 0) -> LocalMap {
        let reg = registry
        var s = world(scouts: scouts).settlements[0]
        // `chartGround` only acts on multiples of its cadence, so land the run
        // on one — otherwise the loop silently does nothing at all.
        let step0 = startTick - startTick % ResourceLoop.scoutTicksPerReveal
        for step in 0...steps {
            s = ResourceLoop.chartGround(s, tick: step0 + step * ResourceLoop.scoutTicksPerReveal,
                                         mapSeed: 7, config: reg.config)
        }
        return s.localMap!
    }

    @Test("A valley can actually be charted to the last corner")
    func cornersAreReachable() {
        let map = chart(scouts: 4, steps: 900)
        #expect(map.isFullyCharted,
                "charted \(Int(map.exploredFraction * 100))% — the corners must be reachable")
    }

    /// Reach used to be derived from the *absolute world tick*, so it measured
    /// how old the world was rather than how far anyone had walked. A colony
    /// founded in year 200 got the run of its valley on day one while the
    /// founding colony crawled — and a settlement's own history counted for
    /// nothing.
    @Test("The frontier moves with work done, not with the world clock")
    func reachComesFromWorkNotClock() {
        // Measured while there is still frontier to move: once a valley is
        // charted both colonies stop, and the step they stop on depends on the
        // seed rather than on anything this test is about.
        let early = chart(scouts: 1, steps: 15)
        let late = chart(scouts: 1, steps: 15, startTick: 20_000)  // founded centuries later
        #expect(!early.isFullyCharted && !late.isFullyCharted)

        #expect(early.scoutProgress == late.scoutProgress,
                "the same scouts working the same span walked the same distance")
        let gap = abs(late.exploredFraction - early.exploredFraction)
        #expect(gap < 0.1,
                "a late-founded colony must not start out knowing more of its valley")
    }

    /// The bug as the player met it: a brand new game, watched for a decade,
    /// where the fog never moved once. `chartGround` needs a scout and the
    /// founding roster had none — scouting's 5% share is the smallest on
    /// `LaborEngine`'s table, so at founding size it lost every comparison.
    @Test("A new game starts with someone whose job is to walk out and look")
    func newGameHasAScout() throws {
        let reg = try GameDataRegistry.bundled()
        let world = GameWorldFactory.newGame(registry: reg)
        let scouts = world.settlements[0].pawns.filter { $0.assignedWork == .scouting }
        #expect(!scouts.isEmpty, "a colony that cannot scout can never chart its own valley")
    }

    @Test("A new game's fog moves within the first years, unattended")
    func newGameFogMovesEarly() throws {
        let reg = try GameDataRegistry.bundled()
        var world = GameWorldFactory.newGame(registry: reg)
        let before = world.settlements[0].localMap!.exploredFraction

        // Ten in-game years: well inside what a player watches before deciding
        // the map is broken.
        world = TickEngine.advance(world, ticks: 10 * reg.config.ticksPerYear, registry: reg).state
        let after = world.settlements[0].localMap!.exploredFraction
        #expect(after > before, "charted \(Int(after * 100))% after a decade — the fog must move")
    }

    /// While there is fog left, the colony keeps someone on it. Losing your last
    /// scout to old age used to stall exploration permanently.
    @Test("A colony replaces a lost scout while ground is left to chart")
    func scoutingIsRestaffed() {
        let reg = registry
        var s = world(scouts: 0, others: 10)
        // Everyone idle: the allocator has a free hand.
        for i in s.settlements[0].pawns.indices {
            s.settlements[0].pawns[i].assignedWork = .idle
        }
        s.settlements[0] = LaborEngine.assignIdleAdults(s.settlements[0], registry: reg)
        #expect(s.settlements[0].pawns.contains { $0.assignedWork == .scouting })
    }

    @Test("Scouts sent somewhere go there, and the order clears once they have")
    func playerCanDirectScouts() {
        let reg = registry
        var s = world(scouts: 4)
        // A corner the wandering range would take an age to reach on its own.
        let target = LocalPoint(x: 0.06, y: 0.94)
        #expect(!s.settlements[0].localMap!.isExplored(target))

        s = GameEngine.sendScouts(s, settlementID: s.settlements[0].id, to: target)
        #expect(s.settlements[0].localMap!.scoutFocus == target)

        s = TickEngine.advance(s, ticks: 120, registry: reg).state
        #expect(s.settlements[0].localMap!.isExplored(target),
                "scouts told where to go must actually go there")
        #expect(s.settlements[0].localMap!.scoutFocus == nil,
                "a finished order is not a standing one")
    }

    @Test("Sending scouts to ground already charted is not an order at all")
    func cannotSendScoutsToKnownGround() {
        var s = world(scouts: 2)
        let home = LocalPoint(x: 0.5, y: 0.5)
        s = GameEngine.sendScouts(s, settlementID: s.settlements[0].id, to: home)
        #expect(s.settlements[0].localMap!.scoutFocus == nil)
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
