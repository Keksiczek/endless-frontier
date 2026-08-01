import Testing
import Foundation
import SwiftUI
import EndlessFrontierCore
@testable import EndlessFrontier

/// The sun, the relief it lights, and the seasons that lie on the ground.
///
/// Rule 6 of the backlog — *check a threshold is reachable by the rate meant to
/// cross it* — has bitten seven times, most recently with a winter that could
/// not make anyone cold. Half of these are named for a reachability rather than
/// for a behaviour: `snowLiesDeepByMidwinter` fails if a whole winter can pass
/// without the ground going white, which is exactly the class of bug that keeps
/// shipping.
@Suite("The sun over the valley")
struct SettlementLightTests {

    // MARK: - The sun

    @Test("The sun is below the horizon at midnight")
    func sunIsDownAtMidnight() {
        let sun = SettlementLight.sun(time: 0)
        #expect(sun.elevation == 0)
        #expect(sun.daylight == 0)
        #expect(sun.strength == 0)
    }

    @Test("The sun stands overhead at noon")
    func sunIsOverheadAtNoon() {
        let sun = SettlementLight.sun(time: AgentMotion.dayLength * 0.5)
        #expect(abs(sun.elevation - 1) < 0.0001)
        #expect(sun.strength > 0.15)
    }

    /// The whole point of 2.10: a *low* sun. If dawn's shadow is not much
    /// longer than noon's there is no raking light and the town reads flat.
    @Test("Shadows rake at dawn and tuck under at noon")
    func shadowsAreLongAtDawn() {
        let dawn = SettlementLight.sun(time: AgentMotion.dayLength * 0.28)
        let noon = SettlementLight.sun(time: AgentMotion.dayLength * 0.5)
        #expect(length(dawn.shadow) > length(noon.shadow) * 2.2)
        #expect(length(dawn.shadow) <= SettlementLight.maxShadow * 1.1)
    }

    /// Morning and evening light must fall on opposite sides, or the sun does
    /// not cross the sky — it just pulses.
    @Test("The light swings across the day")
    func shadowsSwing() {
        let morning = SettlementLight.sun(time: AgentMotion.dayLength * 0.30)
        let evening = SettlementLight.sun(time: AgentMotion.dayLength * 0.70)
        #expect(morning.shadow.dx < 0)
        #expect(evening.shadow.dx > 0)
        // Both lean toward the viewer: this is an oblique view of flat ground.
        #expect(morning.shadow.dy > 0)
        #expect(evening.shadow.dy > 0)
    }

    @Test("The same hour of any day is the same sun")
    func sunIsPeriodic() {
        let a = SettlementLight.sun(time: AgentMotion.dayLength * 0.4)
        let b = SettlementLight.sun(time: AgentMotion.dayLength * 5.4)
        #expect(abs(a.elevation - b.elevation) < 1e-9)
        #expect(abs(a.shadow.dx - b.shadow.dx) < 1e-9)
        #expect(abs(a.shadow.dy - b.shadow.dy) < 1e-9)
        #expect(a.strength == b.strength)
    }

    // MARK: - Relief

    @Test("Relief stays in range and never crawls")
    func reliefIsStable() {
        for i in 0..<400 {
            let u = Double(i % 20) / 20, v = Double(i / 20) / 20
            let h = SettlementLight.relief(u, v, seed: 0xC0FFEE)
            #expect(h >= 0 && h <= 1)
            #expect(h == SettlementLight.relief(u, v, seed: 0xC0FFEE))
        }
    }

    @Test("Two worlds get two landscapes")
    func reliefDiffersBetweenSeeds() {
        let a = (0..<50).map { SettlementLight.relief(Double($0) / 50, 0.5, seed: 1) }
        let b = (0..<50).map { SettlementLight.relief(Double($0) / 50, 0.5, seed: 2) }
        #expect(a != b)
    }

