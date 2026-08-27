import Testing
import Foundation
@testable import EndlessFrontier
@testable import EndlessFrontierCore

/// **What the colony says when nobody is looking at it.**
///
/// `pendingDecisionLine` asked `world.pendingLawProposal` and nothing else —
/// so the storyteller's decision cards, which are the ones a player actually
/// meets (migrants at the gate, a contested border), sent **nothing**. Two
/// queues of things waiting on the player's word, one of them wired. And a
/// raid — the only thing in the game with a clock on it — had no message at
/// all. Keks: *"mělo by to poslat notifikaci pokud se bude dít něco
/// důležitého."*
@MainActor
@Suite("Word from the colony")
struct NotificationLineTests {

    private static let registry = try! GameDataRegistry.bundled()

    private func world() -> WorldState {
        GameWorldFactory.newGame(registry: Self.registry, seed: 4242)
    }

    @Test("A quiet colony has nothing to say")
    func quietSaysNothing() {
        var w = world()
        w.pendingEvents = []
        w.pendingLawProposal = nil
        #expect(NotificationScheduler.pendingDecisionLine(w) == nil)
        #expect(NotificationScheduler.raidLine(w) == nil)
    }

    /// The gap this closes.
    @Test("A storyteller card waiting is worth a message")
    func aCardIsWorthAMessage() throws {
        var w = world()
        w.pendingLawProposal = nil
        let template = try #require(Self.registry.events.first)
        w.pendingEvents = [PendingEvent(templateID: template.id, tick: w.tick)]
        let line = NotificationScheduler.pendingDecisionLine(w)
        #expect(line != nil, "a decision was waiting and the colony said nothing")
        #expect(!(line ?? "").isEmpty)
    }

    @Test("Several waiting is said as several")
    func severalAreCounted() throws {
        var w = world()
        w.pendingLawProposal = nil
        let template = try #require(Self.registry.events.first)
        let one = NotificationScheduler.pendingDecisionLine({
            var x = w; x.pendingEvents = [PendingEvent(templateID: template.id, tick: 0)]; return x
        }())
        w.pendingEvents = (0..<3).map { PendingEvent(templateID: template.id, tick: $0) }
        let many = NotificationScheduler.pendingDecisionLine(w)
        #expect(one != many, "one card and three read the same")
    }

    /// An assembly outranks a card: it is the rarer thing and the one with a
    /// standing cost attached.
    @Test("An assembly vote is said before a card")
    func theAssemblyComesFirst() throws {
        var w = world()
        let template = try #require(Self.registry.events.first)
        w.pendingEvents = [PendingEvent(templateID: template.id, tick: w.tick)]
        let withoutVote = NotificationScheduler.pendingDecisionLine(w)
        // A world where the assembly is also waiting says the assembly's line.
        guard let law = Self.registry.laws.values.first else { return }
        w.pendingLawProposal = LawProposal(
            definitionID: law.id, settlementID: w.settlements[0].id,
            proposedTick: w.tick, votesFor: 9, votesAgainst: 2)
        let withVote = NotificationScheduler.pendingDecisionLine(w)
        #expect(withVote != withoutVote)
    }

    @Test("A raid names who is at the gate and where")
    func aRaidIsNamed() throws {
        var w = world()
        var capital = w.settlements[0]
        capital = SiegeEngine.begin(
            capital, attackerStrength: 30, attackerName: "Vlčí lid",
            fortification: 2, tick: w.tick, registry: Self.registry, seed: 9,
            drawn: 5)
        w.settlements[0] = capital
        let line = try #require(NotificationScheduler.raidLine(w))
        #expect(line.contains("Vlčí lid"), "the message does not say who came: \(line)")
        #expect(line.contains(capital.name), "the message does not say where: \(line)")
    }
}
