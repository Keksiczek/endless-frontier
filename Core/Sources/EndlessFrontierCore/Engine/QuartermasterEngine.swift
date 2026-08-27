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
            // The same share of the bench the builders' standing orders respect
            // — see `StewardEngine.councilBenchShare`. Gear queued past it is
            // gear the player cannot make room for.
            guard s.settlements[index].craftOrders.count
                    < StewardEngine.councilBenchShare else { break }
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
            // A line of swordsmen has nobody on the wall. When the share that
            // can shoot has fallen too low, the next batch is bows — and if the
            // colony cannot work one, it falls back to the best of anything.
            let wantRanged = slot == .weapon
                && wantsRanged(at: settlement, registry: registry)
            let pick = (wantRanged
                        ? bestGear(for: slot, at: settlement, in: s,
                                   registry: registry, preferring: .ranged)
                        : nil)
                ?? bestGear(for: slot, at: settlement, in: s, registry: registry)
            guard let pick else { continue }
            s.settlements[index] = CraftingEngine.place(
                s.settlements[index], recipeID: pick,
                count: min(shortfall, batch), tick: s.tick, registry: registry,
                byCouncil: true)
        }
        return s
    }

    /// The made things the gear bench needs on the pile — hide tanned into
    /// leather, ore smelted into ingots — which is a **different list** from the
    /// one the builders keep.
    ///
    /// Measured with the quartermaster in and this missing: a colony armed forty
    /// of its fifty-five with spears and bows and clothed *nobody, ever*, for
    /// two hundred years. A coat is `leather_garb`; leather is `tan_leather` out
    /// of hides the lodge had been stacking the whole time; and leather is not a
    /// **building** material, so `StewardEngine.wantedMaterials` never asked for
    /// it, so the tannery never ran and `bestGear` could never find an armour it
    /// was able to work. Rule 6 in the supply chain: the last link was reachable
    /// and the one before it was never asked for.
    ///
    /// Only what the colony could actually work — a shop it has, a tech it
    /// knows — so it does not stand a standing order for ingots it has no
    /// bloomery to smelt.
    /// **The gear it will actually make, not everything it could.**
    ///
    /// This used to be the union of the materials of *every* workable
    /// equipment recipe, which was seven ids when there were ten such recipes
    /// and eighteen when content took it to thirty — and the colony stopped
    /// arming itself entirely. `StewardEngine.keepMaterialsComing` places one
    /// standing order per wanted material, so the list is a divisor: the bench
    /// is finite, eighteen standing orders is eighteen slow trickles, and
    /// nothing ever reaches the amount `bestGear` needs in one place. Rule 14
    /// in the supply chain — a rate divided by an entity count that grew.
    ///
    /// It was also asking for the wrong thing all along. `bestGear` picks one
    /// recipe per slot and builds *that*; stocking for the twenty-nine it will
    /// never choose was never useful, it merely became fatal. So the want list
    /// now follows the same choice the bench will make, which keeps it short
    /// however much content arrives — and pointed at the one thing that will
    /// be built.
    static func wantedMaterials(
        for settlement: Settlement, in state: WorldState, registry: GameDataRegistry
    ) -> [String] {
        var wanted: Set<String> = []
        for slot in EquipmentSlot.allCases {
            let workable = registry.recipes.values
                .filter { canWork($0, for: slot, at: settlement, in: state, registry: registry) }
            guard !workable.isEmpty else { continue }
            let byWorth: (RecipeDefinition, RecipeDefinition) -> Bool = { a, b in
                let wa = worth(of: a, registry: registry)
                let wb = worth(of: b, registry: registry)
                return wa == wb ? a.id > b.id : wa < wb
            }
            // **What it is aiming at**, and…
            if let best = workable.max(by: byWorth) { wanted.formUnion(best.materials.keys) }
            // …**what it can actually finish.** Two entries, not one, because
            // the best thing a colony can *work* is often made of something it
            // cannot *get*: a workshop makes chainmail out of ingots, and a
            // colony with no bloomery will stock for chainmail for ever and
            // never tan the hide for a coat. An unreachable best starving the
            // reachable one is the oldest shape in this repository
            // (`ef-unreachable-mechanics`), and this is it inside one function.
            let finishable = workable.filter { recipe in
                recipe.materials.keys.allSatisfy {
                    producible($0, at: settlement, in: state, registry: registry)
                }
            }
            if let reachable = finishable.max(by: byWorth) {
                wanted.formUnion(reachable.materials.keys)
            }
        }
        return wanted.sorted()
    }

    /// What the land itself yields, with no recipe in front of it. Stated the
    /// same way `SiteEngine.lootPool` states it, off `LocalResourceKind`, so
    /// the two cannot drift apart.
    static let gathered: Set<String> = Set(
        LocalResourceKind.allCases.compactMap(\.rawMaterialID)
    ).union([ResourceLoop.hideItemID])

    /// Whether this colony has any way at all of coming by a material: it is
    /// gathered off the land, or something it can work turns it out.
    ///
    /// One level deep on purpose. A full walk of the chain would be the honest
    /// answer and costs a graph search every tick; one level catches the case
    /// this exists for — leather from hides — and a deeper chain that is truly
    /// unreachable simply fails to accumulate, which is visible rather than
    /// fatal.
    static func producible(
        _ materialID: String, at settlement: Settlement,
        in state: WorldState, registry: GameDataRegistry
    ) -> Bool {
        if gathered.contains(materialID) { return true }
        return registry.recipes.values.contains { recipe in
            guard recipe.outputItemID == materialID else { return false }
            if let building = recipe.requiresBuilding,
               !settlement.buildings.contains(where: { $0.definitionID == building }) {
                return false
            }
            if let tech = recipe.requiresTech,
               !state.researchedTechs.contains(tech) { return false }
            return true
        }
    }

    /// What the bench *would* make for a slot if the materials were on the
    /// pile — the same choice `bestGear` makes, with the one clause that asks
    /// whether the stock is already there taken out.
    ///
    /// The split matters: `bestGear` answers "what can I start now", and this
    /// answers "what am I stocking up for". Using the first for both is how a
    /// colony ends up waiting for materials nobody ordered.
    static func intendedGear(
        for slot: EquipmentSlot, at settlement: Settlement,
        in state: WorldState, registry: GameDataRegistry
    ) -> RecipeDefinition? {
        registry.recipes.values
            .filter { canWork($0, for: slot, at: settlement, in: state, registry: registry) }
            .max { a, b in
                let wa = worth(of: a, registry: registry)
                let wb = worth(of: b, registry: registry)
                return wa == wb ? a.id > b.id : wa < wb
            }
    }

    /// Whether this colony could work a recipe for `slot` at all: it makes the
    /// right kind of thing, the shop stands, the knowledge exists, and the
    /// colony can pay for it with as much again left for the builders.
    ///
    /// Deliberately says nothing about whether the *materials* are on the pile
    /// — that is the one question `bestGear` adds and this does not.
    static func canWork(
        _ recipe: RecipeDefinition, for slot: EquipmentSlot, at settlement: Settlement,
        in state: WorldState, registry: GameDataRegistry
    ) -> Bool {
        guard let item = registry.item(recipe.outputItemID),
              item.slot == .equipment, item.equipSlot == slot else { return false }
        if let building = recipe.requiresBuilding,
           !settlement.buildings.contains(where: { $0.definitionID == building }) {
            return false
        }
        if let tech = recipe.requiresTech,
           !state.researchedTechs.contains(tech) { return false }
        for resource in ResourceType.allCases {
            let cost = recipe.resourceCost[resource]
            guard cost > 0 else { continue }
            guard settlement.storage[resource] - cost >= cost * reserve else { return false }
        }
        return true
    }

    /// The best thing the colony could make for a slot and still afford to
    /// build with afterwards — or nil if there is nothing it can both work and
    /// pay for.
    ///
    /// **Best, not cheapest.** A town with a workshop and iron on the shelf
    /// should be turning out swords, not the bronze spear it started with; the
    /// affordability rule below is what stops that from beggaring it.
    /// **What share of an armed line should be able to shoot.**
    ///
    /// `bestGear` ranks by `worth`, which is damage — and a bow has less of it
    /// than an axe, every time. So the quartermaster made blades and only
    /// blades: measured after fifty years, **four of sixty-eight colonists
    /// carried anything ranged, all four a bow, and the shelf held nothing
    /// ranged at all**. Every volley in every fight was arrows for want of
    /// anything else, which is what "the salvos are always the same animation"
    /// turns out to be — a supply problem wearing a drawing's clothes.
    ///
    /// A line needs both: `CombatEngine.militia` has always counted melee and
    /// ranged separately, and `SiegeEngine.loose` gives the shooting its own
    /// phase. Two in five is enough that a colony always has somebody on the
    /// wall and never so many that nobody meets the charge.
    static let rangedShare = 0.4

    /// Whether the line is short of people who can shoot.
    static func wantsRanged(
        at settlement: Settlement, registry: GameDataRegistry
    ) -> Bool {
        var armed = 0, shooting = 0
        for pawn in settlement.pawns {
            guard let weapon = CombatEngine.weaponProfile(pawn, registry: registry)
            else { continue }
            armed += 1
            if weapon.kind == .ranged { shooting += 1 }
        }
        // …and what is waiting on the shelf to be handed out.
        for item in settlement.inventory {
            guard let combat = registry.item(item.definitionID)?.combat else { continue }
            armed += 1
            if combat.kind == .ranged { shooting += 1 }
        }
        guard armed > 0 else { return true }
        return Double(shooting) / Double(armed) < rangedShare
    }

    static func bestGear(
        for slot: EquipmentSlot, at settlement: Settlement,
        in state: WorldState, registry: GameDataRegistry,
        /// When set, only weapons of this class are considered — how the
        /// quartermaster keeps a share of the line able to shoot.
        preferring wanted: WeaponClass? = nil
    ) -> String? {
        let held = CraftingEngine.materialCounts(settlement)
        return registry.recipes.values
            .filter { recipe in
                guard canWork(recipe, for: slot, at: settlement,
                              in: state, registry: registry) else { return false }
                if let wanted {
                    guard registry.item(recipe.outputItemID)?.combat?.kind == wanted
                    else { return false }
                }
                // And the made things it is built out of — iron, timber, hide —
                // are on the pile. Ordering a sword the colony has no ingot for
                // parks the bench on an order it can never start.
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

    /// **How good a thing is, on the one scale the game already uses.**
    ///
    /// Public because the crafting panel needs exactly this answer and there
    /// must not be a second one. Four hundred and eleven recipes were listed
    /// alphabetically with a rarity dot and an ingredient list, and a hundred
    /// and sixteen of them were weapons whose damage runs 1 to 42 — none of it
    /// shown. A player choosing between a bone spear and a steel halberd had
    /// the same information about both, which is why the list read as enormous
    /// rather than merely long. The quartermaster has ranked gear on this scale
    /// since it was written; the panel says the same thing out loud now
    /// (rule 35).
    public static func worth(of item: ItemDefinition) -> Double {
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
    /// **Empty hands first, and only then a trade up.** A piece goes to somebody
    /// with nothing in that slot if anybody has nothing; failing that, to
    /// somebody for whom it is worth `worthTradingUp` times what they are
    /// already carrying — and what they put down goes straight back on the shelf
    /// for the next pass.
    ///
    /// The trade is what stops a town in the industrial age still carrying the
    /// spears of its first century: every slot was full, nothing ever came off
    /// anybody, and the plate harness sat on the shelf for ever. The margin is
    /// what stops it being a colony that spends every council sitting passing
    /// gear round itself, and what keeps a loadout the player set by hand.
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
            let wa = registry.item(a.definitionID).map { worth(of: $0, piece: a) } ?? 0
            let wb = registry.item(b.definitionID).map { worth(of: $0, piece: b) } ?? 0
            return wa == wb ? a.id.uuidString < b.id.uuidString : wa > wb
        }

        for item in shelf {
            guard let def = registry.item(item.definitionID),
                  let slot = def.equipSlot else { continue }
            let settlement = s.settlements[index]
            let hands = settlement.pawns.filter {
                $0.isAdult(ticksPerYear: ticksPerYear) && $0.health > 0
            }
            let offered = worth(of: def, piece: item)
            func pick(_ eligible: [Pawn]) -> Pawn? {
                eligible.max { a, b in
                    let wa = worth(of: def, to: a), wb = worth(of: def, to: b)
                    return wa == wb ? a.id.uuidString > b.id.uuidString : wa < wb
                }
            }
            // Bare hands first, always. A second coat on a warm back while
            // somebody stands in the rain is not an upgrade, it is a waste.
            var taker = pick(hands.filter { $0.equipment[slot] == nil })
            if taker == nil {
                taker = pick(hands.filter { holder in
                    guard let held = holder.equipment[slot],
                          let heldDef = registry.item(held.definitionID) else { return false }
                    let carrying = worth(of: heldDef, piece: held)
                    return offered >= carrying * worthTradingUp
                })
            }
            guard let taker else { continue }
            // `equipItem` already puts whatever they were holding back on the
            // shelf, so the spear a colonist puts down is there for the next
            // pair of empty hands.
            s = GameEngine.equipItem(s, settlementID: settlement.id,
                                     pawnID: taker.id, itemID: item.id,
                                     registry: registry)
        }
        return s
    }

    /// What a piece is worth with the maker's hand counted in — a masterwork
    /// spear beats a plain one, and beats a plain sword by enough that nobody
    /// puts it down for one.
    /// What a **particular piece** is worth: what it is, times how well it was
    /// made, times how much of it is left.
    ///
    /// The wear half is what closes §11.22's open note — *"nothing re-arms a
    /// colony whose gear has gone out of date"*. Gear that never wore out was
    /// gear nobody ever had a reason to replace, so the quartermaster's full
    /// slots stayed full for two hundred years. A blade that is half used up is
    /// now visibly worse than the new one on the shelf, and the swap happens
    /// for the ordinary reason.
    static func worth(of item: ItemDefinition, piece: ItemInstance) -> Double {
        piece.isBroken ? 0 : worth(of: item) * piece.effectiveness
    }

    /// How much better a thing has to be before somebody puts down what they
    /// are already holding.
    ///
    /// **Not a small margin, deliberately.** A colonist swapping for anything
    /// slightly better would have the whole colony passing gear round itself
    /// every council sitting, and would quietly undo a loadout the player set by
    /// hand. Twice as good is the difference between the spear of the first
    /// century and a plate harness — a thing worth crossing the square for —
    /// and not the difference between two axes.
    static let worthTradingUp = 2.0

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
