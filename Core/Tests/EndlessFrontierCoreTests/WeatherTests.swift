import Testing
import Foundation
@testable import EndlessFrontierCore

/// The weather, which used to be four constants.
///
/// `Climate.base(season) + shift` meant every spring in a colony's life was
/// exactly 11°. Consistent, and not weather. What these pin is the pair of ways
/// the fix can be worthless: a wander so small nothing downstream ever notices
/// it (rule 6 — a rate that cannot reach the threshold it is aimed at), and one
/// so large the seasons stop meaning anything.
@Suite("The weather is alive")
struct WeatherTests {

    private func climate(shift: Double = 0, tick: Int, seed: UInt64 = 4242) -> Climate {
        Climate(shift: shift, mapSeed: seed, tick: tick, ticksPerYear: 60)
    }

    /// Every temperature a plains colony actually sees across two centuries.
    private func plainsYear(_ season: Season, seed: UInt64 = 4242) -> [Double] {
        (0..<12_000).compactMap { tick in
            guard Season(tick: tick, ticksPerYear: 60) == season else { return nil }
            return climate(tick: tick, seed: seed).temperature(season)
        }
    }

    // MARK: - It is weather at all

    @Test("Two springs in a colony's life are not the same temperature")
    func springsDiffer() {
        let springs = Set(plainsYear(.spring).map { ($0 * 10).rounded() })
        #expect(springs.count > 50, "only \(springs.count) distinct spring temperatures in 200 years")
    }

    @Test("A year is harder or milder as a whole, not tick by tick")
    func aYearHasACharacter() {
        // The mean of one year against the mean of another: if the only wander
        // were per-tick noise these would be the same to within nothing.
        func meanYear(_ year: Int) -> Double {
            let ticks = (year * 60)..<((year + 1) * 60)
            let all = ticks.map { climate(tick: $0)
                .temperature(Season(tick: $0, ticksPerYear: 60)) }
            return all.reduce(0, +) / Double(all.count)
        }
        let means = (0..<40).map(meanYear)
        let spread = (means.max() ?? 0) - (means.min() ?? 0)
        #expect(spread > 3, "every year averaged the same to within \(spread)°")
    }

    @Test("The sky changes rather than jumps")
    func weatherComesInSpells() {
        // Neighbouring ticks inside a season must not swing wildly, or the
        // thermometer reads as broken rather than as weather.
        var worst = 0.0
        for tick in 1..<2_000 {
            let season = Season(tick: tick, ticksPerYear: 60)
            guard Season(tick: tick - 1, ticksPerYear: 60) == season else { continue }
            worst = max(worst, abs(climate(tick: tick).temperature(season)
                                   - climate(tick: tick - 1).temperature(season)))
        }
        #expect(worst < Climate.spellSwing, "the sky jumped \(worst)° in one tick")
    }

    @Test("Some years are the ones people talk about")
    func hardYearsHappen() {
        let winters = plainsYear(.winter)
        let ordinary = Climate.base(.winter)
        #expect(winters.contains { $0 < ordinary - Climate.yearSwing - 2 },
                "two centuries and never a winter worth remembering")
    }

    // MARK: - …and it reaches the things that read it

    /// Rule 6, and the whole point of doing this at all. A wander nothing
    /// downstream can feel is a decorative number.
    @Test("A bad year is bad enough to hurt a harvest")
    func weatherReachesTheCrops() {
        // Grain's floor is 0° and spring is 11°, so a hard spring has to be
        // able to actually slow the fields.
        let slowed = (0..<12_000).contains { tick in
            guard Season(tick: tick, ticksPerYear: 60) == .spring else { return false }
            let t = climate(tick: tick).temperature(.spring)
            return FarmEngine.growthStep(.grain, season: .spring, temperature: t)
                < FarmEngine.growthStep(.grain, season: .spring,
                                        temperature: Climate.base(.spring))
        }
        #expect(slowed, "no spring in two centuries was cold enough to slow the grain")
    }

    @Test("…and the seasons still outrank it")
    func seasonsStillDominate() {
        let summers = plainsYear(.summer)
        let winters = plainsYear(.winter)
        #expect((winters.max() ?? 0) < (summers.min() ?? 0),
                "the mildest winter was warmer than the harshest summer")
    }

    // MARK: - The rules that must not break

    /// The bug the spell test caught the long way round: `wobble` shifts a
    /// **53**-bit value and a first cut divided it by 2^52, so it returned
    /// −1…3 rather than −1…1 and every swing in this file ran to three times
    /// the number written beside it. A generator whose range is wrong makes
    /// every constant that reads it a lie, so the range is asserted directly.
    @Test("The noise really is between minus one and one")
    func wobbleStaysInRange() {
        for i in 0..<200_000 {
            let v = Climate.wobble(Climate.mix(4242, UInt64(i), 0x5350454C))
            #expect(v >= -1 && v <= 1, "wobble(\(i)) = \(v)")
        }
    }

    @Test("A swing never exceeds the number written next to it")
    func swingsRespectTheirBounds() {
        let ceiling = Climate.yearSwing + Climate.spellSwing + Climate.hardYearSwing
        for tick in 0..<12_000 {
            let season = Season(tick: tick, ticksPerYear: 60)
            #expect(abs(climate(tick: tick).weather(season)) <= ceiling)
        }
    }

    @Test("The same world has the same weather every time it is replayed")
    func weatherIsDeterministic() {
        #expect(plainsYear(.autumn) == plainsYear(.autumn))
        #expect(plainsYear(.autumn) != plainsYear(.autumn, seed: 99),
                "two different worlds had identical weather")
    }

    /// A climate with no world behind it is the ordinary run of things — which
    /// is what every *sowing* decision has to see. What a farm plants is a
    /// judgement about the country it stands in, not about this fortnight.
    @Test("A climate with no world behind it has no weather")
    func theAverageYearIsStillAvailable() {
        for season in Season.allCases {
            #expect(Climate.temperate.temperature(season) == Climate.base(season))
            #expect(Climate(shift: -9).temperature(season) == Climate.base(season) - 9)
        }
    }

    @Test("The country still decides more than the day does")
    func biomeOutranksWeather() {
        // A tundra valley must stay colder than a plains one, whatever kind of
        // year each of them is having.
        for tick in stride(from: 0, to: 12_000, by: 37) {
            let season = Season(tick: tick, ticksPerYear: 60)
            let tundra = climate(shift: -13, tick: tick).temperature(season)
            let plains = climate(shift: 0, tick: tick).temperature(season)
            #expect(tundra < plains)
        }
    }
}
