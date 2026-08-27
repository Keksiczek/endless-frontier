import Foundation

/// The last link: raw ingredients on the shelf become **food** in the larder.
///
/// Before this, `storage[.food]` was where a farmer's skill went. There was no
/// step between the field and the meal, which is why a colony could have a
/// granary, a harvest, a kitchen in the building list and a cook in the
/// population, and none of those four things meant anything.
///
/// Now grain, roots, greens, meat and berries sit in `Settlement.stockpile`
/// where the haulers left them, and somebody with `WorkKind.cooking` has to
/// turn them into servings. `storage[.food]` still means exactly what every
/// reader of it already assumed — **meals ready to eat** — so `ErrandEngine`,
/// the famine, trade, caravans, expedition provisions, events and every
/// authored effect are untouched. What changed is where the number comes from.
///
/// Two safety valves, both deliberate, because a chain with a new link in it
/// has a new way to kill everybody:
///
/// - **A colony with no cookhouse still cooks**, over the fire, slower and only
///   the simple meals. Otherwise a fresh colony starves before it can build
///   one, and a burned kitchen is an extinction event.
/// - **A colony with no cook still eats**, badly, straight off the shelf — see
///   `ErrandEngine.rawFoodValue`. Losing your last cook must be a hard season,
///   not the end.
///
/// Deterministic: no randomness, and the meal chosen is a total order over the
/// meal table.
public enum CookingEngine {

    /// Worker-ticks a cook of no skill puts in each tick, and what a full twenty
    /// of skill adds. The same shape as `CraftingEngine.effort` and
    /// `FarmEngine.reapingEffort` — one idea of what a trained pair of hands is
    /// worth, in three places that each need it.
    static let effortPerCook = 1.0
    static let skillEffort = 1.3

    /// What a fire in the open is worth against a proper kitchen. Enough to
    /// keep a young colony fed while it saves up for the cookhouse, little
    /// enough that building one is obviously right.
    public static let hearthFactor: Double = 0.5

    /// Cooks stop when the larder is full. Standing over a pot to tip it into a
    /// granary that cannot hold it burns the harvest for nothing — and a colony
    /// whose stores are full has better uses for three pairs of hands.
    static let fullEnough: Double = 0.995

    /// The most banked effort a kitchen carries into the next tick: **one batch
    /// of the dearest thing on the table**.
    ///
    /// A ceiling has to be here. Without one a colony with cooks and no
    /// ingredients spins progress up for a decade and then turns a single sack
    /// of grain into a year's dinners at once — the trap `CraftingEngine` had to
    /// be taught (§6.14). One batch is the right *size* for it.
    ///
    /// **Which** batch was not. Capped at the *cheapest* meal, the bank could
    /// never reach the work a dearer one costs — and `best(for:)` chooses by
    /// what the shelf can spare, not by what the morning's work can afford. So a
    /// kitchen with a full shelf reached for the stew every tick, could never
    /// pay for it, and cooked **nothing at all**: the `while` loop never turned
    /// over once, and the cheaper pot it could have afforded was never
    /// considered.
    ///
    /// It only bit a kitchen with *one* cook, which is why nobody saw it. Two
    /// unskilled cooks clear a stew in a tick; one needs four levels of skill
    /// before their hands plus the old 0.8 ceiling reach 2.0, and a sick one
    /// needs twelve. Measured on seed 4242: a colony of twenty-three with
    /// fourteen plots, eleven hundred units of raw harvest on the shelf and a
    /// cook on the staff, with `storage[.food]` at **zero for a hundred years**
    /// and eighteen dead of hunger. Rule 6 in the kitchen — a threshold the rate
    /// meant to cross it cannot reach.
    ///
    /// Read through here rather than recomputed, so the ceiling and the cost it
    /// has to clear are one number in one place (rule 8). The number itself is
    /// worked out once when the meal table is loaded — this runs every tick of
    /// every settlement, and the dearest pot does not change between the answer
    /// and the next question (rule 4).
    public static func bankCeiling(_ registry: GameDataRegistry) -> Double {
        registry.dearestMealWork
    }

    // MARK: - The tick

    public static func advanceOneTick(
        _ state: WorldState, registry: GameDataRegistry
    ) -> WorldState {
        var s = state
        for index in s.settlements.indices {
            s.settlements[index] = advanceOneTick(
                s.settlements[index], registry: registry, tick: s.tick)
        }
        return s
    }

