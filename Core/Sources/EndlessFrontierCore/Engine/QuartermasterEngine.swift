import Foundation

/// Arms and clothes the colony, and puts what it makes on the people who need it.
///
/// The last room in the house with the player still standing in the doorway.
/// `GameEngine.equipItem` is only ever called from the UI, and `StewardEngine`'s
/// standing orders knew about **building materials** and nothing else — so a
/// colony left to itself never made a spear, never made a coat, and never handed
/// anybody so much as a hoe. Measured on a fresh world at year two hundred: an
/// inventory of nothing, every colonist bare in every slot, and a `bronze_spear`
/// that costs fifteen materials sitting unmade in `recipes.json` while the store
/// held two and a half thousand.
///
/// It is the same shape as the frozen world (`StewardEngine`) and it wants the
/// same answer: the colony does the obvious thing on its own, and anything the
/// player chooses stays chosen. Concretely —
///
/// - **It never takes anything off anybody.** A hand-out only ever fills an
///   empty slot, so a spear the player gave their best fighter is theirs.
/// - **It orders against a shortfall, never a standing order.** Gear is a
///   *stock* with a size the colony can name (one coat per pair of hands), not a
///   tap like timber. An endless order would have the bench turning out spears
///   until the iron ran out — rule 21's shape from the other side.
/// - **It leaves the builders their materials.** Same reserve rule the council
///   builds under: order only what the colony could pay for twice.
public enum QuartermasterEngine {

    /// How much of the store the gear bench may reach for, as a multiple of what
    /// the order costs. A colony that arms itself into a state where it cannot
    /// raise a roof has armed itself for nothing.
    static let reserve = 1.0

    /// The most of one thing to put on the bench at once. A shortfall of forty
    /// coats is real, and forty on one order is a bench doing nothing else for a
    /// decade — the colony would rather have four now and four more next season.
    static let batch = 4

    /// How many bare hands it takes before the colony bothers. One person
    /// without a coat is not a quartermaster's problem.
    static let shortfallWorthMaking = 2

    // MARK: - The council's sitting

    /// One pass: order what the colony is short of, then hand out what it has.
    ///
    /// Called from `StewardEngine.advanceOneTick`, on the council's own cadence
    /// (rule 4 — this walks every colonist and must not run per tick).
    public static func advance(
        _ state: WorldState, index: Int, registry: GameDataRegistry
    ) -> WorldState {
        var s = orderWhatIsBare(state, index: index, registry: registry)
        s = handOutGear(s, index: index, registry: registry)
        return s
    }

    // MARK: - Ordering

    /// Puts a batch of gear on the bench for whichever slot the colony is
    /// barest in, if it can pay for it twice over.
    static func orderWhatIsBare(
        _ state: WorldState, index: Int, registry: GameDataRegistry
    ) -> WorldState {
        var s = state
        let settlement = s.settlements[index]
        let ticksPerYear = max(1, registry.config.ticksPerYear)
        let hands = settlement.pawns.filter {
            $0.isAdult(ticksPerYear: ticksPerYear) && $0.health > 0
        }

        // Slots in a fixed order so two runs of the same world make the same
        // things in the same seasons (rule 2 — `EquipmentSlot.allCases` is a
        // declared order, not a hashed one).
        for slot in EquipmentSlot.allCases {
            let bare = hands.count { $0.equipment[slot] == nil }
            let onTheShelf = settlement.inventory.count {
                registry.item($0.definitionID)?.equipSlot == slot
            }
            let shortfall = bare - onTheShelf
            guard shortfall >= shortfallWorthMaking else { continue }
            // One order per slot at a time. The bench is shared with the
            // builders' timber and the cook's stores.
            guard !settlement.craftOrders.contains(where: { order in
                registry.recipes[order.recipeID]
                    .flatMap { registry.item($0.outputItemID)?.equipSlot } == slot
            }) else { continue }
            guard let pick = bestGear(for: slot, at: settlement, in: s, registry: registry)
            else { continue }
            s.settlements[index] = CraftingEngine.place(
                s.settlements[index], recipeID: pick,
                count: min(shortfall, batch), tick: s.tick, registry: registry)
        }
        return s
    }

