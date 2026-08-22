import Testing
import Foundation
@testable import EndlessFrontierCore

/// Keks, watching a raid: *"chovat se že útočí nějak cíleně, ne že teď vedle
/// sebe hýbají dvě čáry lidí a sem tam někdo přiběhne nebo zmizí."*
///
/// Two faults behind one complaint. `aim` re-decided everybody's target from
/// scratch every step off nothing but distance, so as the field moved the
/// nearest enemy kept changing and nobody had an intention that outlived a
/// step; and every raider wanted the same thing, so the whole warband
/// converged into a line facing a line.
@Suite("A warband that came here to do something")
struct SiegeIntentTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    /// A colony with people, roofs and a few years of the council behind it —
    /// a fight between twelve founders is not the fight to measure.
    private func town(_ registry: GameDataRegistry, ticks: Int = 900) -> WorldState {
        var world = GameWorldFactory.newGame(registry: registry, seed: 4242)
        world = TickEngine.advance(world, ticks: ticks, registry: registry).state
        return world
    }

    private func raid(
        _ world: WorldState, strength: Double, registry: GameDataRegistry, seed: UInt64 = 77
    ) -> Settlement? {
        guard var settlement = world.settlements.first else { return nil }
        settlement.siege = nil
        settlement = SiegeEngine.begin(
            settlement, attackerStrength: strength, attackerName: "Test",
            fortification: 10, tick: world.tick, registry: registry, seed: seed)
        return settlement
    }

    // MARK: - Keeping a mark

    /// The hysteresis, asked directly. Somebody a hair's breadth closer is not
    /// a reason to turn your back on the man you are fighting.
    @Test("A fighter does not turn round for somebody marginally nearer")
    func aMarkIsKept() {
        let me = Siege.Combatant(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!,
                                 side: .colony, at: LocalPoint(x: 0.5, y: 0.5),
                                 strength: 100,
                                 target: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!)
        let held = Siege.Combatant(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!,
                                   side: .raider, at: LocalPoint(x: 0.55, y: 0.5), strength: 10)
        let nearer = Siege.Combatant(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!,
                                     side: .raider, at: LocalPoint(x: 0.545, y: 0.5), strength: 10)
        #expect(SiegeEngine.mark(for: me, among: [held, nearer],
                                 horizon: .infinity, preferringWeak: false) == held.id)
    }

    @Test("…and does turn round for somebody decisively nearer")
    func aBetterMarkIsTaken() {
        let mark = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
        let me = Siege.Combatant(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!,
                                 side: .colony, at: LocalPoint(x: 0.5, y: 0.5),
                                 strength: 100, target: mark)
        let held = Siege.Combatant(id: mark, side: .raider,
                                   at: LocalPoint(x: 0.6, y: 0.5), strength: 10)
        let onTop = Siege.Combatant(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!,
                                    side: .raider, at: LocalPoint(x: 0.505, y: 0.5), strength: 10)
        #expect(SiegeEngine.mark(for: me, among: [held, onTop],
                                 horizon: .infinity, preferringWeak: false) == onTop.id)
    }

    @Test("A mark who has fallen out of the fight is not kept")
    func aGoneMarkIsDropped() {
        let me = Siege.Combatant(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!,
                                 side: .colony, at: LocalPoint(x: 0.5, y: 0.5), strength: 100,
                                 target: UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!)
        let other = Siege.Combatant(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!,
                                    side: .raider, at: LocalPoint(x: 0.7, y: 0.5), strength: 10)
        #expect(SiegeEngine.mark(for: me, among: [other],
                                 horizon: .infinity, preferringWeak: false) == other.id)
    }

    /// Somebody with somewhere to be walks past a man three ranks over.
    @Test("Somebody making for the stores only fights what is in the way")
    func ahorizonIsRespected() {
        let me = Siege.Combatant(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!,
                                 side: .raider, at: LocalPoint(x: 0.5, y: 0.5),
                                 strength: 10, intent: .plunder)
        let faraway = Siege.Combatant(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!,
                                      side: .colony, at: LocalPoint(x: 0.9, y: 0.5), strength: 100)
        #expect(SiegeEngine.mark(for: me, among: [faraway],
                                 horizon: SiegeEngine.reach * SiegeEngine.inTheWay,
                                 preferringWeak: true) == nil)
        let blocking = Siege.Combatant(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000D")!,
                                       side: .colony,
                                       at: LocalPoint(x: 0.5 + SiegeEngine.reach, y: 0.5),
                                       strength: 100)
        #expect(SiegeEngine.mark(for: me, among: [faraway, blocking],
                                 horizon: SiegeEngine.reach * SiegeEngine.inTheWay,
                                 preferringWeak: true) == blocking.id)
    }

    // MARK: - A warband is not one thing

    @Test("A warband musters with more than one purpose in it")
    func aWarbandIsMixed() throws {
        let registry = try registry()
        let world = town(registry)
        guard let settlement = raid(world, strength: 60, registry: registry),
              var siege = settlement.siege else { return }
        SiegeEngine.stageIfNeeded(&siege, in: settlement, registry: registry)
        let raiders = siege.fighters.filter { $0.side == .raider }
        #expect(raiders.count > 3, "rule 67: assert the precondition before the finding")
        let intents = Set(raiders.map(\.intent))
        #expect(intents.count > 1,
                "a warband where everybody wants the same thing is two lines facing each other")
        // Everybody who came to burn something came for a particular roof.
        for raider in raiders where raider.intent == .burn {
            #expect(raider.goal != nil)
        }
    }

    @Test("The same raid brings the same warband every time it is replayed")
    func themusterIsDeterministic() throws {
        let registry = try registry()
        let world = town(registry)
        guard let settlement = raid(world, strength: 60, registry: registry),
              var a = settlement.siege, var b = settlement.siege else { return }
        SiegeEngine.stageIfNeeded(&a, in: settlement, registry: registry)
        SiegeEngine.stageIfNeeded(&b, in: settlement, registry: registry)
        #expect(a.fighters.map(\.intent) == b.fighters.map(\.intent))
        #expect(a.fighters.map(\.goal) == b.fighters.map(\.goal))
    }

    /// A colony with nothing standing has nothing to burn, and a warband that
    /// came to burn nothing must still have somewhere to go.
    @Test("A town with no roofs still gets raided")
    func noRoofsIsNotACrash() throws {
        let registry = try registry()
        var world = town(registry, ticks: 60)
        world.settlements[0].colony?.placements = []
        guard let settlement = raid(world, strength: 30, registry: registry),
              var siege = settlement.siege else { return }
        SiegeEngine.stageIfNeeded(&siege, in: settlement, registry: registry)
        #expect(!siege.fighters.contains { $0.intent == .burn })
    }

    // MARK: - It has to show in the fight

    /// The measurement the whole change is for: how often somebody changed
    /// their mind. Before the hysteresis every fighter re-chose every step.
    @Test("A fight is not everybody changing their mind every step")
    func marksAreStable() throws {
        let registry = try registry()
        let world = town(registry)
        guard var settlement = raid(world, strength: 60, registry: registry) else { return }
        var switches = 0, held = 0
        var previous: [UUID: UUID] = [:]
        for _ in 0..<40 {
            guard settlement.siege?.isFinished == false else { break }
            let to = (settlement.siege?.advancedTo ?? 0) + 1
            settlement = SiegeEngine.fight(settlement, to: to, registry: registry).settlement
            guard let siege = settlement.siege else { break }
            for fighter in siege.fighters where !fighter.down && fighter.target != nil {
                if let was = previous[fighter.id] {
                    if was == fighter.target { held += 1 } else { switches += 1 }
                }
                previous[fighter.id] = fighter.target
            }
        }
        #expect(held + switches > 50, "rule 67: nothing was recorded is not the same as nothing happened")
        let churn = Double(switches) / Double(held + switches)
        #expect(churn < 0.25,
                "\(Int(churn * 100))% of marks changed each step — that is the shimmer, not a fight")
    }

    /// The raid has to arrive at the thing it came for, or an intent is a walk
    /// with a name on it (rule 6, in the fight).
    @Test("Somebody who came for a roof gets nearer to it than they started")
    func intentActuallyMoves() throws {
        let registry = try registry()
        let world = town(registry)
        guard var settlement = raid(world, strength: 90, registry: registry) else { return }
        var opening: [UUID: Double] = [:]
        // The last field seen with people still on it. `conclude` clears the
        // siege off the settlement, so reading `settlement.siege` after the
        // fight is reading nothing — which would make this test pass by
        // measuring an empty list (rule 67).
        var last: Siege?
        for _ in 0..<60 {
            guard settlement.siege?.isFinished == false else { break }
            let to = (settlement.siege?.advancedTo ?? 0) + 1
            settlement = SiegeEngine.fight(settlement, to: to, registry: registry).settlement
            guard let siege = settlement.siege else { break }
            last = siege
            for fighter in siege.fighters where fighter.intent == .burn && !fighter.down {
                guard let goal = fighter.goal else { continue }
                if opening[fighter.id] == nil {
                    opening[fighter.id] = SiegeField.distance(fighter.at, goal)
                }
            }
        }
        let siege = try #require(last)
        #expect(!opening.isEmpty, "no arsonist ever stood on the field — nothing was measured")
        var closed = 0, total = 0
        for fighter in siege.fighters where fighter.intent == .burn {
            guard let goal = fighter.goal, let began = opening[fighter.id] else { continue }
            total += 1
            if SiegeField.distance(fighter.at, goal) < began { closed += 1 }
        }
        #expect(total > 0)
        #expect(closed > total / 2,
                "\(closed) of \(total) came for a roof and only that many walked toward it")
    }
}
