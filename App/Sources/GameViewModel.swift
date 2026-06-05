import Foundation
import Observation
import EndlessFrontierCore

/// Owns the live world and bridges player intent to the deterministic Core.
/// All mutation flows through `GameEngine`; the view model only orchestrates
/// loading, persistence, and the "while you were away" summary.
@MainActor
@Observable
final class GameViewModel {
    private(set) var world: WorldState
    private(set) var lastSessionEvents: [HistoricalEvent] = []
    private(set) var loadError: String?

    let registry: GameDataRegistry
    private let store: WorldStore

    init(registry: GameDataRegistry, store: WorldStore = WorldStore(url: WorldStore.defaultURL())) {
        self.registry = registry
        self.store = store
        // Load an existing save, otherwise start a fresh world.
        if let saved = try? store.load() {
            self.world = saved
        } else {
            self.world = GameWorldFactory.newGame(registry: registry)
        }
    }

    /// Builds the view model with the bundled game data, falling back to an
    /// empty registry on failure (surfaced via `loadError`).
    static func bootstrapped() -> GameViewModel {
        do {
            let registry = try GameDataRegistry.bundled()
            return GameViewModel(registry: registry)
        } catch {
            let vm = GameViewModel(registry: GameDataRegistry())
            vm.loadError = "Failed to load game data: \(error)"
            return vm
        }
    }

    // MARK: - Session lifecycle

    /// Advances the world by the real time elapsed since the last session.
    func openSession(now: Date = Date()) {
        let result = GameEngine.openSession(world, now: now, registry: registry)
        world = result.state
        lastSessionEvents = result.fired
        persist()
    }

    func dismissSessionSummary() {
        lastSessionEvents = []
    }

    // MARK: - Player actions

    func setResearch(_ techID: String) {
        world = GameEngine.setResearch(world, techID: techID, registry: registry)
        persist()
    }

    func build(_ buildingID: String) {
        guard let capital = world.settlements.first else { return }
        world = GameEngine.build(world, settlementID: capital.id, buildingID: buildingID, registry: registry)
        persist()
    }

    func startNewGame() {
        // A fresh random seed per playthrough → a different procedural world,
        // while remaining fully deterministic once started.
        let seed = UInt64.random(in: UInt64.min...UInt64.max)
        world = GameWorldFactory.newGame(registry: registry, seed: seed)
        lastSessionEvents = []
        persist()
    }

    func explore(_ regionID: UUID) {
        world = GameEngine.startExpedition(world, targetRegionID: regionID, registry: registry)
        persist()
    }

    func foundOutpost(in regionID: UUID) {
        let existing = world.settlements.count
        world = GameEngine.foundOutpost(world, regionID: regionID, name: "Outpost \(existing)", registry: registry)
        persist()
    }

    private(set) var lastSiteOutcome: SiteOutcome?

    func interactWithSite(_ regionID: UUID) {
        let (newState, outcome) = GameEngine.interactWithSite(world, regionID: regionID, registry: registry)
        world = newState
        lastSiteOutcome = outcome
        persist()
    }

    func dismissSiteOutcome() { lastSiteOutcome = nil }

    /// Player-facing label for the site action available in a region, if any.
    func siteActionLabel(for region: Region) -> String? {
        guard region.hasActiveSite else { return nil }
        switch region.kind {
        case .ruins: return "Excavate Ruins"
        case .dungeon: return "Delve Dungeon"
        case .anomaly: return "Probe Anomaly"
        default: return nil
        }
    }

    // MARK: - Derived view data

    var capital: Settlement? { world.settlements.first }

    /// Which settlement the colony panels are currently looking at.
    var selectedSettlementID: UUID?

    var settlements: [Settlement] { world.settlements }

    var selectedSettlement: Settlement? {
        if let id = selectedSettlementID, let match = world.settlements.first(where: { $0.id == id }) {
            return match
        }
        return capital
    }

    func selectSettlement(_ id: UUID) { selectedSettlementID = id }

    var viewedPawns: [Pawn] { selectedSettlement?.pawns ?? [] }

    var viewedInventory: [ItemInstance] { selectedSettlement?.inventory ?? [] }

    var eraProgress: Double {
        EraEngine.progressToNextEra(world, registry: registry)
    }

    var objectives: [Objective] {
        ObjectivesEngine.current(world, registry: registry)
    }

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

    func housingCapacity(_ settlement: Settlement) -> Int {
        Int(ResourceLoop.housingCapacity(settlement, registry: registry).rounded())
    }

    var activeExpedition: Expedition? { world.activeExpedition }

    var exploreableRegions: [Region] { ExplorationEngine.exploreableRegions(world) }

    var foundableRegions: [Region] { ExpansionEngine.foundableRegions(world) }

    var regions: [Region] { world.regions }

    func biomeName(_ id: String) -> String { registry.biome(id)?.name ?? id }

    func canExplore(_ region: Region) -> Bool {
        world.activeExpedition == nil && exploreableRegions.contains { $0.id == region.id }
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

    func equip(_ itemID: UUID, toPawn pawnID: UUID) {
        guard let settlement = selectedSettlement else { return }
        world = GameEngine.equipItem(world, settlementID: settlement.id, pawnID: pawnID,
                                     itemID: itemID, registry: registry)
        persist()
    }

    func unequip(_ pawnID: UUID, slot: EquipmentSlot) {
        guard let settlement = selectedSettlement else { return }
        world = GameEngine.unequipItem(world, settlementID: settlement.id, pawnID: pawnID, slot: slot)
        persist()
    }

    // MARK: - Trade

    var tradeRoutes: [TradeRoute] { world.tradeRoutes }

    func settlementName(_ id: UUID) -> String {
        world.settlements.first { $0.id == id }?.name ?? "?"
    }

    func addTradeRoute(from: UUID, to: UUID, resource: ResourceType, amount: Double) {
        world = GameEngine.addTradeRoute(world, from: from, to: to, resource: resource, amountPerTick: amount)
        persist()
    }

    func removeTradeRoute(_ routeID: UUID) {
        world = GameEngine.removeTradeRoute(world, routeID: routeID)
        persist()
    }

    var availableRecipes: [RecipeDefinition] {
        CraftingEngine.availableRecipes(world, registry: registry)
    }

    func recipeOutputName(_ recipe: RecipeDefinition) -> String {
        registry.item(recipe.outputItemID)?.name ?? recipe.outputItemID
    }

    func recipeOutputRarity(_ recipe: RecipeDefinition) -> ItemRarity? {
        registry.item(recipe.outputItemID)?.rarity
    }

    func itemName(_ id: String) -> String { registry.item(id)?.name ?? id }

    func craft(_ recipeID: String) {
        world = GameEngine.craft(world, recipeID: recipeID, registry: registry)
        persist()
    }

    func assignWork(pawnID: UUID, to work: WorkKind) {
        guard let settlement = selectedSettlement else { return }
        world = GameEngine.assignWork(world, settlementID: settlement.id, pawnID: pawnID, work: work)
        persist()
    }

    func expeditionDuration(for region: Region) -> Int {
        ExplorationEngine.expeditionDuration(to: region, config: registry.config)
    }

    func regionName(_ id: UUID) -> String {
        world.regions.first { $0.id == id }?.name ?? "Unknown"
    }

    var buildableBuildings: [BuildingDefinition] {
        registry.buildings.values
            .filter { world.unlockedBuildings.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    func techName(_ id: String) -> String { registry.tech(id)?.name ?? id }

    private func persist() {
        try? store.save(world)
    }
}