    /// One settlement's kitchens for one tick.
    public static func advanceOneTick(
        _ settlement: Settlement, registry: GameDataRegistry, tick: Int
    ) -> Settlement {
        var s = settlement
        guard s.storage[.food] < s.storageCapacity[.food] * fullEnough else { return s }
        let hands = effort(of: s, registry: registry)
        guard hands > 0 else { return s }

        let hasKitchen = kitchens(at: s, registry: registry) > 0
        s.kitchenProgress += hands * (hasKitchen ? 1 : hearthFactor)

        // Work down the banked effort one batch at a time, re-choosing the meal
        // after each because the shelf has changed: a colony that runs out of
        // meat mid-tick finishes the tick on pottage rather than stalling.
        var cooked: [String: Int] = [:]
        while let meal = best(for: s, registry: registry, hasKitchen: hasKitchen),
              s.kitchenProgress >= meal.work,
              s.storage[.food] < s.storageCapacity[.food] * fullEnough {
            s.kitchenProgress -= meal.work
            for (itemID, count) in meal.ingredients {
                s.stockpile[itemID, default: 0] -= count
                if s.stockpile[itemID, default: 0] <= 0 { s.stockpile[itemID] = nil }
            }
            s.storage[.food] = min(s.storageCapacity[.food], s.storage[.food] + meal.food)
            cooked[meal.id, default: 0] += 1
        }

        // Effort banked against a bare shelf is capped at one batch — see
        // `bankCeiling`, and note that it is one batch of the *dearest* meal
        // rather than the cheapest, or the dearer ones can never be paid for.
        s.kitchenProgress = min(s.kitchenProgress, bankCeiling(registry))

        if let headline = cooked.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }),
           let meal = registry.meals[headline.key] ?? (registry.meals.isEmpty ? MealDefinition.fallback : nil),
           headline.value >= journalThreshold {
            s.note(tick: tick, kind: .work, text: LocalizedText(values: [
                .en: "The kitchens put up \(headline.value) of \(meal.name.resolve(.en).lowercased()).",
                .cs: "V kuchyni nachystali \(headline.value)× \(meal.name.resolve(.cs).lowercased())."]))
        }
        return s
    }

    /// How many batches in one tick is worth writing down. A cook turning out
    /// one pot of gruel is not news; the kitchens working flat out is.
    static let journalThreshold = 6

    // MARK: - Pieces

    /// The best meal the shelf and the standing buildings actually allow.
    ///
    /// Chosen by food per batch **weighted by what the stores can spare**, and
    /// the weighting is the whole of it. Picking the richest meal outright is
    /// what a first cut did, and it killed the colony: every meal in the table
    /// leans on grain, so the kitchens burned grain and nothing else. Greens
    /// piled up to the granary's roof — 2 852 of them against 17 sacks of
    /// grain — crowded the shelf against the very staple they were crowding
    /// out, and the colony went extinct at t=9 500 with a full store of salad.
    ///
    /// So a meal is scored against the *pressure* it puts on the shelf: what it
    /// asks for, over what is there. A pot leaning on a mountain of greens
    /// costs almost nothing; one built on the last sack of grain costs a lot.
    /// The kitchens use up what there is most of, which is what a kitchen does,
    /// and no single crop can starve the others out.
    ///
    /// Ties break on yield-per-work and then on id — never on dictionary order,
    /// which is not stable in Swift and would make two runs of one seed cook
    /// different dinners.
    static func best(
        for settlement: Settlement, registry: GameDataRegistry, hasKitchen: Bool
    ) -> MealDefinition? {
        registry.cookableMeals
            .filter { meal in
                guard !meal.ingredients.isEmpty, meal.food > 0, meal.work > 0 else { return false }
                if meal.requiresBuilding != nil && !hasKitchen { return false }
                if let needed = meal.requiresBuilding,
                   !settlement.buildings.contains(where: { $0.definitionID == needed && $0.count > 0 }) {
                    return false
                }
                return meal.ingredients.allSatisfy {
                    settlement.stockpile[$0.key, default: 0] >= $0.value
                }
            }
            .max {
                let a = score($0, shelf: settlement.stockpile)
                let b = score($1, shelf: settlement.stockpile)
                if a != b { return a < b }
                return ($0.yieldPerWork, $1.id) < ($1.yieldPerWork, $0.id)
            }
    }

    /// What a meal is worth, against what it costs the shelf.
    ///
    /// `pressure` is how much of each store the batch takes; the `+ 1` keeps a
    /// meal drawing on a nearly-bare shelf finite rather than infinite, so a
    /// colony down to its last sack still cooks it rather than refusing to.
    static func score(_ meal: MealDefinition, shelf: [String: Int]) -> Double {
        var pressure = 0.0
        for (itemID, count) in meal.ingredients {
            pressure += Double(count) / Double(shelf[itemID, default: 0] + 1)
        }
        return meal.food / (1 + pressure)
    }

    /// The worker-ticks the colony's cooks put in this tick.
    static func effort(of settlement: Settlement, registry: GameDataRegistry) -> Double {
        // A strike puts the kitchens out too. Cooking is not a gathering trade,
        // so it never passed through the `gatheringFactors` zeroing that used
        // to stop a struck colony feeding itself — and a strike nobody feels in
        // the larder is a strike that costs the colony nothing.
        guard settlement.strikeTicksRemaining == 0 else { return 0 }
        let shut = PlagueEngine.workFactor(settlement)
        let ticksPerYear = registry.config.ticksPerYear
        return shut * settlement.pawns.reduce(0.0) { total, pawn in
            guard pawn.assignedWork == .cooking,
                  pawn.isAdult(ticksPerYear: ticksPerYear),
                  !pawn.isBroken, !pawn.isAway, pawn.health > 0 else { return total }
            let skill = Double(pawn.skill(.cooking)) / 20
            let condition = min(1, max(0.35, pawn.health / 100))
            return total + (effortPerCook + skill * skillEffort) * condition
        }
    }

    /// Standing buildings whose trade is cooking.
    static func kitchens(at settlement: Settlement, registry: GameDataRegistry) -> Int {
        settlement.buildings.reduce(0) { total, instance in
            guard let def = registry.building(instance.definitionID),
                  def.work == .cooking else { return total }
            return total + instance.count
        }
    }

    /// What the colony's roofs will hold in raw ingredients.
    ///
    /// The `stockpile` has never had a ceiling: iron ore and clay pile up for
    /// two centuries and nobody notices, because nothing in the game asks how
    /// much of them there is. Food is different — the granary is a building the
    /// player pays for and the whole point of it is that it holds the harvest
    /// through a winter. An uncapped shelf makes it decoration.
    ///
    /// So foodstuffs share the same ceiling meals do. Everything else on the
    /// shelf is left exactly as it was: capping ore is a separate argument and
    /// this change should not smuggle it in.
    public static func spoil(
        _ settlement: Settlement, registry: GameDataRegistry, tick: Int
    ) -> Settlement {
        let kinds = foodstuffs(registry)
        var s = settlement
        let held = kinds.reduce(0) { $0 + s.stockpile[$1, default: 0] }
        let capacity = Int(s.storageCapacity[.food])
        guard capacity > 0, held > capacity else { return s }

        // Each kind keeps its share of the roof, rather than whichever sack is
        // read first being emptied — and "first" would be dictionary order,
        // which Swift does not keep stable between runs.
        //
        // Written as *what is kept* rather than as what is lost, deliberately.
        // Subtracting a proportional loss in one pass leaves a remainder
        // stranded whenever the kinds that could absorb it have already been
        // walked past: measured at 275 units left under a roof that holds 100.
        var kept: [String: Int] = [:]
        for kind in kinds.sorted() {
            let have = s.stockpile[kind, default: 0]
            guard have > 0 else { continue }
            kept[kind] = have * capacity / held
        }
        // Integer shares floor, so a few units of roof go unclaimed. Hand them
        // to the biggest pile — the colony keeps everything its granary can
        // hold, and never one sack more.
        var slack = capacity - kept.values.reduce(0, +)
        for kind in kept.keys.sorted(by: { (kept[$0] ?? 0, $1) > (kept[$1] ?? 0, $0) })
        where slack > 0 {
            let give = min(s.stockpile[kind, default: 0] - (kept[kind] ?? 0), slack)
            kept[kind, default: 0] += give
            slack -= give
        }
        for kind in kinds {
            let keep = kept[kind] ?? 0
            s.stockpile[kind] = keep > 0 ? keep : nil
        }
        s.note(tick: tick, kind: .work, text: LocalizedText(values: [
            .en: "There is more of the harvest than there is roof to keep it under, and some of it has gone over.",
            .cs: "Úrody je víc, než kolik je pod střechou místa, a část se zkazila."]))
        return s
    }

    /// Every item id any meal is built out of — what counts as a foodstuff.
    ///
    /// Derived from the meal table rather than listed, so adding a crop to
    /// `meals.json` cannot leave the granary refusing to store it (rule 8: the
    /// ingredients are stated in one place). Built once when the registry
    /// loads, not on every read: the errands ask this question every tick.
    public static func foodstuffs(_ registry: GameDataRegistry) -> Set<String> {
        registry.foodstuffs
    }
}
