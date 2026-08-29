import Foundation
import EndlessFrontierCore

/// **What the panels read**: the quests in hand, the tech tree as a ladder, the
/// regions a party could walk to and what an expedition would cost.
///
/// Lifted out of `GameViewModel` by rule 110 — *a file splits along what it
/// writes, never along what it is about*. Everything here only ever reads, so
/// it can live in an extension without opening `world`'s setter; the verbs it
/// sits beside (setting research, sending a party, equipping somebody) stayed
/// where that setter is.
extension GameViewModel {
    var activeQuests: [(definition: QuestDefinition, progress: QuestProgress)] {
        world.activeQuests.compactMap { progress in
            registry.quest(progress.questID).map { (definition: $0, progress: progress) }
        }
    }

    var completedQuestCount: Int { world.completedQuests.count }

    var tension: Double {
        TensionCalculator.calculate(world, config: registry.config)
    }

    var availableTechs: [TechDefinition] {
        registry.availableTechs(researched: world.researchedTechs)
    }

    enum TechStatus { case researched, active, available, locked }

    func techStatus(_ tech: TechDefinition) -> TechStatus {
        if world.activeResearch == tech.id { return .active }
        // An endless study is never "done" — it goes back on the board.
        if world.researchedTechs.contains(tech.id) {
            return tech.repeatable ? .available : .researched
        }
        // **And whether the colony is old enough to study it.**
        //
        // The tree used to call a tech available on its prerequisites alone,
        // which is what let a medieval colony study `computing`. The Core
        // refuses that now (`TechEngine.isStudiable`), so without this the
        // screen would offer a study and the tap would do nothing — a button
        // that does nothing is worse than a locked one.
        if TechEngine.isStudiable(tech, in: world) { return .available }
        return .locked
    }

    /// What this tech costs right now — a repeatable study grows dearer with
    /// every completion, so the tree must show the *next* price, not the base.
    func knowledgeCost(_ tech: TechDefinition) -> Double {
        TechEngine.cost(of: tech, in: world, config: registry.config)
    }

    /// How many times an endless study has been carried out, if it has.
    func completions(_ tech: TechDefinition) -> Int? {
        guard tech.repeatable else { return nil }
        let n = world.techCompletions[tech.id] ?? 0
        return n > 0 ? n : nil
    }

    /// All techs grouped by era (era order) for the tech-tree screen.
    var techsByEra: [(era: Era, techs: [TechDefinition])] {
        Dictionary(grouping: Array(registry.techs.values), by: \.era)
            .map { (era: $0.key, techs: $0.value.sorted { $0.knowledgeCost < $1.knowledgeCost }) }
            .sorted { $0.era.index < $1.era.index }
    }

    func researchProgressFraction(_ tech: TechDefinition) -> Double? {
        let cost = knowledgeCost(tech)
        guard world.activeResearch == tech.id, cost > 0 else { return nil }
        return min(1, world.researchProgress / cost)
    }

    func housingCapacity(_ settlement: Settlement) -> Int {
        Int(ResourceLoop.housingCapacity(settlement, registry: registry).rounded())
    }

    var activeExpedition: Expedition? { world.activeExpedition }

    var exploreableRegions: [Region] { ExplorationEngine.exploreableRegions(world) }

    var foundableRegions: [Region] { ExpansionEngine.foundableRegions(world) }

    var regions: [Region] { world.regions }

    func biomeName(_ id: String) -> String {
        registry.biome(id)?.name.resolve(AppStrings.language) ?? id
    }

    /// Whether an expedition to this region can be *reached* — adjacent, and
    /// nothing else under way. Says nothing about whether it can be paid for.
    func canExplore(_ region: Region) -> Bool {
        world.activeExpedition == nil && exploreableRegions.contains { $0.id == region.id }
    }

    /// What an expedition here would cost.
    func expeditionCost(for region: Region) -> Resources {
        ExplorationEngine.expeditionCost(to: region, config: registry.config)
    }

    /// What the viewed settlement is holding of a resource.
    func selectedSettlementStorage(_ resource: ResourceType) -> Double {
        selectedSettlement?.storage[resource] ?? 0
    }

    /// Whether the stores can actually cover it.
    ///
    /// `startExpedition` refuses an unaffordable one by doing nothing at all,
    /// so a colony down to its last timber lit a Send Expedition button that
    /// fell into silence — which reads as the game being broken rather than
    /// the colony being broke.
    func canAffordExpedition(to region: Region) -> Bool {
        ExplorationEngine.canAfford(expeditionTo: region, in: world, registry: registry)
    }

    func canFound(_ region: Region) -> Bool {
        foundableRegions.contains { $0.id == region.id }
    }

    func settlement(in region: Region) -> Settlement? {
        world.settlements.first { $0.regionID == region.id }
    }

    var capitalPawns: [Pawn] { capital?.pawns ?? [] }

    var capitalInventory: [ItemInstance] { capital?.inventory ?? [] }

    func itemDefinition(_ instance: ItemInstance) -> ItemDefinition? {
        registry.item(instance.definitionID)
    }

    /// What is on the shelf, resolved to definitions, for the equipment strip.
    ///
    /// Only what is *spare*: an item on somebody's back is not in the stores,
    /// and offering it to a second person would be offering the same sword
    /// twice.
    var equippableStore: [(instance: ItemInstance, definition: ItemDefinition)] {
        guard let settlement = selectedSettlement else { return [] }
        return settlement.inventory.compactMap { instance in
            guard let def = registry.item(instance.definitionID),
                  def.slot == .equipment, def.equipSlot != nil else { return nil }
            return (instance, def)
        }
        // Best first: you are looking for the good one, not the first one.
        .sorted {
            $0.instance.quality != $1.instance.quality
                ? $0.instance.quality > $1.instance.quality
                : $0.definition.name.resolve(AppStrings.language)
                    < $1.definition.name.resolve(AppStrings.language)
        }
    }
}
