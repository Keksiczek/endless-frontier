import Foundation

/// Turns materials (and resources) into gear at a chosen settlement. Materials
/// are item drops from sites; recipes may require a building and/or a tech.
/// All checks and consumption are scoped to one settlement — passing
/// `settlementID == nil` falls back to the capital, preserving older callers.
public enum CraftingEngine {

    // MARK: - Making things takes people, and time

    /// Worker-ticks a crafter of no skill puts into the bench each tick.
    static let effortPerCrafter = 1.0
    /// …and how much a full twenty of skill adds on top. A master is a little
    /// over twice a beginner, which is enough to be worth training and not so
    /// much that one prodigy is the colony's whole industry.
    static let skillEffort = 1.3
    /// The most orders a colony may have queued. A bench is a bench.
    public static let maxOrders = 12

    /// How much one colonist contributes to a bench this tick.
    ///
    /// Zero for anybody who cannot work: a broken colonist, someone away at the
    /// ruins, a child. The trade a colonist is *assigned* is checked by the
    /// caller — this is what the person is worth once they are at the bench.
    public static func effort(of pawn: Pawn) -> Double {
        guard !pawn.isBroken, !pawn.isAway, pawn.health > 0 else { return 0 }
        let skill = Double(pawn.skill(.crafting)) / 20
        let condition = min(1, max(0.35, pawn.health / 100))
        return (effortPerCrafter + skill * skillEffort) * condition
    }

    /// Puts the colony's crafters to work for one tick.
    ///
    /// The order at the head of the queue that *can* be worked is worked — one
    /// bench, one thing at a time, oldest first. "Can be worked" means the
    /// building it names is standing, the tech is known, and the materials are
    /// actually on the shelf; an order that cannot be worked is skipped rather
    /// than blocking the ones behind it, so a colony waiting on iron still
    /// makes its arrows.
    ///
    /// Materials are taken **when the piece is finished**, not when it is
    /// started. Otherwise a half-made sword holds two ingots hostage across a
    /// save, a load, and a famine — and the player cannot see where they went.
    public static func advanceOneTick(
        _ state: WorldState, registry: GameDataRegistry
    ) -> WorldState {
        var s = state
        for index in s.settlements.indices where !s.settlements[index].craftOrders.isEmpty {
            s.settlements[index] = advanceOneTick(
                s.settlements[index], tick: s.tick,
                researched: s.researchedTechs, registry: registry)
        }
        return s
    }

    /// One settlement's bench for one tick.
    public static func advanceOneTick(
        _ settlement: Settlement, tick: Int,
        researched: Set<String>, registry: GameDataRegistry
    ) -> Settlement {
        var s = settlement
        // Clear anything finished or pointing at content that no longer exists,
        // so a queue cannot silently jam on a recipe that was renamed.
        s.craftOrders.removeAll { $0.isComplete || registry.recipes[$0.recipeID] == nil }
        guard !s.craftOrders.isEmpty else { return s }

        let crafters = s.pawns.filter {
            $0.assignedWork == .crafting
                && $0.isAdult(ticksPerYear: registry.config.ticksPerYear)
        }
        let hands = crafters.reduce(0.0) { $0 + effort(of: $1) }
        guard hands > 0 else { return s }

        // **One bench per shop.** A colony with a workshop and a foundry has
        // two benches and works two things at once; one with three workshops
        // still has one workshop's worth of queue, because the shops are the
        // same shop. Before this the whole settlement advanced a single order a
        // tick however much it had built, so raising a second forge bought
        // nothing at all.
        let benches = workableBenches(at: s, researched: researched, registry: registry)
        guard !benches.isEmpty else { return s }
        // The hands are split between the benches that have work. Somebody has
        // to be standing at each of them.
        let share = hands / Double(benches.count)
        let masters = bestSkill(among: crafters)

        // Worked back to front so removing a finished order cannot shift the
        // index of one not yet reached.
        for position in benches.sorted(by: >) {
            guard let recipe = registry.recipes[s.craftOrders[position].recipeID] else { continue }
            let cost = recipe.workPerUnit
            s.craftOrders[position].progress += share

            // However many this bench's day of work finished — several crafters
            // on a cheap recipe genuinely make several, rather than one and a
            // wasted afternoon.
            while s.craftOrders[position].progress >= cost,
                  !s.craftOrders[position].isComplete,
                  hasMaterials(recipe, at: s) {
                s.craftOrders[position].progress -= cost
                s = take(recipe, from: s)
                s = bank(recipe, into: s, tick: tick, made: s.craftOrders[position].made,
                         skill: masters, registry: registry)
                s.craftOrders[position].made += 1
            }
            // Nothing on the shelf to make the next one out of: hold the
            // part-done work rather than spinning progress up for ever.
            if !hasMaterials(recipe, at: s) {
                s.craftOrders[position].progress = min(s.craftOrders[position].progress, cost)
            }
            if s.craftOrders[position].isComplete {
                s.journal.append(tick: tick, kind: .work, text: LocalizedText(values: [
                    .en: "The bench finished the last of the \(recipe.name.resolve(.en)).",
                    .cs: "Na ponku dodělali poslední kus: \(recipe.name.resolve(.cs))."]))
                s.craftOrders.remove(at: position)
            }
        }
        return s
    }

