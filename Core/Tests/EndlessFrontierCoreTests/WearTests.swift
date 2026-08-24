import Testing
import Foundation
@testable import EndlessFrontierCore

/// §11.26 C, and the ask that opened it: *"poškození by mělo být od všeho, co to
/// poškodí, nejen šípy, ale i vlivy okolo."*
///
/// Two halves. **Things wear out** — the string `durability` appeared nowhere in
/// the project and `ItemInstance.quality` was written in `init` and never again,
/// so a sword carried through forty battles was exactly the sword it was forged
/// as. And **buildings are worn by what is around them** — every roof in the
/// colony aged at one flat rate, whether it was thatch on the frontier edge in a
/// tundra winter or a mortared vault in the middle of a street.
@Suite("Everything wears")
struct WearTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private func town() -> Settlement {
        var s = Settlement(
            id: UUID(uuidString: "3EA33EA3-0000-0000-0000-000000000001")!,
            name: "Hold",
            storage: [.food: 500], storageCapacity: .uniform(1000))
        s.colony = ColonyMap(width: 34, height: 34)
        return s
    }

    private func pawn(_ n: Int) -> Pawn {
        var p = Pawn(
            id: UUID(uuidString: String(format: "3EA33EA3-0000-0000-0000-%012d", n + 10))!,
            name: "Hand \(n)")
        p.age = 25 * 60
        return p
    }

    // MARK: - The piece itself

    @Test("Wear is a second axis, not a worse grade")
    func wearAndQualityAreSeparate() {
        let masterwork = ItemInstance(definitionID: "iron_sword", quality: .masterwork, wear: 0.5)
        let shoddyNew = ItemInstance(definitionID: "iron_sword", quality: .shoddy, wear: 0)
        #expect(masterwork.quality == .masterwork, "what it was made as never changes")
        #expect(masterwork.effectiveness < ItemInstance(
            definitionID: "iron_sword", quality: .masterwork).effectiveness)
        #expect(masterwork.effectiveness > shoddyNew.effectiveness,
                "a notched masterwork is still not a shoddy new one")
    }

    @Test("Wearing a piece returns a new one and never runs past nothing")
    func wearIsImmutableAndBounded() {
        let fresh = ItemInstance(definitionID: "iron_sword")
        let used = fresh.worn(by: 0.3)
        #expect(fresh.wear == 0, "the original is untouched")
        #expect(used.wear == 0.3)
        #expect(used.id == fresh.id, "it is the same object, later")
        #expect(fresh.worn(by: 5).wear == 1)
        #expect(fresh.worn(by: 5).isBroken)
    }

    @Test("A blade that is used up stops being a blade")
    func brokenGearDoesNothing() throws {
        let r = try registry()
        var holder = pawn(1)
        let sword = try #require(r.items.values.first { $0.combat != nil })
        holder.equipment[.weapon] = ItemInstance(definitionID: sword.id, wear: 0.99)
        #expect(CombatEngine.weaponProfile(holder, registry: r) == nil)

        holder.equipment[.weapon] = ItemInstance(definitionID: sword.id)
        let sound = try #require(CombatEngine.weaponProfile(holder, registry: r))
        holder.equipment[.weapon] = ItemInstance(definitionID: sword.id, wear: 0.5)
        let worn = try #require(CombatEngine.weaponProfile(holder, registry: r))
        #expect(worn.damage < sound.damage)
    }

    @Test("A battered coat turns less aside than a sound one")
    func armourWearReachesTheWound() throws {
        let r = try registry()
        let coat = try #require(r.items.values.first {
            $0.equipSlot == .armor && $0.slot == .equipment
        })
        var soundly = pawn(2)
        soundly.equipment[.armor] = ItemInstance(definitionID: coat.id)
        var battered = pawn(3)
        battered.equipment[.armor] = ItemInstance(definitionID: coat.id, wear: 0.8)
        #expect(CombatEngine.woundMultiplier(battered) > CombatEngine.woundMultiplier(soundly))
        var ruined = pawn(4)
        ruined.equipment[.armor] = ItemInstance(definitionID: coat.id, wear: 1)
        #expect(CombatEngine.woundMultiplier(ruined) == 1, "no coat at all")
    }

    // MARK: - Where wear comes from

    @Test("Swinging wears the weapon; being swung at wears the coat")
    func fightingWearsWhatIsHeld() throws {
        let r = try registry()
        let sword = try #require(r.items.values.first { $0.combat != nil })
        let coat = try #require(r.items.values.first { $0.equipSlot == .armor })
        var s = town()
        var a = pawn(1); a.equipment[.weapon] = ItemInstance(definitionID: sword.id)
        var b = pawn(2); b.equipment[.armor] = ItemInstance(definitionID: coat.id)
        s.pawns = [a, b]

        var met = SiegeEngine.Melee()
        met.colony = [(colonist: a.id, on: UUID())]
        met.raiders = [(raider: UUID(), on: b.id)]
        let after = SiegeEngine.wearGear(s, met: met)
        #expect((after.pawns[0].equipment[.weapon]?.wear ?? 0) > 0)
        #expect((after.pawns[1].equipment[.armor]?.wear ?? 0) > 0)
        #expect(after.pawns[0].equipment[.armor] == nil, "nothing wears what is not there")
        _ = r
    }

    @Test("A tool at work wears; a tool in a drawer does not")
    func workWearsTools() throws {
        let r = try registry()
        let tool = try #require(r.items.values.first { item in
            item.effects.contains { if case .skillBonus = $0 { return true }; return false }
        })
        var working = pawn(1)
        working.equipment[.weapon] = ItemInstance(definitionID: tool.id)
        working.currentJob = Job(
            id: UUID(uuidString: "3EA33EA3-0000-0000-0000-0000000000FF")!,
            kind: .fellTree, position: LocalPoint(x: 0.5, y: 0.5))
        var idle = pawn(2)
        idle.equipment[.weapon] = ItemInstance(definitionID: tool.id)

        var s = town()
        s.pawns = [working, idle]
        let after = ItemEngine.wearTools(s, registry: r, tick: 100)
        #expect((after.pawns[0].equipment[.weapon]?.wear ?? 0) > 0)
        #expect((after.pawns[1].equipment[.weapon]?.wear ?? 0) == 0)
    }

    @Test("What has come apart is taken out of their hands and written down")
    func brokenGearIsScrapped() throws {
        let r = try registry()
        let tool = try #require(r.items.values.first { $0.slot == .equipment })
        var holder = pawn(1)
        holder.equipment[.weapon] = ItemInstance(definitionID: tool.id, wear: 1)
        var s = town()
        s.pawns = [holder]
        let after = ItemEngine.scrapBroken(s, registry: r, tick: 240)
        #expect(after.pawns[0].equipment[.weapon] == nil)
        #expect(after.journal.entries.contains { $0.subject == .pawn(holder.id) })
    }

    /// §11.22's open note, closed: gear that never wore out was gear nobody had
    /// a reason to replace.
    @Test("A worn piece is worth less than the new one on the shelf")
    func theQuartermasterSeesWear() throws {
        let r = try registry()
        // **Sorted, and something that is actually worth something.**
        //
        // This was `items.values.first { $0.slot == .equipment }` — an
        // arbitrary entry out of a dictionary, so which piece it measured
        // changed the day the content did, and it eventually landed on a
        // leather halter: no combat, no effects, `worth` of zero fresh *and*
        // worn, and `used < fresh` is false when both are nothing. The order
        // was never the point; a piece that can lose value is.
        let def = try #require(
            r.items.values.sorted { $0.id < $1.id }
                .first { $0.slot == .equipment && QuartermasterEngine.worth(of: $0) > 0 },
            "no piece of equipment in the book is worth anything")
        let fresh = QuartermasterEngine.worth(
            of: def, piece: ItemInstance(definitionID: def.id))
        let used = QuartermasterEngine.worth(
            of: def, piece: ItemInstance(definitionID: def.id, wear: 0.7))
        let ruined = QuartermasterEngine.worth(
            of: def, piece: ItemInstance(definitionID: def.id, wear: 1))
        #expect(used < fresh)
        #expect(ruined == 0, "scrap is not stock")
    }

    // MARK: - Buildings, and what is around them

    @Test("Frost and heat are both harder on a roof than a mild day")
    func theSkyWearsBuildings() {
        #expect(BuildingEngine.skyWear(12) == 1)
        #expect(BuildingEngine.skyWear(-25) > 1.5)
        #expect(BuildingEngine.skyWear(42) > 1)
        #expect(BuildingEngine.skyWear(-25) > BuildingEngine.skyWear(42),
                "a hard frost is worse than a hot afternoon")
    }

    @Test("Timber ages faster than mortared stone")
    func substanceDecidesTheRate() {
        #expect(BuildingEngine.substanceWear(.wood) > BuildingEngine.substanceWear(.stone))
        #expect(BuildingEngine.substanceWear(.foliage) > BuildingEngine.substanceWear(.wood))
    }

    @Test("The building on the edge of town weathers faster than the one in it")
    func exposureCounts() throws {
        let r = try registry()
        var s = town()
        // Same building, twice: one by the green, one out on the rim.
        s = ColonyBuilder.place(s, definitionID: "hut", at: TileCoord(19, 19), registry: r)
        s = ColonyBuilder.place(s, definitionID: "hut", at: TileCoord(1, 1), registry: r)
        let after = BuildingEngine.weather(s, registry: r, tick: 40,
                                           climate: Climate(shift: 0))
        let inner = try #require(after.colony?.placements.first)
        let outer = try #require(after.colony?.placements.last)
        #expect(outer.condition < inner.condition)
        #expect(inner.condition < 1, "and both of them weather")
    }

    @Test("A hard winter is a hard winter for the buildings too")
    func aBadYearReachesTheRoofs() throws {
        let r = try registry()
        var s = town()
        s = ColonyBuilder.place(s, definitionID: "hut", at: TileCoord(10, 10), registry: r)
        // Winter falls at three quarters of the year in this calendar; the two
        // climates differ only in how cold the country is.
        let winterTick = (r.config.ticksPerYear / 4) * 3
        let mild = BuildingEngine.weather(s, registry: r, tick: winterTick,
                                          climate: Climate(shift: 12))
        let bitter = BuildingEngine.weather(s, registry: r, tick: winterTick,
                                            climate: Climate(shift: -14))
        #expect((bitter.colony?.placements[0].condition ?? 1)
                < (mild.colony?.placements[0].condition ?? 0))
    }
}

