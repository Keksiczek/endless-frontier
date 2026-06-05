import Foundation

/// Activates and advances multi-stage quests. Unlike the live Objectives list
/// (derived fresh each frame), quests are persistent tracked chains: they start
/// when their trigger conditions are met and progress stage by stage, paying
/// out rewards. Pure and deterministic; runs each tick.
public enum QuestEngine {
    public static func advance(_ state: WorldState, registry: GameDataRegistry) -> WorldState {
        var s = state
        s = activateEligible(s, registry: registry)
        s = progressActive(s, registry: registry)
        return s
    }

    // MARK: - Activation

    static func activateEligible(_ state: WorldState, registry: GameDataRegistry) -> WorldState {
        var s = state
        for quest in registry.quests.values.sorted(by: { $0.id < $1.id }) {
            guard !s.completedQuests.contains(quest.id),
                  !s.activeQuests.contains(where: { $0.questID == quest.id }),
                  WorldQuery.allSatisfied(quest.trigger, in: s) else { continue }
            s.activeQuests.append(QuestProgress(questID: quest.id, stage: 0))
        }
        return s
    }

    // MARK: - Progression

    static func progressActive(_ state: WorldState, registry: GameDataRegistry) -> WorldState {
        var s = state
        var stillActive: [QuestProgress] = []
        for var progress in s.activeQuests {
            guard let quest = registry.quest(progress.questID) else { continue }
            while progress.stage < quest.stages.count,
                  WorldQuery.allSatisfied(quest.stages[progress.stage].goals, in: s) {
                s = applyReward(quest.stages[progress.stage].reward, to: s, registry: registry, key: "\(quest.id)#\(progress.stage)")
                progress.stage += 1
            }
            if progress.stage >= quest.stages.count {
                s.completedQuests.insert(quest.id)
            } else {
                stillActive.append(progress)
            }
        }
        s.activeQuests = stillActive
        return s
    }

    static func applyReward(_ reward: QuestReward, to state: WorldState, registry: GameDataRegistry, key: String) -> WorldState {
        var s = EffectApplier.apply(reward.effects, to: state, registry: registry)
        if let itemID = reward.itemID, registry.item(itemID) != nil,
           let capital = s.settlements.indices.first {
            var rng = SeededRNG(seed: rewardSeed(state: s, key: key))
            s.settlements[capital].inventory.append(ItemInstance(id: rng.nextUUID(), definitionID: itemID))
        }
        return s
    }

    private static func rewardSeed(state: WorldState, key: String) -> UInt64 {
        var h: UInt64 = state.mapSeed &* 0x9E37_79B9_7F4A_7C15
        for byte in key.utf8 { h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3 }
        h = (h ^ UInt64(bitPattern: Int64(state.tick)))
        return h ^ (h >> 29)
    }
}
