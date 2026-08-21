import Testing
import Foundation
@testable import EndlessFrontierCore

/// **Does a real colony ever actually build a road?**
///
/// `RoadTests` proves the system is reachable *in the API* — which rule 59 is
/// the reminder that this is not the same question. A sweep that sets the era,
/// grants the tech and fills the warehouse says the code works; it says nothing
/// about whether a colony left alone ever gets there, and the project's whole
/// history is systems that were correct and unreachable.
///
/// So this walks two centuries of a real world and prints what the map ended up
/// with: how much traffic went where, how many tracks the ground wore, what the
/// council paid to make, and how much of the journey the network actually saves.
/// If the answer is "no roads in two hundred years", the numbers to move are
/// `RoadEngine.trackThreshold`, `reserveMultiple` and `RoadGrade.cost` — and the
/// place to look first is whether anything is recording traffic at all.
///
/// ```
/// EF_PROBE=1 swift test --package-path Core --filter RoadProbe
/// ```
@Suite("The roads, measured", .enabled(
    if: ProcessInfo.processInfo.environment["EF_PROBE"] != nil,
    "a measuring instrument — set EF_PROBE=1 to run it"))
struct RoadProbe {

    @Test("Two hundred years of a colony that has somewhere to go")
    func theNetwork() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)

        // **Totals hid the answer twice.** Two rounds of tuning moved the sum
        // and changed nothing on the map, because a track is worn by traffic on
        // *one edge* and the sum says nothing about how it is spread. The
        // busiest single edge is the number the threshold has to be set
        // against, and `routes` says whether standing trade is even happening.
        print("year │ towns │ routes │ traffic │ busiest │ track road paved rail │ worst │ saved")
        for year in 1...200 {
            state = BalanceHarness.autoPlay(state, registry: registry)
            state = TickEngine.advance(state, ticks: 60, registry: registry).state
            guard year % 20 == 0 else { continue }

            let byGrade = Dictionary(grouping: state.roads.all, by: \.grade)
                .mapValues(\.count)
            let worst = state.roads.all.map(\.condition).min() ?? 1
            // No `%s`: it wants a C string, and handing it a Swift String is a
            // segfault rather than a warning. Interpolate the text instead.
            let counts = String(
                format: "%4d │ %5d │ %6d │ %7.1f │ %7.1f │ %5d %4d %5d %4d │ %5.2f │ ",
                year, state.settlements.count, state.tradeRoutes.count,
                state.roadTraffic.values.reduce(0, +),
                state.roadTraffic.values.max() ?? 0,
                byGrade[.track] ?? 0, byGrade[.road] ?? 0,
                byGrade[.paved] ?? 0, byGrade[.rail] ?? 0,
                worst)
            print(counts + saving(in: state))
        }

        // Not an assertion about *how many* — that is what the printout is for.
        // This one only says the mechanism was reached at all, because a probe
        // that silently measures nothing is the fault it exists to catch.
        #expect(!state.roadTraffic.isEmpty,
                "nobody recorded a journey in two hundred years — check that CaravanEngine.dispatch and the expeditions still call RoadEngine.travelled")
    }

    /// How much shorter the journey **between the two towns farthest apart** is
    /// because of roads, as a percentage. The number the whole system exists to
    /// move.
    ///
    /// The first cut measured the longest journey to any *explored region*,
    /// which is a hex of wilderness at the edge of the map that nothing has
    /// ever built a road toward — so it reported 5% and looked like a system
    /// doing nothing, while the roads between the towns were real and climbing
    /// the whole ladder. **Measure the thing the feature is for**: a metric
    /// aimed at the wrong journey is worse than no metric, because it argues
    /// convincingly for changing something that was right.
    private func saving(in state: WorldState) -> String {
        let byCoord = Dictionary(state.regions.map { ($0.coord, $0) }) { first, _ in first }
        let seats = state.settlements.compactMap { settlement -> HexCoord? in
            guard let id = settlement.regionID else { return nil }
            return state.regions.first { $0.id == id }?.coord
        }
        guard seats.count > 1 else { return "—" }
        var pair: (HexCoord, HexCoord)?
        var span = -1
        for (i, a) in seats.enumerated() {
            for b in seats.dropFirst(i + 1) where a.distance(to: b) > span {
                span = a.distance(to: b)
                pair = (a, b)
            }
        }
        guard let pair,
              let made = state.roads.route(from: pair.0, to: pair.1, regions: byCoord),
              let bare = RoadNetwork().route(from: pair.0, to: pair.1, regions: byCoord),
              bare.cost > 0
        else { return "—" }
        return String(format: "%.0f%%", (1 - made.cost / bare.cost) * 100)
    }
}
