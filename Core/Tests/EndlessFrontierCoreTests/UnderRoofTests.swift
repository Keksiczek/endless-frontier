import Testing
import Foundation
@testable import EndlessFrontierCore

/// Whether somebody is indoors is a thing the simulation knows, and the card
/// has to say the same thing the canvas draws (rule 18).
///
/// Keks's screenshot is the whole suite in one line: a hunter, out stalking
/// game, at zero degrees, with the card reading **"Venku 0 °C · střecha +26"**
/// — outside, and credited a full roof. `housed` was `pawn.homeID != nil`,
/// which is *owning a bed* rather than *standing under one*, so every colonist
/// who had ever been given a house was warm wherever they were.
@Suite("Under a roof means under a roof")
struct UnderRoofTests {

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "8007F00D-0000-0000-0000-%012d", n))!
    }

    private func housedPawn() -> Pawn {
        var p = Pawn(id: id(1), name: "Rarun")
        p.homeID = id(99)          // they own a bed, like everybody in a colony
        return p
    }

    private func job(_ kind: JobKind) -> Job {
        Job(id: id(2), kind: kind, position: LocalPoint(x: 0.2, y: 0.2))
    }

    @Test("A hunter out stalking game is outdoors, house or no house")
    func theHunterIsOutside() {
        var hunter = housedPawn()
        hunter.currentJob = job(.stalkAnimal)
        #expect(!ComfortEngine.underRoof(hunter))
    }

    @Test("Work that happens at a bench or a fire is indoors")
    func theBenchIsIndoors() {
        for kind in [JobKind.craftItem, .cookMeal] {
            var worker = housedPawn()
            worker.currentJob = job(kind)
            #expect(ComfortEngine.underRoof(worker), "\(kind.rawValue) is not under cover")
        }
    }

    /// Every kind, so a job added later has to answer the question rather than
    /// inheriting whichever default happened to be there.
    @Test("Every kind of work says whether it is out in the weather")
    func everyJobKindDecides() {
        let outdoors: Set<JobKind> = [.fellTree, .quarryRock, .raiseBuilding, .tendDeposit,
                                      .standWatch, .stalkAnimal, .cutStone, .workPlot]
        for kind in JobKind.allCases {
            #expect(kind.isUnderCover == !outdoors.contains(kind),
                    "\(kind.rawValue) has not been decided about")
        }
    }

    @Test("Somebody walking to the granary is out in it")
    func anErrandIsOutdoors() {
        var walker = housedPawn()
        walker.errand = Errand(kind: .eat, from: LocalPoint(x: 0.1, y: 0.1),
                               to: LocalPoint(x: 0.6, y: 0.6), leftAt: 0, arrivesAt: 5)
        #expect(!ComfortEngine.underRoof(walker))
    }

    @Test("So is somebody carrying a load home, and somebody away at a ruin")
    func haulingAndBeingAwayAreOutdoors() {
        var hauler = housedPawn()
        hauler.carrying = HaulLoad(itemID: "wood", amount: 4,
                                   destination: LocalPoint(x: 0.5, y: 0.5))
        #expect(!ComfortEngine.underRoof(hauler))

        var away = housedPawn()
        away.expeditionID = id(7)      // `isAway` is derived from this
        #expect(away.isAway)
        #expect(!ComfortEngine.underRoof(away))
    }

    @Test("Somebody with nothing to do is about the house")
    func idleAtHomeIsIndoors() {
        #expect(ComfortEngine.underRoof(housedPawn()))
        var homeless = housedPawn()
        homeless.homeID = nil
        #expect(!ComfortEngine.underRoof(homeless), "no roof to be under")
    }

    /// The number the screenshot showed, asserted rather than described: the
    /// roof term has to actually vanish when somebody walks out of the door.
    @Test("Going outside costs you the roof")
    func theRoofTermFollowsThePerson() {
        let winter = Climate(shift: 0)
        var hunter = housedPawn()
        hunter.currentJob = job(.stalkAnimal)

        let inside = ComfortEngine.reckon(
            season: .winter, housed: ComfortEngine.underRoof(housedPawn()),
            clothing: 0, shelter: 14, climate: winter)
        let outside = ComfortEngine.reckon(
            season: .winter, housed: ComfortEngine.underRoof(hunter),
            clothing: 0, shelter: 14, climate: winter)

        #expect(inside.roof > 0, "being indoors is worth nothing")
        #expect(outside.roof == 0, "a hunter in the snow is credited a roof")
        #expect(outside.warmth < inside.warmth)
    }
}
