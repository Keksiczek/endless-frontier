import Testing
import Foundation
@testable import EndlessFrontierCore

/// What a fight **looks like**, which is a property of the simulation and not
/// of the renderer (rule 18: what is in the simulation is on the canvas).
///
/// Keks, watching one: *"bitva nevypadá jako bitva ale jako dvě řady lidí co
/// mávají mečem — chtěl bych aby bylo realnější."* It was not the drawing.
/// `SiegeField.post` laid every fighter on a **single arc** at one `reach`,
/// both sides — defenders at 0.30, raiders at 0.48 — so twenty against twenty
/// was two parallel lines by construction. And `closingPoint` pulled every
/// defender back onto one ring, so even a formation that started deep flattened
/// the moment anybody swung.
@Suite("A battle has a shape")
struct BattleShapeTests {

    private func field() -> SiegeField { SiegeField(approach: 0) }

    /// How many distinct distances-from-the-heart a body of people occupies.
    /// One means a row. The number is the whole complaint.
    private func depth(of points: [LocalPoint], field: SiegeField) -> Int {
        Set(points.map { (SiegeField.distance(field.heart, $0) * 100).rounded() }).count
    }

    @Test("Twenty defenders are a body of people, not a row")
    func aLineHasDepth() {
        let f = field()
        let posts = (0..<20).map { f.defenderPost(index: $0, of: 20) }
        #expect(depth(of: posts, field: f) > 2,
                "twenty defenders stand at \(depth(of: posts, field: f)) depths — that is a row")
        // …and the depth runs the right way for each side: a defender's rear is
        // toward the town, a raider's is out toward the country they came from.
        let backDefender = f.defenderPost(index: 19, of: 20)
        let frontDefender = f.defenderPost(index: 0, of: 20)
        #expect(SiegeField.distance(f.heart, backDefender)
                < SiegeField.distance(f.heart, frontDefender))
        let backRaider = f.attackerPost(index: 19, of: 20)
        let frontRaider = f.attackerPost(index: 0, of: 20)
        #expect(SiegeField.distance(f.heart, backRaider)
                > SiegeField.distance(f.heart, frontRaider))
    }

    @Test("Nobody stands directly behind anybody")
    func ranksAreStaggered() {
        let f = field()
        let posts = (0..<21).map { f.defenderPost(index: $0, of: 21) }
        // Across the line of attack — the axis is 0, so that is y.
        let across = posts.map { ($0.y * 1000).rounded() }
        #expect(Set(across).count > SiegeField.abreast(of: 21),
                "every rank sits on the same \(Set(across).count) files — that is a grid")
    }

    /// A body of people has to stay roughly as wide as the ground it is fighting
    /// on, at every size. Ninety raiders on the old single arc came out
    /// `rankSpacing × 89` = 1.69 wide on a map one unit across — most of a
    /// warband stood off the edge of the world — and a fixed seven abreast
    /// swapped that for a column thirteen deep that funnelled onto two
    /// defenders.
    @Test("A warband is a body of people, whatever size it is")
    func formationsScaleWithTheirNumber() {
        let f = field()
        for count in [3, 8, 20, 40, 90, 200] {
            let posts = (0..<count).map { f.attackerPost(index: $0, of: count) }
            let across = posts.map { $0.y }
            let width = (across.max() ?? 0) - (across.min() ?? 0)
            let deep = posts.map { SiegeField.distance(f.heart, $0) }
            let depth = (deep.max() ?? 0) - (deep.min() ?? 0)
            #expect(width < 0.6, "\(count) of them stand \(width) wide, on a map one unit across")
            #expect(count < 4 || depth > 0,
                    "\(count) of them are still a single row")
            #expect(count < 4 || width > depth,
                    "\(count) of them are a column \(depth) deep and \(width) wide")
        }
    }

    /// The warband keeps its depth all the way in, because a raider walks at
    /// whoever they closed on and is never pulled back onto a ring.
    ///
    /// The defenders do **not**, and that is the half of this that is still to
    /// do — see `SiegeField.postReach`. `SiegeEngine.closingPoint` puts every
    /// defender on `posture.reach`, one ring for the whole line, as soon as
    /// they have a target. Holding each to their own rank's ring was tried and
    /// reverted: it changes who fights whom, and six of eight defenders stopped
    /// reaching anybody at all.
    @Test("The warband keeps its depth as it comes in")
    func theAttackKeepsItsDepth() throws {
        let registry = try GameDataRegistry.bundled()
        var settlement = Settlement(
            id: UUID(uuidString: "BA771E00-0000-0000-0000-000000000001")!,
            name: "Wallside", storage: [.food: 800], storageCapacity: 2000)
        settlement.pawns = (0..<20).map {
            Pawn(id: UUID(uuidString: String(format: "BA771E00-0000-0000-0000-%012d", $0))!,
                 name: "Hand \($0)")
        }
        settlement.siege = Siege(
            id: UUID(uuidString: "BA771E00-0000-0000-0000-0000000000FF")!,
            startTick: 0, openedAt: 0, attackerName: "Kamenní",
            attackerTribeID: UUID(uuidString: "BA771E00-0000-0000-0000-0000000000AA")!,
            approach: 0, attackers: 24, openingStrength: 60, fortification: 8,
            seed: 0xBEEF, line: settlement.pawns.map(\.id))

        for step in 1...4 {
            settlement = SiegeEngine.advance(settlement, to: step, registry: registry)
        }
        let siege = try #require(settlement.siege)
        let f = SiegeField(approach: siege.approach)
        let raiders = siege.fighters.filter { $0.side == .raider && !$0.down }.map(\.at)
        #expect(raiders.count > 8, "not enough of the warband left to say anything")
        #expect(depth(of: raiders, field: f) > 2,
                "the warband came in as \(depth(of: raiders, field: f)) rows")
    }
}