    /// The orders being worked *right now* — one per distinct shop, oldest
    /// first within each.
    ///
    /// Returns positions into `settlement.craftOrders` so the caller can write
    /// back. An order whose shop is missing, whose research is missing or whose
    /// shelf is bare is skipped rather than blocking the ones behind it: a
    /// colony waiting on iron still makes its arrows.
    static func workableBenches(
        at settlement: Settlement, researched: Set<String>, registry: GameDataRegistry
    ) -> [Int] {
        var taken: Set<String> = []
        var picked: [Int] = []
        // **An order with an end takes the bench first.**
        //
        // This was oldest-first, and a *standing* order never finishes — so the
        // first one ever placed held its bench for the rest of the colony's
        // history and everything queued behind it waited for ever. Measured:
        // fifty years of a council arming its people produced **seventeen
        // weapons for sixty-eight colonists**, because the builders' standing
        // orders for timber and brick were older than every batch of spears
        // and never gave the bench up.
        //
        // Standing orders are a background trickle by design (they are how the
        // colony always has some timber about); a batch of four coats is a job
        // somebody wants done. The job goes first, and the trickle takes what
        // is left.
        for entry in settlement.craftOrders.enumerated()
            .sorted(by: { a, b in
                let (endsA, endsB) = (a.element.wanted != nil, b.element.wanted != nil)
                if endsA != endsB { return endsA }
                if a.element.placedTick != b.element.placedTick {
                    return a.element.placedTick < b.element.placedTick
                }
                return a.offset < b.offset
            }) {
            guard !entry.element.paused,
                  let recipe = registry.recipes[entry.element.recipeID],
                  isWorkable(recipe, at: settlement, researched: researched) else { continue }
            // Recipes needing no shop share one imaginary bench — a colony
            // stitching leather in its yard is not two colonies.
            let bench = recipe.requiresBuilding ?? ""
            guard !taken.contains(bench) else { continue }
            taken.insert(bench)
            picked.append(entry.offset)
        }
        return picked
    }

    /// The best hand in the shop. Quality follows whoever is actually good at
    /// this, not the average of everyone standing near the anvil — an
    /// apprentice fetching and carrying does not spoil a master's work.
    static func bestSkill(among crafters: [Pawn]) -> Int {
        crafters.filter { effort(of: $0) > 0 }.map { $0.skill(.crafting) }.max() ?? 0
    }

    /// Whether an order could be worked at all here: the shop stands, the
    /// knowledge exists, and there is something to make it out of.
    public static func isWorkable(
        _ recipe: RecipeDefinition, at settlement: Settlement, researched: Set<String>
    ) -> Bool {
        if let building = recipe.requiresBuilding,
           !settlement.buildings.contains(where: { $0.definitionID == building }) { return false }
        if let tech = recipe.requiresTech, !researched.contains(tech) { return false }
        return hasMaterials(recipe, at: settlement)
    }