    /// A flat light field is the bug 2.10 exists to fix. The land must actually
    /// vary — some of it lit, some of it in shade — under a real sun.
    @Test("The ground is not uniformly lit")
    func groundIsNotFlat() {
        let sun = SettlementLight.sun(time: AgentMotion.dayLength * 0.32)
        var lightest = -2.0, darkest = 2.0
        for i in 0..<40 {
            for j in 0..<40 {
                let lit = SettlementLight.slopeLight(
                    Double(i) / 40, Double(j) / 40, seed: 77, sun: sun)
                lightest = max(lightest, lit)
                darkest = min(darkest, lit)
            }
        }
        #expect(lightest - darkest > 0.8,
                "the ground reads flat — no slope is meaningfully lit")
    }

    /// Rule 10, one layer up — and the reason the valley was drawn in vertical
    /// stripes for as long as it was lit. The relief noise is round in `(u, v)`;
    /// `(u, v)` is drawn into a rect three times taller than it is wide; so
    /// without correction a hill comes out four times taller than it is broad,
    /// over and over, all the way down the screen.
    ///
    /// Named for the shape of the bug rather than for the behaviour: what must
    /// hold is that the land has *more* features down a long screen than across
    /// a short one, in the same proportion as the screen itself.
    @Test("Hills come out round on a phone, not as vertical stripes")
    func reliefIsRoundOnScreen() {
        let phone = CGRect(x: 0, y: 0, width: 400, height: 1200)
        let aspect = SettlementLight.aspect(of: phone)
        #expect(abs(aspect - 3) < 0.001)

        let across = features { SettlementLight.relief($0, 0.5, seed: 99, aspect: aspect) }
        let down = features { SettlementLight.relief(0.5, $0, seed: 99, aspect: aspect) }
        #expect(Double(down) > Double(across) * 1.6,
                "\(down) features down against \(across) across — still striped")

        // …and the uncorrected field is the bug itself: fewer features down
        // three times the ground.
        let stretched = features { SettlementLight.relief(0.5, $0, seed: 99) }
        #expect(stretched < down)
    }

    @Test("A freak layout cannot ask for a thousand octaves")
    func aspectIsClamped() {
        #expect(SettlementLight.aspect(of: CGRect(x: 0, y: 0, width: 1, height: 9_000)) == 5)
        #expect(SettlementLight.aspect(of: CGRect(x: 0, y: 0, width: 9_000, height: 1)) == 0.25)
        #expect(SettlementLight.aspect(of: .zero) == 1)
    }

    @Test("The land keeps its shape after dark")
    func reliefSurvivesTheNight() {
        let night = SettlementLight.sun(time: 0)
        let a = SettlementLight.slopeLight(0.2, 0.3, seed: 5, sun: night)
        let b = SettlementLight.slopeLight(0.8, 0.7, seed: 5, sun: night)
        #expect(a >= -1 && a <= 1)
        #expect(a != b)
    }

    // MARK: - Cast shadows

    @Test("A building's shadow reaches away from it")
    func boxShadowReachesOut() {
        let sun = SettlementLight.sun(time: AgentMotion.dayLength * 0.30)
        let path = SettlementLight.boxShadow(
            at: CGPoint(x: 100, y: 100), footprint: CGSize(width: 20, height: 12),
            height: 30, sun: sun)
        let box = path.boundingRect
        // It covers the caster's own footprint …
        #expect(box.minX <= 90.5)
        #expect(box.maxX >= 109.5)
        // … and runs out along the sun's line, which at this hour is leftward.
        #expect(box.minX < 90 + sun.shadow.dx * 30 + 1)
        #expect(box.height > 12)
    }

    @Test("Nothing casts a shadow at midnight")
    func nothingCastsAtNight() {
        // The callers' guard is `strength > 0.01`; assert the value they read.
        #expect(SettlementLight.sun(time: 0).strength < 0.01)
    }

    @Test("An overhead sun leaves only a contact patch")
    func blobDegradesAtNoon() {
        let noon = SettlementLight.sun(time: AgentMotion.dayLength * 0.5)
        let blob = SettlementLight.blobShadow(at: .zero, halfWidth: 6, height: 1, sun: noon)
        // Height 1 under a noon sun is a sub-pixel offset: one ellipse, no tail.
        #expect(blob.boundingRect.width < 14)
    }

    @Test("A tower throws further than a field of panels")
    func tallThingsThrowFurther() {
        #expect(SettlementRenderer.height(of: .tower)
                > SettlementRenderer.height(of: .array) * 3)
        #expect(SettlementRenderer.height(of: .house)
                > SettlementRenderer.height(of: .mine))
    }

    // MARK: - The seasons on the ground

    /// The reachability that matters: winter must actually turn the valley
    /// white, and early enough to be seen.
    @Test("Snow lies deep by midwinter")
    func snowLiesDeepByMidwinter() {
        #expect(SettlementSeasons.coverage(season: .winter, progress: 0.05) < 0.4,
                "winter should open with a dusting")
        #expect(SettlementSeasons.coverage(season: .winter, progress: 0.5) > 0.95,
                "midwinter must be deep, not a tint")
        #expect(SettlementSeasons.coverage(season: .winter, progress: 0.95) > 0.95,
                "the thaw is spring's business")
    }

    @Test("Most of the ground is white at midwinter")
    func midwinterIsWhite() {
        let covered = skinned(season: .winter, progress: 0.5) { $0 == .snow || $0 == .drift }
        #expect(covered > 0.7, "midwinter left only \(Int(covered * 100))% white")
    }

    @Test("The first days of winter leave ground showing")
    func winterArrivesGradually() {
        let covered = skinned(season: .winter, progress: 0.03) { $0 == .snow || $0 == .drift }
        #expect(covered < 0.5, "winter arrived all at once")
    }

    /// Spring is mud *first* and dry after — the opposite curve to winter's.
    @Test("Spring opens in mud and dries out")
    func springIsMudFirst() {
        #expect(SettlementSeasons.coverage(season: .spring, progress: 0.02) > 0.9)
        #expect(SettlementSeasons.coverage(season: .spring, progress: 0.95) < 0.05)
        let wet = skinned(season: .spring, progress: 0.05) { $0 == .mud || $0 == .puddle }
        #expect(wet > 0.35, "the thaw left no mud at all")
        let dry = skinned(season: .spring, progress: 0.95) { $0 == .mud || $0 == .puddle }
        #expect(dry < 0.05, "spring never dried out")
    }

    @Test("Leaves fall under the trees and nowhere else")
    func litterFallsUnderWoods() {
        let bare = skinned(season: .autumn, progress: 0.9, wood: 0) { $0 == .litter }
        let under = skinned(season: .autumn, progress: 0.9, wood: 1) { $0 == .litter }
        #expect(bare == 0)
        #expect(under > 0.5)
    }

    @Test("High summer burns off the ridges")
    func summerParchesLate() {
        let early = skinned(season: .summer, progress: 0.05) { $0 == .parched }
        let late = skinned(season: .summer, progress: 0.95) { $0 == .parched }
        #expect(early < 0.1)
        #expect(late > 0.3)
    }

    @Test("Rock and sand shed snow before a meadow does")
    func rockShedsSnow() {
        let onRock = skinned(season: .winter, progress: 0.16, cover: .rock) {
            $0 == .snow || $0 == .drift
        }
        let onMeadow = skinned(season: .winter, progress: 0.16, cover: .meadow) {
            $0 == .snow || $0 == .drift
        }
        #expect(onRock < onMeadow)
    }

    @Test("Snow settles in the hollows before the ridges")
    func snowFillsHollowsFirst() {
        let coverage = SettlementSeasons.coverage(season: .winter, progress: 0.20)
        let hollow = SettlementSeasons.skin(
            cover: .meadow, season: .winter, coverage: coverage,
            relief: 0.05, wood: 0, hash: SettlementGround.hash(1, 1, 1))
        let ridge = SettlementSeasons.skin(
            cover: .meadow, season: .winter, coverage: coverage,
            relief: 0.98, wood: 0, hash: SettlementGround.hash(1, 1, 1))
        #expect(hollow != .bare)
        #expect(ridge == .bare)
    }

    @Test("Every cover is answered in every season", arguments: Season.allCases)
    func everyCoverIsAnswered(season: Season) {
        for cover in GroundCover.allCases {
            for step in 0...4 {
                _ = SettlementSeasons.skin(
                    cover: cover, season: season, coverage: Double(step) / 4,
                    relief: 0.5, wood: 0.5, hash: SettlementGround.hash(9, step, 1))
            }
        }
    }

    // MARK: - Helpers

    private func length(_ v: CGVector) -> CGFloat { sqrt(v.dx * v.dx + v.dy * v.dy) }

    /// How many times a sampled line of ground crosses its own mean — a count
    /// of hills and hollows along it, which is what "how big is a feature"
    /// means when the field is noise rather than a shape.
    private func features(_ height: (Double) -> Double) -> Int {
        let samples = (0..<256).map { height(Double($0) / 256) }
        let mean = samples.reduce(0, +) / Double(samples.count)
        var crossings = 0
        for i in 1..<samples.count
        where (samples[i - 1] < mean) != (samples[i] < mean) { crossings += 1 }
        return crossings
    }

    /// What fraction of a sampled field of ground wears a skin the test wants.
    private func skinned(
        season: Season, progress: Double, cover: GroundCover = .meadow,
        wood: Double = 0.5, matching: (SettlementSeasons.Skin) -> Bool
    ) -> Double {
        let coverage = SettlementSeasons.coverage(season: season, progress: progress)
        var hits = 0, total = 0
        for i in 0..<48 {
            for j in 0..<48 {
                let relief = SettlementLight.relief(Double(i) / 48, Double(j) / 48, seed: 4242)
                let skin = SettlementSeasons.skin(
                    cover: cover, season: season, coverage: coverage,
                    relief: relief, wood: wood, hash: SettlementGround.hash(4242, i, j))
                total += 1
                if matching(skin) { hits += 1 }
            }
        }
        return Double(hits) / Double(total)
    }
}
