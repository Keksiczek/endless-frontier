import Testing
import Foundation
import EndlessFrontierCore
@testable import EndlessFrontier

/// §11.30 — **the game makes no sound at all**, closed.
///
/// The sound itself cannot be tested (it is a render callback on an audio
/// thread, and whether wind sounds like wind is a judgement nobody can make in
/// an assertion). What *can* be tested is the whole of the decision: the mapping
/// from the world to the mix is a pure function, and every complaint anybody
/// will ever have about the ambience — "why are there crickets in January", "why
/// is the village loud at three in the morning" — is a statement about it.
@Suite("What the valley sounds like")
struct SoundscapeTests {

    private func world(
        season: Season = .summer, temperature: Double = 18, weather: Double = 0,
        night: Double = 0, population: Int = 20, awake: Int = 20,
        underAttack: Bool = false, hearths: Int = 1
    ) -> Soundscape.World {
        Soundscape.World(
            season: season, temperature: temperature, weather: weather, night: night,
            population: population, awake: awake, underAttack: underAttack,
            hearths: hearths)
    }

    // MARK: - Weather

    @Test("The wind rises with the cold and with a hard spell")
    func windFollowsTheSky() {
        let mild = Soundscape.mix(world(temperature: 20))
        let cold = Soundscape.mix(world(season: .winter, temperature: -8))
        let gale = Soundscape.mix(world(temperature: 20, weather: -5))
        #expect(cold.wind > mild.wind)
        #expect(gale.wind > mild.wind)
        #expect(mild.wind > 0, "a valley is never perfectly still")
    }

    @Test("It rains when the sky has actually turned, and not before")
    func rainNeedsWeather() {
        #expect(Soundscape.mix(world(weather: 0)).rain == 0)
        #expect(Soundscape.mix(world(weather: -1)).rain == 0, "grey is not wet")
        #expect(Soundscape.mix(world(weather: -4)).rain > 0)
    }

    /// Snow is the quiet one, and everybody knows it without being told.
    @Test("A downpour is loud; the same sky below freezing is not")
    func snowIsQuiet() {
        let rain = Soundscape.mix(world(temperature: 8, weather: -5)).rain
        let snow = Soundscape.mix(world(temperature: -4, weather: -5)).rain
        #expect(snow < rain / 3)
    }

    // MARK: - The hour

    @Test("Crickets are a summer night and nothing else")
    func cricketsKnowTheSeason() {
        #expect(Soundscape.mix(world(night: 1)).crickets > 0)
        #expect(Soundscape.mix(world(night: 0)).crickets == 0, "not at noon")
        #expect(Soundscape.mix(world(season: .winter, temperature: -2, night: 1)).crickets == 0)
        #expect(Soundscape.mix(world(temperature: 5, night: 1)).crickets == 0, "too cold")
    }

    @Test("A sleeping village is quieter than a working one, and not silent")
    func nightHushesTheVillage() {
        let day = Soundscape.mix(world(night: 0, population: 30, awake: 30))
        let night = Soundscape.mix(world(night: 1, population: 30, awake: 2))
        #expect(night.village < day.village / 2)
        #expect(night.village > 0, "thirty people breathing is not nothing")
    }

    @Test("A fire is the thing still making a noise at three in the morning")
    func theFireOutlastsTheDay() {
        let night = Soundscape.mix(world(night: 1, awake: 1, hearths: 3))
        #expect(night.fire > night.village)
    }

    // MARK: - Size

    @Test("A bigger colony is louder, up to a point")
    func theVillageGrowsLouder() {
        let hamlet = Soundscape.mix(world(population: 8, awake: 8))
        let town = Soundscape.mix(world(population: 40, awake: 40))
        let city = Soundscape.mix(world(population: 400, awake: 400))
        #expect(town.village > hamlet.village)
        #expect(city.village <= 1, "gains are gains, not tallies")
        #expect(city.village >= town.village)
    }

    // MARK: - A raid

    @Test("A raid takes the village over")
    func fightingSilencesTheChatter() {
        let calm = Soundscape.mix(world(population: 40, awake: 40))
        let raid = Soundscape.mix(world(population: 40, awake: 40, underAttack: true))
        #expect(raid.village < calm.village)
        #expect(Soundscape.mix(world(night: 1, underAttack: true)).crickets == 0,
                "nothing is chirping through that")
    }

    // MARK: - Stings

    /// Deliberately few: a sound for every journal line is a game that gets
    /// muted, which is worse than silence.
    @Test("Only news worth a sound makes one")
    func stingsAreRare() {
        #expect(Sting.of(.construction) == .hammer)
        #expect(Sting.of(.danger) == .horn)
        #expect(Sting.of(.death) == .knell)
        #expect(Sting.of(.birth) == .chime)
        #expect(Sting.of(.social) == nil)
        #expect(Sting.of(.work) == nil)
        #expect(Sting.of(nil) == nil)
    }

    @Test("Every gain the mixer is handed is a gain")
    func nothingEverLeavesTheRange() {
        for season in Season.allCases {
            for temperature in stride(from: -30.0, through: 45, by: 5) {
                for weather in stride(from: -8.0, through: 8, by: 2) {
                    for night in [0.0, 0.5, 1.0] {
                        let mix = Soundscape.mix(world(
                            season: season, temperature: temperature, weather: weather,
                            night: night, population: 200, awake: 120, hearths: 9))
                        for gain in [mix.wind, mix.rain, mix.crickets, mix.village, mix.fire] {
                            #expect(gain >= 0 && gain <= 1,
                                    "\(season) \(temperature)° \(weather) → \(gain)")
                        }
                    }
                }
            }
        }
    }
}
