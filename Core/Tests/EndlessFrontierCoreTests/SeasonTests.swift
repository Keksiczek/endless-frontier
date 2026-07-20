import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Seasons & calendar")
struct SeasonTests {
    let config = WorldConfig.default   // ticksPerYear 60 → 15 ticks per season

    @Test("Ticks map onto the four seasons in order")
    func seasonBoundaries() {
        #expect(Season(tick: 0, ticksPerYear: 60) == .spring)
        #expect(Season(tick: 14, ticksPerYear: 60) == .spring)
        #expect(Season(tick: 15, ticksPerYear: 60) == .summer)
        #expect(Season(tick: 30, ticksPerYear: 60) == .autumn)
        #expect(Season(tick: 45, ticksPerYear: 60) == .winter)
        #expect(Season(tick: 59, ticksPerYear: 60) == .winter)
        #expect(Season(tick: 60, ticksPerYear: 60) == .spring)
    }

    @Test("Year counts completed calendar years")
    func yearCounting() {
        #expect(Season.year(tick: 0, ticksPerYear: 60) == 0)
        #expect(Season.year(tick: 59, ticksPerYear: 60) == 0)
        #expect(Season.year(tick: 60, ticksPerYear: 60) == 1)
        #expect(Season.year(tick: 600, ticksPerYear: 60) == 10)
    }

    @Test("Degenerate year length falls back to spring")
    func degenerateYearLength() {
        #expect(Season(tick: 42, ticksPerYear: 0) == .spring)
        #expect(Season.year(tick: 42, ticksPerYear: 0) == 0)
    }

    @Test("Seasonal multiplier follows the food table, others stay neutral")
    func seasonMultiplier() {
        #expect(config.seasonYieldMultiplier(for: .food, tick: 0) == 1.0)      // spring
        #expect(config.seasonYieldMultiplier(for: .food, tick: 20) == 1.5)     // summer
        #expect(config.seasonYieldMultiplier(for: .food, tick: 50) == 0.3)     // winter
        #expect(config.seasonYieldMultiplier(for: .materials, tick: 20) == 1.2)
        #expect(config.seasonYieldMultiplier(for: .knowledge, tick: 20) == 1.0)
    }

    @Test("Malformed season table is treated as neutral")
    func malformedTable() {
        var c = WorldConfig.default
        c.seasonFoodYield = [1.0, 2.0]
        #expect(c.seasonYieldMultiplier(for: .food, tick: 20) == 1.0)
    }

    @Test("Calendar section decodes from JSON and falls back when absent")
    func calendarDecoding() throws {
        let json = #"{"calendar": {"ticksPerYear": 120, "seasonFoodYield": [1, 2, 3, 4]}}"#
        let config = try JSONDecoder().decode(WorldConfig.self, from: Data(json.utf8))
        #expect(config.ticksPerYear == 120)
        #expect(config.seasonFoodYield == [1, 2, 3, 4])
        #expect(config.seasonMaterialsYield == WorldConfig.default.seasonMaterialsYield)

        let empty = try JSONDecoder().decode(WorldConfig.self, from: Data("{}".utf8))
        #expect(empty.ticksPerYear == WorldConfig.default.ticksPerYear)
    }

    @Test("Summer grows more food than winter for the same settlement")
    func seasonalProductionDiffers() {
        let registry = Fixtures.registry()
        let summerWorld = Fixtures.world(tick: 20)   // summer
        let winterWorld = Fixtures.world(tick: 50)   // winter

        let summerAfter = ResourceLoop.advanceOneTick(summerWorld, registry: registry)
        let winterAfter = ResourceLoop.advanceOneTick(winterWorld, registry: registry)

        let summerGain = summerAfter.settlements[0].storage[.food] - summerWorld.settlements[0].storage[.food]
        let winterGain = winterAfter.settlements[0].storage[.food] - winterWorld.settlements[0].storage[.food]
        #expect(summerGain > winterGain)
    }

    @Test("WorldState convenience helpers expose season and year")
    func worldStateHelpers() {
        let world = Fixtures.world(tick: 75)
        #expect(world.season(config) == .summer)
        #expect(world.year(config) == 1)
    }
}
