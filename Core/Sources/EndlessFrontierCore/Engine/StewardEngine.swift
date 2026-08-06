import Foundation

/// Keeps the colony moving when nobody is telling it what to do.
///
/// This is the hole the whole game was sitting in. Measured over twelve
/// thousand ticks — two hundred in-game years — a fresh world came out with
/// **three buildings, no construction ever started, no tech ever researched,
/// and still in the first era**, while food, materials, knowledge and influence
/// all sat pinned at the storage cap the entire time. The colony was not dying.
/// It was *frozen*: housing stuck at thirty, so population oscillated around
/// twenty-six for two centuries.
///
/// The chain, every link of which was waiting on the player:
///
/// - `activeResearch` is only ever set from the UI, so no tech was ever
///   studied, so no era ever advanced, so no building was ever unlocked.
/// - `GameEngine.build` is only ever called from the UI, so even the buildings
///   that *were* unlocked were never raised — including the hut that would have
///   lifted the housing ceiling, and the granary that would have lifted the
///   storage cap for every resource.
/// - `CraftingEngine.place` is only ever called from the UI, so the
///   `timber_bundle` that half the early buildings need was never made.
///
/// None of that is acceptable in a game whose premise is that you close it and
/// come back in a week. So the council runs the town on standing sense: it
/// studies the cheapest thing it can, keeps timber on the shelf, and raises
/// whatever the colony is most short of.
///
/// **It never overrules the player.** It acts only in the gaps — when nothing
/// is being researched, when nothing is being built, when no order stands on
/// the bench. Anything you choose stays chosen until it is finished.
public enum StewardEngine {

    /// How often the council sits. Building and research decisions are not
    /// per-tick business, and this runs inside the offline catch-up path that
    /// replays tens of thousands of ticks (rule 4).
    ///
    /// Sixty is about a season. At twenty-five the colony broke ground forty
    /// times per thousand ticks and a quarter-century town had thirty-one
    /// buildings — which is not a settlement growing, it is a spreadsheet
    /// emptying itself.
    public static let interval = 60

    /// How much a council keeps in hand, as a multiple of what it is about to
    /// spend. At 1.0 it will only break ground while it can pay for the thing
    /// *twice*.
    ///
    /// Deliberately relative to the **cost**, not to the warehouse. A share of
    /// capacity looks reasonable and is a trap: raising granaries multiplies
    /// the cap, the reserve grows with it, and a colony whose income has not
    /// changed can suddenly never afford anything again. Measured: capacity
    /// went 500 → 2750 and the town stopped building for the next ten thousand
    /// ticks.
    static let reserve = 1.0

    /// A store this full is a colony with something genuinely spare, which is
    /// the only time it builds for breadth rather than for need.
    static let comfortable = 0.45

    /// How many of the *same* building a town wants, per this many souls.
    /// Without a cap the council answered "the granary is full" with another
    /// granary, nine times over.
    static let soulsPerRepeatBuilding = 15.0

    /// How much of the store counts as "full". A resource sitting here is one
    /// the colony is throwing away every tick.
    static let brimming = 0.92

    /// The colony keeps roughly this many of each building material on the
    /// shelf, so there is something to build *with* when it decides to build.
    static let materialStock = 12

    /// Housing headroom the council likes to keep. Below this it raises a roof.
    static let housingHeadroom = 4

    public static func advanceOneTick(
        _ state: WorldState, registry: GameDataRegistry
    ) -> WorldState {
        guard state.stewardEnabled, state.tick % interval == 0 else { return state }
        var s = state
        s = chooseResearch(s, registry: registry)
        for index in s.settlements.indices {
            s = keepMaterialsComing(s, index: index, registry: registry)
            s = raiseWhatIsShort(s, index: index, registry: registry)
            s = sendSomebodyOut(s, index: index, registry: registry)
        }
        return s
    }

    // MARK: - What the colony is doing, in words

    /// One thing the colony is doing, or one thing it is short of.
    public struct Counsel: Sendable, Equatable, Identifiable {
        public enum Weight: Sendable, Equatable {
            case doing      // under way right now
            case wanting    // the colony is short of this
            case idle       // nothing to report
        }
        public let id: String
        public let weight: Weight
        public let headline: LocalizedText
        public let detail: LocalizedText
    }

