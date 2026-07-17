import Testing
import Foundation
@testable import EndlessFrontierCore

/// Reported: a region card showing "Far Blackwood · Wilderness · Mountains ·
/// hazard 7" — details the UI only renders for a *charted* region — with a Send
/// Expedition button, which it only offers for an *uncharted* one. One card
/// cannot be both, and the region wasn't even in the report's "in reach" list.
///
/// The only way both can be true at once is if two regions share an `id`: the
/// card resolves `first { $0.id == selected }` to the charted one, while
/// `canExplore` matches the same id against an uncharted one in
/// `exploreableRegions`. Tapping then calls `startExpedition`, which correctly
/// refuses (it re-checks `.unknown` on the real target) — so the button sits
/// there doing nothing forever.
@Suite("Every region is its own place")
struct RegionIdentityTests {
    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    /// Ids are what every lookup in the game keys on. Two places sharing one is
    /// not a cosmetic problem — it silently crosses the wires between them.
    @Test("A swept map has no two regions sharing an id")
    func idsAreUniqueAcrossTheMap() throws {
        let reg = try registry()
        var byID: [UUID: HexCoord] = [:]
        var clashes: [(UUID, HexCoord, HexCoord)] = []

        for q in -10...10 {
            for r in -10...10 {
                let coord = HexCoord(q, r)
                guard coord.distance(to: .origin) <= 10 else { continue }
                let region = MapGenerator.region(at: coord, mapSeed: 1_592_651_789, registry: reg)
                if let seen = byID[region.id], seen != coord {
                    clashes.append((region.id, seen, coord))
                }
                byID[region.id] = coord
            }
        }
        #expect(clashes.isEmpty, "two places sharing an id cross every lookup between them: \(clashes.prefix(3))")
    }

    /// The world the player actually holds, grown the way play grows it.
    @Test("A world that has been played has no duplicate region ids")
    func playedWorldKeepsIdsUnique() throws {
        let reg = try registry()
        var world = GameWorldFactory.newGame(registry: reg, seed: 1_592_651_789)
        for _ in 0..<40 {
            world = BalanceHarness.autoPlay(world, registry: reg)
            world = TickEngine.advance(world, ticks: 50, registry: reg).state
        }
        let ids = world.regions.map(\.id)
        #expect(Set(ids).count == ids.count,
                "\(ids.count - Set(ids).count) duplicate id(s) among \(ids.count) regions")
    }

    @Test("No two regions occupy the same hex")
    func coordsAreUnique() throws {
        let reg = try registry()
        var world = GameWorldFactory.newGame(registry: reg, seed: 1_592_651_789)
        for _ in 0..<40 {
            world = TickEngine.advance(world, ticks: 50, registry: reg).state
        }
        let coords = world.regions.map(\.coord)
        #expect(Set(coords).count == coords.count)
    }

    /// The invariant the bug actually broke: what the card shows and what the
    /// button offers must agree, because both key off the same id.
    @Test("A charted region is never offered as explorable")
    func chartedRegionsAreNotExplorable() throws {
        let reg = try registry()
        var world = GameWorldFactory.newGame(registry: reg, seed: 1_592_651_789)
        for _ in 0..<40 {
            world = TickEngine.advance(world, ticks: 50, registry: reg).state
        }
        let reachableIDs = Set(ExplorationEngine.exploreableRegions(world).map(\.id))
        for region in world.regions where region.explorationState != .unknown {
            #expect(!reachableIDs.contains(region.id),
                    "\(region.name) is charted, yet its id is offered for an expedition")
        }
    }
}
