import Testing
import Foundation
@testable import EndlessFrontierCore

/// The last room the player was still standing in the doorway of.
///
/// `GameEngine.equipItem` was only ever called from the UI and the bench's
/// standing orders knew about building materials alone, so a colony left to
/// itself never made a spear, never made a coat and never handed anybody a hoe —
/// while `recipes.json` had a bronze spear in it for fifteen materials and the
/// store sat at two and a half thousand. The same shape as the frozen world, and
/// the same answer: the colony does the obvious thing, and what the player chose
/// stays chosen.
@Suite("The quartermaster")
struct QuartermasterTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    /// A settlement with hands, a full store, raw stuff on the shelf and
    /// nothing on anybody's back.
    ///
    /// The shelf is the part that used to be missing and did not show: the
    /// quartermaster's answer for a colony with nothing on it was
    /// `craft_bronze_spear`, which took **no materials at all** — a bronze
    /// spear out of fifteen generic materials, no bench, no study. That recipe
    /// is a bloomery and `bronze_tools` now, so a colony arms itself out of what
    /// it has gathered, which is what every other early recipe already asked
    /// for. Rule 89: a fixture that omits what the feature reads tests the
    /// fallback.
    private func bareColony(
        _ registry: GameDataRegistry, hands: Int = 6,
        work: WorkKind = .farming, materials: Double = 400
    ) -> Settlement {
        var s = Settlement(
            id: UUID(uuidString: "0A47E12A-0000-0000-0000-000000000001")!,
            name: "Bare",
            storage: [.materials: materials, .food: 400], storageCapacity: .uniform(500))
        s.stockpile["wood"] = 20
        s.stockpile["rough_stone"] = 20
        s.stockpile["hide"] = 20
        s.stockpile["leather"] = 20
        s.stockpile["timber_bundle"] = 20
        for i in 0..<hands {
            var p = Pawn(id: UUID(uuidString: String(
                format: "0A47E12A-1111-0000-0000-%012d", i))!, name: "Hand \(i)")
            p.age = 25 * registry.config.ticksPerYear
            p.assignedWork = work
            s.pawns.append(p)
        }
        return s
    }

    /// A world that has learned its whole book.
    ///
    /// The quartermaster asks for the materials of the gear the colony **can**
    /// make, so gating the book by chain depth (`BACKLOG.md` §30) changed what
    /// a colony with nothing researched wants — correctly: a town that has not
    /// learned to sew a coat has no business tanning hides for one. These tests
    /// are about the *chain*, not the ladder, so the world here knows
    /// everything and the chain is the only thing being measured (rule 109).
    private func world(_ settlement: Settlement, _ registry: GameDataRegistry) -> WorldState {
        var w = GameWorldFactory.newGame(registry: registry, seed: 7)
        w.settlements = [settlement]
        w.researchedTechs = Set(registry.techs.keys)
        return w
    }

    // MARK: - Ordering

    @Test("A colony with bare hands puts gear on the bench")
    func itOrdersWhatNobodyIsWearing() throws {
        let reg = try registry()
        let w = world(bareColony(reg), reg)
        let after = QuartermasterEngine.orderWhatIsBare(w, index: 0, registry: reg)
        let ordered = after.settlements[0].craftOrders.compactMap {
            reg.recipes[$0.recipeID].flatMap { reg.item($0.outputItemID) }
        }
        #expect(ordered.contains { $0.slot == .equipment },
                "six colonists with nothing on them and the bench is empty")
    }

    /// An endless order would have the bench turning out spears until the iron
    /// ran out. Gear is a stock the colony can name the size of, not a tap.
    @Test("The order is sized to the shortfall, not left running")
    func ordersAreFinite() throws {
        let reg = try registry()
        let w = world(bareColony(reg), reg)
        let after = QuartermasterEngine.orderWhatIsBare(w, index: 0, registry: reg)
        let gear = after.settlements[0].craftOrders.filter {
            reg.recipes[$0.recipeID].flatMap { reg.item($0.outputItemID)?.equipSlot } != nil
        }
        #expect(!gear.isEmpty)
        for order in gear {
            let wanted = try #require(order.wanted, "a standing order for gear never stops")
            #expect(wanted <= QuartermasterEngine.batch)
        }
    }

    /// Same reserve rule the council builds under. A colony that arms itself
    /// into a state where it cannot raise a roof has armed itself for nothing.
    @Test("A thin store buys no weapons")
    func theBuildersKeepTheirMaterials() throws {
        let reg = try registry()
        // Under twice the cheapest gear the colony could work — `reserve` is 1,
        // so the rule is "spend it only if the same again is left behind", and
        // the cheapest thing on this shelf is three materials.
        let w = world(bareColony(reg, materials: 2), reg)
        let after = QuartermasterEngine.orderWhatIsBare(w, index: 0, registry: reg)
        #expect(after.settlements[0].craftOrders.isEmpty,
                "two materials in the store and the colony ordered gear with them")
    }

    @Test("One person short of a coat is not a quartermaster's problem")
    func aSingleGapIsIgnored() throws {
        let reg = try registry()
        var s = bareColony(reg, hands: 1)
        // Everything else already dressed — one bare pair of hands is below the
        // threshold, and a bench order per colonist would never stop.
        s.pawns = Array(s.pawns.prefix(1))
        let after = QuartermasterEngine.orderWhatIsBare(world(s, reg), index: 0, registry: reg)
        #expect(after.settlements[0].craftOrders.isEmpty)
    }

    /// The link before the last one. A coat is `leather_garb`, leather is
    /// `tan_leather` out of hides — and leather is not a *building* material, so
    /// the only list of wanted materials in the game never asked for it. The
    /// tannery never ran, `bestGear` could never find an armour it was able to
    /// work, and a colony that armed forty of its fifty-five with spears and
    /// bows clothed **nobody, ever**, for two hundred years.
    @Test("The bench is asked for what the coats are made of")
    func theGearChainIsStocked() throws {
        let reg = try registry()
        var s = bareColony(reg)
        s.buildings.append(BuildingInstance(
            id: UUID(uuidString: "0A47E12A-6666-0000-0000-000000000001")!,
            definitionID: "hunters_lodge"))
        let w = world(s, reg)
        #expect(QuartermasterEngine.wantedMaterials(for: s, in: w, registry: reg)
            .contains("leather"),
                "the colony wants coats and never asks anybody to tan a hide")
        // …and the council's own list, which is the one the bench reads, has it.
        #expect(StewardEngine.wantedMaterials(for: s, in: w, registry: reg)
            .contains("leather"))
    }

    /// **The list must not grow with the content.**
    ///
    /// This is the failure content actually caused, and the reason the rule
    /// changed. `wantedMaterials` was the union over *every* workable gear
    /// recipe: seven ids when ten such recipes shipped, eighteen when a content
    /// pass took it to thirty — and `StewardEngine.keepMaterialsComing` places
    /// one standing order per wanted material, so the bench was split eighteen
    /// ways, nothing ever reached the amount a recipe needs, and the colony
    /// stopped arming itself entirely. Rule 14 in the supply chain.
    ///
    /// The bench makes one thing per slot. The list has to be about that many.
    @Test("The want list is about the gear, not about the size of the cookbook")
    func theWantListStaysShort() throws {
        let reg = try registry()
        var s = bareColony(reg)
        s.buildings.append(BuildingInstance(
            id: UUID(uuidString: "0A47E12A-7777-0000-0000-000000000001")!,
            definitionID: "hunters_lodge"))
        let w = world(s, reg)
        let wanted = QuartermasterEngine.wantedMaterials(for: s, in: w, registry: reg)
        // At most two recipes' worth per slot — the one it is aiming at and the
        // one it can finish — and a recipe is a handful of ingredients.
        let ceiling = EquipmentSlot.allCases.count * 2 * 4
        #expect(wanted.count <= ceiling,
                "the quartermaster is stocking for the whole cookbook: \(wanted)")
        #expect(!wanted.isEmpty, "and it has to want something")
    }

    /// The other half of the same rule: whatever it wants, the colony must be
    /// able to come by. A want list full of things nothing produces is a bench
    /// full of orders that never start.
    @Test("Everything wanted is something this colony could actually get")
    func everythingWantedIsReachable() throws {
        let reg = try registry()
        var s = bareColony(reg)
        s.buildings.append(BuildingInstance(
            id: UUID(uuidString: "0A47E12A-7777-0000-0000-000000000002")!,
            definitionID: "hunters_lodge"))
        let w = world(s, reg)
        let wanted = QuartermasterEngine.wantedMaterials(for: s, in: w, registry: reg)
        let reachable = wanted.filter {
            QuartermasterEngine.producible($0, at: s, in: w, registry: reg)
        }
        #expect(!reachable.isEmpty,
                "not one wanted material has a source: \(wanted)")
    }

    // MARK: - Handing it out

    @Test("What comes off the bench ends up on somebody")
    func gearIsHandedOut() throws {
        let reg = try registry()
        var s = bareColony(reg)
        s.inventory = [ItemInstance(
            id: UUID(uuidString: "0A47E12A-2222-0000-0000-000000000001")!,
            definitionID: "bronze_spear")]
        let after = QuartermasterEngine.handOutGear(world(s, reg), index: 0, registry: reg)
        #expect(after.settlements[0].pawns.contains { $0.equipment[.weapon] != nil },
                "a spear on the shelf and every hand still empty")
        #expect(after.settlements[0].inventory.isEmpty)
    }

    /// A weapon-slot item is a tool as often as it is a weapon — `sturdy_axe`
    /// hangs where a spear does — so the same axe is worth a great deal to a
    /// woodcutter and almost nothing to a scholar. The hand-out is a matching.
    @Test("A tool goes to the trade it helps")
    func toolsFindTheirTrade() throws {
        let reg = try registry()
        var s = bareColony(reg, hands: 0)
        for (i, work) in [WorkKind.research, .logging].enumerated() {
            var p = Pawn(id: UUID(uuidString: String(
                format: "0A47E12A-3333-0000-0000-%012d", i))!, name: "Hand \(i)")
            p.age = 25 * reg.config.ticksPerYear
            p.assignedWork = work
            s.pawns.append(p)
        }
        s.inventory = [ItemInstance(
            id: UUID(uuidString: "0A47E12A-4444-0000-0000-000000000001")!,
            definitionID: "sturdy_axe")]
        let after = QuartermasterEngine.handOutGear(world(s, reg), index: 0, registry: reg)
        let carrying = after.settlements[0].pawns.first { $0.equipment[.weapon] != nil }
        #expect(carrying?.assignedWork == .logging,
                "the axe went to \(carrying?.assignedWork.rawValue ?? "nobody")")
    }

    /// Empty hands outrank a better fit, always. A second coat on a warm back
    /// while somebody stands in the rain is not an upgrade, it is a waste.
    @Test("Bare hands are served before anybody trades up")
    func bareHandsComeFirst() throws {
        let reg = try registry()
        var s = bareColony(reg, hands: 2)
        let kept = ItemInstance(
            id: UUID(uuidString: "0A47E12A-5555-0000-0000-000000000001")!,
            definitionID: "worn_tools")
        s.pawns[0].equipment[.weapon] = kept
        s.inventory = [ItemInstance(
            id: UUID(uuidString: "0A47E12A-5555-0000-0000-000000000002")!,
            definitionID: "iron_sword")]
        let after = QuartermasterEngine.handOutGear(world(s, reg), index: 0, registry: reg)
        #expect(after.settlements[0].pawns[0].equipment[.weapon]?.id == kept.id,
                "the tools were taken out of somebody's hands while a colonist stood empty-handed")
        #expect(after.settlements[0].pawns[1].equipment[.weapon] != nil,
                "the sword sat on the shelf while somebody had nothing at all")
    }

    /// A town in the industrial age was still carrying the spears of its first
    /// century: every slot was full, nothing ever came off anybody, and the
    /// plate harness sat on the shelf for ever. Somebody has to want it.
    @Test("A colonist puts down a spear for a harness")
    func gearIsTradedUp() throws {
        let reg = try registry()
        var s = bareColony(reg, hands: 1, work: .garrison)
        let old = ItemInstance(
            id: UUID(uuidString: "0A47E12A-7777-0000-0000-000000000001")!,
            definitionID: "bronze_spear")
        s.pawns[0].equipment[.weapon] = old
        s.inventory = [ItemInstance(
            id: UUID(uuidString: "0A47E12A-7777-0000-0000-000000000002")!,
            definitionID: "chainsaw")]     // damage 6 → 18, well past the margin
        let after = QuartermasterEngine.handOutGear(world(s, reg), index: 0, registry: reg)
        #expect(after.settlements[0].pawns[0].equipment[.weapon]?.definitionID == "chainsaw",
                "twice the weapon on the shelf and nobody reached for it")
        #expect(after.settlements[0].inventory.contains { $0.id == old.id },
                "the spear they put down should be on the shelf for the next empty pair of hands")
    }

    /// …and not for anything slightly better, or the colony spends every
    /// council sitting passing gear round itself and a loadout set by hand
    /// never survives a season.
    @Test("Nobody swaps for a small improvement")
    func smallGainsAreNotWorthTheSwap() throws {
        let reg = try registry()
        var s = bareColony(reg, hands: 1, work: .garrison)
        let kept = ItemInstance(
            id: UUID(uuidString: "0A47E12A-8888-0000-0000-000000000001")!,
            definitionID: "iron_sword")
        s.pawns[0].equipment[.weapon] = kept
        s.inventory = [ItemInstance(
            id: UUID(uuidString: "0A47E12A-8888-0000-0000-000000000002")!,
            definitionID: "crossbow")]
        let after = QuartermasterEngine.handOutGear(world(s, reg), index: 0, registry: reg)
        #expect(after.settlements[0].pawns[0].equipment[.weapon]?.id == kept.id,
                "a colonist swapped a sword for a crossbow that is barely better")
    }

    /// The maker's hand counts: a masterwork is not put down for a plain piece
    /// of the next kind up.
    @Test("A masterwork is not traded for a plain upgrade")
    func qualityCountsInTheTrade() throws {
        let reg = try registry()
        var s = bareColony(reg, hands: 1, work: .garrison)
        let kept = ItemInstance(
            id: UUID(uuidString: "0A47E12A-9999-0000-0000-000000000001")!,
            definitionID: "iron_sword", quality: .masterwork)
        s.pawns[0].equipment[.weapon] = kept
        s.inventory = [ItemInstance(
            id: UUID(uuidString: "0A47E12A-9999-0000-0000-000000000002")!,
            definitionID: "chainsaw", quality: .shoddy)]
        let after = QuartermasterEngine.handOutGear(world(s, reg), index: 0, registry: reg)
        #expect(after.settlements[0].pawns[0].equipment[.weapon]?.id == kept.id,
                "a masterwork blade was put down for a shoddy one of the next kind up")
    }

    // MARK: - End to end

    /// The one that matters: nobody touching it, and the colony arms itself.
    @Test("A colony nobody equips arms itself")
    func aColonyLeftAloneArmsItself() throws {
        let reg = try registry()
        let start = GameWorldFactory.newGame(registry: reg, seed: 4242)
        #expect(start.settlements[0].pawns.allSatisfy { $0.equipment.isEmpty },
                "the founders start bare — if they do not, this proves nothing")
        let after = TickEngine.advance(start, ticks: 1800, registry: reg).state
        let dressed = after.settlements[0].pawns.count { !$0.equipment.isEmpty }
        #expect(dressed > 0,
                "thirty years and not one colonist has so much as a spear")
    }
}
