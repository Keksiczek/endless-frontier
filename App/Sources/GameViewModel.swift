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

    /// A running record of what each session did — for playtesting feedback.
    let diagnostics = Diagnostics()

    /// The full "why is the world like this" readout, for reporting a playtest.
    var worldReport: String {
        WorldReport.generate(world, registry: registry)
    }

    /// Systems that cannot fire right now, surfaced at the top of diagnostics.
    var blockers: [WorldReport.Blocker] {
        WorldReport.blockers(world, registry: registry)
    }

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

    /// True while a long absence is being simulated, so the UI can say so.
    private(set) var isCatchingUp = false

    /// Advances the world by the real time elapsed since the last session.
    ///
    /// A month away is up to 43,200 ticks of a fully simulated colony — far too
    /// much to run on the main actor, which would freeze the launch. The world
    /// is a `Sendable` value and `TickEngine` is pure, so the catch-up is
    /// computed off-thread and only the result is applied here.
    func openSession(now: Date = Date()) async {
        guard !isCatchingUp else { return }
        let snapshot = world
        let registry = registry

        let ticks = TickEngine.ticksElapsed(
            since: snapshot.lastRealTimestamp, until: now, config: registry.config)
        // A short absence is cheap; don't pay for a thread hop.
        if ticks <= shortCatchUpTicks {
            apply(GameEngine.openSession(snapshot, now: now, registry: registry), before: snapshot)
            return
        }

        isCatchingUp = true
        let result = await Task.detached(priority: .userInitiated) {
            GameEngine.openSession(snapshot, now: now, registry: registry)
        }.value
        isCatchingUp = false
        apply(result, before: snapshot)
    }

    /// Ticks we're happy to simulate inline rather than hopping off the actor.
    private let shortCatchUpTicks = 120

    private func apply(_ result: PlannerResult, before: WorldState) {
        world = result.state
        lastSessionEvents = result.fired
        diagnostics.recordSession(before: before, after: result.state,
                                  fired: result.fired, registry: registry)
        persist()
    }

    func dismissSessionSummary() {
        lastSessionEvents = []
    }

    // MARK: - The live loop
    //
    // The world used to advance only when a session *opened* — with the app in
    // the foreground, literally nothing ever happened. A minute of real time
    // is a tick; this loop lets those ticks actually land while you watch,
    // and surfaces what they did as passing toasts.

    /// A transient on-screen note: something just happened in the colony.
    struct LiveToast: Identifiable, Equatable {
        let id: UUID
        let icon: String
        let text: String
        let kind: ColonyLogEntry.Kind?
    }

    private(set) var toasts: [LiveToast] = []
    private var liveLoop: Task<Void, Never>?
    /// How often the loop checks whether a tick has come due.
    private let livePollSeconds: Double = 5
    /// Live advances stay small; anything bigger goes the catch-up path.
    private let maxLiveTicks = 10
    private let maxVisibleToasts = 4

    /// Starts the once-a-tick heartbeat (idempotent).
    func startLiveLoop() {
        guard liveLoop == nil else { return }
        liveLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.livePollSeconds ?? 5))
                self?.advanceLive()
            }
        }
    }

    func stopLiveLoop() {
        liveLoop?.cancel()
        liveLoop = nil
    }

    /// Advances any ticks that have come due while the app sits open, and
    /// turns what happened into toasts.
    func advanceLive(now: Date = Date()) {
        guard !isCatchingUp else { return }
        let config = registry.config
        let ticks = TickEngine.ticksElapsed(
            since: world.lastRealTimestamp, until: now, config: config)
        guard ticks > 0 else { return }
        // A pile of ticks (device slept with the app up) is a catch-up, not a
        // live moment — no toast storm, just the summary flow.
        guard ticks <= maxLiveTicks else {
            Task { await openSession(now: now) }
            return
        }

        let journalMark = selectedSettlement?.journal.nextID ?? 0
        let before = world
        var result = TickEngine.advance(world, ticks: ticks, registry: registry)
        // Advance the stamp by exactly the ticks simulated — stamping `now`
        // would silently drop the remainder every pass and run the world slow.
        result.state.lastRealTimestamp = before.lastRealTimestamp
            .addingTimeInterval(Double(ticks) * config.realSecondsPerTick)
        world = result.state
        persist()

        surfaceToasts(fired: result.fired, journalMark: journalMark)
    }

    /// What just happened, as passing notes: fresh journal lines of the viewed
    /// settlement, plus any storyteller events that fired.
    private func surfaceToasts(fired: [HistoricalEvent], journalMark: Int) {
        var fresh: [LiveToast] = []
        if let journal = selectedSettlement?.journal {
            for entry in journal.entries(after: journalMark - 1) where entry.id >= journalMark {
                fresh.append(LiveToast(
                    id: UUID(), icon: Self.icon(for: entry.kind),
                    text: entry.text.resolve(AppStrings.language),
                    kind: entry.kind))
            }
        }
        for event in fired {
            guard let template = registry.events.first(where: { $0.id == event.templateID })
            else { continue }
            fresh.append(LiveToast(
                id: UUID(), icon: Self.icon(for: template.type),
                text: template.name.resolve(AppStrings.language),
                kind: nil))
        }
        guard !fresh.isEmpty else { return }
        for toast in fresh.suffix(maxVisibleToasts) {
            show(toast)
        }
    }

    /// Puts a toast up and takes it down again a few breaths later.
    private func show(_ toast: LiveToast) {
        toasts.append(toast)
        if toasts.count > maxVisibleToasts {
            toasts.removeFirst(toasts.count - maxVisibleToasts)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(7))
            self?.toasts.removeAll { $0.id == toast.id }
        }
    }

    static func icon(for kind: ColonyLogEntry.Kind) -> String {
        switch kind {
        case .social: return "bubble.left.and.bubble.right.fill"
        case .work: return "hammer.fill"
        case .construction: return "hammer.fill"
        case .birth: return "heart.fill"
        case .death: return "leaf.fill"
        case .arrival: return "figure.walk.arrival"
        case .departure: return "figure.walk.departure"
        case .discovery: return "binoculars.fill"
        case .danger: return "exclamationmark.triangle.fill"
        case .faith: return "flame.fill"
        }
    }

    static func icon(for type: EventType) -> String {
        switch type {
        case .disaster, .threat: return "exclamationmark.triangle.fill"
        case .opportunity: return "sparkles"
        case .quest: return "flag.fill"
        case .flavor: return "text.book.closed.fill"
        }
    }

    /// Diagnostics helper: fast-forward the world by `ticks` and record what
    /// happened, so events (migrations, disasters…) can be reproduced without
    /// waiting real time. Runs inline — intended for small jumps.
    func debugAdvance(ticks: Int) {
        let before = world
        let result = TickEngine.advance(world, ticks: ticks, registry: registry)
        var stamped = result.state
        stamped.lastRealTimestamp = world.lastRealTimestamp   // don't skew real-time catch-up
        apply(PlannerResult(state: stamped, fired: result.fired), before: before)
    }

    // MARK: - Player actions

    func setResearch(_ techID: String) {
        world = GameEngine.setResearch(world, techID: techID, registry: registry)
        persist()
    }

    func build(_ buildingID: String) {
        guard let settlement = selectedSettlement else { return }
        world = GameEngine.build(world, settlementID: settlement.id, buildingID: buildingID, registry: registry)
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

    /// The colonists of the viewed settlement, gathered by the trade they work.
    struct TradeGroup: Identifiable {
        let work: WorkKind
        let pawns: [Pawn]
        var id: WorkKind { work }
    }

    /// The colony as a workforce rather than a cast list: one flat roll of every
    /// soul is readable at eighteen and hopeless at a hundred and twenty.
    /// Children are their own group — they're not idle, they're seven — and the
    /// busiest trades lead.
    var workforce: [TradeGroup] {
        let ticksPerYear = self.ticksPerYear
        let grouped = Dictionary(grouping: viewedPawns) { pawn in
            pawn.isAdult(ticksPerYear: ticksPerYear) ? pawn.assignedWork : WorkKind.idle
        }
        return grouped
            .map { TradeGroup(work: $0.key, pawns: $0.value.sorted { $0.mood < $1.mood }) }
            .sorted {
                $0.pawns.count != $1.pawns.count
                    ? $0.pawns.count > $1.pawns.count
                    : "\($0.work)" < "\($1.work)"
            }
    }

    /// The few people the colony needs a decision about, lifted out of the
    /// crowd so you don't have to scroll past everyone who's fine to find them.
    var colonistsNeedingAttention: [Pawn] {
        viewedPawns.filter { pawn in
            pawn.health < attentionHealth
                || pawn.mood < attentionMood
                || (pawn.isAdult(ticksPerYear: ticksPerYear) && pawn.assignedWork == .idle)
        }
        .sorted { $0.health != $1.health ? $0.health < $1.health : $0.mood < $1.mood }
    }

    private var attentionHealth: Double { 50 }
    private var attentionMood: Double { 35 }

    var viewedInventory: [ItemInstance] { selectedSettlement?.inventory ?? [] }

    var eraProgress: Double {
        EraEngine.progressToNextEra(world, registry: registry)
    }

    /// The current in-game season and year, for the living-world chrome.
    var season: Season { world.season(registry.config) }
    var year: Int { world.year(registry.config) }

    /// The living outdoor map of the settlement currently in view.
    var viewedLocalMap: LocalMap? { selectedSettlement?.localMap }

    var ticksPerYear: Int { registry.config.ticksPerYear }

    // MARK: - The assembly

    /// The motion the council has put before you, if any.
    var pendingProposal: LawProposal? { world.pendingLawProposal }

    /// Ratify or veto the assembly's motion. Overruling them costs morale —
    /// or influence, if the Leader would rather spend standing than goodwill.
    func resolveProposal(approve: Bool, spendInfluence: Bool = false) {
        world = GameEngine.resolveLawProposal(world, approve: approve,
                                              spendInfluence: spendInfluence, registry: registry)
        persist()
    }

    /// True when ratifying/vetoing would go against the council's vote — the
    /// only case where anything is paid at all.
    func wouldOverrule(approve: Bool) -> Bool {
        guard let proposal = world.pendingLawProposal else { return false }
        return approve != proposal.councilApproves
    }

    // MARK: - Diplomacy

    /// The peoples you have actually met. Natives beyond the fog stay off the
    /// panels until an expedition makes first contact.
    var tribes: [Tribe] { world.tribes.filter(\.discovered) }

    /// How many native peoples are still out there, unmet — the world tab can
    /// hint that the map is not empty.
    var unmetTribeCount: Int { world.tribes.filter { !$0.discovered }.count }

    func canAfford(influence amount: Double) -> Bool {
        GameEngine.canAfford(influence: amount, in: world)
    }

    var giftCost: Double { registry.config.giftInfluenceCost }
    var demandCost: Double { registry.config.demandInfluenceCost }
    var pactCost: Double { registry.config.pactInfluenceCost }
    var overruleCost: Double { registry.config.overruleInfluenceCost }

    /// A people has to already hold you in some regard before a pact is worth
    /// offering — standing can't buy an alliance from strangers.
    func canProposePact(to tribe: Tribe) -> Bool {
        tribe.standing >= registry.config.pactMinStanding && canAfford(influence: pactCost)
    }

    func sendGift(to tribeID: UUID) {
        world = GameEngine.sendGift(world, tribeID: tribeID, registry: registry)
        persist()
    }

    func demandTribute(from tribeID: UUID) {
        world = GameEngine.demandTribute(world, tribeID: tribeID, registry: registry)
        persist()
    }

    func proposePact(with tribeID: UUID) {
        world = GameEngine.proposePact(world, tribeID: tribeID, registry: registry)
        persist()
    }

    /// How long the Leader has left to answer the decision on the desk, in
    /// ticks. Negative would mean it's already gone.
    func ticksLeft(for pending: PendingEvent) -> Int {
        let deadline = registry.events.first { $0.id == pending.templateID }?.decisionTicks
            ?? registry.config.decisionDeadlineTicks
        return max(0, deadline - (world.tick - pending.tick))
    }

    /// Observations the chronicle reads out of the world's history.
    var insights: [Insight] {
        ChronicleEngine.insights(world, registry: registry)
    }

    // MARK: - Event decisions

    /// Events queued for the Leader's word, oldest first.
    var pendingEvents: [PendingEvent] { world.pendingEvents }

    /// The decision currently on the desk, with its template.
    var currentDecision: EventTemplate? {
        guard let pending = world.pendingEvents.first else { return nil }
        return registry.events.first { $0.id == pending.templateID }
    }

    func canAfford(choice choiceID: String, event eventID: String) -> Bool {
        GameEngine.canAffordChoice(world, eventID: eventID, choiceID: choiceID, registry: registry)
    }

    func resolveEventChoice(event eventID: String, choice choiceID: String) {
        world = GameEngine.resolveChoice(world, eventID: eventID, choiceID: choiceID, registry: registry)
        persist()
    }

    func dismissEvent(_ eventID: String) {
        world = GameEngine.dismissEvent(world, eventID: eventID)
        persist()
    }

    var objectives: [Objective] {
        ObjectivesEngine.current(world, registry: registry)
    }

    // MARK: - Where the game is pointing you

    /// The five tabs, so an objective can actually take you to the thing it's
    /// asking for. Telling the player to pick a research project and then
    /// leaving them to find the Science tab themselves is a to-do list, not a
    /// game.
    enum Tab: Hashable { case settlement, world, council, chronicle, science }

    var tab: Tab = .settlement

    /// The screen an objective is really about.
    func destination(for objective: Objective) -> Tab {
        switch objective.category {
        case .research: return .science
        case .explore, .expand, .sites: return .world
        case .colonists: return .settlement
        case .era: return .science   // era gates are almost always a tech
        }
    }

    /// True when following this objective means going somewhere else.
    func isActionable(_ objective: Objective) -> Bool {
        destination(for: objective) != .settlement || objective.category == .colonists
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

    enum TechStatus { case researched, active, available, locked }

    func techStatus(_ tech: TechDefinition) -> TechStatus {
        if world.activeResearch == tech.id { return .active }
        // An endless study is never "done" — it goes back on the board.
        if world.researchedTechs.contains(tech.id) {
            return tech.repeatable ? .available : .researched
        }
        if tech.requires.allSatisfy(world.researchedTechs.contains) { return .available }
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

    func biomeName(_ id: String) -> String { registry.biome(id)?.name ?? id }

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

    // MARK: - Caravans

    var caravans: [Caravan] { world.caravans }

    /// How many colonists a settlement could spare as an escort.
    func availableEscort(_ settlementID: UUID) -> Int {
        world.settlements.first { $0.id == settlementID }?.pawns.count ?? 0
    }

    /// Dispatches a caravan escorted by the origin's first `guards` colonists.
    func dispatchCaravan(from: UUID, to: UUID, resource: ResourceType, amount: Double, guards: Int) {
        guard let origin = world.settlements.first(where: { $0.id == from }) else { return }
        let guardIDs = Array(origin.pawns.prefix(max(0, guards)).map(\.id))
        world = GameEngine.dispatchCaravan(world, originID: from, destinationID: to,
                                           resource: resource, amount: amount, guardIDs: guardIDs)
        persist()
    }

    func canDispatchCaravan(from: UUID, to: UUID, resource: ResourceType, amount: Double, guards: Int) -> Bool {
        guard let origin = world.settlements.first(where: { $0.id == from }) else { return false }
        let guardIDs = Array(origin.pawns.prefix(max(0, guards)).map(\.id))
        return CaravanEngine.canDispatch(world, originID: from, destinationID: to,
                                         resource: resource, amount: amount, guardIDs: guardIDs)
    }

    var availableRecipes: [RecipeDefinition] {
        CraftingEngine.availableRecipes(world, settlementID: selectedSettlement?.id, registry: registry)
    }

    func recipeOutputName(_ recipe: RecipeDefinition) -> String {
        registry.item(recipe.outputItemID)?.name ?? recipe.outputItemID
    }

    func recipeOutputRarity(_ recipe: RecipeDefinition) -> ItemRarity? {
        registry.item(recipe.outputItemID)?.rarity
    }

    func itemName(_ id: String) -> String { registry.item(id)?.name ?? id }

    func craft(_ recipeID: String) {
        world = GameEngine.craft(world, recipeID: recipeID, settlementID: selectedSettlement?.id, registry: registry)
        persist()
    }

    func setSpecialization(_ specialization: SettlementSpecialization) {
        guard let settlement = selectedSettlement else { return }
        world = GameEngine.setSpecialization(world, settlementID: settlement.id, specialization: specialization)
        persist()
    }

    func assignWork(pawnID: UUID, to work: WorkKind) {
        guard let settlement = selectedSettlement else { return }
        world = GameEngine.assignWork(world, settlementID: settlement.id, pawnID: pawnID, work: work)
        persist()
    }

    // MARK: - Colony layout (in-settlement base building)

    /// The build grid of the settlement currently being viewed.
    var viewedColony: ColonyMap? { selectedSettlement?.colony }

    /// Buildings the player can lay down right now (unlocked or early-era).
    var placeableBuildings: [BuildingDefinition] {
        registry.buildings.values
            .filter { world.unlockedBuildings.contains($0.id) || $0.era == .earlySettlement }
            .sorted { $0.name < $1.name }
    }

    func buildingDefinition(_ id: String) -> BuildingDefinition? { registry.building(id) }

    /// What one instance of a building costs per tick to keep standing.
    func upkeep(for definition: BuildingDefinition) -> Resources {
        ResourceLoop.upkeep(for: definition, config: registry.config)
    }

    func buildingName(_ id: String) -> String { registry.building(id)?.name ?? id }

    func canAfford(_ cost: Resources) -> Bool {
        guard let capital else { return false }
        return ResourceType.allCases.allSatisfy { capital.storage[$0] >= cost[$0] }
    }

    func pawnName(_ id: UUID) -> String {
        selectedSettlement?.pawns.first { $0.id == id }?.name ?? "?"
    }

    func placeBuilding(_ buildingID: String, at coord: TileCoord) {
        guard let settlement = selectedSettlement else { return }
        world = GameEngine.placeBuilding(world, settlementID: settlement.id,
                                         buildingID: buildingID, at: coord, registry: registry)
        persist()
    }

    func demolish(at coord: TileCoord) {
        guard let settlement = selectedSettlement else { return }
        world = GameEngine.demolish(world, settlementID: settlement.id, at: coord)
        persist()
    }

    func assignPawn(_ pawnID: UUID, toPlacement placementID: UUID) {
        guard let settlement = selectedSettlement else { return }
        world = GameEngine.assignToBuilding(world, settlementID: settlement.id,
                                            pawnID: pawnID, placementID: placementID, registry: registry)
        persist()
    }

    func unassignPawn(_ pawnID: UUID) {
        guard let settlement = selectedSettlement else { return }
        world = GameEngine.unassignFromBuilding(world, settlementID: settlement.id, pawnID: pawnID)
        persist()
    }

    /// Per-tick production gained from the current layout's adjacency synergies.
    var viewedAdjacencyProduction: Resources {
        guard let settlement = selectedSettlement else { return Resources() }
        return ColonyBonus.adjacencyProduction(settlement, registry: registry)
    }

    /// Morale gained from the current layout's adjacency synergies.
    var viewedAdjacencyMorale: Double {
        guard let settlement = selectedSettlement else { return 0 }
        return ColonyBonus.adjacencyMorale(settlement, registry: registry)
    }

    func paintZone(_ kind: ZoneKind, at coord: TileCoord) {
        guard let settlement = selectedSettlement else { return }
        world = GameEngine.paintZone(world, settlementID: settlement.id, at: coord, kind: kind)
        persist()
    }

    func eraseZone(at coord: TileCoord) {
        guard let settlement = selectedSettlement else { return }
        world = GameEngine.eraseZone(world, settlementID: settlement.id, at: coord)
        persist()
    }

    /// Human-readable synergy descriptions for a building, for the inspector.
    func synergyText(for def: BuildingDefinition) -> [String] {
        def.adjacency.map { rule in
            let neighbour = buildingName(rule.neighbor)
            if let resource = rule.resource, rule.bonus != 0 {
                return "+\(Int(rule.bonus)) \(resource.displayName.lowercased()) next to \(neighbour)"
            }
            return "+\(Int(rule.morale)) morale next to \(neighbour)"
        }
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