    /// The best thing the colony could make for a slot and still afford to
    /// build with afterwards — or nil if there is nothing it can both work and
    /// pay for.
    ///
    /// **Best, not cheapest.** A town with a workshop and iron on the shelf
    /// should be turning out swords, not the bronze spear it started with; the
    /// affordability rule below is what stops that from beggaring it.
    static func bestGear(
        for slot: EquipmentSlot, at settlement: Settlement,
        in state: WorldState, registry: GameDataRegistry
    ) -> String? {
        registry.recipes.values
            .filter { recipe in
                guard let item = registry.item(recipe.outputItemID),
                      item.slot == .equipment, item.equipSlot == slot else { return false }
                if let building = recipe.requiresBuilding,
                   !settlement.buildings.contains(where: { $0.definitionID == building }) {
                    return false
                }
                if let tech = recipe.requiresTech,
                   !state.researchedTechs.contains(tech) { return false }
                // Paid for, with as much again left in hand for the builders.
                for resource in ResourceType.allCases {
                    let cost = recipe.resourceCost[resource]
                    guard cost > 0 else { continue }
                    guard settlement.storage[resource] - cost >= cost * reserve
                    else { return false }
                }
                // And the made things it is built out of — iron, timber, hide —
                // are on the pile. Ordering a sword the colony has no ingot for
                // parks the bench on an order it can never start.
                let held = CraftingEngine.materialCounts(settlement)
                return recipe.materials.allSatisfy { (held[$0.key] ?? 0) >= $0.value }
            }
            .max { a, b in
                let wa = worth(of: a, registry: registry)
                let wb = worth(of: b, registry: registry)
                return wa == wb ? a.id > b.id : wa < wb
            }?
            .id
    }

    /// What a piece of gear is worth to a colony in the abstract — before it is
    /// known who will wear it. Used to pick *what to make*; `worth(of:to:)`
    /// picks *who gets it*.
    static func worth(of recipe: RecipeDefinition, registry: GameDataRegistry) -> Double {
        guard let item = registry.item(recipe.outputItemID) else { return 0 }
        return worth(of: item)
    }

    static func worth(of item: ItemDefinition) -> Double {
        var out = (item.combat?.damage ?? 0)
        for effect in item.effects {
            switch effect {
            case let .skillBonus(_, amount): out += Double(amount) * 3
            case let .moodBonus(amount): out += amount
            case let .healthRegen(amount): out += amount * 8
            case let .colonyDefense(amount): out += amount
            case let .colonyMorale(amount): out += amount
            case let .colonyProduction(_, perTick): out += perTick * 4
            }
        }
        return out
    }

    // MARK: - Handing it out

    /// Gives what is on the shelf to the people it does most good for.
    ///
    /// Greedy, and deliberately: the best item goes to whoever gains most from
    /// it, then the next, and so on. A perfect assignment would be an
    /// interesting problem and a colonist cannot tell the difference.
    ///
    /// **Only ever fills an empty slot.** Rule 1's cousin for the council: what
    /// the player chose stays chosen, so a hand-out never strips anybody to
    /// upgrade them. Somebody who wants a better axe has to be given it.
    static func handOutGear(
        _ state: WorldState, index: Int, registry: GameDataRegistry
    ) -> WorldState {
        var s = state
        let ticksPerYear = max(1, registry.config.ticksPerYear)
        // Walked in a settled order — inventory as stored, colonists by id —
        // so the same colony dresses the same people on a replay.
        var shelf = s.settlements[index].inventory
            .filter { registry.item($0.definitionID)?.slot == .equipment }
        guard !shelf.isEmpty else { return s }
        shelf.sort { a, b in
            let wa = registry.item(a.definitionID).map(worth(of:)) ?? 0
            let wb = registry.item(b.definitionID).map(worth(of:)) ?? 0
            return wa == wb ? a.id.uuidString < b.id.uuidString : wa > wb
        }

        for item in shelf {
            guard let def = registry.item(item.definitionID),
                  let slot = def.equipSlot else { continue }
            let settlement = s.settlements[index]
            let taker = settlement.pawns
                .filter {
                    $0.isAdult(ticksPerYear: ticksPerYear) && $0.health > 0
                        && $0.equipment[slot] == nil
                }
                .max { a, b in
                    let wa = worth(of: def, to: a), wb = worth(of: def, to: b)
                    return wa == wb ? a.id.uuidString > b.id.uuidString : wa < wb
                }
            guard let taker else { continue }
            s = GameEngine.equipItem(s, settlementID: settlement.id,
                                     pawnID: taker.id, itemID: item.id,
                                     registry: registry)
        }
        return s
    }

    /// What this piece of gear is worth to *this* colonist.
    ///
    /// The whole reason the hand-out is a matching and not a queue: a weapon-slot
    /// item is a tool as often as it is a weapon — `worn_tools`, `sturdy_axe` and
    /// `miners_pick` all hang where a spear does — so the same axe is worth a
    /// great deal to a woodcutter and almost nothing to a scholar.
    static func worth(of item: ItemDefinition, to pawn: Pawn) -> Double {
        var out = 0.0
        for effect in item.effects {
            switch effect {
            case let .skillBonus(work, amount):
                out += Double(amount) * (work == pawn.assignedWork ? 12 : 1)
            case let .moodBonus(amount): out += amount
            case let .healthRegen(amount): out += amount * 8
            case let .colonyDefense(amount): out += amount
            case let .colonyMorale(amount): out += amount
            case let .colonyProduction(_, perTick): out += perTick * 4
            }
        }
        // A weapon is worth what it does in a fight, and a fight is what the
        // garrison is for. It still counts for everybody else — when a raid
        // comes, whoever is holding something swings it.
        if let combat = item.combat {
            out += combat.damage * (pawn.assignedWork == .garrison ? 3 : 1)
        }
        return out
    }
}