/// **Who mends the town.**
///
/// Found in a fifty-year-old save, by looking at a night with no lights in it:
/// thirty-three of fifty-five buildings were below `derelictBelow`, six of the
/// nine dwellings held nobody because a wreck sleeps nobody, and thirty-four
/// colonists slept rough beside their own empty houses. The stores were full —
/// three and a half thousand materials — and thirteen adults were **idle**.
///
/// The cause was one line in `LaborEngine`: `if work == .building,
/// !hasConstruction { continue }`. The mason's trade only existed while a
/// scaffold stood, so the moment the last building was finished the colony
/// drained it to zero and never staffed it again — while `BuildingEngine.repair`
/// went on asking for masons every interval and getting `max(1, 0)`. One
/// notional pair of hands puts back `repairPerBuilder` a interval; fifty-five
/// buildings take about five times that off. The town could not stop rotting.
///
/// `needingRepair` — commented "everything that wants a mason" — had **no
/// callers at all**, which is the same fault written down twice.
///
/// This is rule 14 from the other side: wear is charged per building and repair
/// was budgeted per colony, so the bigger the town the further behind it fell.
@Suite("A colony keeps its own roofs up")
struct RoofUpkeepTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private func town(hands: Int) -> Settlement {
        var s = Settlement(
            id: UUID(uuidString: "3EA33EA3-0000-0000-0000-0000000000B1")!,
            name: "Mendham",
            pawns: (0..<hands).map { i in
                var p = Pawn(
                    id: UUID(uuidString: String(format: "3EA33EA3-0000-0000-0000-%012d", 500 + i))!,
                    name: "Hand \(i)")
                p.age = 25 * 60
                return p
            },
            storage: [.food: 900, .materials: 4000],
            storageCapacity: .uniform(9000))
        s.colony = ColonyMap(width: 34, height: 34)
        return s
    }

    /// A town of standing buildings that have been let go, and no scaffold
    /// anywhere — the state every colony reaches the moment it stops expanding.
    ///
    /// Built at a real colony's *size*, because size is the whole fault: wear is
    /// charged per building and the repair budget was not, so six huts hid the
    /// bug and fifty-five showed it.
    private func wornTown(hands: Int, roofs: Int = 40,
                          condition: Double = 0.4) throws -> Settlement {
        let r = try registry()
        var s = town(hands: hands)
        var placed = 0
        for row in 0..<8 where placed < roofs {
            for col in 0..<8 where placed < roofs {
                s = ColonyBuilder.place(s, definitionID: "hut",
                                        at: TileCoord(3 + col * 4, 3 + row * 4), registry: r)
                placed = s.colony?.placements.count ?? 0
            }
        }
        #expect((s.colony?.placements.count ?? 0) >= roofs, "the town did not get built")
        for i in s.colony!.placements.indices {
            s.colony!.placements[i].underConstruction = false
            s.colony!.placements[i].condition = condition
        }
        #expect(s.constructions.isEmpty, "nothing is being raised — that is the point")
        return s
    }

    @Test("A roof that leaks is work, even when nothing is being built")
    func repairIsBuildingWork() throws {
        let r = try registry()
        let worn = try wornTown(hands: 20)
        #expect(!BuildingEngine.needingRepair(worn).isEmpty)

        let staffed = LaborEngine.assignIdleAdults(worn, registry: r)
        let masons = staffed.pawns.count { $0.assignedWork == .building }
        #expect(masons > 0, "nobody was put on the town's own upkeep")
    }

    @Test("A town in good repair does not keep masons standing about")
    func soundTownsNeedNoMasons() throws {
        let r = try registry()
        var sound = try wornTown(hands: 20, condition: 1)
        sound = LaborEngine.assignIdleAdults(sound, registry: r)
        #expect(sound.pawns.count { $0.assignedWork == .building } == 0,
                "there is nothing to build and nothing to mend")
    }

    /// How many hands the upkeep is worth has to follow the **roofs**, not the
    /// headcount: that is the half of this the open trade alone did not fix.
    @Test("A bigger town puts more of itself on its own roofs")
    func upkeepScalesWithTheTown() throws {
        let small = try wornTown(hands: 40, roofs: 12)
        let large = try wornTown(hands: 40, roofs: 55)
        let sSmall = LaborEngine.masonShare(small, adultCount: 40)
        let sLarge = LaborEngine.masonShare(large, adultCount: 40)
        #expect(sSmall == LaborEngine.baseBuildingShare,
                "a dozen roofs is what the plain share was written for")
        #expect(sLarge > sSmall)
        #expect(sLarge <= LaborEngine.maxBuildingShare,
                "never so many that the town is all scaffolds and no dinner")
    }

    @Test("A town in good repair asks for no more masons than the plain share")
    func soundTownsAskForNothingExtra() throws {
        let sound = try wornTown(hands: 40, condition: 1)
        #expect(LaborEngine.masonShare(sound, adultCount: 40) == LaborEngine.baseBuildingShare)
    }

    /// The one that matters, and the shape of the save it was found in: forty
    /// roofs, forty adults, everything let go to 0.4, materials in the store.
    /// Before the fix this fell to 0.26 over the same stretch and kept going.
    @Test("Left alone with hands and materials, a town mends faster than it rots")
    func theTownStopsRotting() throws {
        let r = try registry()
        var s = try wornTown(hands: 40)
        let before = BuildingEngine.upkeepFraction(s)
        for tick in 1...(25 * r.config.ticksPerYear) {
            s = LaborEngine.assignIdleAdults(s, registry: r)
            if tick % BuildingEngine.interval == 0 {
                s = BuildingEngine.weather(s, registry: r, tick: tick, climate: Climate(shift: 0))
                s = BuildingEngine.repair(s, registry: r)
            }
        }
        let after = BuildingEngine.upkeepFraction(s)
        #expect(after > before, "the town went on falling down with masons and materials to hand")
        #expect(after > 0.6, "and a quarter-century of upkeep should show")
        #expect(after > BuildingEngine.derelictBelow,
                "nothing a colony lives in should be left derelict by default")
    }

    /// …and the colony still has to eat while it mends. A mason share that
    /// outranked the floors would answer a leaking roof by taking the cook.
    @Test("Mending the town never takes its last cook")
    func upkeepNeverStarvesTheColony() throws {
        let r = try registry()
        var s = try wornTown(hands: 12, roofs: 55, condition: 0.2)
        for _ in 1...20 { s = LaborEngine.assignIdleAdults(s, registry: r) }
        #expect(s.pawns.contains { $0.assignedWork == .cooking })
        #expect(s.pawns.contains { $0.assignedWork == .farming })
    }
}
