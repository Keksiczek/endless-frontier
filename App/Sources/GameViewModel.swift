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
        // Load an existing save, otherwise start a fresh world in the
        // player's language.
        if let saved = try? store.load() {
            self.world = saved
        } else {
            self.world = GameWorldFactory.newGame(registry: registry,
                                                  language: AppStrings.language)
        }
        // Battles already on the books at load are history, not news — mark them
        // seen so the report only springs up for fights fought from here on.
        self.acknowledgedBattleIDs = Set(world.settlements.compactMap { $0.lastBattle?.id })
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

    /// Battles the player has already been shown. A fight lands as a `BattleLog`
    /// on the settlement; the report springs up once, and stays down after the
    /// player closes it — see `battleReport`.
    private var acknowledgedBattleIDs: Set<UUID> = []

    private var liveLoop: Task<Void, Never>?
    /// The separate, much faster heartbeat a live raid runs on.
    private var siegeLoop: Task<Void, Never>?
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
        stopSiegeLoop()
    }

    // MARK: - A raid, while it is happening

    /// The fight going on at the settlement you are looking at, if one is.
    var siege: Siege? { selectedSettlement?.siege }

    /// Real seconds between two exchanges while the player is watching.
    ///
    /// The whole point of `Siege`: the world clock would carry the fight at
    /// one step every seven and a half seconds, which is a battle you can
    /// stare straight at and see nothing happen in. Driven from here it runs
    /// at a pace a person can read *and* answer — and because a step is fought
    /// once by whoever reaches it first, running ahead of the world clock does
    /// not change the fight, only who got to steer it.
    private let siegeStepSeconds: Double = 1.4

    /// Starts stepping a live raid. Idempotent; stops itself when the fighting
    /// does.
    func startSiegeLoop() {
        guard siegeLoop == nil, siege != nil else { return }
        siegeLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.siegeStepSeconds ?? 1.4))
                guard let self, self.advanceSiegeStep() else { break }
            }
            self?.siegeLoop = nil
        }
    }

    func stopSiegeLoop() {
        siegeLoop?.cancel()
        siegeLoop = nil
    }

    /// Fights one more exchange. Returns whether the raid is still going.
    @discardableResult
    func advanceSiegeStep() -> Bool {
        guard let index = selectedSettlementIndex,
              let running = world.settlements[index].siege else { return false }
        let fought = SiegeEngine.fight(
            world.settlements[index], to: running.advancedTo + 1, registry: registry)
        world.settlements[index] = fought.settlement
        if let finished = fought.concluded {
            // The neighbours are charged for what the attempt actually cost
            // them, exactly as `ActionLoop` would have done it.
            world = SiegeEngine.chargeAttacker(world, for: finished)
            persist()
            return false
        }
        return true
    }

    // MARK: - A sickness, while it is happening

    /// The outbreak at the settlement you are looking at, if there is one.
    var outbreak: Outbreak? { selectedSettlement?.outbreak }

    var outbreakPlague: PlagueDefinition? {
        outbreak.flatMap { registry.plague($0.plagueID) }
    }

    /// The carriers who are furthest gone, by name — so a sickness is a list of
    /// people rather than a number.
    var worstAfflicted: [String] {
        guard let outbreak, let settlement = selectedSettlement else { return [] }
        return settlement.pawns
            .filter { outbreak.infected.contains($0.id) }
            .sorted { $0.health < $1.health }
            .prefix(4)
            .map(\.name)
    }

    /// Shuts the gates, or opens them again.
    func setQuarantine(_ on: Bool) {
        guard let index = selectedSettlementIndex else { return }
        world.settlements[index] = PlagueEngine.setQuarantine(world.settlements[index], on)
        persist()
    }

    /// Tells the line what to do. Recorded on the siege, so it is part of the
    /// world rather than a thing that happened outside it.
    func order(posture: Siege.Posture) {
        guard let index = selectedSettlementIndex else { return }
        world.settlements[index] = SiegeEngine.order(
            world.settlements[index], posture: posture)
    }

    /// Pulls a colonist out of the line, or sends them back to it.
    func setInLine(_ pawnID: UUID, holding: Bool) {
        guard let index = selectedSettlementIndex else { return }
        world.settlements[index] = SiegeEngine.withdraw(
            world.settlements[index], pawnID: pawnID, out: !holding)
    }

    /// Sends one colonist somewhere, or after somebody.
    ///
    /// The tap half of the fight. Written onto the siege, like the posture, so
    /// it is an input the same seed replays from rather than a thing that
    /// happened outside the world.
    func command(_ order: SiegeCommand) {
        guard let index = selectedSettlementIndex else { return }
        switch order {
        case .move(let pawn, let point):
            world.settlements[index] = SiegeEngine.order(
                world.settlements[index], pawnID: pawn, moveTo: point)
        case .engage(let pawn, let raider):
            world.settlements[index] = SiegeEngine.order(
                world.settlements[index], pawnID: pawn, engage: raider)
        }
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

    // MARK: - Battle report

    /// The most recent battle at the viewed settlement that the player has not
    /// yet dismissed — the canvas plays the fight, this makes it legible and
    /// impossible to miss even if you looked away. Reactive: when a tick lands a
    /// new `lastBattle`, the observed `world` change surfaces this card.
    var battleReport: BattleLog? {
        guard let battle = selectedSettlement?.lastBattle,
              !acknowledgedBattleIDs.contains(battle.id) else { return nil }
        return battle
    }

    /// Puts the battle report away for good.
    func dismissBattleReport() {
        if let id = selectedSettlement?.lastBattle?.id {
            acknowledgedBattleIDs.insert(id)
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
        // while remaining fully deterministic once started. The world is
        // founded in the player's language: newborns, outposts and freshly
        // charted places will speak it from then on.
        let seed = UInt64.random(in: UInt64.min...UInt64.max)
        world = GameWorldFactory.newGame(registry: registry, seed: seed,
                                         language: AppStrings.language)
        lastSessionEvents = []
        persist()
    }

    func explore(_ regionID: UUID) {
        world = GameEngine.startExpedition(world, targetRegionID: regionID, registry: registry)
        persist()
    }

    func foundOutpost(in regionID: UUID) {
        // An empty name asks the engine to forge one in the world's language.
        world = GameEngine.foundOutpost(world, regionID: regionID, name: "", registry: registry)
        persist()
    }

    private(set) var lastSiteOutcome: SiteOutcome?

    /// Sends a party out to a ruin or an anomaly on the world map.
    ///
    /// This used to resolve the whole thing on the spot: `interactWithSite` and
    /// an outcome, same tick, nobody gone. Now hands leave the colony and are
    /// away for as long as the country is wide, and the report lands when they
    /// walk back in — see `RegionExpeditionEngine`.
    func sendToSite(_ regionID: UUID) {
        guard let settlement = selectedSettlement,
              let sent = RegionExpeditionEngine.dispatch(
                world, settlementID: settlement.id, regionID: regionID,
                registry: registry) else { return }
        world = sent
        persist()
    }

    /// The party on the road to this region, if one is out.
    func partyOut(toRegion regionID: UUID) -> RegionExpedition? {
        world.regionExpeditions.first { $0.regionID == regionID }
    }

    /// Every party out of the valley, for the world map to draw.
    var regionExpeditions: [RegionExpedition] { world.regionExpeditions }

    func dismissSiteOutcome() { lastSiteOutcome = nil }

    /// The region a find came from, so the outcome can be shown over the ground
    /// it happened on rather than in a bare dialog.
    func region(named name: String) -> Region? {
        world.regions.first { $0.name == name }
    }

    /// Player-facing label for the site action available in a region, if any.
    func siteActionLabel(for region: Region) -> String? {
        guard region.hasActiveSite else { return nil }
        let cs = AppStrings.language == .cs
        switch region.kind {
        case .ruins: return cs ? "Prozkoumat zříceniny" : "Excavate Ruins"
        case .dungeon: return cs ? "Sestoupit do podzemí" : "Delve Dungeon"
        case .anomaly: return cs ? "Zkoumat anomálii" : "Probe Anomaly"
        case .sanctuary: return cs ? "Vykonat pouť" : "Make Pilgrimage"
        case .lostCity:
            // A dead city takes several runs to strip — say which this is.
            let run = (region.siteVisits ?? 0) + 1
            return cs
                ? "Prohledat mrtvé město (\(run)/\(SiteEngine.lostCityVisits))"
                : "Salvage the Lost City (\(run)/\(SiteEngine.lostCityVisits))"
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

    /// Where the viewed settlement sits in the world's array — needed wherever
    /// it has to be written back rather than read.
    var selectedSettlementIndex: Int? {
        if let id = selectedSettlementID,
           let index = world.settlements.firstIndex(where: { $0.id == id }) { return index }
        return world.settlements.isEmpty ? nil : 0
    }

    // MARK: - Standing orders

    /// The viewed colony's standing orders, or the default ones if there is no
    /// colony to have any.
    var policy: ColonyPolicy { selectedSettlement?.policy ?? ColonyPolicy() }

    /// Writes the viewed colony's standing orders. This is the *one* place the
    /// player sets how a town of sixty is run, and the engine keeps it from
    /// there — no per-colonist clicking, and nothing here reaches past the
    /// policy into anybody's assignment.
    func setPolicy(_ policy: ColonyPolicy) {
        guard let id = selectedSettlement?.id,
              let index = world.settlements.firstIndex(where: { $0.id == id }),
              world.settlements[index].policy != policy else { return }
        world.settlements[index].policy = policy
        persist()
    }

    func setTrade(_ work: WorkKind, to stance: ColonyPolicy.TradeStance) {
        setPolicy(policy.setting(work, to: stance))
    }

    func setRation(_ ration: ColonyPolicy.Ration) {
        var updated = policy
        updated.ration = ration
        setPolicy(updated)
    }

    func setRoster(_ roster: ColonyPolicy.Roster) {
        var updated = policy
        updated.roster = roster
        setPolicy(updated)
    }

    /// How many days of food the granary holds at the current ration, so the
    /// ration picker can say what the choice is actually worth.
    func foodDaysRemaining(_ settlement: Settlement) -> Int {
        let mouths = Double(settlement.pawns.count)
        guard mouths > 0 else { return 0 }
        // Steady-state upkeep: decay/hungerPerMeal meals a tick, each costing
        // a ration's share of a full meal.
        let perTick = mouths * 0.1 * settlement.policy.ration.foodPerMeal
            / max(0.01, settlement.policy.ration.hungerPerMeal)
        guard perTick > 0 else { return 0 }
        return Int(settlement.storage[.food] / perTick)
    }

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

    /// The weather where the settlement in view actually stands, and what the
    /// thermometer reads today.
    ///
    /// Temperature was computed in two places and shown in none: the only
    /// reading anywhere was a colonist's "Warmth" bar, which is a comfort and
    /// not a temperature, so nobody could connect the season, the valley, the
    /// roof and the coat to the number. This is the same `Climate` the
    /// simulation runs on — never a second one.
    var climate: Climate {
        guard let settlement = selectedSettlement else { return .temperate }
        return Climate.of(settlement, in: world, registry: registry)
    }

    var temperature: Double { climate.temperature(season) }

    /// Why one colonist is as warm as they are: the day, the roof, the coat and
    /// the fires, out of the same engine that decides whether they freeze.
    func warmthReckoning(for pawn: Pawn) -> ComfortEngine.Reckoning? {
        guard let settlement = selectedSettlement else { return nil }
        return ComfortEngine.reckon(
            season: season, housed: pawn.homeID != nil, clothing: pawn.equipment.count,
            shelter: ComfortEngine.shelter(settlement, registry: registry),
            climate: climate)
    }

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

    /// Materials worth offering as cargo: anything the game defines as a
    /// material, so a route can be set up *before* the origin has any — you
    /// plan the supply line, then dig.
    var tradableMaterials: [(id: String, name: String)] {
        registry.items.values
            .filter { $0.slot == .material }
            .map { (id: $0.id, name: $0.name.resolve(AppStrings.language)) }
            .sorted { $0.name < $1.name }
    }

    /// A standing shipment of goods — timber, ore, clay — between settlements.
    /// The reason a coastal colony with no iron is a *choice* rather than a
    /// dead end.
    func addMaterialRoute(from: UUID, to: UUID, materialID: String, units: Double) {
        world = GameEngine.addMaterialRoute(world, from: from, to: to,
                                            materialID: materialID, unitsPerTick: units,
                                            registry: registry)
        persist()
    }

    /// What a route carries, named for display.
    func routeCargoName(_ route: TradeRoute) -> String {
        route.materialID.map { itemName($0) } ?? route.resource.displayName
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
        registry.item(recipe.outputItemID)?.name.resolve(AppStrings.language) ?? recipe.outputItemID
    }

    func recipeOutputRarity(_ recipe: RecipeDefinition) -> ItemRarity? {
        registry.item(recipe.outputItemID)?.rarity
    }

    func itemName(_ id: String) -> String {
        registry.item(id)?.name.resolve(AppStrings.language) ?? id
    }

    /// What the settlement holds of a material, counting both the stockpile and
    /// any loose instances (loot, or a save from before the stockpile existed).
    func materialCount(_ id: String) -> Int {
        guard let s = selectedSettlement else { return 0 }
        return (s.stockpile[id] ?? 0) + s.inventory.count { $0.definitionID == id }
    }

    /// The materials on hand, named and ordered for display. Raw goods first —
    /// they are what the colony's own work produces — then everything made.
    var stockpileEntries: [(id: String, name: String, count: Int, isRaw: Bool)] {
        guard let s = selectedSettlement else { return [] }
        let raw = Set(LocalResourceKind.allCases.compactMap(\.rawMaterialID))
            .union([ResourceLoop.hideItemID])
        var counts = s.stockpile
        for instance in s.inventory where registry.item(instance.definitionID)?.slot == .material {
            counts[instance.definitionID, default: 0] += 1
        }
        return counts
            .filter { $0.value > 0 }
            .map { (id: $0.key, name: itemName($0.key), count: $0.value, isRaw: raw.contains($0.key)) }
            .sorted {
                if $0.isRaw != $1.isRaw { return $0.isRaw }
                return $0.name < $1.name
            }
    }

    /// Recipes this settlement is *equipped* to make — its building and tech
    /// gates are satisfied — whether or not the materials are on hand.
    ///
    /// The panel used to list only what could be crafted right now, so a player
    /// short one ingot saw nothing at all and had no way to learn what the
    /// workshop was for. Showing the shortfall is the whole point.
    var recipesHere: [RecipeDefinition] {
        guard let s = selectedSettlement else { return [] }
        return registry.recipes.values
            .filter { recipe in
                if let building = recipe.requiresBuilding,
                   !s.buildings.contains(where: { $0.definitionID == building }) { return false }
                if let tech = recipe.requiresTech, !world.researchedTechs.contains(tech) { return false }
                return true
            }
            .sorted { $0.name.resolve(AppStrings.language) < $1.name.resolve(AppStrings.language) }
    }

    /// Whether everything a recipe needs is on hand at the selected settlement.
    func canCraft(_ recipe: RecipeDefinition) -> Bool {
        CraftingEngine.canCraft(recipe, in: world,
                                settlementID: selectedSettlement?.id, registry: registry)
    }

    // MARK: - The bench

    /// What the viewed colony has been told to make, oldest first.
    var craftOrders: [CraftOrder] {
        (selectedSettlement?.craftOrders ?? []).sorted { $0.placedTick < $1.placedTick }
    }

    /// How many colonists are actually at the bench. Crafting is work now, and
    /// an order with nobody on it is a bar that never moves — the panel says so
    /// rather than letting the player wait on nothing.
    var crafterCount: Int {
        guard let settlement = selectedSettlement else { return 0 }
        let adult = Pawn.adultAgeYears * registry.config.ticksPerYear
        return settlement.pawns.count {
            $0.assignedWork == .crafting && $0.age >= adult && !$0.isBroken && !$0.isAway
        }
    }

    func recipe(_ id: String) -> RecipeDefinition? { registry.recipes[id] }

    /// How far through the one currently on the bench, 0…1.
    func craftFraction(_ order: CraftOrder) -> Double {
        guard let recipe = registry.recipes[order.recipeID] else { return 0 }
        return order.fraction(of: recipe.workPerUnit)
    }

    /// Why an order is not moving, when it is not — the shop is missing, the
    /// knowledge is missing, or the shelf is bare.
    func craftBlockedReason(_ order: CraftOrder) -> String? {
        guard let settlement = selectedSettlement,
              let recipe = registry.recipes[order.recipeID] else { return nil }
        let cs = AppStrings.language == .cs
        if order.paused { return nil }
        if let building = recipe.requiresBuilding,
           !settlement.buildings.contains(where: { $0.definitionID == building }) {
            let name = registry.building(building)?.name.resolve(AppStrings.language) ?? building
            return (cs ? "Chybí stavba: " : "Needs ") + name
        }
        if let tech = recipe.requiresTech, !world.researchedTechs.contains(tech) {
            return cs ? "Chybí výzkum" : "Needs research"
        }
        if !CraftingEngine.hasMaterials(recipe, at: settlement) {
            return cs ? "Chybí materiál" : "Short of materials"
        }
        return nil
    }

    /// Roughly how long one will take at the bench as it is staffed right now.
    func craftTimeLabel(_ recipe: RecipeDefinition) -> String {
        let cs = AppStrings.language == .cs
        guard let settlement = selectedSettlement else { return "—" }
        let adult = Pawn.adultAgeYears * registry.config.ticksPerYear
        let hands = settlement.pawns
            .filter { $0.assignedWork == .crafting && $0.age >= adult }
            .reduce(0.0) { $0 + CraftingEngine.effort(of: $1) }
        guard hands > 0 else {
            return "\(Int(recipe.workPerUnit)) " + (cs ? "práce" : "work")
        }
        let ticks = Int((recipe.workPerUnit / hands).rounded(.up))
        return "~\(ticks) " + (cs ? "tiků" : "ticks")
    }

    func placeCraftOrder(_ recipeID: String, count: Int?) {
        guard let index = selectedSettlementIndex else { return }
        world.settlements[index] = CraftingEngine.place(
            world.settlements[index], recipeID: recipeID, count: count,
            tick: world.tick, registry: registry)
        persist()
    }

    func cancelCraftOrder(_ orderID: UUID) {
        guard let index = selectedSettlementIndex else { return }
        world.settlements[index] = CraftingEngine.cancel(
            world.settlements[index], orderID: orderID)
        persist()
    }

    func setCraftPaused(_ orderID: UUID, paused: Bool) {
        guard let index = selectedSettlementIndex else { return }
        world.settlements[index] = CraftingEngine.setPaused(
            world.settlements[index], orderID: orderID, paused: paused)
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

    /// The simulation clock, handed to the canvas so it can interpolate between
    /// ticks. Presentation only — nothing in the simulation reads it back.
    var tickClock: TickClock {
        TickClock(tick: world.tick, lastTickAt: world.lastRealTimestamp,
                  realSecondsPerTick: registry.config.realSecondsPerTick)
    }

    /// `world.tick` plus how far the current tick has already run.
    func continuousTick(now: Date = Date()) -> Double {
        tickClock.continuous(at: now)
    }

    // MARK: - The local map

    /// Sends a party out to work a landmark the scouts found. The haul lands
    /// when they walk back in — watch them go.
    func dispatchToPOI(_ poiID: Int) {
        guard let settlement = selectedSettlement else { return }
        world = GameEngine.dispatchToPOI(
            world, settlementID: settlement.id, poiID: poiID, registry: registry)
        persist()
    }

    /// The live POI behind a canvas selection — read fresh every time, so a
    /// card never offers an action the world has since spent.
    func poi(_ poiID: Int) -> LocalPOI? {
        viewedLocalMap?.pois.first { $0.id == poiID }
    }

    /// The beast behind a tap — wild if the valley still has it, kept if the
    /// colony does. Both are the same `Animal`; only one of them has a collar.
    func animal(_ animalID: UUID) -> (animal: Animal, kept: TamedAnimal?)? {
        if let wild = viewedLocalMap?.wildlife.animals.first(where: { $0.id == animalID }) {
            return (wild, nil)
        }
        if let kept = selectedSettlement?.tamed.first(where: { $0.animal.id == animalID }) {
            return (kept.animal, kept)
        }
        return nil
    }

    /// The party out at a place, if one is.
    func expedition(forPOI poiID: Int) -> POIExpedition? {
        selectedSettlement?.expedition(forPOI: poiID)
    }

    /// Who went, by name — the card names them so a party is people, not a
    /// number.
    func partyNames(_ expedition: POIExpedition) -> [String] {
        guard let settlement = selectedSettlement else { return [] }
        return expedition.memberIDs.compactMap { id in
            settlement.pawns.first { $0.id == id }?.name
        }
    }

    /// Whether the colony could actually field a party for this place right
    /// now — the card explains itself rather than showing a dead button.
    func canDispatch(to poi: LocalPOI) -> Bool {
        guard let settlement = selectedSettlement else { return false }
        guard poi.isWorkable(tick: world.tick, ticksPerYear: ticksPerYear),
              !settlement.hasPartyOut(poiID: poi.id) else { return false }
        return !LocalPOIEngine.chooseParty(settlement, for: poi.kind,
                                           ticksPerYear: ticksPerYear).isEmpty
    }

    /// Points the settlement's scouts at a patch of fog.
    func sendScouts(to point: LocalPoint) {
        guard let settlement = selectedSettlement else { return }
        world = GameEngine.sendScouts(world, settlementID: settlement.id, to: point)
        persist()
    }

    /// Adults currently walking the frontier — the card says whether an order
    /// has anyone to carry it.
    var scoutCount: Int {
        selectedSettlement?.pawns.filter {
            $0.assignedWork == .scouting && $0.isAdult(ticksPerYear: ticksPerYear) && !$0.isBroken
        }.count ?? 0
    }

    // MARK: - Colony layout (in-settlement base building)

    /// The build grid of the settlement currently being viewed.
    var viewedColony: ColonyMap? { selectedSettlement?.colony }

    /// Buildings the player can lay down right now (unlocked or early-era).
    var placeableBuildings: [BuildingDefinition] {
        registry.buildings.values
            .filter { world.unlockedBuildings.contains($0.id) || $0.era == .earlySettlement }
            .sorted { $0.name.resolve(AppStrings.language) < $1.name.resolve(AppStrings.language) }
    }

    func buildingDefinition(_ id: String) -> BuildingDefinition? { registry.building(id) }

    /// What one instance of a building costs per tick to keep standing.
    func upkeep(for definition: BuildingDefinition) -> Resources {
        ResourceLoop.upkeep(for: definition, config: registry.config)
    }

    /// Whether the settlement holds the goods a building calls for.
    func hasMaterials(for def: BuildingDefinition) -> Bool {
        guard let settlement = selectedSettlement else { return false }
        return GameEngine.hasMaterials(def.materialCost, in: world, settlementID: settlement.id)
    }

    /// "4/6 trámy, 0/2 cihly" — what the build still needs off the pile.
    func materialCostSummary(_ def: BuildingDefinition) -> String? {
        guard !def.materialCost.isEmpty else { return nil }
        return def.materialCost.sorted { $0.key < $1.key }
            .map { "\(itemName($0.key)) \(materialCount($0.key))/\($0.value)" }
            .joined(separator: ", ")
    }

    func buildingName(_ id: String) -> String {
        registry.building(id)?.name.resolve(AppStrings.language) ?? id
    }

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
        let cs = AppStrings.language == .cs
        return def.adjacency.map { rule in
            let neighbour = buildingName(rule.neighbor)
            if let resource = rule.resource, rule.bonus != 0 {
                return cs
                    ? "+\(Int(rule.bonus)) \(resource.displayName.lowercased()) vedle: \(neighbour)"
                    : "+\(Int(rule.bonus)) \(resource.displayName.lowercased()) next to \(neighbour)"
            }
            return cs
                ? "+\(Int(rule.morale)) morálka vedle: \(neighbour)"
                : "+\(Int(rule.morale)) morale next to \(neighbour)"
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
            .sorted { $0.name.resolve(AppStrings.language) < $1.name.resolve(AppStrings.language) }
    }

    func techName(_ id: String) -> String {
        registry.tech(id)?.name.resolve(AppStrings.language) ?? id
    }

    private func persist() {
        try? store.save(world)
    }
}
