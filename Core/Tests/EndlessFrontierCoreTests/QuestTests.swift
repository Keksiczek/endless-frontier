import Testing
@testable import EndlessFrontierCore

@Suite("Quests")
struct QuestTests {
    private func reg() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private func materials(_ s: WorldState) -> Double {
        s.settlements.reduce(0) { $0 + $1.storage[.materials] }
    }

    @Test("Quests load from data")
    func bundledQuests() throws {
        #expect(try reg().quests.count >= 4)
    }

    @Test("A quest with no trigger activates immediately; gated quests wait")
    func activation() throws {
        let r = try reg()
        var world = GameWorldFactory.newGame(registry: r, seed: 1)   // population 50
        world = QuestEngine.advance(world, registry: r)
        #expect(world.activeQuests.contains { $0.questID == "founding_a_home" })
        #expect(!world.activeQuests.contains { $0.questID == "reach_outward" })  // needs population 60
    }

    @Test("Meeting a stage goal advances the quest and pays the reward")
    func stageProgress() throws {
        let r = try reg()
        var world = GameWorldFactory.newGame(registry: r, seed: 1)
        world = QuestEngine.advance(world, registry: r)              // activate
        let before = materials(world)
        world.settlements[0].population = 70                         // satisfy stage 1
        world = QuestEngine.advance(world, registry: r)
        let progress = world.activeQuests.first { $0.questID == "founding_a_home" }
        #expect(progress?.stage == 1)
        #expect(materials(world) > before)                          // +60 materials reward
    }

    @Test("Completing all stages finishes the quest and grants its item")
    func completion() throws {
        let r = try reg()
        var world = GameWorldFactory.newGame(registry: r, seed: 1)
        world = QuestEngine.advance(world, registry: r)
        world.settlements[0].population = 70
        world.researchedTechs.insert("writing")                     // satisfy both stages
        world = QuestEngine.advance(world, registry: r)
        #expect(world.completedQuests.contains("founding_a_home"))
        #expect(!world.activeQuests.contains { $0.questID == "founding_a_home" })
        #expect(world.settlements[0].inventory.contains { $0.definitionID == "leather_garb" })
    }

    @Test("Clearing a dungeon advances the depths quest via its world flag")
    func dungeonQuestFlag() throws {
        let r = try reg()
        var world = GameWorldFactory.newGame(registry: r, seed: 1)
        world.globalStats.threatLevel = 30                          // trigger into_the_depths
        world.worldFlags["cleared:dungeon"] = true                  // as SiteEngine would set
        world = QuestEngine.advance(world, registry: r)
        let progress = world.activeQuests.first { $0.questID == "into_the_depths" }
        #expect(progress?.stage == 1 || world.completedQuests.contains("into_the_depths"))
    }

    @Test("Quest progression is deterministic")
    func deterministic() throws {
        let r = try reg()
        var world = GameWorldFactory.newGame(registry: r, seed: 1)
        world.settlements[0].population = 80
        let a = QuestEngine.advance(world, registry: r)
        let b = QuestEngine.advance(world, registry: r)
        #expect(a == b)
    }

    @Test("Every quest reward item references a real item")
    func rewardIntegrity() throws {
        let r = try reg()
        for quest in r.quests.values {
            for stage in quest.stages {
                if let itemID = stage.reward.itemID {
                    #expect(r.item(itemID) != nil, "Quest \(quest.id) rewards missing item \(itemID)")
                }
            }
        }
    }
}