    /// What the council would tell you if you asked.
    ///
    /// The game had no answer to "what should I be doing?" anywhere in it. The
    /// quest panel is a list of long arcs, the diagnostics screen is a wall of
    /// measurements, and nothing said *this colony, right now, is waiting on
    /// timber*. This reads the same signals the council itself acts on, so the
    /// advice is never a guess about the simulation — it is the simulation's
    /// own reasoning, said out loud.
    public static func counsel(
        for settlement: Settlement, in state: WorldState, registry: GameDataRegistry
    ) -> [Counsel] {
        var out: [Counsel] = []

        if let project = settlement.constructions.first,
           let def = registry.building(project.definitionID) {
            let left = Int(max(0, project.required - project.progress))
            out.append(Counsel(
                id: "building", weight: .doing,
                headline: LocalizedText(values: [
                    .en: "Raising \(def.name.resolve(.en))",
                    .cs: "Staví se: \(def.name.resolve(.cs))"]),
                detail: LocalizedText(values: [
                    .en: "\(left) of work left. Builders make it go faster.",
                    .cs: "Zbývá \(left) práce. Stavitelé to urychlí."])))
        }

        if let studyID = state.activeResearch, let tech = registry.tech(studyID) {
            let price = TechEngine.cost(of: tech, in: state, config: registry.config)
            let left = Int(max(0, price - state.researchProgress))
            out.append(Counsel(
                id: "research", weight: .doing,
                headline: LocalizedText(values: [
                    .en: "Studying \(tech.name.resolve(.en))",
                    .cs: "Zkoumá se: \(tech.name.resolve(.cs))"]),
                detail: LocalizedText(values: [
                    .en: "\(left) knowledge still wanted. Scholars and a library bring it in.",
                    .cs: "Chybí \(left) vědění. Přinesou ho učenci a knihovna."])))
        }

        // What it is short of, worst first.
        let housing = ResourceLoop.housingCapacity(settlement, registry: registry)
        if settlement.population >= housing - Double(housingHeadroom) {
            out.append(Counsel(
                id: "housing", weight: .wanting,
                headline: LocalizedText(values: [
                    .en: "Nowhere left to sleep",
                    .cs: "Není kde spát"]),
                detail: LocalizedText(values: [
                    .en: "\(Int(settlement.population)) souls to \(Int(housing)) beds — the colony cannot grow until something is raised.",
                    .cs: "\(Int(settlement.population)) duší na \(Int(housing)) lůžek — dokud se nepostaví, osada neporoste."])))
        }
        if isBrimming(settlement) {
            out.append(Counsel(
                id: "stores", weight: .wanting,
                headline: LocalizedText(values: [
                    .en: "The stores are overflowing",
                    .cs: "Sklady přetékají"]),
                detail: LocalizedText(values: [
                    .en: "Everything earned past the cap is thrown away. A granary deepens the store — for every resource, not only grain.",
                    .cs: "Všechno nad strop se vyhazuje. Sýpka sklad prohloubí — u všech surovin, ne jen u obilí."])))
        }
        if settlement.storage[.food] < settlement.storageCapacity * 0.2 {
            out.append(Counsel(
                id: "food", weight: .wanting,
                headline: LocalizedText(values: [
                    .en: "The larder is thin",
                    .cs: "Spíž je prázdná"]),
                detail: LocalizedText(values: [
                    .en: "Put more hands on farming and hunting, or raise a farm.",
                    .cs: "Přesuň lidi na pole a lov, nebo postav statek."])))
        }
        // A bench with nobody at it is a queue that will never move.
        if !settlement.craftOrders.isEmpty,
           !settlement.pawns.contains(where: { $0.assignedWork == .crafting }) {
            out.append(Counsel(
                id: "bench", weight: .wanting,
                headline: LocalizedText(values: [
                    .en: "Nobody is at the bench",
                    .cs: "U ponku nikdo nestojí"]),
                detail: LocalizedText(values: [
                    .en: "Orders are standing and no one is a crafter. Nothing will be made.",
                    .cs: "Zakázky čekají a nikdo není řemeslník. Nic se nevyrobí."])))
        }

        if out.isEmpty {
            out.append(Counsel(
                id: "calm", weight: .idle,
                headline: LocalizedText(values: [
                    .en: "The colony wants for nothing",
                    .cs: "Osadě nic nechybí"]),
                detail: LocalizedText(values: [
                    .en: "Grow it, send a party out, or set the standing orders to something new.",
                    .cs: "Rozšiř ji, vyprav výpravu, nebo přenastav stálé rozkazy."])))
        }
        return out
    }

