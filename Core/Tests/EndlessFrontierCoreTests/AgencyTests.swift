import Testing
import Foundation
@testable import EndlessFrontierCore

/// A shortage the storyteller can't see, a decision with no deadline, and a
/// currency with nothing to buy — three ways the game asked nothing of the
/// player.

@Suite("Agency — a shortage worries the storyteller")
struct ShortageTensionTests {
    /// `depletedResourceCount` only counted a store at *exactly* zero. That was
    /// moot while everything pinned at the cap; now that the sinks make stores
    /// move, running your granary down to its last sack should worry the
    /// storyteller before it is actually, finally empty.
    @Test("Nearly out counts, not just bone empty")
    func nearEmptyRaisesTension() {
        var full = Fixtures.world(food: 400, materials: 400)
        full.settlements[0].storageCapacity = .uniform(500)
        var scraping = full
        scraping.settlements[0].storage[.food] = 20   // 4% of capacity

        #expect(TensionCalculator.calculate(scraping, config: .default)
                > TensionCalculator.calculate(full, config: .default),
                "a colony down to its last sacks should be tenser than a full one")
    }

    @Test("A comfortable store contributes nothing")
    func comfortableStoresAreCalm() {
        var world = Fixtures.world()
        world.settlements[0].storageCapacity = .uniform(500)
        for resource in ResourceType.allCases {
            world.settlements[0].storage[resource] = 400
        }
        #expect(TensionCalculator.shortageCount(world, config: .default) == 0)
    }

    @Test("An empty store still counts")
    func emptyStillCounts() {
        var world = Fixtures.world()
        world.settlements[0].storageCapacity = .uniform(500)
        for resource in ResourceType.allCases {
            world.settlements[0].storage[resource] = 0
        }
        #expect(TensionCalculator.shortageCount(world, config: .default) == ResourceType.allCases.count)
    }
}

@Suite("Agency — a decision has a deadline")
struct DecisionDeadlineTests {
    static let choiceEvent = EventTemplate(
        id: "drought", type: .disaster, name: "Drought", era: [], weight: 100,
        cooldownTicks: 10_000,
        choices: [EventChoice(id: "ration", label: "Ration the stores", effects: [])],
        narrativeHint: "The wells run low."
    )

    private func registry() -> GameDataRegistry {
        Fixtures.registry(events: [Self.choiceEvent], config: .default)
    }

    /// `PendingEvent.tick` was recorded and then never read by anything. A
    /// decision waited forever, and the only way it ever left the queue unasked
    /// was a seventh one silently shoving it off the six-cap. A choice nobody
    /// has to make by any particular time isn't a decision.
    @Test("An unanswered decision expires")
    func decisionsExpire() {
        let reg = registry()
        var world = Fixtures.world()
        world.pendingEvents = [PendingEvent(templateID: "drought", tick: 0)]
        world.tick = reg.config.decisionDeadlineTicks + 1

        let after = StoryPlanner.expireDecisions(world, registry: reg)
        #expect(after.state.pendingEvents.isEmpty, "the moment must pass")
    }

    @Test("A fresh decision is left alone")
    func freshDecisionsSurvive() {
        let reg = registry()
        var world = Fixtures.world()
        world.pendingEvents = [PendingEvent(templateID: "drought", tick: 0)]
        world.tick = reg.config.decisionDeadlineTicks / 2

        let after = StoryPlanner.expireDecisions(world, registry: reg)
        #expect(after.state.pendingEvents.count == 1)
    }

    @Test("The Leader's silence costs morale")
    func indecisionCostsMorale() {
        let reg = registry()
        var world = Fixtures.world()
        world.pendingEvents = [PendingEvent(templateID: "drought", tick: 0)]
        world.tick = reg.config.decisionDeadlineTicks + 1
        let before = world.settlements[0].stats.morale

        let after = StoryPlanner.expireDecisions(world, registry: reg)
        #expect(after.state.settlements[0].stats.morale < before,
                "a colony that looked to you and heard nothing should feel it")
        #expect(after.expired == ["drought"])
    }

    @Test("Deciding in time is never punished")
    func answeringIsFree() {
        let reg = registry()
        var world = Fixtures.world()
        world.pendingEvents = [PendingEvent(templateID: "drought", tick: 0)]
        world.tick = 10
        let before = world.settlements[0].stats.morale

        let after = StoryPlanner.expireDecisions(world, registry: reg)
        #expect(after.state.settlements[0].stats.morale == before)
    }

    @Test("Decisions expire as the world turns, without anyone calling for them")
    func expiryRunsInTheTick() {
        let reg = registry()
        var world = Fixtures.world()
        world.pendingEvents = [PendingEvent(templateID: "drought", tick: 0)]
        let after = TickEngine.advance(world, ticks: reg.config.decisionDeadlineTicks + 40, registry: reg).state
        #expect(!after.pendingEvents.contains { $0.templateID == "drought" && $0.tick == 0 })
    }
}

