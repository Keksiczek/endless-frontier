import Testing
import Foundation
@testable import EndlessFrontierCore

/// A colonist has a body now. These pin the parts that fail quietly: a wound
/// that cannot actually kill anyone, a healer who does nothing, or a mauled arm
/// that costs the colony nothing.
@Suite("A colonist has a body")
struct BodyTests {

    private var registry: GameDataRegistry {
        GameDataRegistry(buildings: [], techs: [], eras: [], biomes: [], events: [],
                         config: .default)
    }

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-B0D9-%012d", n))!
    }

    private func colony(_ pawns: [Pawn], herbs: Int = 0) -> Settlement {
        var s = Settlement(id: id(999), name: "Infirmary", regionID: UUID())
        s.pawns = pawns
        s.storage[ResourceType.food] = 500
        if herbs > 0 { s.stockpile[MedicineEngine.herbItemID] = herbs }
        return s
    }

    private func hurt(_ name: String, part: BodyPartKind, by amount: Double,
                      n: Int = 0, work: WorkKind = .farming) -> Pawn {
        var p = Pawn(id: id(n), name: name, assignedWork: work)
        p.body.injure(part, by: amount, id: id(500 + n), tick: 0)
        p.health = max(0, p.health - amount)
        return p
    }

    // MARK: - Where a blow lands

    @Test("A blow lands somewhere, and the torso takes most of them")
    func blowsLandOnParts() {
        var counts: [BodyPartKind: Int] = [:]
        for i in 0..<2000 {
            let part = Body.struckPart(roll: Double(i) / 2000)
            counts[part, default: 0] += 1
        }
        #expect(counts.count == BodyPartKind.allCases.count, "some part is unreachable")
        let torso = counts[.torso] ?? 0
        let head = counts[.head] ?? 0
        #expect(torso > head, "a torso is a bigger target than a head")
    }

    @Test("A wound is on the part it landed on")
    func aWoundHasAPlace() {
        let mauled = hurt("Jarek", part: .rightArm, by: 30)
        #expect(mauled.body.ailments.count == 1)
        #expect(mauled.body.ailments[0].part == .rightArm)
        #expect(mauled.body.part(.rightArm)!.condition < 1)
        #expect(mauled.body.part(.leftArm)!.condition == 1, "the other arm is fine")
    }

    @Test("Losing a vital part is not survivable; losing an arm is")
    func vitalPartsAreVital() {
        var p = Pawn(id: id(1), name: "Unlucky")
        p.body.injure(.rightArm, by: 200, id: id(2), tick: 0)
        #expect(p.body.part(.rightArm)!.missing)
        #expect(p.body.isAlive)

        p.body.injure(.head, by: 200, id: id(3), tick: 0)
        #expect(!p.body.isAlive)
    }

    @Test("A colonist with no legs cannot walk, with no arms cannot work")
    func partsDoJobs() {
        var p = Pawn(id: id(4), name: "Broken")
        #expect(p.body.canWalk)
        #expect(p.body.canWork)
        for leg in [BodyPartKind.leftLeg, .rightLeg] {
            p.body.injure(leg, by: 200, id: id(600), tick: 0)
        }
        #expect(!p.body.canWalk)
        for arm in [BodyPartKind.leftArm, .rightArm] {
            p.body.injure(arm, by: 200, id: id(601), tick: 0)
        }
        #expect(!p.body.canWork)
    }

    // MARK: - Bleeding

    /// The recurring bug shape: a wound that cannot actually reach the
    /// threshold it is meant to cross. An untended wound has to be able to kill.
    @Test("An untended wound bleeds, and bleeding can kill")
    func bleedingIsReachable() {
        var s = colony([hurt("Bleeder", part: .torso, by: 45)])
        #expect(s.pawns[0].body.bleeding > 0)
        var ticks = 0
        while s.pawns[0].health > 0, ticks < 2000 {
            s = MedicineEngine.advanceOneTick(s, registry: registry, tick: ticks)
            ticks += 1
        }
        #expect(s.pawns[0].health == 0,
                "a wound nobody sees to should be able to carry somebody off")
    }

    @Test("A tended wound stops bleeding")
    func tendingStopsTheBleeding() {
        var s = colony([hurt("Bleeder", part: .torso, by: 40)])
        s = MedicineEngine.tendTheWounded(s, registry: registry, tick: 1)
        #expect(s.pawns[0].body.bleeding == 0)
        #expect(s.pawns[0].body.ailments.allSatisfy { $0.tended })
    }

    @Test("A healer tends more people than a colony without one")
    func healersTendMore() {
        func run(withHealer: Bool) -> Settlement {
            var pawns = (0..<5).map { i in hurt("Hurt\(i)", part: .torso, by: 35, n: i) }
            if withHealer {
                pawns.append(Pawn(id: id(90), name: "Herb", assignedWork: .healing))
            }
            var s = colony(pawns)
            s = MedicineEngine.tendTheWounded(s, registry: registry, tick: 1)
            return s
        }
        let alone = run(withHealer: false).pawns.count { $0.body.untended.isEmpty }
        let helped = run(withHealer: true).pawns.count { $0.body.untended.isEmpty }
        #expect(helped > alone)
    }

    @Test("The worst off is seen first")
    func triageWorksWorstFirst() {
        let light = hurt("Light", part: .leftArm, by: 10, n: 1)
        let grave = hurt("Grave", part: .torso, by: 48, n: 2)
        var s = colony([light, grave])
        s = MedicineEngine.tendTheWounded(s, registry: registry, tick: 1)
        let graveTended = s.pawns.first { $0.name == "Grave" }?.body.untended.isEmpty ?? false
        #expect(graveTended, "the one bleeding hardest should be reached first")
    }

    @Test("Herbs make the tending stick, and are spent doing it")
    func herbsAreUsed() {
        var s = colony([hurt("Hurt", part: .torso, by: 40)], herbs: 4)
        s = MedicineEngine.tendTheWounded(s, registry: registry, tick: 1)
        #expect((s.stockpile[MedicineEngine.herbItemID] ?? 0) < 4)
    }

    @Test("A wound closes over time, faster once it is tended")
    func woundsClose() {
        func run(tended: Bool) -> Double {
            var s = colony([hurt("Hurt", part: .leftArm, by: 30)])
            if tended { s = MedicineEngine.tendTheWounded(s, registry: registry, tick: 0) }
            for tick in 0..<40 {
                s = MedicineEngine.advanceOneTick(s, registry: registry, tick: tick)
            }
            return s.pawns.first?.body.ailments.first?.severity ?? 0
        }
        #expect(run(tended: true) < run(tended: false))
    }

    @Test("A lost arm does not grow back")
    func lostPartsStayLost() {
        var p = Pawn(id: id(7), name: "Onearm")
        p.body.injure(.rightArm, by: 200, id: id(8), tick: 0)
        var s = colony([p])
        for tick in 0..<500 {
            s = MedicineEngine.advanceOneTick(s, registry: registry, tick: tick)
        }
        #expect(s.pawns[0].body.part(.rightArm)!.missing)
    }

    // MARK: - What it costs the colony

    @Test("A mauled colonist is worth less of a day's work")
    func woundsCostWork() {
        let whole = Pawn(id: id(10), name: "Whole")
        let mauled = hurt("Mauled", part: .rightArm, by: 40, n: 11)
        #expect(MedicineEngine.workCapacity(mauled) < MedicineEngine.workCapacity(whole))
    }

    @Test("Somebody too badly hurt to stand is not at work at all")
    func theGravelyHurtDoNotWork() {
        var p = Pawn(id: id(12), name: "Down")
        for part in [BodyPartKind.leftArm, .rightArm, .leftLeg, .rightLeg] {
            p.body.injure(part, by: 200, id: id(700), tick: 0)
        }
        #expect(MedicineEngine.workCapacity(p) == 0)
    }

    @Test("A whole colonist is at full capacity, and their screen says nothing")
    func theWholeAreWhole() {
        let p = Pawn(id: id(13), name: "Fine")
        #expect(MedicineEngine.workCapacity(p) == 1)
        #expect(p.body.ailments.isEmpty)
        #expect(!p.body.needsTending)
    }

    @Test("Wounding is deterministic for a seed")
    func woundingIsDeterministic() {
        var a = SeededRNG(seed: 42)
        var b = SeededRNG(seed: 42)
        let one = MedicineEngine.wound(Pawn(id: id(14), name: "A"), amount: 25, tick: 3, rng: &a)
        let two = MedicineEngine.wound(Pawn(id: id(14), name: "A"), amount: 25, tick: 3, rng: &b)
        #expect(one.body.ailments.map(\.part) == two.body.ailments.map(\.part))
        #expect(one.health == two.health)
    }

    @Test("A colonist from an older save is whole")
    func oldSavesAreWhole() throws {
        let json = """
        {"id":"00000000-0000-0000-B0D9-000000000099","name":"Old","trait":"none",
         "skills":[],"skillXP":[],"needs":{"hunger":80,"rest":80,"recreation":70},
         "mood":70,"assignedWork":"idle","health":100,"isBroken":false}
        """
        let pawn = try JSONDecoder().decode(Pawn.self, from: Data(json.utf8))
        #expect(pawn.body.parts.count == BodyPartKind.allCases.count)
        #expect(pawn.body.isAlive)
        #expect(pawn.body.capacity == 1)
    }
}
