import Testing
import Foundation
@testable import EndlessFrontierCore

/// Reported from a real game: "there are POIs on the map with no interactions —
/// you can't do anything with them", and then: "the goal is to watch colonists
/// walk into a POI and do what's in it."
///
/// The first answer was a button that paid out instantly. That is still nobody
/// going anywhere: the ruins across the valley cost exactly what the spring next
/// door did, and the colony's hands were never missing from the fields. These
/// tests pin the expedition down — that the party is real people, that they are
/// gone while they are gone, and that the haul arrives with them and not before.
@Suite("Parties go out and work the land")
struct LocalPOIInteractionTests {
    private let seat = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!

    private var registry: GameDataRegistry { Fixtures.registry(buildings: []) }
    private var ticksPerYear: Int { registry.config.ticksPerYear }

    /// A colony with one discovered point of interest of the given kind.
    private func world(
        _ kind: LocalPOIKind, at position: LocalPoint = LocalPoint(x: 0.62, y: 0.5),
        tick: Int = 0, discovered: Bool = true, adults: Int = 8
    ) -> WorldState {
        var settlement = Settlement(id: seat, name: "Camp", pawns: [], storage: [.food: 900],
                                    storageCapacity: .uniform(2000))
        settlement.pawns = (0..<adults).map { i in
            var p = Pawn(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 700 + i))!,
                         name: "Soul \(i)", skills: [.mining: i, .research: i],
                         assignedWork: .mining, health: 70)
            p.age = 25 * ticksPerYear
            p.needs.recreation = 50
            return p
        }
        var map = LocalMapGenerator.generate(mapSeed: 11, regionID: seat,
                                             biome: Fixtures.defaultBiomes[0], registry: registry)
        map.pois = [LocalPOI(id: 1, kind: kind, position: position, discovered: discovered)]
        settlement.localMap = map
        return WorldState(tick: tick, settlements: [settlement])
    }

    private func dispatch(_ state: WorldState) -> WorldState {
        GameEngine.dispatchToPOI(state, settlementID: seat, poiID: 1, registry: registry)
    }

    /// Runs the expedition machinery alone, without the life cycle underneath.
    private func advance(_ state: WorldState, ticks: Int) -> WorldState {
        var s = state
        for _ in 0..<ticks {
            s.tick += 1
            s.settlements[0] = LocalPOIEngine.advanceOneTick(
                s.settlements[0], tick: s.tick, mapSeed: s.mapSeed, registry: registry)
        }
        return s
    }

    private func expedition(_ state: WorldState) -> POIExpedition? {
        state.settlements[0].expeditions.first
    }

    // MARK: - Setting out

    @Test("Ordering a visit sends named people, and pays nothing yet")
    func dispatchSendsPeople() {
        let before = world(.ruins)
        let after = dispatch(before)
        let party = try! #require(expedition(after))

        #expect(party.memberIDs.count == LocalPOIKind.ruins.partySize)
        #expect(after.settlements[0].storage[.knowledge] == before.settlements[0].storage[.knowledge],
                "the haul arrives with the party, not with the order")
        for id in party.memberIDs {
            let pawn = after.settlements[0].pawns.first { $0.id == id }
            #expect(pawn?.expeditionID == party.id)
            #expect(pawn?.isAway == true)
        }
        #expect(after.settlements[0].journal.entries.count == 1, "the colony notes them leaving")
    }

    @Test("The party is picked for the trade the place asks for")
    func partySuitsTheWork() {
        let after = dispatch(world(.cave))
        let party = try! #require(expedition(after))
        let chosen = after.settlements[0].pawns.filter { party.memberIDs.contains($0.id) }
        let left = after.settlements[0].pawns.filter { !party.memberIDs.contains($0.id) }
        let worstChosen = chosen.map { $0.skill(.mining) }.min() ?? 0
        let bestLeft = left.map { $0.skill(.mining) }.max() ?? 0
        #expect(worstChosen >= bestLeft, "the best miners go down the cave")
    }

    @Test("A colonist out at the site does not also work the colony")
    func awayHandsAreMissing() {
        // Same colony, same span — the only difference is that some of them left.
        let home = TickEngine.advance(world(.cave), ticks: 4, registry: registry).state
        let sent = TickEngine.advance(dispatch(world(.cave)), ticks: 4, registry: registry).state
        #expect(sent.settlements[0].storage[.materials] < home.settlements[0].storage[.materials],
                "an expedition that costs the colony nothing is not a decision")
    }

    @Test("Undiscovered ground cannot be worked")
    func undiscoveredIsInert() {
        let after = dispatch(world(.ruins, discovered: false))
        #expect(after.settlements[0].expeditions.isEmpty)
    }

    @Test("Two parties cannot be sent to the same place")
    func noDoubleDispatch() {
        let once = dispatch(world(.ruins))
        let twice = dispatch(once)
        #expect(twice.settlements[0].expeditions.count == 1)
    }

    @Test("A colony too small to spare anyone sends nobody")
    func neverStripsTheColonyBare() {
        let after = dispatch(world(.cave, adults: 2))
        #expect(after.settlements[0].expeditions.isEmpty,
                "a colony of two does not send both of them down a cave")
    }

    // MARK: - The journey

    @Test("A far place is a longer walk than a near one")
    func travelScalesWithDistance() {
        let near = LocalPOIEngine.travelTicks(to: LocalPoint(x: 0.55, y: 0.5))
        let far = LocalPOIEngine.travelTicks(to: LocalPoint(x: 0.95, y: 0.95))
        #expect(far > near)
        #expect(near >= 1, "even next door takes a tick — nothing is instant")
    }

    @Test("The party walks out, works, walks home — in that order")
    func phasesRunInOrder() {
        let state = dispatch(world(.ruins))
        let party = try! #require(expedition(state))
        // Asked on the action grid the world actually runs on — one clock,
        // one vocabulary.
        func clock(_ ticksAfterDeparture: Int) -> WorldClock {
            WorldClock(tick: party.departedTick + ticksAfterDeparture, step: 0)
        }
        #expect(party.phase(at: clock(0)) == .outbound)
        #expect(party.phase(at: clock(party.travelTicks)) == .working)
        #expect(party.phase(at: clock(party.travelTicks + party.workTicks)) == .returning)
        #expect(party.phase(at: clock(party.totalTicks)) == nil)
    }

    @Test("The haul lands when they walk back in, and not a tick before")
    func rewardArrivesOnReturn() {
        let state = dispatch(world(.ruins))
        let party = try! #require(expedition(state))
        let before = state.settlements[0].storage[.knowledge]

        let midway = advance(state, ticks: party.totalTicks - 1)
        #expect(midway.settlements[0].storage[.knowledge] == before, "still out there")

        let home = advance(state, ticks: party.totalTicks)
        #expect(home.settlements[0].storage[.knowledge] > before)
        #expect(home.settlements[0].expeditions.isEmpty, "the party is off the books")
        #expect(home.settlements[0].pawns.allSatisfy { !$0.isAway }, "and back on the colony's")
        #expect(home.settlements[0].localMap!.pois[0].visits == 1)
    }

    @Test("A finished trip is wired into the real tick loop, not just the engine")
    func integratesWithTickEngine() {
        let state = dispatch(world(.treasure))
        let party = try! #require(expedition(state))
        let before = state.settlements[0].storage[.materials]

        let after = TickEngine.advance(state, ticks: party.totalTicks + 1, registry: registry).state
        #expect(after.settlements[0].expeditions.isEmpty)
        #expect(after.settlements[0].storage[.materials] > before)
    }

    // MARK: - What the places hold

    @Test("Every kind pays the colony something for the walk", arguments: LocalPOIKind.allCases)
    func everyKindPays(kind: LocalPOIKind) {
        let state = dispatch(world(kind))
        let party = try! #require(expedition(state))
        let home = advance(state, ticks: party.totalTicks)

        let gained = ResourceType.allCases.contains {
            home.settlements[0].storage[$0] > state.settlements[0].storage[$0]
        }
        let healed = home.settlements[0].pawns.first!.health > state.settlements[0].pawns.first!.health
        let rested = home.settlements[0].pawns.first!.needs.recreation
            > state.settlements[0].pawns.first!.needs.recreation
        #expect(gained || healed || rested, "working a place must be worth the walk")
        // Setting out, what they found in there, and coming back. The middle
        // line is the point of the place having anything in it at all.
        #expect(home.settlements[0].journal.entries.count >= 2,
                "setting out, and coming back")
    }

    @Test("A finite place is picked clean and then refuses more parties", arguments: [
        LocalPOIKind.treasure, .ruins, .wreck
    ])
    func finitePlacesExhaust(kind: LocalPOIKind) {
        var state = world(kind)
        for visit in 1...kind.maxVisits {
            state = dispatch(state)
            let party = try! #require(expedition(state), "visit \(visit) should be dispatchable")
            state = advance(state, ticks: party.totalTicks)
        }
        #expect(state.settlements[0].localMap!.pois[0].isExhausted)
        state = dispatch(state)
        #expect(state.settlements[0].expeditions.isEmpty,
                "\(kind) should be picked clean after \(kind.maxVisits) runs")
    }

    @Test("Each return trip to a finite place yields less")
    func returnsDiminish() {
        var state = world(.wreck)
        var hauls: [Double] = []
        for _ in 1...2 {
            let before = state.settlements[0].storage[.materials]
            state = dispatch(state)
            let party = try! #require(expedition(state))
            state = advance(state, ticks: party.totalTicks)
            hauls.append(state.settlements[0].storage[.materials] - before)
        }
        #expect(hauls[1] < hauls[0], "the easy pickings go first")
        #expect(hauls[1] > 0)
    }

    @Test("A spring does not run dry, but it does need to rest")
    func renewableRespectsCooldown() {
        var state = dispatch(world(.spring))
        let party = try! #require(expedition(state))
        state = advance(state, ticks: party.totalTicks)
        #expect(!state.settlements[0].localMap!.pois[0].isExhausted)

        let tooSoon = dispatch(state)
        #expect(tooSoon.settlements[0].expeditions.isEmpty, "straight back the next day: nothing doing")

        var later = state
        later.tick += LocalPOIKind.spring.cooldownYears * ticksPerYear
        #expect(!dispatch(later).settlements[0].expeditions.isEmpty,
                "after its cooldown a renewable place gives again")
    }

    // MARK: - What it costs

    @Test("When a cave falls in, it falls on someone who actually went")
    func hazardHitsThePartyNotABystander() {
        // Across many departures the roof comes down at least once; whoever it
        // lands on must be one of the people who walked out.
        var sawCasualty = false
        for tick in stride(from: 0, to: 3000, by: 30) {
            let state = dispatch(world(.cave, tick: tick))
            guard let party = expedition(state) else { continue }
            let after = advance(state, ticks: party.travelTicks + 1)
            guard let hurt = after.settlements[0].expeditions.first?.casualtyID else { continue }
            sawCasualty = true
            #expect(party.memberIDs.contains(hurt),
                    "the roof cannot fall on someone who stayed home")
            break
        }
        #expect(sawCasualty, "a cave with no risk is a vending machine, not a cave")
    }

    /// The hard invariant of this codebase: same seed and inputs, same world.
    @Test("Expeditions are deterministic for a seed and tick")
    func deterministic() {
        func run() -> WorldState {
            let state = dispatch(world(.cave, tick: 240))
            let party = expedition(state)!
            return advance(state, ticks: party.totalTicks)
        }
        let a = run(), b = run()
        #expect(a.settlements[0].storage[.materials] == b.settlements[0].storage[.materials])
        #expect(a.settlements[0].pawns.map(\.health) == b.settlements[0].pawns.map(\.health))
        #expect(a.settlements[0].pawns.count == b.settlements[0].pawns.count)
    }

    // MARK: - Saves

    @Test("Old saves decode without visit state or expeditions")
    func decodesLegacyPOI() throws {
        let legacy = """
        {"id":3,"kind":"ruins","position":{"x":0.4,"y":0.6},"discovered":true}
        """.data(using: .utf8)!
        let poi = try JSONDecoder().decode(LocalPOI.self, from: legacy)
        #expect(poi.visits == 0)
        #expect(poi.lastVisitTick == nil)
        #expect(poi.isWorkable(tick: 0, ticksPerYear: 60))
    }

    @Test("A colonist saved before expeditions existed comes back home, not away")
    func decodesLegacyPawn() throws {
        // Written by round-tripping a real pawn and dropping the new key, so the
        // fixture cannot drift away from what the encoder actually emits.
        var pawn = Pawn(name: "Old", assignedWork: .farming)
        pawn.expeditionID = UUID()
        let encoded = try JSONEncoder().encode(pawn)
        var fields = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        fields.removeValue(forKey: "expeditionID")
        let legacy = try JSONSerialization.data(withJSONObject: fields)

        let restored = try JSONDecoder().decode(Pawn.self, from: legacy)
        #expect(restored.expeditionID == nil)
        #expect(!restored.isAway)
    }

    @Test("A party survives a save and reload mid-journey")
    func expeditionRoundTrips() throws {
        let state = dispatch(world(.ruins))
        let data = try JSONEncoder().encode(state)
        let back = try JSONDecoder().decode(WorldState.self, from: data)
        let original = try #require(expedition(state))
        let restored = try #require(back.settlements[0].expeditions.first)
        #expect(restored == original)
        #expect(back.settlements[0].pawns.filter(\.isAway).count == original.memberIDs.count)
    }
}
