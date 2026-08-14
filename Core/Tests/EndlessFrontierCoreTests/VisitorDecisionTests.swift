import Testing
import Foundation
@testable import EndlessFrontierCore

/// A party that merely arrived and left again was scenery. A party you have to
/// *answer* is the game. These pin that the ask actually reaches the Leader,
/// that it is authored content rather than code, and that a traveller who wants
/// nothing does not interrupt anyone.
@Suite("A visit you have to answer")
struct VisitorDecisionTests {

    private func registry() throws -> GameDataRegistry {
        try GameDataRegistry.bundled()
    }

    private func world() -> WorldState {
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-A5CD-000000000001")!,
                           name: "Crossroads", regionID: UUID())
        var map = LocalMap(river: RiverShape(baseY: 0.9, amplitude: 0, phase: 0),
                           nodes: [], pois: [])
        map.reveal(around: LocalPoint(x: 0.5, y: 0.5), radius: 2)
        s.localMap = map
        var w = WorldState(settlements: [s])
        w.mapSeed = 77
        return w
    }

    private func send(_ kind: VisitorKind, into world: WorldState) -> WorldState {
        var w = world
        let entry = LocalPoint(x: 0.02, y: 0.5)
        w.settlements[0].localMap?.visitors = [
            Visitor(id: UUID(uuidString: "00000000-0000-0000-A5CD-000000000002")!,
                    kind: kind, fromName: "Kamenní", position: entry, entry: entry)
        ]
        return w
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

    private func run(_ world: WorldState, registry: GameDataRegistry, ticks: Int) -> WorldState {
        var w = world
        for _ in 0..<ticks {
            w = liveTick(w, registry: registry)
            w.tick += 1
        }
        return w
    }

    @Test("Every party that wants something has a decision written for it")
    func decisionsAreAuthored() throws {
        let reg = try registry()
        for kind in VisitorKind.allCases {
            guard let id = VisitorEngine.decision(for: kind) else { continue }
            #expect(reg.events.contains { $0.id == id },
                    "\(kind) asks for '\(id)', which no event provides")
        }
    }

    @Test("Each of those decisions offers real choices, in both languages")
    func decisionsHaveChoices() throws {
        let reg = try registry()
        for kind in VisitorKind.allCases {
            guard let id = VisitorEngine.decision(for: kind),
                  let template = reg.events.first(where: { $0.id == id }) else { continue }
            #expect(template.choices.count >= 2, "\(id) is not a decision, it is an announcement")
            #expect(template.decisionTicks != nil, "\(id) has no deadline")
            for choice in template.choices {
                #expect(!choice.label.resolve(.cs).isEmpty, "\(id)/\(choice.id) has no Czech")
                #expect(!choice.label.resolve(.en).isEmpty, "\(id)/\(choice.id) has no English")
                #expect(choice.label.resolve(.cs) != choice.label.resolve(.en),
                        "\(id)/\(choice.id) was never translated")
            }
        }
    }

    @Test("Refugees at the square put the question to the Leader")
    func refugeesAsk() throws {
        let reg = try registry()
        let after = run(send(.refugee, into: world()), registry: reg, ticks: 40)
        #expect(after.pendingEvents.contains { $0.templateID == "visitors_refugees" })
    }

    /// A traveller used to want nothing, which made them the one visitor who
    /// could not change anything. Some of them have been walking a long time
    /// and would rather stop — and a colony that only ever grows out of its own
    /// cradle decays whatever else is done right (§11.10). So they ask now.
    @Test("A traveller who has walked far enough asks to stay")
    func aWandererAsksToStay() throws {
        let reg = try registry()
        let after = run(send(.wanderer, into: world()), registry: reg, ticks: 40)
        #expect(after.pendingEvents.contains { $0.templateID == "visitors_wanderer" })
    }

    /// The settler is the one who does *not* ask: an unanswered decision
    /// expires with none of its effects applied, so a colony whose only door to
    /// growth needs a tap dies whenever nobody is watching.
    @Test("A household that has already decided asks nobody")
    func aSettlerAsksNothing() throws {
        let reg = try registry()
        let after = run(send(.settler, into: world()), registry: reg, ticks: 40)
        #expect(after.pendingEvents.isEmpty)
        #expect(VisitorEngine.decision(for: .settler) == nil)
    }

    @Test("The question is asked once, not every tick they stand there")
    func theAskIsNotRepeated() throws {
        let reg = try registry()
        let after = run(send(.trader, into: world()), registry: reg, ticks: 60)
        #expect(after.pendingEvents.count { $0.templateID == "visitors_traders" } <= 1)
    }

    @Test("Taking the refugees in actually brings people, and costs the stores")
    func takingThemInAddsColonists() throws {
        let reg = try registry()
        var w = world()
        w.settlements[0].storage[ResourceType.food] = 300
        w.settlements[0].pawns = [Pawn(name: "First")]
        w.pendingEvents = [PendingEvent(templateID: "visitors_refugees", tick: 0)]

        let before = w.settlements[0].pawns.count
        let after = GameEngine.resolveChoice(w, eventID: "visitors_refugees",
                                            choiceID: "take_them_in", registry: reg)
        #expect(after.settlements[0].pawns.count > before)
        #expect(after.settlements[0].storage[ResourceType.food] < 300)
        #expect(after.pendingEvents.isEmpty, "answering it should take it off the queue")
    }

    @Test("Turning them away costs standing instead")
    func sendingThemOnCosts() throws {
        let reg = try registry()
        var w = world()
        w.settlements[0].pawns = [Pawn(name: "First")]
        w.pendingEvents = [PendingEvent(templateID: "visitors_refugees", tick: 0)]
        let before = w.settlements[0].stats.morale
        let after = GameEngine.resolveChoice(w, eventID: "visitors_refugees",
                                            choiceID: "send_them_on", registry: reg)
        #expect(after.settlements[0].pawns.count == 1)
        #expect(after.settlements[0].stats.morale < before)
    }
}
