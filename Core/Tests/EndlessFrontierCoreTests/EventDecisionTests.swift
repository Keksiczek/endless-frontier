import Foundation
import Testing
@testable import EndlessFrontierCore

/// Regressions for two bugs a playtest surfaced: research that never moved, and
/// choice events (welcoming migrants) whose effects could never run because the
/// choices were never put to the player.
@Suite("Event decisions & research")
struct EventDecisionTests {
    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private static let townID = UUID(uuidString: "00000000-0000-0000-0E1D-000000000001")!

    private func town(knowledge: Double = 0, pawns: [Pawn] = []) -> Settlement {
        Settlement(id: Self.townID, name: "Study Town", kind: .capital, pawns: pawns,
                   storage: [.food: 500, .knowledge: knowledge], storageCapacity: .uniform(9999))
    }

    private func scholars(_ count: Int) -> [Pawn] {
        (0..<count).map { i in
            Pawn(id: UUID(uuidString: String(format: "00000000-0000-0000-0E1E-%012d", i + 1))!,
                 name: "Scholar \(i)", skills: [.research: 10], assignedWork: .research)
        }
    }

    // MARK: - Research

    @Test("Research spends the knowledge colonists actually banked")
    func researchDrawsBankedKnowledge() throws {
        let reg = try registry()
        let tech = try #require(reg.availableTechs(researched: []).first)
        // Bank less than the study costs, so it advances without completing.
        let banked = tech.knowledgeCost / 2
        var world = WorldState(settlements: [town(knowledge: banked)])
        world = TechEngine.setResearch(world, techID: tech.id, registry: reg)

        world = TechEngine.advanceResearch(world, registry: reg)
        #expect(world.researchProgress == banked)                   // the bank funded it
        #expect(world.settlements[0].storage[.knowledge] == 0)      // and was spent
    }

    @Test("Scholars alone move research, with no library in sight")
    func scholarsDriveResearch() throws {
        let reg = try registry()
        let tech = try #require(reg.availableTechs(researched: []).first)
        // No buildings at all — before the fix, globalStats.knowledgeOutput was
        // zero here and research sat still forever.
        var world = WorldState(settlements: [town(pawns: scholars(4))])
        world = TechEngine.setResearch(world, techID: tech.id, registry: reg)
        #expect(world.globalStats.knowledgeOutput == 0)

        world = TickEngine.advance(world, ticks: 40, registry: reg).state
        #expect(world.researchProgress > 0 || world.researchedTechs.contains(tech.id))
    }

    @Test("Research eventually completes and unlocks its effects")
    func researchCompletes() throws {
        let reg = try registry()
        let tech = try #require(reg.availableTechs(researched: []).first)
        var world = WorldState(settlements: [town(knowledge: tech.knowledgeCost + 10)])
        world = TechEngine.setResearch(world, techID: tech.id, registry: reg)
        world = TechEngine.advanceResearch(world, registry: reg)
        #expect(world.researchedTechs.contains(tech.id))
        #expect(world.activeResearch == nil)
    }

    @Test("Knowledge banks up when nothing is being studied")
    func knowledgeAccruesWithoutResearch() throws {
        let reg = try registry()
        var world = WorldState(settlements: [town(knowledge: 25)])
        world = TechEngine.advanceResearch(world, registry: reg)   // no active research
        #expect(world.settlements[0].storage[.knowledge] == 25)    // untouched
    }

    // MARK: - Event decisions

    @Test("An event with choices queues for the Leader instead of evaporating")
    func choiceEventQueues() throws {
        let reg = try registry()
        let template = try #require(reg.events.first { !$0.choices.isEmpty })
        let world = WorldState(settlements: [town()])
        let (after, _) = StoryPlanner.fireTemplate(template, in: world, registry: reg)
        #expect(after.pendingEvents.contains { $0.templateID == template.id })
    }

    @Test("An event without choices doesn't pester the player")
    func plainEventDoesNotQueue() throws {
        let reg = try registry()
        let template = try #require(reg.events.first { $0.choices.isEmpty })
        let world = WorldState(settlements: [town()])
        let (after, _) = StoryPlanner.fireTemplate(template, in: world, registry: reg)
        #expect(after.pendingEvents.isEmpty)
    }

    @Test("Welcoming migrants actually adds colonists")
    func welcomingMigrantsAddsColonists() throws {
        let reg = try registry()
        let migration = try #require(reg.events.first { $0.id == "migration_wave" })
        let welcome = try #require(migration.choices.first { choice in
            choice.effects.contains { if case .addPawn = $0 { return true }; return false }
        })

        var world = WorldState(settlements: [town(pawns: scholars(3))])
        let (fired, _) = StoryPlanner.fireTemplate(migration, in: world, registry: reg)
        world = fired
        let before = world.settlements[0].pawns.count

        world = GameEngine.resolveChoice(world, eventID: migration.id,
                                         choiceID: welcome.id, registry: reg)
        #expect(world.settlements[0].pawns.count > before)   // they moved in
        #expect(world.pendingEvents.isEmpty)                 // decision made
    }

    @Test("The same event re-firing refreshes rather than duplicating")
    func repeatedEventDoesNotStack() throws {
        let reg = try registry()
        let template = try #require(reg.events.first { !$0.choices.isEmpty })
        var world = WorldState(settlements: [town()])
        for _ in 0..<5 {
            world = StoryPlanner.fireTemplate(template, in: world, registry: reg).0
        }
        #expect(world.pendingEvents.filter { $0.templateID == template.id }.count == 1)
    }

    @Test("A backlog of decisions is capped so a month away isn't a hundred taps")
    func queueIsCapped() throws {
        let reg = try registry()
        let choiceEvents = reg.events.filter { !$0.choices.isEmpty }
        var world = WorldState(settlements: [town()])
        for template in choiceEvents {
            world = StoryPlanner.fireTemplate(template, in: world, registry: reg).0
        }
        #expect(world.pendingEvents.count <= StoryPlanner.maxPendingEvents)
    }

    @Test("A dismissed decision leaves the desk without acting")
    func dismissClearsWithoutEffect() throws {
        let reg = try registry()
        let template = try #require(reg.events.first { !$0.choices.isEmpty })
        var world = StoryPlanner.fireTemplate(template, in: WorldState(settlements: [town()]),
                                              registry: reg).0
        let pawnsBefore = world.settlements[0].pawns.count
        world = GameEngine.dismissEvent(world, eventID: template.id)
        #expect(world.pendingEvents.isEmpty)
        #expect(world.settlements[0].pawns.count == pawnsBefore)
    }

    @Test("Pending decisions survive a save round-trip")
    func pendingEventsPersist() throws {
        let reg = try registry()
        let template = try #require(reg.events.first { !$0.choices.isEmpty })
        let world = StoryPlanner.fireTemplate(template, in: WorldState(settlements: [town()]),
                                              registry: reg).0
        let restored = try JSONDecoder().decode(WorldState.self, from: JSONEncoder().encode(world))
        #expect(restored.pendingEvents == world.pendingEvents)
    }
}