    // MARK: - Study

    /// Picks the cheapest thing the colony could learn next.
    ///
    /// Cheapest-first rather than clever: it walks the tree from the bottom, so
    /// a colony left alone genuinely climbs it, and a player who wants
    /// something specific has only to say so — an explicit choice is never
    /// touched, because this runs only when nothing is being studied.
    public static func chooseResearch(
        _ state: WorldState, registry: GameDataRegistry
    ) -> WorldState {
        guard state.activeResearch == nil else { return state }
        guard let pick = nextTech(for: state, registry: registry) else { return state }
        return TechEngine.setResearch(state, techID: pick, registry: registry)
    }

    /// The cheapest researchable tech, ties broken by id so the same world
    /// always makes the same choice.
    public static func nextTech(
        for state: WorldState, registry: GameDataRegistry
    ) -> String? {
        registry.techs.values
            .filter { tech in
                guard tech.requires.allSatisfy(state.researchedTechs.contains) else { return false }
                return tech.repeatable || !state.researchedTechs.contains(tech.id)
            }
            .min { a, b in
                let ca = TechEngine.cost(of: a, in: state, config: registry.config)
                let cb = TechEngine.cost(of: b, in: state, config: registry.config)
                return ca == cb ? a.id < b.id : ca < cb
            }?
            .id
    }

    // MARK: - The shelf

    /// Keeps a standing order for the building materials the colony can make.
    ///
    /// Half the early buildings ask for `timber_bundle`, which comes off a
    /// bench, from an order nobody was ever placing. A standing order is the
    /// right shape for it: the colony always wants some timber about, the way
    /// it always wants some food.
    static func keepMaterialsComing(
        _ state: WorldState, index: Int, registry: GameDataRegistry
    ) -> WorldState {
        var s = state
        let settlement = s.settlements[index]
        // Only what this colony is actually short of, and only what it could
        // plausibly make here.
        for materialID in wantedMaterials(for: settlement, registry: registry) {
            let held = CraftingEngine.materialCounts(settlement)[materialID] ?? 0
            guard held < materialStock else { continue }
            // One standing order per material is enough — it never finishes.
            guard !settlement.craftOrders.contains(where: {
                registry.recipes[$0.recipeID]?.outputItemID == materialID
            }) else { continue }
            guard let recipe = cheapestRecipe(making: materialID, at: settlement,
                                              in: s, registry: registry) else { continue }
            s.settlements[index] = CraftingEngine.place(
                s.settlements[index], recipeID: recipe, count: nil,
                tick: s.tick, registry: registry)
        }
        return s
    }

    /// The crafted materials the buildings this colony could raise ask for.
    static func wantedMaterials(
        for settlement: Settlement, registry: GameDataRegistry
    ) -> [String] {
        var wanted: Set<String> = []
        for def in registry.buildings.values where def.era == .earlySettlement {
            wanted.formUnion(def.materialCost.keys)
        }
        return wanted.sorted()
    }

    /// The cheapest recipe making a given material that this colony could
    /// actually work — the shop stands and the knowledge exists.
    static func cheapestRecipe(
        making materialID: String, at settlement: Settlement,
        in state: WorldState, registry: GameDataRegistry
    ) -> String? {
        registry.recipes.values
            .filter { recipe in
                guard recipe.outputItemID == materialID else { return false }
                if let building = recipe.requiresBuilding,
                   !settlement.buildings.contains(where: { $0.definitionID == building }) {
                    return false
                }
                if let tech = recipe.requiresTech,
                   !state.researchedTechs.contains(tech) { return false }
                return true
            }
            .min { a, b in
                a.workPerUnit == b.workPerUnit
                    ? a.id < b.id : a.workPerUnit < b.workPerUnit
            }?
            .id
    }

    // MARK: - Building

    /// Raises whatever the colony is most short of, if it can pay for it.
    static func raiseWhatIsShort(
        _ state: WorldState, index: Int, registry: GameDataRegistry
    ) -> WorldState {
        let settlement = state.settlements[index]
        // One project at a time. A queue of scaffolding nobody is working is
        // not progress, and it is the player's to decide to open a second.
        guard settlement.constructions.isEmpty else { return state }
        guard let pick = nextBuilding(for: settlement, in: state, registry: registry)
        else { return state }
        return GameEngine.build(state, settlementID: settlement.id,
                                buildingID: pick, registry: registry)
    }