    /// Whether the shelves hold everything one of these needs.
    public static func hasMaterials(
        _ recipe: RecipeDefinition, at settlement: Settlement
    ) -> Bool {
        let counts = materialCounts(settlement)
        for (materialID, needed) in recipe.materials where (counts[materialID] ?? 0) < needed {
            return false
        }
        for resource in ResourceType.allCases
        where settlement.storage[resource] < recipe.resourceCost[resource] {
            return false
        }
        return true
    }

    /// Spends one unit's worth of materials and resources.
    private static func take(_ recipe: RecipeDefinition, from settlement: Settlement) -> Settlement {
        var s = settlement
        for (materialID, needed) in recipe.materials.sorted(by: { $0.key < $1.key }) {
            var remaining = needed
            let stocked = s.stockpile[materialID] ?? 0
            let fromStock = min(stocked, remaining)
            if fromStock > 0 {
                s.stockpile[materialID] = stocked - fromStock
                remaining -= fromStock
            }
            guard remaining > 0 else { continue }
            var removed = 0
            s.inventory.removeAll { instance in
                guard removed < remaining, instance.definitionID == materialID else { return false }
                removed += 1
                return true
            }
        }
        for resource in ResourceType.allCases where recipe.resourceCost[resource] > 0 {
            s.storage[resource] = s.storage[resource] - recipe.resourceCost[resource]
        }
        return s
    }

    /// Puts the finished thing where it belongs: a material on the pile, a
    /// piece of gear on the shelf as a thing somebody can pick up.
    private static func bank(
        _ recipe: RecipeDefinition, into settlement: Settlement, tick: Int, made: Int,
        skill: Int, registry: GameDataRegistry
    ) -> Settlement {
        var s = settlement
        // A material is a count on the pile; a piece of gear or an artifact is
        // a thing, with an id, that somebody can pick up and wear. A count has
        // nowhere to carry *how well it was made* — an ingot is an ingot.
        if registry.item(recipe.outputItemID)?.slot == .material {
            s.stockpile[recipe.outputItemID, default: 0] += 1
            return s
        }
        // Identity from the bench, the tick and how many have come off it, so
        // the same colony making the same order twice never collides — and
        // never reaches for an unseeded `UUID()` (rule 2).
        var rng = SeededRNG(seed: benchSeed(settlementID: s.id, recipeID: recipe.id,
                                            tick: tick, made: made))
        let id = rng.nextUUID()
        let quality = ItemQuality.rolled(skill: skill, roll: rng.nextUnit())
        s.inventory.append(ItemInstance(
            id: id, definitionID: recipe.outputItemID, quality: quality))
        // Something worth talking about gets talked about.
        if quality == .masterwork {
            let thing = registry.item(recipe.outputItemID)?.name ?? recipe.name
            s.journal.append(tick: tick, kind: .work, text: LocalizedText(values: [
                .en: "A masterwork came off the bench: \(thing.resolve(.en)).",
                .cs: "Z ponku sešel mistrovský kus: \(thing.resolve(.cs))."]))
        }
        return s
    }

    static func benchSeed(settlementID: UUID, recipeID: String, tick: Int, made: Int) -> UInt64 {
        var h: UInt64 = 0x9E37_79B9_7F4A_7C15
        let bytes = settlementID.uuid
        h = (h ^ UInt64(bytes.0)) &* 0x0100_0000_01B3
        h = (h ^ UInt64(bytes.7)) &* 0x0100_0000_01B3
        h = (h ^ UInt64(bytes.15)) &* 0x0100_0000_01B3
        for byte in recipeID.utf8 { h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3 }
        h = (h ^ UInt64(bitPattern: Int64(tick))) &* 0xD1B5_4A32_D192_ED03
        h = (h ^ UInt64(bitPattern: Int64(made))) &* 0xCBF2_9CE4_8422_2325
        return h ^ (h >> 29)
    }

    // MARK: - Orders

