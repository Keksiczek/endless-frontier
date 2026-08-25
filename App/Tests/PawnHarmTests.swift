import Testing
import Foundation
import EndlessFrontierCore
@testable import EndlessFrontier

/// **The body on the canvas is the body in the save.**
///
/// `Body` has carried parts that go missing and ailments that name the part
/// they landed on since the medical model went in, and the figure drew hair,
/// build, height and skin — so a colonist with one arm walked to work swinging
/// two, and a man bandaged after a raid was drawn exactly like the man who had
/// missed it. Keks: *"zranění neodpovídají tomu, co vidíme na plátně."*
@Suite("What a body shows")
struct PawnHarmTests {

    private func pawn() -> Pawn {
        Pawn(id: UUID(uuidString: "HA0D0000-0000-0000-0000-000000000001")
             ?? UUID(), name: "Wounded")
    }

    @Test("A whole colonist has nothing to draw")
    func theUnhurtCostOneBranch() {
        let harm = PawnHarm.of(pawn())
        #expect(!harm.isHurt)
        #expect(!harm.limps)
    }

    @Test("A missing arm is a missing arm")
    func lostLimbsShow() {
        var one = pawn()
        for index in one.body.parts.indices where one.body.parts[index].kind == .rightArm {
            one.body.parts[index].missing = true
        }
        let harm = PawnHarm.of(one)
        #expect(harm.rightArm == .gone)
        #expect(harm.leftArm == .whole)
        #expect(harm.isHurt)
    }

    @Test("A hurt leg limps; a lost one takes a stick")
    func legsDecideTheWalk() {
        var hurt = pawn()
        for index in hurt.body.parts.indices where hurt.body.parts[index].kind == .leftLeg {
            hurt.body.parts[index].condition = 0.4
        }
        #expect(PawnHarm.of(hurt).leftLeg == .hurt)
        #expect(PawnHarm.of(hurt).limps)

        var lost = pawn()
        for index in lost.body.parts.indices where lost.body.parts[index].kind == .leftLeg {
            lost.body.parts[index].missing = true
        }
        #expect(PawnHarm.of(lost).leftLeg == .gone)
    }

    @Test("Tended wounds show linen; untended ones show blood")
    func dressingIsVisible() {
        var tended = pawn()
        tended.body.ailments.append(Ailment(
            id: UUID(), kind: .wound, part: .torso, severity: 0.5, tended: true,
            wound: .cut))
        let dressed = PawnHarm.of(tended)
        #expect(dressed.bandaged.contains(.torso))
        #expect(!dressed.open.contains(.torso))

        var raw = pawn()
        raw.body.ailments.append(Ailment(
            id: UUID(), kind: .wound, part: .torso, severity: 0.5, tended: false,
            wound: .cut))
        let open = PawnHarm.of(raw)
        #expect(open.open.contains(.torso))
        #expect(!open.bandaged.contains(.torso))
    }

    /// A fever is something the card says and the figure shows by being laid
    /// up — not by bleeding from a limb it never hurt.
    @Test("An illness is not a wound")
    func sicknessDoesNotBleed() {
        var ill = pawn()
        ill.body.ailments.append(Ailment(
            id: UUID(), kind: .sickness, part: .torso, severity: 0.6))
        let harm = PawnHarm.of(ill)
        #expect(harm.open.isEmpty)
        #expect(harm.bandaged.isEmpty)
    }
}