    /// What the colony should raise next, or nil if there is nothing it both
    /// needs and can pay for.
    ///
    /// The order is what a council would actually argue about: somewhere to
    /// sleep, somewhere to put things, something to eat, and then whatever is
    /// missing. Named needs rather than a score, so the reason a colony built
    /// a granary is a sentence and not a number.
    public static func nextBuilding(
        for settlement: Settlement, in state: WorldState, registry: GameDataRegistry
    ) -> String? {
        let affordable = buildableHere(settlement, in: state, registry: registry)
        guard !affordable.isEmpty else { return nil }

        // 1. A roof. Population is capped by housing, so a colony at its
        //    ceiling stops growing entirely — which is exactly the two hundred
        //    frozen years this engine exists to end.
        let housing = ResourceLoop.housingCapacity(settlement, registry: registry)
        if settlement.population >= housing - Double(housingHeadroom),
           let roof = best(of: affordable, by: { $0.housing }) {
            return roof
        }

        // 2. Somewhere to put things. A store at the brim is a colony throwing
        //    away everything it earns.
        if isBrimming(settlement),
           let store = best(of: affordable, by: { $0.storage }) {
            return store
        }

        // 2b. Ground under crop for the mouths there are.
        //
        //     This clause is about *capacity*, not about stock, and it has to
        //     come before the larder one — a granary at the brim says nothing
        //     about whether the fields can still fill it next year. Measured
        //     without it: two farms and twelve plots feeding a colony that grew
        //     to seventy-four, food pinned at the cap right up until the season
        //     it wasn't, and then eighty-seven dead of hunger inside ten years.
        //     A store is a buffer; a field is an income. Rule 6 in its plainest
        //     form — check the rate can reach the threshold, and do it before
        //     the threshold arrives.
        if FarmEngine.plotsStanding(settlement)
            < FarmEngine.plotsWanted(for: settlement.population),
           let farm = best(of: affordable, by: { Double($0.plots) }) {
            return farm
        }

        // 3. Something to eat, if the larder is thin — and the council has to
        //    know *which* half of the food chain is short, because the two want
        //    opposite buildings and building the wrong one changes nothing.
        //
        //    A colony with sacks on the shelf and an empty larder does not need
        //    another field; it needs somebody able to cook, and a fire to do it
        //    over. A colony with an empty larder and an empty shelf needs
        //    ground. Ranking farms by `production[.food]` — which is what this
        //    clause used to do — stopped meaning anything the moment a farm
        //    became a place that owns plots rather than a food faucet, and
        //    would have quietly returned nil for ever.
        if settlement.storage[.food] < settlement.storageCapacity * 0.25 {
            let onTheShelf = CookingEngine.foodstuffs(registry)
                .reduce(0) { $0 + settlement.stockpile[$1, default: 0] }
            if onTheShelf >= sacksWorthCooking,
               CookingEngine.kitchens(at: settlement, registry: registry) == 0,
               let kitchen = best(of: affordable, by: { $0.work == .cooking ? 1 : 0 }) {
                return kitchen
            }
            if let farm = best(of: affordable, by: { Double($0.plots) }) {
                return farm
            }
        }

        // 4. Otherwise — and *only* out of genuine surplus — the cheapest
        //    thing the colony does not have at all. Breadth before depth, so a
        //    town gets a library and a quarry before a second farm.
        //
        //    Gated on brimming stores on purpose: a colony that builds whenever
        //    it can afford to never has anything in hand, which is how the
        //    first cut of this drove materials to one and kept them there.
        guard hasSomethingSpare(settlement) else { return nil }
        let standing = Set(settlement.buildings.map(\.definitionID))
        let novel = affordable.filter { !standing.contains($0.id) }
        return (novel.isEmpty ? affordable : novel)
            .min { a, b in
                let ca = a.cost[.materials], cb = b.cost[.materials]
                return ca == cb ? a.id < b.id : ca < cb
            }?
            .id
    }

    /// Whether the colony has enough put by to build for its own sake.
    public static func hasSomethingSpare(_ settlement: Settlement) -> Bool {
        guard settlement.storageCapacity > 0 else { return false }
        return settlement.storage[.materials] >= settlement.storageCapacity * comfortable
    }

    /// Raw ingredients on the shelf past which "we have no kitchen" is the
    /// colony's actual problem rather than "we have no fields". A handful of
    /// berries is not an argument for a cookhouse; a winter's grain is.
    static let sacksWorthCooking = 20

