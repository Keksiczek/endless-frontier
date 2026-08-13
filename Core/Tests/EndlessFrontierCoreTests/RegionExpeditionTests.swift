import Testing
import Foundation
@testable import EndlessFrontierCore

/// The last thing in the game that was still a button.
///
/// `SiteEngine.interact` took a region id and handed back an outcome in the
/// same tick: nobody went, nobody was gone, nobody could fail, and a lost city
/// three regions away cost exactly what one next door did.
@Suite("Out of the valley")
struct RegionExpeditionTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private func world(hexesAway: Int = 3, pop: Int = 20) -> WorldState {
        let homeRegion = Region(
            id: UUID(uuidString: "00000000-0000-0000-4E61-000000000001")!,
            name: "Home Vale", coord: HexCoord(0, 0), kind: .homeland,
            biomeID: "temperate", explorationState: .fullyExplored)
        let site = Region(
            id: UUID(uuidString: "00000000-0000-0000-4E61-000000000002")!,
            name: "The Dead Halls", coord: HexCoord(hexesAway, 0), kind: .ruins,
            biomeID: "temperate", hazardLevel: 3, explorationState: .fullyExplored)

        let pawns = (0..<pop).map { i -> Pawn in
            var pawn = Pawn(
                id: UUID(uuidString: String(format: "00000000-0000-0000-4E61-%012d", i + 10))!,
                name: "Walker \(i)")
            pawn.age = 27 * 60
            return pawn
        }
        var capital = Settlement(
            id: UUID(uuidString: "00000000-0000-0000-4E61-AAAAAAAAAAAA")!,
            name: "Home", kind: .capital, pawns: pawns,
            storage: [.food: 800], storageCapacity: .uniform(4000))
        capital.regionID = homeRegion.id
        return WorldState(tick: 0, mapSeed: 71, settlements: [capital],
                          regions: [homeRegion, site])
    }

    private func siteRegion(_ state: WorldState) -> UUID { state.regions[1].id }

    private func carry(_ state: WorldState, ticks: Int,
                       registry reg: GameDataRegistry) -> WorldState {
        var s = state
        for tick in 0..<ticks {
            s.tick = tick
            for step in 0..<WorldClock.actionStepsPerTick {
                s = RegionExpeditionEngine.advanceStep(
                    s, clock: WorldClock(tick: tick, step: step), registry: reg)
            }
        }
        return s
    }

    // MARK: - Going is a journey

    /// The property the whole thing exists for: distance costs time.
    @Test("A place across the map is further than one next door")
    func distanceCosts() throws {
        let reg = try registry()
        let near = try #require(RegionExpeditionEngine.dispatch(
            world(hexesAway: 1), settlementID: world().settlements[0].id,
            regionID: world(hexesAway: 1).regions[1].id, registry: reg))
        let far = try #require(RegionExpeditionEngine.dispatch(
            world(hexesAway: 6), settlementID: world().settlements[0].id,
            regionID: world(hexesAway: 6).regions[1].id, registry: reg))
        #expect(far.regionExpeditions[0].travelTicks
                > near.regionExpeditions[0].travelTicks * 3)
    }

    @Test("The hands that go are hands the colony has not got")
    func theyAreActuallyAway() throws {
        let reg = try registry()
        let start = world()
        let sent = try #require(RegionExpeditionEngine.dispatch(
            start, settlementID: start.settlements[0].id,
            regionID: siteRegion(start), registry: reg))
        let away = sent.settlements[0].pawns.count { $0.isAway }
        #expect(away > 0 && away <= RegionExpeditionEngine.partySize)
        // …and never so many that the colony is stripped bare.
        #expect(sent.settlements[0].pawns.count { !$0.isAway }
                >= RegionExpeditionEngine.keepAtHome)
    }

    @Test("Only one party at a time is on any one road")
    func oneAtATime() throws {
        let reg = try registry()
        let start = world()
        let sent = try #require(RegionExpeditionEngine.dispatch(
            start, settlementID: start.settlements[0].id,
            regionID: siteRegion(start), registry: reg))
        #expect(RegionExpeditionEngine.dispatch(
            sent, settlementID: start.settlements[0].id,
            regionID: siteRegion(start), registry: reg) == nil)
    }

    @Test("A colony with nobody to spare sends nobody")
    func nobodyToSpare() throws {
        let reg = try registry()
        let start = world(pop: 3)
        #expect(RegionExpeditionEngine.dispatch(
            start, settlementID: start.settlements[0].id,
            regionID: siteRegion(start), registry: reg) == nil)
    }

    // MARK: - There is something at the far end

    @Test("The place has things in it, and they are dealt with over time")
    func theSiteIsWorked() throws {
        let reg = try registry()
        let start = world(hexesAway: 1)
        var s = try #require(RegionExpeditionEngine.dispatch(
            start, settlementID: start.settlements[0].id,
            regionID: siteRegion(start), registry: reg))
        let travel = s.regionExpeditions[0].travelTicks

        s = carry(s, ticks: travel + 1, registry: reg)
        let site = try #require(s.regionExpeditions.first?.site)
        #expect(!site.things.isEmpty, "they walked a fortnight to an empty room")

        s = carry(s, ticks: travel + RegionExpeditionEngine.workTicks, registry: reg)
        let worked = try #require(s.regionExpeditions.first?.site)
        #expect(worked.progress > 0, "nothing at all happened in there")
    }

    @Test("They come home, the hands are free again, and the report lands")
    func theyComeHome() throws {
        let reg = try registry()
        let start = world(hexesAway: 1)
        var s = try #require(RegionExpeditionEngine.dispatch(
            start, settlementID: start.settlements[0].id,
            regionID: siteRegion(start), registry: reg))
        let total = s.regionExpeditions[0].totalTicks

        s = carry(s, ticks: total + 2, registry: reg)
        #expect(s.regionExpeditions.isEmpty, "nobody ever came back")
        #expect(s.settlements[0].pawns.allSatisfy { !$0.isAway })
        #expect(s.settlements[0].journal.entries.count >= 2,
                "setting out, and whatever they found")
    }

    /// The reason for the whole exercise: the reward is what they earned.
    @Test("A party driven out of a place brings back less than one that cleared it")
    func theHaulFollowsTheWork() throws {
        let reg = try registry()
        let start = world(hexesAway: 1)
        var s = try #require(RegionExpeditionEngine.dispatch(
            start, settlementID: start.settlements[0].id,
            regionID: siteRegion(start), registry: reg))
        let total = s.regionExpeditions[0].totalTicks
        let travel = s.regionExpeditions[0].travelTicks

        // One that gets on with it.
        let cleared = carry(s, ticks: total + 2, registry: reg)

        // …and one whose party is gone by the time it gets there.
        s = carry(s, ticks: travel + 1, registry: reg)
        for index in s.settlements[0].pawns.indices where s.settlements[0].pawns[index].isAway {
            s.settlements[0].pawns[index].health = 0
        }
        let driven = carry(s, ticks: total + 2, registry: reg)

        let earned = cleared.settlements[0].storage[.knowledge]
        let empty = driven.settlements[0].storage[.knowledge]
        #expect(earned > empty, "the place paid the same whether or not they got into it")
    }

    // MARK: - The invariants

    @Test("The same party, the same road, the same haul")
    func deterministic() throws {
        let reg = try registry()
        func run() throws -> WorldState {
            let start = world(hexesAway: 1)
            let sent = try #require(RegionExpeditionEngine.dispatch(
                start, settlementID: start.settlements[0].id,
                regionID: siteRegion(start), registry: reg))
            return carry(sent, ticks: sent.regionExpeditions[0].totalTicks + 2, registry: reg)
        }
        let a = try run(), b = try run()
        #expect(a.settlements[0].storage[.knowledge] == b.settlements[0].storage[.knowledge])
        #expect(a.settlements[0].pawns.map(\.health) == b.settlements[0].pawns.map(\.health))
    }

    @Test("A party on the road survives being written to disk")
    func survivesASave() throws {
        let reg = try registry()
        let start = world()
        let sent = try #require(RegionExpeditionEngine.dispatch(
            start, settlementID: start.settlements[0].id,
            regionID: siteRegion(start), registry: reg))
        let back = try JSONDecoder().decode(
            WorldState.self, from: try JSONEncoder().encode(sent))
        #expect(back.regionExpeditions == sent.regionExpeditions)
    }

    /// Rule 3: a world saved before anybody could leave the valley must load.
    @Test("A world saved before this existed still loads")
    func oldWorldsLoad() throws {
        var raw = try #require(try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(world())) as? [String: Any])
        raw.removeValue(forKey: "regionExpeditions")
        let old = try JSONDecoder().decode(
            WorldState.self, from: try JSONSerialization.data(withJSONObject: raw))
        #expect(old.regionExpeditions.isEmpty)
        #expect(old.regions.count == 2)
    }
}
