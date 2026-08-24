import Testing
import Foundation
@testable import EndlessFrontierCore

/// **What routing a walk costs**, measured rather than assumed.
///
/// `SettlementRoute` is an A\* run for every leg a colonist walks. It is
/// memoised in the app (`WalkRoutes`) and cheap on a hit, and the question this
/// pins is the *miss*: a town where nothing is cached yet, or one whose layout
/// just changed, pays the full search for every walker at once.
///
/// The shape being guarded is rule 38's, which has now bitten three times in
/// this file's neighbourhood — a per-frame loop containing something that
/// scales with content. This one is bounded by the search box rather than by
/// the town, and that is the property worth holding still.
@Suite("A walk costs what a walk costs")
struct RouteCostTests {

    static func town(_ buildings: Int, registry: GameDataRegistry) -> Settlement {
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-8A1C-f7695d4586ee")!,
                           name: "Wideacre", kind: .capital)
        s = ColonyBuilder.ensureMap(s)
        for _ in 0..<buildings {
            s = ColonyBuilder.placeSiteAtFirstFit(
                s, definitionID: "hut", registry: registry).settlement
        }
        return s
    }

    /// **The wall clock was tried here and taken out again.**
    ///
    /// Routing was measured at **4.4 ms a leg** with a linear frontier and
    /// **1.8 ms with the heap that replaced it** — a real 2.4× win, and the
    /// reason the heap is there. But every way of *asserting* it flaked: the
    /// same code came out at 1.8 ms alone, 2.6 with one other suite running and
    /// 3.9 with several, and taking a ratio against a straight line swung
    /// 409 → 696 for the same reason, because a straight line is a dozen
    /// integer steps and the measurement noise swamps it.
    ///
    /// A guard that trips on a loaded machine gets deleted, which costs more
    /// than it saves — the 150 ms layout budget next door has done exactly that
    /// twice this week. So what is pinned here is the *shape* instead: a route
    /// stays within a bounded detour of the straight line, which is what a
    /// search that has stopped exploring sensibly would break, and which is the
    /// same on any machine.
    @Test("A route is a detour, not an expedition")
    func routingStaysBounded() throws {
        let registry = try GameDataRegistry.bundled()
        let s = Self.town(60, registry: registry)
        let colony = try #require(s.colony)
        let ground = SettlementRoute.Ground(colony: colony, worn: [:])
        let lots = colony.placements
        #expect(lots.count > 20, "only \(lots.count) buildings — this measures nothing")

        var worst = 0.0
        var measured = 0
        for (i, a) in lots.enumerated() where measured < 120 {
            for b in lots.dropFirst(i + 1) where measured < 120 {
                let from = PathEngine.centre(of: a), to = PathEngine.centre(of: b)
                let straight = Double(abs(from.x - to.x) + abs(from.y - to.y))
                guard straight > 2 else { continue }
                let route = SettlementRoute.walk(from: from, to: to,
                                                 ground: ground, freeLots: [a, b])
                worst = max(worst, Double(route.count - 1) / straight)
                measured += 1
            }
        }
        #expect(measured > 20, "only \(measured) journeys were long enough to judge")
        // Four-neighbour routing round buildings: the straight line is already
        // Manhattan, so a detour of half again is a street going round things
        // and three times is a search that has lost the plot.
        #expect(worst < 3, "the longest route is \(worst)× its straight line")
    }

    @Test("A route is the same route every time it is asked for")
    func routingIsDeterministic() throws {
        let registry = try GameDataRegistry.bundled()
        let s = Self.town(30, registry: registry)
        let colony = try #require(s.colony)
        let ground = SettlementRoute.Ground(colony: colony, worn: [:])
        let lots = colony.placements
        let from = PathEngine.centre(of: lots[0])
        let to = PathEngine.centre(of: lots[lots.count - 1])
        let once = SettlementRoute.walk(from: from, to: to, ground: ground)
        let twice = SettlementRoute.walk(from: from, to: to, ground: ground)
        #expect(once == twice, "the same two ends gave two different streets")
        #expect(once.count > 1, "the route is a single tile")
    }

    @Test("A route goes round a building rather than through it")
    func routingAvoidsLots() throws {
        let registry = try GameDataRegistry.bundled()
        let s = Self.town(40, registry: registry)
        let colony = try #require(s.colony)
        let ground = SettlementRoute.Ground(colony: colony, worn: [:])
        let lots = colony.placements
        var crossed = 0, walked = 0
        for (i, a) in lots.enumerated() where i < 12 {
            for b in lots.dropFirst(i + 1).prefix(4) {
                let ends = [a, b]
                let route = SettlementRoute.walk(
                    from: PathEngine.centre(of: a), to: PathEngine.centre(of: b),
                    ground: ground, freeLots: ends)
                for tile in route {
                    walked += 1
                    // Somebody else's floor. The walker's own two lots are
                    // theirs to cross, which is why they are passed as free.
                    if colony.placements.contains(where: {
                        $0.id != a.id && $0.id != b.id && $0.covers(tile)
                    }) { crossed += 1 }
                }
            }
        }
        #expect(walked > 0)
        // Not zero: a lot walled in by its neighbours has to be reachable, and
        // `acrossWater`/`occupiedCost` are dear rather than forbidden on
        // purpose. A tenth is a street that goes round things.
        #expect(Double(crossed) / Double(walked) < 0.1,
                "\(crossed) of \(walked) steps were through somebody's building")
    }
}