    /// Whether any store is full enough to be spilling.
    public static func isBrimming(_ settlement: Settlement) -> Bool {
        guard settlement.storageCapacity > 0 else { return false }
        return ResourceType.allCases.contains {
            settlement.storage[$0] >= settlement.storageCapacity * brimming
        }
    }

    /// Everything this settlement could break ground on right now: unlocked,
    /// paid for out of its own stores, and with the crafted goods on the shelf.
    static func buildableHere(
        _ settlement: Settlement, in state: WorldState, registry: GameDataRegistry
    ) -> [BuildingDefinition] {
        registry.buildings.values.filter { def in
            guard state.unlockedBuildings.contains(def.id) || def.era == .earlySettlement
            else { return false }
            guard def.era.index <= state.era.index else { return false }
            // Paid for, and with as much again left in hand afterwards.
            for resource in ResourceType.allCases {
                let cost = def.cost[resource]
                guard cost > 0 else { continue }
                guard settlement.storage[resource] - cost >= cost * reserve else { return false }
            }
            // And not the ninth of something a town this size wants one of.
            let standing = settlement.buildings
                .first { $0.definitionID == def.id }?.count ?? 0
            let allowed = 1 + Int(settlement.population / soulsPerRepeatBuilding)
            guard standing < allowed else { return false }
            return GameEngine.hasMaterials(def.materialCost, in: state,
                                           settlementID: settlement.id)
        }
    }

    // MARK: - Sending people out

    /// Puts a party on the road when there are spare hands and nobody is out.
    ///
    /// The council did three things — study, keep timber on the shelf, raise
    /// what is short — and never once left the valley. A player who does not
    /// personally tap the world map therefore saw *none* of the expedition
    /// content: the fog never lifted, the ruins were never worked, the
    /// landmarks in the neighbouring regions were never visited. All three
    /// paths existed and worked; nothing autonomous ever called them.
    ///
    /// Same "acts only in the gaps" rule as the rest of the council. Every
    /// dispatch below refuses on its own when a party is already out, when the
    /// standing roster says nobody leaves, or when the colony cannot spare the
    /// people — so an explicit choice by the player is never overridden and a
    /// town of six never sends four of them down a cave.
    ///
    /// In the order a council would argue it: know where you are first, then
    /// work what is on your own doorstep, then go over the hill.
    static func sendSomebodyOut(
        _ state: WorldState, index: Int, registry: GameDataRegistry
    ) -> WorldState {
        let settlement = state.settlements[index]
        guard settlement.policy.roster != .nobody else { return state }
        // The council sits four times a year and it must not decide to send
        // somebody out at every sitting: unguarded, that charted twenty-six
        // regions in fifty years and left the colony too poor to build.
        // Once every few years is a standing order; four times a year is a
        // policy of permanent absence.
        guard state.tick % outwardInterval == 0 else { return state }
        if canAffordToLookAround(settlement),
           let charted = chartTheFog(state, registry: registry) { return charted }
        guard canSpareTheHands(settlement, registry: registry) else { return state }
        if let worked = workTheValley(state, index: index, registry: registry) { return worked }
        return goOverTheHill(state, index: index, registry: registry) ?? state
    }

    /// How much of its working strength a council will have out of the valley
    /// at once, and the smallest colony that will send anybody at all.
    ///
    /// `LocalPOIEngine.chooseParty` already refuses to strip a settlement bare,
    /// but "bare" there means *two people left standing* — which is the right
    /// floor for a party the player asked for and far too generous for a
    /// standing order. Measured: a town of forty had four to seven people on
    /// the road permanently, and stopped growing at forty.
    static let handsAbroad = 0.12
    static let smallestPartySender = 12

    /// How often the council will even consider sending somebody out of the
    /// valley. A multiple of `interval`, so it lands on a sitting.
    static let outwardInterval = interval * 3

    static func canSpareTheHands(
        _ settlement: Settlement, registry: GameDataRegistry
    ) -> Bool {
        let ticksPerYear = max(1, registry.config.ticksPerYear)
        let adults = settlement.pawns.filter {
            $0.isAdult(ticksPerYear: ticksPerYear) && !$0.isBroken
        }
        guard adults.count >= smallestPartySender else { return false }
        return Double(adults.count { $0.isAway }) < Double(adults.count) * handsAbroad
    }