    /// Puts something on the bench. Returns the settlement unchanged if the
    /// recipe is unknown or the queue is full.
    public static func place(
        _ settlement: Settlement, recipeID: String, count: Int?,
        tick: Int, registry: GameDataRegistry
    ) -> Settlement {
        guard registry.recipes[recipeID] != nil,
              settlement.craftOrders.count < maxOrders else { return settlement }
        var s = settlement
        var rng = SeededRNG(seed: benchSeed(settlementID: s.id, recipeID: recipeID,
                                            tick: tick, made: s.craftOrders.count))
        s.craftOrders.append(CraftOrder(
            id: rng.nextUUID(), recipeID: recipeID, wanted: count,
            placedTick: tick))
        return s
    }

    public static func cancel(_ settlement: Settlement, orderID: UUID) -> Settlement {
        var s = settlement
        s.craftOrders.removeAll { $0.id == orderID }
        return s
    }

    public static func setPaused(
        _ settlement: Settlement, orderID: UUID, paused: Bool
    ) -> Settlement {
        var s = settlement
        guard let index = s.craftOrders.firstIndex(where: { $0.id == orderID }) else { return s }
        s.craftOrders[index].paused = paused
        return s
    }

    /// Recipes the player can craft right now at the given settlement
    /// (materials, resources and requirements all satisfied there).
    public static func availableRecipes(
        _ state: WorldState,
        settlementID: UUID? = nil,
        registry: GameDataRegistry
    ) -> [RecipeDefinition] {
        registry.recipes.values
            .filter { canCraft($0, in: state, settlementID: settlementID, registry: registry) }
            .sorted { $0.id < $1.id }
    }

    public static func canCraft(
        _ recipe: RecipeDefinition,
        in state: WorldState,
        settlementID: UUID? = nil,
        registry: GameDataRegistry
    ) -> Bool {
        guard let index = targetIndex(state, settlementID) else { return false }
        let settlement = state.settlements[index]
        // Materials on hand.
        let counts = materialCounts(settlement)
        for (materialID, needed) in recipe.materials where (counts[materialID] ?? 0) < needed {
            return false
        }
        // Resources on hand.
        for resource in ResourceType.allCases where settlement.storage[resource] < recipe.resourceCost[resource] {
            return false
        }
        // Building requirement.
        if let building = recipe.requiresBuilding,
           !settlement.buildings.contains(where: { $0.definitionID == building }) {
            return false
        }
        // Tech requirement (tech is researched world-wide).
        if let tech = recipe.requiresTech, !state.researchedTechs.contains(tech) {
            return false
        }
        return true
    }

    /// Materials on hand: the counted stockpile plus anything still sitting in
    /// the inventory as individual instances.
    ///
    /// Both are read because materials used to be loot instances only. A save
    /// written before the stockpile existed still has its ingots in
    /// `inventory`, and site drops may still land there — a craft must see
    /// them either way, or a player's hoard silently stops counting.
    static func materialCounts(_ settlement: Settlement) -> [String: Int] {
        settlement.inventory.reduce(into: settlement.stockpile) { counts, instance in
            counts[instance.definitionID, default: 0] += 1
        }
    }

    /// Resolves the settlement a craft acts on: the named one if given and
    /// present, otherwise the capital, otherwise the first settlement.
    static func targetIndex(_ state: WorldState, _ settlementID: UUID?) -> Int? {
        if let settlementID, let i = state.settlements.firstIndex(where: { $0.id == settlementID }) {
            return i
        }
        return state.settlements.firstIndex(where: { $0.kind == .capital })
            ?? state.settlements.indices.first
    }

    private static func craftSeed(state: WorldState, recipeID: String, settlementIndex: Int) -> UInt64 {
        var h: UInt64 = state.mapSeed &* 0x9E37_79B9_7F4A_7C15
        for byte in recipeID.utf8 { h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3 }
        h = (h ^ UInt64(bitPattern: Int64(state.tick)))
        h = (h ^ UInt64(state.settlements[settlementIndex].inventory.count))
        h = h &+ UInt64(settlementIndex) &* 0x9E37_79B9_7F4A_7C15
        return h ^ (h >> 29)
    }
}
