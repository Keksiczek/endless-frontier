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

/// The moon, and the night it makes.
///
/// Keks, after dark: *"noc je dost tmavá a jednotvárná, možná přidat fáze
/// měsíce."* Both halves are one fault — every night was exactly as dark as
/// every other one, because the only input was how far past sunset the clock
/// stood. These pin the cycle and, more importantly, that it **reaches the
/// picture**: a full moon night has to be visibly lighter than a new moon one,
/// or the phase is a label on a status bar and nothing else.
@Suite("The moon")
struct MoonTests {

    private func day(_ n: Double) -> Double { AgentMotion.dayLength * n }

    @Test("New at the start of the cycle, full in the middle of it")
    func theCycleRunsNewToFull() {
        #expect(MoonPhase.illumination(at: day(0)) < 0.01)
        #expect(MoonPhase.illumination(at: day(MoonPhase.synodicDays / 2)) > 0.99)
        #expect(MoonPhase.illumination(at: day(MoonPhase.synodicDays)) < 0.01,
                "and it comes back round")
    }

    @Test("The quarters are half lit")
    func quartersAreHalfLit() {
        let quarter = MoonPhase.illumination(at: day(MoonPhase.synodicDays / 4))
        #expect(abs(quarter - 0.5) < 0.01)
    }

    @Test("Every phase is named in both languages and carries a symbol")
    func phasesAreNamedAndDrawn() {
        for phase in MoonPhase.Phase.allCases {
            #expect(!phase.czech.isEmpty)
            #expect(!phase.english.isEmpty)
            #expect(phase.czech != phase.english, "\(phase) was never translated")
            #expect(phase.symbol.hasPrefix("moonphase."))
        }
    }

    @Test("The named phase follows the cycle, and the whole set turns up")
    func everyPhaseHappens() {
        var seen: Set<String> = []
        for step in 0..<300 {
            let t = day(Double(step) * MoonPhase.synodicDays / 300)
            seen.insert(MoonPhase.phase(at: t).english)
        }
        #expect(seen.count == MoonPhase.Phase.allCases.count)
        #expect(MoonPhase.phase(at: day(0)) == .new)
        #expect(MoonPhase.phase(at: day(MoonPhase.synodicDays / 2)) == .full)
    }

    // MARK: - …and it has to reach the picture

    /// The point of the whole thing: a full moon night is **markedly** lighter
    /// than a new moon one. If this ever stops being true the phase is a label
    /// and the night is monotonous again.
    @Test("A full moon night is lighter than a new moon night")
    func theMoonChangesHowDarkItGets() {
        let dark = SettlementRenderer.darkness(moonlight: 0)
        let lit = SettlementRenderer.darkness(moonlight: 1)
        #expect(lit < dark)
        #expect(dark - lit > 0.2, "a difference nobody can see is not a difference")
        #expect(lit > 0.25, "…and a full moon is still night")
    }

    @Test("Cloud puts the moon out")
    func stormyNightsAreTheDarkest() {
        let full = day(MoonPhase.synodicDays / 2)
        let clear = MoonPhase.moonlight(at: full, weather: 0)
        let storm = MoonPhase.moonlight(at: full, weather: -6)
        #expect(clear > 0.9)
        #expect(storm < clear / 3, "a full moon behind a storm lights nothing")
    }

    @Test("A thin crescent is worth almost nothing")
    func crescentsAreNearlyDark() {
        let crescent = MoonPhase.moonlight(at: day(MoonPhase.synodicDays * 0.08), weather: 0)
        #expect(crescent < 0.15)
    }
}