@Suite("Agency — influence buys something")
struct InfluenceSpendingTests {
    private func world(influence: Double, standing: Double = 0) -> WorldState {
        var state = WorldState(tick: 100, settlements: [
            Settlement(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!,
                name: "Seat", pawns: Fixtures.pawns(20),
                // Deliberately not at the cap: tribute clamps to capacity, so a
                // seat with a full granary has nowhere to put the spoils.
                storage: [.influence: influence, .food: 100]
            )
        ])
        state.tribes = [
            Tribe(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E2")!,
                  name: "The Walkers", foundedTick: 0,
                  originStory: LocalizedText("They left."),
                  population: 60, genes: Genes(), defense: 5, stores: 100,
                  standing: standing)
        ]
        return state
    }

    private var tribeID: UUID { UUID(uuidString: "00000000-0000-0000-0000-0000000000E2")! }

    /// Administration made influence a tax; nothing made it a choice. The
    /// Leader could watch neighbours trade, marry and raid, and never act.
    @Test("A gift costs influence and warms relations")
    func giftWarmsRelations() {
        let reg = Fixtures.registry(config: .default)
        let before = world(influence: 500)
        let after = GameEngine.sendGift(before, tribeID: tribeID, registry: reg)

        #expect(after.settlements[0].storage[.influence] < 500, "a gift must cost something")
        #expect(after.tribes[0].standing > before.tribes[0].standing)
    }

    @Test("A gift you cannot afford changes nothing")
    func giftNeedsCapital() {
        let reg = Fixtures.registry(config: .default)
        let before = world(influence: 1)
        let after = GameEngine.sendGift(before, tribeID: tribeID, registry: reg)
        #expect(after == before, "an unaffordable act must be inert, not partial")
    }

    @Test("A demand takes their stores and their goodwill")
    func demandTakesAndCosts() {
        let reg = Fixtures.registry(config: .default)
        let before = world(influence: 500, standing: 40)
        let after = GameEngine.demandTribute(before, tribeID: tribeID, registry: reg)

        #expect(after.tribes[0].stores < before.tribes[0].stores)
        #expect(after.tribes[0].standing < before.tribes[0].standing, "bullying should be remembered")
        #expect(after.settlements[0].storage[.food] > before.settlements[0].storage[.food])
    }

    @Test("Only a people who already trust you will take a pact")
    func pactNeedsGoodwill() {
        let reg = Fixtures.registry(config: .default)
        let strangers = GameEngine.proposePact(world(influence: 900, standing: 0), tribeID: tribeID, registry: reg)
        #expect(strangers.tribes[0].status != .allied, "you cannot buy an alliance from strangers")

        let friends = GameEngine.proposePact(world(influence: 900, standing: 50), tribeID: tribeID, registry: reg)
        #expect(friends.tribes[0].status == .allied)
        #expect(friends.settlements[0].storage[.influence] < 900)
    }

    @Test("Political capital buys the assembly's silence")
    func overrulingCanBeBought() {
        let reg = try! GameDataRegistry.bundled()
        guard let law = reg.laws.values.first else { return }
        var base = world(influence: 900)
        // The council votes it down, so ratifying it means overruling them.
        base.pendingLawProposal = LawProposal(
            definitionID: law.id, settlementID: base.settlements[0].id,
            proposedTick: 100, votesFor: 1, votesAgainst: 5)

        // Overruling the council by force of will costs morale…
        let defied = GameEngine.resolveLawProposal(base, approve: true, spendInfluence: false, registry: reg)
        // …but a Leader who spends their standing on it does not pay in morale.
        let bought = GameEngine.resolveLawProposal(base, approve: true, spendInfluence: true, registry: reg)

        #expect(bought.settlements[0].stats.morale > defied.settlements[0].stats.morale)
        #expect(bought.settlements[0].storage[.influence] < defied.settlements[0].storage[.influence])
    }
}
