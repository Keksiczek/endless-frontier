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

    /// How full the roofs are allowed to get before the council raises another.
    ///
    /// **A ratio, not the last free bed**, and that is the whole of this
    /// constant. `PopulationEngine.headroomFactor` squares the free fraction of
    /// the beds, so a colony two-thirds housed is already breeding at a ninth of
    /// its vigour — while a council watching `population >= housing - 4` does
    /// not call a meeting until ninety-five per cent full. The two thresholds
    /// could never meet, so the council never met.
    ///
    /// Measured, seed 4242, two hundred years: **beds stood at 82 from year
    /// twenty to year two hundred**, population flat at 53–55, headroom down to
    /// 0.108 and a couple's best chance at a child 0.0007 a tick. Nothing was
    /// short of anything — granary full, fields at their wanted count — and the
    /// village simply could not become a town.
    ///
    /// Rule 6 in its plainest form, wearing rule 16's clothes: a council
    /// watching a *stock* while the thing it governs is throttled by a *ratio*.
    /// Build against the ratio the births actually feel.
    ///
    /// At 0.55 a colony at the trigger still breeds at a fifth of its vigour,
    /// and above it at more — enough that a village grows, not so much that it
    /// cannot fail.
    static let crowdedAbove = 0.55

    /// How many beds a colony of this many souls wants standing.
    ///
    /// Deliberately more than one per head. A colony housed exactly to its own
    /// size has zero headroom and therefore no next generation; the spare beds
    /// *are* the growth.
    public static func bedsWanted(for population: Double) -> Double {
        population / crowdedAbove
    }

    public static func advanceOneTick(
        _ state: WorldState, registry: GameDataRegistry
    ) -> WorldState {
        guard state.stewardEnabled, state.tick % interval == 0 else { return state }
        var s = state
        s = chooseResearch(s, registry: registry)
        for index in s.settlements.indices {
            s = keepMaterialsComing(s, index: index, registry: registry)
            s = raiseWhatIsShort(s, index: index, registry: registry)
            // Arms, coats and tools, and the handing out of them. The bench
            // knew about building materials and nothing else, so a colony left
            // to itself went two hundred years without making a spear.
            s = QuartermasterEngine.advance(s, index: index, registry: registry)
            // …and the yard. A colony that has a cartwright and never builds a
            // cart is the mounts system in the state it shipped in: four seams
            // wired, tested, and reading an empty yard for ever.
            s = keepTheYard(s, index: index, registry: registry)
            s = sendSomebodyOut(s, index: index, registry: registry)
            // …and, when it is doing well enough to spare them, a party that
            // does not come back: a daughter town on charted ground.
            s = foundIfItCan(s, index: index, registry: registry)
        }
        // …and the ways between them. Once per pass rather than per settlement:
        // a road belongs to the world, and `RoadEngine.wanted` already picks the
        // single edge carrying the most traffic through the worst country.
        //
        // Last, deliberately. A colony short of beds should raise a roof before
        // it paves anything, and everything above it takes what it needs first.
        s = RoadEngine.build(s, registry: registry)
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
        if housing < bedsWanted(for: settlement.population) {
            out.append(Counsel(
                id: "housing", weight: .wanting,
                headline: LocalizedText(values: [
                    .en: "The houses are close",
                    .cs: "V domech je těsno"]),
                detail: LocalizedText(values: [
                    .en: "\(Int(settlement.population)) souls to \(Int(housing)) beds — families stop growing long before the last bed is taken.",
                    .cs: "\(Int(settlement.population)) duší na \(Int(housing)) lůžek — rodiny přestanou růst dávno předtím, než dojde poslední lůžko."])))
        }
        if isBrimming(settlement) {
            out.append(Counsel(
                id: "stores", weight: .wanting,
                headline: LocalizedText(values: [
                    .en: "The stores are overflowing",
                    .cs: "Sklady přetékají"]),
                detail: LocalizedText(values: [
                    .en: "Everything earned past the cap is thrown away. Each store is deepened by the buildings that hold that good — a granary for grain, a warehouse for timber, a library for what is known.",
                    .cs: "Všechno nad strop se vyhazuje. Každý sklad prohlubují budovy, které to zboží drží — sýpka obilí, sklad dřevo, knihovna vědění."])))
        }
        if settlement.storage[.food] < settlement.storageCapacity[.food] * 0.2 {
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
    /// **How much of the bench the council may take.**
    ///
    /// `CraftingEngine.maxOrders` is twelve and this used to be all of them: one
    /// standing order per wanted material, and `wantedMaterials` unions the
    /// material list of *every building the colony has unlocked in every era it
    /// has reached* plus everything the gear bench asks for. Past the first age
    /// that is comfortably a dozen, so the queue filled with council orders and
    /// stayed full — which does three things at once, all of them invisible:
    ///
    /// - the player's own orders are **refused**, because `CraftingEngine.place`
    ///   returns the settlement unchanged when the queue is full and the panel's
    ///   buttons go dead;
    /// - `QuartermasterEngine` can never queue a spear or a coat, because it
    ///   runs after this one;
    /// - and every material trickles, because the bench's effort is split
    ///   twelve ways.
    ///
    /// Keks: *"crafteni je stale neprehledne … a crafti spatne."* Four slots
    /// left free is a bench the player still owns. If they fill it themselves,
    /// the council simply waits — which is the right way round.
    static let councilBenchShare = 8

    static func keepMaterialsComing(
        _ state: WorldState, index: Int, registry: GameDataRegistry
    ) -> WorldState {
        var s = state
        let settlement = s.settlements[index]
        // Only what this colony is actually short of, and only what it could
        // plausibly make here — **most useful first**.
        for materialID in shoppingList(for: settlement, in: s, registry: registry) {
            guard s.settlements[index].craftOrders.count < councilBenchShare else { break }
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
    ///
    /// **Every era it has reached, not just the first one.** This read
    /// `def.era == .earlySettlement`, which was true of the colony it was
    /// written for and false of every colony that outlives its first age: the
    /// council went on making the four things a hut and a granary want and
    /// never once ordered the timber bundle a cookhouse asks for, so the
    /// buildings of the age the colony had actually reached were unbuildable
    /// while its store sat at the cap. Caught from the other end by a test that
    /// asked whether a hundred-year-old colony could pay for the cheapest
    /// building in the book and found it could not — not for want of materials,
    /// for want of the *made* thing the recipe turns them into.
    ///
    /// Rule 6 wearing a content filter: a clause that was true of the state the
    /// code was written in, and silently false ever after.
    static func wantedMaterials(
        for settlement: Settlement, in state: WorldState, registry: GameDataRegistry
    ) -> [String] {
        var wanted: Set<String> = []
        for def in registry.buildings.values
        where def.era.index <= state.era.index
            && (def.era == .earlySettlement || state.unlockedBuildings.contains(def.id)) {
            wanted.formUnion(def.materialCost.keys)
        }
        // …and what the **gear** bench asks for, which is a different list.
        //
        // Measured with the quartermaster in and nothing else changed: a colony
        // armed forty of its fifty-five with spears and bows and clothed
        // **nobody, ever**. A coat is `leather_garb`, leather is `tan_leather`
        // out of hides the lodge had been stacking the whole time — and leather
        // is not a *building* material, so nothing on this list ever asked for
        // it, so the tannery never ran and `QuartermasterEngine.bestGear` found
        // no armour it could work. The same shape as the era filter above: a
        // demand list that names one consumer and is read as if it named them
        // all.
        wanted.formUnion(QuartermasterEngine.wantedMaterials(
            for: settlement, in: state, registry: registry))
        return wanted.sorted()
    }

    /// **What to make first.**
    ///
    /// `wantedMaterials` is a *set* — everything any building or piece of gear
    /// might ask for, sorted alphabetically, which is to say in no order at
    /// all. Walked in that order against a bench of twelve slots, the council
    /// stood a dozen standing orders and split its crafters twelve ways, and
    /// the four timber bundles standing between the colony and a warehouse
    /// arrived at a twelfth of the rate — if the alphabet ever got that far.
    ///
    /// So: the materials that unblock a building the colony **wants right now**
    /// come first, and among those the one that unblocks the most. Everything
    /// else follows in its old order, because a colony should still keep a
    /// little of everything about.
    static func shoppingList(
        for settlement: Settlement, in state: WorldState, registry: GameDataRegistry
    ) -> [String] {
        let all = wantedMaterials(for: settlement, in: state, registry: registry)
        // What is wanted but blocked, and on what.
        var unblocks: [String: Int] = [:]
        for def in wantedHere(settlement, in: state, registry: registry)
        where !GameEngine.hasMaterials(def.materialCost, in: state,
                                       settlementID: settlement.id) {
            for material in def.materialCost.keys { unblocks[material, default: 0] += 1 }
        }
        return all.sorted { a, b in
            let (ua, ub) = (unblocks[a] ?? 0, unblocks[b] ?? 0)
            return ua == ub ? a < b : ua > ub
        }
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

        // 1. Ground under crop. **Dinner outranks a bed**, and it has to.
        //
        //    This clause used to sit third, behind roofs and stores, which was
        //    survivable only while the colony was not really growing: a town
        //    that has stopped growing is not short of beds, so the housing
        //    clause fell through and the fields got their turn. Fix the
        //    fertility clock (§11.19) and the colony grows every year for two
        //    centuries — so housing is short *every year for two centuries*, and
        //    the clause below it is never reached. Measured, seed 4242: plots
        //    stood at **38 from year sixty to year two hundred** while
        //    `plotsWanted` climbed to 49 and the beds went 160 → 224. The
        //    council knew it was short of fields, said so, and built houses.
        //
        //    Rule 27 in a second place: a priority chain whose first branch has
        //    become permanently true starves everything under it. The ordering
        //    that survives growth is the one that is true of people — you can
        //    sleep four to a room for a season; you cannot eat next year's
        //    harvest this winter.
        if FarmEngine.plotsStanding(settlement)
            < FarmEngine.plotsWanted(for: settlement.population),
           let farm = best(of: affordable, by: { Double($0.plots) }) {
            return farm
        }

        // 2. A roof. Population is *throttled* by housing long before it is
        //    capped by it — `crowdedAbove` is where that starts to bite, and
        //    waiting for the last free bed is how the colony sat at 82 beds and
        //    fifty-five souls for a hundred and eighty years.
        let housing = ResourceLoop.housingCapacity(settlement, registry: registry)
        if housing < bedsWanted(for: settlement.population),
           let roof = best(of: affordable, by: { $0.housing }) {
            return roof
        }

        // 3. Somewhere to put things. A store at the brim is a colony throwing
        //    away everything it earns.
        //
        //    Below the fields on purpose, and it always was: a granary at the
        //    brim says nothing about whether the ground can still fill it next
        //    year. A store is a buffer; a field is an income.
        //    Typed storage (2026-08-13) made this clause sharper rather than
        //    harder: it used to rank by one number, so a colony drowning in
        //    timber answered with whatever had the biggest `storage` field. It
        //    now builds a store **for the good that is actually spilling** — a
        //    warehouse for timber, a library for knowledge, a bank for standing.
        let spilling = brimmingResources(settlement)
        if !spilling.isEmpty,
           let store = best(of: affordable, by: { def in
               spilling.reduce(0) { $0 + def.storage[$1] }
           }) {
            return store
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
        if settlement.storage[.food] < settlement.storageCapacity[.food] * 0.25 {
            let onTheShelf = CookingEngine.foodstuffs(registry)
                .reduce(0) { $0 + settlement.stockpile[$1, default: 0] }
            if onTheShelf >= sacksWorthCooking,
               CookingEngine.kitchens(at: settlement, registry: registry) == 0,
               let kitchen = best(of: affordable, by: { $0.work == .cooking ? 1 : 0 }) {
                return kitchen
            }
            // **No farm fallback.** It used to reach for one here, and that was
            // wrong twice over.
            //
            // Wrong by construction: clause 1 above already answers "the ground
            // is short" and takes the same `best(of:by:plots)`. So control only
            // arrives here when plots are *not* short — or when no farm is
            // affordable, in which case this lookup fails too. The branch could
            // therefore only ever fire in the one case where another field
            // changes nothing.
            //
            // And wrong in what it cost: a thin larder is thin for as long as
            // the famine lasts, so this branch was permanently true, and rule
            // 27 did the rest — everything below it starved. Measured, seed
            // 2025: `Emake` flat at 5.0 (one windmill) from year sixty to year
            // two hundred while demand climbed to 5.9 and the store sat at zero
            // from year 170. The brownout clause below was never reached, not
            // once, because the colony was hungry.
            //
            // Falling through is the honest answer. An empty larder with the
            // ground already broken and a cook already standing is not a
            // building problem, and the council saying nothing lets the clauses
            // under it — light, and breadth — have their turn.
        }

        // 3c. Light and heat. The council had **no clause for energy at all** —
        //     the word appeared once in this file, in a comment about an old
        //     bug — so a colony browned out and never once answered it.
        //
        //     Measured, seed 2025 at twelve thousand ticks: population 240 in
        //     the early industrial age draws `240 * 0.05 * 1.0` = twelve a tick
        //     (`ResourceLoop.domesticEnergyDemand`), the store went to zero
        //     around year 167 and stayed there, and morale bled
        //     `brownoutMoralePenalty` every tick for the rest of the run. Three
        //     windmills — five each, thirty-five materials each — would have
        //     covered it, out of a store of seven thousand. The council could
        //     always afford the answer; nobody ever asked the question.
        //
        //     Rule 16 wearing its other face: demand scales with **people** and
        //     supply with **buildings**, so this gap widens on its own every
        //     year the colony grows. It cannot be tuned away in
        //     `eraEnergyDemand`, because the multiplier is what makes an age
        //     feel different — it has to be *answered*, per tick, by a council
        //     that looks.
        //
        //     Below food and above breadth: a brownout is a standing bleed, not
        //     a death. Guarded by `best` returning nil when nothing affordable
        //     generates, so an early colony with no windmill unlocked falls
        //     straight through rather than starving the clause below it
        //     (rule 27).
        let draw = ResourceLoop.domesticEnergyDemand(
            population: settlement.population, era: state.era, config: registry.config)
        if draw > 0, generation(of: settlement, registry: registry) < draw,
           let generator = best(of: affordable, by: { $0.production[.energy] }) {
            return generator
        }

        // 4. Otherwise — and *only* out of genuine surplus — **what this
        //    colony is actually short of**, weighed by the people in the room.
        //
        //    This clause used to be "the cheapest thing we do not have yet,
        //    and once we have one of everything, the cheapest thing at all",
        //    which is the whole of the late game and is why Keks's town had
        //    five observatories and no smithy: *"steward staví knihovny a
        //    univerzity několikrát a nijaké výrobní nebo obranné budovy ne."*
        //    Nothing in it asked what the colony lacked, and nothing asked who
        //    was on the council. See `CouncilAppetite`.
        //
        //    Still gated on brimming stores: a colony that builds whenever it
        //    can afford to never has anything in hand, which is how the first
        //    cut of this drove materials to one and kept them there.
        guard hasSomethingSpare(settlement) else { return nil }
        let wanted = affordable
            .map { (def: $0, score: CouncilAppetite.score($0, for: settlement,
                                                          in: state, registry: registry)) }
            .filter { $0.score >= CouncilAppetite.worthBuilding }
        guard !wanted.isEmpty else { return nil }
        return wanted.min { a, b in
            a.score == b.score ? a.def.id < b.def.id : a.score > b.score
        }?.def.id
    }

    /// Whether the colony has enough put by to build for its own sake.
    public static func hasSomethingSpare(_ settlement: Settlement) -> Bool {
        let roof = settlement.storageCapacity[.materials]
        guard roof > 0 else { return false }
        return settlement.storage[.materials] >= roof * comfortable
    }

    /// Raw ingredients on the shelf past which "we have no kitchen" is the
    /// colony's actual problem rather than "we have no fields". A handful of
    /// berries is not an argument for a cookhouse; a winter's grain is.
    static let sacksWorthCooking = 20

    /// What the colony's standing buildings make in a tick, for one resource.
    ///
    /// Deliberately the **nameplate** figure off the definitions rather than
    /// what `ResourceLoop` actually banked last tick: the council is deciding
    /// whether to raise another generator, and a windmill idle for want of a
    /// hand is still a windmill. Asking the banked figure would have the town
    /// answer "no power" with a second windmill nobody is standing in.
    public static func production(
        of settlement: Settlement, _ resource: ResourceType, registry: GameDataRegistry
    ) -> Double {
        settlement.buildings.reduce(0.0) { acc, instance in
            acc + (registry.building(instance.definitionID)?.production[resource] ?? 0)
                * Double(instance.count)
        }
    }

    /// Shorthand for the one the brownout clause asks about.
    static func generation(
        of settlement: Settlement, registry: GameDataRegistry
    ) -> Double {
        production(of: settlement, .energy, registry: registry)
    }

    /// Whether any store is full enough to be spilling.
    public static func isBrimming(_ settlement: Settlement) -> Bool {
        !brimmingResources(settlement).isEmpty
    }

    /// **Which** stores are spilling. Each against its own roof, which is the
    /// whole point of typing capacity: a colony can be drowning in timber and
    /// short of grain in the same season, and one number could not say so.
    public static func brimmingResources(_ settlement: Settlement) -> [ResourceType] {
        let people = max(1, settlement.population)
        return ResourceType.allCases.filter { resource in
            let roof = settlement.storageCapacity[resource]
            guard roof > 0, settlement.storage[resource] >= roof * brimming else { return false }
            // **And there is such a thing as enough roof.**
            //
            // Measured after the council learned to weigh what it builds: a
            // colony of 158 souls stood at **124 buildings, 81 of them stores**
            // — eleven banks, eleven markets, eleven universities, twelve
            // railyards. Every one of them was a *store*, so every one of them
            // was chosen by the clause above, which had no notion of enough:
            // full store → build roof → fill it → build roof, for two
            // centuries. The materials roof reached 44 300 for 232 people.
            //
            // A store defers a spill; it never ends one. Past this much room
            // per soul the colony is not short of a warehouse, it is producing
            // more than it can ever use, and the council should let it spill
            // and spend its materials on something that does something.
            return roof / people < roofEnough(resource)
        }
    }

    /// How much room per soul is **enough** of a given good, past which more
    /// roof answers nothing.
    ///
    /// Food and materials are spent every tick, so a colony wants a real
    /// buffer of both — a bad winter is a season of eating the store. Energy
    /// is drawn steadily and generated steadily. Knowledge and standing are
    /// spent in lumps by research and by decisions, and a colony sitting on
    /// four hundred of either is not going to be saved by a fifth bank.
    static func roofEnough(_ resource: ResourceType) -> Double {
        switch resource {
        case .food: return 60
        case .materials: return 60
        case .energy: return 25
        case .knowledge: return 20
        case .influence: return 20
        }
    }

    /// Everything this settlement could break ground on right now: unlocked,
    /// paid for out of its own stores, and with the crafted goods on the shelf.
    static func buildableHere(
        _ settlement: Settlement, in state: WorldState, registry: GameDataRegistry
    ) -> [BuildingDefinition] {
        wantedHere(settlement, in: state, registry: registry).filter { def in
            GameEngine.hasMaterials(def.materialCost, in: state, settlementID: settlement.id)
        }
    }

    /// Everything the colony **would** break ground on if the made things were
    /// on the shelf — every guard `buildableHere` applies except that one.
    ///
    /// Split out because the difference between the two lists is the council's
    /// shopping list, and until this existed nothing computed it. A colony in
    /// the medieval age, six hundred materials of six hundred, could build
    /// exactly **one** thing — a well — because a warehouse wants four timber
    /// bundles, a granary wants timber bundles, and nearly every definition in
    /// the book names some made thing. The store it needed was blocked on four
    /// bundles it had never been asked to make.
    static func wantedHere(
        _ settlement: Settlement, in state: WorldState, registry: GameDataRegistry
    ) -> [BuildingDefinition] {
        let shortOfRoofs = ResourceLoop.housingCapacity(settlement, registry: registry)
            < bedsWanted(for: settlement.population)
        // What is spilling over the brim right now. A colony at its cap is
        // **destroying everything it earns**, every tick, and the building that
        // stops that is not a discretionary purchase — the same argument
        // shelter already wins below.
        let spilling = brimmingResources(settlement)
        return registry.buildings.values.filter { def in
            guard state.unlockedBuildings.contains(def.id) || def.era == .earlySettlement
            else { return false }
            guard def.era.index <= state.era.index else { return false }
            // Paid for, and with as much again left in hand afterwards.
            for resource in ResourceType.allCases {
                let cost = def.cost[resource]
                guard cost > 0 else { continue }
                guard settlement.storage[resource] - cost >= cost * reserve else { return false }
            }
            // And not the ninth of something a town this size wants one of —
            // unless it is a roof and the colony is short of roofs.
            //
            // A dwelling has to be exempt, because `allowed` grows with the
            // population and the population is bounded by the beds: leave the
            // cap on and the colony walks into "no more huts until there are
            // more people, and no more people until there are more huts". The
            // same two-century freeze this engine exists to end, arriving later
            // and at a bigger number. How many dwellings a town wants is the
            // housing clause's business (`bedsWanted`), not this one's.
            let standing = settlement.buildings
                .first { $0.definitionID == def.id }?.count ?? 0
            let allowed = 1 + Int(settlement.population / soulsPerRepeatBuilding)
            guard (shortOfRoofs && def.sleepers > 0) || standing < allowed else { return false }

            // …and the colony can still *keep* it standing (rule 25) — unless
            // it is a roof and there are not enough. **Shelter is not a
            // discretionary purchase.** The upkeep brake refused huts the
            // moment the ledger tightened, which is a colony forbidden to grow:
            // `PopulationEngine.headroomFactor` throttles births on the free
            // fraction of the beds, so no roofs means no people means no income
            // means still no roofs. Caught by "A town at its housing ceiling
            // raises a roof" — the same exemption the repeat cap already makes
            // one line above, and for the same reason.
            //
            // **And a store for a good that is spilling is exempt too**, for
            // a reason the brake cannot see: it weighs a building's *materials
            // production* against its upkeep, and a warehouse produces nothing
            // at all. So a colony pinned at its materials cap was refused the
            // one building that raises the cap — for ever, because being at the
            // cap does not change the ledger the brake reads. Measured from the
            // player's side: year 28, six hundred materials of six hundred, a
            // market and no warehouse, and the council answering with an
            // observatory. Keks: *"nestavi sklady materialu a divne budovy."*
            //
            // The trade is not close. A warehouse costs twenty-five and holds
            // three hundred and fifty; its upkeep is `upkeepRateOfCost` of that
            // twenty-five, against a colony throwing away its whole quarry
            // output every tick it stands full.
            let answersTheBrim = spilling.contains { def.storage[$0] > 0 }
            guard (shortOfRoofs && def.sleepers > 0) || answersTheBrim
                    || canAffordToKeep(def, at: settlement, registry: registry) else { return false }
            return true
        }
    }

    /// Whether the colony's income still covers its upkeep once this is
    /// standing.
    ///
    /// **Rule 25, measured.** `upkeepRateOfCost` is 0.005 *a tick*, which is
    /// thirty per cent of a building's price every year, for ever — and the
    /// council had no notion of it. It builds for breadth out of surplus
    /// (`hasSomethingSpare`), so every sitting added a standing cost and most
    /// of them added no income at all.
    ///
    /// Measured by `ZZStewardProbe` on the day the timber lock was opened, seed
    /// 4242: the colony reached the **modern era** with 163 buildings and a
    /// population of 204 — the furthest this game has ever got — and then
    /// materials went 7886 → 3084 → **9**, food to zero, and the population fell
    /// 204 → 28 in twenty years. It did not starve for want of ground or hands.
    /// It had built more than it could feed, and the ledger took the difference
    /// out of everything at once.
    ///
    /// The test is the honest one: after this building stands, does the colony
    /// still make more than it spends? A lumberyard passes on its own
    /// production; a fourth observatory does not.
    static func canAffordToKeep(
        _ def: BuildingDefinition, at settlement: Settlement, registry: GameDataRegistry
    ) -> Bool {
        let config = registry.config
        var income = 0.0
        var outgoing = 0.0
        for instance in settlement.buildings {
            guard let standing = registry.building(instance.definitionID) else { continue }
            let count = Double(instance.count)
            income += standing.production[.materials] * count
            outgoing += ResourceLoop.upkeep(for: standing, config: config)[.materials] * count
            outgoing += standing.consumption[.materials] * count
        }
        income += def.production[.materials]
        outgoing += ResourceLoop.upkeep(for: def, config: config)[.materials]
        outgoing += def.consumption[.materials]
        // A margin, not a knife edge: a colony that breaks exactly even has
        // nothing left the season a lumberyard falls derelict.
        return income >= outgoing * upkeepMargin
    }

    /// How much more than its upkeep a colony wants to be earning before it
    /// takes on another standing cost.
    static let upkeepMargin = 1.15

    // MARK: - The yard

    /// How many colonists one conveyance is worth keeping for.
    ///
    /// **Rule 14 — a rate times an entity count.** `StableEngine.yardLimit` is
    /// 24, which is a ceiling on absurdity and not a plan: twenty-four elk at
    /// 0.35 food a tick is more than a village of forty eats. A yard is sized
    /// against the people who would push the things, so it grows with the
    /// colony and never outruns it.
    static let colonistsPerConveyance = 6.0

    /// Builds one thing for the yard when the colony is short of them.
    ///
    /// Same "acts only in the gaps" rule as the rest of the council: it stops
    /// at the size the population justifies, it never spends the last of the
    /// stores, and it will not take on a mouth the colony is not already
    /// feeding comfortably.
    static func keepTheYard(
        _ state: WorldState, index: Int, registry: GameDataRegistry
    ) -> WorldState {
        let settlement = state.settlements[index]
        let wanted = min(StableEngine.yardLimit,
                         Int(settlement.population / colonistsPerConveyance))
        guard settlement.conveyances.count < wanted else { return state }

        // The best thing it can actually make: what carries most, and between
        // equals what moves fastest. Ties broken by id, because two identical
        // definitions must not order differently between runs (rule 3).
        let choices = registry.conveyances.values
            .filter { def in
                StableEngine.canBuild(def.id, in: state, settlement: settlement,
                                      registry: registry)
                    && canFeedIt(def, at: settlement)
            }
            .sorted { a, b in
                if a.cargo != b.cargo { return a.cargo > b.cargo }
                if a.pace != b.pace { return a.pace > b.pace }
                return a.id < b.id
            }
        guard let best = choices.first else { return state }
        var s = state
        s.settlements[index] = StableEngine.build(
            settlement, definitionID: best.id, in: state, registry: registry)
        return s
    }

    /// Whether the colony is comfortable enough in everything this thing draws
    /// to take on another one that draws it every tick, for ever.
    ///
    /// Deliberately a *comfort* test on each store this eats out of rather than
    /// a projection: the council has no net-rate to read, and a horse bought
    /// out of a granary at a third full is a horse eating the winter.
    static func canFeedIt(_ def: ConveyanceDefinition, at settlement: Settlement) -> Bool {
        for resource in ResourceType.allCases where def.upkeep[resource] > 0 {
            let roof = settlement.storageCapacity[resource]
            guard roof > 0, settlement.storage[resource] >= roof * comfortable
            else { return false }
        }
        // …and what it *burns*, which is a thing on the shelf rather than a
        // number on the ledger. A council that cannot see the fuel builds the
        // lorry anyway, and the lorry stands in the yard for ever: `upkeep`
        // and `material_upkeep` are two different questions and this only
        // ever asked the first.
        for (item, due) in def.materialUpkeep where due > 0 {
            // A tickful is not a supply. `fuelRunway` ticks of it is the
            // difference between "we have some" and "we can keep it running",
            // and it is measured in ticks so it scales with how thirsty the
            // thing is rather than with a number somebody picked.
            guard settlement.stockpile[item, default: 0] >= due * fuelRunway
            else { return false }
        }
        return true
    }

    /// How many ticks of fuel the colony wants on the shelf before it builds
    /// something else that drinks. A tick is two real minutes, so this is about
    /// two hours of it running — long enough that a refinery going down is a
    /// problem to solve rather than an immediate stoppage.
    static let fuelRunway = 60

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

        // **The valley gets every other sitting.**
        //
        // Charting the fog used to be tried first and unconditionally, and it
        // takes the sitting whenever it succeeds. That was survivable while the
        // colony was poor, because `canAffordToLookAround` wants a brimming
        // store and the store was never brimming. Once the ledger stopped
        // bleeding (`upkeepRateOfCost` 0.03 → 0.005) it was affordable *every
        // time* — measured, seed 4242: thirteen regions charted in forty years,
        // four workable landmarks standing in the colony's own valley the whole
        // while, and **not one party ever sent to any of them**. Nothing was
        // broken; the first branch of a priority chain simply became always-true
        // and starved everything underneath it. Rule 6, wearing an `if`.
        //
        // Alternating is the smallest honest fix: both paths keep a share, and
        // whichever has nothing to do hands its turn to the other on the spot.
        let valleyFirst = (state.tick / outwardInterval) % 2 == 0
        if valleyFirst, canSpareTheHands(settlement, registry: registry),
           let worked = workTheValley(state, index: index, registry: registry) { return worked }
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

    // MARK: - Founding

    /// The smallest a colony may be and still send a founding party out.
    ///
    /// Six settlers leave with them (`ExpansionEngine.settlers`), and a village
    /// that gives up six of thirty has gutted its own workforce. This is
    /// deliberately well above the point where the colony is merely surviving:
    /// a daughter town is what a colony does when it is *doing well*, not a way
    /// out of trouble.
    static let smallestFounder = 55.0

    /// How many souls a colony wants for each town it holds before it founds
    /// another. Without this the capital seeds a settlement every few years the
    /// moment it clears the floor, and a realm of eight hamlets of six people
    /// is not a civilisation — it is one colony with its hands cut off.
    static let soulsPerSettlement = 45.0

    /// Sends out a founding party, when the colony is big enough to spare one
    /// and there is charted ground with nobody on it.
    ///
    /// **The fourth room the player was standing in the doorway of.**
    /// `ExpansionEngine.foundOutpost` is reached only through
    /// `GameEngine.foundOutpost`, and that is only ever called from the UI — so
    /// a world nobody touches holds exactly one settlement for ever. Measured,
    /// seed 4242, two hundred years: **thirty-three fully charted regions with
    /// nobody living in them**, and not one founding party in the whole run.
    ///
    /// It was not a small thing to leave undone. Era milestones asked for two,
    /// three, four settlements, so an unattended colony was **locked in the
    /// ancient age for ever** and could never build the medieval or industrial
    /// buildings its own scholars had unlocked — `buildableHere` filters on
    /// `def.era.index <= state.era.index`, so the whole later half of the game
    /// was unreachable. The settlement gates are gone from `eras.json` now, and
    /// this is the other half: population is what the remaining gates ask for,
    /// and one valley cannot hold enough people to answer them.
    static func foundIfItCan(
        _ state: WorldState, index: Int, registry: GameDataRegistry
    ) -> WorldState {
        // Its own cadence, and never on the sitting that sends people out to
        // explore: a colony that empties itself of hands in the same season it
        // gives away six of them is a colony that stops working. Hence the
        // offset — `sendSomebodyOut` takes the sitting on the interval, this
        // one takes the sitting after it, so the two never draw on the same
        // roster in the same season.
        guard state.tick % outwardInterval == interval else { return state }
        let settlement = state.settlements[index]
        guard settlement.kind == .capital,
              settlement.policy.roster != .nobody,
              settlement.population >= smallestFounder,
              settlement.population
                  >= soulsPerSettlement * Double(state.settlements.count + 1),
              canSpareTheHands(settlement, registry: registry) else { return state }
        // Charted ground with nobody on it — the nearest, so a realm grows
        // outward from its own valley rather than scattering. Ties on id, so
        // the same world founds the same towns in the same order (rule 2).
        guard let home = state.regions.first(where: { $0.id == settlement.regionID }),
              let pick = ExpansionEngine.foundableRegions(state)
                .min(by: { a, b in
                    let da = a.coord.distance(to: home.coord)
                    let db = b.coord.distance(to: home.coord)
                    return da == db ? a.id.uuidString < b.id.uuidString : da < db
                })
        else { return state }
        let founded = ExpansionEngine.foundOutpost(
            state, regionID: pick.id, name: "", registry: registry)
        guard founded.settlements.count > state.settlements.count else { return state }
        var s = founded
        if let town = s.settlements.last {
            s.settlements[index].journal.append(
                tick: s.tick, kind: .arrival, text: LocalizedText(values: [
                    .en: "A founding party walked out to raise \(town.name).",
                    .cs: "Skupina osadníků vyšla založit \(town.name)."]))
        }
        return s
    }

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
        ResourceType.allCases.allSatisfy { resource in
            guard ExplorationEngine.expeditionResources.contains(resource) else { return true }
            let roof = settlement.storageCapacity[resource]
            return roof > 0 && settlement.storage[resource] >= roof * brimming
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
