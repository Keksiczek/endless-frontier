import Testing
import Foundation
import SwiftUI
import EndlessFrontierCore
@testable import EndlessFrontier

/// **Night, and a clock to read it by.**
///
/// Keks, watching a town: *"teď všichni chodí spát, ale vypadá to stejně jako
/// přes den, klidně i hodiny k tomu, ať je přehled co se děje a lidé dělají."*
///
/// The day was all there — a five-minute drawn day, a schedule that puts people
/// to bed, a sun that goes under the horizon at `dusk`. Two things were not:
/// the darkness only started 0.09 of a day **after** sunset (so the first third
/// of every night was painted as noon), and nothing anywhere on the screen said
/// what hour it was.
///
/// These pin both, and the first one is a reachability test in the shape rule 6
/// keeps producing: it fails if there is a moment when the sun is down and the
/// valley is not dark.
@Suite("Night, and the hour")
struct NightTests {

    private func at(_ fraction: Double) -> Double { AgentMotion.dayLength * fraction }

    // MARK: - It actually goes dark

    @Test("Broad day is not darkened at all")
    func noonIsNotNight() {
        #expect(SettlementRenderer.nightness(time: at(0.5)) == 0)
        #expect(SettlementRenderer.nightness(time: at(0.35)) == 0)
        #expect(SettlementRenderer.nightness(time: at(0.65)) == 0)
    }

    @Test("The dead of night is fully dark")
    func midnightIsDark() {
        #expect(SettlementRenderer.nightness(time: at(0)) == 1)
        #expect(SettlementRenderer.nightness(time: at(0.98)) > 0.9)
    }

    /// **The bug, pinned.** Sunset was at 0.75 and the wash did not begin until
    /// 0.84, so an hour and a half of night was drawn in full daylight.
    @Test("The moment the sun goes down, the valley starts to darken")
    func duskIsNotDay() {
        let justAfterSunset = at(SettlementLight.dusk + 0.01)
        #expect(SettlementRenderer.nightness(time: justAfterSunset) > 0,
                "the sun is under the horizon and the light has to follow it")
        let deeper = at(SettlementLight.dusk + 0.05)
        #expect(SettlementRenderer.nightness(time: deeper)
                > SettlementRenderer.nightness(time: justAfterSunset),
                "and it keeps getting darker rather than switching")
    }

    @Test("Dawn brightens on the same rule, from the other side")
    func dawnIsSymmetric() {
        let beforeSunrise = at(SettlementLight.dawn - 0.01)
        #expect(SettlementRenderer.nightness(time: beforeSunrise) > 0)
        #expect(SettlementRenderer.nightness(time: at(SettlementLight.dawn + 0.01)) == 0)
    }

    /// Every hour the sun is down is an hour the valley is at least partly dark
    /// — the thing that was false, sampled all the way round the clock.
    /// The endpoints are excluded on purpose: at the exact instant of sunset
    /// the sun is *on* the horizon and nothing should have darkened yet. It is
    /// the hour after it that used to be drawn as noon.
    @Test("There is no hour with the sun down and the lamps off")
    func nightIsNeverDrawnAsDay() {
        for step in 0..<240 {
            let fraction = Double(step) / 240
            guard fraction > SettlementLight.dusk || fraction < SettlementLight.dawn,
                  fraction != SettlementLight.dusk, fraction != SettlementLight.dawn
            else { continue }
            #expect(SettlementLight.sun(time: at(fraction)).daylight == 0,
                    "the sun should be down at \(fraction)")
            #expect(SettlementRenderer.nightness(time: at(fraction)) > 0,
                    "sun down at \(fraction) and nothing darkened")
        }
    }

    // MARK: - The hour, readable

    @Test("The clock reads midnight at midnight and noon at noon")
    func theClockAgreesWithTheDay() {
        #expect(DayClock.clockText(at: at(0)) == "00:00")
        #expect(DayClock.clockText(at: at(0.5)) == "12:00")
        #expect(DayClock.clockText(at: at(0.75)) == "18:00")
        let (hour, _) = DayClock.hourAndMinute(at: at(0.25))
        #expect(hour == 6)
    }

    @Test("The clock and the canvas measure the same day")
    func oneClockForOneDay() {
        // Rule 35: the strip must not keep its own midnight. Both read the day
        // off the same epoch, so the same instant is the same hour in both.
        let now = Date()
        let mine = DayClock.fraction(at: DayClock.time(at: now))
        let canvas = (now.timeIntervalSince(DayClock.epoch) / AgentMotion.dayLength)
            .truncatingRemainder(dividingBy: 1)
        #expect(abs(mine - (canvas < 0 ? canvas + 1 : canvas)) < 1e-9)
    }

    @Test("The named part of the day follows the sun and the schedule")
    func phasesLineUpWithTheDay() {
        #expect(DayClock.phase(at: at(0.0), season: .summer) == .night)
        #expect(DayClock.phase(at: at(0.5), season: .summer) == .midday)
        #expect(DayClock.phase(at: at(0.85), season: .summer) == .night)
        // Just after sunset it is dusk, not night and not afternoon.
        #expect(DayClock.phase(at: at(SettlementLight.dusk + 0.01), season: .summer) == .dusk)
    }

    @Test("Both languages name every part of the day")
    func thePhasesAreBilingual() {
        for phase in [DayClock.Phase.night, .dawn, .morning, .midday, .afternoon, .dusk] {
            #expect(!phase.czech.isEmpty)
            #expect(!phase.english.isEmpty)
            #expect(phase.czech != phase.english, "\(phase) was never translated")
            #expect(!phase.symbol.isEmpty)
        }
    }

    // MARK: - What the town is doing

    @Test("At night the ones with nothing pressing are asleep, by day they are not")
    func theTallyReadsTheHour() {
        var s = Settlement(id: UUID(uuidString: "0D0C0000-0000-0000-0000-000000000001")!,
                           name: "Hold")
        for i in 0..<4 {
            var p = Pawn(id: UUID(uuidString: String(
                format: "0D0C0000-0000-0000-0000-%012d", i + 1))!, name: "Hand \(i)")
            p.age = 25 * 60
            s.pawns.append(p)
        }
        let night = DayClock.doing(s, at: at(0.0), season: .summer, language: .cs)
        #expect(night.contains { $0.what == "spí" && $0.count == 4 })
        let day = DayClock.doing(s, at: at(0.5), season: .summer, language: .cs)
        #expect(!day.contains { $0.what == "spí" })
    }

    @Test("Somebody carrying a load is counted as carrying it, night or not")
    func workOutranksTheHour() {
        var s = Settlement(id: UUID(uuidString: "0D0C0000-0000-0000-0000-000000000002")!,
                           name: "Hold")
        var p = Pawn(id: UUID(uuidString: "0D0C0000-0000-0000-0000-000000000010")!,
                     name: "Ondra")
        p.age = 25 * 60
        p.carrying = HaulLoad(itemID: "wood", amount: 3,
                              destination: LocalPoint(x: 0.5, y: 0.5))
        s.pawns = [p]
        let tally = DayClock.doing(s, at: at(0.0), season: .summer, language: .en)
        #expect(tally.contains { $0.what == "hauling" })
    }
}
