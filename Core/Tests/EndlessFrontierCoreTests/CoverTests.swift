import Testing
import Foundation
@testable import EndlessFrontierCore

/// §11.27 — a building is a solid object, and one day something shoots past it.
///
/// The model is **two axes multiplied**: how high a thing stands and what it is
/// made of. These pin the cases that prove it is a model rather than a table of
/// hand-set numbers waiting to drift.
@Suite("What stands in the way")
struct CoverTests {

    // MARK: - The rule

    @Test("A bush stops the eye and not the arrow; a boulder stops both")
    func heightAndSubstanceBothCount() {
        let bush = Cover.fraction(SceneryKind.bush.body.stature,
                                  SceneryKind.bush.body.substance)
        let boulder = Cover.fraction(SceneryKind.boulder.body.stature,
                                     SceneryKind.boulder.body.substance)
        #expect(bush < 0.15, "a hedge is not a wall")
        #expect(boulder > 0.4, "and a boulder is")
        #expect(boulder > bush * 4)
    }

    /// The case the whole model was chosen to get right: a ravine is ground
    /// going the *other* way. Impassable, and no shelter at all.
    @Test("A ravine stops a walker dead and an arrow not at all")
    func theRavineProvesTheAxisIsHeight() {
        #expect(LandformKind.ravine.blocksMovement)
        let body = LandformKind.ravine.body
        #expect(Cover.fraction(body.stature, body.substance) == 0)
    }

    /// …and its mirror, which is why the two axes cannot be collapsed into one.
    @Test("Old walls are walked through and sheltered behind")
    func aRuinIsPassableAndCovering() {
        #expect(!LandformKind.ruinField.blocksMovement)
        let body = LandformKind.ruinField.body
        #expect(Cover.fraction(body.stature, body.substance) > 0.5)
    }

    @Test("At one height, what a thing is made of still decides it")
    func substanceSeparatesEqualHeights() {
        let hedge = Cover.fraction(.chest, .foliage)
        let palisade = Cover.fraction(.chest, .wood)
        let wall = Cover.fraction(.chest, .stone)
        #expect(hedge < palisade)
        #expect(palisade < wall)
    }

    @Test("Nothing on the map gives more shelter than a building")
    func aBuildingIsTotal() {
        let building = Cover.fraction(Cover.building.stature, Cover.building.substance)
        #expect(building == 1)
        for kind in SceneryKind.allCases {
            #expect(Cover.fraction(kind.body.stature, kind.body.substance) <= building)
        }
    }

    // MARK: - The line

    private func map(scenery: [SceneryProp] = []) -> LocalMap {
        var m = LocalMap(river: RiverShape(baseY: 0.95, amplitude: 0, phase: 0),
                         nodes: [], pois: [])
        m.scenery = scenery
        m.trees = []
        m.rocks = []
        return m
    }

    @Test("Open ground between two people is open ground")
    func nothingIsNothing() {
        let field = CoverField(map())
        #expect(field.between(LocalPoint(x: 0.2, y: 0.5), LocalPoint(x: 0.8, y: 0.5)) == 0)
    }

    @Test("A boulder on the line shelters what is behind it")
    func somethingOnTheLineCounts() {
        let boulder = SceneryProp(id: 1, kind: .boulder,
                                  position: LocalPoint(x: 0.5, y: 0.5), scale: 1)
        let field = CoverField(map(scenery: [boulder]))
        let across = field.between(LocalPoint(x: 0.2, y: 0.5), LocalPoint(x: 0.8, y: 0.5))
        #expect(across > 0.4, "the shot crosses it and it is waist-high stone")
        // …and a shot that goes round it does not.
        let past = field.between(LocalPoint(x: 0.2, y: 0.2), LocalPoint(x: 0.8, y: 0.2))
        #expect(past == 0, "nothing stands on that line")
    }

    /// Cover is a wall, and walls do not add up: three hedges in a row are one
    /// hedge's worth of shelter, not three.
    @Test("The greatest thing on the line decides it, not the sum")
    func coverIsTheWorstNotTheTotal() {
        let hedges = (0..<3).map {
            SceneryProp(id: $0, kind: .bush,
                        position: LocalPoint(x: 0.4 + Double($0) * 0.05, y: 0.5), scale: 1)
        }
        let one = CoverField(map(scenery: [hedges[0]]))
            .between(LocalPoint(x: 0.2, y: 0.5), LocalPoint(x: 0.8, y: 0.5))
        let three = CoverField(map(scenery: hedges))
            .between(LocalPoint(x: 0.2, y: 0.5), LocalPoint(x: 0.8, y: 0.5))
        #expect(one == three)
        #expect(three < 1)
    }

    @Test("Nobody is blocked by the ground they are standing on")
    func youShootOverYourOwnParapet() {
        let boulder = SceneryProp(id: 1, kind: .boulder,
                                  position: LocalPoint(x: 0.2, y: 0.5), scale: 1)
        let field = CoverField(map(scenery: [boulder]))
        // The shooter is standing at the boulder; it is not in their way.
        #expect(field.between(LocalPoint(x: 0.2, y: 0.5), LocalPoint(x: 0.8, y: 0.5)) == 0)
    }

    @Test("A cover field with nothing in it answers nothing, and does not crash")
    func theEmptyFieldIsSafe() {
        let field = CoverField()
        #expect(field.isEmpty)
        #expect(field.at(LocalPoint(x: 0.5, y: 0.5)) == 0)
        #expect(field.between(LocalPoint(x: 0, y: 0), LocalPoint(x: 1, y: 1)) == 0)
    }

    /// Total cover must not be a veto: an archer facing a wall who simply never
    /// shoots is a fight that stalls. See `SiegeEngine.coverBite`.
    @Test("Even total cover leaves something to shoot at")
    func coverTaxesRatherThanVetoes() {
        #expect(SiegeEngine.coverBite < 1)
        #expect(SiegeEngine.coverBite > 0.5, "and it still has to actually bite")
    }
}