    /// Whether the colony has enough put by that looking over the hill is not
    /// taken out of somebody's dinner.
    ///
    /// An expedition is paid for in food and timber, and the council sits four
    /// times a year: unguarded, it charted twenty-six regions in fifty years
    /// and spent every material the town would otherwise have built with.
    /// Measured — 44 buildings and a population of 62 became 33 and 32, and the
    /// colony never left the first era. Exactly the shape rule 6 warns about,
    /// running the other way: a new sink that quietly starves an existing one.
    ///
    /// So the bar is set **above** the one building has to clear
    /// (`hasSomethingSpare`, at `comfortable`) rather than beside it: the
    /// colony looks over the hill out of *overflow*, when the store is at the
    /// brim and the next barrow of timber would be thrown away anyway. Raising
    /// a roof always wins the argument, which is right — you explore from a
    /// full granary, not from a full-ish one.
    static func canAffordToLookAround(_ settlement: Settlement) -> Bool {
        guard settlement.storageCapacity > 0 else { return false }
        return ResourceType.allCases.allSatisfy { resource in
            ExplorationEngine.expeditionResources.contains(resource)
                ? settlement.storage[resource] >= settlement.storageCapacity * brimming
                : true
        }
    }

    /// The nearest unknown region, if the colony can pay for the trip.
    ///
    /// Nearest to anything already held, so the frontier grows outward from the
    /// colony rather than jumping about the map. Ties on id.
    static func chartTheFog(
        _ state: WorldState, registry: GameDataRegistry
    ) -> WorldState? {
        guard state.activeExpedition == nil else { return nil }
        let held = state.regions.filter { $0.explorationState != .unknown }.map(\.coord)
        guard !held.isEmpty else { return nil }
        func reach(_ region: Region) -> Int {
            held.map { region.coord.distance(to: $0) }.min() ?? Int.max
        }
        let pick = ExplorationEngine.exploreableRegions(state)
            .filter { ExplorationEngine.canAfford(expeditionTo: $0, in: state, registry: registry) }
            .min { a, b in
                let ra = reach(a), rb = reach(b)
                if ra != rb { return ra < rb }
                // Somewhere safe before somewhere sheer, then by id.
                if a.hazardLevel != b.hazardLevel { return a.hazardLevel < b.hazardLevel }
                return a.id.uuidString < b.id.uuidString
            }
        guard let pick else { return nil }
        let out = ExplorationEngine.startExpedition(
            state, targetRegionID: pick.id, registry: registry)
        return out.activeExpedition == nil ? nil : out
    }

    /// A landmark in the colony's own valley that nobody is working.
    static func workTheValley(
        _ state: WorldState, index: Int, registry: GameDataRegistry
    ) -> WorldState? {
        let settlement = state.settlements[index]
        // One party out of the valley at a time. Two is the colony emptying
        // itself, and it is the player's call to open a second.
        guard settlement.expeditions.isEmpty, let map = settlement.localMap else { return nil }
        let ticksPerYear = max(1, registry.config.ticksPerYear)
        for poi in map.pois.sorted(by: { $0.id < $1.id })
        where poi.isWorkable(tick: state.tick, ticksPerYear: ticksPerYear) {
            if let out = LocalPOIEngine.dispatch(
                state, settlementID: settlement.id, poiID: poi.id, registry: registry) {
                return out
            }
        }
        return nil
    }

    /// …and failing that, a site in a region the colony has already charted.
    static func goOverTheHill(
        _ state: WorldState, index: Int, registry: GameDataRegistry
    ) -> WorldState? {
        let settlement = state.settlements[index]
        guard state.regionExpeditions.isEmpty else { return nil }
        for region in state.regions
            .filter({ $0.explorationState != .unknown && $0.hasActiveSite })
            .sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            if let out = RegionExpeditionEngine.dispatch(
                state, settlementID: settlement.id, regionID: region.id, registry: registry) {
                return out
            }
        }
        return nil
    }

    /// The affordable building with the most of something, ties by id. Returns
    /// nil when nothing on the list offers any of it at all.
    private static func best(
        of options: [BuildingDefinition], by value: (BuildingDefinition) -> Double
    ) -> String? {
        options
            .filter { value($0) > 0 }
            .min { a, b in
                let va = value(a), vb = value(b)
                return va == vb ? a.id < b.id : va > vb
            }?
            .id
    }
}
