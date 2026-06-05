import Foundation

/// What a quest (or stage) grants on completion: world effects plus an optional
/// item dropped into the capital's inventory.
public struct QuestReward: Codable, Sendable, Equatable {
    public let effects: [EventEffect]
    public let itemID: String?

    public init(effects: [EventEffect] = [], itemID: String? = nil) {
        self.effects = effects
        self.itemID = itemID
    }

    private enum CodingKeys: String, CodingKey { case effects, itemID }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        effects = try c.decodeIfPresent([EventEffect].self, forKey: .effects) ?? []
        itemID = try c.decodeIfPresent(String.self, forKey: .itemID)
    }
}

/// One step of a quest. Its `goals` (reused `EventCondition`s) must all be
/// satisfied to complete the stage and earn its `reward`.
public struct QuestStage: Codable, Sendable, Equatable {
    public let description: String
    public let goals: [EventCondition]
    public let reward: QuestReward

    public init(description: String, goals: [EventCondition] = [], reward: QuestReward = QuestReward()) {
        self.description = description
        self.goals = goals
        self.reward = reward
    }

    private enum CodingKeys: String, CodingKey { case description, goals, reward }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        description = try c.decode(String.self, forKey: .description)
        goals = try c.decodeIfPresent([EventCondition].self, forKey: .goals) ?? []
        reward = try c.decodeIfPresent(QuestReward.self, forKey: .reward) ?? QuestReward()
    }
}

/// A data-defined, multi-stage quest. Loaded from `quests.json`. Becomes active
/// when its `trigger` conditions are met, then advances stage by stage.
public struct QuestDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let trigger: [EventCondition]
    public let stages: [QuestStage]

    public init(id: String, name: String, description: String = "",
                trigger: [EventCondition] = [], stages: [QuestStage] = []) {
        self.id = id
        self.name = name
        self.description = description
        self.trigger = trigger
        self.stages = stages
    }

    private enum CodingKeys: String, CodingKey { case id, name, description, trigger, stages }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        trigger = try c.decodeIfPresent([EventCondition].self, forKey: .trigger) ?? []
        stages = try c.decodeIfPresent([QuestStage].self, forKey: .stages) ?? []
    }
}

/// A player's progress through an active quest.
public struct QuestProgress: Codable, Sendable, Equatable, Identifiable {
    public let questID: String
    public var stage: Int

    public var id: String { questID }

    public init(questID: String, stage: Int = 0) {
        self.questID = questID
        self.stage = stage
    }
}
